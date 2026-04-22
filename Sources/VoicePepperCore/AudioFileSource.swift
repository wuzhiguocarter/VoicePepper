import AVFoundation
import Combine

public final class AudioFileSource {
    public let audioSegmentPublisher = PassthroughSubject<AudioSegment, Never>()
    public let sessionEndPublisher = PassthroughSubject<RecordingSessionData, Never>()

    private var isStopped = false

    public init() {}

    public func play(url: URL, chunkDuration: TimeInterval = 1.5) async {
        isStopped = false
        let startedAt = Date()

        let audioFile: AVAudioFile
        do {
            audioFile = try AVAudioFile(forReading: url)
        } catch {
            NSLog("[AudioFileSource] 无法读取文件: %@ error=%@", url.path, error.localizedDescription)
            return
        }

        let format = audioFile.processingFormat
        guard format.sampleRate == 16000, format.channelCount == 1 else {
            NSLog("[AudioFileSource] 格式不符: sampleRate=%.0f channels=%d (需要 16kHz mono)",
                  format.sampleRate, format.channelCount)
            sessionEndPublisher.send(RecordingSessionData(samples: [], startedAt: startedAt, endedAt: Date()))
            return
        }

        let samplesPerChunk = AVAudioFrameCount(format.sampleRate * chunkDuration)
        var allSamples: [Float] = []

        while !isStopped {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: samplesPerChunk) else { break }

            do {
                try audioFile.read(into: buffer, frameCount: samplesPerChunk)
            } catch {
                break
            }

            guard buffer.frameLength > 0, let channelData = buffer.floatChannelData else { break }

            let samples = Array(UnsafeBufferPointer(start: channelData[0], count: Int(buffer.frameLength)))
            allSamples.append(contentsOf: samples)
            audioSegmentPublisher.send(AudioSegment(samples: samples, capturedAt: Date()))

            // pace to real-time to avoid CPU burst
            let ns = UInt64(Double(buffer.frameLength) / format.sampleRate * 1_000_000_000)
            try? await Task.sleep(nanoseconds: ns)
        }

        guard !isStopped else { return }
        sessionEndPublisher.send(RecordingSessionData(samples: allSamples, startedAt: startedAt, endedAt: Date()))
    }

    public func stop() {
        isStopped = true
    }
}
