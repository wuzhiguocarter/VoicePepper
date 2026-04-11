import SwiftUI
import KeyboardShortcuts

// MARK: - Preferences View (Tasks 3.4 & 3.5)

struct PreferencesView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
            // Hotkey Section
            Section("快捷键") {
                HStack {
                    Text("录音快捷键")
                    Spacer()
                    KeyboardShortcuts.Recorder("", name: .toggleRecording)
                        .help("点击后按下新快捷键")
                }

                // Accessibility permission status
                HStack {
                    Image(systemName: appState.accessibilityPermissionGranted
                          ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(appState.accessibilityPermissionGranted ? .green : .red)

                    Text(appState.accessibilityPermissionGranted
                         ? "辅助功能权限已授权"
                         : "辅助功能权限未授权（全局快捷键不可用）")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    if !appState.accessibilityPermissionGranted {
                        Button("前往系统设置") {
                            openAccessibilitySettings()
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                    }
                }
            }

            // Model Section
            Section("Whisper 模型") {
                Picker("模型", selection: $appState.selectedModel) {
                    ForEach(WhisperModel.allCases) { model in
                        Text(model.displayName).tag(model)
                    }
                }
                .pickerStyle(.radioGroup)

                HStack {
                    Image(systemName: appState.isModelLoaded ? "checkmark.circle.fill" : "arrow.down.circle")
                        .foregroundColor(appState.isModelLoaded ? .green : .orange)
                    Text(appState.isModelLoaded
                         ? "模型已加载，可以使用"
                         : (appState.modelLoadError ?? "模型未加载"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text("模型存储位置：~/Library/Application Support/VoicePepper/models/")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // VAD Section
            Section("转录敏感度") {
                HStack {
                    Text("静音检测阈值")
                    Spacer()
                    Stepper("\(appState.vadSilenceThresholdMs) ms",
                            value: $appState.vadSilenceThresholdMs,
                            in: 200...2000,
                            step: 100)
                }
                Text("值越小，分段越频繁；值越大，段落越长")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 480, height: 420)
    }

    private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
