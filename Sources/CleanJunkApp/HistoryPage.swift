import CleanJunkCore
import SwiftUI

struct HistoryPage: View {
    @ObservedObject var model: WorkbenchModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 9) {
                    Eyebrow(text: "LOCAL AUDIT TRAIL")
                    Text("Cleanup activity")
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                    Text("A locally stored record of artifacts sent to Finder's Trash.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    model.showTrash()
                } label: {
                    Label("Open Trash", systemImage: "trash")
                }
                .buttonStyle(.glass)
            }
            .padding(.top, 23)

            SurfaceCard {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.title).foregroundStyle(CJStyle.mint)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("\(model.history.count) recorded operations")
                            .font(.headline)
                        Text("Files remain in Trash until it is emptied. CleanJunk never empties Trash automatically. Finder handles recovery.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            if model.history.isEmpty {
                ContentUnavailableView("No cleanup operations", systemImage: "clock",
                                       description: Text("Your cleanup history will appear here after an approved operation."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(model.history) {
                    TableColumn("Artifact") { record in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(URL(fileURLWithPath: record.originalPath).lastPathComponent)
                                .font(.subheadline.weight(.medium))
                            Text(record.originalPath).font(.caption2).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                    }
                    TableColumn("Category") { record in
                        Text(record.category.rawValue).font(.caption)
                    }.width(min: 125, ideal: 150)
                    TableColumn("Estimated size") { record in
                        Text(record.sizeBytes.cjSize).monospacedDigit()
                    }.width(min: 95, ideal: 130)
                    TableColumn("Moved") { record in
                        Text(record.performedAt, format: .dateTime.month().day().hour().minute())
                    }.width(min: 125, ideal: 160)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
    }
}
