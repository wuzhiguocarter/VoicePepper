---
title: "BLE 设备管理器 SwiftUI 实例不一致导致状态不同步"
category: integration-issues
date: 2026-04-18
module: BLE
tags: [CoreBluetooth, SwiftUI, EnvironmentObject, instance-identity, state-sync]
problem_type: state-desync
severity: high
---

## 问题

偏好设置页显示 BLE 设备"已连接"，但 Popover 始终显示"未连接"。三次修复尝试（Combine assign、sink、didSet 回调）均未解决。

## 根因

`PreferencesView` 通过 `NSApp.delegate as? AppDelegate` 获取 `bleDeviceManager` 时有 fallback 分支创建新实例。当 fallback 触发时，用户在**第二个实例**上扫描和连接，AppDelegate 持有的原始实例从未被操作，回调永远不触发。

```swift
// ❌ 错误：fallback 创建第二个实例
init() {
    if let delegate = NSApp.delegate as? AppDelegate {
        self._bleDeviceManager = ObservedObject(wrappedValue: delegate.bleDeviceManager)
    } else {
        self._bleDeviceManager = ObservedObject(wrappedValue: BLEDeviceManager()) // 第二个实例！
    }
}
```

## 解决方案

用 `@EnvironmentObject` 注入，由 AppDelegate 在创建窗口时传递唯一实例：

```swift
// PreferencesView.swift
@EnvironmentObject var bleDeviceManager: BLEDeviceManager

// AppDelegate.openPreferencesWindow()
let view = PreferencesView()
    .environmentObject(appState)
    .environmentObject(modelManager)
    .environmentObject(bleDeviceManager)  // ← 关键修复
```

## 诊断方法

在 `didSet` 中打印对象地址和回调状态，快速定位实例不一致：

```swift
NSLog("[BLEDeviceManager] connectionState: %@ → %@, callback=%@, self=%p",
      String(describing: oldValue), String(describing: connectionState),
      onConnectionStateChanged == nil ? "nil" : "set",
      Unmanaged.passUnretained(self).toOpaque().debugDescription)
```

## 预防

当数据不同步时，**先验证对象同一性**（是否同一个实例），再怀疑管道机制（Combine、KVO、回调）。SwiftUI 中永远通过 EnvironmentObject 或参数传递共享服务，避免在 View.init() 中自行获取。
