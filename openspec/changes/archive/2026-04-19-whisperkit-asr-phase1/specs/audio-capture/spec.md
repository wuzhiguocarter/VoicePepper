## MODIFIED Requirements

### Requirement: pipeline 感知音频路由
系统 SHALL 根据当前 `SpeechPipelineMode` 将 VAD 分段的 `AudioSegment` 路由到正确的转录引擎，`AudioCaptureService` 自身不感知路由逻辑。

#### Scenario: 路由决策发生在管道组装层
- **WHEN** `AudioCaptureService.audioSegmentPublisher` 发出一个 `AudioSegment`
- **THEN** 管道组装层（`AppDelegate`）根据 `appState.speechPipelineMode` 决定将其发送给 `TranscriptionService` 还是 `WhisperKitASRService`，`AudioCaptureService` 不参与此决策
