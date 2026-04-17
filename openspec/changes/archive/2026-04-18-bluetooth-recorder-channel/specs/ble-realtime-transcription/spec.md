## ADDED Requirements

### Requirement: 启动实时转写会话
系统 SHALL 在用户选择蓝牙录音源并开始录音时，向录音笔发送"开始实时转写"命令，进入实时转写模式。

#### Scenario: 发起实时转写
- **WHEN** 用户在蓝牙录音源模式下点击录音按钮或按下快捷键
- **THEN** 系统通过 BLE 发送 type=1, cmd=0（开始实时转写）命令，App 进入录音状态，等待设备推送音频数据

#### Scenario: 设备未连接时尝试启动
- **WHEN** 用户尝试以蓝牙录音源启动录音，但录音笔未连接
- **THEN** 系统在 UI 中提示"请先连接蓝牙录音笔"，不启动录音

### Requirement: 接收实时音频流
系统 SHALL 持续接收录音笔通过 BLE 推送的实时音频数据（type=1, cmd=1），累积为 AudioSegment 后送入 TranscriptionService 转录。

#### Scenario: 正常音频流接收
- **WHEN** 录音笔持续推送 type=1, cmd=1 音频数据包
- **THEN** 系统提取每包中的音频数据，累积到缓冲区，当缓冲区满足一个转录段（约 3-5 秒音频）时，封装为 AudioSegment 发送到 TranscriptionService

#### Scenario: 音频格式转换
- **WHEN** 系统收到 BLE 音频数据（假设为 PCM 16kHz 16-bit mono LE）
- **THEN** 系统将 Int16 样本转换为 Float32（范围 -1.0 ~ 1.0），保持 16kHz 采样率，直接供 whisper.cpp 使用

### Requirement: 结束实时转写会话
系统 SHALL 在用户停止录音时，向录音笔发送"结束实时转写"命令，并处理缓冲区中剩余的音频数据。

#### Scenario: 用户主动停止
- **WHEN** 用户点击停止录音按钮或按下快捷键
- **THEN** 系统发送 type=1, cmd=2（结束实时转写）命令，将缓冲区中剩余音频封装为最后一个 AudioSegment 送入转录，App 回到空闲状态

#### Scenario: 设备端主动停止
- **WHEN** 录音笔发送 type=1, cmd=4, param=2（停止）
- **THEN** 系统处理缓冲区中剩余音频，App 回到空闲状态，UI 显示"录音笔已停止转写"

### Requirement: 暂停与继续转写
系统 SHALL 支持实时转写会话的暂停和继续操作，由 App 端或设备端发起。

#### Scenario: App 端暂停
- **WHEN** 用户点击暂停按钮
- **THEN** 系统发送 type=1, cmd=3, param=1（暂停）命令，App 进入暂停状态，暂停接收和转录音频

#### Scenario: App 端继续
- **WHEN** 用户点击继续按钮
- **THEN** 系统发送 type=1, cmd=3, param=0（继续）命令，App 恢复接收和转录音频

#### Scenario: 设备端暂停
- **WHEN** 录音笔发送 type=1, cmd=4, param=1（暂停）
- **THEN** App 进入暂停状态，UI 显示"录音笔已暂停"

#### Scenario: 设备端继续
- **WHEN** 录音笔发送 type=1, cmd=4, param=0（继续）
- **THEN** App 恢复接收和转录音频

### Requirement: 按键联动录音
系统 SHALL 响应录音笔通过 Characteristic 0xAE23 推送的按键命令，联动 App 录音状态。

#### Scenario: 设备端开始录音
- **WHEN** 录音笔推送 type=3, cmd=1（开始录音按键）
- **THEN** 系统自动发起实时转写（等同用户点击录音按钮），并回复 ACK type=3, cmd=2, param=1（成功）

#### Scenario: 设备端保存录音
- **WHEN** 录音笔推送 type=3, cmd=3（保存录音按键）
- **THEN** 系统停止实时转写，并回复 ACK type=3, cmd=4, param=1（成功）

#### Scenario: 设备端暂停/继续录音
- **WHEN** 录音笔推送 type=3, cmd=5（暂停）或 cmd=7（继续）
- **THEN** 系统执行对应的暂停/继续操作，并回复 ACK type=3, cmd=6/8, param=1（成功）

### Requirement: 实时音频电平显示
系统 SHALL 在实时转写过程中计算 BLE 音频流的 RMS 电平，用于 UI 波形显示。

#### Scenario: 音频电平更新
- **WHEN** 系统收到一批 BLE 音频数据
- **THEN** 计算该批数据的 RMS 值（0.0-1.0），通过 AppState.audioLevel 更新 UI 波形显示
