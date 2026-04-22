import Foundation
import Combine
import VoicePepperCore

// MARK: - Recording State

enum RecordingState: Equatable {
    case idle
    case recording(startedAt: Date)
    case processing

    var isRecording: Bool {
        if case .recording = self { return true }
        return false
    }

    var duration: TimeInterval? {
        guard case .recording(let start) = self else { return nil }
        return Date().timeIntervalSince(start)
    }
}

// MARK: - Transcription Entry

struct TranscriptionEntry: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let timestamp: Date
    let duration: TimeInterval // audio segment duration in seconds

    var formattedTimestamp: String {
        let f = DateFormatter()
        f.timeStyle = .medium
        f.dateStyle = .none
        return f.string(from: timestamp)
    }
}

// MARK: - App State (Task 2.3)

@MainActor
final class AppState: ObservableObject {
    // Recording
    @Published var recordingState: RecordingState = .idle
    @Published var audioLevel: Float = 0.0          // 0.0 - 1.0 for waveform
    @Published var bufferWarning: Bool = false       // ring buffer overflow warning

    // Transcription
    @Published var entries: [TranscriptionEntry] = []
    @Published var realtimeChunks: [RealtimeTranscriptChunk] = []
    @Published var isModelLoaded: Bool = false
    @Published var modelLoadError: String? = nil

    // WhisperKit 模型状态（实验性模式专用）
    @Published var isWhisperKitModelReady: Bool = false
    @Published var whisperKitModelStatus: String = "正在准备 WhisperKit 模型..."

    // Errors
    @Published var micPermissionDenied: Bool = false
    @Published var accessibilityPermissionGranted: Bool = false

    // 录音源
    @Published var recordingSource: RecordingSource {
        didSet { UserDefaults.standard.set(recordingSource.rawValue, forKey: "recordingSource") }
    }
    /// filePlayback 模式使用的 WAV 文件路径（持久化到 UserDefaults）
    @Published var filePlaybackWAVURL: URL? {
        didSet { UserDefaults.standard.set(filePlaybackWAVURL?.path, forKey: "filePlaybackWAVPath") }
    }
    @Published var bleConnectionState: BLEConnectionState = .disconnected
    @Published var bleBatteryLevel: Int? = nil      // 0-100, 110=充电中
    @Published var bleDeviceStatus: BLEDeviceStatus = []

    // 历史录音（由 RecordingFileService 驱动）
    var recordingFileService: RecordingFileService?
    /// 当前正在播放的录音 ID（nil 表示无播放）
    @Published var currentlyPlayingId: UUID? = nil

    // Preferences
    @Published var selectedModel: WhisperModel {
        didSet { UserDefaults.standard.set(selectedModel.rawValue, forKey: "selectedModel") }
    }
    @Published var speechPipelineMode: SpeechPipelineMode {
        didSet { UserDefaults.standard.set(speechPipelineMode.rawValue, forKey: "speechPipelineMode") }
    }
    @Published var vadSilenceThresholdMs: Int = 500

    // E2E 测试钩子：由 AppDelegate 注入，供 SwiftUI 按钮调用
    var toggleRecordingAction: (() -> Void)?
    // 偏好设置入口：由 AppDelegate 注入，StatusBarManager 和 TranscriptionPopoverView 统一调用
    var openPreferencesAction: (() -> Void)?

    init() {
        let stored = UserDefaults.standard.string(forKey: "selectedModel")
        selectedModel = stored.flatMap(WhisperModel.init(rawValue:)) ?? .tiny

        let storedPipeline = UserDefaults.standard.string(forKey: "speechPipelineMode")
        speechPipelineMode = storedPipeline.flatMap(SpeechPipelineMode.init(rawValue:)) ?? .legacyWhisperCPP

        let storedSource = UserDefaults.standard.string(forKey: "recordingSource")
        recordingSource = storedSource.flatMap(RecordingSource.init(rawValue:)) ?? .microphone

        if let storedPath = UserDefaults.standard.string(forKey: "filePlaybackWAVPath") {
            filePlaybackWAVURL = URL(fileURLWithPath: storedPath)
        }
    }

    // MARK: Computed

    var allTranscriptionText: String {
        entries.map(\.text).joined(separator: "\n")
    }

    var recordingDuration: TimeInterval {
        recordingState.duration ?? 0
    }

    // MARK: Mutations

    func appendEntry(_ entry: TranscriptionEntry) {
        entries.append(entry)
    }

    func updateRealtimeChunks(_ chunks: [RealtimeTranscriptChunk]) {
        realtimeChunks = chunks
    }

    func clearSession() {
        entries.removeAll()
        realtimeChunks.removeAll()
    }

    func startRecording() {
        recordingState = .recording(startedAt: Date())
    }

    func stopRecording() {
        recordingState = .idle
        audioLevel = 0
    }
}

// MARK: - Whisper Model

enum WhisperModel: String, CaseIterable, Identifiable {
    case tiny             = "ggml-tiny"
    case base             = "ggml-base"
    case small            = "ggml-small"
    case medium           = "ggml-medium"
    case largeV2          = "ggml-large-v2"
    case largeV3          = "ggml-large-v3"
    case largeV3Q5_0      = "ggml-large-v3-q5_0"
    case largeV3TurboQ5_0 = "ggml-large-v3-turbo-q5_0"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tiny:             return "Tiny (~75 MB)"
        case .base:             return "Base (~142 MB)"
        case .small:            return "Small (~244 MB)"
        case .medium:           return "Medium (~769 MB)"
        case .largeV2:          return "Large v2 (~2.87 GB)"
        case .largeV3:          return "Large v3 (~2.87 GB)"
        case .largeV3Q5_0:      return "Large v3 Q5_0 (~1.1 GB)"
        case .largeV3TurboQ5_0: return "Large v3 Turbo Q5_0 (~0.6 GB)"
        }
    }

    /// 量化模型标记，在 UI 中显示"推荐"标签
    var isRecommended: Bool {
        switch self {
        case .largeV3Q5_0, .largeV3TurboQ5_0: return true
        default: return false
        }
    }

    var filename: String { "\(rawValue).bin" }

    /// Hugging Face / ggerganov CDN download URL
    var downloadURL: URL {
        URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(filename)")!
    }
}
