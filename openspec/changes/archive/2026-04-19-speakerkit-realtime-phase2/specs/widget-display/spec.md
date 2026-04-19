## ADDED Requirements

### Requirement: 实验性模式 Popover 展示说话人标签
系统 SHALL 在实验性模式（`SpeechPipelineMode.experimentalArgmaxOSS`）下，Popover 面板展示 `RealtimeTranscriptChunk` 列表，每条 chunk 带有说话人 badge（如 `[S1]`），同时保持默认模式 Popover 行为不变。

#### Scenario: 实验性模式展示说话人 badge
- **WHEN** `SpeechPipelineMode` 为 `experimentalArgmaxOSS` 且 `AppState.realtimeChunks` 非空
- **THEN** Popover 展示每条 chunk 的说话人标签（格式 `[S1]`、`[S2]`）和转录文字，不同说话人用颜色或视觉区分

#### Scenario: chunk speakerLabel 为 nil 时回退展示
- **WHEN** 某条 `RealtimeTranscriptChunk` 的 `speakerLabel` 为 nil（speaker 事件尚未到达）
- **THEN** 该 chunk 展示转录文字，说话人位置显示占位符（如 `[?]`）或留空，不崩溃

#### Scenario: 默认模式 Popover 不受影响
- **WHEN** `SpeechPipelineMode` 为 `legacyWhisperCPP`
- **THEN** Popover 展示行为与 Phase 1 前完全一致，使用 `AppState.entries` 纯文本列表
