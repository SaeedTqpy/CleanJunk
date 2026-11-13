import AppKit
import CleanJunkCore
import SwiftUI

private enum Destination: String, CaseIterable, Hashable, Identifiable {
    case overview = "Overview"
    case explorer = "Space Explorer"
    case deep = "Full Mac Scan"
    case system = "System Data"
    case developers = "Developer Caches"
    case homebrew = "Packages"
    case history = "Activity"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .overview: return "square.grid.2x2.fill"
        case .explorer: return "internaldrive.fill"
        case .system: return "externaldrive.fill"
        case .developers: return "curlybraces.square.fill"
        case .homebrew: return "shippingbox.fill"
        case .history: return "clock.arrow.circlepath"
        }
    }
}

struct WorkbenchView: View {
    @StateObject private var model = WorkbenchModel()
    @State private var selection: Destination? = .overview
    @State private var showConfirmation = false

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("CLEANJUNK") {
                    ForEach(Destination.allCases) { destination in
                        NavigationLink(value: destination) {
                            Label(destination.rawValue, systemImage: destination.icon)
                                .padding(.vertical, 5)
                        }
                    }
                }
                Section("STATUS") {
                    Label(model.scanning ? "Scanning disk…" : "Local analysis", systemImage: "circle.dotted")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Label("Privacy by design", systemImage: "lock.shield")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationSplitViewColumnWidth(min: 205, ideal: 225, max: 270)
            .listStyle(.sidebar)
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 9) {
                    Image(systemName: "circle.hexagongrid.fill")
                        .font(.title3)
                        .foregroundStyle(CJStyle.mint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("CLEANJUNK").font(.system(size: 11, weight: .bold, design: .rounded))
                        Text("Developer Edition").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 17)
                .padding(.vertical, 15)
            }
        } detail: {
            Group {
                switch selection ?? .overview {
                case .overview: OverviewPage(model: model, browse: { selection = .explorer })
                case .explorer: ArtifactPage(model: model, filter: nil)
                case .system: SystemDataPage(model: model)
                case .developers: DeveloperPage(model: model)
                case .homebrew: HomebrewPage(model: model)
                case .history: HistoryPage(model: model)
                }
            }
            .navigationTitle((selection ?? .overview).rawValue)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    GlassEffectContainer(spacing: 8) {
                        Button {
                            Task { await model.refresh() }
                        } label: {
                            Label(model.scanning ? "Scanning" : "Scan", systemImage: "arrow.clockwise")
                        }
                        .disabled(model.scanning || model.trashing)
                        .buttonStyle(.glass)

                        if !model.selectedEligible.isEmpty {
                            Button {
                                showConfirmation = true
                            } label: {
                                Label("Review cleanup", systemImage: "trash")
                            }
                            .buttonStyle(.glassProminent)
                            .tint(CJStyle.mint)
                            .disabled(model.trashing || model.scanning)
                        }
                    }
                }
            }
        }
        .tint(CJStyle.mint)
        .confirmationDialog("Move selected artifacts to Trash?",
                            isPresented: $showConfirmation,
                            titleVisibility: .visible) {
            Button("Move \(model.selectedEligible.count) item(s) to Trash", role: .destructive) {
                Task { await model.trashSelected() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Estimated selected footprint: \(model.selectedBytes.cjSize). Project directories may require rebuilding. Items are moved to Finder's Trash, never permanently deleted.")
        }
        .alert("CleanJunk", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .task {
            await model.refresh()
            await model.loadHistory()
            await model.inspectHomebrew()
        }
    }
}

struct OverviewPage: View {
    @ObservedObject var model: WorkbenchModel
    var browse: () -> Void

    private var groups: [(ArtifactCategory, Int64)] {
        ArtifactCategory.allCases.map { category in
            (category, model.snapshot.items.filter { $0.category == category }
                .reduce(Int64(0)) { $0 + $1.sizeBytes })
        }.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        Eyebrow(text: "SYSTEM INTELLIGENCE")
                        Text("Make room for\nwhat matters.")
                            .font(.system(size: 39, weight: .semibold, design: .rounded))
                            .tracking(-1.5)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Understand your development footprint before you remove a single file.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: 460, alignment: .leading)
                    }
                    Spacer(minLength: 8)
                    ZStack {
                        Circle().fill(CJStyle.mint.opacity(0.13))
                            .frame(width: 148, height: 148).blur(radius: 14)
                        Image(systemName: "internaldrive")
                            .font(.system(size: 74, weight: .ultraLight))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(CJStyle.mint)
                    }
                    .accessibilityHidden(true)
                }
                .padding(.top, 24)

                GlassEffectContainer(spacing: 12) {
                    HStack(spacing: 12) {
                        Button {
                            Task { await model.refresh() }
                        } label: {
                            Label(model.scanning ? "Analyzing…" : "Run Smart Scan",
                                  systemImage: model.scanning ? "hourglass" : "sparkle.magnifyingglass")
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                        }
                        .buttonStyle(.glassProminent)
                        .disabled(model.scanning)
                        Button(action: browse) {
                            Label("Explore findings", systemImage: "arrow.up.right")
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                        }
                        .buttonStyle(.glass)
                        Spacer()
                    }
                }

                if let notice = model.notice {
                    Label(notice, systemImage: "checkmark.circle")
                        .font(.caption).foregroundStyle(CJStyle.mint)
                }

                HStack(spacing: 14) {
                    MetricCard(label: "Scanned footprint",
                               value: model.snapshot.totalBytes.cjSize,
                               footnote: "Measured scan scopes, not total System Data",
                               symbol: "internaldrive.fill", tint: CJStyle.mint)
                    MetricCard(label: "Reviewable artifacts",
                               value: "\(model.snapshot.items.filter(\.isTrashEligible).count)",
                               footnote: "Each requires explicit confirmation",
                               symbol: "square.stack.3d.up", tint: CJStyle.violet)
                    MetricCard(label: "Reviewable footprint",
                               value: model.snapshot.reviewableBytes.cjSize,
                               footnote: "Not a guarantee of reclaimed space",
                               symbol: "arrow.down.to.line.compact", tint: CJStyle.amber)
                }

                HStack(alignment: .top, spacing: 16) {
                    SurfaceCard {
                        VStack(alignment: .leading, spacing: 18) {
                            HStack {
                                VStack(alignment: .leading, spacing: 6) {
                                    Eyebrow(text: "SPACE DISTRIBUTION")
                                    Text("Where your space goes").font(.title3.weight(.semibold))
                                }
                                Spacer()
                                Text("ESTIMATED").font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.tertiary)
                            }
                            if groups.isEmpty {
                                ContentUnavailableView("No analysis yet",
                                    systemImage: "internaldrive",
                                    description: Text("Run a scan to discover development caches and other artifacts."))
                                    .frame(minHeight: 195)
                            } else {
                                ForEach(groups, id: \.0) { category, bytes in
                                    VStack(spacing: 8) {
                                        HStack {
                                            Label(category.rawValue, systemImage: category.symbol)
                                                .font(.subheadline)
                                            Spacer()
                                            Text(bytes.cjSize).font(.caption.monospacedDigit())
                                                .foregroundStyle(.secondary)
                                        }
                                        GeometryReader { geo in
                                            ZStack(alignment: .leading) {
                                                Capsule().fill(.primary.opacity(0.07))
                                                Capsule().fill(CJStyle.color(for: category))
                                                    .frame(width: geo.size.width * CGFloat(bytes) / CGFloat(max(1, model.snapshot.totalBytes)))
                                            }
                                        }
                                        .frame(height: 7)
                                    }
                                }
                            }
                        }
                    }
                    SurfaceCard {
                        VStack(alignment: .leading, spacing: 15) {
                            Eyebrow(text: "CLEANUP GUARDRAILS")
                            Text("Safety is the feature.")
                                .font(.title3.weight(.semibold))
                            securityLine("shield.lefthalf.filled", "No root access", "System folders are outside cleanup policy.")
                            securityLine("checkmark.seal", "Manual approval", "Every artifact is reviewed before Trash.")
                            securityLine("arrow.uturn.backward.circle", "Finder's Trash", "No irreversible deletion in the app.")
                            securityLine("bolt.horizontal.circle", "Package-aware", "Homebrew dependencies are inspected, not guessed.")
                        }
                    }
                }

                HStack {
                    Image(systemName: model.snapshot.isEstimateComplete ? "checkmark.circle" : "exclamationmark.triangle")
                        .foregroundStyle(model.snapshot.isEstimateComplete ? CJStyle.mint : CJStyle.amber)
                    Text(model.snapshot.isEstimateComplete
                         ? "Scanned scope estimates complete. Actual recoverable disk space may vary."
                         : "Some locations were inaccessible or exceeded analysis limits. Displayed sizes are partial.")
                        .foregroundStyle(.secondary).font(.caption)
                }
                .padding(.bottom, 24)
            }
            .padding(.horizontal, 28)
        }
    }

    private func securityLine(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).frame(width: 20).foregroundStyle(CJStyle.mint)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
