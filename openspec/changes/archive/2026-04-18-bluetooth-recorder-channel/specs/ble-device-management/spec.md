## ADDED Requirements

### Requirement: BLE 设备扫描
系统 SHALL 使用 CBCentralManager 扫描包含 Service UUID 0xAE20 的 BLE 外围设备，并在 UI 中展示已发现的设备列表（设备名称、信号强度）。

#### Scenario: 发起扫描
- **WHEN** 用户在蓝牙设备管理界面点击"扫描"按钮
- **THEN** 系统开始 BLE 扫描，仅显示广播 Service 0xAE20 的设备，扫描持续 10 秒后自动停止

#### Scenario: 蓝牙未开启
- **WHEN** 系统发起 BLE 扫描但 Mac 蓝牙处于关闭状态
- **THEN** 系统在 UI 中显示"请先开启蓝牙"提示，不执行扫描

#### Scenario: 无设备发现
- **WHEN** 扫描 10 秒内未发现任何匹配设备
- **THEN** 系统在 UI 中显示"未找到录音笔设备"提示

### Requirement: BLE 设备连接
系统 SHALL 允许用户从已发现设备列表中选择一个设备进行连接，连接成功后订阅所有必要的 Characteristic 通知。

#### Scenario: 连接成功
- **WHEN** 用户选择一个已发现的录音笔设备并点击"连接"
- **THEN** 系统连接该 Peripheral，发现 Service 0xAE20，订阅 Characteristic 0xAE22 和 0xAE23 的通知，UI 显示"已连接"状态

#### Scenario: 连接失败
- **WHEN** 连接超时（15 秒）或被设备拒绝
- **THEN** 系统在 UI 中显示连接失败原因，用户可重试

### Requirement: BLE 设备断开
系统 SHALL 支持用户主动断开录音笔连接，且在意外断连时通知用户。

#### Scenario: 用户主动断开
- **WHEN** 用户点击"断开连接"按钮
- **THEN** 系统取消所有 Characteristic 订阅，断开 Peripheral 连接，UI 恢复为"未连接"状态

#### Scenario: 意外断连
- **WHEN** 录音笔超出 BLE 范围或电量耗尽导致连接中断
- **THEN** 系统在 UI 中显示"连接已断开"，并自动触发重连流程

### Requirement: 自动重连
系统 SHALL 在意外断连后自动尝试重连，采用指数退避策略，最多重试 5 次。

#### Scenario: 重连成功
- **WHEN** 设备意外断连后，系统在第 N 次重连尝试时成功连接
- **THEN** 系统恢复所有 Characteristic 订阅，UI 显示"已连接"，重连计数器归零

#### Scenario: 重连耗尽
- **WHEN** 5 次重连均失败（间隔 2s → 4s → 8s → 16s → 32s）
- **THEN** 系统停止自动重连，UI 显示"连接已断开，请手动重连"，用户可通过"重新连接"按钮手动发起

### Requirement: 设备信息查询
系统 SHALL 在连接成功后查询录音笔的电池电量和设备状态，并持续更新。

#### Scenario: 获取电池电量
- **WHEN** 设备连接成功
- **THEN** 系统发送"获取电量"命令（type=0, cmd=3），解析回复的电量百分比（0-100）或充电状态（110），在 UI 中展示

#### Scenario: 获取设备状态
- **WHEN** 设备连接成功
- **THEN** 系统发送"获取设备状态"命令（type=0, cmd=14），解析设备状态 bit mask，在 UI 中展示当前模式（空闲/录音/播放/实时转写等）

#### Scenario: 电量通知更新
- **WHEN** 录音笔通过 Characteristic 0xAE23 推送电量变化
- **THEN** 系统解析并更新 UI 中的电量显示
