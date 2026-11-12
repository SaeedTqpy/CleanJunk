import Foundation

public actor StorageScanner {
    private let fileManager: FileManager
    private let maxVisitedPerCandidate: Int
    private let maxWorkspaceEntries: Int

    public init(maxVisitedPerCandidate: Int = 100_000, maxWorkspaceEntries: Int = 150_000) {
        self.fileManager = FileManager()
        self.maxVisitedPerCandidate = maxVisitedPerCandidate
        self.maxWorkspaceEntries = maxWorkspaceEntries
    }

    public func scan(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                     workspace: URL? = nil) throws -> ScanSnapshot {
        var candidates: [ScanItem] = []
        var skipped: [String] = []
        let scopes = ScanPolicy.standardScopes(home: home)
        let nestedScopeRoots = Set(scopes.map { $0.root.path })
        for scope in scopes {
            try Task.checkCancellation()
            guard fileManager.fileExists(atPath: scope.root.path) else { continue }
            guard scope.root.resolvingSymlinksInPath().path == scope.root.path else {
                skipped.append(scope.root.path)
                continue
            }
            do {
                let children = try fileManager.contentsOfDirectory(
                    at: scope.root, includingPropertiesForKeys: [.isSymbolicLinkKey], options: []
                )
                for child in children {
                    try Task.checkCancellation()
                    // A more specific scan scope owns this directory; do not double count it.
                    if nestedScopeRoots.contains(child.standardizedFileURL.path) { continue }
                    if let names = scope.exactFileNames, !names.contains(child.lastPathComponent) {
                        continue
                    }
                    guard !isSymlink(child) else {
                        skipped.append(child.path)
                        continue
                    }
                    let measurement = measure(child)
                    candidates.append(ScanItem(
                        path: child.standardizedFileURL.path,
                        scopeRootPath: scope.root.path,
                        category: scope.category,
                        risk: scope.risk,
                        rationale: scope.rationale,
                        sizeBytes: measurement.bytes,
                        isSizeComplete: measurement.complete
                    ))
                }
            } catch {
                skipped.append(scope.root.path)
            }
        }

        if let workspace {
            try ScanPolicy.validateWorkspace(workspace, home: home)
            let (projectItems, projectSkipped) = try scanWorkspace(workspace)
            candidates.append(contentsOf: projectItems)
            skipped.append(contentsOf: projectSkipped)
        }

        // Some cache scopes overlap; keep the most specific named scope.
        let sorted = candidates.sorted {
            let left = $0.scopeRootPath.count
            let right = $1.scopeRootPath.count
            return left == right ? $0.path < $1.path : left > right
        }
        var unique: [ScanItem] = []
        var seen = Set<String>()
        for item in sorted where !seen.contains(item.path) {
            seen.insert(item.path)
            unique.append(item)
        }
        return ScanSnapshot(items: unique.sorted { $0.sizeBytes > $1.sizeBytes },
                            skippedPaths: skipped)
    }

    private func scanWorkspace(_ workspace: URL) throws -> ([ScanItem], [String]) {
        guard let enumerator = fileManager.enumerator(at: workspace,
                                                      includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                                                      options: [.skipsPackageDescendants],
                                                      errorHandler: { _, _ in true }) else {
            return ([], [workspace.path])
        }
        var found: [ScanItem] = []
        var skipped: [String] = []
        var visited = 0
        for case let url as URL in enumerator {
            try Task.checkCancellation()
            visited += 1
            if visited > maxWorkspaceEntries {
                skipped.append("Workspace search limit reached: \(workspace.path)")
                break
            }
            if isSymlink(url) {
                enumerator.skipDescendants()
                continue
            }
            let depth = url.pathComponents.count - workspace.pathComponents.count
            if depth > 8 {
                enumerator.skipDescendants()
                continue
            }
            guard ScanPolicy.projectArtifactNames.contains(url.lastPathComponent),
                  isDirectory(url) else { continue }
            enumerator.skipDescendants()
            let measurement = measure(url)
            found.append(ScanItem(
                path: url.standardizedFileURL.path,
                scopeRootPath: workspace.standardizedFileURL.path,
                category: .workspace,
                risk: .review,
                rationale: "Project-generated directory; review before trashing. Reinstallation or rebuilding may be necessary.",
                sizeBytes: measurement.bytes,
                isSizeComplete: measurement.complete
            ))
        }
        return (found, skipped)
    }

    private func measure(_ url: URL) -> (bytes: Int64, complete: Bool) {
        let keys: Set<URLResourceKey> = [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey,
                                         .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey]
        if isSymlink(url) { return (0, false) }
        if !isDirectory(url) {
            return (allocatedBytes(url, keys: keys), true)
        }
        guard let enumerator = fileManager.enumerator(at: url,
                                                      includingPropertiesForKeys: Array(keys),
                                                      options: [],
                                                      errorHandler: { _, _ in true }) else {
            return (0, false)
        }
        var total: Int64 = 0
        var visited = 0
        for case let child as URL in enumerator {
            if Task.isCancelled { return (total, false) }
            visited += 1
            if visited > maxVisitedPerCandidate { return (total, false) }
            if isSymlink(child) {
                enumerator.skipDescendants()
                continue
            }
            if !isDirectory(child) {
                let next = allocatedBytes(child, keys: keys)
                let (sum, overflow) = total.addingReportingOverflow(next)
                total = overflow ? Int64.max : sum
            }
        }
        return (total, true)
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    private func isSymlink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }

    private func allocatedBytes(_ url: URL, keys: Set<URLResourceKey>) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }
        return Int64(max(0, values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0))
    }
}
