import CleanJunkCore
import SwiftUI

struct SystemDataPage: View {
    @ObservedObject var model: WorkbenchModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Eyebrow(text: "MACOS STORAGE FORENSICS")
                        Text("Understand System Data")
                            .font(.system(size: 32, weight: .semibold, design: .rounded))
                        Text("Read-only disk capacity and local Time Machine snapshot diagnostics.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        Task { await model.inspectSystemStorage() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.glass)
                    .disabled(model.inspectingSystemStorage)
                }
                .padding(.top, 24)

                SurfaceCard {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(CJStyle.mint)
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("System Data is not a folder.")
                                .font(.title3.weight(.semibold))
                            Text("The macOS Storage category aggregates many kinds of files. Disk capacity and snapshot counts below do not equal its reported size, and snapshots are not safe to delete like regular files.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }

                if let report = model.systemStorage {
                    HStack(spacing: 14) {
                        MetricCard(label: "Volume capacity",
                                   value: report.totalCapacityBytes.cjSize,
                                   footnote: "Filesystem-reported capacity",
                                   symbol: "internaldrive.fill", tint: CJStyle.mint)
                        MetricCard(label: "Occupied capacity",
                                   value: report.usedCapacityBytes.cjSize,
                                   footnote: "All categories, not System Data alone",
                                   symbol: "square.stack.3d.up.fill", tint: CJStyle.violet)
                        MetricCard(label: "Filesystem free",
                                   value: report.freeCapacityBytes.cjSize,
                                   footnote: "May differ from purgeable space",
                                   symbol: "arrow.down.right.circle.fill", tint: CJStyle.amber)
                    }

                    SurfaceCard {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                VStack(alignment: .leading, spacing: 5) {
                                    Eyebrow(text: "APFS / TIME MACHINE")
                                    Text("Local snapshots").font(.title3.weight(.semibold))
                                }
                                Spacer()
                                Pill(symbol: "clock.arrow.circlepath",
                                     text: "\(report.localSnapshotNames.count) found",
                                     tint: CJStyle.violet)
                            }
                            if report.localSnapshotNames.isEmpty {
                                Label("No Time Machine local snapshots were listed, or inspection is unavailable.",
                                      systemImage: "checkmark.shield")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            } else {
                                ForEach(report.localSnapshotNames.prefix(25), id: \.self) { name in
                                    HStack {
                                        Image(systemName: "externaldrive.badge.timemachine")
                                            .foregroundStyle(CJStyle.violet)
                                        Text(name)
                                            .font(.system(size: 12, design: .monospaced))
                                            .textSelection(.enabled)
                                        Spacer()
                                    }
                                    .padding(.vertical, 3)
                                }
                                if report.localSnapshotNames.count > 25 {
                                    Text("Showing 25 snapshot identifiers.")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Divider()
                            Text("Snapshots are managed by macOS. CleanJunk never removes local snapshots or estimates how many bytes removing one would reclaim.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }

                    if !report.warnings.isEmpty {
                        SurfaceCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Diagnostic limitations", systemImage: "exclamationmark.triangle")
                                    .foregroundStyle(CJStyle.amber)
                                ForEach(report.warnings, id: \.self) { warning in
                                    Text(warning).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    Text("Inspected \(report.inspectedAt.formatted(date: .abbreviated, time: .shortened)). No mutation or snapshot deletion performed.")
                        .font(.caption2).foregroundStyle(.tertiary)
                } else {
                    HStack(spacing: 11) {
                        if model.inspectingSystemStorage {
                            ProgressView().controlSize(.small)
                        }
                        Text(model.inspectingSystemStorage ? "Reading filesystem diagnostics…" : "Run Refresh to inspect this Mac.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 28)
        }
        .task {
            if model.systemStorage == nil { await model.inspectSystemStorage() }
        }
    }
}
