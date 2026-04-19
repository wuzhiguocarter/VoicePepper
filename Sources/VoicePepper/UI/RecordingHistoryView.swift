import SwiftUI
import AVFoundation
import AppKit

// MARK: - Recording History View

struct RecordingHistoryView: View {
    @ObservedObject var service: RecordingFileService
    @Binding var currentlyPlayingId: UUID?

    // AVAudioPlayer 持有在 StateObject 中以保活
    @StateObject private var player = AudioPlayerWrapper()

    // 转录文本预览 Sheet 状态
    @State private var selectedTranscriptionText: String?
    @State private var selectedTranscriptionDate: String?

    var body: some View {
        Group {
            if service.recordings.isEmpty {
                emptyState
            } else {
                recordingList
            }
        }
        .onAppear {
            service.loadRecordings()
        }
        .sheet(item: Binding(
            get: { selectedTranscriptionText.map { IdentifiableString(value: $0, subtitle: selectedTranscriptionDate ?? "") } },
            set: { _ in selectedTranscriptionText = nil; selectedTranscriptionDate = nil }
        )) { item in
            TranscriptionTextView(text: item.value, title: item.subtitle)
        }
    }

    // MARK: 空状态

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform.slash")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("暂无录音记录")
                .font(.callout)
                .foregroundColor(.secondary)
            Text("开始录音后，录音文件将自动保存在此处")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: 列表

    private var recordingList: some View {
        List {
            ForEach(service.recordings) { item in
                RecordingRowView(
                    item: item,
                    isPlaying: currentlyPlayingId == item.id,
                    onPlayPause: { handlePlayPause(item: item) },
                    onRevealInFinder: { revealInFinder(item: item) },
                    onDelete: { service.delete(item: item) },
                    onViewTranscription: {
                        selectedTranscriptionText = item.preferredTranscriptionText
                        selectedTranscriptionDate = item.formattedDate
                    }
                )
                .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
            }
        }
        .listStyle(.plain)
        .onChange(of: currentlyPlayingId) {
            if currentlyPlayingId == nil {
                player.stop()
            }
        }
    }

    // MARK: 播放逻辑

    private func handlePlayPause(item: RecordingItem) {
        if currentlyPlayingId == item.id {
            // 暂停
            player.pause()
            currentlyPlayingId = nil
        } else {
            // 停止前一条，播放新的
            player.stop()
            currentlyPlayingId = item.id
            player.play(url: item.url) {
                // 播放结束回调
                Task { @MainActor in
                    if currentlyPlayingId == item.id {
                        currentlyPlayingId = nil
                    }
                }
            }
        }
    }

    // MARK: Finder 定位

    private func revealInFinder(item: RecordingItem) {
        if FileManager.default.fileExists(atPath: item.url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([item.url])
        } else {
            service.loadRecordings()
        }
    }
}

// MARK: - Recording Row View

private struct RecordingRowView: View {
    let item: RecordingItem
    let isPlaying: Bool
    let onPlayPause: () -> Void
    let onRevealInFinder: () -> Void
    let onDelete: () -> Void
    let onViewTranscription: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            // 左侧信息
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(item.formattedDate)
                        .font(.callout)
                        .lineLimit(1)
                    if item.transcriptJSONURL != nil {
                        Image(systemName: "person.2.fill")
                            .font(.caption2)
                            .foregroundColor(.accentColor)
                    }
                    if item.transcriptionURL != nil {
                        Image(systemName: "doc.text")
                            .font(.caption2)
                            .foregroundColor(item.transcriptJSONURL != nil ? .secondary : .accentColor)
                    }
                }
                Text(item.formattedDuration)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // 播放/暂停按钮
            Button(action: onPlayPause) {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title2)
                    .foregroundColor(isPlaying ? .accentColor : .primary)
            }
            .buttonStyle(.borderless)
            .help(isPlaying ? "暂停" : "播放")
            .accessibilityLabel(isPlaying ? "暂停" : "播放")

            // 查看转录文本按钮
            if item.preferredTranscriptionText != nil {
                Button(action: onViewTranscription) {
                    Image(systemName: "doc.text")
                        .font(.body)
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.borderless)
                .help(item.transcriptJSONURL != nil ? "查看说话人分离转录" : "查看转录文本")
                .accessibilityLabel("查看转录文本")
            }

            // 在 Finder 中显示按钮
            Button(action: onRevealInFinder) {
                Image(systemName: "folder")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)
            .help("在 Finder 中显示")
            .accessibilityLabel("在 Finder 中显示")

            // 删除按钮
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)
            .help("删除录音")
            .accessibilityLabel("删除录音")
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Audio Player Wrapper

/// ObservableObject 包装 AVAudioPlayer，保持强引用并转发 delegate 回调。
@MainActor
final class AudioPlayerWrapper: NSObject, ObservableObject, AVAudioPlayerDelegate {

    private var audioPlayer: AVAudioPlayer?
    private var completionHandler: (() -> Void)?

    func play(url: URL, onComplete: @escaping () -> Void) {
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.prepareToPlay()
            player.play()
            audioPlayer = player
            completionHandler = onComplete
        } catch {
            NSLog("[AudioPlayerWrapper] 播放失败: %@", error.localizedDescription)
            onComplete()
        }
    }

    func pause() {
        audioPlayer?.pause()
    }

    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
        completionHandler = nil
    }

    // MARK: AVAudioPlayerDelegate

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.audioPlayer = nil
            self.completionHandler?()
            self.completionHandler = nil
        }
    }
}

// MARK: - Identifiable String (Sheet binding helper)

private struct IdentifiableString: Identifiable {
    let id = UUID()
    let value: String
    let subtitle: String
}

// MARK: - Transcription Text View (Sheet)

struct TranscriptionTextView: View {
    let text: String
    let title: String

    @Environment(\.dismiss) private var dismiss
    @State private var showCopied = false

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Text("转录文本 - \(title)")
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            // 文本内容
            ScrollView {
                Text(text)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }

            Divider()

            // 底部操作栏
            HStack {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    showCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        showCopied = false
                    }
                } label: {
                    Label(showCopied ? "已复制" : "复制全部", systemImage: "doc.on.doc")
                        .font(.callout)
                }
                .buttonStyle(.bordered)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(width: 380, height: 320)
    }
}
