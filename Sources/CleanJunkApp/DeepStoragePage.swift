import AppKit
import CleanJunkCore
import SwiftUI
import UniformTypeIdentifiers

/// All indexed entries are forensic metadata. This page never calls cleanup APIs.
struct DeepStoragePage: View {
    @ObservedObject var model: WorkbenchModel
    let reviewCaches: () -> Void
    @State private var search = ""
    @State private var receiptSearch = ""
    @State private var advice = "All"
    @State private var category = "All"
    @State private var confirmFullDisk = false

    private var selectedAdvice: DeepCleanupAdvice? {
        DeepCleanupAdvice(rawValue: advice)
    }

    private var selectedCategory: DeepStorageCategory? {
        DeepStorageCategory(rawValue: category)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                explanation

                if model.deepRunning {
                    scanProgress
                }

                if let summary = model.deepSummary {
                    summaryCards(summary)
                    categoryBreakdown(summary)
                    macOSReceipts
                    indexedFiles
                    coverage(summary)
                } else if !model.deepRunning {
                    ContentUnavailableView("No complete full-disk index",
                                           systemImage: "internaldrive",
                                           description: Text("Run a read-only scan to inventory each accessible file, including application contents and hidden directories."))
                        .frame(minHeight: 250)
                }

                if let error = model.deepError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(CJStyle.amber)
                        .textSelection(.enabled)
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 32)
        }
        .confirmationDialog(
            "Scan every accessible file on this Mac?",
            isPresented: $confirmFullDisk, titleVisibility: .visible
        ) {
            Button("Start full read-only scan") {
                model.beginDeepScan()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This may scan millions of files, use disk resources and take considerable time. No files will be deleted. macOS access controls remain enforced; inaccessible regions will be reported.")
        }
        .task { if model.deepSummary == nil { await model.loadDeepSummary() } }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 15) {
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow(text: "FILE-BY-FILE STORAGE FORENSICS")
                Text("Full Mac Intelligence")
                    .font(.system(size: 31, weight: .semibold, design: .rounded))
                Text("Index accessible files, app containers, installed packages and hidden caches. Understand before removing.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.deepRunning {
                Button {
                    model.cancelDeepScan()
                } label: {
                    Label("Cancel", systemImage: "stop.circle")
                }
                .buttonStyle(.glass)
            } else {
                Button {
                    confirmFullDisk = true
                } label: {
                    Label("Scan entire Mac", systemImage: "internaldrive")
                }
                .buttonStyle(.glassProminent)
                .disabled(model.trashing)
                Button {
                    let picker = NSOpenPanel()
                    picker.canChooseDirectories = true
                    picker.canChooseFiles = false
                    picker.allowsMultipleSelection = false
                    picker.message = "Select an external volume or a specific folder to scan"
                    if picker.runModal() == .OK, let url = picker.url {
                        model.beginDeepScan(root: url)
                    }
                } label: {
                    Label("Choose folder", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.glass)
            }
        }
        .padding(.top, 23)
    }

    private var explanation: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 10) {
                    Image(systemName: "lock.shield.fill")
                        .foregroundStyle(CJStyle.mint)
                    Text("This is a complete inventory attempt, not a deletion command.")
                        .font(.subheadline.weight(.semibold))
                }
                Text("Rebuildable means a known generated cache, not an invitation to delete it automatically. App databases, source code, operating-system files, installers and unknown files are preserved. Full Disk Access can increase read coverage; it cannot bypass macOS System Integrity Protection.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Label("Review Full Disk Access", systemImage: "gearshape")
                    }
                    .buttonStyle(.glass)
                    Spacer()
                    Text("Metadata only · Stored locally · No automatic removal")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var scanProgress: some View {
        SurfaceCard {
            HStack(alignment: .top, spacing: 14) {
                ProgressView().controlSize(.small)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Indexing files and directories…")
                        .font(.subheadline.weight(.medium))
                    if let progress = model.deepProgress {
                        Text("\(progress.examinedEntries.formatted()) entries · \(progress.indexedFiles.formatted()) files · \(progress.allocatedBytes.cjSize)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text(progress.currentDirectory)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Text("Discovering the filesystem. Total progress is unknown until the scan finishes.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
        }
    }

    private func summaryCards(_ summary: DeepScanSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                MetricCard(label: "Files indexed",
                           value: summary.filesIndexed.formatted(),
                           footnote: "Plus \(summary.directoriesIndexed.formatted()) folders",
                           symbol: "doc.on.doc.fill", tint: CJStyle.mint)
                MetricCard(label: "Measured allocation",
                           value: summary.allocatedBytes.cjSize,
                           footnote: "Excludes duplicate hard links; APFS clones may share blocks",
                           symbol: "internaldrive.fill", tint: CJStyle.violet)
                MetricCard(label: "Rebuildable footprint",
                           value: summary.rebuildableCandidateBytes.cjSize,
                           footnote: "Known generated caches; still require user approval",
                           symbol: "checkmark.shield", tint: CJStyle.amber)
            }
            HStack {
                Label(summary.coverageComplete ? "Accessible scan coverage completed" : "Partial coverage — see inaccessible paths",
                      systemImage: summary.coverageComplete ? "checkmark.circle" : "exclamationmark.triangle")
                    .foregroundStyle(summary.coverageComplete ? CJStyle.mint : CJStyle.amber)
                Spacer()
                Text("Scan ended \(summary.finishedAt.formatted(date: .abbreviated, time: .shortened))")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
    }

    private func categoryBreakdown(_ summary: DeepScanSummary) -> some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Eyebrow(text: "OWNERSHIP AND STORAGE TYPES")
                        Text("Where your files belong")
                            .font(.title3.weight(.semibold))
                    }
                    Spacer()
                    Text("\(summary.entriesExamined.formatted()) entries examined")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(summary.categories) { group in
                    HStack(spacing: 12) {
                        Text(group.category.rawValue)
                            .frame(width: 160, alignment: .leading)
                        GeometryReader { geo in
                            Capsule().fill(CJStyle.subtle)
                                .overlay(alignment: .leading) {
                                    Capsule().fill(CJStyle.mint.opacity(0.8))
                                        .frame(width: max(2, geo.size.width * CGFloat(group.allocatedBytes) /
                                                         CGFloat(max(1, summary.allocatedBytes))))
                                }
                        }
                        .frame(height: 8)
                        Text(group.allocatedBytes.cjSize)
                            .monospacedDigit()
                            .frame(width: 95, alignment: .trailing)
                        Text("\(group.entries.formatted())")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(width: 100, alignment: .trailing)
                    }
                    .font(.caption)
                }
            }
        }
    }

    private var macOSReceipts: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Eyebrow(text: "MACOS INSTALLER PACKAGE RECEIPTS")
                        Text("Installed package evidence")
                            .font(.title3.weight(.semibold))
                        Text("Reads pkgutil receipts; Homebrew is available separately under Packages.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        Task { await model.loadInstallerReceipts() }
                    } label: {
                        Label("Read pkgutil inventory", systemImage: "shippingbox")
                    }
                    .buttonStyle(.glass)
                    .disabled(model.inspectingReceipts || model.deepRunning)
                }
                if model.inspectingReceipts {
                    ProgressView("Reading package receipts…").controlSize(.small)
                }
                if let receipts = model.installerReceipts {
                    HStack {
                        Pill(symbol: "shippingbox",
                             text: "\(receipts.packageIDs.count.formatted()) package receipts",
                             tint: CJStyle.violet)
                        Spacer()
                        Text("Local, read-only · No uninstallation")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    TextField("Find an installer package identifier", text: $receiptSearch)
                        .textFieldStyle(.roundedBorder)
                    let matching = receipts.packageIDs
                        .filter { receiptSearch.isEmpty ||
                            $0.localizedCaseInsensitiveContains(receiptSearch) }
                    ForEach(Array(matching.prefix(15)), id: \.self) { identifier in
                        Text(identifier)
                            .font(.system(size: 12, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    if matching.count > 15 {
                        Text("Showing 15 of \(matching.count.formatted()) matching receipts.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Text(receipts.limitations)
                        .font(.caption2).foregroundStyle(.secondary)
                } else {
                    Text("The system installer receipt list is optional and is not a proof of a package's active usage.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var indexedFiles: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Eyebrow(text: "PERSISTENT SEARCHABLE FILE INDEX")
                    Text("Every indexed file")
                        .font(.title3.weight(.semibold))
                    Text("Sorted by allocated size. 150 rows per page. All metadata remains in your local SQLite index.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    let panel = NSSavePanel()
                    panel.nameFieldStringValue = "CleanJunk-Deep-Inventory.csv"
                    panel.allowedContentTypes = [.commaSeparatedText]
                    if panel.runModal() == .OK, let url = panel.url {
                        Task { await model.exportDeepCSV(to: url) }
                    }
                } label: {
                    Label("Export all CSV", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.glass)
                .disabled(model.deepRunning)
            }
            HStack(spacing: 9) {
                TextField("Search filename, path or app identifier", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { applyFilters() }
                Picker("Recommendation", selection: $advice) {
                    Text("All recommendations").tag("All")
                    ForEach(DeepCleanupAdvice.allCases) { item in
                        Text(item.rawValue).tag(item.rawValue)
                    }
                }
                .frame(width: 205)
                Picker("Category", selection: $category) {
                    Text("All categories").tag("All")
                    ForEach(DeepStorageCategory.allCases) { item in
                        Text(item.rawValue).tag(item.rawValue)
                    }
                }
                .frame(width: 180)
                Button("Search") { applyFilters() }
                    .buttonStyle(.glass)
            }

            Table(model.deepRows) {
                TableColumn("Name / path") { item in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 7) {
                            Image(systemName: item.isDirectory ? "folder" :
                                  (item.isLink ? "link" : "doc"))
                                .foregroundStyle(CJStyle.mint)
                            Text(item.name).font(.subheadline.weight(.medium)).lineLimit(1)
                        }
                        Text(item.path)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .help(item.evidence + "\n" + item.path)
                    .contextMenu {
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)])
                        }
                        Button("Copy path") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(item.path, forType: .string)
                        }
                    }
                }
                TableColumn("Owner") { item in
                    Text(item.owner).font(.caption).lineLimit(1)
                        .help(item.category.rawValue)
                }.width(min: 105, ideal: 155)
                TableColumn("Assessment") { item in
                    Text(item.advice.rawValue)
                        .font(.caption)
                        .foregroundStyle(item.advice == .rebuildable ? CJStyle.mint :
                                          (item.advice == .preserve ? CJStyle.amber : .secondary))
                        .help(item.evidence)
                }.width(min: 130, ideal: 170)
                TableColumn("Allocated") { item in
                    Text(item.allocatedBytes.cjSize).font(.caption.monospacedDigit())
                }.width(min: 80, ideal: 115)
            }
            .frame(height: 440)

            HStack {
                Label("Read-only index: this screen cannot delete any file.",
                      systemImage: "info.circle")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button("Previous") {
                    Task { await model.previousDeepPage() }
                }
                .disabled(model.deepPage == 0)
                Button("Next") {
                    Task { await model.nextDeepPage() }
                }
                .disabled(model.deepRows.count < 150)
                Text("Page \(model.deepPage + 1)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func coverage(_ summary: DeepScanSummary) -> some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Scan coverage and limits")
                    .font(.headline)
                HStack {
                    Text("\(summary.inaccessibleEntries.formatted()) access errors")
                    Text("·")
                    Text("\(summary.hardlinkDuplicates.formatted()) duplicate hard links")
                    Text("·")
                    Text(summary.limitsReached ? "Entry/time limit reached" : "Within scan limits")
                }
                .font(.caption).foregroundStyle(.secondary)
                if !summary.warnings.isEmpty {
                    DisclosureGroup("See \(summary.warnings.count) recorded exclusions or warnings") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(summary.warnings, id: \.self) { warning in
                                Text(warning)
                                    .font(.caption2)
                                    .textSelection(.enabled)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.top, 7)
                    }
                }
                Text("Apple privacy controls, protected system data, APFS snapshots, virtual mounts and inaccessible user accounts prevent a guarantee of 100% filesystem coverage. Exclusions are reported rather than hidden.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func applyFilters() {
        Task {
            await model.searchDeepFiles(text: search, advice: selectedAdvice,
                                        category: selectedCategory, page: 0)
        }
    }
}
