## 1. 基础设施与协议层

- [x] 1.1 Package.swift 添加 CoreBluetooth 框架链接，Entitlements 添加蓝牙权限声明
- [x] 1.2 创建 `Sources/VoicePepper/Services/BLE/BLEProtocol.swift`：实现数据包封装/解析（Magic 校验、CRC-16/XMODEM、SeqNo 管理、DataLen 小端序）
- [x] 1.3 创建 `Sources/VoicePepper/Services/BLE/BLEConstants.swift`：定义 Service UUID、Characteristic UUID、数据类型枚举、命令枚举等协议常量

## 2. BLE 设备管理

- [x] 2.1 创建 `Sources/VoicePepper/Services/BLE/BLEDeviceManager.swift`：CBCentralManager 封装，实现设备扫描（过滤 Service 0xAE20）、连接、断开
- [x] 2.2 实现 Characteristic 发现与订阅（0xAE21 写入、0xAE22/0xAE23 通知订阅）
- [x] 2.3 实现自动重连机制（指数退避 2s→4s→8s→16s→32s，最多 5 次）
- [x] 2.4 实现设备信息查询（电量、设备状态）及 0xAE23 通道的电量/按键通知处理

## 3. 录音源切换与状态扩展

- [x] 3.1 AppState 新增 `RecordingSource` 枚举（microphone/bluetoothRecorder）及相关 Published 属性（录音源、BLE 连接状态、电量、设备状态）
- [x] 3.2 AppState 新增录音源持久化（UserDefaults 存取）
- [x] 3.3 AppDelegate 中根据录音源类型分发录音操作（麦克风走 AudioCaptureService，蓝牙走 BLERecorderService）

## 4. BLE 实时转写服务

- [x] 4.1 创建 `Sources/VoicePepper/Services/BLE/BLERecorderService.swift`：组合 BLEDeviceManager + BLEProtocol，管理实时转写会话生命周期
- [x] 4.2 实现实时转写命令收发（开始/结束/暂停/继续）
- [x] 4.3 实现音频数据接收与缓冲：BLE 音频数据累积，按时间窗口（约 3-5 秒）封装为 AudioSegment
- [x] 4.4 实现 Int16→Float32 音频格式转换及 RMS 电平计算
- [x] 4.5 实现按键联动：响应 type=3 按键命令驱动录音状态，回复 ACK

## 5. AppDelegate 集成与管线连接

- [x] 5.1 AppDelegate 中初始化 BLEDeviceManager 和 BLERecorderService，连接到 TranscriptionService
- [x] 5.2 BLERecorderService.audioSegmentPublisher → TranscriptionService.enqueue 管线接入
- [x] 5.3 BLE 音频会话结束 → RecordingFileService 持久化接入（复用 sessionEndPublisher 模式）

## 6. UI 集成

- [x] 6.1 TranscriptionPopoverView 新增蓝牙设备状态区域（连接状态、电量、设备状态指示）
- [x] 6.2 TranscriptionPopoverView 或 PreferencesView 新增录音源切换控件
- [x] 6.3 PreferencesView 新增蓝牙设备管理面板（扫描、设备列表、连接/断开按钮）

## 7. 验证与收尾

- [x] 7.1 确保现有麦克风录音通道不受影响（运行现有 E2E 测试验证）
- [x] 7.2 编译通过并运行基本冒烟测试（App 启动、蓝牙权限弹窗、UI 展示正常）
