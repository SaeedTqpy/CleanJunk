import SwiftUI

@main
struct CleanJunkApp: App {
    var body: some Scene {
        WindowGroup {
            WorkbenchView()
                .frame(minWidth: 980, minHeight: 670)
        }
        .defaultSize(width: 1240, height: 820)
        .windowStyle(.automatic)

        Settings {
            PreferencesView()
                .frame(width: 520, height: 330)
        }
    }
}
