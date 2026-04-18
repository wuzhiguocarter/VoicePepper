import SwiftUI
import AppKit
import Foundation

// MARK: - App Entry Point

@main
struct VoicePepperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        // ggml 后端插件搜索路径：使用 .app bundle 内嵌入的插件，
        // 避免依赖 Homebrew 安装路径（硬编码在 dylib 中，分发后不存在）
        if let frameworksPath = Bundle.main.privateFrameworksPath {
            let backendsPath = (frameworksPath as NSString).appendingPathComponent("ggml-backends")
            if FileManager.default.fileExists(atPath: backendsPath) {
                setenv("GGML_BACKEND_PATH", backendsPath, 1)
            }
        }
    }

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
