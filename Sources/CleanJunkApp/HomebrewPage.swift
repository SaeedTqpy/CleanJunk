import CleanJunkCore
import SwiftUI

struct HomebrewPage: View {
    @ObservedObject var model: WorkbenchModel
    @State private var search = ""
    @State private var candidatesOnly = false
    @State private var showDryRun = false

    private var packages: [BrewPackage] {
        (model.brew?.packages ?? []).filter {
            (!candidatesOnly || $0.isAutoremoveCandidate) &&
            (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) ||
             $0.description.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow(text: "DEPENDENCY INTELLIGENCE")
                    Text("Homebrew inventory")
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                    Text("Installed formulae, dependency intent, and Homebrew's own autoremove dry run.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task { await model.inspectHomebrew() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.glass)
                .disabled(model.inspectingBrew)
            }
            .padding(.top, 23)

            if let brew = model.brew {
                HStack(spacing: 14) {
                    MetricCard(label: "Formulae", value: "\(brew.packages.count)",
                               footnote: "Installed via Homebrew", symbol: "shippingbox", tint: CJStyle.mint)
                    MetricCard(label: "Casks", value: "\(brew.caskCount)",
                               footnote: "Applications in inventory", symbol: "app.dashed", tint: CJStyle.violet)
                    MetricCard(label: "Autoremove preview",
                               value: "\(brew.packages.filter(\.isAutoremoveCandidate).count)",
                               footnote: "Candidates from Homebrew dry run", symbol: "checkmark.shield",
                               tint: CJStyle.amber)
                }

                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search formulae", text: $search).textFieldStyle(.plain)
                    Toggle("Only autoremove candidates", isOn: $candidatesOnly)
                        .toggleStyle(.checkbox)
                    Button(showDryRun ? "Hide dry run" : "Show dry run") {
                        withAnimation(.snappy) { showDryRun.toggle() }
                    }
                    .buttonStyle(.glass)
                }
                .padding(12)
                .background(CJStyle.subtle, in: RoundedRectangle(cornerRadius: 14))

                if showDryRun {
                    SurfaceCard {
                        VStack(alignment: .leading, spacing: 9) {
                            Label("brew autoremove --dry-run", systemImage: "terminal")
                                .font(.headline)
                            ScrollView {
                                Text(brew.autoremoveDryRun.isEmpty ? "No dependency-only formulae are scheduled for removal." : brew.autoremoveDryRun)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 125)
                        }
                    }
                }

                Table(packages) {
                    TableColumn("Formula") { package in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(package.name).font(.subheadline.weight(.medium))
                            Text(package.description).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .padding(.vertical, 4)
                    }
                    TableColumn("Version") { package in
                        Text(package.version).font(.caption.monospaced())
                    }.width(min: 88, ideal: 122)
                    TableColumn("Requested") { package in
                        Text(package.explicitlyRequested.map { $0 ? "Yes" : "Dependency" } ?? "Unknown")
                            .font(.caption).foregroundStyle(.secondary)
                    }.width(min: 90, ideal: 110)
                    TableColumn("Dependents") { package in
                        Text("\(package.installedDependents)").monospacedDigit()
                    }.width(min: 74, ideal: 90)
                    TableColumn("Status") { package in
                        if package.isAutoremoveCandidate {
                            Pill(symbol: "exclamationmark.circle", text: "Review", tint: CJStyle.amber)
                        } else {
                            Text("Installed").font(.caption).foregroundStyle(.secondary)
                        }
                    }.width(min: 95, ideal: 130)
                }

                Label("Read-only mode: CleanJunk never uninstalls formulae. A dry-run candidate is not proof that external projects do not use it.",
                      systemImage: "lock.shield")
                    .font(.caption).foregroundStyle(.secondary).padding(.bottom, 16)
            } else {
                ContentUnavailableView(
                    model.inspectingBrew ? "Inspecting Homebrew" : "No package inventory",
                    systemImage: "shippingbox",
                    description: Text(model.brewError ?? "Use Refresh to inspect the Homebrew installation on this Mac.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.horizontal, 28)
    }
}
