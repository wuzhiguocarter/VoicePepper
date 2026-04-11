import Foundation
import Combine

// MARK: - Transcription Service (Tasks 5.5, 5.6)
// Receives AudioSegments, queues them for serial whisper.cpp transcription,
// and publishes results back to AppState.

final class TranscriptionService {

    // Published: model ready / error (wired in AppDelegate)
    let modelReadyPublisher = PassthroughSubject<Bool, Never>()
    let modelErrorPublisher = PassthroughSubject<String, Never>()

    private let appState: AppState
    private let modelManager = WhisperModelManager()

    // Task 5.6 - serial queue: prevents concurrent whisper inference
    private let transcriptionQueue = OperationQueue()

    private var cancellables = Set<AnyCancellable>()

    init(appState: AppState) {
        self.appState = appState

        // Serial queue
        transcriptionQueue.maxConcurrentOperationCount = 1
        transcriptionQueue.qualityOfService = .userInitiated

        observeModelState()
    }

    // MARK: - Lifecycle

    func start() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let model = self.appState.selectedModel
            NSLog("[TranscriptionService] start() 调用，加载模型: %@", model.rawValue)
            await self.modelManager.ensureModel(model)
        }
    }

    func stop() {
        transcriptionQueue.cancelAllOperations()
    }

    // MARK: - Enqueue Segment

    func enqueue(_ segment: AudioSegment) {
        guard modelManager.whisperContext != nil else { return }

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

    // MARK: - Model State

    private func observeModelState() {
        modelManager.statePublisher
            .sink { [weak self] state in
                switch state {
                case .ready:
                    self?.modelReadyPublisher.send(true)
                case .failed(let error):
                    self?.modelReadyPublisher.send(false)
                    self?.modelErrorPublisher.send(error.localizedDescription)
                default:
                    break
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
