import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public enum InspectionProcessError: LocalizedError, Sendable {
    case timedOut
    case exceededOutputLimit
    case failed(Int32)
    case invalidUTF8

    public var errorDescription: String? {
        switch self {
        case .timedOut: return "Package-manager inspection timed out."
        case .exceededOutputLimit: return "Package-manager inspection produced too much output."
        case .failed(let code): return "Package-manager inspection exited with status \(code)."
        case .invalidUTF8: return "Package-manager output is not UTF-8."
        }
    }
}

/// Runs only an explicitly supplied executable with argv (never via a shell).
/// Uses a bounded temporary file instead of a pipe to avoid stdout-buffer deadlocks.
public enum SafeProcessRunner {
    public static func run(
        executable: URL,
        arguments: [String],
        environmentOverrides: [String: String] = [:],
        timeoutSeconds: Double = 35,
        maximumOutputBytes: Int = 32 * 1_024 * 1_024
    ) throws -> String {
        let fileManager = FileManager.default
        let output = fileManager.temporaryDirectory
            .appendingPathComponent("CleanJunkCommand-\(UUID().uuidString).stdout")
        guard fileManager.createFile(atPath: output.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let handle = try FileHandle(forWritingTo: output)
        defer {
            try? handle.close()
            try? fileManager.removeItem(at: output)
        }

        let command = Process()
        command.executableURL = executable
        command.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        for (key, value) in environmentOverrides { environment[key] = value }
        command.environment = environment
        command.standardOutput = handle
        command.standardError = FileHandle.nullDevice

        let finished = DispatchSemaphore(value: 0)
        command.terminationHandler = { _ in finished.signal() }
        try command.run()

        if finished.wait(timeout: .now() + max(1, timeoutSeconds)) == .timedOut {
            if command.isRunning { command.terminate() }
            if finished.wait(timeout: .now() + 2) == .timedOut && command.isRunning {
                _ = kill(command.processIdentifier, SIGKILL)
                _ = finished.wait(timeout: .now() + 2)
            }
            throw InspectionProcessError.timedOut
        }

        try handle.close()
        guard command.terminationStatus == 0 else {
            throw InspectionProcessError.failed(command.terminationStatus)
        }
        let size = (try fileManager.attributesOfItem(atPath: output.path)[.size] as? NSNumber)?.intValue ?? 0
        guard size <= maximumOutputBytes else { throw InspectionProcessError.exceededOutputLimit }

        let data = try Data(contentsOf: output)
        guard let text = String(data: data, encoding: .utf8) else {
            throw InspectionProcessError.invalidUTF8
        }
        return text
    }
}
