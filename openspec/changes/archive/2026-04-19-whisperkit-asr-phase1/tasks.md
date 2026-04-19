## 1. WhisperKitASRService 改造：串行队列 + 按需加载

- [x] 1.1 在 `WhisperKitASRService` 中添加 `enqueue(_ segment: AudioSegment) async` 方法，内部维护串行任务队列（Task + actor 保证串行）
- [x] 1.2 将 `WhisperKitConfig` 改为 `load: true, download: true`，使首次 `prepareIfNeeded()` 触发模型下载（模型名 `"tiny"`）
- [x] 1.3 为 `enqueue` 添加错误捕获：下载/推理失败时 `NSLog` 记录错误，不抛出（保护主流程）
- [x] 1.4 添加 `callback: ((ASRTranscriptEvent) -> Void)?` 属性，转录完成后回调（供 AppDelegate 注入）

## 2. AppDelegate 音频路由分叉

- [x] 2.1 在 `AppDelegate.setupAudioServices()` 中，将 `audioService.audioSegmentPublisher` 的 `.sink` 改为按 `appState.speechPipelineMode` 分叉路由：`legacyWhisperCPP` 路由给 `transcriptionSvc?.enqueue`，`experimentalArgmaxOSS` 路由给 `experimentalWhisperKitService?.enqueue`
- [x] 2.2 在 `AppDelegate` 中实现 `handleWhisperKitASREvent(_ event: ASRTranscriptEvent)`：将事件映射为 `TranscriptionEntry(text: event.text, timestamp: ...)` 并追加到 `appState.entries`（在 MainActor 上执行）
- [x] 2.3 在 `experimentalWhisperKitService` 的 `callback` 注入 `handleWhisperKitASREvent`（在 `applicationDidFinishLaunching` 的实验性服务初始化块内）

## 3. Preferences UI 引擎选择器

- [x] 3.1 在 `PreferencesView` 中新增 "语音引擎" Section，包含 `Picker` 绑定 `appState.speechPipelineMode`，展示 `SpeechPipelineMode.allCases` 的 `displayName`
- [x] 3.2 在 Picker 下方添加说明文字（`Text`）：`"切换引擎后请重启 App 生效。Experimental 模式首次使用需下载模型（约 150MB）。"`

## 4. 验证

- [x] 4.1 `swift build` 编译通过（包含路由分叉和 UI 改动）
- [ ] 4.2 在 Preferences 切换到 `experimentalArgmaxOSS`，重启 App，录音后确认 Popover 出现文字（通过日志或 UI 观察，不要求精确文字匹配）
- [x] 4.3 切换回 `legacyWhisperCPP`，重启 App，录音后确认 whisper.cpp 链路仍正常工作（现有 E2E 测试通过）
- [x] 4.4 运行 `tests/e2e_test.py` 确认默认模式（`legacyWhisperCPP`）无回归
