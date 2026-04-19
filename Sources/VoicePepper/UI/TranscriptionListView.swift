import SwiftUI

// MARK: - Transcription List

struct TranscriptionListView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            if appState.speechPipelineMode == .experimentalArgmaxOSS {
                RealtimeChunkListView()
                    .environmentObject(appState)
            } else {
                LegacyEntryListView()
                    .environmentObject(appState)
            }
        }
    }
}

// MARK: - Legacy Entry List (whisper.cpp 模式)

private struct LegacyEntryListView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            if appState.entries.isEmpty {
                EmptyTranscriptionView()
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
                    .onChange(of: appState.entries.count) {
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

// MARK: - Realtime Chunk List (实验性模式)

private struct RealtimeChunkListView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            if appState.realtimeChunks.isEmpty {
                EmptyTranscriptionView()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(appState.realtimeChunks) { chunk in
                                ChunkRowView(chunk: chunk)
                                    .id(chunk.id)
                                    .accessibilityIdentifier("transcriptionEntry-\(chunk.id)")
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    .accessibilityIdentifier("transcriptionScrollView")
                    .onChange(of: appState.realtimeChunks.count) {
                        if let lastId = appState.realtimeChunks.last?.id {
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

// MARK: - Chunk Row (实验性模式带 speaker badge)

struct ChunkRowView: View {
    let chunk: RealtimeTranscriptChunk

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(chunk.speakerLabel ?? "?")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(speakerColor)
                .cornerRadius(4)
                .fixedSize()

            VStack(alignment: .leading, spacing: 2) {
                Text(chunk.text)
                    .font(.body)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundColor(chunk.isFinal ? .primary : .secondary)

                Text(String(format: "%.1fs – %.1fs", chunk.startTimeSeconds, chunk.endTimeSeconds))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
    }

    private var speakerColor: Color {
        switch chunk.speakerLabel {
        case "S0": return .blue
        case "S1": return Color.orange
        case "S2": return Color.purple
        case "S3": return Color.green
        case "S4": return Color.pink
        case nil:  return Color.gray
        default:   return Color.indigo
        }
    }
}

// MARK: - Entry Row (Legacy)

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

// MARK: - Empty State

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
            } else if appState.speechPipelineMode == .experimentalArgmaxOSS && !appState.isWhisperKitModelReady {
                Text(appState.whisperKitModelStatus)
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                ProgressView()
                    .scaleEffect(0.8)
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
