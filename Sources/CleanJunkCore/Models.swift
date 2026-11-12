import Foundation

public enum ArtifactCategory: String, CaseIterable, Codable, Sendable, Identifiable {
    case xcode = "Xcode"
    case packageCache = "Package caches"
    case appCache = "Application caches"
    case developerLogs = "Developer logs"
    case workspace = "Project artifacts"
    case docker = "Docker data"

    public var id: String { rawValue }
    public var symbol: String {
        switch self {
        case .xcode: return "hammer.fill"
        case .packageCache: return "shippingbox.fill"
        case .appCache: return "square.stack.3d.up.fill"
        case .developerLogs: return "doc.text.magnifyingglass"
        case .workspace: return "chevron.left.forwardslash.chevron.right"
        case .docker: return "externaldrive.fill"
        }
    }
}

public enum RiskLevel: Int, Codable, Comparable, Sendable {
    case reconstructible = 0
    case review = 1
    case protected = 2

    public static func < (lhs: RiskLevel, rhs: RiskLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var label: String {
        switch self {
        case .reconstructible: return "Rebuildable"
        case .review: return "Review required"
        case .protected: return "Inspect only"
        }
    }
}

public struct ScanItem: Codable, Hashable, Identifiable, Sendable {
    public let path: String
    public let scopeRootPath: String
    public let category: ArtifactCategory
    public let risk: RiskLevel
    public let rationale: String
    public let sizeBytes: Int64
    public let isSizeComplete: Bool

    public var id: String { path }
    public var name: String { URL(fileURLWithPath: path).lastPathComponent }
    public var isTrashEligible: Bool { risk != .protected }

    public init(path: String, scopeRootPath: String, category: ArtifactCategory, risk: RiskLevel,
                rationale: String, sizeBytes: Int64, isSizeComplete: Bool) {
        self.path = path
        self.scopeRootPath = scopeRootPath
        self.category = category
        self.risk = risk
        self.rationale = rationale
        self.sizeBytes = sizeBytes
        self.isSizeComplete = isSizeComplete
    }
}

public struct ScanSnapshot: Sendable {
    public let items: [ScanItem]
    public let skippedPaths: [String]
    public let scannedAt: Date

    public init(items: [ScanItem], skippedPaths: [String], scannedAt: Date = Date()) {
        self.items = items
        self.skippedPaths = skippedPaths
        self.scannedAt = scannedAt
    }

    public var totalBytes: Int64 { items.reduce(0) { $0 + $1.sizeBytes } }
    public var reviewableBytes: Int64 {
        items.filter(\.isTrashEligible).reduce(0) { $0 + $1.sizeBytes }
    }
    public var isEstimateComplete: Bool { items.allSatisfy(\.isSizeComplete) && skippedPaths.isEmpty }
}

public enum CleanJunkError: LocalizedError, Sendable {
    case forbiddenPath
    case pathChanged
    case alreadyExists
    case unsupportedOperation
    case invalidWorkspace

    public var errorDescription: String? {
        switch self {
        case .forbiddenPath: return "This location is not approved for cleanup."
        case .pathChanged: return "The location has changed or contains a symbolic link. Rescan before continuing."
        case .alreadyExists: return "The original location is occupied. No files were overwritten."
        case .unsupportedOperation: return "This operation is not supported."
        case .invalidWorkspace: return "Choose a specific development folder, not a system or home directory."
        }
    }
}

public struct TrashRecord: Codable, Sendable, Identifiable {
    public let id: UUID
    public let originalPath: String
    public let trashPath: String?
    public let sizeBytes: Int64
    public let category: ArtifactCategory
    public let performedAt: Date

    public init(id: UUID = UUID(), originalPath: String, trashPath: String?, sizeBytes: Int64,
                category: ArtifactCategory, performedAt: Date = Date()) {
        self.id = id
        self.originalPath = originalPath
        self.trashPath = trashPath
        self.sizeBytes = sizeBytes
        self.category = category
        self.performedAt = performedAt
    }
}
