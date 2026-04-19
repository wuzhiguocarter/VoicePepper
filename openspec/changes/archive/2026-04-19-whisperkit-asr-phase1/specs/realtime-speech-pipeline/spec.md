## MODIFIED Requirements

### Requirement: 实验性 WhisperKit 模型加载与预热
系统 SHALL 在实验性模式（`SpeechPipelineMode.experimentalArgmaxOSS`）下按需下载并缓存 WhisperKit 模型，首次录音启动时完成模型预热，预热完成前排队等待音频段。

#### Scenario: 首次进入实验性模式录音
- **WHEN** 用户在实验性模式下开始第一次录音
- **THEN** 系统触发 WhisperKit 模型下载（如缓存不存在），下载/加载完成后处理音频队列，首段转录结果在模型就绪后输出

#### Scenario: 模型已缓存时启动
- **WHEN** WhisperKit 模型已在系统缓存目录中存在
- **THEN** 系统直接加载缓存模型，不重新下载，加载时间 ≤ 5 秒

#### Scenario: 模型下载失败
- **WHEN** 网络不可用或下载超时
- **THEN** 系统捕获错误，记录日志，当次录音的音频段被丢弃（不崩溃）

### Requirement: 实验性模式端到端音频路由
系统 SHALL 在实验性模式激活时，将麦克风 VAD 分段后的 `AudioSegment` 路由给 `WhisperKitASRService` 进行转录，而不路由给 `TranscriptionService`（whisper.cpp）。

#### Scenario: 实验性模式麦克风录音
- **WHEN** `SpeechPipelineMode` 为 `experimentalArgmaxOSS` 且麦克风捕获到音频段
- **THEN** 该音频段被提交给 `WhisperKitASRService` 进行转录，不提交给 `TranscriptionService`

#### Scenario: 默认模式麦克风录音不受影响
- **WHEN** `SpeechPipelineMode` 为 `legacyWhisperCPP`
- **THEN** 音频段路由行为与 Phase 0 完全相同，不经过 `WhisperKitASRService`

### Requirement: WhisperKit 转录结果驱动 AppState
系统 SHALL 将 `WhisperKitASRService` 产出的 `ASRTranscriptEvent` 写入 `AppState.entries`，使现有 Popover UI 无需改动即可展示 WhisperKit 转录文字。

#### Scenario: WhisperKit 完成一段转录
- **WHEN** `WhisperKitASRService` 完成一个 `AudioSegment` 的转录
- **THEN** 转录文字以 `TranscriptionEntry` 形式追加到 `AppState.entries`，Popover 中实时可见

### Requirement: 引擎模式配置 UI
系统 SHALL 在设置页提供引擎模式选择器，允许用户在 `legacyWhisperCPP` 和 `experimentalArgmaxOSS` 之间切换，切换结果持久化，下次启动生效。

#### Scenario: 用户切换引擎模式
- **WHEN** 用户在 Preferences 中选择"WhisperKit + SpeakerKit (Experimental)"
- **THEN** `AppState.speechPipelineMode` 更新并写入 `UserDefaults`，下次 App 启动后新模式生效

#### Scenario: 切换提示
- **WHEN** 用户完成引擎切换
- **THEN** 设置页显示"重启 App 后生效"说明文字
