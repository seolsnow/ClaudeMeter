import Foundation
import Observation
import ServiceManagement
import os

private let log = Logger(subsystem: "com.devsisters.claudemeter", category: "Settings")

@Observable
final class Settings {
    var launchAtLogin: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status == .enabled { return }
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            log.error("launchAtLogin toggle failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
