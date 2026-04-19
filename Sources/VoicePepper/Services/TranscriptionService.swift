import Foundation
import Combine

// MARK: - Transcription Service
// Receives AudioSegments, queues them for serial whisper.cpp transcription,
// and publishes results back to AppState.
// Subscribes to appState.$selectedModel for runtime hot-switching.

final class TranscriptionService {

    // Published: model ready / error (wired in AppDelegate)
    let modelReadyPublisher = PassthroughSubject<Bool, Never>()
    let modelErrorPublisher = PassthroughSubject<String, Never>()

    private let appState: AppState
    let modelManager: WhisperModelManager

    // Serial queue: prevents concurrent whisper inference
    private let transcriptionQueue = OperationQueue()

    private var cancellables = Set<AnyCancellable>()

    init(appState: AppState, modelManager: WhisperModelManager) {
        self.appState = appState
        self.modelManager = modelManager

        transcriptionQueue.maxConcurrentOperationCount = 1
        transcriptionQueue.qualityOfService = .userInitiated

        observeModelState()
        // 订阅需在 MainActor 上（appState 是 @MainActor 隔离）
        Task { @MainActor [weak self] in self?.observeSelectedModel() }
    }

    // MARK: - Lifecycle

    func start() {
        // 初始加载由 selectedModel 订阅驱动（observeSelectedModel dropFirst 已去掉），
        // 此处保留向后兼容：首次 start() 触发初始模型加载
        Task { [weak self] in
            guard let self else { return }
            let model = await MainActor.run { self.appState.selectedModel }
            NSLog("[TranscriptionService] start() 调用，加载模型: %@", model.rawValue)
            await self.modelManager.ensureModel(model)
        }
    }

    func stop() {
        transcriptionQueue.cancelAllOperations()
    }

    func waitUntilIdle() async {
        await withCheckedContinuation { continuation in
            transcriptionQueue.addBarrierBlock {
                continuation.resume()
            }
        }

        // `handleResult` appends entries on MainActor via Task; hop back once so pending
        // UI-state mutations triggered by finished operations are observed before snapshotting.
        await MainActor.run {}
    }

    // MARK: - Enqueue Segment

    func enqueue(_ segment: AudioSegment) {
        // switchModel 会先将 whisperContext 置 nil，切换期间此 guard 自然丢弃入队
        guard modelManager.whisperContext != nil else {
            NSLog("[TranscriptionService] 模型切换中，丢弃音频段")
            return
        }

        let op = TranscriptionOperation(
            segment: segment,
            context: modelManager.whisperContext!
        ) { [weak self] result in
            self?.handleResult(result, capturedAt: segment.capturedAt)
        }

        transcriptionQueue.addOperation(op)
    }

    // MARK: - Result Handler

    private func handleResult(_ result: Result<String, Error>, capturedAt: Date) {
        switch result {
        case .success(let text) where !text.isEmpty:
            let entry = TranscriptionEntry(
                text: text,
                timestamp: capturedAt,
                duration: 0
            )
            Task { @MainActor [weak self] in
                self?.appState.appendEntry(entry)
            }
        case .failure(let error):
            print("[TranscriptionService] Error: \(error)")
        default:
            break // empty transcription, skip
        }
    }

    // MARK: - Model State Observation

    private func observeModelState() {
        modelManager.statePublisher
            .sink { [weak self] state in
                switch state {
                case .ready:
                    self?.modelReadyPublisher.send(true)
                case .failed(let error):
                    self?.modelReadyPublisher.send(false)
                    self?.modelErrorPublisher.send(error.localizedDescription)
                    // 下载/加载失败时回退 selectedModel 到上一个成功的 activeModel
                    Task { @MainActor [weak self] in
                        guard let self,
                              let fallback = self.modelManager.activeModel else { return }
                        NSLog("[TranscriptionService] 模型加载失败，回退到 %@", fallback.rawValue)
                        self.appState.selectedModel = fallback
                    }
                default:
                    break
                }
            }
            .store(in: &cancellables)
    }

    /// 订阅 selectedModel 变化，触发热切换（必须在 @MainActor 上调用）
    @MainActor
    private func observeSelectedModel() {
        appState.$selectedModel
            .removeDuplicates()
            .dropFirst() // 跳过初始值，避免与 start() 重复加载
            .sink { [weak self] newModel in
                guard let self else { return }
                NSLog("[TranscriptionService] selectedModel 变化，切换到: %@", newModel.rawValue)
                self.transcriptionQueue.cancelAllOperations()
                Task { [weak self] in
                    await self?.modelManager.switchModel(newModel)
                }
            }
            .store(in: &cancellables)
    }
}

// MARK: - Transcription Operation

private final class TranscriptionOperation: Operation, @unchecked Sendable {
    private let segment: AudioSegment
    private let whisperContext: WhisperContext
    private let completion: (Result<String, Error>) -> Void

    init(segment: AudioSegment, context: WhisperContext, completion: @escaping (Result<String, Error>) -> Void) {
        self.segment = segment
        self.whisperContext = context
        self.completion = completion
    }

    override func main() {
        guard !isCancelled else { return }

        do {
            let text = try whisperContext.transcribe(samples: segment.samples)
            completion(.success(text))
        } catch {
            completion(.failure(error))
        }
    }
}
