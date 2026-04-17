# Spec: recording

## Purpose

管理音频采集与 VAD 分段流程，并在分段完成时并行触发转录与文件保存两条下游管道。

## Requirements

### Requirement: 录音完成后触发文件保存
录音流程 SHALL 在 VAD 分段完成时，除触发转录外，还异步触发 `RecordingFileService` 的文件保存操作，两者并行执行互不阻塞。

#### Scenario: VAD 分段同时触发转录和保存
- **WHEN** `AudioCaptureService.onSegmentComplete` 回调触发
- **THEN** `TranscriptionService` 接收样本进行转录，`RecordingFileService` 接收样本异步写盘，两者独立执行

#### Scenario: 保存失败不影响转录
- **WHEN** 文件写盘失败（如磁盘满）
- **THEN** 转录结果仍正常输出，不因写盘失败而中断或延迟

### Requirement: 录音状态管理
录音状态 SHALL 扩展以支持外部设备（蓝牙录音笔）触发的录音操作。RecordingState 枚举保持不变（idle / recording / processing），但录音的启动和停止 SHALL 可以由蓝牙录音笔的物理按键触发，与快捷键和 UI 按钮触发的效果完全一致。

#### Scenario: 快捷键触发录音
- **WHEN** 用户按下 ⌥Space 快捷键
- **THEN** App 切换录音状态（开始/停止），行为与当前一致

#### Scenario: UI 按钮触发录音
- **WHEN** 用户点击 Popover 中的录音按钮
- **THEN** App 切换录音状态（开始/停止），行为与当前一致

#### Scenario: 蓝牙按键触发开始录音
- **WHEN** 蓝牙录音笔推送"开始录音"按键命令（type=3, cmd=1）且当前为空闲状态
- **THEN** App 进入录音状态，使用蓝牙录音源，录音行为与其他方式触发一致

#### Scenario: 蓝牙按键触发保存录音
- **WHEN** 蓝牙录音笔推送"保存录音"按键命令（type=3, cmd=3）且当前正在录音
- **THEN** App 停止录音，处理剩余音频，行为与其他方式触发一致
