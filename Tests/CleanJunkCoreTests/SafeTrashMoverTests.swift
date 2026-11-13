import Foundation
import XCTest
@testable import CleanJunkCore

final class SafeTrashMoverTests: XCTestCase {
    private func fixture() throws -> (home: URL, file: URL, item: ScanItem) {
        // Descriptor-relative symlink protection must reject system temporary paths
        // with intermediary symbolic links. Test valid cleanup under a real user
        // home ancestor, which is the supported production scope.
        let home = FileManager.default.homeDirectoryForCurrentUser
            .resolvingSymlinksInPath()
            .appendingPathComponent("CleanJunkMove-\(UUID().uuidString)")
        let root = home.appendingPathComponent("Library/Caches")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("fixture.bin")
        try Data(repeating: 123, count: 256).write(to: file)
        let identity = try XCTUnwrap(FileIdentity.capture(at: file))
        let item = ScanItem(path: file.path, scopeRootPath: root.path,
                            category: .appCache, risk: .review,
                            rationale: "Test only", sizeBytes: 256, isSizeComplete: true,
                            identity: identity)
        return (home, file, item)
    }

    func testMovesOntoSameVolumeWithoutDeletingAndPreservesIdentity() throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.home) }
        let moved = try SafeTrashMover.move(f.item, home: f.home)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.file.path))
        XCTAssertTrue(moved.path.hasPrefix(f.home.appendingPathComponent(".Trash").path + "/"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: moved.path))
        XCTAssertEqual(FileIdentity.capture(at: moved), f.item.identity)
    }

    func testStaleOrTamperedIdentityIsRejected() throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.home) }
        let old = f.home.appendingPathComponent("replaced.bin")
        try FileManager.default.moveItem(at: f.file, to: old)
        try Data(repeating: 8, count: 256).write(to: f.file)
        XCTAssertThrowsError(try SafeTrashMover.move(f.item, home: f.home))
        XCTAssertTrue(FileManager.default.fileExists(atPath: f.file.path))
    }

    func testRestoresFromFakeHomeTrashWithoutOverwrite() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.home) }
        let journalURL = f.home.appendingPathComponent("state/journal.json")
        let journal = CleanupJournal(location: journalURL)
        let transaction = try await journal.prepare(f.item)
        let trashed = try SafeTrashMover.move(f.item, home: f.home)
        try await journal.complete(transaction.id, trashPath: trashed.path)

        let executor = CleanupExecutor(home: f.home, journal: journal)
        try await executor.restore(transaction.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: f.file.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: trashed.path))
        let updated = await journal.all()
        XCTAssertEqual(updated.first?.state, .restored)
    }

    func testRestoreDoesNotOverwriteAnOccupiedOriginal() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.home) }
        let journal = CleanupJournal(location: f.home.appendingPathComponent("journal.json"))
        let transaction = try await journal.prepare(f.item)
        let trashed = try SafeTrashMover.move(f.item, home: f.home)
        try await journal.complete(transaction.id, trashPath: trashed.path)
        try Data(repeating: 3, count: 99).write(to: f.file)
        let executor = CleanupExecutor(home: f.home, journal: journal)
        do {
            try await executor.restore(transaction.id)
            XCTFail("Restore must not overwrite the replacement file.")
        } catch CleanJunkError.alreadyExists {
            XCTAssertEqual(try Data(contentsOf: f.file).count, 99)
            XCTAssertTrue(FileManager.default.fileExists(atPath: trashed.path))
        }
    }
}
