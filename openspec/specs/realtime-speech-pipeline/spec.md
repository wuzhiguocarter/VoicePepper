# Spec: realtime-speech-pipeline

## Purpose

提供统一的实时语音处理管道，协调 ASR 引擎与 speaker diarization 引擎的事件输出，通过 timeline merger 合并为带 speaker 标签的实时 transcript chunk，并为未来迁移到新本地语音栈（WhisperKit / SpeakerKit）预留实验性适配层。

## Requirements

### Requirement: 统一实时语音事件模型
系统 SHALL 提供统一的数据模型来表示音频帧、ASR 事件、speaker 事件和合并后的实时 transcript chunk，以支持未来迁移到新的本地语音栈。

#### Scenario: ASR 与 speaker 事件使用统一模型
- **WHEN** 实验性 ASR 引擎和 diarization 引擎向应用层输出事件
- **THEN** 应用层使用统一的数据模型承接这些事件，而不是直接把底层 SDK 类型暴露给 UI

### Requirement: Timeline merger 合并实时事件
系统 SHALL 提供 timeline merger，将 ASR 文本事件与 speaker segment 事件合并为统一 transcript chunk。

#### Scenario: 接收 ASR 事件
- **WHEN** merger 收到一条文本事件
- **THEN** 它更新或生成对应的 transcript chunk

#### Scenario: 接收 speaker 事件
- **WHEN** merger 收到一条 speaker segment 事件
- **THEN** 它尝试将 speaker 标签映射到时间重叠的 transcript chunk

### Requirement: 实验性 WhisperKit / SpeakerKit 适配层
系统 SHALL 提供实验性 `WhisperKit` 与 `SpeakerKit` 服务封装，以支持未来迁移验证，同时不影响当前默认链路。

#### Scenario: 初始化实验性 ASR 服务
- **WHEN** 应用启用实验性新栈
- **THEN** 系统可初始化 `WhisperKit` 适配层

#### Scenario: 初始化实验性 speaker 服务
- **WHEN** 应用启用实验性新栈
- **THEN** 系统可初始化 `SpeakerKit` 适配层

### Requirement: 实验性 WhisperKit 模型加载与预热
系统 SHALL 在实验性模式（`SpeechPipelineMode.experimentalArgmaxOSS`）下按需下载并缓存 WhisperKit 模型，首次录音启动时完成模型预热，预热完成前排队等待音频段。

#### Scenario: 首次进入实验性模式录音
- **WHEN** 用户在实验性模式下开始第一次录音
- **THEN** 系统触发 WhisperKit 模型下载（如缓存不存在），下载/加载完成后处理音频队列，首段转录结果在模型就绪后输出

#### Scenario: 模型已缓存时启动
- **WHEN** WhisperKit 模型已在系统缓存目录中存在
- **THEN** 系统直接加载缓存模型，不重新下载，加载时间 ≤ 5 秒

#### Scenario: 模型下载失败
- **WHEN** 网络不可用或下载超时
- **THEN** 系统捕获错误，记录日志，当次录音的音频段被丢弃（不崩溃）

### Requirement: 实验性模式端到端音频路由
系统 SHALL 在实验性模式激活时，将麦克风 VAD 分段后的 `AudioSegment` 路由给 `WhisperKitASRService` 进行转录，而不路由给 `TranscriptionService`（whisper.cpp）。

#### Scenario: 实验性模式麦克风录音
- **WHEN** `SpeechPipelineMode` 为 `experimentalArgmaxOSS` 且麦克风捕获到音频段
- **THEN** 该音频段被提交给 `WhisperKitASRService` 进行转录，不提交给 `TranscriptionService`

#### Scenario: 默认模式麦克风录音不受影响
- **WHEN** `SpeechPipelineMode` 为 `legacyWhisperCPP`
- **THEN** 音频段路由行为与 Phase 0 完全相同，不经过 `WhisperKitASRService`

### Requirement: WhisperKit 转录结果驱动 AppState
系统 SHALL 将 `WhisperKitASRService` 产出的 `ASRTranscriptEvent` 通过 `TimelineMerger.applyASREvent` 合并为 `RealtimeTranscriptChunk`，更新 `AppState.realtimeChunks`，Popover 在实验性模式下展示带说话人标签的 chunk 列表。

#### Scenario: WhisperKit 完成一段转录
- **WHEN** `WhisperKitASRService` 完成一个 `AudioSegment` 的转录
- **THEN** 转录文字经 `TimelineMerger.applyASREvent` 合并后更新 `AppState.realtimeChunks`，Popover 中实时可见

### Requirement: SpeakerKit 并行实时 diarization
系统 SHALL 在实验性模式（`SpeechPipelineMode.experimentalArgmaxOSS`）下，将麦克风 VAD 分段的 `AudioSegment` 同时提交给 `SpeakerKitDiarizationService` 进行并行 diarization，产出 `SpeakerSegmentEvent`。

#### Scenario: 实验性模式下 SpeakerKit 并行处理
- **WHEN** `SpeechPipelineMode` 为 `experimentalArgmaxOSS` 且麦克风捕获到音频段
- **THEN** 该音频段同时提交给 `WhisperKitASRService` 和 `SpeakerKitDiarizationService`，两者各自串行处理，互不阻塞

#### Scenario: SpeakerKit 初始化失败不影响 ASR
- **WHEN** `SpeakerKitDiarizationService` 模型下载或加载失败
- **THEN** 系统记录错误日志，ASR 路径继续正常产出转录文字，speaker 标签缺失但应用不崩溃

### Requirement: TimelineMerger 合并实时 ASR 与 speaker 事件
系统 SHALL 在实验性模式下，将 `ASRTranscriptEvent` 和 `SpeakerSegmentEvent` 都输入 `TimelineMerger`，产出含 `speakerLabel?` 的 `RealtimeTranscriptChunk` 列表，并更新 `AppState.realtimeChunks`。

#### Scenario: ASR 与 speaker 事件合并
- **WHEN** `TimelineMerger` 同时收到 ASR 事件和时间重叠的 speaker 事件
- **THEN** 对应 `RealtimeTranscriptChunk` 的 `speakerLabel` 被赋值为最佳匹配的 speaker 标签（如 `"S1"`）

#### Scenario: speaker 事件到来前的 ASR chunk
- **WHEN** ASR 事件先于 speaker 事件到达 TimelineMerger
- **THEN** 对应 chunk 的 `speakerLabel` 为 nil，不阻塞 chunk 输出；当 speaker 事件到达后，已有 chunk 的 speaker 标签被回填更新

### Requirement: AppState 实验性模式数据源
系统 SHALL 在 `AppState` 中新增 `realtimeChunks: [RealtimeTranscriptChunk]`，作为实验性模式下 Popover 的 UI 数据源；默认模式继续使用 `entries: [TranscriptionEntry]`。

#### Scenario: 实验性模式更新 realtimeChunks
- **WHEN** `TimelineMerger` 产出新的 chunk 列表
- **THEN** `AppState.realtimeChunks` 在 MainActor 上更新，Popover 重新渲染

#### Scenario: 会话结束清空 realtimeChunks
- **WHEN** 录音会话结束并完成持久化
- **THEN** `AppState.realtimeChunks` 被清空，与 `entries` 同步清空

### Requirement: 引擎模式配置 UI
系统 SHALL 在设置页提供引擎模式选择器，允许用户在 `legacyWhisperCPP` 和 `experimentalArgmaxOSS` 之间切换，切换结果持久化，下次启动生效。

#### Scenario: 用户切换引擎模式
- **WHEN** 用户在 Preferences 中选择"WhisperKit + SpeakerKit (Experimental)"
- **THEN** `AppState.speechPipelineMode` 更新并写入 `UserDefaults`，下次 App 启动后新模式生效

#### Scenario: 切换提示
- **WHEN** 用户完成引擎切换
- **THEN** 设置页显示"重启 App 后生效"说明文字
