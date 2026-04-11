# VoicePepper 开发与运行指南

## 前置依赖

```bash
# whisper-cpp（必须）
brew install whisper-cpp

# Xcode Command Line Tools（用于 swift build）
xcode-select --install
```

## Whisper 模型下载

首次运行时 APP 会自动引导下载，也可以手动下载：

```bash
# 创建模型目录
mkdir -p ~/Library/Application\ Support/VoicePepper/models

# 下载 base 模型（推荐，准确率与速度平衡）
curl -L https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin \
     -o ~/Library/Application\ Support/VoicePepper/models/ggml-base.bin

# 或下载 tiny 模型（更快，适合实时场景）
curl -L https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin \
     -o ~/Library/Application\ Support/VoicePepper/models/ggml-tiny.bin
```

也可以复用 Homebrew 自带的测试模型（tiny，已下载）：

```bash
cp /opt/homebrew/share/whisper-cpp/for-tests-ggml-tiny.bin \
   ~/Library/Application\ Support/VoicePepper/models/ggml-tiny.bin
```

## 开发构建（CLI）

```bash
# 编译
swift build

# 运行（注意：命令行运行无法正常使用 Cocoa UI，请用 Xcode 运行完整 App）
.build/debug/VoicePepper
```

## Xcode 构建（推荐）

```bash
# 在 Xcode 中打开项目
open Package.swift
```

Xcode 中配置：
1. Product > Scheme > VoicePepper
2. Target > Signing & Capabilities：添加团队签名
3. Info.plist：确认 `NSMicrophoneUsageDescription` 存在
4. Entitlements：导入 `Sources/VoicePepper/Resources/VoicePepper.entitlements`
5. `Command+R` 运行

## 首次权限配置

运行后 APP 会出现在菜单栏（麦克风图标）。

1. **麦克风权限**：系统会自动弹出请求，点击"允许"
2. **辅助功能权限**（全局快捷键必须）：
   - 系统设置 > 隐私与安全 > 辅助功能
   - 添加 VoicePepper 并开启

## 使用方式

| 操作 | 说明 |
|------|------|
| `⌥ Space` | 开始/停止录音（默认快捷键） |
| 点击菜单栏图标 | 展开转录面板 |
| 面板 > 复制全部 | 复制所有转录文本到剪贴板 |
| 面板 > 清除 | 清空当前会话记录 |
| 右键菜单栏图标 | 打开偏好设置（自定义快捷键、选择模型） |

## 项目结构

```
VoicePepper/
├── Package.swift                          # SPM 构建配置
├── Sources/
│   ├── CWhisper/                         # whisper.cpp C bridge
│   │   ├── include/CWhisper.h
│   │   └── CWhisper.c
│   └── VoicePepper/
│       ├── App/
│       │   ├── VoicePepperApp.swift      # @main 入口
│       │   └── AppDelegate.swift         # 应用生命周期 & 快捷键
│       ├── Models/
│       │   └── AppState.swift            # 全局状态（ObservableObject）
│       ├── Services/
│       │   ├── AudioCaptureService.swift # AVAudioEngine 录音
│       │   ├── AudioRingBuffer.swift     # 环形缓冲区
│       │   ├── VADDetector.swift         # 语音活动检测
│       │   ├── WhisperContext.swift      # whisper.cpp C API 封装
│       │   ├── WhisperModelManager.swift # 模型下载 & 加载
│       │   ├── TranscriptionService.swift# 串行转录队列
│       │   └── AccessibilityMonitor.swift# 辅助功能权限监听
│       └── UI/
│           ├── StatusBarManager.swift    # 状态栏图标 & Popover
│           ├── TranscriptionPopoverView.swift
│           ├── TranscriptionListView.swift
│           ├── RecordingStatusBar.swift
│           ├── AudioLevelView.swift
│           └── PreferencesView.swift
└── Resources/
    ├── Info.plist                        # App 元数据（Xcode 使用）
    └── VoicePepper.entitlements         # 权限配置
```

## 架构说明

```
[快捷键 ⌥Space]
       ↓
[AppDelegate.handleToggleRecording]
       ↓
[AudioCaptureService.start()]
  AVAudioEngine → AVAudioConverter(16kHz mono)
       ↓
[VADDetector] — 500ms 静音触发分段
       ↓
[TranscriptionService.enqueue(segment)]
  OperationQueue(serial) → WhisperContext.transcribe()
       ↓
[AppState.appendEntry()] → @Published
       ↓
[TranscriptionListView] — 自动滚动显示
```
