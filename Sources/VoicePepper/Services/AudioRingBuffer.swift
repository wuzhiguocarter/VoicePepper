import Foundation
import Combine

// MARK: - Audio Ring Buffer (Task 4.4 & 4.5)
// Thread-safe circular buffer for Float (PCM samples).
// Capacity = 30 min × 16000 Hz × 4 bytes ≈ 115 MB

final class AudioRingBuffer {

    // Overflow warning publisher (Task 4.5)
    let overflowPublisher = PassthroughSubject<Void, Never>()

    private let capacity: Int
    private var buffer: [Float]
    private var writeIndex: Int = 0
    private var count: Int = 0
    private let lock = NSLock()

    /// capacity in number of float samples
    init(capacitySamples: Int = 16000 * 60 * 30) {
        self.capacity = capacitySamples
        self.buffer = [Float](repeating: 0, count: capacitySamples)
    }

    // MARK: Write

    /// Append samples, overwriting oldest if full (ring behavior).
    func write(_ samples: [Float]) {
        lock.lock()
        defer { lock.unlock() }

        let overflowed = count + samples.count > capacity

        for sample in samples {
            buffer[writeIndex] = sample
            writeIndex = (writeIndex + 1) % capacity
            if count < capacity {
                count += 1
            }
            // If count == capacity, oldest sample is silently overwritten (ring)
        }

        if overflowed {
            DispatchQueue.main.async { [weak self] in
                self?.overflowPublisher.send()
            }
        }
    }

    // MARK: Read

    /// Read the last `n` samples. Returns fewer if buffer has less.
    func readLast(_ n: Int) -> [Float] {
        lock.lock()
        defer { lock.unlock() }

        let available = min(n, count)
        guard available > 0 else { return [] }

        var result = [Float](repeating: 0, count: available)
        // Oldest sample in ring is at: (writeIndex - count + capacity) % capacity
        let startIndex = (writeIndex - available + capacity) % capacity

        for i in 0..<available {
            result[i] = buffer[(startIndex + i) % capacity]
        }
        return result
    }

    /// Drain all samples and reset buffer.
    func drainAll() -> [Float] {
        lock.lock()
        defer { lock.unlock() }

        guard count > 0 else { return [] }

        var result = [Float](repeating: 0, count: count)
        let startIndex = (writeIndex - count + capacity) % capacity

        for i in 0..<count {
            result[i] = buffer[(startIndex + i) % capacity]
        }

        writeIndex = 0
        count = 0
        return result
    }

    var sampleCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    var isEmpty: Bool {
        lock.lock()
        defer { lock.unlock() }
        return count == 0
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        writeIndex = 0
        count = 0
    }
}
