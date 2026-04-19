## MODIFIED Requirements

### Requirement: VAD 分段实时转录（实验性引擎可运行）
系统 SHALL 在实验性模式下使用 `WhisperKit` 作为实际可运行的 ASR 引擎，对 VAD 分段音频执行转录并产生真实文字输出（不仅是"可编译"）。

#### Scenario: 实验性模式下 WhisperKit 完成转录
- **WHEN** `SpeechPipelineMode` 为 `experimentalArgmaxOSS` 且录音中出现语音段
- **THEN** 系统将该语音段提交给 `WhisperKitASRService`，模型完成推理后产出 `ASRTranscriptEvent`，文字出现在 Popover 中

#### Scenario: 实验性模式首字延迟可接受
- **WHEN** WhisperKit 模型已加载且第一段音频完成
- **THEN** 转录结果在音频段结束后 5 秒内输出（Apple Silicon tiny 模型，含首段 overhead）
