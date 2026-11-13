import Foundation

/// Assessment is evidence-based; these labels do not authorize an automatic removal.
public enum DeepCleanupAdvice: String, Codable, CaseIterable, Identifiable, Sendable {
    case rebuildable = "Rebuildable — ask first"
    case investigate = "Review with app owner"
    case preserve = "Preserve"
    case unknown = "Unknown — do not remove"

    public var id: String { rawValue }
    public var isDeletionAuthorized: Bool { false }
}

public enum DeepStorageCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case developerCache = "Developer cache"
    case applicationCache = "Application cache"
    case applicationData = "Application data"
    case installedPackage = "Installed package"
    case application = "Application bundle"
    case system = "macOS / protected"
    case userContent = "User content"
    case diagnostic = "Diagnostics"
    case other = "Other"

    public var id: String { rawValue }
}

public struct DeepClassification: Sendable {
    public let category: DeepStorageCategory
    public let advice: DeepCleanupAdvice
    public let owner: String
    public let evidence: String

    public init(category: DeepStorageCategory, advice: DeepCleanupAdvice,
                owner: String, evidence: String) {
        self.category = category
        self.advice = advice
        self.owner = owner
        self.evidence = evidence
    }
}

public struct DeepFileRecord: Identifiable, Codable, Hashable, Sendable {
    public let path: String
    public let category: DeepStorageCategory
    public let advice: DeepCleanupAdvice
    public let owner: String
    public let evidence: String
    public let logicalBytes: Int64
    public let allocatedBytes: Int64
    public let modifiedEpoch: Int64
    public let isDirectory: Bool
    public let isLink: Bool
    public let isHardlinkDuplicate: Bool

    public var id: String { path }
    public var name: String { URL(fileURLWithPath: path).lastPathComponent }
}

public struct DeepScanProgress: Sendable {
    public let examinedEntries: Int64
    public let indexedFiles: Int64
    public let indexedDirectories: Int64
    public let allocatedBytes: Int64
    public let currentDirectory: String
    public let inaccessibleEntries: Int64
}

public struct DeepCategoryTotal: Codable, Sendable, Identifiable {
    public let category: DeepStorageCategory
    public let entries: Int64
    public let allocatedBytes: Int64
    public var id: String { category.rawValue }
}

public struct DeepScanSummary: Codable, Sendable {
    public let roots: [String]
    public let startedAt: Date
    public let finishedAt: Date
    public let entriesExamined: Int64
    public let filesIndexed: Int64
    public let directoriesIndexed: Int64
    public let symbolicLinksIndexed: Int64
    public let allocatedBytes: Int64
    public let rebuildableCandidateBytes: Int64
    public let hardlinkDuplicates: Int64
    public let inaccessibleEntries: Int64
    public let warnings: [String]
    public let categories: [DeepCategoryTotal]
    public let limitsReached: Bool

    /// A full system scan is never claimed if the OS denied access to paths.
    public var coverageComplete: Bool { !limitsReached && inaccessibleEntries == 0 }
}

public enum DeepScanError: LocalizedError, Sendable {
    case invalidRoot
    case sqlite(String)
    case missingIndex

    public var errorDescription: String? {
        switch self {
        case .invalidRoot: return "Choose an existing directory. A protected, unavailable or symbolic-link root cannot be scanned."
        case .sqlite(let message): return "Deep inventory database error: " + message
        case .missingIndex: return "No completed deep-scan index exists. Run a scan first."
        }
    }
}

/// File-level evidence classification. Never reads file content or executes binaries.
/// Deletion permission remains a distinct safety policy; no advice value authorizes it.
public enum DeepStorageClassifier {
    public static func classify(path: String, home: String) -> DeepClassification {
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        let h = URL(fileURLWithPath: home).standardizedFileURL.path
        let relativeHome = standardized == h ? "" :
            (standardized.hasPrefix(h + "/") ? String(standardized.dropFirst(h.count + 1)) : nil)

        func inside(_ value: String, _ root: String) -> Bool {
            value == root || value.hasPrefix(root + "/")
        }
        func result(_ category: DeepStorageCategory, _ advice: DeepCleanupAdvice,
                    _ owner: String, _ why: String) -> DeepClassification {
            DeepClassification(category: category, advice: advice,
                               owner: owner, evidence: why)
        }
        func matches(_ value: String, _ prefix: String) -> Bool {
            inside(value, prefix)
        }

        // Homebrew Intel and other third-party installations live under /usr/local.
        // This must be classified before the protected /usr system-root rule.
        if standardized == "/usr/local" || standardized.hasPrefix("/usr/local/") {
            let pathComponents = standardized.split(separator: "/").map(String.init)
            let owner = pathComponents.count > 3 && pathComponents[2] == "Cellar"
                ? pathComponents[3] : "Third-party package"
            return result(.installedPackage, .preserve, owner,
                          "Third-party tool or package. Use its owning package manager or vendor installer.")
        }

        // System and low-level locations override every appearance-based cache heuristic.
        for root in ["/System", "/bin", "/sbin", "/usr", "/Library",
                     "/private", "/dev", "/opt/homebrew/Cellar", "/opt/homebrew/Caskroom"] {
            if matches(standardized, root) {
                if matches(standardized, "/opt/homebrew/Cellar") ||
                    matches(standardized, "/opt/homebrew/Caskroom") {
                    let parts = standardized.split(separator: "/")
                    let package = parts.count > 3 ? String(parts[3]) : "Homebrew"
                    return result(.installedPackage, .preserve, package,
                                  "Installed Homebrew formula or cask; uninstall only through Homebrew after dependency review.")
                }
                return result(.system, .preserve, "macOS",
                              "System-level or shared machine data must not be removed by this app.")
            }
        }

        if standardized == "/Applications" || standardized.hasPrefix("/Applications/") {
            let app = standardized.split(separator: "/")
                .first(where: { $0.hasSuffix(".app") }).map(String.init) ?? "Applications"
            return result(.application, .preserve, app,
                          "Installed applications and their bundle contents are not temporary caches.")
        }
        if standardized.hasPrefix("/opt/") || standardized.hasPrefix("/usr/local/") {
            return result(.installedPackage, .preserve, "System package or tool",
                          "Machine-wide tools, language runtimes and dependencies require their owning installer.")
        }

        guard let relativeHome else {
            return result(.other, .unknown, "Unknown owner",
                          "No verified owner or rebuildability evidence for this path.")
        }

        if inside(relativeHome, "Library/Group Containers") {
            return result(.applicationData, .preserve, "Shared application group",
                          "App group containers may contain user documents, synchronization state and protected secrets.")
        }
        if inside(relativeHome, "Library/Containers") {
            let parts = relativeHome.split(separator: "/").map(String.init)
            let bundle = parts.count > 2 ? parts[2] : "App container"
            let internalCache = parts.count >= 6 &&
                parts[3] == "Data" && parts[4] == "Library" && parts[5] == "Caches"
            return result(internalCache ? .applicationCache : .applicationData,
                          internalCache ? .investigate : .preserve, bundle,
                          internalCache
                            ? "App sandbox cache; contents might be active or protected by macOS. Review with its owner."
                            : "App sandbox data can include documents, accounts and databases. Never classify as disposable.")
        }

        if inside(relativeHome, "Library/Application Support") {
            let parts = relativeHome.split(separator: "/").map(String.init)
            let owner = parts.count > 2 ? parts[2] : "Application Support"
            return result(.applicationData, .preserve, owner,
                          "Application Support can contain databases, settings, licenses and authentication material.")
        }
        if inside(relativeHome, "Library/Mail") ||
            inside(relativeHome, "Library/Messages") ||
            inside(relativeHome, "Library/Keychains") {
            return result(.applicationData, .preserve, "Apple user data",
                          "Personal communication or secure account data must be preserved.")
        }

        let cachePrefixes: [(String, String)] = [
            (".npm/_cacache", "npm"),
            (".cache/pip", "pip"),
            (".cache/uv", "uv"),
            ("Library/Caches/uv", "uv"),
            (".cache/go-build", "Go"),
            (".cargo/registry/cache", "Cargo"),
            ("Library/Developer/Xcode/DerivedData", "Xcode")
        ]
        for (prefix, owner) in cachePrefixes where inside(relativeHome, prefix) {
            return result(.developerCache, .rebuildable, owner,
                          "Known generated cache. May require redownload/rebuild and must not be cleaned while in use.")
        }

        if inside(relativeHome, "Library/Caches") {
            let rest = String(relativeHome.dropFirst("Library/Caches".count))
            let component = rest.split(separator: "/").first.map(String.init) ?? "Application cache"
            return result(.applicationCache, .investigate, component,
                          "App-owned cache; rebuildability and active usage depend on the owning application.")
        }
        if inside(relativeHome, "Library/Logs/DiagnosticReports") {
            return result(.diagnostic, .investigate, "Diagnostic reports",
                          "Crash reports may be valuable for debugging current issues.")
        }

        let segments = relativeHome.split(separator: "/").map(String.init)
        if let appIndex = segments.firstIndex(where: { $0.hasSuffix(".app") }) {
            return result(.application, .preserve, segments[appIndex],
                          "Application bundle contains executable code or app resources, not disposable junk.")
        }

        if segments.contains("node_modules") ||
            segments.contains("site-packages") ||
            segments.contains(".venv") ||
            segments.contains("venv") ||
            segments.contains("target") ||
            segments.contains(".gradle") {
            var packageOwner = segments.contains("site-packages") ? "Python packages" :
                (segments.contains("node_modules") ? "Node.js" :
                    (segments.contains("target") ? "Rust" :
                        (segments.contains(".gradle") ? "Gradle" : "Python")))
            if let index = segments.firstIndex(of: "node_modules"),
               segments.count > index + 1 {
                let first = segments[index + 1]
                if first.hasPrefix("@"), segments.count > index + 2 {
                    packageOwner = first + "/" + segments[index + 2]
                } else {
                    packageOwner = first
                }
            }
            return result(.installedPackage, .investigate, packageOwner,
                          "Installed dependencies or build outputs may be referenced by active projects and offline builds.")
        }

        if segments.contains("Documents") || segments.contains("Desktop") ||
            segments.contains("Pictures") || segments.contains("Movies") ||
            segments.contains("Music") || segments.contains("Downloads") {
            return result(.userContent, .preserve, "User files",
                          "User-created and downloaded files must never be automatically classified as junk.")
        }

        if inside(relativeHome, ".cargo") || inside(relativeHome, ".rustup") ||
            inside(relativeHome, ".nvm") || inside(relativeHome, ".pyenv") {
            return result(.installedPackage, .preserve, "Developer toolchain",
                          "Language toolchain data and package installations need package-manager ownership evidence.")
        }

        return result(.other, .unknown, "Unknown owner",
                      "Insufficient evidence to recommend removal; inspect before taking action.")
    }
}
