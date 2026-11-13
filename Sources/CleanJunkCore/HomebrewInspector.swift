import Foundation

public struct BrewFormula: Decodable, Sendable {
    public let name: String
    public let desc: String?
    public let dependencies: [String]?
    public let installed: [BrewInstallation]

    public struct BrewInstallation: Decodable, Sendable {
        public let version: String
        public let installed_on_request: Bool?
        public let installed_as_dependency: Bool?
        public let runtime_dependencies: [RuntimeDependency]?
    }

    public struct RuntimeDependency: Decodable, Sendable {
        public let full_name: String
    }
}

public struct BrewInventory: Decodable, Sendable {
    public let formulae: [BrewFormula]
    public let casks: [BrewCask]

    public struct BrewCask: Decodable, Sendable {
        public let token: String?
        public let name: [String]?
    }
}

public struct BrewPackage: Identifiable, Sendable {
    public let name: String
    public let description: String
    public let version: String
    public let explicitlyRequested: Bool?
    public let installedDependents: Int
    public let isAutoremoveCandidate: Bool

    public var id: String { name }
}

public struct BrewReport: Sendable {
    public let packages: [BrewPackage]
    public let caskCount: Int
    public let autoremoveDryRun: String
    public let executablePath: String
}

public enum BrewInspectionError: LocalizedError {
    case notInstalled
    case failed(String)
    case invalidOutput

    public var errorDescription: String? {
        switch self {
        case .notInstalled: return "Homebrew was not found in its standard locations."
        case .failed(let reason): return "Homebrew inspection failed: \(reason)"
        case .invalidOutput: return "Homebrew returned unrecognized inventory data."
        }
    }
}

public actor HomebrewInspector {
    public init() {}

    public func inspect() throws -> BrewReport {
        let paths = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
        guard let binary = paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw BrewInspectionError.notInstalled
        }
        let rawInventory = try command(binary, ["info", "--json=v2", "--installed"])
        guard let json = rawInventory.data(using: .utf8),
              let inventory = try? JSONDecoder().decode(BrewInventory.self, from: json) else {
            throw BrewInspectionError.invalidOutput
        }
        let autoremove = (try? command(binary, ["autoremove", "--dry-run"])) ?? "Dry-run unavailable"
        let candidateNames = Set(autoremove.split(separator: "\n").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        })
        let names = Set(inventory.formulae.map(\.name))
        var useCount: [String: Int] = [:]
        for formula in inventory.formulae {
            let runtime = formula.installed.last?.runtime_dependencies?.map(\.full_name)
            for name in runtime ?? formula.dependencies ?? [] where names.contains(name) {
                useCount[name, default: 0] += 1
            }
        }
        let packages = inventory.formulae.map { formula in
            let install = formula.installed.last
            return BrewPackage(name: formula.name,
                               description: formula.desc ?? "No description",
                               version: install?.version ?? "Unknown",
                               explicitlyRequested: install?.installed_on_request,
                               installedDependents: useCount[formula.name, default: 0],
                               isAutoremoveCandidate: candidateNames.contains(formula.name))
        }.sorted { a, b in
            if a.isAutoremoveCandidate != b.isAutoremoveCandidate {
                return a.isAutoremoveCandidate && !b.isAutoremoveCandidate
            }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
        return BrewReport(packages: packages, caskCount: inventory.casks.count,
                          autoremoveDryRun: autoremove, executablePath: binary)
    }

    private func command(_ path: String, _ arguments: [String]) throws -> String {
        try SafeProcessRunner.run(
            executable: URL(fileURLWithPath: path),
            arguments: arguments,
            environmentOverrides: [
                "HOMEBREW_NO_AUTO_UPDATE": "1",
                "HOMEBREW_NO_ANALYTICS": "1",
                "HOMEBREW_NO_COLOR": "1"
            ],
            timeoutSeconds: 35
        )
    }

}
