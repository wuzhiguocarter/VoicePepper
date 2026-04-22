import Foundation
import Combine
import VoicePepperCore

// MARK: - CLI 参数解析

struct CLIArgs {
    let wavPath: String
    let lang: String
    let whisperKitModel: String
    let noSpeaker: Bool

    static func parse() -> CLIArgs? {
        var args = ArraySlice(CommandLine.arguments.dropFirst())
        var wavPath: String? = nil
        var lang = "zh"
        var whisperKitModel = "large-v3"
        var noSpeaker = false

        while !args.isEmpty {
            let arg = args.removeFirst()
            switch arg {
            case "--wav":
                guard let next = args.first else { printUsage(); return nil }
                args = args.dropFirst()
                wavPath = next
            case "--lang":
                guard let next = args.first else { printUsage(); return nil }
                args = args.dropFirst()
                lang = next
            case "--whisperkit-model":
                guard let next = args.first else { printUsage(); return nil }
                args = args.dropFirst()
                whisperKitModel = next
            case "--no-speaker":
                noSpeaker = true
            default:
                fputs("未知参数: \(arg)\n", stderr)
                printUsage()
                return nil
            }
        }

        guard let path = wavPath else {
            fputs("缺少必填参数 --wav\n", stderr)
            printUsage()
            return nil
        }

        return CLIArgs(wavPath: path, lang: lang, whisperKitModel: whisperKitModel, noSpeaker: noSpeaker)
    }

    private static func printUsage() {
        fputs("""
        用法: VoicePepperEval --wav <路径> [--lang zh|en] [--whisperkit-model <名称>] [--no-speaker]

        选项:
          --wav <路径>              WAV 文件路径（16kHz mono）
          --lang <zh|en>            转录语言（默认 zh）
          --whisperkit-model <名称> WhisperKit 模型名称（默认 large-v3）
          --no-speaker              禁用 SpeakerKit（仅 ASR，速度更快）

        """, stderr)
    }
}

// MARK: - 输出数据结构

struct TranscriptChunkOutput: Codable {
    let text: String
    let start: Double
    let end: Double
    let speaker: String?
}

// MARK: - 检查参数

guard let args = CLIArgs.parse() else { exit(1) }

let wavURL = URL(fileURLWithPath: args.wavPath)
guard FileManager.default.fileExists(atPath: args.wavPath) else {
    fputs("错误: 文件不存在 \(args.wavPath)\n", stderr)
    exit(1)
}

// MARK: - 初始化服务

let asrService = WhisperKitASRService(modelName: args.whisperKitModel, language: args.lang)
let speakerService: SpeakerKitDiarizationService? = args.noSpeaker ? nil : SpeakerKitDiarizationService()
let merger = TimelineMerger()
let fileSource = AudioFileSource()

// MARK: - 预热模型

fputs("[VoicePepperEval] 正在加载 WhisperKit 模型 (\(args.whisperKitModel))...\n", stderr)
await asrService.prepareModel()
fputs("[VoicePepperEval] 模型就绪\n", stderr)

// MARK: - 注册回调

await asrService.setCallback { event in
    Task { _ = await merger.applyASREvent(event, source: .filePlayback) }
}

if let sk = speakerService {
    await sk.setCallback { events in
        Task {
            for ev in events { _ = await merger.applySpeakerEvent(ev) }
        }
    }
}

// MARK: - 订阅音频分段

var cancellables = Set<AnyCancellable>()
fileSource.audioSegmentPublisher
    .sink { segment in
        Task { await asrService.enqueue(segment) }
        if let sk = speakerService { Task { await sk.enqueue(segment) } }
    }
    .store(in: &cancellables)

// MARK: - 播放文件

fputs("[VoicePepperEval] 开始处理: \(args.wavPath)\n", stderr)
await fileSource.play(url: wavURL, chunkDuration: 15.0)
fputs("[VoicePepperEval] 音频播放完成，等待转录任务...\n", stderr)

// MARK: - 等待所有异步任务完成

await asrService.waitUntilIdle()
if let sk = speakerService { await sk.waitUntilIdle() }
fputs("[VoicePepperEval] 转录完成\n", stderr)

// MARK: - 输出结果 JSON

let chunks = await merger.snapshot()
let output = chunks.map { chunk in
    TranscriptChunkOutput(
        text: chunk.text,
        start: chunk.startTimeSeconds,
        end: chunk.endTimeSeconds,
        speaker: chunk.speakerLabel
    )
}

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted]
guard let jsonData = try? encoder.encode(output),
      let jsonStr = String(data: jsonData, encoding: .utf8) else {
    fputs("错误: JSON 序列化失败\n", stderr)
    exit(1)
}
print(jsonStr)
