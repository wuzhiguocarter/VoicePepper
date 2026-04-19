import AVFoundation
import Combine

// MARK: - Audio Capture Error

enum AudioCaptureError: Error, Equatable {
    case permissionDenied
    case engineStartFailed(String)
    case converterSetupFailed
}

// MARK: - Audio Segment

/// A segment of 16kHz mono PCM audio ready for transcription
struct AudioSegment {
    let samples: [Float]        // 16kHz mono float32
    let capturedAt: Date
}

// MARK: - Audio Capture Service (Tasks 4.1 - 4.6)

final class AudioCaptureService {

    /// Emits completed audio segments (post-VAD silence detection)
    let audioSegmentPublisher = PassthroughSubject<AudioSegment, Never>()
    /// Emits current RMS level 0..1 for waveform display
    let levelPublisher = PassthroughSubject<Float, Never>()
    /// 录音会话结束时发出，携带本次会话完整音频和时间边界
    let sessionEndPublisher = PassthroughSubject<RecordingSessionData, Never>()

    /// 当前录音会话累积的 PCM 样本（所有 VAD 段依次追加）
    private var sessionSamples: [Float] = []

    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private let ringBuffer = AudioRingBuffer()           // 30min capacity
    private let vadDetector = VADDetector()
    private var sessionStartedAt: Date?

    private weak var appState: AppState?
    private var cancellables = Set<AnyCancellable>()

    // Whisper requires 16kHz mono
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16000,
        channels: 1,
        interleaved: false
    )!

    init(appState: AppState) {
        self.appState = appState

        // Propagate overflow warning to AppState (Task 4.5)
        ringBuffer.overflowPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak appState] in
                Task { @MainActor in
                    appState?.bufferWarning = true
                }
            }
            .store(in: &cancellables)

        // Hook VAD segment-complete → publish AudioSegment + 累积会话样本
        vadDetector.onSegmentComplete = { [weak self] samples in
            guard let self else { return }
            let segment = AudioSegment(samples: samples, capturedAt: Date())
            self.audioSegmentPublisher.send(segment)
            self.sessionSamples.append(contentsOf: samples)
        }
    }

    // MARK: - Start / Stop

    func start(completion: @escaping (AudioCaptureError?) -> Void) {
        // Task 4.6 - check/request microphone permission
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            if granted {
                DispatchQueue.main.async {
                    do {
                        try self?.startEngine()
                        self?.sessionStartedAt = Date()
                        completion(nil)
                    } catch let err as AudioCaptureError {
                        completion(err)
                    } catch {
                        completion(.engineStartFailed(error.localizedDescription))
                    }
                }
            } else {
                DispatchQueue.main.async {
                    completion(.permissionDenied)
                }
            }
        }
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        // 先强制刷新 VAD 中尚未完成的语音段，确保短时录音也能保存
        vadDetector.forceFlush()

        // Flush remaining samples as final segment
        let remaining = ringBuffer.drainAll()
        if !remaining.isEmpty {
            let segment = AudioSegment(samples: remaining, capturedAt: Date())
            audioSegmentPublisher.send(segment)
            sessionSamples.append(contentsOf: remaining)
        }

        // 发出完整会话样本供持久化，然后清空缓冲
        let completedSession = sessionSamples
        if !completedSession.isEmpty {
            let startedAt = sessionStartedAt ?? Date().addingTimeInterval(-Double(completedSession.count) / 16000.0)
            sessionEndPublisher.send(
                RecordingSessionData(
                    samples: completedSession,
                    startedAt: startedAt,
                    endedAt: Date()
                )
            )
        }
        sessionSamples.removeAll()
        sessionStartedAt = nil

        vadDetector.reset()
        ringBuffer.reset()

        DispatchQueue.main.async { [weak self] in
            self?.appState?.audioLevel = 0
        }
    }

    // MARK: - Engine Setup

    private func startEngine() throws {
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Setup converter: input → 16kHz mono float32 (Task 4.3)
        guard let conv = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw AudioCaptureError.converterSetupFailed
        }
        self.converter = conv

        // Task 4.2 - install tap with 1024 frame buffer
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.processTapBuffer(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            throw AudioCaptureError.engineStartFailed(error.localizedDescription)
        }
    }

    // MARK: - Buffer Processing

    private func processTapBuffer(_ inputBuffer: AVAudioPCMBuffer) {
        guard let converter,
              let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: AVAudioFrameCount(
                    Double(inputBuffer.frameLength) * targetFormat.sampleRate / inputBuffer.format.sampleRate + 1
                )
              ) else { return }

        var error: NSError?
        var inputConsumed = false

        // Task 4.3 - convert to 16kHz mono
        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if inputConsumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            outStatus.pointee = .haveData
            inputConsumed = true
            return inputBuffer
        }

        guard error == nil, outputBuffer.frameLength > 0,
              let channelData = outputBuffer.floatChannelData else { return }

        let samples = Array(UnsafeBufferPointer(
            start: channelData[0],
            count: Int(outputBuffer.frameLength)
        ))

        // Compute RMS for waveform display
        let rms = computeRMS(samples)
        DispatchQueue.main.async { [weak self] in
            self?.appState?.audioLevel = rms
        }

        // Feed into VAD detector
        vadDetector.feed(samples: samples)
    }

    // MARK: - Helpers

    private func computeRMS(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sumSq = samples.reduce(0) { $0 + $1 * $1 }
        return min(1.0, sqrt(sumSq / Float(samples.count)) * 10)
    }
}
