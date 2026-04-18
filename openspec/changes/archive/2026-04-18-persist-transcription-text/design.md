## Context

VoicePepper 是 macOS 状态栏 Native App，使用 Whisper.cpp 进行实时语音转录。当前架构：
- 录音通过 `RecordingFileService` 以 WAV 格式持久化到 `~/Library/Application Support/VoicePepper/Recordings/`
- 转录文本仅保存在 `AppState.entries`（内存数组），App 重启或清除后丢失
- 历史录音列表（`RecordingHistoryView`）只展示录音文件，无转录文本关联

录音和转录是同一个会话的产物，但当前没有将它们关联持久化的机制。

## Goals / Non-Goals

**Goals:**
- 转录文本随录音文件一起持久化，App 重启后可查看
- 历史录音列表支持查看对应转录文本
- 转录文本与录音文件通过文件名关联（同名不同扩展名）
- 支持一键复制转录文本

**Non-Goals:**
- 不实现转录文本的全文搜索（后续可扩展）
- 不修改实时转录流程的内存展示逻辑
- 不引入数据库（使用纯文件系统方案）
- 不支持手动编辑转录文本

## Decisions

### 1. 转录文本存储格式：同名 `.txt` 文件配对

**选择：** 转录文本保存为与录音同名的 `.txt` 文件，放在同一目录。

例如：`Recording_20250101_120000.wav` → `Recording_20250101_120000.txt`

**理由：**
- 零配置关联：通过文件名（去掉扩展名）即可匹配
- 人类可读：直接在 Finder 中打开查看
- 无需数据库或索引文件
- 与现有 `RecordingFileService.storageDirectory` 共享目录

**备选方案：** 单独的 JSON/SQLite 索引文件 → 引入额外复杂度，当前规模不需要。

### 2. 转录文本保存时机：录音会话结束时一次性写入

**选择：** 在 `RecordingFileService.save()` 保存录音文件的同时，从 `AppState.entries` 收集当前会话的全部转录文本，拼接后写入 `.txt` 文件。

**理由：**
- 避免每条 TranscriptionEntry 单独写文件造成的 I/O 开销
- 录音和转录文本保持原子性（要么都保存，要么都不保存）
- 实现简单，不需要监听 TranscriptionEntry 的追加事件

### 3. UI 交互：Sheet 展示转录文本

**选择：** 在历史录音列表中，每条录音增加一个"文档"图标按钮，点击后弹出 Sheet 展示转录文本，带复制按钮。

**理由：**
- Sheet 是 macOS 标准交互模式，不干扰列表浏览
- 转录文本可能较长，Sheet 提供足够的展示空间
- 与现有 Popover 内 Tab 切换不冲突

### 4. RecordingItem 模型扩展

**选择：** `RecordingItem` 新增可选属性 `transcriptionText: String?` 和 `transcriptionURL: URL?`，在 `loadRecordings()` 时尝试加载同名的 `.txt` 文件。

**理由：**
- Optional 属性保证向后兼容（旧录音无转录文本）
- 延迟加载避免一次性读取所有文件内容

## Risks / Trade-offs

- **[大文件性能]** 转录文本可能很长 → `.txt` 文件按需读取（仅点击预览时加载全文），列表只显示有无标记
- **[文件不匹配]** 录音保存成功但转录写入失败 → 转录文本为 Optional，缺失时不影响录音播放
- **[旧数据兼容]** 升级前的录音没有配对 `.txt` → `transcriptionText` 为 nil，UI 仅显示播放按钮，不显示转录按钮
