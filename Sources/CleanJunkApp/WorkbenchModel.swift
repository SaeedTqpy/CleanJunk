import AppKit
import CleanJunkCore
import Foundation
import SwiftUI

@MainActor
final class WorkbenchModel: ObservableObject {
    @Published private(set) var snapshot = ScanSnapshot(items: [], skippedPaths: [])
    @Published private(set) var brew: BrewReport?
    @Published private(set) var workspaceReport: WorkspaceDependencyReport?
    @Published private(set) var sourceReports: [String: SourceReferenceReport] = [:]
    @Published private(set) var analyzingSources = Set<String>()
    @Published private(set) var systemStorage: SystemStorageReport?
    @Published private(set) var deepSummary: DeepScanSummary?
    @Published private(set) var deepProgress: DeepScanProgress?
    @Published private(set) var deepRows: [DeepFileRecord] = []
    @Published private(set) var deepRunning = false
    @Published private(set) var installerReceipts: InstallerReceiptInventory?
    @Published private(set) var inspectingReceipts = false
    @Published private(set) var deepPage = 0
    @Published var deepError: String?
    @Published private(set) var inspectingSystemStorage = false
    @Published private(set) var inspectingWorkspace = false
    @Published private(set) var history: [TrashRecord] = []
    @Published private(set) var cleanupOperations: [CleanupOperation] = []
    @Published private(set) var journalCorrupted = false
    @Published private(set) var workspace: URL?
    @Published private(set) var scanning = false
    @Published private(set) var inspectingBrew = false
    @Published private(set) var trashing = false
    @Published var selectedItemPaths = Set<String>()
    @Published var errorMessage: String?
    @Published var brewError: String?
    @Published var notice: String?

    private let scanner = StorageScanner()
    private let executor = CleanupExecutor()
    private let activity = ActivityLog()
    private let inspector = HomebrewInspector()
    private let workspaceInspector = WorkspaceDependencyInspector()
    private let sourceInspector = SourceReferenceInspector()
    private let systemInspector = SystemStorageInspector()
    private let deepScanner = DeepStorageScanner()
    private let deepIndex = DeepScanIndex()
    private let receiptInspector = InstallerReceiptInspector()
    private var deepTask: Task<Void, Never>?
    private var deepQuery = ""
    private var deepAdvice: DeepCleanupAdvice?
    private var deepCategory: DeepStorageCategory?

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

    func loadInstallerReceipts() async {
        guard !inspectingReceipts else { return }
        inspectingReceipts = true
        defer { inspectingReceipts = false }
        do {
            installerReceipts = try await receiptInspector.inspect()
        } catch {
            deepError = "Installer receipt inventory unavailable: " + error.localizedDescription
        }
    }

    func loadDeepSummary() async {
        do {
            deepSummary = try await deepIndex.latestSummary()
            if deepSummary != nil { await searchDeepFiles() }
        } catch {
            deepError = error.localizedDescription
        }
    }

    func beginDeepScan(root: URL = URL(fileURLWithPath: "/")) {
        guard !deepRunning, !trashing else { return }
        deepTask = Task { await performDeepScan(root: root) }
    }

    func cancelDeepScan() {
        deepTask?.cancel()
    }

    private func performDeepScan(root: URL) async {
        deepRunning = true
        deepError = nil
        deepProgress = nil
        defer {
            deepRunning = false
            deepTask = nil
        }
        do {
            let report = try await deepScanner.scan(roots: [root]) { update in
                await MainActor.run { self.deepProgress = update }
            }
            deepSummary = report
            await searchDeepFiles()
        } catch is CancellationError {
            deepError = "Deep scan cancelled. Previous completed index was preserved."
        } catch {
            deepError = error.localizedDescription
        }
    }

    func searchDeepFiles(text: String? = nil,
                         advice: DeepCleanupAdvice? = nil,
                         category: DeepStorageCategory? = nil,
                         page: Int = 0) async {
        if let text { deepQuery = text }
        deepAdvice = advice
        deepCategory = category
        deepPage = max(0, page)
        guard deepSummary != nil else { deepRows = []; return }
        do {
            deepRows = try await deepIndex.search(deepQuery,
                advice: deepAdvice, category: deepCategory,
                limit: 150, offset: deepPage * 150)
        } catch {
            deepError = error.localizedDescription
        }
    }

    func exportDeepCSV(to url: URL) async {
        guard deepSummary != nil, !deepRunning else { return }
        do {
            try await deepIndex.exportCSV(to: url)
            notice = "File-by-file inventory exported to " + url.lastPathComponent
        } catch {
            deepError = "Export failed: " + error.localizedDescription
        }
    }

    func nextDeepPage() async {
        guard deepRows.count == 150 else { return }
        await searchDeepFiles(text: deepQuery, advice: deepAdvice,
                              category: deepCategory, page: deepPage + 1)
    }

    func previousDeepPage() async {
        guard deepPage > 0 else { return }
        await searchDeepFiles(text: deepQuery, advice: deepAdvice,
                              category: deepCategory, page: deepPage - 1)
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

    func inspectSystemStorage() async {
        guard !inspectingSystemStorage else { return }
        inspectingSystemStorage = true
        defer { inspectingSystemStorage = false }
        do {
            systemStorage = try await systemInspector.inspect()
        } catch {
            errorMessage = error.localizedDescription
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

    func analyzeSourceReferences(_ project: WorkspaceProject) async {
        guard let workspace, project.ecosystem == .node,
              !analyzingSources.contains(project.manifestPath) else { return }
        analyzingSources.insert(project.manifestPath)
        defer { analyzingSources.remove(project.manifestPath) }
        do {
            let result = try await sourceInspector.inspect(project: project, workspace: workspace)
            guard self.workspace == workspace else { return }
            sourceReports[project.id] = result
        } catch is CancellationError {
            notice = "Source analysis cancelled."
        } catch {
            errorMessage = "Source analysis failed: " + error.localizedDescription
        }
    }

    func setWorkspace(_ url: URL) async {
        do {
            try ScanPolicy.validateWorkspace(url, home: FileManager.default.homeDirectoryForCurrentUser)
            workspace = url.standardizedFileURL
            selectedItemPaths = []
            workspaceReport = nil
            sourceReports = [:]
            await refresh()
            await inspectWorkspace()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeWorkspace() async {
        workspace = nil
        workspaceReport = nil
        sourceReports = [:]
        selectedItemPaths = []
        await refresh()
    }

    func loadHistory() async {
        history = await activity.all()
        cleanupOperations = await executor.operations()
        journalCorrupted = await executor.journalIsCorrupted()
    }

    func trashSelected() async {
        guard !trashing, !scanning, !selectedEligible.isEmpty else { return }
        trashing = true
        errorMessage = nil
        notice = nil
        defer { trashing = false }
        let targets = selectedEligible
        var moved = 0
        var failures: [String] = []
        for item in targets {
            do {
                let result = try await executor.trash(item, workspace: workspace)
                moved += 1
                if let warning = result.auditWarning { failures.append(warning) }
                do {
                    try await activity.append(result.record)
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

    func restoreOperation(_ operation: CleanupOperation) async {
        guard !trashing, !scanning else { return }
        trashing = true
        errorMessage = nil
        defer { trashing = false }
        do {
            try await executor.restore(operation.id)
            notice = "Item restored to its original location."
            await loadHistory()
            await refresh()
        } catch {
            errorMessage = "Restore was not completed: " + error.localizedDescription +
                ". If the original path is occupied or Trash is on another volume, restore manually in Finder."
            await loadHistory()
        }
    }

    func reveal(_ item: ScanItem) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)])
    }

    func showTrash() {
        NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash"))
    }
}
