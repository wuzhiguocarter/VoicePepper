import SwiftUI
import AppKit

// MARK: - App Entry Point

@main
struct VoicePepperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // 偏好设置窗口由 AppDelegate.openPreferencesWindow() 手动管理，
        // 规避 .accessory app 中 Settings scene / showSettingsWindow: 不可靠的问题。
        // SwiftUI 要求 body 至少返回一个 Scene，用零尺寸空 Window 占位。
        WindowGroup(id: "void") {
            EmptyView()
        }
        .defaultSize(width: 0, height: 0)
    }
}
