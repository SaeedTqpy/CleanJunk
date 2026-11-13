import Foundation

public struct SystemStorageReport: Sendable {
    public let totalCapacityBytes: Int64
    public let freeCapacityBytes: Int64
    public let localSnapshotNames: [String]
    public let warnings: [String]
    public let inspectedAt: Date

    public var usedCapacityBytes: Int64 {
        max(0, totalCapacityBytes - freeCapacityBytes)
    }

    public init(totalCapacityBytes: Int64, freeCapacityBytes: Int64,
                localSnapshotNames: [String], warnings: [String], inspectedAt: Date = Date()) {
        self.totalCapacityBytes = totalCapacityBytes
        self.freeCapacityBytes = freeCapacityBytes
        self.localSnapshotNames = localSnapshotNames
        self.warnings = warnings
        self.inspectedAt = inspectedAt
    }
}

/// macOS System Data is not a single path, and APFS snapshots don't have a trustworthy
/// independently recoverable byte count in this read-only inspection.
public actor SystemStorageInspector {
    public init() {}

    public func inspect(volumePath: String = "/") throws -> SystemStorageReport {
        let attributes = try FileManager.default.attributesOfFileSystem(forPath: volumePath)
        let total = (attributes[.systemSize] as? NSNumber)?.int64Value ?? 0
        let free = (attributes[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
        var warnings: [String] = []
        var names: [String] = []

        let tmutil = URL(fileURLWithPath: "/usr/bin/tmutil")
        if FileManager.default.isExecutableFile(atPath: tmutil.path) {
            do {
                let output = try SafeProcessRunner.run(
                    executable: tmutil,
                    arguments: ["listlocalsnapshots", volumePath],
                    timeoutSeconds: 12,
                    maximumOutputBytes: 2 * 1_024 * 1_024
                )
                names = Self.parseSnapshotNames(output)
            } catch {
                warnings.append("Local snapshot inspection unavailable: " + error.localizedDescription)
            }
        } else {
            warnings.append("Time Machine command-line diagnostics are unavailable on this Mac.")
        }

        return SystemStorageReport(totalCapacityBytes: total,
                                   freeCapacityBytes: free,
                                   localSnapshotNames: names,
                                   warnings: warnings)
    }

    public static func parseSnapshotNames(_ output: String) -> [String] {
        let names = output.split(whereSeparator: \.isNewline).compactMap { line -> String? in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.hasPrefix("com.apple.TimeMachine.") ? trimmed : nil
        }
        return Array(Set(names)).sorted()
    }
}
