## 1. 数据模型扩展

- [x] 1.1 `RecordingItem` 新增 `transcriptionURL: URL?` 可选属性，指向同名 `.txt` 文件
- [x] 1.2 `RecordingItem` 新增 `transcriptionText: String?` 计算属性，按需从 `.txt` 文件读取内容

## 2. RecordingFileService 转录文本持久化

- [x] 2.1 `RecordingFileService` 新增 `saveTranscription(_:forRecordingURL:)` 方法，将转录文本写入同名 `.txt` 文件
- [x] 2.2 `RecordingFileService.save()` 方法扩展：接收转录条目数组参数，在保存 WAV 后同步保存 `.txt`
- [x] 2.3 `RecordingFileService.loadRecordings()` 扩展：加载时检测每条录音的配对 `.txt` 文件，填充 `transcriptionURL`
- [x] 2.4 `RecordingFileService.delete()` 扩展：删除录音时同步删除配对的 `.txt` 文件

## 3. 转录文本保存调用链

- [x] 3.1 修改 `AudioCaptureService` 或 `AppDelegate` 中的录音停止回调，将当前会话转录条目传递给 `RecordingFileService.save()`
- [x] 3.2 确保转录文本格式为 `[HH:mm:ss] 转录内容`，多条用换行分隔

## 4. UI：历史录音转录文本预览

- [x] 4.1 `RecordingRowView` 新增"查看转录"按钮（`doc.text` 图标），仅当 `transcriptionURL != nil` 时显示且可点击
- [x] 4.2 新增 `TranscriptionTextView` Sheet 视图，展示转录文本全文，带"复制"按钮
- [x] 4.3 `RecordingHistoryView` 增加 `@State` 控制 Sheet 展示状态，绑定当前选中录音的转录文本

## 5. 编译验证

- [x] 5.1 `swift build` 编译通过，无错误和警告
