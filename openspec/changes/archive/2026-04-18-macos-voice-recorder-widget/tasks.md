## 1. 项目初始化与依赖配置

- [x] 1.1 使用 Xcode 创建 macOS App 项目（SwiftUI，最低部署目标 macOS 13.0）
- [x] 1.2 配置 App Sandbox 权限：禁用 Sandbox（非 MAS）或配置麦克风 entitlement
- [x] 1.3 在 Info.plist 添加 NSMicrophoneUsageDescription 权限描述
- [x] 1.4 通过 SPM 添加 `KeyboardShortcuts` 依赖（全局快捷键管理）
- [x] 1.5 通过 SPM 或 git submodule 集成 whisper.cpp，配置 Metal 编译标志
- [x] 1.6 创建 whisper.cpp Swift C bridge 头文件（bridging header）

## 2. 应用架构搭建

- [x] 2.1 实现 AppDelegate（NSApplicationDelegate），配置为 Agent 应用（LSUIElement = true，无 Dock 图标）
- [x] 2.2 创建 StatusBarManager：管理 NSStatusBar 图标和 Popover 展开/收起
- [x] 2.3 设计 AppState 数据模型（ObservableObject）：录音状态、转录文本列表、快捷键配置
- [x] 2.4 创建 DI 容器或 Environment 注入，连接 AudioCaptureService、TranscriptionService 与 UI 层

## 3. 全局快捷键（hotkey-control）

- [x] 3.1 在 AppDelegate 中使用 KeyboardShortcuts 注册默认快捷键 ⌥Space
- [x] 3.2 实现辅助功能权限检测（AXIsProcessTrusted()），未授权时弹出引导 Alert
- [x] 3.3 实现权限变更监听（轮询或 NSWorkspace 通知），授权后自动激活快捷键
- [x] 3.4 构建偏好设置面板（PreferencesView），集成 KeyboardShortcuts.Recorder 组件
- [x] 3.5 实现快捷键冲突检测逻辑，冲突时在设置界面显示警告

## 4. 音频捕获（audio-capture）

- [x] 4.1 创建 AudioCaptureService 类，封装 AVAudioEngine 录音逻辑
- [x] 4.2 实现 installTap 捕获麦克风输入（PCM Buffer），配置 1024 帧缓冲区
- [x] 4.3 实现 AVAudioConverter：将输入格式转换为 16kHz mono float32
- [x] 4.4 创建 AudioRingBuffer（泛型循环队列），最大容量 30 分钟 × 16000 × 4 bytes ≈ 115MB
- [x] 4.5 实现缓冲区溢出检测，溢出时截断最旧数据并通过 Combine 发布警告事件
- [x] 4.6 添加麦克风权限请求流程，权限被拒时发布错误事件供 UI 处理

## 5. Whisper 转录（whisper-transcription）

- [x] 5.1 创建 WhisperModelManager：负责模型文件管理（检测、下载、加载）
- [x] 5.2 实现模型文件下载（URLSession），下载到 ~/Library/Application Support/VoicePepper/models/
- [x] 5.3 实现 WhisperContext 封装（C 函数调用）：whisper_init_from_file、whisper_full、whisper_free
- [x] 5.4 实现 VAD 检测算法：基于 RMS 能量阈值，连续 500ms 低于阈值判定为停顿
- [x] 5.5 创建 TranscriptionService：整合 AudioRingBuffer + VAD + WhisperContext，管理转录队列
- [x] 5.6 实现串行转录队列（OperationQueue maxConcurrentOperationCount=1），防止并发竞争
- [x] 5.7 连续语音超 30 秒强制提交转录（Timer 实现）
- [x] 5.8 编译验证 Metal 加速路径在 Apple Silicon 设备上正确启用

## 6. Widget UI（widget-display）

- [x] 6.1 创建 StatusBarView（SwiftUI），包含录音状态图标动效（脉冲动画）
- [x] 6.2 构建 TranscriptionPopoverView：主面板，包含滚动转录文本区域
- [x] 6.3 实现 TranscriptionListView：使用 ScrollViewReader 自动滚动至最新内容
- [x] 6.4 实现 RecordingStatusBar：面板顶部状态栏，显示计时器（MM:SS）和录音状态
- [x] 6.5 实现音频电平波形组件（AudioLevelView）：使用 Canvas API 绘制实时波形
- [x] 6.6 实现"复制全部"按钮逻辑，复制后显示 200ms "已复制"反馈
- [x] 6.7 实现"清除会话"按钮，添加二次确认 Alert
- [x] 6.8 空状态占位视图（无转录内容时显示提示文字）

## 7. 集成与端到端测试

- [ ] 7.1 端到端验证：快捷键 → 录音 → VAD 分段 → whisper 转录 → UI 显示完整链路
- [ ] 7.2 测试 Intel Mac 兼容性（若有设备），验证 CPU 路径转录速度 ≥ 1x 实时
- [ ] 7.3 测试长时间录音（>30 分钟）缓冲区溢出保护是否正常触发
- [ ] 7.4 测试辅助功能权限引导流程（在沙盒用户下验证）
- [ ] 7.5 测试模型文件缺失时的下载引导流程
- [ ] 7.6 内存泄漏检查：使用 Instruments Allocations 验证录音停止后内存正确释放

## 8. 打包与分发准备

- [ ] 8.1 配置 Xcode Archive scheme，生成签名的 .app bundle
- [x] 8.2 编写 README：whisper 模型下载说明、首次启动权限配置步骤
- [ ] 8.3 创建 DMG 安装包（可选，使用 create-dmg 工具）
