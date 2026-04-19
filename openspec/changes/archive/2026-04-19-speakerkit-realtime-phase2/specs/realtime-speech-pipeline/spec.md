## MODIFIED Requirements

### Requirement: WhisperKit 转录结果驱动 AppState
系统 SHALL 将 `WhisperKitASRService` 产出的 `ASRTranscriptEvent` 通过 `TimelineMerger.applyASREvent` 合并为 `RealtimeTranscriptChunk`，更新 `AppState.realtimeChunks`，Popover 在实验性模式下展示带说话人标签的 chunk 列表。

#### Scenario: WhisperKit 完成一段转录
- **WHEN** `WhisperKitASRService` 完成一个 `AudioSegment` 的转录
- **THEN** 转录文字经 `TimelineMerger.applyASREvent` 合并后更新 `AppState.realtimeChunks`，Popover 中实时可见

## ADDED Requirements

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
