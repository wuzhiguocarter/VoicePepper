## Context

本项目从零构建一个 macOS 原生应用，核心诉求是低延迟、完全离线的语音转录体验。用户群体为需要快速记录灵感或会议内容的开发者/创作者。技术约束：必须本地处理（无云端 API），支持 macOS 13+，最小化权限申请。

关键依赖：
- **whisper.cpp**：Meta Whisper 的高性能 C++ 实现，支持 Apple Silicon Metal 加速
- **AVFoundation**：macOS 标准音频捕获框架
- **SwiftUI + AppKit**：UI 层（Widget 卡片使用 SwiftUI，状态栏图标使用 AppKit NSStatusBar）

## Goals / Non-Goals

**Goals:**
- 全局快捷键（无需应用焦点）触发录音开始/停止
- 通过 Swift C 互操作调用 whisper.cpp，实现流式实时转录
- SwiftUI Widget 卡片浮窗，实时滚动显示转录文本
- 状态栏图标指示当前录音状态
- 完全离线运行，所有处理在本地完成

**Non-Goals:**
- 多语言实时切换（初版固定语言模型）
- 说话人分离（Speaker Diarization）
- 云端同步或跨设备功能
- iOS/iPadOS 支持
- 自定义 whisper 模型训练

## Decisions

### 决策 1：whisper.cpp 集成方式 — Swift Package vs. 预编译二进制

**选择**：通过 Swift Package Manager 集成 whisper.cpp 源码，使用 `swift-whisper` 开源封装库（或自建 C bridge）。

**原因**：
- 预编译二进制需处理 Gatekeeper 签名，维护多架构版本（x86_64 + arm64）复杂
- SPM 源码集成可自动适配 Metal/CoreML 加速，编译时优化更彻底
- 社区已有成熟封装：`ggerganov/whisper.cpp` 可直接作为 Swift binary target

**备选**：命令行子进程调用 `whisper-cli`，通过 stdout 流读取结果
- 优点：隔离性好，进程崩溃不影响主应用
- 缺点：延迟高（进程启动开销），难以做流式实时转录

### 决策 2：实时转录策略 — 分段处理 vs. 流式 VAD

**选择**：基于 VAD（Voice Activity Detection）的分段处理，每检测到语音静默（>500ms）即触发一次转录。

**原因**：
- whisper.cpp 不支持真正的 token-level 流式输出，需要完整音频段才能转录
- VAD 分段在延迟和准确率之间取得最佳平衡（约 1-3 秒延迟）
- 避免切断词语导致的转录错误

**实现**：
```
[AVCaptureSession] → [PCM Buffer Ring] → [VAD Detector] → [whisper.cpp] → [Text Output]
```

### 决策 3：Widget UI 形态 — 状态栏弹出面板 vs. 独立浮窗

**选择**：状态栏图标 + 点击展开的下拉面板（Popover），不使用独立窗口。

**原因**：
- 状态栏 Popover 是 macOS 系统推荐的"常驻工具"UI 模式（同 CleanMyMac、Bartender）
- 不占用 Dock 位置，不出现在 Cmd+Tab 切换列表
- SwiftUI 原生支持 NSPopover，实现简单
- 快捷键触发录音时无需显示面板，保持后台静默

### 决策 4：全局快捷键实现 — CGEventTap vs. NSEvent.addGlobalMonitor

**选择**：`NSEvent.addGlobalMonitorForEvents` + `MASShortcut` 库（或 `KeyboardShortcuts` SPM 包）。

**原因**：
- `CGEventTap` 需要辅助功能权限（Accessibility），用户体验较差
- `NSEvent.addGlobalMonitorForEvents` 在现代 macOS 中也需要权限，但通过 `KeyboardShortcuts` 库处理权限引导更优雅
- `KeyboardShortcuts`（nicklockwood 维护）是 Swift 生态中最成熟的方案，支持用户自定义快捷键

## Risks / Trade-offs

| 风险 | 缓解措施 |
|------|----------|
| whisper.cpp 首次加载模型耗时（large model ~4s） | 应用启动时预加载，状态栏显示"模型加载中"提示 |
| 全局快捷键权限被拒绝 | 首次启动引导用户开启辅助功能权限，优雅降级为应用内快捷键 |
| Apple Silicon vs Intel 性能差异 | 检测架构，arm64 启用 Metal 加速；x86_64 使用 CPU 路径 |
| 长时间录音导致内存增长 | Ring buffer 限制最大缓存（如 30 分钟），超出自动截断 |
| App Sandbox 限制 whisper 模型文件访问 | 使用 Application Support 目录存储模型，或禁用 Sandbox（非 MAS 分发） |

## Open Questions

1. **模型大小选择**：默认提供 `tiny`（75MB）还是 `base`（142MB）？需要平衡准确率和首次下载体积
2. **音频格式**：whisper.cpp 要求 16kHz mono PCM，AVFoundation 采样率转换在哪层完成（AVAudioEngine 的 installTap 还是手动 resample）
3. **历史记录持久化**：转录结果是否需要跨会话保存？初版可能只保留当次会话内容
