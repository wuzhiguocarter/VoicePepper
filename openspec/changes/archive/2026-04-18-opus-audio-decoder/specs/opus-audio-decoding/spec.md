## ADDED Requirements

### Requirement: Opus 帧解码
系统 SHALL 使用 libopus 将 40 字节 Opus 帧（SILK 12kHz，20ms）解码为 16kHz mono Float32 PCM 样本。

#### Scenario: 正常解码
- **WHEN** 系统收到一个 40 字节的 Opus 帧
- **THEN** 调用 opus_decode 输出 320 个 Int16 样本（20ms @ 16kHz），转换为 Float32 范围 [-1.0, 1.0]

#### Scenario: 解码失败
- **WHEN** opus_decode 返回负值（帧数据损坏）
- **THEN** 系统返回空数组，跳过该帧，不影响后续帧解码

### Requirement: BLE 数据包批量解码
系统 SHALL 将每个 160 字节 BLE 音频负载拆分为 4 个 40 字节 Opus 帧并依次解码。

#### Scenario: 批量解码
- **WHEN** 系统收到 160 字节音频负载
- **THEN** 按 40 字节步进拆分为 4 帧，逐帧调用 Opus 解码器，合并输出约 1280 个 Float32 样本（80ms @ 16kHz）
