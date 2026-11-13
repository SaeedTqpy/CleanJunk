import Foundation

/// macOS installer receipts are evidence of package installation, not proof every file
/// still exists or that deleting a package is safe.
public struct InstallerReceiptInventory: Sendable {
    public let packageIDs: [String]
    public let inspectedAt: Date
    public let limitations: String
}

public actor InstallerReceiptInspector {
    public init() {}

    public func inspect() throws -> InstallerReceiptInventory {
        let executable = URL(fileURLWithPath: "/usr/sbin/pkgutil")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw CleanJunkError.unsupportedOperation
        }
        let output = try SafeProcessRunner.run(
            executable: executable,
            arguments: ["--pkgs"],
            timeoutSeconds: 30,
            maximumOutputBytes: 12 * 1_024 * 1_024
        )
        return InstallerReceiptInventory(
            packageIDs: Self.parse(output),
            inspectedAt: Date(),
            limitations: "Installer receipts are read-only evidence, not an authoritative inventory of current file contents. Uninstallation requires the owning vendor or package manager."
        )
    }

    public static func parse(_ text: String) -> [String] {
        let names = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") && $0.count <= 500 }
        return Array(Set(names)).sorted()
    }
}
