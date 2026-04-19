## ADDED Requirements

### Requirement: filePlayback 音频路由分支
系统 SHALL 在 `AppDelegate` 中为 `RecordingSource.filePlayback` 增加独立的音频路由分支，将 `AudioFileSource.audioSegmentPublisher` 的输出路由至 `WhisperKitASRService`（实验性模式），复用现有 WhisperKit → TimelineMerger → `realtimeChunks` 链路，不修改麦克风和 BLE 的现有路由逻辑。

#### Scenario: filePlayback 模式下音频段路由
- **WHEN** `appState.recordingSource == .filePlayback` 且 `appState.speechPipelineMode == .experimentalArgmaxOSS`，且 `AudioFileSource` 发布一个 `AudioSegment`
- **THEN** 该 `AudioSegment` 被提交给 `WhisperKitASRService.enqueue()`，若 `SpeakerKitDiarizationService` 已初始化则同时提交给它，不经过 `TranscriptionService`（whisper.cpp）

#### Scenario: 麦克风和 BLE 路由不受影响
- **WHEN** `appState.recordingSource` 为 `.microphone` 或 `.bluetoothRecorder`
- **THEN** 音频路由行为与引入 filePlayback 之前完全相同，`AudioFileSource` 不参与路由

### Requirement: filePlayback 跳过麦克风权限检查
系统 SHALL 在 `handleToggleRecording` 中，当录音源为 `filePlayback` 时跳过麦克风权限检查，直接触发 `AudioFileSource.play(url:)`。

#### Scenario: filePlayback 启动不触发麦克风权限
- **WHEN** 调用 `handleToggleRecording()` 且 `recordingSource == .filePlayback`
- **THEN** 系统不请求麦克风权限，直接调用 `audioFileSource.play(url:)` 开始文件回放
