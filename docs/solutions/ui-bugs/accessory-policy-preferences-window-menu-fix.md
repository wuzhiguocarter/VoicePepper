---
title: "macOS .accessory app 中偏好设置窗口无响应及退出按钮灰色"
module: "UI/StatusBar"
tags:
  - macos
  - accessory-app
  - nsapplication
  - activation-policy
  - preferences-window
  - nsmenuitem
  - status-bar
  - appdelegate
  - swiftui-settings-scene
  - nswindow
problem_type: "ui-bug"
date: 2026-04-12
related_files:
  - Sources/VoicePepper/App/AppDelegate.swift
  - Sources/VoicePepper/App/VoicePepperApp.swift
  - Sources/VoicePepper/Models/AppState.swift
  - Sources/VoicePepper/UI/StatusBarManager.swift
  - Sources/VoicePepper/UI/TranscriptionPopoverView.swift
---

## 问题描述

VoicePepper 以 `.accessory` 激活策略运行（`LSUIElement=YES`，无 Dock 图标）：

- 右键状态栏菜单点击「偏好设置…」：**无任何响应，窗口不出现**
- 右键状态栏菜单「退出 VoicePepper」：**按钮灰色，点击无效**
- Popover 左下角 ⚙ 按钮：**同样无响应**

## 根本原因

### 原因一：退出按钮灰色

```swift
// ❌ 错误写法
for item in menu.items { item.target = self }
```

`self` 是 `StatusBarManager`，它没有实现 `terminate(_:)`。AppKit 在菜单显示前会验证每个 item 的 target 是否响应其 action，找不到实现就自动 gray out。

### 原因二：偏好设置无响应

```swift
// ❌ 在 .accessory app 中不可靠
NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
```

SwiftUI 的 `Settings { }` scene 依赖系统菜单栏（App > 偏好设置）触发。`.accessory` 策略的应用没有系统菜单栏，该入口永远无法激活。`showSettingsWindow:` 是私有 API，在 `.accessory` 模式下无法到达 Settings scene。

## 修复方案

### 1. AppState 注入回调（解耦 UI 层）

```swift
// AppState.swift
// 复用 toggleRecordingAction 的 closure bridge 模式
var openPreferencesAction: (() -> Void)?
```

### 2. AppDelegate 手动管理 NSWindow

```swift
// AppDelegate.swift
import SwiftUI

private var preferencesWindow: NSWindow?

func openPreferencesWindow() {
    // 窗口已存在且可见时直接前置，避免重复创建
    if let window = preferencesWindow, window.isVisible {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return
    }

    let view = PreferencesView()
        .environmentObject(appState)
        .environmentObject(modelManager)

    let vc = NSHostingController(rootView: view)
    let window = NSWindow(contentViewController: vc)
    window.title = "偏好设置"
    window.styleMask = [.titled, .closable, .miniaturizable]
    window.setContentSize(NSSize(width: 420, height: 520))
    window.center()
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)

    preferencesWindow = window  // 强引用：防止 ARC 立即回收，窗口一闪即逝
}
```

在 `setupServices()` 中注入：

```swift
appState.openPreferencesAction = { [weak self] in
    self?.openPreferencesWindow()
}
```

### 3. 修复退出按钮 target

```swift
// StatusBarManager.swift — showContextMenu()
// ✅ 分别设置 target，而非统一 for item in items { item.target = self }
let prefsItem = NSMenuItem(title: "偏好设置…", action: #selector(openPreferences), keyEquivalent: ",")
prefsItem.target = self  // StatusBarManager 实现了 openPreferences()

let quitItem = NSMenuItem(title: "退出 VoicePepper",
                          action: #selector(NSApplication.terminate(_:)),
                          keyEquivalent: "q")
quitItem.target = NSApp  // 直接指向 NSApplication，绕过 responder chain

@objc private func openPreferences() {
    appState.openPreferencesAction?()  // 通过回调调用，与 AppDelegate 解耦
}
```

### 4. 调用方统一使用回调

```swift
// TranscriptionPopoverView.swift — gear 按钮
Button {
    appState.openPreferencesAction?()
} label: {
    Image(systemName: "gearshape").font(.caption)
}
```

### 5. 移除 Settings scene

```swift
// VoicePepperApp.swift
// ❌ 移除：Settings scene 在 .accessory app 中无法触发
// Settings { PreferencesView().environmentObject(...) }

// ✅ 替换为占位（SwiftUI App body 至少需要一个 Scene）
WindowGroup(id: "void") {
    EmptyView()
}
.defaultSize(width: 0, height: 0)
```

## 预防清单

- `.accessory` 应用禁用 SwiftUI `Settings { }` scene 和 `showSettingsWindow:` 私有 API
- 每个 `NSMenuItem` 显式设置独立 `target`，不使用 `for item in items { item.target = self }` 批量覆盖
- `NSApplication.terminate(_:)` 的 target 必须是 `NSApp`，不能是自定义类
- 手动持有 `NSWindow` 强引用（实例变量），防止 ARC 回收导致窗口闪现即消
- 需要 `activate(ignoringOtherApps: true)` 确保 `.accessory` 应用窗口接受键盘输入

## 验证

1. 右键状态栏图标 → 「退出 VoicePepper」可点击，应用正常退出
2. 右键 → 「偏好设置…」→ 窗口弹出
3. Popover ⚙ 按钮 → 同一窗口弹出
4. 关闭后再次点击 → 新窗口创建；未关闭时再次点击 → 已有窗口前置

## 相关文档

- [`docs/solutions/best-practices/macos-ax-e2e-testing-swiftui-2026-04-11.md`](../best-practices/macos-ax-e2e-testing-swiftui-2026-04-11.md) — 同样使用 closure bridge 模式（`toggleRecordingAction`）解决 AppDelegate-SwiftUI 通信
- [`docs/solutions/integration-issues/whisper-cpp-ggml-backend-integration-swift-2026-04-11.md`](../integration-issues/whisper-cpp-ggml-backend-integration-swift-2026-04-11.md) — WhisperContext 设计与 MainActor 隔离模式
