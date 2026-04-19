## ADDED Requirements

### Requirement: 实验性模式下 TimelineMerger 驱动持久化
系统 SHALL 在实验性模式（`SpeechPipelineMode.experimentalArgmaxOSS`）下，录音会话结束时使用 `TimelineMerger.snapshot()` 产出的统一 timeline 构造 `SpeakerAttributedTranscriptDocument` 并落盘，替代 FluidAudio 后处理作为 JSON 主来源。

#### Scenario: 实验性模式会话结束持久化
- **WHEN** 实验性模式下录音会话结束
- **THEN** 系统从 `TimelineMerger.snapshot()` 取最终 chunk 列表，构造并保存 `.json` sidecar，其中每条 chunk 包含 `text`、`startTimeSeconds`、`endTimeSeconds`、`speakerLabel?` 字段

#### Scenario: 默认模式持久化路径不变
- **WHEN** `SpeechPipelineMode` 为 `legacyWhisperCPP`
- **THEN** 持久化流程与 Phase 1 前完全一致，通过 FluidAudio 离线 diarization 生成 JSON
