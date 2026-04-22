## Why

现有 WER 评估依赖 App UI + AX 自动化（PyObjC + 物理显示器），无法在 CI headless 环境自动运行，且每次评估需手动确认 App 状态。需要一个 standalone 模式：复用 App 内部真实的 WhisperKit + SpeakerKit + TimelineMerger pipeline，以命令行方式批量处理 WAV 文件，输出 WER 报告。

## What Changes

- 新增 Swift 可执行 target `VoicePepperEval`（`Sources/VoicePepperEval/main.swift`）：复用 `WhisperKitASRService`、`SpeakerKitDiarizationService`、`TimelineMerger`、`AudioFileSource`，CLI 接受 WAV 路径 + 语言参数，输出 `RealtimeTranscriptChunk` JSON
- 更新 `Package.swift`：新增 `VoicePepperEval` executable target，与 `VoicePepper` 共享 library target
- 新增 `scripts/standalone_eval.py`：Python 驱动层，加载数据集（AISHELL-1 / AMI），调用 `VoicePepperEval` binary，解析 JSON，计算 WER，输出报告
- 新增 `tests/test_standalone_eval.py`：覆盖词级 WER 函数和报告生成的单元测试

## Capabilities

### New Capabilities

- `standalone-eval-pipeline`：基于真实 WhisperKit + SpeakerKit pipeline 的 headless 批量评估能力，支持 AISHELL-1（中文字符级 WER）和 AMI（英文词级 WER）

### Modified Capabilities

- `audio-capture`：将 `WhisperKitASRService`、`SpeakerKitDiarizationService`、`TimelineMerger`、`AudioFileSource`、`RealtimeTranscriptChunk` 从 `VoicePepper` App target 提取到共享 library target，供 `VoicePepperEval` 复用

## Impact

- `Package.swift`：重构为 library + 两个 executable（`VoicePepper` App、`VoicePepperEval` CLI）
- 新增：`Sources/VoicePepperEval/main.swift`
- 新增：`scripts/standalone_eval.py`、`tests/test_standalone_eval.py`
- 依赖不变（WhisperKit、SpeakerKit、FluidAudio 均已在 Package.swift 中）
