import SwiftUI

// MARK: - Recording Status Bar (Task 6.4)
// Top bar in popover: shows timer (MM:SS) + audio level waveform

struct RecordingStatusBar: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator dot
            Circle()
                .fill(appState.recordingState.isRecording ? Color.red : Color.gray.opacity(0.4))
                .frame(width: 8, height: 8)
                // .ignore 将 Circle 暴露为独立 AX 元素，否则 SwiftUI 会将 Shape 合并
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier(appState.recordingState.isRecording ? "recordingIndicatorActive" : "recordingIndicatorIdle")

            // Timer display — 用 TimelineView 每秒刷新，避免 Timer.publish 在频繁 body 求值时被反复重建
            if appState.recordingState.isRecording {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(formatDuration(appState.recordingDuration))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            } else {
                Text(appState.isModelLoaded ? "就绪" : "加载模型中...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Audio level waveform (Task 6.5)
            if appState.recordingState.isRecording {
                AudioLevelView(level: appState.audioLevel)
                    .frame(width: 60, height: 20)
            }

            // Buffer warning badge
            if appState.bufferWarning {
                Label("缓冲区满", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%02d:%02d", m, s)
    }
}
