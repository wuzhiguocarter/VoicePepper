import SwiftUI
import AppKit

// MARK: - App Entry Point

@main
struct VoicePepperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Only a preferences window - main UI lives in the status bar popover
        Settings {
            PreferencesView()
                .environmentObject(appDelegate.appState)
        }
    }
}
