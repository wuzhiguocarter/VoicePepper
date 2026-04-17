import SwiftUI
import AppKit

// MARK: - Transcription Popover View (Task 6.2)
// Main panel: status bar at top, transcript list, action buttons at bottom.

struct TranscriptionPopoverView: View {
    @EnvironmentObject var appState: AppState

    @State private var showClearConfirm = false
    @State private var showCopiedFeedback = false
    @State private var selectedTab: PopoverTab = .transcription

    enum PopoverTab: String, CaseIterable {
        case transcription = "转录"
        case history = "历史录音"
    }

    var body: some View {
        VStack(spacing: 0) {

            // 录音源 + BLE 状态
            recordingSourceHeader

            Divider()

            // Top: Recording status bar (timer + waveform) - Task 6.4
            RecordingStatusBar()
                .environmentObject(appState)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("recordingStatusBar")

            Divider()

            // Tab 切换
            Picker("", selection: $selectedTab) {
                ForEach(PopoverTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            // 内容区
            Group {
                if selectedTab == .transcription {
                    // Middle: Transcript list (scrollable) - Task 6.3
                    TranscriptionListView()
                        .environmentObject(appState)
                        .frame(minHeight: 280)
                } else {
                    // 历史录音列表
                    if let service = appState.recordingFileService {
                        RecordingHistoryView(
                            service: service,
                            currentlyPlayingId: Binding(
                                get: { appState.currentlyPlayingId },
                                set: { appState.currentlyPlayingId = $0 }
                            )
                        )
                        .frame(minHeight: 280)
                    } else {
                        Text("录音服务未就绪")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }

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

    // MARK: Recording Source Header

    private var recordingSourceHeader: some View {
        HStack(spacing: 8) {
            // 录音源选择
            Picker("", selection: $appState.recordingSource) {
                ForEach(RecordingSource.allCases) { source in
                    Label(source.displayName, systemImage: source == .microphone ? "mic" : "antenna.radiowaves.left.and.right")
                        .tag(source)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 200)

            Spacer()

            // BLE 状态指示（仅蓝牙模式显示）
            if appState.recordingSource == .bluetoothRecorder {
                bleStatusIndicator
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var bleStatusIndicator: some View {
        HStack(spacing: 4) {
            // 连接状态圆点
            Circle()
                .fill(bleConnectionColor)
                .frame(width: 8, height: 8)

            Text(bleConnectionText)
                .font(.caption2)
                .foregroundColor(.secondary)

            // 电量指示
            if let battery = appState.bleBatteryLevel {
                Divider().frame(height: 12)
                if battery == 110 {
                    Image(systemName: "battery.100.bolt")
                        .font(.caption2)
                        .foregroundColor(.green)
                } else {
                    Image(systemName: batteryIcon(battery))
                        .font(.caption2)
                        .foregroundColor(battery <= 20 ? .red : .secondary)
                    Text("\(battery)%")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .accessibilityIdentifier("bleStatusIndicator")
    }

    private var bleConnectionColor: Color {
        switch appState.bleConnectionState {
        case .connected: return .green
        case .connecting, .reconnecting: return .orange
        default: return .red
        }
    }

    private var bleConnectionText: String {
        switch appState.bleConnectionState {
        case .connected: return "已连接"
        case .connecting: return "连接中"
        case .reconnecting(let n): return "重连(\(n))"
        case .scanning: return "扫描中"
        case .disconnected: return "未连接"
        }
    }

    private func batteryIcon(_ level: Int) -> String {
        switch level {
        case 0..<25: return "battery.25"
        case 25..<50: return "battery.50"
        case 50..<75: return "battery.75"
        default: return "battery.100"
        }
    }

    // MARK: Action Bar

    private var actionBar: some View {
        HStack {
            // 偏好设置入口
            Button {
                appState.openPreferencesAction?()
            } label: {
                Image(systemName: "gearshape")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .help("偏好设置 (模型选择、快捷键…)")
            .accessibilityIdentifier("settingsButton")

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

