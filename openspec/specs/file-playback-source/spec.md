# Spec: file-playback-source

## Purpose

定义文件回放音频源能力：读取本地 WAV 文件并将 PCM 数据注入现有音频管道，用于开发测试和 WER 可重复评估，不暴露给最终用户 UI。

## Requirements

### Requirement: WAV 文件读取与 PCM 分块
系统 SHALL 通过 `AudioFileSource` 服务读取本地 16kHz 单声道 WAV 文件，按固定时长（默认 1.5 秒）分块，以 `AudioSegment` 形式发布到 `audioSegmentPublisher`，行为与麦克风 VAD 分段等价。

#### Scenario: 正常读取 16kHz 单声道 WAV
- **WHEN** 调用 `AudioFileSource.play(url:)` 且目标文件为合法 16kHz 单声道 float32/int16 WAV
- **THEN** 服务按 1.5 秒步长逐块读取 PCM，每块以 `AudioSegment` 形式发布到 `audioSegmentPublisher`，块间间隔与实际时长等比（避免 CPU 爆满）

#### Scenario: 文件播放完成后触发 sessionEnd
- **WHEN** WAV 文件所有数据块均已发布完毕
- **THEN** 服务向 `sessionEndPublisher` 发布一个 `RecordingSessionData`，触发与正常录音停止等价的持久化流程

#### Scenario: 非 16kHz 文件
- **WHEN** 目标 WAV 文件采样率不等于 16000Hz 或声道数不等于 1
- **THEN** 服务记录错误日志并立即发布 `sessionEndPublisher`（空会话），不崩溃

#### Scenario: 文件不存在
- **WHEN** 调用 `play(url:)` 且指定 URL 无法读取
- **THEN** 服务记录错误日志并立即返回，不发布任何 `AudioSegment`

### Requirement: 文件回放停止控制
系统 SHALL 提供 `stop()` 方法，允许在 WAV 文件播放完成前提前终止，停止后不再发布新的 `AudioSegment`。

#### Scenario: 播放中途停止
- **WHEN** WAV 文件播放过程中调用 `stop()`
- **THEN** 当前块发布后停止后续块的发布，不发布 `sessionEndPublisher`

### Requirement: 仅供开发测试使用
`AudioFileSource` 及 `RecordingSource.filePlayback` SHALL 仅用于开发测试场景，不通过正式 UI 选择器暴露给最终用户。

#### Scenario: filePlayback 不出现在 UI 选择器
- **WHEN** 用户打开录音源设置界面
- **THEN** 界面仅显示 microphone 和 bluetoothRecorder 两个选项，不显示 filePlayback
