## ADDED Requirements

### Requirement: filePlayback 录音源枚举扩展
系统 SHALL 在 `RecordingSource` 枚举中新增 `filePlayback` case，用于标识文件回放录音源，该 case 不加入 `CaseIterable` 的 UI 迭代序列。

#### Scenario: filePlayback case 可被代码引用
- **WHEN** 代码使用 `RecordingSource.filePlayback` 常量
- **THEN** 编译通过，可用于 AppDelegate 路由判断和 `appState.recordingSource` 赋值

#### Scenario: filePlayback 不出现在 CaseIterable 枚举
- **WHEN** 遍历 `RecordingSource.allCases`
- **THEN** 结果仅包含 `microphone` 和 `bluetoothRecorder`，不包含 `filePlayback`，UI Picker 不渲染 filePlayback 选项
