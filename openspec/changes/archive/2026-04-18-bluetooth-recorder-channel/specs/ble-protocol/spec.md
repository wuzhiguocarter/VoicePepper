## ADDED Requirements

### Requirement: 数据包封装
系统 SHALL 按照录音笔协议格式封装发送数据包：Magic(0x5A) + SeqNo(1B) + CRC16(2B) + DataLen(2B, 小端) + Data(nB)。

#### Scenario: 封装控制命令包
- **WHEN** 系统需要发送 type=0, cmd=3（获取电量）命令
- **THEN** 生成的数据包以 0x5A 开头，包含递增的包序号，CRC16 由 DataLen+Data 计算（XMODEM 算法），DataLen 为实际数据长度（小端序），Data 区域包含 type=0x00 + cmd=0x03

#### Scenario: 包序号循环
- **WHEN** 包序号达到 255 后再发送下一个包
- **THEN** 包序号重置为 0 并继续递增

### Requirement: 数据包解析
系统 SHALL 正确解析接收到的数据包，验证 Magic 字节和 CRC 校验。

#### Scenario: 正常解析
- **WHEN** 收到一个完整的数据包，Magic 为 0x5A 且 CRC 校验通过
- **THEN** 系统提取 SeqNo、数据类型和数据内容，传递给业务层处理

#### Scenario: Magic 校验失败
- **WHEN** 收到的数据包首字节不是 0x5A
- **THEN** 系统丢弃该包并记录警告日志

#### Scenario: CRC 校验失败
- **WHEN** 收到的数据包 CRC 校验不通过
- **THEN** 系统丢弃该包并记录警告日志，不发送 ACK

### Requirement: CRC-16/XMODEM 校验
系统 SHALL 使用 CRC-16/XMODEM 算法计算校验值，计算范围为 DataLen 字段 + Data 字段。

#### Scenario: CRC 计算正确性
- **WHEN** 系统对 DataLen + Data 区域执行 CRC-16/XMODEM 计算
- **THEN** 计算结果与标准 CRC-16/XMODEM 实现一致（多项式 0x1021，初始值 0x0000）

### Requirement: ACK 回复机制
系统 SHALL 在成功接收数据包后发送 ACK 回复，回复包的包序号与接收包序号相同。

#### Scenario: 正常 ACK
- **WHEN** 系统成功接收并解析一个来自设备的数据包
- **THEN** 系统构造 ACK 包（与收到包相同的 SeqNo），通过 Characteristic 0xAE21 发送

### Requirement: 命令收发
系统 SHALL 支持发送控制命令（type=0）、实时转写命令（type=1）并正确路由接收到的不同类型数据。

#### Scenario: 发送控制命令
- **WHEN** 业务层请求发送"同步时间"命令
- **THEN** 系统封装 type=0, cmd=0, param=当前北京时间（7 字节：年2B+月1B+日1B+时1B+分1B+秒1B）的数据包，通过 Characteristic 0xAE21 发送

#### Scenario: 接收音频数据
- **WHEN** 系统收到 type=1, cmd=1 的数据包
- **THEN** 提取音频数据部分，传递给 BLERecorderService 进行音频处理

#### Scenario: 接收按键命令
- **WHEN** 系统通过 Characteristic 0xAE23 收到 type=3 的数据包
- **THEN** 提取按键命令（cmd 值），传递给业务层处理按键联动
