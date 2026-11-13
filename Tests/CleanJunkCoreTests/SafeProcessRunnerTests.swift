import Foundation
import XCTest
@testable import CleanJunkCore

final class SafeProcessRunnerTests: XCTestCase {
    func testExplicitExecutableAndArguments() throws {
        let output = try SafeProcessRunner.run(
            executable: URL(fileURLWithPath: "/bin/echo"),
            arguments: ["hello", "cleanjunk"],
            timeoutSeconds: 5
        )
        XCTAssertEqual(output.trimmingCharacters(in: .whitespacesAndNewlines), "hello cleanjunk")
    }

    func testNonzeroExitIsReported() throws {
        XCTAssertThrowsError(
            try SafeProcessRunner.run(
                executable: URL(fileURLWithPath: "/usr/bin/false"),
                arguments: [], timeoutSeconds: 5
            )
        )
    }

    func testOutputLimit() throws {
        XCTAssertThrowsError(
            try SafeProcessRunner.run(
                executable: URL(fileURLWithPath: "/bin/echo"),
                arguments: [String(repeating: "x", count: 100)],
                maximumOutputBytes: 8
            )
        ) { error in
            guard case InspectionProcessError.exceededOutputLimit = error else {
                XCTFail("Expected explicit output limit, got \(error)")
                return
            }
        }
    }

    func testNoShellEvaluation() throws {
        let payload = "$(touch /tmp/cleanjunk-should-not-exist)"
        let output = try SafeProcessRunner.run(
            executable: URL(fileURLWithPath: "/bin/echo"),
            arguments: [payload], timeoutSeconds: 5
        )
        XCTAssertTrue(output.contains(payload))
    }
}
