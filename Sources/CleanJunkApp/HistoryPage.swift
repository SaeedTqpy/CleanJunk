import CleanJunkCore
import SwiftUI

struct HistoryPage: View {
    @ObservedObject var model: WorkbenchModel

    private var unresolved: Int {
        model.cleanupOperations.filter { $0.state == .prepared || $0.state == .requiresReconciliation }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 9) {
                    Eyebrow(text: "LOCAL AUDIT TRAIL")
                    Text("Cleanup activity")
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                    Text("Every operation is recorded before it touches the filesystem.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Button { model.showTrash() } label: {
                    Label("Open Finder Trash", systemImage: "trash")
                }
                .buttonStyle(.glass)
            }
            .padding(.top, 23)

            SurfaceCard {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.title).foregroundStyle(CJStyle.mint)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("\(model.cleanupOperations.count) journaled operations")
                            .font(.headline)
                        Text("Files remain in Trash until emptied. Original locations are never overwritten during restoration.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if unresolved > 0 {
                        Pill(symbol: "exclamationmark.triangle", text: "\(unresolved) unresolved", tint: CJStyle.amber)
                    }
                }
            }

            if model.journalCorrupted {
                Label("Cleanup journal cannot be decoded. Operations are disabled to avoid overwriting audit history. Back up the existing journal and investigate before continuing.",
                      systemImage: "exclamationmark.shield.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(CJStyle.amber)
                    .padding(10)
                    .background(CJStyle.amber.opacity(0.10),
                                in: RoundedRectangle(cornerRadius: 12))
            }

            if model.cleanupOperations.isEmpty {
                ContentUnavailableView("No cleanup operations", systemImage: "clock",
                                       description: Text("Approved operations will appear here, including interrupted transactions."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(model.cleanupOperations) {
                    TableColumn("Artifact") { operation in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(URL(fileURLWithPath: operation.sourcePath).lastPathComponent)
                                .font(.subheadline.weight(.medium))
                            Text(operation.sourcePath)
                                .font(.caption2).foregroundStyle(.tertiary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                        .help(operation.detail ?? operation.sourcePath)
                    }
                    TableColumn("Status") { operation in
                        switch operation.state {
                        case .prepared:
                            Pill(symbol: "clock", text: "Pending review", tint: CJStyle.amber)
                        case .movedToTrash:
                            Pill(symbol: "trash", text: "In Trash", tint: CJStyle.violet)
                        case .restored:
                            Pill(symbol: "arrow.uturn.backward", text: "Restored", tint: CJStyle.mint)
                        case .failed, .requiresReconciliation:
                            Pill(symbol: "exclamationmark.triangle", text: "Check in Finder", tint: CJStyle.amber)
                        }
                    }.width(min: 130, ideal: 165)
                    TableColumn("When") { operation in
                        Text(operation.startedAt, format: .dateTime.month().day().hour().minute())
                            .font(.caption).foregroundStyle(.secondary)
                    }.width(min: 125, ideal: 150)
                    TableColumn("Restore") { operation in
                        Button {
                            Task { await model.restoreOperation(operation) }
                        } label: {
                            Label("Restore", systemImage: "arrow.uturn.backward")
                                .labelStyle(.titleOnly)
                        }
                        .buttonStyle(.glass)
                        .disabled(operation.state != .movedToTrash || model.trashing || model.scanning ||
                                  operation.trashPath == nil)
                        .help("Restores only when the original location is empty and the Trash entry matches the recorded file identity.")
                    }.width(min: 85, ideal: 115)
                }
            }

            if unresolved > 0 {
                Label("An interrupted or ambiguous move needs manual verification in Finder. CleanJunk never assumes it succeeded.",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(CJStyle.amber)
            }
            Label("Restoration may be unavailable for external-volume Trash, modified items, or occupied original paths.",
                  systemImage: "info.circle")
                .font(.caption2).foregroundStyle(.secondary)
                .padding(.bottom, 15)
        }
        .padding(.horizontal, 28)
    }
}
