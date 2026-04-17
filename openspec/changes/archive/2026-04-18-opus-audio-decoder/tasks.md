## 1. Opus 解码集成

- [x] 1.1 创建 COpus SPM 桥接模块（Sources/COpus/）
- [x] 1.2 Package.swift 新增 COpus target + VoicePepper 依赖
- [x] 1.3 创建 BLEOpusDecoder Swift 封装（opus_decode 16kHz mono）
- [x] 1.4 BLERecorderService 用 Opus 解码替换 PCM Int16 转换

## 2. BLE 状态同步修复

- [x] 2.1 BLEDeviceManager 添加 peripheralCache 缓存 CBPeripheral 强引用
- [x] 2.2 BLEDeviceManager connectionState/batteryLevel/deviceStatus 改用 didSet + 回调
- [x] 2.3 AppDelegate.openPreferencesWindow 注入 bleDeviceManager EnvironmentObject
- [x] 2.4 PreferencesView 改用 @EnvironmentObject 获取 bleDeviceManager

## 3. UI 修复

- [x] 3.1 RecordingStatusBar 从 Timer.publish 改为 TimelineView 避免高频重建

## 4. 经验文档

- [x] 4.1 记录 BLE SwiftUI 实例不一致问题到 docs/solutions/
