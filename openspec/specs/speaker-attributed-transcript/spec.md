# Spec: speaker-attributed-transcript

## Purpose

在录音会话结束后，为已保存的 WAV 录音生成本地 speaker diarization 结果，并将带 speaker 标签的结构化 transcript 持久化为 sidecar 文件。

## Requirements

### Requirement: 录音会话结束后生成 speaker-attributed transcript
系统 SHALL 在录音会话结束并成功保存 WAV 后，使用本地 `FluidAudio` 离线 diarization 为该会话生成带 speaker 标签的结构化 transcript。

#### Scenario: diarization 成功
- **WHEN** 一次录音会话结束且对应 WAV 文件保存成功
- **THEN** 系统使用 `FluidAudio` 对该 WAV 文件执行离线 speaker diarization，并生成同名 `.json` transcript sidecar

#### Scenario: diarization 失败时回退
- **WHEN** `FluidAudio` 模型准备失败、推理失败或输出不可用
- **THEN** 系统仍然保存 WAV 和纯文本 `.txt`，且不因 diarization 失败中断录音持久化流程

### Requirement: speaker-attributed transcript 持久化格式
系统 SHALL 将结构化 transcript 保存为与录音同名的 UTF-8 JSON 文件，至少包含会话时间、全文文本、speaker chunk 列表以及为 future speaker identification 预留的可选字段。

#### Scenario: 生成 sidecar 文件
- **WHEN** `Recording_20260419_193000.wav` 的 diarization 成功
- **THEN** 系统在同目录生成 `Recording_20260419_193000.json`

#### Scenario: 结构化字段完整
- **WHEN** 系统写入 transcript JSON
- **THEN** 每个 chunk 至少包含 `text`、`timestamp`、`speakerLabel` 字段，并允许存在 `speakerProfileID` 等可选字段

#### Scenario: 结构化字段包含引擎元数据
- **WHEN** 系统写入 transcript JSON
- **THEN** sidecar 支持记录 `asrEngine`、`diarizationEngine`、`modelVersion` 等引擎元数据，用于比较不同本地推理栈

### Requirement: speaker 标签回填到实时转录条目
系统 SHALL 将录音会话中的实时转录条目按时间顺序映射到 diarization 结果，并为每条文本分配一个 speaker 标签。

#### Scenario: 匹配到说话人片段
- **WHEN** 某条实时转录时间点落在 diarization 的 `SPEAKER_01` 片段内
- **THEN** 对应 transcript chunk 的 `speakerLabel` 设为 `SPEAKER_01`

#### Scenario: 无法匹配片段
- **WHEN** 某条实时转录条目无法映射到任何 diarization 片段
- **THEN** 系统保留该条文本，并允许 `speakerLabel` 为空或标记为未知，而不丢弃文本

### Requirement: 实验性模式下 TimelineMerger 驱动持久化
系统 SHALL 在实验性模式（`SpeechPipelineMode.experimentalArgmaxOSS`）下，录音会话结束时使用 `TimelineMerger.snapshot()` 产出的统一 timeline 构造 `SpeakerAttributedTranscriptDocument` 并落盘，替代 FluidAudio 后处理作为 JSON 主来源。

#### Scenario: 实验性模式会话结束持久化
- **WHEN** 实验性模式下录音会话结束
- **THEN** 系统从 `TimelineMerger.snapshot()` 取最终 chunk 列表，构造并保存 `.json` sidecar，其中每条 chunk 包含 `text`、`startTimeSeconds`、`endTimeSeconds`、`speakerLabel?` 字段

#### Scenario: 默认模式持久化路径不变
- **WHEN** `SpeechPipelineMode` 为 `legacyWhisperCPP`
- **THEN** 持久化流程与 Phase 1 前完全一致，通过 FluidAudio 离线 diarization 生成 JSON
