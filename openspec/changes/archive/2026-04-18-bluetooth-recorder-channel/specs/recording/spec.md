## MODIFIED Requirements

### Requirement: 录音状态管理
录音状态 SHALL 扩展以支持外部设备（蓝牙录音笔）触发的录音操作。RecordingState 枚举保持不变（idle / recording / processing），但录音的启动和停止 SHALL 可以由蓝牙录音笔的物理按键触发，与快捷键和 UI 按钮触发的效果完全一致。

#### Scenario: 快捷键触发录音（保持不变）
- **WHEN** 用户按下 ⌥Space 快捷键
- **THEN** App 切换录音状态（开始/停止），行为与当前一致

#### Scenario: UI 按钮触发录音（保持不变）
- **WHEN** 用户点击 Popover 中的录音按钮
- **THEN** App 切换录音状态（开始/停止），行为与当前一致

#### Scenario: 蓝牙按键触发开始录音
- **WHEN** 蓝牙录音笔推送"开始录音"按键命令（type=3, cmd=1）且当前为空闲状态
- **THEN** App 进入录音状态，使用蓝牙录音源，录音行为与其他方式触发一致

#### Scenario: 蓝牙按键触发保存录音
- **WHEN** 蓝牙录音笔推送"保存录音"按键命令（type=3, cmd=3）且当前正在录音
- **THEN** App 停止录音，处理剩余音频，行为与其他方式触发一致
