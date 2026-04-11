import SwiftUI
import AppKit

// MARK: - Transcription Popover View (Task 6.2)
// Main panel: status bar at top, transcript list, action buttons at bottom.

struct TranscriptionPopoverView: View {
    @EnvironmentObject var appState: AppState

    @State private var showClearConfirm = false
    @State private var showCopiedFeedback = false

    var body: some View {
        VStack(spacing: 0) {

            // Top: Recording status bar (timer + waveform) - Task 6.4
            RecordingStatusBar()
                .environmentObject(appState)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("recordingStatusBar")

            Divider()

            // Middle: Transcript list (scrollable) - Task 6.3
            TranscriptionListView()
                .environmentObject(appState)
                .frame(minHeight: 300)

            Divider()

            // Bottom: Action bar
            actionBar
        }
        .frame(width: 400, height: 460)
        .background(Color(NSColor.windowBackgroundColor))
        // .contain 保留子元素各自的 accessibilityIdentifier，避免 SwiftUI 平铺时被父 id 覆盖
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("transcriptionPopover")
        // E2E 测试钩子：零尺寸隐藏按钮，通过 AX 触发录音切换
        .overlay(alignment: .topLeading) {
            Button("") {
                NSLog("[TestButton] testToggleRecordingButton pressed")
                appState.toggleRecordingAction?()
            }
            .frame(width: 1, height: 1)
            .opacity(0.01)
            .accessibilityLabel("Toggle Recording")
            .accessibilityIdentifier("testToggleRecordingButton")
        }
    }

    // MARK: Action Bar

    private var actionBar: some View {
        HStack {
            // Clear session (Task 6.7)
            Button(role: .destructive) {
                showClearConfirm = true
            } label: {
                Label("清除", systemImage: "trash")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .disabled(appState.entries.isEmpty)
            .accessibilityIdentifier("clearButton")
            .confirmationDialog(
                "清除所有转录内容？",
                isPresented: $showClearConfirm,
                titleVisibility: .visible
            ) {
                Button("清除", role: .destructive) {
                    appState.clearSession()
                }
                Button("取消", role: .cancel) {}
            }

            Spacer()

            // Entry count
            if !appState.entries.isEmpty {
                Text("\(appState.entries.count) 条")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Copy all (Task 6.6)
            Button {
                copyAll()
            } label: {
                Label(showCopiedFeedback ? "已复制" : "复制全部", systemImage: "doc.on.doc")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .disabled(appState.entries.isEmpty)
            .accessibilityIdentifier("copyAllButton")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: Copy Action (Task 6.6)

    private func copyAll() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(appState.allTranscriptionText, forType: .string)

        // 200ms feedback
        withAnimation {
            showCopiedFeedback = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation {
                showCopiedFeedback = false
            }
        }
    }
}

