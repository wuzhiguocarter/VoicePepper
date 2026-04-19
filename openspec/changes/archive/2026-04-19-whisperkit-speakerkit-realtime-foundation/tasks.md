## 1. OpenSpec 与依赖接入

- [x] 1.1 为 WhisperKit / SpeakerKit foundation 变更补齐 proposal、design、tasks 与 delta specs
- [x] 1.2 在 `Package.swift` 中引入 `argmax-oss-swift` 并完成可编译接入

## 2. 实时语音统一数据模型

- [x] 2.1 新增 `AudioFrame`、`ASRTranscriptEvent`、`SpeakerSegmentEvent`、`RealtimeTranscriptChunk`
- [x] 2.2 新增 `TimelineMerger` actor，支持合并 ASR / speaker 事件
- [x] 2.3 为结构化 transcript 增加 `engineMetadata`

## 3. 实验性引擎适配层

- [x] 3.1 新增 `WhisperKitASRService`
- [x] 3.2 新增 `SpeakerKitDiarizationService`
- [x] 3.3 保持默认 `whisper.cpp + FluidAudio` 路径不变

## 4. 应用集成与配置

- [x] 4.1 为实验性新栈增加最小配置入口
- [x] 4.2 让应用能初始化新栈基础设施而不影响现有流程

## 5. 验证

- [x] 5.1 `swift build` 通过
- [x] 5.2 运行受影响的 E2E 测试并确认现有录音、转录、历史链路无回归
