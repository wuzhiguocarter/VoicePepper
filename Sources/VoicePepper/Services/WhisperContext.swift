import Foundation
import CWhisper

// MARK: - Whisper Context (Task 5.3)
// Thin Swift wrapper around whisper.cpp C API.
// Must be used from a single thread (serial queue).

final class WhisperContext {

    private var ctx: OpaquePointer?
    private(set) var isLoaded: Bool = false

    // MARK: Init / Deinit

    init(modelPath: String) throws {
        NSLog("[WhisperContext] 初始化 modelPath=\(modelPath)")

        // 加载 ggml 后端插件（Metal/BLAS/CPU），必须在 whisper_init 前调用
        // 否则 devices=0，whisper_init 在 make_buft_list 处崩溃
        ggml_backend_load_all()
        NSLog("[WhisperContext] ggml_backend_load_all 完成，设备数=%d", ggml_backend_dev_count())

        var cparams = whisper_context_default_params()

        // Task 5.8 - enable Metal on Apple Silicon
        #if arch(arm64)
        cparams.use_gpu = true
        NSLog("[WhisperContext] GPU 加速已启用 (arm64 Metal)")
        #else
        cparams.use_gpu = false
        #endif

        guard let context = whisper_init_from_file_with_params(modelPath, cparams) else {
            NSLog("[WhisperContext] whisper_init_from_file_with_params 返回 nil，模型加载失败")
            throw WhisperError.modelLoadFailed(path: modelPath)
        }
        self.ctx = context
        self.isLoaded = true
        NSLog("[WhisperContext] 模型加载成功")
    }

    deinit {
        if let ctx {
            whisper_free(ctx)
        }
    }

    // MARK: Transcription

    /// Transcribe 16kHz mono float32 samples, returns text or throws.
    func transcribe(samples: [Float], language: String = "auto") throws -> String {
        guard let ctx, isLoaded else {
            throw WhisperError.notLoaded
        }
        NSLog("[WhisperContext] transcribe 开始: %d 样本 (%.1fs), language=%@", samples.count, Double(samples.count)/16000.0, language)

        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.print_progress = false
        params.print_realtime = false
        params.print_timestamps = false
        params.language = (language as NSString).utf8String

        // Task 5.8 - run on GPU when available
        #if arch(arm64)
        params.n_threads = 4
        #else
        params.n_threads = Int32(ProcessInfo.processInfo.processorCount)
        #endif

        // 用简体中文 initial_prompt 引导模型优先输出简体，
        // 避免 whisper 对中文音频默认输出繁体字。
        // NSString 生命周期覆盖整个 whisper_full 调用，utf8String 指针安全。
        let promptNS = "以下是普通话的转录，请使用简体中文。" as NSString
        params.initial_prompt = promptNS.utf8String

        let whisperRet = samples.withUnsafeBufferPointer { ptr in
            whisper_full(ctx, params, ptr.baseAddress, Int32(samples.count))
        }

        guard whisperRet == 0 else {
            throw WhisperError.transcriptionFailed(code: Int(whisperRet))
        }

        // Collect all segments
        let segmentCount = whisper_full_n_segments(ctx)
        var text = ""
        for i in 0..<segmentCount {
            if let segText = whisper_full_get_segment_text(ctx, i) {
                text += String(cString: segText)
            }
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        NSLog("[WhisperContext] transcribe 完成: %d 段, 文本=%@", segmentCount, String(trimmed.prefix(100)))
        return trimmed
    }
}

// MARK: - Errors

enum WhisperError: LocalizedError {
    case modelLoadFailed(path: String)
    case notLoaded
    case transcriptionFailed(code: Int)

    var errorDescription: String? {
        switch self {
        case .modelLoadFailed(let path):
            return "无法加载 Whisper 模型：\(path)"
        case .notLoaded:
            return "Whisper 模型尚未加载"
        case .transcriptionFailed(let code):
            return "转录失败，错误码：\(code)"
        }
    }
}
