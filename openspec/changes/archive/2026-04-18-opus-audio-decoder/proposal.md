## Why

蓝牙录音笔(A06)通过 BLE 传输的实时音频数据采用 Opus SILK 12kHz 编码（40字节/帧），而非之前假设的 PCM 16kHz。需要集成 libopus 解码器将 Opus 帧解码为 16kHz Float32 PCM，供 Whisper 转录。同时修复 BLE 状态同步和录音计时器 UI 问题。

## What Changes

- **新增 COpus 桥接模块**：通过 SPM target 桥接 homebrew 安装的 libopus，供 Swift 调用
- **新增 BLEOpusDecoder**：封装 libopus opus_decode API，将 40 字节 Opus 帧解码为 16kHz mono Float32
- **修改 BLERecorderService**：用 Opus 解码替换原有的 PCM Int16→Float32 转换
- **修复 BLE 状态不同步**：PreferencesView 通过 EnvironmentObject 获取 BLEDeviceManager（而非 fallback 创建新实例）
- **修复录音计时器**：RecordingStatusBar 从 Timer.publish 改为 TimelineView，避免高频刷新重建 Timer
- **修复 BLE 连接失败**：BLEDeviceManager 缓存 CBPeripheral 强引用，防止 ARC 回收

## Capabilities

### New Capabilities

- `opus-audio-decoding`: BLE 音频 Opus 解码（COpus 桥接 + BLEOpusDecoder）

### Modified Capabilities

- `ble-realtime-transcription`: 音频解码从 PCM 假设改为 Opus 实际解码
- `ble-device-management`: 增加 CBPeripheral 缓存、EnvironmentObject 注入、状态回调机制

## Impact

- **新增文件**：`Sources/COpus/`（桥接模块）、`Sources/VoicePepper/Services/BLE/OpusDecoder.swift`
- **修改 Package.swift**：新增 COpus target + dependency
- **修改 AppDelegate**：EnvironmentObject 注入 bleDeviceManager + 状态回调
- **修改 RecordingStatusBar**：Timer → TimelineView
- **依赖**：libopus（brew install opus），系统框架无变化
