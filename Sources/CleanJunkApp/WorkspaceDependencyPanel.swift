import CleanJunkCore
import SwiftUI

/// Provenance is intentionally read-only; declarations are not proof of runtime usage.
struct WorkspaceDependencyPanel: View {
    @ObservedObject var model: WorkbenchModel
    @State private var expanded = false

    var body: some View {
        if let report = model.workspaceReport {
            SurfaceCard {
                VStack(alignment: .leading, spacing: 13) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Eyebrow(text: "DEPENDENCY PROVENANCE")
                            Text("Detected projects").font(.headline)
                        }
                        Spacer()
                        Pill(symbol: "folder.badge.gearshape",
                             text: "\(report.projects.count) projects",
                             tint: CJStyle.violet)
                        Pill(symbol: "shippingbox",
                             text: "\(report.declaredDependencies) declarations",
                             tint: CJStyle.mint)
                        Button {
                            Task { await model.inspectWorkspace() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .help("Refresh project inventory")
                        .buttonStyle(.glass)
                        .disabled(model.inspectingWorkspace)
                    }

                    Text("Declarations are not evidence of actual code usage. No packages are uninstalled by this analysis.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !report.isComplete {
                        Label("Project discovery was incomplete. Check inspection warnings.",
                              systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(CJStyle.amber)
                    }

                    DisclosureGroup(isExpanded: $expanded) {
                        VStack(alignment: .leading, spacing: 10) {
                            if report.projects.isEmpty {
                                Text("No supported project manifest found in this workspace.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            ForEach(report.projects.prefix(8)) { project in
                                projectRow(project)
                            }
                            if report.projects.count > 8 {
                                Text("Showing the first 8 of \(report.projects.count) projects.")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            ForEach(report.warnings.prefix(4), id: \.self) { warning in
                                Label(warning, systemImage: "exclamationmark.triangle")
                                    .font(.caption2).foregroundStyle(CJStyle.amber)
                            }
                        }
                        .padding(.top, 9)
                    } label: {
                        Text("Review project manifests and lockfiles")
                            .font(.subheadline.weight(.medium))
                    }
                }
            }
        } else if model.inspectingWorkspace {
            HStack {
                ProgressView().controlSize(.small)
                Text("Inspecting package manifests and lockfiles…")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    @ViewBuilder
    private func projectRow(_ project: WorkspaceProject) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                Image(systemName: "curlybraces.square")
                    .foregroundStyle(CJStyle.violet)
                Text(project.projectName)
                    .font(.subheadline.weight(.semibold))
                Text(project.ecosystem.rawValue)
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text("\(project.declaredDependencyCount) declared")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }

            Text(project.directory)
                .font(.caption2).foregroundStyle(.tertiary)
                .lineLimit(1).truncationMode(.middle)
                .textSelection(.enabled)

            if !project.lockfiles.isEmpty {
                Label(project.lockfiles.joined(separator: " · "),
                      systemImage: "checkmark.seal")
                    .font(.caption2).foregroundStyle(CJStyle.mint)
            }
            if let count = project.lockfilePackageCount {
                Text("\(count) lockfile entries (not necessarily unique installed packages)")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            if project.ecosystem == .node && !project.dependencies.isEmpty {
                HStack(spacing: 6) {
                    ForEach(project.dependencies.prefix(5)) { dependency in
                        Text(dependency.name)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(CJStyle.subtle, in: Capsule())
                            .help("\(dependency.scope.rawValue): \(dependency.requirement)")
                    }
                }
            }
            ForEach(project.notes.prefix(2), id: \.self) { note in
                Text(note).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(CJStyle.subtle, in: RoundedRectangle(cornerRadius: 12))
    }
}
