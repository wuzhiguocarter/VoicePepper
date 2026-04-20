## 背景

当前 `VoicePepper` App target 将所有 Swift 源码包含在一个 executable 中。核心 pipeline 服务（`WhisperKitASRService`、`SpeakerKitDiarizationService`、`TimelineMerger`、`AudioFileSource`）虽然没有 AppKit/SwiftUI 依赖，可以独立运行，但由于被包含在 App target 中，无法供 CLI 复用。

`RecordingSource` 和 `SpeechPipelineMode` 枚举定义在 `AppState.swift` 中，而 `TimelineMerger` 将 `RecordingSource` 作为参数，因此需要将其移动到共享层。

## 目标 / 非目标

**目标：**
- 将 `VoicePepperCore` 作为 library target 提取 pipeline 服务，供 App 和 CLI binary 共享
- `VoicePepperEval` CLI binary：接受 WAV 路径，运行 WhisperKit + SpeakerKit + TimelineMerger pipeline，将 `RealtimeTranscriptChunk[]` 以 JSON 格式输出到 stdout
- `scripts/standalone_eval.py`：Python 驱动层，通过 subprocess 调用 `VoicePepperEval` binary，计算 WER 并生成报告
- 在 CI headless macOS runner 上可运行（只需指定模型路径）

**非目标：**
- DER（Diarization Error Rate）评估 — Phase 3
- 实时流式模式
- Linux 支持

## 方案决策

### Package.swift 结构重组

```
VoicePepperCore（library）
  ├── Sources/VoicePepperCore/
  │   ├── PipelineTypes.swift        ← RecordingSource、SpeechPipelineMode（从 AppState.swift 分离）
  │   ├── RealtimeSpeechPipeline.swift  ← 迁移
  │   ├── AudioFileSource.swift      ← 迁移
  │   ├── WhisperKitASRService.swift ← 迁移
  │   ├── SpeakerKitDiarizationService.swift ← 迁移
  │   ├── TimelineMerger.swift       ← 迁移
  │   └── SpeakerAttributedTranscript.swift ← 迁移
  └── dependencies: WhisperKit, SpeakerKit, FluidAudio

VoicePepper（executable）— App UI
  ├── Sources/VoicePepper/           ← 其余 App 源码（AppState、AppDelegate、UI）
  └── dependencies: VoicePepperCore, CWhisper, COpus, KeyboardShortcuts

VoicePepperEval（executable）— CLI eval
  ├── Sources/VoicePepperEval/main.swift
  └── dependencies: VoicePepperCore
```

从 `AppState.swift` 中移除 `RecordingSource`/`SpeechPipelineMode` 后，添加 `import VoicePepperCore`。

### VoicePepperEval CLI 接口

```
.build/debug/VoicePepperEval \
  --wav /path/to/sample.wav \
  --lang zh \
  --whisperkit-model large-v3 \
  --speakerkit-model /path/to/models \
  [--no-speaker]          # 禁用 SpeakerKit（优先速度）
```

stdout 输出（JSON）：
```json
[
  {"text": "今天天气很好", "start": 0.0, "end": 4.2, "speaker": "S0"},
  {"text": "是的很晴朗",   "start": 4.5, "end": 7.1, "speaker": "S1"}
]
```

### VoicePepperEval main.swift 异步执行模式

Swift CLI 中运行 actor-based 服务时，使用 `@main` 或 `CommandLine` + `RunLoop` 模式：

```swift
import Foundation
import VoicePepperCore

// 在 Task {} 内协调 actor-isolated 服务
// 接收 AudioFileSource.sessionEndPublisher → pipeline 结束信号
// 调用 TimelineMerger.snapshot() → JSON 序列化
```

### SpeakerKit 初始化策略

`SpeakerKitDiarizationService` 默认值为 `download: true, load: true`。CLI 环境下可通过 `--no-speaker` 标志禁用。启用时显式指定模型路径，避免网络访问。

## 风险 / 权衡

- **文件迁移 → 编译错误风险**：`AppState.swift` 中 `RecordingSource` 的引用较多，迁移后必须添加 `import VoicePepperCore`。
- **SpeakerKit CLI 兼容性**：需要验证 SpeakerKit 在没有 macOS UI 上下文的情况下能否正常初始化。若有问题，则默认切换为 `--no-speaker`。
- **WhisperKit 模型路径**：CLI 通过环境变量 `VOICEPEPPER_MODEL_DIR` 或 `--whisperkit-model` 标志指定。默认路径为 `~/Library/Application Support/argmaxinc/whisperkit-coreml/`。
