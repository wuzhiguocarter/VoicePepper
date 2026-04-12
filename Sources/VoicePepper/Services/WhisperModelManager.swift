import Foundation
import Combine

// MARK: - Model Download State

enum ModelLoadState {
    case idle
    case downloading(progress: Double)
    case loading
    case ready
    case failed(Error)
}

// MARK: - Whisper Model Manager

final class WhisperModelManager: NSObject, ObservableObject {

    /// 向后兼容：现有 TranscriptionService 订阅此 publisher
    let statePublisher = CurrentValueSubject<ModelLoadState, Never>(.idle)

    /// 当前已加载到内存的模型
    @Published private(set) var activeModel: WhisperModel?

    /// 每个模型的独立下载/加载状态，供 UI 逐行展示
    @Published private(set) var modelStates: [WhisperModel: ModelLoadState] = [:]

    private(set) var whisperContext: WhisperContext?

    // ~/Library/Application Support/VoicePepper/models/
    static var modelsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("VoicePepper/models", isDirectory: true)
    }

    // MARK: - Public: Local Status

    /// 检测模型文件是否已下载到本地
    func isModelDownloaded(_ model: WhisperModel) -> Bool {
        let path = Self.modelsDirectory.appendingPathComponent(model.filename).path
        return FileManager.default.fileExists(atPath: path)
    }

    // MARK: - Public: Switch Model

    /// 卸载旧模型上下文，加载新模型（下载或直接加载）
    func switchModel(_ model: WhisperModel) async {
        NSLog("[WhisperModelManager] switchModel: \(model.rawValue)")

        // 释放旧上下文（ARC 触发 C 层 deinit）
        whisperContext = nil
        activeModel = nil

        await ensureModel(model)
    }

    // MARK: - Load or Download

    /// 检测本地是否存在，不存在则先下载再加载
    func ensureModel(_ model: WhisperModel) async {
        let localPath = Self.modelsDirectory.appendingPathComponent(model.filename)
        NSLog("[WhisperModelManager] ensureModel: \(model.rawValue), path=\(localPath.path)")

        if FileManager.default.fileExists(atPath: localPath.path) {
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: localPath.path)[.size] as? Int) ?? 0
            NSLog("[WhisperModelManager] 本地模型存在，大小=\(fileSize) bytes，开始加载")
            await loadModel(model, at: localPath)
        } else {
            NSLog("[WhisperModelManager] 本地模型不存在，开始下载 url=\(model.downloadURL)")
            await downloadAndLoad(model: model, destination: localPath)
        }
    }

    // MARK: - Private: Load

    private func loadModel(_ model: WhisperModel, at url: URL) async {
        NSLog("[WhisperModelManager] loadModel 开始: \(url.lastPathComponent)")
        sendState(.loading, for: model)

        do {
            let t0 = Date()
            let context = try WhisperContext(modelPath: url.path)
            let elapsed = Date().timeIntervalSince(t0)
            self.whisperContext = context
            NSLog("[WhisperModelManager] 模型加载成功，耗时 %.2fs", elapsed)
            sendState(.ready, for: model)
            await MainActor.run { activeModel = model }
        } catch {
            NSLog("[WhisperModelManager] 模型加载失败: \(error)")
            sendState(.failed(error), for: model)
        }
    }

    // MARK: - Private: Download

    private func downloadAndLoad(model: WhisperModel, destination: URL) async {
        try? FileManager.default.createDirectory(
            at: Self.modelsDirectory,
            withIntermediateDirectories: true
        )

        sendState(.downloading(progress: 0), for: model)

        do {
            let (localTempURL, response) = try await URLSession.shared.download(from: model.downloadURL) { [weak self] _, totalBytesWritten, totalExpected in
                let progress = totalExpected > 0 ? Double(totalBytesWritten) / Double(totalExpected) : 0
                self?.sendState(.downloading(progress: progress), for: model)
            }

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }

            try FileManager.default.moveItem(at: localTempURL, to: destination)
            await loadModel(model, at: destination)

        } catch {
            sendState(.failed(error), for: model)
        }
    }

    // MARK: - Private: State Broadcast

    /// 同时更新 modelStates 字典（per-model UI）和向后兼容的 statePublisher
    private func sendState(_ state: ModelLoadState, for model: WhisperModel) {
        DispatchQueue.main.async { [weak self] in
            self?.modelStates[model] = state
        }
        statePublisher.send(state)
    }
}

// MARK: - URLSession download with progress

extension URLSession {
    func download(from url: URL, progress: @escaping (Int64, Int64, Int64) -> Void) async throws -> (URL, URLResponse) {
        return try await withCheckedThrowingContinuation { continuation in
            let task = self.downloadTask(with: url) { tempURL, response, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let tempURL, let response {
                    continuation.resume(returning: (tempURL, response))
                } else {
                    continuation.resume(throwing: URLError(.unknown))
                }
            }

            // Track progress via KVO observation
            let observation = task.observe(\.countOfBytesReceived, options: [.new]) { task, _ in
                progress(task.countOfBytesReceived, task.countOfBytesReceived, task.countOfBytesExpectedToReceive)
            }

            task.resume()

            // Hold observation alive until task completes
            withExtendedLifetime(observation) {}
        }
    }
}
