## ADDED Requirements

### Requirement: 状态栏图标与 Popover 面板
系统 SHALL 在 macOS 状态栏显示一个图标，点击后展开 Popover 面板展示转录内容，图标样式应反映当前录音状态。

#### Scenario: 空闲状态图标
- **WHEN** 应用未在录音
- **THEN** 状态栏显示麦克风静态图标（SF Symbol: `mic`）

#### Scenario: 录音中状态图标
- **WHEN** 录音正在进行
- **THEN** 状态栏图标变为带动效的红色录音图标（SF Symbol: `mic.fill`），并有脉冲动画

#### Scenario: 展开 Popover 面板
- **WHEN** 用户点击状态栏图标
- **THEN** 展开 Popover 面板，面板宽度 400px，最大高度 600px，显示当前会话转录内容

### Requirement: 实时转录文本展示
系统 SHALL 在 Widget 面板内实时追加并展示转录文本，新内容出现时自动滚动到底部。

#### Scenario: 新转录结果追加
- **WHEN** whisper.cpp 返回新转录文本
- **THEN** 文本追加到面板底部，面板自动滚动使最新内容可见，追加动作在 100ms 内完成

#### Scenario: 空状态提示
- **WHEN** 当前会话无转录内容
- **THEN** 面板显示占位提示文本（如"按下快捷键开始录音..."）

### Requirement: 转录文本操作
系统 SHALL 支持用户对转录文本进行选择、复制等基础操作，并提供一键全选复制按钮。

#### Scenario: 一键复制全部
- **WHEN** 用户点击"复制全部"按钮
- **THEN** 当前会话所有转录文本复制到剪贴板，按钮短暂显示"已复制"确认反馈

#### Scenario: 清除会话
- **WHEN** 用户点击"清除"按钮
- **THEN** 面板清空当前会话所有转录内容，操作不可撤销时需二次确认

### Requirement: 录音状态实时反馈
系统 SHALL 在面板内显示录音状态指示器，包括录音时长计时和音频电平波形。

#### Scenario: 录音计时
- **WHEN** 录音进行中且面板已展开
- **THEN** 面板顶部显示实时计时器（格式 MM:SS），每秒更新

#### Scenario: 音频电平波形
- **WHEN** 录音进行中
- **THEN** 面板显示实时音频电平波形图，反映当前音量，静默时波形趋于平线
