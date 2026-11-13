import Foundation

public enum ImportEvidenceStatus: String, Sendable {
    case observed = "Referenced in source"
    case notObserved = "No static reference found"
    case unknown = "Insufficient evidence"
}

public struct ImportEvidence: Identifiable, Sendable {
    public let dependency: DeclaredDependency
    public let status: ImportEvidenceStatus
    public let examplePaths: [String]
    public var id: String { dependency.id }
}

public struct SourceReferenceReport: Sendable {
    public let manifestPath: String
    public let inspectedSourceFiles: Int
    public let evidence: [ImportEvidence]
    public let warnings: [String]
    public let isComplete: Bool

    public var notObservedRuntimeCount: Int {
        evidence.filter { $0.status == .notObserved && $0.dependency.scope == .runtime }.count
    }
}

/// Bounded static import-evidence search. Never equates absent imports with unused packages:
/// plugins, configuration, scripts, reflection and dynamic imports can all evade this scan.
public actor SourceReferenceInspector {
    private let fileManager = FileManager()
    private let maxFiles: Int
    private let maxBytesPerFile: Int
    private let maxTotalBytes: Int

    private let ignored = Set([
        ".git", "node_modules", ".pnpm-store", ".yarn", ".next", ".nuxt", ".turbo",
        ".venv", "venv", "target", "dist", "build", ".build", "coverage",
        "vendor", "__pycache__", "DerivedData"
    ])

    private let sourceExtensions = Set([
        "js", "jsx", "ts", "tsx", "mjs", "cjs", "mts", "cts",
        "vue", "svelte", "astro"
    ])

    private let matcher = try! NSRegularExpression(
        pattern: #"(?:\b(?:import|export)\s+(?:[^;\r\n]*?\s+from\s+)?|\b(?:require|import)\s*\(\s*|\b(?:jest|vi)\.mock\s*\(\s*)['"]([^'"]+)['"]"#,
        options: []
    )

    public init(maxFiles: Int = 12_000,
                maxBytesPerFile: Int = 2 * 1_024 * 1_024,
                maxTotalBytes: Int = 64 * 1_024 * 1_024) {
        self.maxFiles = max(1, maxFiles)
        self.maxBytesPerFile = max(1, maxBytesPerFile)
        self.maxTotalBytes = max(1, maxTotalBytes)
    }

    public func inspect(project: WorkspaceProject, workspace: URL,
                        home: URL = FileManager.default.homeDirectoryForCurrentUser) throws -> SourceReferenceReport {
        try ScanPolicy.validateWorkspace(workspace, home: home)
        guard project.ecosystem == .node,
              ScanPolicy.isStrictDescendant(URL(fileURLWithPath: project.manifestPath), of: workspace),
              project.manifestPath.hasSuffix("/package.json") else {
            throw CleanJunkError.unsupportedOperation
        }
        let directory = URL(fileURLWithPath: project.directory).standardizedFileURL
        guard directory.resolvingSymlinksInPath() == directory else {
            throw CleanJunkError.pathChanged
        }
        var found: [String: [String]] = [:]
        var scanned = 0
        var bytesRead = 0
        var complete = true
        var warnings: [String] = []

        guard let iterator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
            options: [.skipsPackageDescendants],
            errorHandler: { url, error in
                warnings.append("Cannot inspect " + url.path + ": " + error.localizedDescription)
                complete = false
                return true
            }) else {
            return SourceReferenceReport(
                manifestPath: project.manifestPath, inspectedSourceFiles: 0,
                evidence: [], warnings: ["Could not enumerate project directory"],
                isComplete: false)
        }

        for case let url as URL in iterator {
            try Task.checkCancellation()
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey,
                                                            .isSymbolicLinkKey, .fileSizeKey])
            if values?.isSymbolicLink == true {
                iterator.skipDescendants()
                continue
            }
            if values?.isDirectory == true {
                if ignored.contains(url.lastPathComponent) { iterator.skipDescendants() }
                continue
            }
            guard values?.isRegularFile == true, sourceExtensions.contains(url.pathExtension.lowercased()) else {
                continue
            }
            if scanned >= maxFiles {
                warnings.append("Source inspection stopped at its \(maxFiles) file limit.")
                complete = false
                break
            }
            guard let size = values?.fileSize, size <= maxBytesPerFile else {
                warnings.append("Skipped oversized or unreadable source: " + url.lastPathComponent)
                complete = false
                continue
            }
            if bytesRead + size > maxTotalBytes {
                warnings.append("Source inspection stopped at its \(maxTotalBytes) byte limit.")
                complete = false
                break
            }
            let normalized = url.standardizedFileURL
            guard normalized.resolvingSymlinksInPath() == normalized,
                  let data = try? Data(contentsOf: normalized),
                  let text = String(data: data, encoding: .utf8) else {
                warnings.append("Could not safely read " + url.lastPathComponent)
                complete = false
                continue
            }
            bytesRead += data.count
            scanned += 1
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            for match in matcher.matches(in: text, range: range) {
                guard let valueRange = Range(match.range(at: 1), in: text) else { continue }
                let specifier = String(text[valueRange])
                guard let package = Self.packageName(from: specifier) else { continue }
                if found[package, default: []].count < 3 {
                    found[package, default: []].append(normalized.path)
                }
            }
        }

        let evidences = project.dependencies.map { dependency -> ImportEvidence in
            if let paths = found[dependency.name], !paths.isEmpty {
                return ImportEvidence(dependency: dependency, status: .observed,
                                      examplePaths: Array(Set(paths)).sorted())
            }
            // CLI tools, optional packages and peer deps are frequently used without an import.
            if dependency.scope != .runtime || !complete {
                return ImportEvidence(dependency: dependency, status: .unknown,
                                      examplePaths: [])
            }
            return ImportEvidence(dependency: dependency, status: .notObserved,
                                  examplePaths: [])
        }
        return SourceReferenceReport(
            manifestPath: project.manifestPath, inspectedSourceFiles: scanned,
            evidence: evidences, warnings: warnings, isComplete: complete)
    }

    public static func packageName(from specifier: String) -> String? {
        guard !specifier.isEmpty, !specifier.hasPrefix("."),
              !specifier.hasPrefix("/"), !specifier.hasPrefix("#"),
              !specifier.hasPrefix("node:"), !specifier.contains("://") else { return nil }
        let parts = specifier.split(separator: "/")
        guard let first = parts.first else { return nil }
        if first.hasPrefix("@") {
            guard parts.count >= 2 else { return nil }
            return String(first) + "/" + String(parts[1])
        }
        return String(first)
    }
}
