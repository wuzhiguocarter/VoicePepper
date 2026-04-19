## MODIFIED Requirements

### Requirement: VAD 分段实时转录
系统 SHALL 支持在保持现有 `whisper.cpp` 主路径可用的前提下，为未来迁移到新的本地 ASR 引擎预留统一事件模型与实验性适配层。

#### Scenario: 默认主路径保持不变
- **WHEN** 应用正常启动且未启用实验性新栈
- **THEN** 系统继续使用现有 `whisper.cpp` 转录链路，不改变当前 UI 与 E2E 行为

#### Scenario: 实验性新栈可编译接入
- **WHEN** 仓库引入 `WhisperKit`
- **THEN** 应用能够编译通过，并通过独立适配层初始化实验性 ASR 引擎，而不要求立即切换默认主路径
