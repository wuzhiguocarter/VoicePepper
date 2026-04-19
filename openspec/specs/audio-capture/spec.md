## ADDED Requirements

### Requirement: 后台麦克风录音
系统 SHALL 通过 AVAudioEngine 捕获麦克风输入，在应用无焦点时保持后台录音能力，输出 16kHz mono PCM 格式音频数据供转录模块消费。

#### Scenario: 开始录音
- **WHEN** 用户触发录音快捷键且麦克风权限已授权
- **THEN** 系统开始捕获麦克风音频，状态变为"录音中"

#### Scenario: 麦克风权限未授权
- **WHEN** 用户触发录音快捷键但麦克风权限未授权
- **THEN** 系统弹出权限引导提示，不开始录音

#### Scenario: 停止录音
- **WHEN** 用户再次触发快捷键或点击停止
- **THEN** 系统停止音频捕获，将剩余缓冲区数据推送给转录模块

### Requirement: 音频格式转换
系统 SHALL 将 AVAudioEngine 输出的原始音频格式（通常 44.1kHz/48kHz stereo float32）实时转换为 whisper.cpp 所需的 16kHz mono float32 格式。

#### Scenario: 采样率转换
- **WHEN** 麦克风输入采样率不等于 16000Hz
- **THEN** 系统使用 AVAudioConverter 进行实时重采样，转换后数据误差不超过 -60dBFS

#### Scenario: 声道合并
- **WHEN** 麦克风输入为立体声
- **THEN** 系统将左右声道混合为单声道（取平均值）

### Requirement: 环形缓冲区管理
系统 SHALL 维护一个最大 30 分钟容量的音频环形缓冲区，防止长时间录音导致内存溢出。

#### Scenario: 缓冲区未溢出
- **WHEN** 录音时长未超过 30 分钟
- **THEN** 所有音频数据均完整保留并可供转录

#### Scenario: 缓冲区溢出保护
- **WHEN** 录音时长超过 30 分钟
- **THEN** 系统自动丢弃最早的音频数据，保持缓冲区在内存限制内，并在 UI 显示警告

### Requirement: pipeline 感知音频路由
系统 SHALL 根据当前 `SpeechPipelineMode` 将 VAD 分段的 `AudioSegment` 路由到正确的转录引擎，`AudioCaptureService` 自身不感知路由逻辑。

#### Scenario: 路由决策发生在管道组装层
- **WHEN** `AudioCaptureService.audioSegmentPublisher` 发出一个 `AudioSegment`
- **THEN** 管道组装层（`AppDelegate`）根据 `appState.speechPipelineMode` 决定将其发送给 `TranscriptionService` 还是 `WhisperKitASRService`，`AudioCaptureService` 不参与此决策

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
