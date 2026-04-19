## MODIFIED Requirements

### Requirement: speaker-attributed transcript 持久化格式
系统 SHALL 将结构化 transcript 保存为与录音同名的 UTF-8 JSON 文件，至少包含会话时间、全文文本、speaker chunk 列表以及为 future speaker identification 预留的可选字段。

#### Scenario: 结构化字段包含引擎元数据
- **WHEN** 系统写入 transcript JSON
- **THEN** sidecar 支持记录 `asrEngine`、`diarizationEngine`、`modelVersion` 等引擎元数据，用于比较不同本地推理栈
