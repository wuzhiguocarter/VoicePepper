## Why

开发者和内容创作者在工作中频繁需要快速记录语音并获得文字转录，但现有工具要么需要切换应用、要么依赖云端 API（有隐私风险和网络延迟）。本项目提供一个轻量级 macOS 原生 Widget APP，通过全局快捷键一键录音、本地 whisper-cpp 实时转录，让用户无需离开当前工作流即可完成语音转文字。

## What Changes

- **新建** macOS 桌面应用（Swift/SwiftUI），以 Widget 形式常驻状态栏或桌面
- **新增** 全局快捷键监听，支持一键开启/停止后台录音（无需切换焦点）
- **新增** 本地 whisper-cpp 集成，通过 Swift 调用 whisper.cpp 进行离线实时转录
- **新增** Widget 卡片 UI，实时滚动展示转录文本，支持复制和历史查看
- **新增** 系统托盘图标，显示录音状态（录音中/空闲）

## Capabilities

### New Capabilities

- `audio-capture`: 后台麦克风录音能力，支持全局快捷键触发，AVFoundation 实现
- `whisper-transcription`: 本地 whisper-cpp 集成，将音频流实时转换为文字
- `widget-display`: 桌面 Widget 卡片，实时展示转录结果并支持文本操作
- `hotkey-control`: 全局快捷键注册与管理，不依赖应用焦点

### Modified Capabilities

<!-- 无现有规范需要修改 -->

## Impact

- **依赖**: whisper-cpp（本地二进制或 Swift Package）、AVFoundation、SwiftUI、AppKit
- **权限**: 麦克风访问权限（NSMicrophoneUsageDescription）、辅助功能权限（全局快捷键）
- **平台**: macOS 13.0+ (Ventura)
- **隐私**: 全程本地处理，无网络请求，音频数据不离开设备
