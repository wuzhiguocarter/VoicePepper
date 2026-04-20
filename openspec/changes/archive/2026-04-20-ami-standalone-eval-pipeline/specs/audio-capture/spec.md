## MODIFIED Requirements

### Requirement: pipeline 服务提取为共享 library

系统 SHALL 将以下文件从 `Sources/VoicePepper/` 移动到 `Sources/VoicePepperCore/`，并在 `Package.swift` 中注册为 library target：

- `Services/WhisperKitASRService.swift`
- `Services/SpeakerKitDiarizationService.swift`
- `Services/TimelineMerger.swift`
- `Services/AudioFileSource.swift`
- `Services/SpeakerAttributedTranscript.swift`
- `Models/RealtimeSpeechPipeline.swift`

`RecordingSource` 和 `SpeechPipelineMode` 枚举从 `Models/AppState.swift` 提取到 `Sources/VoicePepperCore/PipelineTypes.swift`。

#### Scenario: 提取后 App target 功能不变
- **WHEN** 完成文件移动并更新 Package.swift
- **THEN** `VoicePepper` App target 添加 `VoicePepperCore` 依赖后编译通过，AppState.swift 添加 `import VoicePepperCore`

#### Scenario: CLI target 复用 pipeline
- **WHEN** `VoicePepperEval` target 声明 `dependencies: ["VoicePepperCore"]`
- **THEN** 可在 main.swift 中直接实例化 WhisperKitASRService, SpeakerKitDiarizationService, TimelineMerger, AudioFileSource
