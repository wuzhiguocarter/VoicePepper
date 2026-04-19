## MODIFIED Requirements

### Requirement: 历史录音列表视图
系统 SHALL 在 Popover 中提供"历史录音"标签页，列出所有已保存的录音文件，每条显示：文件名（或友好时间格式）、录制时间、时长。

#### Scenario: 打开历史录音标签页
- **WHEN** 用户点击 Popover 中的"历史录音"标签
- **THEN** 列表加载并展示所有录音条目，按录制时间降序排列（最新在顶）

#### Scenario: 条目标记结构化转录可用
- **WHEN** 某条录音存在同名 speaker-attributed transcript JSON sidecar
- **THEN** 该条目被标记为可查看结构化转录，并可进入带 speaker 标签的转录预览

### Requirement: 在 Finder 中显示录音文件
每条录音记录 SHALL 提供"在 Finder 中显示"按钮，点击后通过 `NSWorkspace` 在 Finder 中定位并高亮对应文件。

#### Scenario: 点击"在 Finder 中显示"
- **WHEN** 用户点击某条录音的"在 Finder 中显示"按钮
- **THEN** Finder 打开并高亮该录音文件

### Requirement: 删除历史录音
每条录音记录 SHALL 提供删除操作，确认后同时删除磁盘文件并从列表移除。

#### Scenario: 删除包含结构化 transcript 的录音
- **WHEN** 用户删除一条存在同名 `.json` transcript sidecar 的录音
- **THEN** 录音文件、配套 `.txt` 文件和 `.json` sidecar 一并删除

### Requirement: 历史录音转录预览优先展示 speaker 标签
系统 SHALL 在查看历史转录时优先读取结构化 transcript，并将文本渲染为带 speaker 标签的可读内容；若结构化 transcript 缺失，则回退到纯文本 `.txt`。

#### Scenario: 存在结构化 transcript
- **WHEN** 用户点击一条带 `.json` sidecar 的录音的"查看转录"按钮
- **THEN** 预览界面展示格式化后的 speaker-attributed 文本，例如 `[SPEAKER_00] 你好`

#### Scenario: 旧录音无结构化 transcript
- **WHEN** 用户点击一条仅有 `.txt` 配对文件的旧录音
- **THEN** 系统继续展示现有纯文本转录，不报错
