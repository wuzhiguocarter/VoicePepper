## Why

Phase 1 完成了 WhisperKit 实时 ASR 接入，实验性模式下已能产出转录文字，但 `SpeakerKitDiarizationService` 和 `TimelineMerger` 仍是孤岛——Popover 只展示纯文本，无说话人标签，持久化也仍依赖 FluidAudio 后处理。Phase 2 将激活这两个组件，实现"边说边出字，同时显示匿名说话人标签"的体验目标。

## What Changes

- **SpeakerKit 接入实时路径**：实验性模式下，麦克风音频并行喂给 `SpeakerKitDiarizationService`，产出 `SpeakerSegmentEvent`
- **TimelineMerger 激活**：`ASRTranscriptEvent` + `SpeakerSegmentEvent` 同时输入 `TimelineMerger`，产出 `RealtimeTranscriptChunk`（含 speakerLabel）
- **AppState 扩展**：新增 `realtimeChunks: [RealtimeTranscriptChunk]`，实验性模式下 UI 数据源切换到此属性
- **Popover UI 改造**：实验性模式下展示带 `[S1]`/`[S2]` badge 的 chunk，默认模式 UI 不变
- **持久化适配**：实验性模式下会话结束时用 `TimelineMerger.snapshot()` 产出的统一 timeline 落盘，替代 FluidAudio 后处理作为 JSON 主来源

## Capabilities

### New Capabilities

（无新 capability，均为已有 capability 的行为扩展）

### Modified Capabilities

- `realtime-speech-pipeline`：新增 SpeakerKit 并行实时路径、TimelineMerger 激活、AppState.realtimeChunks 数据源
- `widget-display`：实验性模式下 Popover 展示带说话人 badge 的 RealtimeTranscriptChunk
- `speaker-attributed-transcript`：实验性模式下持久化来源从 FluidAudio 切换为 TimelineMerger 统一 timeline

## Impact

- `Sources/VoicePepper/Services/SpeakerKitDiarizationService.swift`（改造：启用 download/load，添加 enqueue 接口）
- `Sources/VoicePepper/Services/TimelineMerger.swift`（已存在，无需修改）
- `Sources/VoicePepper/Models/AppState.swift`（新增 realtimeChunks 属性）
- `Sources/VoicePepper/App/AppDelegate.swift`（接通 SpeakerKit + TimelineMerger，改造 session 结束持久化）
- `Sources/VoicePepper/UI/PopoverView.swift`（实验性模式下展示 speaker chunk）
- `Sources/VoicePepper/Models/SpeakerAttributedTranscript.swift`（可能需要扩展以承接 TimelineMerger 输出）
