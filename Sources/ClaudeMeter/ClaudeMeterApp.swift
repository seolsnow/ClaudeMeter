import SwiftUI

@main
struct ClaudeMeterApp: App {
    @State private var settings = Settings()
    @State private var store = UsageStore()

    var body: some Scene {
        MenuBarExtra {
            DetailPanelView(
                store: store,
                settings: settings,
                onQuit: { NSApplication.shared.terminate(nil) }
            )
        } label: {
            MenuBarLabel(snapshot: store.snapshot)
        }
        .menuBarExtraStyle(.window)
    }
}
