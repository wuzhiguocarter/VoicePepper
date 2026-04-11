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

// MARK: - Whisper Model Manager (Tasks 5.1 & 5.2)

final class WhisperModelManager: NSObject {

    let statePublisher = CurrentValueSubject<ModelLoadState, Never>(.idle)

    private(set) var whisperContext: WhisperContext?

    // ~/Library/Application Support/VoicePepper/models/
    static var modelsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("VoicePepper/models", isDirectory: true)
    }

    // MARK: - Load or Download

    /// Check local model exists; if not, download it first, then load.
    func ensureModel(_ model: WhisperModel) async {
        let localPath = Self.modelsDirectory.appendingPathComponent(model.filename)
        NSLog("[WhisperModelManager] ensureModel: \(model.rawValue), path=\(localPath.path)")

        if FileManager.default.fileExists(atPath: localPath.path) {
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: localPath.path)[.size] as? Int) ?? 0
            NSLog("[WhisperModelManager] 本地模型存在，大小=\(fileSize) bytes，开始加载")
            await loadModel(at: localPath)
        } else {
            NSLog("[WhisperModelManager] 本地模型不存在，开始下载 url=\(model.downloadURL)")
            await downloadAndLoad(model: model, destination: localPath)
        }
    }

    // MARK: - Private: Load

    private func loadModel(at url: URL) async {
        NSLog("[WhisperModelManager] loadModel 开始: \(url.lastPathComponent)")
        statePublisher.send(.loading)

        do {
            let t0 = Date()
            let context = try WhisperContext(modelPath: url.path)
            let elapsed = Date().timeIntervalSince(t0)
            self.whisperContext = context
            NSLog("[WhisperModelManager] 模型加载成功，耗时 %.2fs", elapsed)
            statePublisher.send(.ready)
        } catch {
            NSLog("[WhisperModelManager] 模型加载失败: \(error)")
            statePublisher.send(.failed(error))
        }
    }

    // MARK: - Private: Download (Task 5.2)

    private func downloadAndLoad(model: WhisperModel, destination: URL) async {
        // Create directory if needed
        try? FileManager.default.createDirectory(
            at: Self.modelsDirectory,
            withIntermediateDirectories: true
        )

        statePublisher.send(.downloading(progress: 0))

        do {
            let (localTempURL, response) = try await URLSession.shared.download(from: model.downloadURL) { bytesWritten, totalBytesWritten, totalExpected in
                let progress = totalExpected > 0 ? Double(totalBytesWritten) / Double(totalExpected) : 0
                DispatchQueue.main.async { [weak self] in
                    self?.statePublisher.send(.downloading(progress: progress))
                }
            }

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }

            try FileManager.default.moveItem(at: localTempURL, to: destination)
            await loadModel(at: destination)

        } catch {
            statePublisher.send(.failed(error))
        }
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
