import AppKit
import CleanJunkCore
import Foundation
import SwiftUI

@MainActor
final class WorkbenchModel: ObservableObject {
    @Published private(set) var snapshot = ScanSnapshot(items: [], skippedPaths: [])
    @Published private(set) var brew: BrewReport?
    @Published private(set) var workspaceReport: WorkspaceDependencyReport?
    @Published private(set) var inspectingWorkspace = false
    @Published private(set) var history: [TrashRecord] = []
    @Published private(set) var workspace: URL?
    @Published private(set) var scanning = false
    @Published private(set) var inspectingBrew = false
    @Published private(set) var trashing = false
    @Published var selectedItemPaths = Set<String>()
    @Published var errorMessage: String?
    @Published var brewError: String?
    @Published var notice: String?

    private let scanner = StorageScanner()
    private let removal = RemovalService()
    private let activity = ActivityLog()
    private let inspector = HomebrewInspector()
    private let workspaceInspector = WorkspaceDependencyInspector()

    var selectedEligible: [ScanItem] {
        snapshot.items.filter { selectedItemPaths.contains($0.id) && $0.isTrashEligible }
    }

    var selectedBytes: Int64 { selectedEligible.reduce(0) { $0 + $1.sizeBytes } }

    func refresh() async {
        guard !scanning else { return }
        scanning = true
        errorMessage = nil
        defer { scanning = false }
        do {
            let result = try await scanner.scan(workspace: workspace)
            snapshot = result
            selectedItemPaths.formIntersection(Set(result.items.map(\.id)))
        } catch is CancellationError {
            notice = "Scan cancelled."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func inspectHomebrew() async {
        guard !inspectingBrew else { return }
        inspectingBrew = true
        brewError = nil
        defer { inspectingBrew = false }
        do {
            brew = try await inspector.inspect()
        } catch {
            brewError = error.localizedDescription
        }
    }

    func inspectWorkspace() async {
        guard let workspace, !inspectingWorkspace else { return }
        inspectingWorkspace = true
        defer { inspectingWorkspace = false }
        do {
            workspaceReport = try await workspaceInspector.inspect(workspace: workspace)
        } catch {
            workspaceReport = nil
            errorMessage = error.localizedDescription
        }
    }

    func setWorkspace(_ url: URL) async {
        do {
            try ScanPolicy.validateWorkspace(url, home: FileManager.default.homeDirectoryForCurrentUser)
            workspace = url.standardizedFileURL
            selectedItemPaths = []
            workspaceReport = nil
            await refresh()
            await inspectWorkspace()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeWorkspace() async {
        workspace = nil
        workspaceReport = nil
        selectedItemPaths = []
        await refresh()
    }

    func loadHistory() async {
        history = await activity.all()
    }

    func trashSelected() async {
        guard !trashing, !selectedEligible.isEmpty else { return }
        trashing = true
        errorMessage = nil
        notice = nil
        defer { trashing = false }
        let targets = selectedEligible
        var moved = 0
        var failures: [String] = []
        for item in targets {
            do {
                let receipt = try await removal.trash(item, workspace: workspace)
                moved += 1
                do {
                    try await activity.append(receipt)
                } catch {
                    failures.append("Moved \(item.name), but history could not be saved: \(error.localizedDescription)")
                }
            } catch {
                failures.append("\(item.name): \(error.localizedDescription)")
            }
        }
        selectedItemPaths = []
        await loadHistory()
        await refresh()
        if workspace != nil { await inspectWorkspace() }
        if moved > 0 {
            notice = "\(moved) item(s) moved to Finder's Trash. Space is reclaimed only after Trash is emptied."
        }
        if !failures.isEmpty {
            errorMessage = failures.prefix(5).joined(separator: "\n")
        }
    }

    func reveal(_ item: ScanItem) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)])
    }

    func showTrash() {
        NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash"))
    }
}
