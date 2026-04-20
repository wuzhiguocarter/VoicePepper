import Foundation

// MARK: - Recording Source

public enum RecordingSource: String, CaseIterable, Identifiable, Sendable {
    case microphone = "microphone"
    case bluetoothRecorder = "bluetoothRecorder"
    case filePlayback = "filePlayback"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .microphone: return "麦克风"
        case .bluetoothRecorder: return "蓝牙录音笔"
        case .filePlayback: return "文件回放"
        }
    }
}

// MARK: - Speech Pipeline Mode

public enum SpeechPipelineMode: String, CaseIterable, Identifiable, Sendable {
    case legacyWhisperCPP = "legacyWhisperCPP"
    case experimentalArgmaxOSS = "experimentalArgmaxOSS"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .legacyWhisperCPP: return "whisper.cpp + FluidAudio"
        case .experimentalArgmaxOSS: return "WhisperKit + SpeakerKit (Experimental)"
        }
    }
}
