## 1. OpenSpec 与依赖接入

- [x] 1.1 为本次变更补齐 `speaker-attributed-transcript` 与相关 delta specs
- [x] 1.2 在 `Package.swift` 中引入 `FluidAudio` 依赖并完成可编译接入

## 2. Speaker-attributed transcript 数据模型

- [x] 2.1 新增结构化 transcript / speaker chunk 持久化模型
- [x] 2.2 扩展 `RecordingItem` 以识别同名 `.json` transcript sidecar
- [x] 2.3 提供 speaker-attributed transcript 到可读文本的格式化输出

## 3. FluidAudio diarization 服务

- [x] 3.1 新增 `FluidAudio` 离线 diarization 服务封装，负责模型准备与文件处理
- [x] 3.2 实现基于 `TranscriptionEntry` 时间顺序的 speaker 标签回填逻辑
- [x] 3.3 在 diarization 失败时保证纯文本持久化和历史记录回退路径可用

## 4. 录音持久化与 UI 集成

- [x] 4.1 扩展 `RecordingFileService.save()`，同时保存 `.txt` 和 `.json`
- [x] 4.2 扩展 `RecordingFileService.loadRecordings()` / `delete()`，管理 `.json` sidecar
- [x] 4.3 修改历史录音转录预览，优先展示 speaker-attributed 文本
- [x] 4.4 在 `AppDelegate` 的录音会话结束流程中接入 diarization 持久化

## 5. 验证

- [x] 5.1 `swift build` 通过
- [x] 5.2 运行受影响的 E2E 测试并确认录音、转录、历史记录链路可用
