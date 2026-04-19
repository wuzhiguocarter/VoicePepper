## Why

Phase 0 建立了 WhisperKit + SpeakerKit 基础设施骨架（服务、数据模型、TimelineMerger），但所有组件仍是孤岛——没有音频流进入、模型不加载、UI 不感知。Phase 1 的目标是接通这条链路：让实验性模式下的麦克风录音真正经由 WhisperKit 产出实时文字，验证新栈在 Apple Silicon 上的可行性，为后续全面迁移积累数据。

## What Changes

- **WhisperKitASRService 模型加载**：从 `load:false/download:false` 改为支持在线下载并缓存 WhisperKit 模型（tiny 优先），在实验性模式激活时完成预热
- **音频路由分叉**：`AudioCaptureService` 在 `SpeechPipelineMode.experimentalArgmaxOSS` 时将 VAD 分段后的音频同时（或替代）发往 `WhisperKitASRService`，而不仅走 `TranscriptionService`（whisper.cpp）
- **事件下游接通**：`WhisperKitASRService` 输出的 `ASRTranscriptEvent` 经 `TimelineMerger` 合并后更新 `AppState`，驱动 Popover 实时文字
- **Preferences 引擎选择器**：在设置页新增"语音引擎"Picker，允许用户在 `legacyWhisperCPP` 和 `experimentalArgmaxOSS` 之间切换
- **旁路保留**：whisper.cpp + FluidAudio 默认路径完全不变；BLE 链路暂不要求支持新栈；SpeakerKit 不接入实时路径

## Capabilities

### New Capabilities

（无新增 capability——Phase 1 均为对现有 capability 的行为升级）

### Modified Capabilities

- `realtime-speech-pipeline`：新增"模型加载与预热"、"实验性模式端到端音频路由"、"TimelineMerger 驱动 AppState"三个运行时行为要求；新增"引擎模式配置 UI"要求
- `whisper-transcription`：将"实验性新栈可编译接入"升级为"实验性 WhisperKit 可作为运行时可选 ASR 引擎"——行为从"能编译"变为"能产生真实文字输出"
- `audio-capture`：新增"pipeline 感知音频路由"要求——在实验性模式下，音频帧同时路由给 WhisperKit 适配层

## Impact

- **修改**：`WhisperKitASRService`（加载逻辑）、`AudioCaptureService`（路由分叉）、`AppDelegate`（预热时机）、`PreferencesView`（引擎选择器）
- **修改**：`AppState`（新增 WhisperKit 输出的 transcript chunks 状态，或复用 entries）
- **依赖变化**：`argmax-oss-swift` 从"可编译"升级为"运行时依赖，需网络下载模型"
- **不变**：`TranscriptionService`、`WhisperContext`、`FluidAudioDiarizationService`、BLE 链路、历史存储格式
