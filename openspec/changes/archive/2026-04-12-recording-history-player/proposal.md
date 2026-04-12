## Why

当前 VoicePepper 仅将录音数据暂存于内存中用于实时转录，录音结束后音频文件即丢失，用户无法回听原始录音或找到对应文件。增加录音持久化与历史列表功能，让用户可以查看、播放并在 Finder 中定位历史录音。

## What Changes

- 每次录音结束后，将音频自动保存为 `.m4a` 文件至应用专属目录（`~/Library/Application Support/VoicePepper/Recordings/`）
- 在 Popover 中新增"历史录音"标签页，展示所有保存的录音列表（文件名、时长、日期）
- 每条录音记录提供两个操作按钮：
  - **在 Finder 中显示**：用 `NSWorkspace` 定位并高亮文件
  - **播放**：使用 `AVAudioPlayer` 在 App 内直接播放录音
- 录音列表支持删除（滑动删除或删除按钮）

## Capabilities

### New Capabilities

- `recording-persistence`: 录音文件持久化存储服务，负责将 PCM 音频转换为 M4A 并写入磁盘
- `recording-history`: 历史录音列表 UI，展示已保存录音，支持播放和 Finder 定位

### Modified Capabilities

- `recording`: 录音流程需在录音完成后触发文件保存

## Impact

- **新增文件**：`RecordingFileService.swift`（录音存储服务）、`RecordingHistoryView.swift`（历史列表 UI）、`RecordingItem.swift`（数据模型）
- **修改文件**：`AppState.swift`（增加录音历史状态）、`TranscriptionPopoverView.swift`（增加历史标签页）、`AudioCaptureService.swift`（录音完成后触发保存）
- **权限**：需要在 `Info.plist` 中保留麦克风权限；文件写入不需要额外沙盒权限（应用支持目录为允许路径）
- **依赖**：仅使用系统框架 `AVFoundation`、`Foundation`、`AppKit`，无新增第三方依赖
