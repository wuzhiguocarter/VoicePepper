# Spec: recording-history

## Purpose

在 Popover 内提供历史录音标签页，支持列表浏览、App 内播放、Finder 定位与删除操作。

## Requirements

### Requirement: 历史录音列表视图
系统 SHALL 在 Popover 中提供"历史录音"标签页，列出所有已保存的录音文件，每条显示：文件名（或友好时间格式）、录制时间、时长。

#### Scenario: 打开历史录音标签页
- **WHEN** 用户点击 Popover 中的"历史录音"标签
- **THEN** 列表加载并展示所有录音条目，按录制时间降序排列（最新在顶）

#### Scenario: 无历史录音时展示空状态
- **WHEN** 录音目录中没有任何 M4A 文件
- **THEN** 列表显示空状态提示文字（如"暂无录音记录"）

#### Scenario: 列表刷新
- **WHEN** 用户切换到历史录音标签页
- **THEN** 系统重新扫描录音目录并更新列表

### Requirement: 在 Finder 中显示录音文件
每条录音记录 SHALL 提供"在 Finder 中显示"按钮，点击后通过 `NSWorkspace` 在 Finder 中定位并高亮对应文件。

#### Scenario: 点击"在 Finder 中显示"
- **WHEN** 用户点击某条录音的"在 Finder 中显示"按钮
- **THEN** Finder 打开并高亮该 M4A 文件

#### Scenario: 文件不存在时的处理
- **WHEN** 录音文件已被用户手动删除但列表尚未刷新，用户点击"在 Finder 中显示"
- **THEN** 系统刷新列表移除该条目

### Requirement: App 内播放录音
每条录音记录 SHALL 提供"播放/暂停"按钮，使用 `AVAudioPlayer` 在 App 内播放该录音。同一时刻只允许一条录音处于播放状态。

#### Scenario: 点击播放按钮
- **WHEN** 用户点击某条录音的"播放"按钮
- **THEN** 该录音开始播放，按钮状态变为"暂停"图标

#### Scenario: 点击暂停按钮
- **WHEN** 录音正在播放时，用户点击"暂停"按钮
- **THEN** 播放暂停，按钮状态恢复为"播放"图标

#### Scenario: 切换播放另一条录音
- **WHEN** 一条录音正在播放时，用户点击另一条录音的"播放"按钮
- **THEN** 前一条停止播放，新录音开始播放

#### Scenario: 播放完成后重置状态
- **WHEN** 录音播放到文件末尾
- **THEN** 播放按钮恢复为"播放"图标，进度归零

### Requirement: 删除历史录音
每条录音记录 SHALL 提供删除操作，确认后同时删除磁盘文件并从列表移除。

#### Scenario: 删除一条录音
- **WHEN** 用户触发某条录音的删除操作
- **THEN** 磁盘上对应的 M4A 文件被删除，列表立即移除该条目

#### Scenario: 删除当前正在播放的录音
- **WHEN** 一条录音正在播放时，用户触发删除
- **THEN** 播放停止，文件删除，列表移除该条目
