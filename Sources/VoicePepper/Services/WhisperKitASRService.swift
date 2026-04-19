import Foundation
import WhisperKit

actor WhisperKitASRService {
    private let modelName: String
    private var whisperKit: WhisperKit?
    private var pendingTask: Task<Void, Never>?

    private var callback: (@Sendable (ASRTranscriptEvent) -> Void)?
    private var modelReadyCallback: (@Sendable (Bool, String) -> Void)?

    func setCallback(_ cb: @Sendable @escaping (ASRTranscriptEvent) -> Void) {
        callback = cb
    }

    func setModelReadyCallback(_ cb: @Sendable @escaping (Bool, String) -> Void) {
        modelReadyCallback = cb
    }

    init(modelName: String = "large-v3") {
        self.modelName = modelName
    }

    /// Enqueue a segment for serial transcription. Each call chains after the previous.
    func enqueue(_ segment: AudioSegment) {
        let previous = pendingTask
        pendingTask = Task {
            await previous?.value
            await processSegment(segment)
        }
    }

    private func processSegment(_ segment: AudioSegment) async {
        do {
            let events = try await transcribe(audioSamples: segment.samples)
            let cb = callback
            for event in events where !event.text.isEmpty {
                cb?(event)
            }
        } catch {
            NSLog("[WhisperKitASRService] 转录失败: %@", error.localizedDescription)
        }
    }

    /// Eagerly download and load the model. Safe to call multiple times.
    func prepareModel() async {
        let cb = modelReadyCallback
        cb?(false, "正在加载 WhisperKit 模型 (\(modelName))...")
        do {
            try await prepareIfNeeded()
            NSLog("[WhisperKitASRService] 模型预热完成")
            cb?(true, "WhisperKit 模型就绪")
        } catch {
            NSLog("[WhisperKitASRService] 模型预热失败: %@", error.localizedDescription)
            cb?(false, "WhisperKit 模型加载失败，请检查网络或重启 App")
        }
    }

    private func prepareIfNeeded() async throws {
        guard whisperKit == nil else { return }

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let tokenizerURL = docs.appendingPathComponent("huggingface/models/openai/whisper-\(modelName)")

        // 优先使用本地已下载的模型文件，跳过 HuggingFace 元数据验证
        if let localFolder = Self.localModelFolder(for: modelName) {
            NSLog("[WhisperKitASRService] 使用本地模型: %@", localFolder)
            let config = WhisperKitConfig(
                model: modelName,
                modelFolder: localFolder,
                tokenizerFolder: tokenizerURL,
                verbose: false,
                load: true,
                download: false
            )
            whisperKit = try await WhisperKit(config)
        } else {
            NSLog("[WhisperKitASRService] 开始下载模型: %@", modelName)
            let endpoint = ProcessInfo.processInfo.environment["HF_ENDPOINT"] ?? "https://huggingface.co"
            let config = WhisperKitConfig(
                model: modelName,
                modelEndpoint: endpoint,
                tokenizerFolder: tokenizerURL,
                verbose: false,
                load: true,
                download: true
            )
            whisperKit = try await WhisperKit(config)
        }
        NSLog("[WhisperKitASRService] 模型加载成功")
    }

    /// 检查 WhisperKit 默认缓存路径是否已有完整模型目录
    private static func localModelFolder(for modelName: String) -> String? {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let base = docs.appendingPathComponent("huggingface/models/argmaxinc/whisperkit-coreml")

        // WhisperKit 下载时使用 "openai_whisper-<modelName>" 作为文件夹名
        let folderName = "openai_whisper-\(modelName)"
        let folder = base.appendingPathComponent(folderName)

        // 检查必要文件是否存在
        let requiredFiles = ["config.json", "AudioEncoder.mlmodelc", "TextDecoder.mlmodelc"]
        let allExist = requiredFiles.allSatisfy {
            FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path)
        }
        return allExist ? folder.path : nil
    }

    private func transcribe(audioSamples: [Float]) async throws -> [ASRTranscriptEvent] {
        try await prepareIfNeeded()
        guard let whisperKit else { return [] }

        let options = DecodingOptions(language: "zh", skipSpecialTokens: true, wordTimestamps: true)
        let results = try await whisperKit.transcribe(audioArray: audioSamples, decodeOptions: options)

        return results.flatMap { result in
            result.segments.map { segment in
                ASRTranscriptEvent(
                    id: UUID(),
                    startTimeSeconds: Double(segment.start),
                    endTimeSeconds: Double(segment.end),
                    text: segment.text.trimmingCharacters(in: .whitespacesAndNewlines),
                    isFinal: true
                )
            }
        }
    }
}
