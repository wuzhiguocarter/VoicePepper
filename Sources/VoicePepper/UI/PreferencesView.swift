import SwiftUI
import KeyboardShortcuts

// MARK: - Preferences View

struct PreferencesView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var modelManager: WhisperModelManager

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
                ForEach(WhisperModel.allCases) { model in
                    ModelRow(
                        model: model,
                        isSelected: appState.selectedModel == model,
                        isSwitching: isSwitching,
                        modelManager: modelManager
                    ) {
                        guard !isSwitching else { return }
                        appState.selectedModel = model
                    }
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
        .frame(width: 520, height: 480)
    }

    /// 任意模型正在下载或加载时为 true，此时禁止切换
    private var isSwitching: Bool {
        modelManager.modelStates.values.contains {
            if case .downloading = $0 { return true }
            if case .loading = $0 { return true }
            return false
        }
    }

    private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Model Row

private struct ModelRow: View {
    let model: WhisperModel
    let isSelected: Bool
    let isSwitching: Bool
    let modelManager: WhisperModelManager
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                // 选中指示
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .frame(width: 16)

                // 模型名称 + 推荐标签
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(model.displayName)
                            .fontWeight(isSelected ? .semibold : .regular)

                        if model.isRecommended {
                            Text("推荐")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.yellow.opacity(0.25))
                                .foregroundColor(.orange)
                                .cornerRadius(4)
                        }
                    }

                    statusSubtitle
                }

                Spacer()

                statusTrailing
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isSwitching && !isSelected)
        .opacity(isSwitching && !isSelected ? 0.45 : 1.0)
    }

    @ViewBuilder
    private var statusSubtitle: some View {
        switch resolvedState {
        case .downloading(let progress):
            VStack(alignment: .leading, spacing: 3) {
                ProgressView(value: progress)
                    .frame(width: 160)
                Text(String(format: "下载中 %.0f%%", progress * 100))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        case .loading:
            Text("加载中…")
                .font(.caption)
                .foregroundColor(.secondary)
        case .failed:
            Text("下载失败，请检查网络连接")
                .font(.caption)
                .foregroundColor(.red)
        case .ready:
            if modelManager.activeModel == model {
                Text("使用中")
                    .font(.caption)
                    .foregroundColor(.green)
            } else {
                Text("已下载")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        default:
            // idle / nil — check local file
            if modelManager.isModelDownloaded(model) {
                Text("已下载")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("未下载")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private var statusTrailing: some View {
        switch resolvedState {
        case .downloading:
            ProgressView()
                .scaleEffect(0.7)
        case .loading:
            ProgressView()
                .scaleEffect(0.7)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundColor(.red)
        case .ready:
            if modelManager.activeModel == model {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else {
                Image(systemName: "checkmark.circle")
                    .foregroundColor(.secondary)
            }
        default:
            if modelManager.isModelDownloaded(model) {
                Image(systemName: "checkmark.circle")
                    .foregroundColor(.secondary)
            } else {
                Image(systemName: "arrow.down.circle")
                    .foregroundColor(.secondary)
            }
        }
    }

    /// 优先使用 modelStates 中的实时状态，fallback 到 idle
    private var resolvedState: ModelLoadState {
        modelManager.modelStates[model] ?? .idle
    }
}
