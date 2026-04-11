import Foundation

// MARK: - VAD Detector (Task 5.4)
// Voice Activity Detection via RMS energy threshold.
// Fires onSegmentComplete when:
//   - Silence > silenceThresholdMs (default 500ms)
//   - OR speech duration > maxSegmentDuration (30s, Task 5.7)

final class VADDetector {

    // Callback fired with accumulated speech samples when segment ends
    var onSegmentComplete: (([Float]) -> Void)?

    // Config
    var silenceThresholdMs: Int = 500   // ms of silence to trigger segment end
    var energyThreshold: Float = 0.01   // RMS below this = silence
    var sampleRate: Int = 16000         // must match audio pipeline

    // Max 30s per segment (Task 5.7 - force flush)
    private let maxSegmentSamples: Int = 16000 * 30

    private var speechBuffer: [Float] = []
    private var silenceSampleCount: Int = 0
    private var inSpeech: Bool = false

    // Force-flush timer samples threshold
    private var silenceThresholdSamples: Int {
        silenceThresholdMs * sampleRate / 1000
    }

    // MARK: Feed

    /// Process incoming samples (16kHz mono float32)
    func feed(samples: [Float]) {
        for sample in samples {
            let energy = abs(sample)
            let isSpeech = energy > energyThreshold

            if isSpeech {
                inSpeech = true
                silenceSampleCount = 0
                speechBuffer.append(sample)

                // Force flush if segment too long (Task 5.7)
                if speechBuffer.count >= maxSegmentSamples {
                    flushSegment()
                }
            } else {
                if inSpeech {
                    speechBuffer.append(sample)   // include trailing silence
                    silenceSampleCount += 1

                    // Silence duration exceeded threshold → end of segment
                    if silenceSampleCount >= silenceThresholdSamples {
                        flushSegment()
                    }
                }
                // If not in speech, discard leading silence
            }
        }
    }

    // MARK: Flush

    private func flushSegment() {
        guard !speechBuffer.isEmpty else { return }
        let segment = speechBuffer
        speechBuffer = []
        silenceSampleCount = 0
        inSpeech = false
        onSegmentComplete?(segment)
    }

    /// Force flush remaining speech (called on recording stop)
    func forceFlush() {
        flushSegment()
    }

    func reset() {
        speechBuffer = []
        silenceSampleCount = 0
        inSpeech = false
    }
}
