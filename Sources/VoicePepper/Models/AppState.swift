import Foundation
import Combine

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
    @Published var isModelLoaded: Bool = false
    @Published var modelLoadError: String? = nil

    // Errors
    @Published var micPermissionDenied: Bool = false
    @Published var accessibilityPermissionGranted: Bool = false

    // Preferences
    @Published var selectedModel: WhisperModel = .tiny
    @Published var vadSilenceThresholdMs: Int = 500

    // E2E 测试钩子：由 AppDelegate 注入，供 SwiftUI 按钮调用
    var toggleRecordingAction: (() -> Void)?

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

    func clearSession() {
        entries.removeAll()
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
    case tiny  = "ggml-tiny"
    case base  = "ggml-base"
    case small = "ggml-small"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tiny:  return "Tiny (~75 MB)"
        case .base:  return "Base (~142 MB)"
        case .small: return "Small (~244 MB)"
        }
    }

    var filename: String { "\(rawValue).bin" }

    /// Hugging Face / ggerganov CDN download URL
    var downloadURL: URL {
        URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(filename)")!
    }
}
