import Foundation

public enum CleanupOperationState: String, Codable, Sendable {
    case prepared
    case movedToTrash
    case failed
    case requiresReconciliation
}

public struct CleanupOperation: Identifiable, Codable, Sendable {
    public let id: UUID
    public let sourcePath: String
    public let scannedIdentity: FileIdentity
    public let estimatedBytes: Int64
    public let startedAt: Date
    public var state: CleanupOperationState
    public var trashPath: String?
    public var detail: String?

    public init(id: UUID = UUID(), sourcePath: String, scannedIdentity: FileIdentity,
                estimatedBytes: Int64, startedAt: Date = Date(),
                state: CleanupOperationState = .prepared,
                trashPath: String? = nil, detail: String? = nil) {
        self.id = id
        self.sourcePath = sourcePath
        self.scannedIdentity = scannedIdentity
        self.estimatedBytes = estimatedBytes
        self.startedAt = startedAt
        self.state = state
        self.trashPath = trashPath
        self.detail = detail
    }
}

/// Write-ahead journal. No move begins unless prepare has been persisted.
/// Prepared operations after an interrupted run must be reconciled by the user.
public actor CleanupJournal {
    private let location: URL
    private let fileManager = FileManager()
    private let unreadableExistingJournal: Bool
    private var operations: [CleanupOperation]

    public init(location: URL? = nil) {
        let applicationSupport = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/CleanJunk", isDirectory: true)
        let path = location ?? applicationSupport.appendingPathComponent("cleanup-operations-v1.json")
        self.location = path
        if FileManager.default.fileExists(atPath: path.path) {
            let data = try? Data(contentsOf: path)
            if let data, let parsed = try? JSONDecoder().decode([CleanupOperation].self, from: data) {
                self.operations = parsed
                self.unreadableExistingJournal = false
            } else {
                self.operations = []
                self.unreadableExistingJournal = true
            }
        } else {
            self.operations = []
            self.unreadableExistingJournal = false
        }
    }

    public func all() -> [CleanupOperation] {
        operations.sorted { $0.startedAt > $1.startedAt }
    }

    public func prepare(_ candidate: ScanItem) throws -> CleanupOperation {
        guard candidate.isTrashEligible, let identity = candidate.identity else {
            throw CleanJunkError.forbiddenPath
        }
        let operation = CleanupOperation(sourcePath: candidate.path,
                                         scannedIdentity: identity,
                                         estimatedBytes: candidate.sizeBytes)
        try persist(operations + [operation])
        return operation
    }

    public func complete(_ id: UUID, trashPath: String?) throws {
        try modify(id: id, status: .movedToTrash, path: trashPath,
                   detail: "Moved to Finder Trash. Space is freed only after emptying Trash.")
    }

    public func markForReconciliation(_ id: UUID, reason: String) throws {
        try modify(id: id, status: .requiresReconciliation, path: nil, detail: reason)
    }

    private func modify(id: UUID, status: CleanupOperationState,
                        path: String?, detail: String) throws {
        guard let index = operations.firstIndex(where: { $0.id == id }) else {
            throw CleanJunkError.unsupportedOperation
        }
        var next = operations
        next[index].state = status
        next[index].trashPath = path
        next[index].detail = detail
        try persist(next)
    }

    private func persist(_ next: [CleanupOperation]) throws {
        guard !unreadableExistingJournal else {
            throw CleanJunkError.unsupportedOperation
        }
        let data = try JSONEncoder().encode(next)
        try fileManager.createDirectory(at: location.deletingLastPathComponent(),
                                        withIntermediateDirectories: true)
        try data.write(to: location, options: .atomic)
        operations = next
    }
}

public struct CleanupExecutionResult: Sendable {
    public let record: TrashRecord
    public let auditWarning: String?
}

public actor CleanupExecutor {
    private let home: URL
    private let removal: RemovalService
    private let journal: CleanupJournal

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                journal: CleanupJournal? = nil) {
        self.home = home.standardizedFileURL
        self.removal = RemovalService(home: home)
        self.journal = journal ?? CleanupJournal()
    }

    public func operations() async -> [CleanupOperation] {
        await journal.all()
    }

    public func trash(_ candidate: ScanItem, workspace: URL?) async throws -> CleanupExecutionResult {
        guard candidate.isTrashEligible else { throw CleanJunkError.forbiddenPath }
        try ScanPolicy.validateRemoval(candidate, home: home, workspace: workspace)
        let operation = try await journal.prepare(candidate)
        do {
            let record = try await removal.trash(candidate, workspace: workspace)
            do {
                try await journal.complete(operation.id, trashPath: record.trashPath)
                return CleanupExecutionResult(record: record, auditWarning: nil)
            } catch {
                // Move succeeded: returning a success with an explicit audit warning matters.
                return CleanupExecutionResult(record: record,
                    auditWarning: "Item moved, but final audit update failed. Reconcile operation \(operation.id): \(error.localizedDescription)")
            }
        } catch {
            // Keep any failed/interrupted operation in the durable journal.
            try? await journal.markForReconciliation(
                operation.id, reason: "Operation failed or interrupted: \(error.localizedDescription)"
            )
            throw error
        }
    }
}
