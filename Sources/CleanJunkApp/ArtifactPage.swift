import AppKit
import CleanJunkCore
import SwiftUI

struct ArtifactPage: View {
    @ObservedObject var model: WorkbenchModel
    let filter: ArtifactCategory?
    @State private var search = ""
    @State private var selectionFilter = "All"

    private var visibleItems: [ScanItem] {
        model.snapshot.items.filter { item in
            let categoryMatches = filter == nil || item.category == filter
            let riskMatches = selectionFilter == "All" ||
                (selectionFilter == "Reviewable" && item.isTrashEligible) ||
                (selectionFilter == "Protected" && !item.isTrashEligible)
            let textMatches = search.isEmpty ||
                item.name.localizedCaseInsensitiveContains(search) ||
                item.path.localizedCaseInsensitiveContains(search)
            return categoryMatches && riskMatches && textMatches
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow(text: filter == nil ? "FORENSIC STORAGE VIEW" : "DEVELOPER ARTIFACTS")
                Text(filter == nil ? "Space Explorer" : "Developer artifacts")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                Text("Select individual items to move them to Finder's Trash. Protected data is never selectable for cleanup.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(.top, 23)

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search files and directories", text: $search)
                    .textFieldStyle(.plain)
                if !search.isEmpty {
                    Button { search = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }.buttonStyle(.plain)
                }
                Divider().frame(height: 20)
                Picker("Filter", selection: $selectionFilter) {
                    Text("All").tag("All")
                    Text("Reviewable").tag("Reviewable")
                    Text("Protected").tag("Protected")
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 260)
            }
            .padding(12)
            .background(CJStyle.subtle, in: RoundedRectangle(cornerRadius: 14))

            if model.scanning {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Measuring selected cache locations…")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
            }
            HStack {
                Text("\(visibleItems.count) findings")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if !model.selectedEligible.isEmpty {
                    Pill(symbol: "checkmark.circle",
                         text: "\(model.selectedEligible.count) selected • \(model.selectedBytes.cjSize)",
                         tint: CJStyle.mint)
                    Button("Clear selection") { model.selectedItemPaths = [] }
                        .font(.caption).buttonStyle(.plain)
                }
            }

            Table(visibleItems, selection: $model.selectedItemPaths) {
                TableColumn("Artifact") { item in
                    HStack(spacing: 10) {
                        Image(systemName: item.category.symbol)
                            .font(.system(size: 14))
                            .foregroundStyle(CJStyle.color(for: item.category))
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.name).font(.subheadline.weight(.medium))
                                .lineLimit(1)
                            Text(item.path).font(.caption2).foregroundStyle(.tertiary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                    }
                    .padding(.vertical, 5)
                    .help(item.rationale)
                    .contextMenu {
                        Button("Show in Finder") { model.reveal(item) }
                        Button("Copy path") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(item.path, forType: .string)
                        }
                    }
                }
                TableColumn("Category") { item in
                    Text(item.category.rawValue).font(.caption).foregroundStyle(.secondary)
                }.width(min: 120, ideal: 155)
                TableColumn("Risk") { item in
                    Pill(symbol: item.risk == .protected ? "lock.fill" : "circle.fill",
                         text: item.risk.label, tint: item.risk.cjColor)
                }.width(min: 110, ideal: 155)
                TableColumn("Footprint") { item in
                    Text((item.isSizeComplete ? "" : "≥ ") + item.sizeBytes.cjSize)
                        .monospacedDigit()
                }.width(min: 85, ideal: 120)
            }
            .contextMenu(forSelectionType: String.self) { selected in
                if let path = selected.first,
                   let item = model.snapshot.items.first(where: { $0.path == path }) {
                    Button("Reveal in Finder") { model.reveal(item) }
                }
            }
            .overlay {
                if visibleItems.isEmpty && !model.scanning {
                    ContentUnavailableView("No matching artifacts", systemImage: "sparkle.magnifyingglass",
                                           description: Text("Change the filters or run a new scan."))
                }
            }

            HStack {
                Label("Footprints are estimates. APFS shared blocks and sparse files can affect space reclaimed.",
                      systemImage: "info.circle")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button("Reveal selected in Finder") {
                    if let item = visibleItems.first(where: { model.selectedItemPaths.contains($0.id) }) {
                        model.reveal(item)
                    }
                }
                .disabled(model.selectedItemPaths.isEmpty)
                .buttonStyle(.glass)
            }
            .padding(.bottom, 15)
        }
        .padding(.horizontal, 28)
    }
}

struct DeveloperPage: View {
    @ObservedObject var model: WorkbenchModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 7) {
                    Eyebrow(text: "PROJECT-AWARE CLEANUP")
                    Text("Developer workspaces").font(.system(size: 30, weight: .semibold, design: .rounded))
                    Text("Inspect generated directories without touching your source code.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    let panel = NSOpenPanel()
                    panel.message = "Choose a specific project or development workspace"
                    panel.prompt = "Analyze folder"
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.allowsMultipleSelection = false
                    if panel.runModal() == .OK, let url = panel.url {
                        Task { await model.setWorkspace(url) }
                    }
                } label: {
                    Label("Choose workspace", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.glassProminent)
            }
            .padding(.top, 24)

            if let workspace = model.workspace {
                HStack(spacing: 10) {
                    Image(systemName: "folder.fill").foregroundStyle(CJStyle.mint)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(workspace.lastPathComponent).font(.headline)
                        Text(workspace.path).font(.caption2).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                    Button("Remove") { Task { await model.removeWorkspace() } }
                        .buttonStyle(.glass)
                }
                .padding(14)
                .background(CJStyle.mint.opacity(0.09), in: RoundedRectangle(cornerRadius: 15))
            } else {
                Label("No workspace selected. Global developer caches are still included below.",
                      systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }

            WorkspaceDependencyPanel(model: model)

            ArtifactPage(model: model, filter: nil)
                .padding(.horizontal, -28)
        }
        .padding(.horizontal, 28)
    }
}
