import Foundation
import XCTest
@testable import CleanJunkCore

final class DeepStorageScannerTests: XCTestCase {
    private func fixture() throws -> (home: URL, database: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CleanJunkDeepTests-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        let home = root.appendingPathComponent("User", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return (home, home.appendingPathComponent("Library/Application Support/CleanJunk/index.sqlite"))
    }

    private func write(_ bytes: Int, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: bytes).write(to: url)
    }

    func testDeepInventoryIncludesHiddenFilesAndPreservesUserDatabases() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.home.deletingLastPathComponent()) }

        try write(2048, to: f.home.appendingPathComponent(".npm/_cacache/blob"))
        try write(1024, to: f.home.appendingPathComponent("Library/Containers/com.example.mail/Data/Library/Caches/scratch"))
        try write(777, to: f.home.appendingPathComponent("Library/Application Support/com.example.bank/customer.sqlite"))
        try write(4096, to: f.home.appendingPathComponent("Documents/important.txt"))
        try write(512, to: f.home.appendingPathComponent("Code/app/node_modules/lib/main.js"))

        let scanner = DeepStorageScanner(databaseURL: f.database)
        let report = try await scanner.scan(roots: [f.home], home: f.home)
        XCTAssertGreaterThanOrEqual(report.filesIndexed, 5)
        XCTAssertFalse(report.limitsReached)
        XCTAssertGreaterThan(report.allocatedBytes, 0)

        let index = DeepScanIndex(databaseURL: f.database)
        let persisted = try await index.latestSummary()
        XCTAssertEqual(persisted?.filesIndexed, report.filesIndexed)

        let cacheRows = try await index.search("blob")
        let cache = try XCTUnwrap(cacheRows.first)
        XCTAssertEqual(cache.category, .developerCache)
        XCTAssertEqual(cache.advice, .rebuildable)
        XCTAssertFalse(cache.advice.isDeletionAuthorized)

        let databaseRows = try await index.search("customer.sqlite")
        let database = try XCTUnwrap(databaseRows.first)
        XCTAssertEqual(database.advice, .preserve)
        XCTAssertEqual(database.category, .applicationData)

        let sandboxRows = try await index.search("scratch")
        let sandboxCache = try XCTUnwrap(sandboxRows.first)
        XCTAssertEqual(sandboxCache.owner, "com.example.mail")
        XCTAssertEqual(sandboxCache.advice, .investigate)
        XCTAssertEqual(sandboxCache.category, .applicationCache)

        let dependencyRows = try await index.search("main.js")
        let dependencies = try XCTUnwrap(dependencyRows.first)
        XCTAssertEqual(dependencies.category, .installedPackage)
        XCTAssertEqual(dependencies.advice, .investigate)
    }

    func testSymlinkIsIndexedButNeverTraversed() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.home.deletingLastPathComponent()) }
        let outside = f.home.deletingLastPathComponent().appendingPathComponent("outside-secrets")
        try write(2048, to: outside.appendingPathComponent("private.dat"))
        try FileManager.default.createSymbolicLink(
            at: f.home.appendingPathComponent("linked-secrets"), withDestinationURL: outside
        )

        let report = try await DeepStorageScanner(databaseURL: f.database)
            .scan(roots: [f.home], home: f.home)
        XCTAssertEqual(report.symbolicLinksIndexed, 1)
        let rows = try await DeepScanIndex(databaseURL: f.database).search("linked-secrets")
        XCTAssertEqual(rows.count, 1)
        XCTAssertTrue(rows[0].isLink)
        let privateRows = try await DeepScanIndex(databaseURL: f.database).search("private.dat")
        XCTAssertTrue(privateRows.isEmpty)
    }

    func testHardLinksDoNotDoubleCountAllocatedBytes() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.home.deletingLastPathComponent()) }
        let first = f.home.appendingPathComponent("first.bin")
        let second = f.home.appendingPathComponent("second.bin")
        try write(100_000, to: first)
        try FileManager.default.linkItem(at: first, to: second)
        let report = try await DeepStorageScanner(databaseURL: f.database)
            .scan(roots: [f.home], home: f.home)
        XCTAssertEqual(report.hardlinkDuplicates, 1)
        XCTAssertEqual(report.filesIndexed, 2)
        XCTAssertGreaterThan(report.allocatedBytes, 0)
        XCTAssertLessThan(report.allocatedBytes, 200_000)
        let rows = try await DeepScanIndex(databaseURL: f.database).search()
        XCTAssertEqual(rows.filter(\.isHardlinkDuplicate).count, 1)
    }

    func testExplicitLimitsReportIncompleteCoverage() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.home.deletingLastPathComponent()) }
        for n in 0..<12 {
            try write(32, to: f.home.appendingPathComponent("cache/file-\(n).txt"))
        }
        let report = try await DeepStorageScanner(databaseURL: f.database, maxEntries: 3)
            .scan(roots: [f.home], home: f.home)
        XCTAssertTrue(report.limitsReached)
        XCTAssertFalse(report.coverageComplete)
        XCTAssertFalse(report.warnings.isEmpty)
    }

    func testSearchAndCSVExportUseOnlyMetadata() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.home.deletingLastPathComponent()) }
        try write(64, to: f.home.appendingPathComponent("Documents/customer,report.txt"))
        try write(64, to: f.home.appendingPathComponent(".npm/_cacache/hash"))
        _ = try await DeepStorageScanner(databaseURL: f.database)
            .scan(roots: [f.home], home: f.home)
        let index = DeepScanIndex(databaseURL: f.database)
        let filtered = try await index.search("", advice: .rebuildable,
                                              category: .developerCache)
        XCTAssertTrue(filtered.contains { $0.name == "hash" && !$0.isDirectory })
        XCTAssertTrue(filtered.contains { $0.name == "_cacache" && $0.isDirectory })
        let export = f.home.deletingLastPathComponent().appendingPathComponent("inventory.csv")
        try await index.exportCSV(to: export)
        let contents = try String(contentsOf: export, encoding: .utf8)
        XCTAssertTrue(contents.contains("\"" + f.home.appendingPathComponent("Documents/customer,report.txt").path + "\""))
        XCTAssertTrue(contents.contains("allocated_bytes"))
    }

    func testClassifierProtectsSystemAndPersonalContent() {
        let h = "/Users/fixture"
        XCTAssertEqual(DeepStorageClassifier.classify(path: "/System/Library/CoreServices",
                                                       home: h).advice, .preserve)
        XCTAssertEqual(DeepStorageClassifier.classify(path: h + "/Library/Containers/com.foo/Data/Documents/a.db",
                                                       home: h).advice, .preserve)
        XCTAssertEqual(DeepStorageClassifier.classify(path: h + "/Pictures/family.jpg",
                                                       home: h).advice, .preserve)
        XCTAssertEqual(DeepStorageClassifier.classify(path: "/opt/homebrew/Cellar/python/3.14",
                                                       home: h).category, .installedPackage)
        XCTAssertEqual(DeepStorageClassifier.classify(path: h + "/Library/Developer/Xcode/DerivedData/P",
                                                       home: h).advice, .rebuildable)
    }
}
