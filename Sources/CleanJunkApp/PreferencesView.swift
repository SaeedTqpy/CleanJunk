import SwiftUI

struct PreferencesView: View {
    var body: some View {
        Form {
            Section("CleanJunk Developer Edition") {
                LabeledContent("Platform", value: "macOS 26 or later")
                LabeledContent("Appearance", value: "Native Liquid Glass · follows System appearance")
                LabeledContent("Scanning", value: "Local, read-only")
            }
            Section("Safety") {
                Label("No permanent deletion: items are sent to Finder's Trash.", systemImage: "checkmark.shield")
                Label("System directories and Docker virtual disks are never trashed.", systemImage: "lock.shield")
                Label("Homebrew inspection does not execute uninstall commands.", systemImage: "shippingbox")
                Label("No root helper, background agent, or remote analytics.", systemImage: "hand.raised")
            }
            Section("Privacy") {
                Text("Analysis runs on this Mac. Cleanup history is stored in ~/Library/Application Support/CleanJunk/.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(14)
    }
}
