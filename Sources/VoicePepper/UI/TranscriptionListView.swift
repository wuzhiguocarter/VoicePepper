import SwiftUI

// MARK: - Transcription List (Task 6.3)
// Scrollable list of transcription entries, auto-scrolls to latest.

struct TranscriptionListView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            if appState.entries.isEmpty {
                EmptyTranscriptionView()           // Task 6.8
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(appState.entries) { entry in
                                EntryRow(entry: entry)
                                    .id(entry.id)
                                    .accessibilityIdentifier("transcriptionEntry-\(entry.id)")
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    .accessibilityIdentifier("transcriptionScrollView")
                    // macOS 13 compatible onChange
                    .onChange(of: appState.entries.count) { _ in
                        // Auto-scroll to latest (Task 6.3)
                        if let lastId = appState.entries.last?.id {
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo(lastId, anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Entry Row

private struct EntryRow: View {
    let entry: TranscriptionEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.text)
                .font(.body)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            Text(entry.formattedTimestamp)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
    }
}

// MARK: - Empty State (Task 6.8)

struct EmptyTranscriptionView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "mic.slash")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
                .accessibilityIdentifier("emptyStateIcon")

            if let error = appState.modelLoadError {
                Text("模型加载失败")
                    .font(.headline)
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            } else if !appState.isModelLoaded {
                Text("正在加载 Whisper 模型...")
                    .font(.callout)
                    .foregroundColor(.secondary)
                ProgressView()
                    .scaleEffect(0.8)
            } else if appState.micPermissionDenied {
                Text("麦克风权限被拒绝")
                    .font(.headline)
                Text("请在系统设置 > 隐私与安全 > 麦克风 中允许 VoicePepper")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text("按下快捷键开始录音")
                    .font(.callout)
                    .foregroundColor(.secondary)

                Text("默认：⌥ Space")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(4)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .accessibilityIdentifier("emptyTranscriptionView")
    }
}
