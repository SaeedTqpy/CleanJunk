import XCTest
@testable import CleanJunkCore

final class StorageScannerTests: XCTestCase {
    private func temporaryHome() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CleanJunkTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func write(_ bytes: Int, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data(repeating: 0x32, count: bytes).write(to: url)
    }

    func testScanFindsAppCacheButDoesNotTouchFiles() async throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let file = home.appendingPathComponent("Library/Caches/com.example.app/cache.bin")
        try write(4096, to: file)
        let scanner = StorageScanner()
        let report = try await scanner.scan(home: home)
        let candidate = try XCTUnwrap(report.items.first {
            $0.name == "com.example.app" && $0.category == .appCache
        })
        XCTAssertGreaterThan(candidate.sizeBytes, 0)
        XCTAssertEqual(candidate.risk, .review)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func testDockerVirtualDiskIsInspectionOnly() async throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let docker = home.appendingPathComponent(
            "Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw")
        try write(1024, to: docker)
        let report = try await StorageScanner().scan(home: home)
        let item = try XCTUnwrap(report.items.first { $0.path == docker.path })
        XCTAssertEqual(item.risk, .protected)
        XCTAssertFalse(item.isTrashEligible)
        XCTAssertThrowsError(try ScanPolicy.validateRemoval(item, home: home, workspace: nil))
    }

    func testWorkspaceDiscoversNodeModulesAndDoesNotWalkInside() async throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let workspace = home.appendingPathComponent("Code", isDirectory: true)
        let file = workspace.appendingPathComponent("web/node_modules/library/index.js")
        try write(200, to: file)
        let report = try await StorageScanner().scan(home: home, workspace: workspace)
        let item = try XCTUnwrap(report.items.first {
            $0.name == "node_modules" && $0.category == .workspace
        })
        XCTAssertTrue(item.isTrashEligible)
        XCTAssertNoThrow(try ScanPolicy.validateRemoval(item, home: home, workspace: workspace))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func testSymlinkIsNeverTreatedAsCandidate() async throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let root = home.appendingPathComponent("Library/Caches", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let outside = home.appendingPathComponent("private-data")
        try write(128, to: outside)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("alias"),
                                                   withDestinationURL: outside)
        let report = try await StorageScanner().scan(home: home)
        XCTAssertFalse(report.items.contains { $0.name == "alias" })
    }

    func testTamperedCandidateIsRejected() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let wrong = home.appendingPathComponent("Documents/important.txt")
        try write(64, to: wrong)
        let fake = ScanItem(path: wrong.path,
                            scopeRootPath: home.appendingPathComponent("Library/Caches").path,
                            category: .appCache, risk: .review, rationale: "Fake",
                            sizeBytes: 64, isSizeComplete: true)
        XCTAssertThrowsError(try ScanPolicy.validateRemoval(fake, home: home, workspace: nil))
        XCTAssertTrue(FileManager.default.fileExists(atPath: wrong.path))
    }

    func testHomeDirectoryCannotBecomeWorkspace() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        XCTAssertThrowsError(try ScanPolicy.validateWorkspace(home, home: home))
        XCTAssertThrowsError(try ScanPolicy.validateWorkspace(URL(fileURLWithPath: "/"), home: home))
    }

    func testScannedFileIdentityMustMatchAtCleanup() async throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let root = home.appendingPathComponent("Library/Caches", isDirectory: true)
        let target = root.appendingPathComponent("temporary.txt")
        try write(128, to: target)

        let report = try await StorageScanner().scan(home: home)
        let item = try XCTUnwrap(report.items.first { $0.path == target.path })
        XCTAssertNotNil(item.identity)
        XCTAssertTrue(item.isTrashEligible)
        XCTAssertNoThrow(try ScanPolicy.validateRemoval(item, home: home, workspace: nil))

        let old = root.appendingPathComponent("previous.txt")
        try FileManager.default.moveItem(at: target, to: old)
        try write(256, to: target)
        XCTAssertThrowsError(try ScanPolicy.validateRemoval(item, home: home, workspace: nil))
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
    }

    func testIncompleteScanCannotBeSelectedForTrash() async throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        for index in 0..<12 {
            try write(256, to: home.appendingPathComponent("Library/Caches/many/item\(index)"))
        }
        let report = try await StorageScanner(maxVisitedPerCandidate: 1).scan(home: home)
        let item = try XCTUnwrap(report.items.first { $0.name == "many" })
        XCTAssertFalse(item.isSizeComplete)
        XCTAssertFalse(item.isTrashEligible)
        XCTAssertThrowsError(try ScanPolicy.validateRemoval(item, home: home, workspace: nil))
    }

    func testPartialMeasurementsAreExplicit() async throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        for index in 0..<6 {
            try write(2048, to: home.appendingPathComponent("Library/Caches/test/file\(index)"))
        }
        let report = try await StorageScanner(maxVisitedPerCandidate: 2).scan(home: home)
        let item = try XCTUnwrap(report.items.first { $0.name == "test" })
        XCTAssertFalse(item.isSizeComplete)
        XCTAssertFalse(report.isEstimateComplete)
    }
}
