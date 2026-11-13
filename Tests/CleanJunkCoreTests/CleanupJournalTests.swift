import Foundation
import XCTest
@testable import CleanJunkCore

final class CleanupJournalTests: XCTestCase {
    private func fixture() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("CleanJunkJournalTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func candidate(at url: URL, home: URL) throws -> ScanItem {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data(repeating: 7, count: 64).write(to: url)
        let identity = try XCTUnwrap(FileIdentity.capture(at: url))
        return ScanItem(path: url.path,
                        scopeRootPath: home.appendingPathComponent("Library/Caches").path,
                        category: .appCache, risk: .review,
                        rationale: "Fixture only", sizeBytes: 64,
                        isSizeComplete: true, identity: identity)
    }

    func testWriteAheadAndCommitSurviveReopen() async throws {
        let home = try fixture()
        defer { try? FileManager.default.removeItem(at: home) }
        let url = home.appendingPathComponent("Library/Caches/com.example.test")
        let item = try candidate(at: url, home: home)
        let journalURL = home.appendingPathComponent("state/operations.json")
        let journal = CleanupJournal(location: journalURL)

        let pending = try await journal.prepare(item)
        XCTAssertEqual(pending.state, .prepared)
        XCTAssertTrue(FileManager.default.fileExists(atPath: journalURL.path))
        let reloaded = CleanupJournal(location: journalURL)
        let onDisk = await reloaded.all()
        XCTAssertEqual(onDisk.first?.state, .prepared)

        try await journal.complete(pending.id, trashPath: home.appendingPathComponent(".Trash/com.example.test").path)
        let committed = await CleanupJournal(location: journalURL).all()
        XCTAssertEqual(committed.count, 1)
        XCTAssertEqual(committed.first?.state, .movedToTrash)
    }

    func testCorruptExistingJournalRefusesToOverwrite() async throws {
        let home = try fixture()
        defer { try? FileManager.default.removeItem(at: home) }
        let journalURL = home.appendingPathComponent("operations.json")
        try Data("corrupt".utf8).write(to: journalURL)
        let item = try candidate(at: home.appendingPathComponent("Library/Caches/test"), home: home)
        let journal = CleanupJournal(location: journalURL)
        do {
            _ = try await journal.prepare(item)
            XCTFail("Corrupted journal must fail closed.")
        } catch {
            XCTAssertTrue(FileManager.default.fileExists(atPath: journalURL.path))
            XCTAssertEqual(try Data(contentsOf: journalURL), Data("corrupt".utf8))
        }
    }

    func testUnmeasuredArtifactCannotStartJournalOperation() async throws {
        let home = try fixture()
        defer { try? FileManager.default.removeItem(at: home) }
        let path = home.appendingPathComponent("Library/Caches/test")
        let item = try candidate(at: path, home: home)
        let unmeasured = ScanItem(path: item.path, scopeRootPath: item.scopeRootPath,
                                  category: .appCache, risk: .review, rationale: "Test",
                                  sizeBytes: 1, isSizeComplete: false, identity: item.identity)
        let journal = CleanupJournal(location: home.appendingPathComponent("ops.json"))
        do {
            _ = try await journal.prepare(unmeasured)
            XCTFail("Incomplete measurement must not be submitted.")
        } catch CleanJunkError.forbiddenPath {
            XCTAssertTrue(true)
        }
    }
}
