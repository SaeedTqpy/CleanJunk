import Foundation
import XCTest
@testable import CleanJunkCore

final class SourceReferenceInspectorTests: XCTestCase {
    private func fixture() throws -> (home: URL, workspace: URL, project: URL) {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("CleanJunkImports-\(UUID().uuidString)")
        let workspace = home.appendingPathComponent("Development")
        let project = workspace.appendingPathComponent("website")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        return (home, workspace, project)
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    func testImportEvidenceAndNonObservedRuntime() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.home) }
        try write("""
        {"name": "website", "dependencies": {
          "react": "^19.0.0", "@acme/ui": "^1.0.0", "lodash": "^4.0.0"
        }, "devDependencies": {"eslint": "^9.0.0"}}
        """, to: f.project.appendingPathComponent("package.json"))
        try write("""
        import React from "react";
        import {Button} from "@acme/ui/button";
        const helper = require("react/jsx-runtime");
        """, to: f.project.appendingPathComponent("src/index.tsx"))

        let manifestReport = try await WorkspaceDependencyInspector()
            .inspect(workspace: f.workspace, home: f.home)
        let project = try XCTUnwrap(manifestReport.projects.first)
        let report = try await SourceReferenceInspector()
            .inspect(project: project, workspace: f.workspace, home: f.home)
        XCTAssertTrue(report.isComplete)
        XCTAssertEqual(report.inspectedSourceFiles, 1)
        let byName = Dictionary(uniqueKeysWithValues: report.evidence.map { ($0.dependency.name, $0.status) })
        XCTAssertEqual(byName["react"], .observed)
        XCTAssertEqual(byName["@acme/ui"], .observed)
        XCTAssertEqual(byName["lodash"], .notObserved)
        XCTAssertEqual(byName["eslint"], .unknown)
        XCTAssertEqual(report.notObservedRuntimeCount, 1)
    }

    func testImportSpecifierNormalization() {
        XCTAssertEqual(SourceReferenceInspector.packageName(from: "react/jsx-runtime"), "react")
        XCTAssertEqual(SourceReferenceInspector.packageName(from: "@acme/ui/button"), "@acme/ui")
        XCTAssertNil(SourceReferenceInspector.packageName(from: "../local"))
        XCTAssertNil(SourceReferenceInspector.packageName(from: "node:fs"))
        XCTAssertNil(SourceReferenceInspector.packageName(from: "https://example.com/pkg"))
    }

    func testIncompleteScanCannotAssertAbsence() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.home) }
        try write(#"{"dependencies":{"unknown":"1.0.0"}}"#,
                  to: f.project.appendingPathComponent("package.json"))
        try write("const x = 1;", to: f.project.appendingPathComponent("src/a.ts"))
        try write("const y = 2;", to: f.project.appendingPathComponent("src/b.ts"))
        let manifestReport = try await WorkspaceDependencyInspector()
            .inspect(workspace: f.workspace, home: f.home)
        let project = try XCTUnwrap(manifestReport.projects.first)
        let report = try await SourceReferenceInspector(maxFiles: 1)
            .inspect(project: project, workspace: f.workspace, home: f.home)
        XCTAssertFalse(report.isComplete)
        XCTAssertEqual(report.evidence.first?.status, .unknown)
    }

    func testRejectsProjectOutsideChosenWorkspace() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.home) }
        try write(#"{"dependencies":{"react":"*"}}}"#,
                  to: f.project.appendingPathComponent("package.json"))
        let manifestReport = try await WorkspaceDependencyInspector()
            .inspect(workspace: f.workspace, home: f.home)
        let project = try XCTUnwrap(manifestReport.projects.first)
        let elsewhere = f.home.appendingPathComponent("Other")
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        do {
            _ = try await SourceReferenceInspector()
                .inspect(project: project, workspace: elsewhere, home: f.home)
            XCTFail("A project outside the selected workspace must be rejected.")
        } catch CleanJunkError.unsupportedOperation { }
    }
}
