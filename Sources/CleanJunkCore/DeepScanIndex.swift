import Foundation
import Darwin
import SQLite3

private let deepSQLiteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// A local, persistent index of file metadata. File bodies are never copied into SQLite.
/// Writes are staged and atomically installed only after an entire scan finishes.
final class DeepScanDatabase {
    private var database: OpaquePointer?
    private var insertStatement: OpaquePointer?

    init(url: URL, create: Bool) throws {
        let flags = (create ? SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE : SQLITE_OPEN_READONLY)
            | SQLITE_OPEN_FULLMUTEX
        let result = sqlite3_open_v2(url.path, &database, flags, nil)
        guard result == SQLITE_OK, database != nil else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "Cannot open SQLite database"
            if let database { sqlite3_close(database) }
            database = nil
            throw DeepScanError.sqlite(message)
        }
        if create {
            _ = chmod(url.path, 0o600)
            try execute("""
                PRAGMA journal_mode=DELETE;
                PRAGMA synchronous=FULL;
                PRAGMA temp_store=MEMORY;
                CREATE TABLE IF NOT EXISTS files (
                    path TEXT PRIMARY KEY NOT NULL,
                    category TEXT NOT NULL,
                    advice TEXT NOT NULL,
                    owner TEXT NOT NULL,
                    evidence TEXT NOT NULL,
                    logical_bytes INTEGER NOT NULL,
                    allocated_bytes INTEGER NOT NULL,
                    modified_epoch INTEGER NOT NULL,
                    is_directory INTEGER NOT NULL,
                    is_link INTEGER NOT NULL,
                    duplicate_hardlink INTEGER NOT NULL
                );
                CREATE INDEX IF NOT EXISTS file_size_order ON files(allocated_bytes DESC);
                CREATE INDEX IF NOT EXISTS file_category ON files(category, advice);
                CREATE TABLE IF NOT EXISTS metadata (
                    key TEXT PRIMARY KEY NOT NULL,
                    value TEXT NOT NULL
                );
                """)
            try prepareInsert()
        }
    }

    deinit {
        if let insertStatement { sqlite3_finalize(insertStatement) }
        if let database { sqlite3_close(database) }
    }

    private func error() -> DeepScanError {
        DeepScanError.sqlite(database.map { String(cString: sqlite3_errmsg($0)) } ?? "Database not available")
    }

    func execute(_ sql: String) throws {
        guard let database else { throw DeepScanError.missingIndex }
        var message: UnsafeMutablePointer<CChar>?
        let status = sqlite3_exec(database, sql, nil, nil, &message)
        if status != SQLITE_OK {
            let detail = message.map { String(cString: $0) } ?? "SQL operation failed"
            if let message { sqlite3_free(message) }
            throw DeepScanError.sqlite(detail)
        }
    }

    private func prepareInsert() throws {
        guard let database else { throw DeepScanError.missingIndex }
        let sql = """
            INSERT INTO files(path,category,advice,owner,evidence,logical_bytes,
                              allocated_bytes,modified_epoch,is_directory,is_link,duplicate_hardlink)
            VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11)
            """
        guard sqlite3_prepare_v2(database, sql, -1, &insertStatement, nil) == SQLITE_OK else {
            throw error()
        }
    }

    func insert(_ item: DeepFileRecord) throws {
        guard let statement = insertStatement else { throw DeepScanError.missingIndex }
        sqlite3_reset(statement)
        sqlite3_clear_bindings(statement)
        bindText(statement, 1, item.path)
        bindText(statement, 2, item.category.rawValue)
        bindText(statement, 3, item.advice.rawValue)
        bindText(statement, 4, item.owner)
        bindText(statement, 5, item.evidence)
        sqlite3_bind_int64(statement, 6, item.logicalBytes)
        sqlite3_bind_int64(statement, 7, item.allocatedBytes)
        sqlite3_bind_int64(statement, 8, item.modifiedEpoch)
        sqlite3_bind_int(statement, 9, item.isDirectory ? 1 : 0)
        sqlite3_bind_int(statement, 10, item.isLink ? 1 : 0)
        sqlite3_bind_int(statement, 11, item.isHardlinkDuplicate ? 1 : 0)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw error() }
    }

    func saveSummary(_ summary: DeepScanSummary) throws {
        guard let database else { throw DeepScanError.missingIndex }
        let json = try String(decoding: JSONEncoder().encode(summary), as: UTF8.self)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database,
            "INSERT OR REPLACE INTO metadata(key,value) VALUES ('summary',?1)", -1,
            &statement, nil) == SQLITE_OK else { throw error() }
        defer { sqlite3_finalize(statement) }
        bindText(statement, 1, json)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw error() }
    }

    func loadSummary() throws -> DeepScanSummary? {
        guard let database else { throw DeepScanError.missingIndex }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT value FROM metadata WHERE key='summary'", -1,
                                 &statement, nil) == SQLITE_OK else { throw error() }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW,
              let data = sqlite3_column_text(statement, 0) else { return nil }
        return try JSONDecoder().decode(DeepScanSummary.self,
                                        from: Data(String(cString: data).utf8))
    }

    func categoryTotals() throws -> [DeepCategoryTotal] {
        guard let database else { throw DeepScanError.missingIndex }
        var statement: OpaquePointer?
        let sql = "SELECT category,COUNT(*),SUM(allocated_bytes) FROM files GROUP BY category ORDER BY SUM(allocated_bytes) DESC"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { throw error() }
        defer { sqlite3_finalize(statement) }
        var totals: [DeepCategoryTotal] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let name = sqlite3_column_text(statement, 0),
                  let category = DeepStorageCategory(rawValue: String(cString: name)) else { continue }
            totals.append(DeepCategoryTotal(category: category,
                                            entries: sqlite3_column_int64(statement, 1),
                                            allocatedBytes: sqlite3_column_int64(statement, 2)))
        }
        return totals
    }

    func files(search: String, advice: DeepCleanupAdvice?, category: DeepStorageCategory?,
               limit: Int, offset: Int) throws -> [DeepFileRecord] {
        guard let database else { throw DeepScanError.missingIndex }
        let sql = """
            SELECT path,category,advice,owner,evidence,logical_bytes,allocated_bytes,
                   modified_epoch,is_directory,is_link,duplicate_hardlink
            FROM files
            WHERE (?1='' OR instr(lower(path),lower(?1))>0)
              AND (?2='' OR advice=?2)
              AND (?3='' OR category=?3)
            ORDER BY allocated_bytes DESC, path ASC
            LIMIT ?4 OFFSET ?5
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { throw error() }
        defer { sqlite3_finalize(statement) }
        bindText(statement, 1, String(search.prefix(500)))
        bindText(statement, 2, advice?.rawValue ?? "")
        bindText(statement, 3, category?.rawValue ?? "")
        sqlite3_bind_int(statement, 4, Int32(max(1, min(limit, 500))))
        sqlite3_bind_int64(statement, 5, Int64(max(0, offset)))

        func columnText(_ col: Int32) -> String {
            guard let value = sqlite3_column_text(statement, col) else { return "" }
            return String(cString: value)
        }
        var records: [DeepFileRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let kind = DeepStorageCategory(rawValue: columnText(1)),
                  let recommendation = DeepCleanupAdvice(rawValue: columnText(2)) else { continue }
            records.append(DeepFileRecord(
                path: columnText(0), category: kind, advice: recommendation,
                owner: columnText(3), evidence: columnText(4),
                logicalBytes: sqlite3_column_int64(statement, 5),
                allocatedBytes: sqlite3_column_int64(statement, 6),
                modifiedEpoch: sqlite3_column_int64(statement, 7),
                isDirectory: sqlite3_column_int(statement, 8) != 0,
                isLink: sqlite3_column_int(statement, 9) != 0,
                isHardlinkDuplicate: sqlite3_column_int(statement, 10) != 0
            ))
        }
        return records
    }

    func exportCSV(to destination: URL) throws {
        guard let database else { throw DeepScanError.missingIndex }
        let sql = """
            SELECT path,category,advice,owner,evidence,logical_bytes,allocated_bytes,
                   modified_epoch,is_directory,is_link,duplicate_hardlink
            FROM files ORDER BY path ASC
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw error()
        }
        defer { sqlite3_finalize(statement) }

        let fm = FileManager.default
        guard fm.createFile(atPath: destination.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }

        func value(_ index: Int32) -> String {
            guard let p = sqlite3_column_text(statement, index) else { return "" }
            return String(cString: p)
        }
        func escape(_ string: String) -> String {
            "\"" + string.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        try output.write(contentsOf: Data(
            "path,category,advice,owner,evidence,logical_bytes,allocated_bytes,modified_epoch,is_directory,is_link,is_hardlink_duplicate\n".utf8
        ))
        var batch = ""
        var rows = 0
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { break }
            guard status == SQLITE_ROW else { throw error() }
            var fields = (0...4).map { escape(value(Int32($0))) }
            for index in 5...10 {
                fields.append(String(sqlite3_column_int64(statement, Int32(index))))
            }
            batch += fields.joined(separator: ",") + "\n"
            rows += 1
            if rows >= 1_000 {
                try output.write(contentsOf: Data(batch.utf8))
                rows = 0
                batch = ""
            }
        }
        if !batch.isEmpty { try output.write(contentsOf: Data(batch.utf8)) }
    }

    private func bindText(_ statement: OpaquePointer?, _ index: Int32, _ value: String) {
        sqlite3_bind_text(statement, index, (value as NSString).utf8String, -1,
                          deepSQLiteTransient)
    }
}

/// Read-only query actor for completed scans, independent of scanner lifetime.
public actor DeepScanIndex {
    public let databaseURL: URL

    public init(databaseURL: URL = Self.defaultDatabaseURL) {
        self.databaseURL = databaseURL
    }

    public static var defaultDatabaseURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/CleanJunk/deep-storage-v1.sqlite")
    }

    public func exportCSV(to destination: URL) throws {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            throw DeepScanError.missingIndex
        }
        try DeepScanDatabase(url: databaseURL, create: false).exportCSV(to: destination)
    }

    public func latestSummary() throws -> DeepScanSummary? {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return nil }
        return try DeepScanDatabase(url: databaseURL, create: false).loadSummary()
    }

    public func search(_ text: String = "", advice: DeepCleanupAdvice? = nil,
                       category: DeepStorageCategory? = nil, limit: Int = 150,
                       offset: Int = 0) throws -> [DeepFileRecord] {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            throw DeepScanError.missingIndex
        }
        return try DeepScanDatabase(url: databaseURL, create: false)
            .files(search: text, advice: advice, category: category,
                   limit: limit, offset: offset)
    }
}
