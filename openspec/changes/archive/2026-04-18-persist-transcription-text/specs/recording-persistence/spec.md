## MODIFIED Requirements

### Requirement: 录音文件自动保存
系统 SHALL 在每次 VAD 分段完成后，将该段的 Float32 PCM 数据异步写入 WAV 文件至 `~/Library/Application Support/VoicePepper/Recordings/` 目录。文件名格式为 `Recording_YYYYMMDD_HHmmss.wav`，时间戳取分段完成时刻。同时，将当前会话产生的所有转录文本写入同名的 `.txt` 文件。

#### Scenario: VAD 分段完成后保存文件
- **WHEN** VAD 检测到静音并触发 `onSegmentComplete` 回调
- **THEN** 系统在后台异步将 PCM 样本写入 WAV 文件，同时将转录文本写入同名 `.txt` 文件，不阻塞主线程

#### Scenario: 有转录内容时保存文本
- **WHEN** VAD 分段完成且当前会话有转录条目
- **THEN** 系统将转录文本按时间顺序拼接写入与录音同名的 `.txt` 文件

#### Scenario: 无转录内容时仅保存音频
- **WHEN** VAD 分段完成但当前会话无转录条目（模型未加载等）
- **THEN** 系统仅保存 WAV 文件，不创建 `.txt` 文件

#### Scenario: 目标目录不存在时自动创建
- **WHEN** 应用首次保存录音且 Recordings 目录不存在
- **THEN** 系统自动创建目录后完成文件写入

#### Scenario: 写入失败时静默处理
- **WHEN** 文件写入过程中发生 I/O 错误（如磁盘满）
- **THEN** 系统在日志中记录错误，不向用户展示错误弹窗，不影响转录流程
