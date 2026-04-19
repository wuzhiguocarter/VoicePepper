## ADDED Requirements

### Requirement: 统一实时语音事件模型
系统 SHALL 提供统一的数据模型来表示音频帧、ASR 事件、speaker 事件和合并后的实时 transcript chunk，以支持未来迁移到新的本地语音栈。

#### Scenario: ASR 与 speaker 事件使用统一模型
- **WHEN** 实验性 ASR 引擎和 diarization 引擎向应用层输出事件
- **THEN** 应用层使用统一的数据模型承接这些事件，而不是直接把底层 SDK 类型暴露给 UI

### Requirement: Timeline merger 合并实时事件
系统 SHALL 提供 timeline merger，将 ASR 文本事件与 speaker segment 事件合并为统一 transcript chunk。

#### Scenario: 接收 ASR 事件
- **WHEN** merger 收到一条文本事件
- **THEN** 它更新或生成对应的 transcript chunk

#### Scenario: 接收 speaker 事件
- **WHEN** merger 收到一条 speaker segment 事件
- **THEN** 它尝试将 speaker 标签映射到时间重叠的 transcript chunk

### Requirement: 实验性 WhisperKit / SpeakerKit 适配层
系统 SHALL 提供实验性 `WhisperKit` 与 `SpeakerKit` 服务封装，以支持未来迁移验证，同时不影响当前默认链路。

#### Scenario: 初始化实验性 ASR 服务
- **WHEN** 应用启用实验性新栈
- **THEN** 系统可初始化 `WhisperKit` 适配层

#### Scenario: 初始化实验性 speaker 服务
- **WHEN** 应用启用实验性新栈
- **THEN** 系统可初始化 `SpeakerKit` 适配层
