import SwiftUI

@main
struct ClaudeMeterApp: App {
    @State private var settings = Settings()
    @State private var store = UsageStore()
    @AppStorage("showSessionInMenuBar") private var showSession: Bool = true
    @AppStorage("showWeeklyInMenuBar") private var showWeekly: Bool = true

    var body: some Scene {
        MenuBarExtra {
            DetailPanelView(
                store: store,
                settings: settings,
                onQuit: { NSApplication.shared.terminate(nil) }
            )
        } label: {
            MenuBarLabel(snapshot: store.snapshot, showSession: showSession, showWeekly: showWeekly)
        }
        .menuBarExtraStyle(.window)
    }
}
