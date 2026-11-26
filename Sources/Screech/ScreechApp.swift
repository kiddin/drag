import AppKit
import ServiceManagement
import SwiftUI

@main
struct ScreechApp: App {
    @State private var model = AppModel()

    init() {
        // `make uninstall` runs this so the login item does not outlive the app.
        if CommandLine.arguments.contains("--unregister-login-item") {
            try? SMAppService.mainApp.unregister()
            exit(0)
        }
        // No Dock icon, even when launched outside the .app bundle.
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuView(model: model)
        } label: {
            Image(systemName: model.enabled ? "waveform" : "waveform.slash")
        }
        .menuBarExtraStyle(.window)
    }
}
