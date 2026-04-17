## Why

VoicePepper 目前仅支持 Mac 内置/外接麦克风作为音频输入源。用户在会议、采访、课堂等场景中常使用蓝牙录音笔采集高质量音频，但无法将录音笔的实时音频流直接导入 VoicePepper 进行本地转录。新增蓝牙录音笔通道，让用户可以将录音笔通过 BLE 连接到 Mac，实时获取音频并调用本地 whisper.cpp 模型转录，扩展 VoicePepper 的音频采集能力。

## What Changes

- **新增 BLE 录音笔连接管理**：通过 CoreBluetooth 扫描、连接、断开 BLE 录音笔设备（Service UUID 0xAE20），支持自动重连
- **新增 BLE 协议层**：实现录音笔通信协议的数据包封装/解析，包括 Magic 校验、CRC-16/XMODEM 校验、包序号管理、ACK 回复机制
- **新增实时转写音频通道**：接收录音笔推送的实时音频数据（type=1, cmd=1），转换为 16kHz mono PCM 后复用现有 TranscriptionService 进行转录
- **新增按键联动**：响应录音笔物理按键事件（开始/暂停/继续/保存录音），驱动 App 录音状态变更并回复 ACK
- **新增设备状态 UI**：在状态栏 Popover 中展示蓝牙连接状态、电池电量、设备运行状态
- **新增录音源切换**：支持用户在"麦克风"和"蓝牙录音笔"两种录音源之间切换

## Capabilities

### New Capabilities

- `ble-device-management`: BLE 录音笔设备的扫描、连接、断开、自动重连管理
- `ble-protocol`: 录音笔 BLE 通信协议实现（数据包格式、CRC 校验、序号管理、命令收发）
- `ble-realtime-transcription`: 从 BLE 录音笔接收实时音频流并通过本地 whisper.cpp 转录
- `recording-source-switch`: 麦克风与蓝牙录音笔之间的录音源切换机制

### Modified Capabilities

- `recording`: 录音状态管理需扩展以支持蓝牙录音笔的按键联动（外部设备触发开始/暂停/继续/保存）

## Impact

- **新增源文件**：`Sources/VoicePepper/Services/BLE/` 目录下新增 BLE 相关服务
- **修改 AppState**：新增蓝牙设备状态、录音源类型等属性
- **修改 AppDelegate**：注册 BLE 服务，连接音频管线
- **修改 Package.swift**：新增 CoreBluetooth 链接
- **修改 UI**：TranscriptionPopoverView / PreferencesView 增加蓝牙设备管理入口
- **Entitlements**：需添加 Bluetooth 权限声明
- **无外部依赖变更**：CoreBluetooth 为系统框架
