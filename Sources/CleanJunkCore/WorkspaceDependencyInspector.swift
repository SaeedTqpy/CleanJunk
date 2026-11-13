import Foundation

/// Read-only project provenance. Presence in a lockfile never proves actual source usage.
public enum ProjectEcosystem: String, CaseIterable, Codable, Sendable {
    case node = "Node.js"
    case python = "Python"
    case rust = "Rust"
    case go = "Go"
}

public enum DependencyScope: String, Codable, Sendable {
    case runtime = "Runtime"
    case development = "Development"
    case optional = "Optional"
    case peer = "Peer"
}

public struct DeclaredDependency: Identifiable, Hashable, Sendable {
    public let name: String
    public let requirement: String
    public let scope: DependencyScope

    public var id: String { scope.rawValue + ":" + name }
}

public struct WorkspaceProject: Identifiable, Sendable {
    public let manifestPath: String
    public let ecosystem: ProjectEcosystem
    public let projectName: String
    public let dependencies: [DeclaredDependency]
    public let lockfiles: [String]
    public let lockfilePackageCount: Int?
    public let hasLocalInstall: Bool
    public let notes: [String]

    public var id: String { ecosystem.rawValue + ":" + manifestPath }
    public var directory: String { URL(fileURLWithPath: manifestPath).deletingLastPathComponent().path }
    public var declaredDependencyCount: Int { dependencies.count }
}

public struct WorkspaceDependencyReport: Sendable {
    public let workspacePath: String
    public let projects: [WorkspaceProject]
    public let warnings: [String]
    public let isComplete: Bool

    public var declaredDependencies: Int {
        projects.reduce(0) { $0 + $1.declaredDependencyCount }
    }

    public init(workspacePath: String, projects: [WorkspaceProject], warnings: [String], isComplete: Bool) {
        self.workspacePath = workspacePath
        self.projects = projects
        self.warnings = warnings
        self.isComplete = isComplete
    }
}

/// No package-manager commands, network calls, or filesystem mutations.
public actor WorkspaceDependencyInspector {
    private let fileManager = FileManager()
    private let maxEntries: Int
    private let maxProjects: Int

    private let manifestKinds: [String: ProjectEcosystem] = [
        "package.json": .node,
        "pyproject.toml": .python,
        "Cargo.toml": .rust,
        "go.mod": .go
    ]

    private let ignoredDirectories: Set<String> = [
        ".git", ".hg", ".svn", "node_modules", ".yarn", ".pnpm-store",
        ".venv", "venv", "__pycache__", "target", "vendor", "dist", "build",
        ".next", ".nuxt", ".turbo", ".gradle", ".build", "DerivedData", ".cache"
    ]

    public init(maxEntries: Int = 40_000, maxProjects: Int = 200) {
        self.maxEntries = max(1, maxEntries)
        self.maxProjects = max(1, maxProjects)
    }

    public func inspect(workspace: URL,
                        home: URL = FileManager.default.homeDirectoryForCurrentUser) throws -> WorkspaceDependencyReport {
        try ScanPolicy.validateWorkspace(workspace, home: home)
        let root = workspace.standardizedFileURL
        var found: [WorkspaceProject] = []
        var warnings: [String] = []
        var complete = true
        var visited = 0

        guard let iterator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsPackageDescendants],
            errorHandler: { path, error in
                warnings.append("Cannot inspect " + path.lastPathComponent + ": " + error.localizedDescription)
                complete = false
                return true
            }
        ) else {
            return WorkspaceDependencyReport(workspacePath: root.path,
                                             projects: [],
                                             warnings: ["Cannot enumerate selected workspace"],
                                             isComplete: false)
        }

        for case let url as URL in iterator {
            try Task.checkCancellation()
            visited += 1
            if visited > maxEntries {
                warnings.append("Workspace search stopped at the \(maxEntries)-entry safety limit.")
                complete = false
                break
            }

            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if values?.isSymbolicLink == true {
                iterator.skipDescendants()
                continue
            }
            let depth = url.pathComponents.count - root.pathComponents.count
            if depth > 8 {
                if values?.isDirectory == true { iterator.skipDescendants() }
                continue
            }
            if values?.isDirectory == true {
                if ignoredDirectories.contains(url.lastPathComponent) {
                    iterator.skipDescendants()
                }
                continue
            }
            guard let kind = manifestKinds[url.lastPathComponent] else { continue }
            if found.count >= maxProjects {
                warnings.append("Project discovery stopped at the \(maxProjects)-project safety limit.")
                complete = false
                break
            }

            if url.resolvingSymlinksInPath().standardizedFileURL != url.standardizedFileURL {
                warnings.append("Skipped a linked project manifest: " + url.path)
                complete = false
                continue
            }
            found.append(inspectManifest(url, kind: kind))
        }

        found.sort { $0.manifestPath.localizedStandardCompare($1.manifestPath) == .orderedAscending }
        return WorkspaceDependencyReport(workspacePath: root.path,
                                         projects: found, warnings: warnings, isComplete: complete)
    }

    private func inspectManifest(_ manifest: URL, kind: ProjectEcosystem) -> WorkspaceProject {
        let folder = manifest.deletingLastPathComponent()
        switch kind {
        case .node:
            return inspectNode(manifest, folder: folder)
        case .python, .rust, .go:
            let locks: [String]
            switch kind {
            case .python: locks = existing(["uv.lock", "poetry.lock", "Pipfile.lock"], in: folder)
            case .rust: locks = existing(["Cargo.lock"], in: folder)
            case .go: locks = existing(["go.sum"], in: folder)
            case .node: locks = []
            }
            return WorkspaceProject(
                manifestPath: manifest.path, ecosystem: kind,
                projectName: folder.lastPathComponent, dependencies: [],
                lockfiles: locks, lockfilePackageCount: nil,
                hasLocalInstall: false,
                notes: ["Manifest discovered. This ecosystem's dependency graph is not yet parsed; no unused-package conclusion is possible."]
            )
        }
    }

    private func inspectNode(_ manifest: URL, folder: URL) -> WorkspaceProject {
        let locks = existing(["package-lock.json", "npm-shrinkwrap.json", "pnpm-lock.yaml",
                              "yarn.lock", "bun.lock", "bun.lockb"], in: folder)
        var notes: [String] = []
        var dependencies: [DeclaredDependency] = []
        var projectName = folder.lastPathComponent

        if let data = boundedContents(manifest, maximum: 2 * 1_024 * 1_024),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            projectName = (object["name"] as? String) ?? projectName
            let declarations: [(String, DependencyScope)] = [
                ("dependencies", .runtime),
                ("devDependencies", .development),
                ("optionalDependencies", .optional),
                ("peerDependencies", .peer)
            ]
            for (field, scope) in declarations {
                guard let entries = object[field] as? [String: String] else { continue }
                for name in entries.keys.sorted() {
                    guard let requirement = entries[name] else { continue }
                    dependencies.append(DeclaredDependency(name: name,
                                                          requirement: requirement,
                                                          scope: scope))
                }
            }
        } else {
            notes.append("Unreadable or invalid package.json; dependency declarations unavailable.")
        }

        if locks.isEmpty {
            notes.append("No recognized lockfile found. Reproducible installation cannot be verified.")
        } else if locks.count > 1 {
            notes.append("Multiple package-manager lockfiles detected; determine which manager owns the project.")
        }
        if fileManager.fileExists(atPath: folder.appendingPathComponent("node_modules").path) {
            notes.append("node_modules exists. This alone does not indicate whether individual packages are used.")
        }
        let npmLock = ["npm-shrinkwrap.json", "package-lock.json"]
            .compactMap { name -> URL? in
                let url = folder.appendingPathComponent(name)
                return locks.contains(name) ? url : nil
            }.first
        let packageCount = npmLock.flatMap { countNpmLockPackages($0) }

        return WorkspaceProject(
            manifestPath: manifest.path, ecosystem: .node, projectName: projectName,
            dependencies: dependencies, lockfiles: locks,
            lockfilePackageCount: packageCount,
            hasLocalInstall: fileManager.fileExists(atPath: folder.appendingPathComponent("node_modules").path),
            notes: notes
        )
    }

    private func existing(_ names: [String], in folder: URL) -> [String] {
        names.filter { name in
            let candidate = folder.appendingPathComponent(name).standardizedFileURL
            return fileManager.fileExists(atPath: candidate.path) &&
                candidate.resolvingSymlinksInPath().standardizedFileURL == candidate
        }
    }

    private func countNpmLockPackages(_ path: URL) -> Int? {
        guard let data = boundedContents(path, maximum: 24 * 1_024 * 1_024),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let packages = root["packages"] as? [String: Any] else {
            return nil
        }
        // Root entry "" is not an installed dependency. Nested packages can duplicate names.
        return packages.keys.filter { !$0.isEmpty }.count
    }

    private func boundedContents(_ path: URL, maximum: Int) -> Data? {
        guard path.resolvingSymlinksInPath().standardizedFileURL == path.standardizedFileURL,
              let values = try? path.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true,
              let size = values.fileSize,
              size > 0, size <= maximum else {
            return nil
        }
        return try? Data(contentsOf: path)
    }
}
