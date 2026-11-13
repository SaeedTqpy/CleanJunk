import Foundation
import XCTest
@testable import CleanJunkCore

final class WorkspaceDependencyInspectorTests: XCTestCase {
    private func fixture() throws -> URL {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(
            "CleanJunkDependencyTests-\(UUID().uuidString)", isDirectory: true
        )
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return home
    }

    private func put(_ content: String, at url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data(content.utf8).write(to: url)
    }

    func testReadsDirectDependenciesAndNpmLockWithoutUsageClaims() async throws {
        let home = try fixture()
        defer { try? FileManager.default.removeItem(at: home) }
        let workspace = home.appendingPathComponent("Development")
        let project = workspace.appendingPathComponent("frontend")
        try put("""
        {
          "name": "site",
          "dependencies": {"react": "^19.0.0", "lodash": "^4.17.0"},
          "devDependencies": {"typescript": "~5.6.0"},
          "optionalDependencies": {"fsevents": "^2.0.0"},
          "peerDependencies": {"react-dom": "*"}
        }
        """, at: project.appendingPathComponent("package.json"))
        try put("""
        {
          "lockfileVersion": 3,
          "packages": {
            "": {},
            "node_modules/react": {},
            "node_modules/react-dom": {},
            "node_modules/lodash": {},
            "node_modules/typescript": {}
          }
        }
        """, at: project.appendingPathComponent("package-lock.json"))
        try put("{}", at: project.appendingPathComponent("node_modules/example/package.json"))

        let result = try await WorkspaceDependencyInspector().inspect(workspace: workspace, home: home)
        XCTAssertTrue(result.isComplete)
        XCTAssertEqual(result.projects.count, 1)
        let site = try XCTUnwrap(result.projects.first)
        XCTAssertEqual(site.projectName, "site")
        XCTAssertEqual(site.declaredDependencyCount, 5)
        XCTAssertEqual(site.dependencies.filter { $0.scope == .runtime }.count, 2)
        XCTAssertEqual(site.lockfilePackageCount, 4)
        XCTAssertTrue(site.hasLocalInstall)
    }

    func testDetectsMultipleManagersAndInvalidJSONWithoutCrashing() async throws {
        let home = try fixture()
        defer { try? FileManager.default.removeItem(at: home) }
        let workspace = home.appendingPathComponent("Development")
        try put("not-json", at: workspace.appendingPathComponent("web/package.json"))
        try put("lock", at: workspace.appendingPathComponent("web/yarn.lock"))
        try put("lock", at: workspace.appendingPathComponent("web/pnpm-lock.yaml"))
        let result = try await WorkspaceDependencyInspector().inspect(workspace: workspace, home: home)
        let project = try XCTUnwrap(result.projects.first)
        XCTAssertEqual(project.declaredDependencyCount, 0)
        XCTAssertEqual(project.lockfiles.count, 2)
        XCTAssertTrue(project.notes.contains { $0.contains("Multiple") })
        XCTAssertTrue(project.notes.contains { $0.contains("invalid") })
    }

    func testRecognizesOtherEcosystemsButNeverInventsTheirDependencies() async throws {
        let home = try fixture()
        defer { try? FileManager.default.removeItem(at: home) }
        let workspace = home.appendingPathComponent("Development")
        try put("[project]\nname='service'\n", at: workspace.appendingPathComponent("api/pyproject.toml"))
        try put("[package]\nname='agent'\n", at: workspace.appendingPathComponent("agent/Cargo.toml"))
        try put("module example.com/cmd\n", at: workspace.appendingPathComponent("cmd/go.mod"))
        let result = try await WorkspaceDependencyInspector().inspect(workspace: workspace, home: home)
        XCTAssertEqual(Set(result.projects.map(\.ecosystem)), Set([.python, .rust, .go]))
        XCTAssertEqual(result.declaredDependencies, 0)
        XCTAssertTrue(result.projects.allSatisfy { !$0.notes.isEmpty })
    }

    func testRefusesHomeRoot() async throws {
        let home = try fixture()
        defer { try? FileManager.default.removeItem(at: home) }
        do {
            _ = try await WorkspaceDependencyInspector().inspect(workspace: home, home: home)
            XCTFail("Expected invalidWorkspace")
        } catch CleanJunkError.invalidWorkspace {
            // Expected.
        }
    }

    func testLimitsAreReportedWithoutMisleadingCompleteness() async throws {
        let home = try fixture()
        defer { try? FileManager.default.removeItem(at: home) }
        let workspace = home.appendingPathComponent("Development")
        for index in 0..<5 {
            try put("{}", at: workspace.appendingPathComponent("p\(index)/package.json"))
        }
        let result = try await WorkspaceDependencyInspector(maxEntries: 1, maxProjects: 1)
            .inspect(workspace: workspace, home: home)
        XCTAssertFalse(result.isComplete)
        XCTAssertFalse(result.warnings.isEmpty)
    }

    func testSymlinkedManifestNotRead() async throws {
        let home = try fixture()
        defer { try? FileManager.default.removeItem(at: home) }
        let workspace = home.appendingPathComponent("Development")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let external = home.appendingPathComponent("outside.json")
        try put("{\"name\":\"outside\"}", at: external)
        try FileManager.default.createSymbolicLink(
            at: workspace.appendingPathComponent("package.json"), withDestinationURL: external
        )
        let result = try await WorkspaceDependencyInspector().inspect(workspace: workspace, home: home)
        XCTAssertTrue(result.projects.isEmpty)
    }
}
