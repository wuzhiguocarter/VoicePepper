## MODIFIED Requirements

### Requirement: 接收实时音频流
系统 SHALL 持续接收录音笔通过 BLE 推送的实时音频数据（type=1, cmd=1），使用 Opus 解码器将每包 160 字节负载解码为 16kHz Float32 PCM，累积为 AudioSegment 后送入 TranscriptionService 转录。

#### Scenario: 正常音频流接收
- **WHEN** 录音笔持续推送 type=1, cmd=1 音频数据包
- **THEN** 系统对每包 160 字节负载调用 BLEOpusDecoder.decodePacket，将输出的 Float32 样本累积到缓冲区，满足约 4 秒时封装为 AudioSegment 发送到 TranscriptionService

#### Scenario: Opus 解码输出格式
- **WHEN** 系统使用 Opus 解码器处理 BLE 音频数据
- **THEN** 输出为 16kHz mono Float32 PCM，与 Whisper 输入格式完全匹配，无需额外重采样
