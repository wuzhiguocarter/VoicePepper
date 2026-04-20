# Spec: recording-source-switch

## Purpose

定义录音源类型（麦克风/蓝牙录音笔）的切换管理、状态持久化及 UI 状态感知。

## Requirements

### Requirement: 录音源类型定义
系统 SHALL 定义录音源枚举类型，包含 microphone（麦克风）和 bluetoothRecorder（蓝牙录音笔）两种选项。

#### Scenario: 默认录音源
- **WHEN** App 启动且未曾切换过录音源
- **THEN** 默认录音源为 microphone

### Requirement: 录音源切换
系统 SHALL 允许用户在 Popover 界面或偏好设置中切换录音源，切换时自动停止当前录音。

#### Scenario: 空闲时切换
- **WHEN** App 处于空闲状态，用户将录音源从 microphone 切换为 bluetoothRecorder
- **THEN** 系统记录新的录音源选择，后续录音使用蓝牙通道

#### Scenario: 录音中切换
- **WHEN** App 正在录音，用户尝试切换录音源
- **THEN** 系统先停止当前录音，再切换到新的录音源，UI 恢复到空闲状态

#### Scenario: 蓝牙未连接时切换到蓝牙
- **WHEN** 用户切换到 bluetoothRecorder 但蓝牙录音笔未连接
- **THEN** 系统允许切换，但在用户尝试开始录音时提示"请先连接蓝牙录音笔"

### Requirement: 录音源状态持久化
系统 SHALL 将用户选择的录音源持久化到 UserDefaults，App 重启后恢复上次选择。

#### Scenario: 持久化与恢复
- **WHEN** 用户选择 bluetoothRecorder 作为录音源后退出 App
- **THEN** 下次启动时录音源自动恢复为 bluetoothRecorder

### Requirement: 录音源感知的 UI 状态
系统 SHALL 根据当前录音源在 UI 中展示对应的状态信息。

#### Scenario: 麦克风模式 UI
- **WHEN** 录音源为 microphone
- **THEN** Popover 中显示麦克风相关状态（音频电平、录音时长），不显示蓝牙设备信息

#### Scenario: 蓝牙模式 UI
- **WHEN** 录音源为 bluetoothRecorder
- **THEN** Popover 中显示蓝牙设备连接状态、电池电量、设备状态，以及蓝牙音频电平

### Requirement: filePlayback 录音源枚举扩展
系统 SHALL 在 `RecordingSource` 枚举中新增 `filePlayback` case，用于标识文件回放录音源，该 case 不加入 `CaseIterable` 的 UI 迭代序列。

#### Scenario: filePlayback case 可被代码引用
- **WHEN** 代码使用 `RecordingSource.filePlayback` 常量
- **THEN** 编译通过，可用于 AppDelegate 路由判断和 `appState.recordingSource` 赋值

#### Scenario: filePlayback 不出现在 CaseIterable 枚举
- **WHEN** 遍历 `RecordingSource.allCases`
- **THEN** 结果仅包含 `microphone` 和 `bluetoothRecorder`，不包含 `filePlayback`，UI Picker 不渲染 filePlayback 选项
