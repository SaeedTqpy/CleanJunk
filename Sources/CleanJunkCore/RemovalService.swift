import Foundation

public actor RemovalService {
    private let home: URL
    private let fileManager = FileManager()

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home.standardizedFileURL
    }

    /// Sends a single verified candidate to Finder's Trash. Never permanently deletes files.
    /// Requires revalidation immediately before executing, even after a successful scan.
    @discardableResult
    public func trash(_ candidate: ScanItem, workspace: URL?) throws -> TrashRecord {
        try ScanPolicy.validateRemoval(candidate, home: home, workspace: workspace)
        let url = URL(fileURLWithPath: candidate.path).standardizedFileURL
        guard let recordedIdentity = candidate.identity,
              FileIdentity.capture(at: url) == recordedIdentity else {
            throw CleanJunkError.pathChanged
        }
        // Identity is rechecked immediately before Finder's Trash operation.
        // A fully race-resistant implementation still requires descriptor-relative rename.
        var destination: NSURL?
        try fileManager.trashItem(at: url, resultingItemURL: &destination)
        return TrashRecord(originalPath: url.path, trashPath: (destination as URL?)?.path,
                           sizeBytes: candidate.sizeBytes, category: candidate.category)
    }
}

public actor ActivityLog {
    private let fileURL: URL
    private var entries: [TrashRecord]

    public init(fileURL: URL? = nil) {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/CleanJunk", isDirectory: true)
        let location = fileURL ?? root.appendingPathComponent("cleanup-history.json")
        self.fileURL = location
        self.entries = (try? Data(contentsOf: location))
            .flatMap { try? JSONDecoder().decode([TrashRecord].self, from: $0) } ?? []
    }

    public func all() -> [TrashRecord] { entries.sorted { $0.performedAt > $1.performedAt } }

    public func append(_ record: TrashRecord) throws {
        let next = entries + [record]
        let data = try JSONEncoder().encode(next)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
        entries = next
    }
}
