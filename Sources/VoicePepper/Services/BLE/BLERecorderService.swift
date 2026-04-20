import Foundation
import Combine
import VoicePepperCore

// MARK: - BLE Recorder Service

/// 业务层：组合 BLEDeviceManager + BLEProtocol，管理实时转写会话，输出 AudioSegment
final class BLERecorderService {

    /// 发出转写就绪的音频段，供 TranscriptionService 消费
    let audioSegmentPublisher = PassthroughSubject<AudioSegment, Never>()
    /// 音频电平（0.0-1.0）供 UI 波形显示
    let levelPublisher = PassthroughSubject<Float, Never>()
    /// 会话结束时发出全部 PCM 样本和会话时间边界，供 RecordingFileService 持久化
    let sessionEndPublisher = PassthroughSubject<RecordingSessionData, Never>()

    private let deviceManager: BLEDeviceManager
    private let protocol_ = BLEProtocol()
    private let opusDecoder: BLEOpusDecoder?
    private weak var appState: AppState?
    private var cancellables = Set<AnyCancellable>()

    /// 音频累积缓冲区
    private var audioBuffer: [Float] = []
    /// 当前会话全部样本（所有段合并）
    private var sessionSamples: [Float] = []
    /// 缓冲区阈值：约 4 秒 16kHz 音频
    private let bufferThreshold = 16000 * 4
    /// 是否处于实时转写会话中
    private var isTranscribing = false
    private var sessionStartedAt: Date?

    /// 调试用：原始 BLE 音频数据 dump 文件
    private var rawDumpHandle: FileHandle?
    private var rawDumpPacketCount = 0

    // MARK: Init

    init(deviceManager: BLEDeviceManager, appState: AppState) {
        self.deviceManager = deviceManager
        self.appState = appState
        self.opusDecoder = BLEOpusDecoder()
        setupSubscriptions()
    }

    // MARK: - Public API

    /// 开始实时转写（发送命令到录音笔）
    func startRealtimeTranscription() {
        guard deviceManager.connectionState == .connected else {
            NSLog("[BLERecorderService] 设备未连接，无法启动实时转写")
            return
        }
        isTranscribing = true
        audioBuffer.removeAll()
        sessionSamples.removeAll()
        sessionStartedAt = Date()

        // 调试：开始 dump 原始音频数据
        startRawDump()

        deviceManager.sendCommand(type: .audio, command: BLERealtimeCommand.start.rawValue)
        NSLog("[BLERecorderService] 发送开始实时转写命令")
    }

    /// 结束实时转写
    func stopRealtimeTranscription() {
        guard isTranscribing else { return }
        deviceManager.sendCommand(type: .audio, command: BLERealtimeCommand.stop.rawValue)
        flushBuffer()
        emitSessionEnd()
        isTranscribing = false

        // 调试：停止 dump
        stopRawDump()

        NSLog("[BLERecorderService] 发送结束实时转写命令")
    }

    /// 暂停实时转写
    func pauseRealtimeTranscription() {
        deviceManager.sendCommand(
            type: .audio,
            command: BLERealtimeCommand.pauseResume.rawValue,
            payload: Data([1])  // 1=暂停
        )
    }

    /// 继续实时转写
    func resumeRealtimeTranscription() {
        deviceManager.sendCommand(
            type: .audio,
            command: BLERealtimeCommand.pauseResume.rawValue,
            payload: Data([0])  // 0=继续
        )
    }

    // MARK: - Private: Subscriptions

    private func setupSubscriptions() {
        // 主数据通道（0xAE22）：音频数据 + 控制回复
        deviceManager.dataReceivedPublisher
            .sink { [weak self] data in self?.handleDataChannel(data) }
            .store(in: &cancellables)

        // 按键/电量通道（0xAE23）
        deviceManager.buttonReceivedPublisher
            .sink { [weak self] data in self?.handleButtonChannel(data) }
            .store(in: &cancellables)

        // 注意：BLE 状态 → AppState 的同步由 AppDelegate 负责（直接 Combine 订阅，避免异步中间层丢失状态）
    }

    // MARK: - Private: Data Channel (0xAE22)

    private func handleDataChannel(_ rawData: Data) {
        guard let packet = protocol_.unpack(rawData) else { return }

        // 发送 ACK
        deviceManager.sendACK(
            seqNo: packet.seqNo,
            type: BLEDataType(rawValue: packet.dataType) ?? .control,
            command: packet.command
        )

        guard let dataType = BLEDataType(rawValue: packet.dataType) else { return }

        switch dataType {
        case .audio:
            handleRealtimeAudio(packet)
        case .control:
            handleControlReply(packet)
        default:
            break
        }
    }

    // MARK: - Private: Realtime Audio

    private func handleRealtimeAudio(_ packet: BLEParsedPacket) {
        guard let cmd = BLERealtimeCommand(rawValue: packet.command) else { return }

        switch cmd {
        case .audioData:
            guard isTranscribing else { return }
            // 调试：dump 原始音频负载
            dumpRawPayload(packet.payload)

            // Opus 解码：160 字节 = 4 × 40 字节 Opus 帧 → 16kHz Float32 PCM
            let samples = opusDecoder?.decodePacket(packet.payload) ?? []
            guard !samples.isEmpty else { return }
            audioBuffer.append(contentsOf: samples)
            sessionSamples.append(contentsOf: samples)

            // RMS 电平
            let rms = computeRMS(samples)
            levelPublisher.send(rms)

            // 缓冲区满则发出一个 AudioSegment
            if audioBuffer.count >= bufferThreshold {
                let segment = AudioSegment(samples: audioBuffer, capturedAt: Date())
                audioSegmentPublisher.send(segment)
                audioBuffer.removeAll()
            }

        case .deviceState:
            // 设备端停止/暂停/继续
            guard let param = packet.payload.first else { return }
            switch param {
            case 0: // 继续
                NSLog("[BLERecorderService] 设备端继续转写")
            case 1: // 暂停
                NSLog("[BLERecorderService] 设备端暂停转写")
            case 2: // 停止
                NSLog("[BLERecorderService] 设备端停止转写")
                flushBuffer()
                emitSessionEnd()
                isTranscribing = false
                // 通知 AppState 停止录音
                DispatchQueue.main.async { [weak self] in
                    self?.appState?.stopRecording()
                }
            default:
                break
            }

        default:
            break
        }
    }

    // MARK: - Private: Control Reply

    private func handleControlReply(_ packet: BLEParsedPacket) {
        guard let cmd = BLEControlCommand(rawValue: packet.command) else { return }

        switch cmd {
        case .replyBattery:
            guard let level = packet.payload.first else { return }
            DispatchQueue.main.async { [weak self] in
                self?.deviceManager.batteryLevel = Int(level)
            }

        case .replyDeviceStatus:
            guard let status = packet.payload.first else { return }
            DispatchQueue.main.async { [weak self] in
                self?.deviceManager.deviceStatus = BLEDeviceStatus(rawValue: status)
            }

        default:
            break
        }
    }

    // MARK: - Private: Button Channel (0xAE23)

    private func handleButtonChannel(_ rawData: Data) {
        guard let packet = protocol_.unpack(rawData) else { return }

        // 发送 ACK
        deviceManager.sendACK(
            seqNo: packet.seqNo,
            type: BLEDataType(rawValue: packet.dataType) ?? .button,
            command: packet.command
        )

        guard packet.dataType == BLEDataType.button.rawValue,
              let cmd = BLEButtonCommand(rawValue: packet.command) else { return }

        switch cmd {
        case .devStartRecording:
            NSLog("[BLERecorderService] 录音笔按键：开始录音")
            // 回复成功 ACK
            deviceManager.sendACK(
                seqNo: packet.seqNo,
                type: .button,
                command: BLEButtonCommand.ackStartRecording.rawValue,
                payload: Data([1])  // 1=成功
            )
            // 触发 App 端录音
            DispatchQueue.main.async { [weak self] in
                self?.appState?.toggleRecordingAction?()
            }

        case .devSaveRecording:
            NSLog("[BLERecorderService] 录音笔按键：保存录音")
            deviceManager.sendACK(
                seqNo: packet.seqNo,
                type: .button,
                command: BLEButtonCommand.ackSaveRecording.rawValue,
                payload: Data([1])
            )
            DispatchQueue.main.async { [weak self] in
                guard let self, let state = self.appState,
                      state.recordingState.isRecording else { return }
                state.toggleRecordingAction?()
            }

        case .devPauseRecording:
            NSLog("[BLERecorderService] 录音笔按键：暂停录音")
            deviceManager.sendACK(
                seqNo: packet.seqNo,
                type: .button,
                command: BLEButtonCommand.ackPauseRecording.rawValue,
                payload: Data([1])
            )
            pauseRealtimeTranscription()

        case .devResumeRecording:
            NSLog("[BLERecorderService] 录音笔按键：继续录音")
            deviceManager.sendACK(
                seqNo: packet.seqNo,
                type: .button,
                command: BLEButtonCommand.ackResumeRecording.rawValue,
                payload: Data([1])
            )
            resumeRealtimeTranscription()

        default:
            break  // ACK 回复类型，App 不需要处理
        }
    }

    // MARK: - Private: Audio Helpers

    /// Int16 LE PCM → Float32 [-1.0, 1.0]
    private func convertInt16ToFloat32(_ data: Data) -> [Float] {
        let sampleCount = data.count / 2
        guard sampleCount > 0 else { return [] }

        return data.withUnsafeBytes { raw -> [Float] in
            let int16Ptr = raw.bindMemory(to: Int16.self)
            return (0..<sampleCount).map { Float(int16Ptr[$0]) / 32768.0 }
        }
    }

    private func computeRMS(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sumSq = samples.reduce(0) { $0 + $1 * $1 }
        return min(1.0, sqrt(sumSq / Float(samples.count)) * 10)
    }

    private func flushBuffer() {
        guard !audioBuffer.isEmpty else { return }
        let segment = AudioSegment(samples: audioBuffer, capturedAt: Date())
        audioSegmentPublisher.send(segment)
        audioBuffer.removeAll()
    }

    private func emitSessionEnd() {
        let completed = sessionSamples
        if !completed.isEmpty {
            let startedAt = sessionStartedAt ?? Date().addingTimeInterval(-Double(completed.count) / 16000.0)
            sessionEndPublisher.send(
                RecordingSessionData(
                    samples: completed,
                    startedAt: startedAt,
                    endedAt: Date()
                )
            )
        }
        sessionSamples.removeAll()
        sessionStartedAt = nil
    }

    // MARK: - Debug: Raw Audio Dump

    private func startRawDump() {
        let path = "/tmp/ble_audio_raw.bin"
        FileManager.default.createFile(atPath: path, contents: nil)
        rawDumpHandle = FileHandle(forWritingAtPath: path)
        rawDumpPacketCount = 0
        NSLog("[BLERecorderService] 开始 dump 原始音频到 %@", path)
    }

    private func dumpRawPayload(_ data: Data) {
        rawDumpHandle?.write(data)
        rawDumpPacketCount += 1
        if rawDumpPacketCount <= 3 {
            // 前 3 包完整 hex dump 方便分析
            NSLog("[BLERecorderService] 音频包 #%d (%d bytes): %@",
                  rawDumpPacketCount, data.count,
                  data.map { String(format: "%02X", $0) }.joined(separator: " "))
        }
        if rawDumpPacketCount % 100 == 0 {
            NSLog("[BLERecorderService] 已 dump %d 包", rawDumpPacketCount)
        }
    }

    private func stopRawDump() {
        rawDumpHandle?.closeFile()
        rawDumpHandle = nil
        NSLog("[BLERecorderService] dump 结束，共 %d 包", rawDumpPacketCount)
    }
}
