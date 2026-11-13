import Foundation
import XCTest
@testable import CleanJunkCore

final class SystemStorageInspectorTests: XCTestCase {
    func testParsesTimeMachineSnapshotList() {
        let sample = """
        Snapshots for disk /:
        com.apple.TimeMachine.2026-10-30-090000.local
        com.apple.TimeMachine.2026-11-02-090000.local
        com.apple.TimeMachine.2026-11-02-090000.local
        unrelated log
        """
        XCTAssertEqual(SystemStorageInspector.parseSnapshotNames(sample), [
            "com.apple.TimeMachine.2026-10-30-090000.local",
            "com.apple.TimeMachine.2026-11-02-090000.local"
        ])
    }

    func testCapacityMathDoesNotClaimSnapshotSavings() {
        let report = SystemStorageReport(
            totalCapacityBytes: 250_000, freeCapacityBytes: 70_000,
            localSnapshotNames: ["com.apple.TimeMachine.example"], warnings: []
        )
        XCTAssertEqual(report.usedCapacityBytes, 180_000)
        XCTAssertEqual(report.localSnapshotNames.count, 1)
    }
}
