## Context

蓝牙录音笔 A06 通过 BLE 实时转写通道（type=1, cmd=1）推送的音频数据为 Opus 编码，格式：SILK 12kHz，20ms 帧，每帧固定 40 字节，每个 BLE 数据包含 4 帧（160 字节）。通过抓取原始 BLE 数据并用 libopus 逐格式尝试解码，最终确认 Opus 16kHz 输出为正确格式。

## Goals / Non-Goals

**Goals:**
- 集成 libopus 实现 Opus → 16kHz Float32 PCM 实时解码
- 修复 BLE 状态同步（PreferencesView EnvironmentObject 注入）
- 修复录音计时器高频刷新失效问题

**Non-Goals:**
- 不支持其他音频编码格式（仅 Opus SILK）
- 不修改 Whisper 转录逻辑

## Decisions

### 1. COpus SPM 桥接模块

**决策**：与 CWhisper 相同模式，创建 `Sources/COpus/` target 桥接系统 libopus。

**理由**：复用已有的 C 库桥接模式，最小化学习成本。libopus 通过 homebrew 安装在 `/opt/homebrew/`。

### 2. 每帧独立解码

**决策**：每 40 字节作为独立 Opus 帧调用 `opus_decode`，不做跨帧状态管理。

**理由**：Opus 解码器内部自动维护状态（predictor、filter history），`opus_decode` 逐帧调用是标准用法。

### 3. RecordingStatusBar Timer → TimelineView

**决策**：去掉 `Timer.publish` + `@State elapsed`，改用 `TimelineView(.periodic(from:by:))` 每秒刷新。

**理由**：`Timer.publish` 作为 View struct 属性会在每次 body 求值时重建，BLE 音频电平高频更新导致 Timer 来不及触发就被替换，计时器永远显示 00:00。`TimelineView` 由 SwiftUI 框架管理生命周期，不受 body 重建影响。

## Risks / Trade-offs

- **[libopus 依赖]** → 需要 `brew install opus`。缓解：在 README 和构建文档中明确标注。
- **[Opus 帧大小固定假设]** → 当前假设每帧 40 字节。若录音笔固件更新改变帧大小，需适配。缓解：OpusDecoder 支持可变帧大小，只是分帧逻辑需调整。
