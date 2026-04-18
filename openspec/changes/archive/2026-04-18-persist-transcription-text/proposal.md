## Why

当前语音转录文本仅保存在内存中（`AppState.entries`），App 重启或清除会话后转录内容即丢失。用户需要在历史录音列表中查看对应录音的转录文本，实现"录音文件 + 转录文本"的一体化管理，方便回顾和检索。

## What Changes

- 每次录音保存时，将对应的转录文本以 `.txt` 文件持久化到 `~/Library/Application Support/VoicePepper/Recordings/` 目录，与录音 WAV 文件同名（除扩展名外）
- `RecordingItem` 模型增加关联转录文本文件路径和内容字段
- 历史录音列表每条记录增加"查看转录"按钮，点击后在 Sheet/Popover 中展示转录文本
- 转录文本支持一键复制
- 删除录音时同步删除对应的转录文本文件

## Capabilities

### New Capabilities
- `transcription-persistence`: 转录文本文件持久化，与录音文件配对存储到同一目录，提供加载、读取、删除能力

### Modified Capabilities
- `recording-history`: 历史录音列表增加转录文本预览按钮和内容展示能力
- `recording-persistence`: 保存录音时同步保存对应的转录文本文件

## Impact

- **Models**: `RecordingItem` 新增 `transcriptionText` 和 `transcriptionURL` 属性
- **Services**: `RecordingFileService` 增加 `.txt` 文件的保存、加载、删除逻辑
- **UI**: `RecordingHistoryView` / `RecordingRowView` 增加转录文本预览按钮和展示 Sheet
- **Storage**: `~/Library/Application Support/VoicePepper/Recordings/` 目录将同时存放 `.wav` 和 `.txt` 文件
- **AppState**: `TranscriptionService.handleResult` 保存转录文本到文件系统
