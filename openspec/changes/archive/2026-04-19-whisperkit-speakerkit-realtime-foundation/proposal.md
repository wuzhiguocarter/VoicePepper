## Why

`WhisperKit + SpeakerKit` 已被确定为 VoicePepper 在 Apple Silicon 端侧统一语音栈的长期优先方向，但当前仓库仍以 `whisper.cpp + FluidAudio` 为主链。直接一次性切换风险过高，且 Argmax 开源 SDK 的能力边界也要求先做迁移基础设施，而不是假设开源版已经提供完整“实时带 speaker”的现成接口。

因此本次 change 的目标不是立即完成整条终局链路，而是先在当前仓库中落地可演进的基础设施：

- 接入 `argmax-oss-swift`，引入 `WhisperKit` / `SpeakerKit`
- 抽象统一的实时语音事件模型和 timeline merger
- 为 WhisperKit / SpeakerKit 提供实验性服务适配层
- 保持现有 `whisper.cpp + FluidAudio` 默认路径不变，避免现有功能回归

## What Changes

- 在 `Package.swift` 中引入 `argmax-oss-swift`，添加 `WhisperKit` 与 `SpeakerKit` 产品依赖
- 新增统一的实时语音数据模型：`AudioFrame`、`ASRTranscriptEvent`、`SpeakerSegmentEvent`、`RealtimeTranscriptChunk`
- 新增 `TimelineMerger`，用于合并 ASR 与 diarization 事件
- 新增实验性 `WhisperKitASRService` 与 `SpeakerKitDiarizationService`
- 为结构化 transcript 增加 `engineMetadata`
- 新增实验性配置入口，但默认仍使用现有 `whisper.cpp + FluidAudio`

## Impact

- 为后续迁移到 `WhisperKit + SpeakerKit` 提供实际代码落点
- 不改变当前默认录音与转录用户路径
- 允许在本地逐步验证新栈的模型初始化、事件输出和 timeline 合并能力
