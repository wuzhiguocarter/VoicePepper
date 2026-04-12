## ADDED Requirements

### Requirement: 录音文件自动保存
系统 SHALL 在每次 VAD 分段完成后，将该段的 Float32 PCM 数据异步写入 M4A 文件至 `~/Library/Application Support/VoicePepper/Recordings/` 目录。文件名格式为 `Recording_YYYYMMDD_HHmmss.m4a`，时间戳取分段完成时刻。

#### Scenario: VAD 分段完成后保存文件
- **WHEN** VAD 检测到静音并触发 `onSegmentComplete` 回调
- **THEN** 系统在后台异步将 PCM 样本写入 M4A 文件，不阻塞主线程

#### Scenario: 目标目录不存在时自动创建
- **WHEN** 应用首次保存录音且 Recordings 目录不存在
- **THEN** 系统自动创建目录后完成文件写入

#### Scenario: 写入失败时静默处理
- **WHEN** 文件写入过程中发生 I/O 错误（如磁盘满）
- **THEN** 系统在日志中记录错误，不向用户展示错误弹窗，不影响转录流程

### Requirement: 保存格式为 M4A（AAC 编码）
系统 SHALL 使用 `AVAssetWriter` 将 16kHz mono Float32 PCM 编码为 AAC，输出格式为 M4A，比特率不低于 64kbps。

#### Scenario: 编码参数正确
- **WHEN** 写入一个时长 10 秒的录音段
- **THEN** 输出文件为有效的 M4A 格式，可被 `AVAudioPlayer` 正常加载播放

### Requirement: 录音存储目录可枚举
系统 SHALL 确保所有保存的 M4A 文件存放于同一固定目录，且该目录可通过 `FileManager` 枚举以支持历史列表功能。

#### Scenario: 枚举录音文件
- **WHEN** 调用 `RecordingFileService.listRecordings()`
- **THEN** 返回目录内所有 `.m4a` 文件的 URL 列表，按修改时间降序排列
