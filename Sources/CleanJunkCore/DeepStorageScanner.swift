import Darwin
import Foundation

/// Iterates actual directory entries (including hidden files and app bundle contents).
/// The index stores metadata only: no file content, hashing or user documents are read.
/// Traversal does not follow symbolic links, and failure to access a path is reported.
public actor DeepStorageScanner {
    private let fileManager = FileManager()
    private let databaseURL: URL
    private let maxEntries: Int64
    private let maxDuration: TimeInterval

    public init(databaseURL: URL = DeepScanIndex.defaultDatabaseURL,
                maxEntries: Int64 = 10_000_000,
                maxDuration: TimeInterval = 1_800) {
        self.databaseURL = databaseURL
        self.maxEntries = max(1, maxEntries)
        self.maxDuration = max(1, maxDuration)
    }

    public func scan(roots requestedRoots: [URL] = [URL(fileURLWithPath: "/")],
                     home: URL = FileManager.default.homeDirectoryForCurrentUser,
                     progress: @Sendable (DeepScanProgress) async -> Void = { _ in }) async throws -> DeepScanSummary {
        let start = Date()
        let homePath = home.standardizedFileURL.resolvingSymlinksInPath().path
        var roots: [URL] = []

        for requested in requestedRoots {
            let root = requested.standardizedFileURL
            var metadata = stat()
            guard root.path.hasPrefix("/"),
                  lstat(root.path, &metadata) == 0,
                  (UInt32(metadata.st_mode) & UInt32(S_IFMT)) == UInt32(S_IFDIR),
                  root.resolvingSymlinksInPath() == root else {
                throw DeepScanError.invalidRoot
            }
            if roots.contains(where: { DeepStorageClassifier.isDescendant(root.path, of: $0.path) }) { continue }
            roots.removeAll { DeepStorageClassifier.isDescendant($0.path, of: root.path) }
            roots.append(root)
        }
        guard !roots.isEmpty else { throw DeepScanError.invalidRoot }

        let parent = databaseURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
        // Scan results include private paths: restrict directory and database permissions.
        _ = chmod(parent.path, 0o700)
        let freeAtStart = (try? fileManager.attributesOfFileSystem(forPath: parent.path)[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
        if freeAtStart > 0 && freeAtStart < 512 * 1_024 * 1_024 {
            throw DeepScanError.insufficientSpace
        }
        let pending = parent.appendingPathComponent(".deep-storage-" + UUID().uuidString + ".sqlite")
        var didInstall = false
        var db: DeepScanDatabase? = try DeepScanDatabase(url: pending, create: true)
        defer {
            db = nil
            if !didInstall { try? fileManager.removeItem(at: pending) }
        }

        var examined: Int64 = 0
        var files: Int64 = 0
        var directories: Int64 = 0
        var links: Int64 = 0
        var allocated: Int64 = 0
        var rebuildable: Int64 = 0
        var duplicateHardlinks: Int64 = 0
        var inaccessible: Int64 = 0
        var warnings: [String] = []
        var hitLimit = false
        var visitedDirectories = Set<FileIdentity>()
        var seenHardlinks = Set<FileIdentity>()
        let ownDataRoot = parent.standardizedFileURL.path
        var transactionEntries = 0

        func warn(_ path: URL, _ reason: String) {
            inaccessible += 1
            if warnings.count < 100 {
                warnings.append(path.path + " — " + reason)
            }
        }

        try db?.execute("BEGIN IMMEDIATE")
        for root in roots {
            try Task.checkCancellation()
            if let identity = FileIdentity.capture(at: root) {
                visitedDirectories.insert(identity)
            }
            guard let enumerator = fileManager.enumerator(
                at: root, includingPropertiesForKeys: nil,
                options: [],
                errorHandler: { url, error in
                    warn(url, error.localizedDescription)
                    return true
                }) else {
                warn(root, "Unable to enumerate root")
                continue
            }

            for case let entry as URL in enumerator {
                if examined % 1_000 == 0 { try Task.checkCancellation() }
                if examined >= maxEntries || Date().timeIntervalSince(start) > maxDuration {
                    hitLimit = true
                    if warnings.count < 100 {
                        warnings.append("Scan stopped at configured entry or time limit; coverage is incomplete.")
                    }
                    break
                }

                let url = entry.standardizedFileURL
                let path = url.path
                // Avoid virtual devices, duplicate APFS Data mount mirror, and self-indexing.
                // External and network volumes can be selected explicitly as scan roots.
                let skipReason: String?
                if path == ownDataRoot || path.hasPrefix(ownDataRoot + "/") {
                    skipReason = "CleanJunk's private index is excluded to avoid indexing itself."
                } else if root.path == "/" &&
                            ["/dev", "/Network", "/Volumes", "/System/Volumes/Data",
                             "/System/Volumes/Preboot", "/System/Volumes/VM",
                             "/System/Volumes/Update"].contains(path) {
                    skipReason = "Virtual, duplicate or separately mounted volume; explicit scan scope required."
                } else {
                    skipReason = nil
                }
                if let skipReason {
                    enumerator.skipDescendants()
                    if warnings.count < 100 { warnings.append(path + " — " + skipReason) }
                    continue
                }

                examined += 1
                var metadata = stat()
                guard lstat(path, &metadata) == 0 else {
                    warn(url, "lstat unavailable: " + String(errno))
                    enumerator.skipDescendants()
                    continue
                }
                let kind = UInt32(metadata.st_mode) & UInt32(S_IFMT)
                let isDirectory = kind == UInt32(S_IFDIR)
                let isLink = kind == UInt32(S_IFLNK)
                let regular = kind == UInt32(S_IFREG)
                if isLink { enumerator.skipDescendants() }

                let identity = FileIdentity(device: UInt64(metadata.st_dev),
                                            inode: UInt64(metadata.st_ino),
                                            fileType: kind)
                if isDirectory {
                    if visitedDirectories.contains(identity) {
                        enumerator.skipDescendants()
                        continue
                    }
                    visitedDirectories.insert(identity)
                    directories += 1
                } else if regular {
                    files += 1
                } else if isLink {
                    links += 1
                }

                let duplicate = regular && metadata.st_nlink > 1 &&
                    !seenHardlinks.insert(identity).inserted
                if duplicate { duplicateHardlinks += 1 }

                // st_blocks uses 512-byte blocks; de-duplicate only hard links, not APFS clones.
                let blocks = max(0, Int64(metadata.st_blocks))
                let (rawBytes, overflow) = blocks.multipliedReportingOverflow(by: 512)
                let size = regular && !duplicate ? (overflow ? Int64.max : rawBytes) : 0
                let logical = regular ? max(0, Int64(metadata.st_size)) : 0
                let classification = DeepStorageClassifier.classify(path: path, home: homePath)
                let item = DeepFileRecord(
                    path: path, category: classification.category,
                    advice: classification.advice, owner: classification.owner,
                    evidence: classification.evidence,
                    logicalBytes: logical, allocatedBytes: size,
                    modifiedEpoch: Int64(metadata.st_mtimespec.tv_sec),
                    isDirectory: isDirectory, isLink: isLink,
                    isHardlinkDuplicate: duplicate
                )
                try db?.insert(item)
                let (sum, sumOverflow) = allocated.addingReportingOverflow(size)
                allocated = sumOverflow ? Int64.max : sum
                if classification.advice == .rebuildable {
                    let (total, overflow) = rebuildable.addingReportingOverflow(size)
                    rebuildable = overflow ? Int64.max : total
                }

                transactionEntries += 1
                if transactionEntries >= 2_000 {
                    try db?.execute("COMMIT")
                    try db?.execute("BEGIN IMMEDIATE")
                    transactionEntries = 0
                }

                if examined % 2_500 == 0 {
                    await progress(DeepScanProgress(
                        examinedEntries: examined,
                        indexedFiles: files,
                        indexedDirectories: directories,
                        allocatedBytes: allocated,
                        currentDirectory: url.deletingLastPathComponent().path,
                        inaccessibleEntries: inaccessible
                    ))
                }
            }
            if hitLimit { break }
        }

        let categories = try db?.categoryTotals() ?? []
        let summary = DeepScanSummary(
            roots: roots.map(\.path), startedAt: start, finishedAt: Date(),
            entriesExamined: examined, filesIndexed: files, directoriesIndexed: directories,
            symbolicLinksIndexed: links, allocatedBytes: allocated,
            rebuildableCandidateBytes: rebuildable, hardlinkDuplicates: duplicateHardlinks,
            inaccessibleEntries: inaccessible, warnings: warnings,
            categories: categories, limitsReached: hitLimit
        )
        try db?.saveSummary(summary)
        try db?.execute("COMMIT")
        db = nil

        if fileManager.fileExists(atPath: databaseURL.path) {
            _ = try fileManager.replaceItemAt(databaseURL, withItemAt: pending,
                                               backupItemName: nil, options: [])
        } else {
            try fileManager.moveItem(at: pending, to: databaseURL)
        }
        _ = chmod(databaseURL.path, 0o600)
        didInstall = true
        await progress(DeepScanProgress(
            examinedEntries: examined, indexedFiles: files,
            indexedDirectories: directories, allocatedBytes: allocated,
            currentDirectory: "Scan completed",
            inaccessibleEntries: inaccessible
        ))
        return summary
    }
}

extension DeepStorageClassifier {
    public static func isDescendant(_ path: String, of root: String) -> Bool {
        if path == root { return true }
        if root == "/" { return path.hasPrefix("/") }
        return path.hasPrefix(root + "/")
    }
}
