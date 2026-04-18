import SwiftUI
import AppKit
import Foundation
import CWhisper

// MARK: - App Entry Point

@main
struct VoicePepperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        // ggml 后端插件（Metal, BLAS, CPU）嵌入在 .app bundle 内，
        // 必须在 whisper 初始化前显式加载，否则 dylib 中硬编码的
        // Homebrew 路径在分发环境下不存在，导致无 GPU 加速崩溃
        if let frameworksPath = Bundle.main.privateFrameworksPath {
            let backendsPath = (frameworksPath as NSString).appendingPathComponent("ggml-backends")
            if FileManager.default.fileExists(atPath: backendsPath) {
                ggml_backend_load_all_from_path(backendsPath)
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
