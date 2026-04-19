## 1. SpeakerKitDiarizationService 改造

- [x] 1.1 将 `SpeakerKitDiarizationService` 的 `PyannoteConfig` 改为 `download: true, load: true`，移除 `@available(macOS 14.0, *)` 限制（与 WhisperKitASRService 对齐）
- [x] 1.2 添加 `private var pendingTask: Task<Void, Never>?` 串行队列和 `private var callback: (@Sendable ([SpeakerSegmentEvent]) -> Void)?`
- [x] 1.3 实现 `func setCallback(_ cb: @Sendable @escaping ([SpeakerSegmentEvent]) -> Void)` 方法
- [x] 1.4 实现 `func enqueue(_ segment: AudioSegment)` 方法，内部串行调用 `diarize`，结果通过 callback 回传；错误仅 NSLog，不抛出

## 2. AppState 扩展

- [x] 2.1 在 `AppState` 中新增 `@Published var realtimeChunks: [RealtimeTranscriptChunk] = []`
- [x] 2.2 新增 `func updateRealtimeChunks(_ chunks: [RealtimeTranscriptChunk])` 方法
- [x] 2.3 在 `clearSession()` 中同步清空 `realtimeChunks`

## 3. AppDelegate 接通 SpeakerKit + TimelineMerger

- [x] 3.1 在 `setupServices()` 的实验性模式块中，初始化 SpeakerKit 并注入 callback：diarization 结果经 `timelineMerger?.applySpeakerEvent` 后调用 `appState.updateRealtimeChunks`
- [x] 3.2 修改 `handleWhisperKitASREvent`：改为调用 `timelineMerger?.applyASREvent` 并将结果更新到 `appState.updateRealtimeChunks`（而不是直接 `appendEntry`）
- [x] 3.3 在 `audioService.audioSegmentPublisher` 的 sink 中，实验性模式下同时调用 `speakerKitService?.enqueue(segment)`
- [x] 3.4 在实验性模式的 session 结束 sink 中，用 `timelineMerger?.snapshot()` 构造持久化数据，新增 `RecordingFileService.saveWithRealtimeChunks`

## 4. Popover UI 改造

- [x] 4.1 在 `PopoverView`（或 `TranscriptionPopoverView`）中，根据 `appState.speechPipelineMode` 分叉渲染：实验性模式展示 `realtimeChunks`，默认模式展示 `entries`
- [x] 4.2 实现 `ChunkRowView`：展示 `[S1]` badge（speaker 为 nil 时显示 `[?]`）+ 转录文字，不同说话人用颜色区分（S1=蓝，S2=橙，S3+=紫，nil=灰）

## 5. 验证

- [x] 5.1 `swift build` 编译通过
- [x] 5.2 默认模式（legacyWhisperCPP）运行 `tests/e2e_test.py` 无回归
- [ ] 5.3 实验性模式下录音，日志确认 SpeakerKit enqueue 被调用、TimelineMerger 产出 chunk（手动验证，需真实录音）
