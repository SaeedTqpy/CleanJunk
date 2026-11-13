import Foundation

public struct ScanScope: Sendable {
    public let root: URL
    public let category: ArtifactCategory
    public let risk: RiskLevel
    public let rationale: String
    public let exactFileNames: Set<String>?

    public init(root: URL, category: ArtifactCategory, risk: RiskLevel, rationale: String,
                exactFileNames: Set<String>? = nil) {
        self.root = root.standardizedFileURL
        self.category = category
        self.risk = risk
        self.rationale = rationale
        self.exactFileNames = exactFileNames
    }
}

public enum ScanPolicy {
    public static let projectArtifactNames: Set<String> = [
        "node_modules", ".next", ".nuxt", ".turbo", ".svelte-kit",
        ".venv", "venv", "__pycache__", ".pytest_cache", ".mypy_cache",
        "target", ".gradle", ".dart_tool", ".build"
    ]

    public static func standardScopes(home: URL) -> [ScanScope] {
        let home = home.standardizedFileURL
        func at(_ path: String) -> URL { home.appendingPathComponent(path, isDirectory: true) }
        return [
            ScanScope(root: at("Library/Developer/Xcode/DerivedData"),
                      category: .xcode, risk: .reconstructible,
                      rationale: "Derived build products. Xcode will regenerate them."),
            ScanScope(root: at("Library/Developer/Xcode/Archives"),
                      category: .xcode, risk: .protected,
                      rationale: "Archived app builds can include irreplaceable signed distributions."),
            ScanScope(root: at("Library/Caches/com.apple.dt.Xcode"),
                      category: .xcode, risk: .review,
                      rationale: "Xcode caches can be recreated, but current development may be interrupted."),
            ScanScope(root: at("Library/Caches"),
                      category: .appCache, risk: .review,
                      rationale: "Application caches. Confirm the owning application is not in use."),
            ScanScope(root: at(".npm/_cacache"),
                      category: .packageCache, risk: .reconstructible,
                      rationale: "npm content-addressable package cache; downloads may be required again."),
            ScanScope(root: at(".cache/pip"),
                      category: .packageCache, risk: .reconstructible,
                      rationale: "pip download and wheel caches; dependencies may need to be downloaded again."),
            ScanScope(root: at(".gradle/caches"),
                      category: .packageCache, risk: .review,
                      rationale: "Gradle dependency and build caches; can disrupt a running Gradle daemon."),
            ScanScope(root: at("Library/Caches/Homebrew"),
                      category: .packageCache, risk: .review,
                      rationale: "Homebrew downloaded artifacts; prefer Homebrew's own cleanup command."),
            ScanScope(root: at("Library/Logs/DiagnosticReports"),
                      category: .developerLogs, risk: .review,
                      rationale: "Crash diagnostics; useful for investigating current defects."),
            ScanScope(root: at("Library/Containers/com.docker.docker/Data/vms/0/data"),
                      category: .docker, risk: .protected,
                      rationale: "Docker virtual disk. NEVER remove directly; use Docker's own volume/image tools.",
                      exactFileNames: ["Docker.raw", "Docker.qcow2"])
        ]
    }

    public static func isStrictDescendant(_ child: URL, of parent: URL) -> Bool {
        let childPath = child.standardizedFileURL.path
        let parentPath = parent.standardizedFileURL.path
        return childPath.hasPrefix(parentPath + "/")
    }

    public static func validateWorkspace(_ workspace: URL, home: URL) throws {
        let candidate = workspace.standardizedFileURL
        let path = candidate.path
        let forbidden = ["/", "/System", "/Library", "/Applications", "/usr", "/bin", "/sbin",
                         "/private", "/private/var", "/Volumes", home.standardizedFileURL.path]
        guard !forbidden.contains(path),
              !path.hasPrefix("/System/"), !path.hasPrefix("/Library/"),
              !path.hasPrefix("/private/var/"),
              candidate.resolvingSymlinksInPath().path == path else {
            throw CleanJunkError.invalidWorkspace
        }
    }

    public static func validateRemoval(_ item: ScanItem, home: URL,
                                       workspace: URL?) throws {
        guard item.isTrashEligible else { throw CleanJunkError.forbiddenPath }
        let target = URL(fileURLWithPath: item.path).standardizedFileURL
        guard let recordedIdentity = item.identity,
              FileIdentity.capture(at: target) == recordedIdentity else {
            throw CleanJunkError.pathChanged
        }
        let root = URL(fileURLWithPath: item.scopeRootPath).standardizedFileURL

        // Require every path component to remain the same after resolving symlinks.
        guard target.resolvingSymlinksInPath().path == target.path,
              root.resolvingSymlinksInPath().path == root.path else {
            throw CleanJunkError.pathChanged
        }

        if item.category == .workspace {
            guard let workspace else { throw CleanJunkError.forbiddenPath }
            try validateWorkspace(workspace, home: home)
            guard root == workspace.standardizedFileURL,
                  isStrictDescendant(target, of: root),
                  projectArtifactNames.contains(target.lastPathComponent) else {
                throw CleanJunkError.forbiddenPath
            }
            return
        }

        let permitted = standardScopes(home: home).contains { scope in
            scope.category == item.category &&
            scope.risk == item.risk &&
            scope.risk != .protected &&
            scope.root == root &&
            target.deletingLastPathComponent().standardizedFileURL == root &&
            (scope.exactFileNames == nil || scope.exactFileNames!.contains(target.lastPathComponent))
        }
        guard permitted else { throw CleanJunkError.forbiddenPath }
    }
}
