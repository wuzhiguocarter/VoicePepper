## MODIFIED Requirements

### Requirement: 录音文件自动保存
系统 SHALL 在每次录音会话结束后，将该会话的完整 Float32 PCM 数据写入 `~/Library/Application Support/VoicePepper/Recordings/` 目录，并为该录音保存相关的 transcript sidecar 文件。

#### Scenario: 会话结束后保存录音与 transcript
- **WHEN** 一次录音会话结束且存在完整会话样本
- **THEN** 系统保存 WAV 录音文件，并按可用性保存纯文本 `.txt` 和 speaker-attributed `.json` sidecar

#### Scenario: 目标目录不存在时自动创建
- **WHEN** 应用首次保存录音且 Recordings 目录不存在
- **THEN** 系统自动创建目录后完成文件写入

### Requirement: 录音存储目录可枚举
系统 SHALL 确保所有录音主文件和 transcript sidecar 存放于同一固定目录，且该目录可通过 `FileManager` 枚举以支持历史列表功能。

#### Scenario: 枚举录音文件
- **WHEN** 调用录音列表加载逻辑
- **THEN** 返回目录内所有有效录音文件，并识别各自配对的 `.txt` 和 `.json` sidecar

### Requirement: 删除录音时同步删除 transcript sidecar
系统 SHALL 在删除录音主文件时，同步删除同名 transcript sidecar 文件。

#### Scenario: 删除完整记录
- **WHEN** 用户删除一条录音
- **THEN** 同名 `.wav`、`.txt`、`.json` 文件一并删除；若某个 sidecar 缺失，不影响删除流程
