## 1. RecordingSource 枚举扩展

- [x] 1.1 在 `AppState.swift` 的 `RecordingSource` 枚举中新增 `case filePlayback = "filePlayback"`，不加入 `allCases`（通过自定义 `CaseIterable` 实现或移除 CaseIterable 自动合成）

## 2. AudioFileSource 服务实现

- [x] 2.1 创建 `Sources/VoicePepper/Services/AudioFileSource.swift`，包含 `audioSegmentPublisher`（`PassthroughSubject<AudioSegment, Never>`）和 `sessionEndPublisher`（`PassthroughSubject<RecordingSessionData, Never>`）
- [x] 2.2 实现 `play(url: URL, chunkDuration: TimeInterval = 1.5) async` 方法：用 `AVAudioFile` 读取 WAV，验证格式（16kHz mono），按 chunkDuration 分块推 `AudioSegment`，用 `Task.sleep` 控制时序
- [x] 2.3 实现格式验证：采样率不等于 16000Hz 或声道数不等于 1 时记录错误日志并发布空 `sessionEndPublisher`
- [x] 2.4 实现文件不存在/读取失败的错误处理：记录日志，直接返回不发布任何事件
- [x] 2.5 实现 `stop()` 方法，设置取消标志，使 `play()` 的循环提前退出

## 3. AppDelegate 路由接入

- [x] 3.1 在 `AppDelegate` 中声明并初始化 `audioFileSource: AudioFileSource` 实例
- [x] 3.2 在 `setupServices()` 中订阅 `audioFileSource.audioSegmentPublisher`，当 `recordingSource == .filePlayback` 且 `speechPipelineMode == .experimentalArgmaxOSS` 时，将 segment 路由至 `WhisperKitASRService.enqueue()` 和（可选）`SpeakerKitDiarizationService.enqueue()`
- [x] 3.3 在 `handleToggleRecording()` 中新增 `filePlayback` 分支：跳过麦克风权限检查，触发 `audioFileSource.play(url:)`（从 `UserDefaults` 或硬编码测试路径取 URL）

## 4. 评估脚本

- [x] 4.1 创建 `tests/file_playback_eval.py`：接受 `--wav <path>` 和 `--ref <text|txt_file>` 参数
- [x] 4.2 实现 WER 计算（使用 `jiwer` 库或手写 edit-distance），对比 `appState.realtimeChunks` 输出文本与 ground truth
- [x] 4.3 输出 WER 数值和转录文本对比表（hypothesis vs reference 行对行比较）
