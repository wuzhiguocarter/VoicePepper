## Context

VoicePepper 当前音频管线为单源架构：`AudioCaptureService(AVAudioEngine)` → `VADDetector` → `AudioSegment` → `TranscriptionService` → whisper.cpp。所有音频均来自 Mac 麦克风，通过 AVAudioEngine 采集后转换为 16kHz mono PCM。

本次新增蓝牙录音笔通道，需要在不破坏现有麦克风管线的前提下，引入第二条音频输入管线：BLE 录音笔 → 协议解析 → PCM 转换 → 复用 TranscriptionService。

录音笔使用 BLE 通信，协议为自定义二进制包格式（Magic + SeqNo + CRC16 + Data），通过 CoreBluetooth 的 CBCentralManager 扫描和连接设备。

## Goals / Non-Goals

**Goals:**
- 实现 BLE 录音笔的扫描、连接、断开、自动重连
- 完整实现录音笔 BLE 通信协议（包封装/解析、CRC 校验、ACK 机制）
- 接收实时转写音频流，转换为 16kHz mono PCM 后复用 TranscriptionService
- 响应录音笔物理按键事件，联动 App 录音状态
- 在 UI 中展示蓝牙设备状态（连接、电量、设备状态）
- 支持麦克风与蓝牙录音笔之间的录音源切换

**Non-Goals:**
- 不实现录音笔文件管理功能（文件列表、文件导入/删除）——后续迭代
- 不实现录音笔固件升级
- 不实现多设备同时连接（仅支持单设备）
- 不修改 whisper.cpp 集成或模型管理逻辑
- 不实现蓝牙音频的 VAD 检测——录音笔端已处理静音检测，App 直接按收到的音频段转录

## Decisions

### 1. BLE 角色：App 作为 Central

**决策**：App 使用 `CBCentralManager` 主动扫描和连接录音笔。

**理由**：尽管协议文档描述"录音笔为主机，App 为从机"，这是从 BLE GATT 数据方向的描述。在 CoreBluetooth 实现中，App 作为 Central 扫描并连接 Peripheral（录音笔），然后通过 GATT Characteristic 读写数据。这是 macOS BLE 开发的标准模式，CoreBluetooth 不支持 macOS App 作为纯 Peripheral 被动等待连接。

**替代方案**：使用 `CBPeripheralManager` 让 App 广播等待录音笔连接——不可行，macOS 上 Peripheral 模式功能受限且不符合用户预期（用户期望 App 端发起连接）。

### 2. 分层架构：Protocol → Device → Service

**决策**：三层分离设计：
- **BLEProtocol**：纯数据层，负责包封装/解析、CRC 校验，无 CoreBluetooth 依赖（可单元测试）
- **BLEDeviceManager**：设备管理层，封装 CBCentralManager 的扫描/连接/重连逻辑
- **BLERecorderService**：业务层，组合协议层和设备层，管理实时转写会话，输出 AudioSegment 供 TranscriptionService 消费

**理由**：协议解析逻辑复杂（CRC、分包、序号），独立出来便于单元测试和调试。设备管理与业务逻辑分离，职责清晰。

### 3. 音频数据格式假设：PCM 16kHz Mono Int16

**决策**：假设录音笔推送的音频数据为 PCM 16kHz 16-bit mono little-endian，收到后直接转换为 Float32 供 whisper.cpp 使用。

**理由**：协议文档未明确音频编码格式，但录音笔类产品常用 PCM 16kHz 采样率。若实际格式不同（如 8kHz 或 ADPCM），仅需在 `BLERecorderService` 中增加一个解码/重采样步骤，不影响整体架构。

**兜底方案**：在 `BLERecorderService` 中预留 `AudioDecoder` 协议，初始实现为 PCM16KHz 直通，后续可替换。

### 4. 不复用 VADDetector

**决策**：BLE 音频通道不经过 VADDetector，直接将收到的音频数据按时间窗口分段后送入 TranscriptionService。

**理由**：录音笔端的实时转写模式已经对音频做了预处理（按说话段推送），App 再做 VAD 是多余的。BLE 通道使用基于时间的分段策略（每 N 秒或每次 BLE 音频包批次作为一个 AudioSegment）。

### 5. 录音源模型：枚举 + 独占

**决策**：新增 `RecordingSource` 枚举（.microphone / .bluetoothRecorder），同一时刻只能激活一个录音源。切换录音源时，先停止当前源，再启动新源。

**理由**：
- 两个音频源同时转录会产生混乱的转录结果
- TranscriptionService 是单队列，两路音频会相互阻塞
- 用户预期在同一时刻只使用一种输入

### 6. 自动重连策略

**决策**：设备断连后，自动重连最多 5 次，间隔指数退避（2s → 4s → 8s → 16s → 32s）。超过重连次数后标记为"已断开"，需用户手动重新连接。

**理由**：BLE 连接不稳定是常态（录音笔移出范围、电量耗尽），自动重连提升用户体验。但无限重连会浪费系统资源且给用户错误预期。

## Risks / Trade-offs

- **[音频格式不匹配]** → 录音笔实际音频格式可能不是 PCM 16kHz mono。**缓解**：BLERecorderService 中预留 AudioDecoder 抽象，初始实现为 PCM 直通，后续可扩展。首次连接时可通过试听短段音频验证。
- **[BLE 带宽限制]** → BLE 4.0 的有效吞吐约 2-3 KB/s，16kHz 16-bit mono PCM 需要 32 KB/s，可能丢包。**缓解**：录音笔端可能使用压缩编码（需实测确认），且 BLE 4.2+ 支持更大 MTU 和更高吞吐。协议层已有包序号和 CRC 校验机制用于检测丢包。
- **[macOS 蓝牙权限]** → macOS 13+ 需要在 Info.plist/Entitlements 中声明蓝牙用途。**缓解**：添加 NSBluetoothAlwaysUsageDescription 和 com.apple.security.device.bluetooth entitlement。
- **[首次配对体验]** → 用户首次使用需经历"扫描 → 选择设备 → 配对"流程，可能不够直观。**缓解**：提供清晰的设备扫描 UI，自动过滤非目标设备（仅显示包含 Service 0xAE20 的设备）。
