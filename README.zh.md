# VoicePepper

macOS 菜单栏语音转写工具，基于 [whisper.cpp](https://github.com/ggerganov/whisper.cpp) 实现完全离线的实时语音识别。所有音频处理均在本地完成，不上传任何数据。

## 功能特性

- **离线转写** — 基于 whisper.cpp，支持 8 种模型（tiny ~ large-v3），含量化版本
- **全局快捷键** — 默认 `⌥ Space`，任意应用中一键开始/停止录音
- **智能分段** — VAD 静音检测自动分段，实时显示转写结果
- **BLE 录音笔** — 支持蓝牙录音笔（A06），无线实时转写
- **录音历史** — WAV 格式持久化存储，支持回放和重新转写
- **模型热切换** — 在偏好设置中切换模型，无需重启
- **菜单栏常驻** — 状态栏图标，不占用 Dock 和任务栏

## 系统要求

- macOS 13.0 (Ventura) 或更新
- Apple Silicon (M1/M2/M3/M4) 或 Intel Mac

## 安装指南

### 第 1 步：下载

从 [GitHub Releases](https://github.com/wuzhiguocarter/VoicePepper/releases) 页面下载最新版本的 DMG 文件。

**如何选择版本？**

点击屏幕左上角  → 关于本机 → 查看芯片信息：

| 你的芯片 | 下载文件 |
|---------|---------|
| Apple M1 / M2 / M3 / M4 | `VoicePepper-*-arm64.dmg` （体积最小，推荐） |
| Intel | `VoicePepper-*-x86_64.dmg` |
| 不确定 | `VoicePepper-*-universal.dmg` （两种芯片都支持） |

### 第 2 步：安装

1. 双击下载的 `.dmg` 文件，弹出安装窗口
2. 将 **VoicePepper** 图标拖拽到 **Applications** 文件夹
3. 关闭安装窗口，到启动台（Launchpad）或应用程序文件夹找到 VoicePepper

### 第 3 步：首次打开

由于应用未经 Apple 开发者签名，macOS 会阻止首次打开。按以下步骤操作：

1. 打开 **访达 (Finder)** → 应用程序
2. 找到 **VoicePepper**，**右键点击**（或按住 Control 点击）
3. 选择 **打开**
4. 在弹出的对话框中点击 **打开**

> 只需操作一次，之后可正常双击打开。

### 第 4 步：授权权限

首次启动后需要授予两项权限：

**麦克风权限**（系统自动弹窗）：
- 点击 **好** 允许访问麦克风

**辅助功能权限**（全局快捷键需要，手动授予）：
1. 打开 **系统设置** → **隐私与安全性** → **辅助功能**
2. 点击左下角 🔒 解锁
3. 点击 **+**，从应用程序列表中添加 **VoicePepper**
4. 确保 VoicePepper 旁边的开关已打开

### 第 5 步：下载语音模型

首次启动时，应用会引导你下载 Whisper 语音识别模型。

| 模型 | 大小 | 速度 | 准确率 | 推荐场景 |
|------|------|------|--------|---------|
| tiny | 75 MB | 最快 | 一般 | 快速体验、低配 Mac |
| base | 142 MB | 快 | 较好 | 日常使用 |
| large-v3-turbo-q5_0 | 600 MB | 中 | 最佳 | 追求准确率（推荐） |

模型下载一次即可，存储在 `~/Library/Application Support/VoicePepper/models/`。

## 使用指南

### 基本操作

VoicePepper 是菜单栏应用，启动后**不会在 Dock 中显示图标**，请看屏幕右上角的菜单栏。

| 操作 | 说明 |
|------|------|
| `⌥ Space` | 开始 / 停止录音（全局快捷键，任意应用中可用） |
| 点击菜单栏图标 | 展开转写面板，查看转写结果 |
| 面板 → 复制全部 | 将所有转写文本复制到剪贴板 |
| 面板 → 清除 | 清空当前会话 |
| 右键菜单栏图标 | 打开偏好设置 |

### 偏好设置

在偏好设置中可以：

- **自定义快捷键** — 修改录音触发快捷键
- **切换模型** — 选择不同的 Whisper 模型
- **音频源切换** — 在内置麦克风和 BLE 录音笔之间切换

### BLE 录音笔

如有兼容的蓝牙录音笔（A06）：

1. 开启录音笔蓝牙
2. 在偏好设置中选择 BLE 音频源
3. 等待自动连接
4. 按录音笔按钮开始录音，VoicePepper 实时转写

### 卸载

1. 退出 VoicePepper（右键菜单栏图标 → 退出）
2. 从应用程序文件夹删除 VoicePepper.app
3. （可选）删除数据：`rm -rf ~/Library/Application\ Support/VoicePepper`

## 开发者

### 从源码构建

```bash
# 安装依赖
brew install whisper-cpp opus

# 编译
swift build -c release

# 或用 Xcode 打开
open Package.swift
```

详细开发指南见 [SETUP.md](SETUP.md)。

### 技术栈

- **语言**: Swift 5.9 + SwiftUI
- **语音识别**: [whisper.cpp](https://github.com/ggerganov/whisper.cpp)（C API 桥接）
- **音频解码**: [Opus](https://opus-codec.org/)（BLE 录音笔音频）
- **快捷键**: [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts)
- **构建**: Swift Package Manager
- **CI/CD**: GitHub Actions（自动构建 3 种架构 DMG）

## 许可证

[MIT](LICENSE)
