import Foundation
import COpus

// MARK: - Opus Decoder

/// 录音笔 BLE 音频 Opus 解码器
/// 格式：SILK 12kHz，20ms 帧，40 字节/帧，输出 16kHz mono Float32
final class BLEOpusDecoder {

    private var decoder: OpaquePointer?
    /// Opus 输出采样率（16kHz 匹配 Whisper 输入要求）
    private let sampleRate: Int32 = 16000
    /// 每帧最大样本数（20ms @ 16kHz = 320 samples）
    private let maxFrameSamples: Int32 = 960  // 允许最大 60ms

    init?() {
        var error: Int32 = 0
        decoder = opus_decoder_create(sampleRate, 1, &error)
        guard error == 0, decoder != nil else {
            NSLog("[OpusDecoder] 创建解码器失败: error=%d", error)
            return nil
        }
        NSLog("[OpusDecoder] 解码器就绪 (16kHz mono)")
    }

    deinit {
        if let decoder {
            opus_decoder_destroy(decoder)
        }
    }

    /// 解码一个 Opus 帧（40 字节）为 Float32 PCM 样本
    /// - Parameter frameData: 40 字节的 Opus 帧（含 TOC byte）
    /// - Returns: 16kHz mono Float32 样本数组，解码失败返回空数组
    func decode(frame frameData: Data) -> [Float] {
        guard let decoder else { return [] }

        var pcmBuffer = [Int16](repeating: 0, count: Int(maxFrameSamples))
        let samplesDecoded = frameData.withUnsafeBytes { rawBuf -> Int32 in
            guard let ptr = rawBuf.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return -1 }
            return opus_decode(
                decoder,
                ptr, Int32(frameData.count),
                &pcmBuffer, maxFrameSamples,
                0  // no FEC
            )
        }

        guard samplesDecoded > 0 else { return [] }

        // Int16 → Float32 归一化
        return pcmBuffer[..<Int(samplesDecoded)].map { Float($0) / 32768.0 }
    }

    /// 解码一个 BLE 数据包（160 字节 = 4 个 40 字节 Opus 帧）
    /// - Parameter payload: 160 字节音频负载（BLE 协议层已剥离包头）
    /// - Returns: 16kHz mono Float32 样本数组
    func decodePacket(_ payload: Data) -> [Float] {
        var allSamples: [Float] = []
        // 每 40 字节一个 Opus 帧
        for offset in stride(from: 0, to: payload.count, by: 40) {
            let end = min(offset + 40, payload.count)
            let frame = payload[offset..<end]
            let samples = decode(frame: Data(frame))
            allSamples.append(contentsOf: samples)
        }
        return allSamples
    }
}
