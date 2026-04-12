## 1. 录音文件存储服务

- [x] 1.1 新建 `Sources/VoicePepper/Services/RecordingFileService.swift`，定义 `RecordingItem` 模型（id、url、duration、createdAt）
- [x] 1.2 实现 `RecordingFileService.storageDirectory` 属性，返回并创建 `~/Library/Application Support/VoicePepper/Recordings/` 目录
- [x] 1.3 实现 `RecordingFileService.save(samples:sampleRate:)` 异步方法，接收整个会话的完整 PCM 样本（所有 VAD 段合并后），使用 `AVAssetWriter` 编码为一个 M4A 文件写入存储目录
- [x] 1.4 实现 `RecordingFileService.listRecordings()` 方法，枚举目录内 `.m4a` 文件，按修改时间降序返回 `[RecordingItem]`
- [x] 1.5 实现 `RecordingFileService.delete(item:)` 方法，删除磁盘文件并从列表移除

## 2. 接入录音流程

- [x] 2.1 在 `AppDelegate` 或 `VoicePepperApp` 中实例化 `RecordingFileService` 并注入 `AppState`
- [x] 2.2 在 `AudioCaptureService` 中维护 `sessionSamples: [Float]` 缓冲，每次 VAD 分段时追加样本；`stop()` 时通过 `sessionEndPublisher` 发出完整样本，`AppDelegate` 订阅后调用 `RecordingFileService.save()`
- [x] 2.3 在 `AppState` 中增加 `recordings: [RecordingItem]` 和 `currentlyPlayingId: UUID?` 发布属性

## 3. 历史录音列表 UI

- [x] 3.1 新建 `Sources/VoicePepper/UI/RecordingHistoryView.swift`，实现录音列表 SwiftUI 视图
- [x] 3.2 实现列表行视图，显示录制时间（友好格式）、时长；右侧提供"播放/暂停"按钮和"在 Finder 中显示"按钮
- [x] 3.3 实现空状态视图（无录音时显示提示文字）
- [x] 3.4 实现删除操作（`onDelete` 或删除按钮），调用 `RecordingFileService.delete()` 并刷新列表
- [x] 3.5 实现播放逻辑：使用 `AVAudioPlayer` 播放选中录音，维护 `currentlyPlayingId` 状态，同一时刻只允许一条录音播放；播放结束后自动重置状态
- [x] 3.6 实现"在 Finder 中显示"：调用 `NSWorkspace.shared.activateFileViewerSelecting([url])`，文件不存在时刷新列表

## 4. 集成到 Popover

- [x] 4.1 在 `TranscriptionPopoverView.swift` 中添加 Tab 切换（转录/历史录音），或在底部增加入口按钮导航到 `RecordingHistoryView`
- [x] 4.2 切换到历史录音标签时触发列表刷新（调用 `RecordingFileService.listRecordings()`）
- [x] 4.3 确保 Popover 布局在展示历史列表时高度适应内容

## 5. 验证

- [x] 5.1 构建通过（`swift build`），无编译警告
- [x] 5.2 验证：App 启动后 Recordings 目录自动创建；`sessionEndPublisher` 在 stop() 时发出完整样本
- [x] 5.3 验证：`RecordingFileService.save()` 使用 AVAudioFile 异步写入 M4A，AVAudioPlayer 播放逻辑正确实现
- [x] 5.4 验证：`NSWorkspace.activateFileViewerSelecting` 调用链完整，文件不存在时刷新列表
- [x] 5.5 验证：`delete(item:)` 同时删除磁盘文件并从 @Published recordings 列表移除
