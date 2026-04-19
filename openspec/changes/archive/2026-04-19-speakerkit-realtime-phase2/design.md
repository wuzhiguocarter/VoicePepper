## Context

Phase 1 建立了实验性模式下的 WhisperKit 单引擎链路：音频 → WhisperKitASRService → ASRTranscriptEvent → handleWhisperKitASREvent → AppState.entries → Popover 纯文本列表。

`SpeakerKitDiarizationService`（`download:false, load:false`）和 `TimelineMerger` 均已存在于代码库但完全未激活。`RealtimeTranscriptChunk` 数据模型已定义，包含 `speakerLabel?` 字段。

Phase 2 的核心工作是在不改变默认模式任何行为的前提下，将这两个组件接入实验性模式的数据流。

## Goals / Non-Goals

**Goals:**
- SpeakerKit 与 WhisperKit 并行运行，各自处理同一段音频
- TimelineMerger 将两路事件合并为 `RealtimeTranscriptChunk`
- AppState 新增 `realtimeChunks` 作为实验性模式 UI 数据源
- Popover 在实验性模式下展示带说话人 badge 的 chunk
- 实验性模式下会话结束持久化使用 TimelineMerger 输出

**Non-Goals:**
- 不做跨会话 speaker identification
- 不改动 BLE 链路
- 不改动默认 whisper.cpp 模式任何路径

## Decisions

### 决策 1：SpeakerKit 启用 `download:true, load:true`

SpeakerKit Pyannote 模型约 100-200MB，首次使用需从 `argmaxinc/speakerkit-coreml` 下载。与 WhisperKit 处理方式一致，改为 `download:true, load:true`，在 `prepareIfNeeded()` 中懒加载。SpeakerKit 初始化失败只 NSLog，不阻断 ASR 路径。

### 决策 2：SpeakerKit 与 WhisperKit 并行，各自串行

音频段同时提交给两个 actor 的 `enqueue`，两者内部各自维护串行任务队列（现有 WhisperKit 模式），互不阻塞。SpeakerKit 处理完成后调用 `handleSpeakerKitEvent`，与 ASR 事件在 AppDelegate 汇聚后喂给 TimelineMerger。

**替代方案**：先等 ASR 完成再做 diarization（串行）→ 延迟过高，放弃。

### 决策 3：TimelineMerger 由 AppDelegate 持有并协调

`TimelineMerger` 已在 AppDelegate 中声明为 `private var timelineMerger: TimelineMerger?`，Phase 2 直接激活。两路事件（`applyASREvent` / `applySpeakerEvent`）都在 `Task { @MainActor }` 中调用，结果更新 `appState.realtimeChunks`。

### 决策 4：AppState 新增 `realtimeChunks`，保留 `entries`

`entries` 继续作为默认模式数据源，不删除。实验性模式下 `appendEntry` 改为同时追加到 `entries`（向后兼容）和更新 `realtimeChunks`（由 TimelineMerger 驱动）。

实际上 WhisperKit 路径不再直接调用 `appendEntry`——改为调用 `updateRealtimeChunks(_ chunks: [RealtimeTranscriptChunk])`，PopoverView 根据 `speechPipelineMode` 选择数据源。

### 决策 5：SpeakerKit 添加 `enqueue` 接口

与 WhisperKitASRService 保持对称设计，`SpeakerKitDiarizationService` 新增：
```swift
func enqueue(_ segment: AudioSegment, sessionTime: Double)
func setCallback(_ cb: @Sendable ([SpeakerSegmentEvent]) -> Void)
```
AppDelegate 注入 callback，diarization 完成后通知 TimelineMerger。

### 决策 6：持久化使用 TimelineMerger.snapshot()

实验性模式下 session 结束时，从 TimelineMerger 取 snapshot，构造 `SpeakerAttributedTranscriptDocument` 后落盘。默认模式仍走 FluidAudio 离线后处理，两条持久化路径共存。

## Risks / Trade-offs

- **SpeakerKit 首次下载时长**：Pyannote 模型约 100-200MB，首次进入实验性模式录音可能等待较长。缓解：只在 `experimentalArgmaxOSS` 模式下初始化，失败不崩溃。
- **speaker label 稳定性**：chunk 级归属而非字级，短片段可能出现 speaker 跳变。Phase 2 不追求精度，只保证不崩溃、标签有意义。
- **TimelineMerger ASR/speaker 时钟对齐**：当前 ASRTranscriptEvent 时间戳来自 WhisperKit 推理结果，SpeakerSegmentEvent 来自 Pyannote 推理，均基于音频段内相对时间，不一定对齐到同一会话时钟。TimelineMerger 的 `bestSpeakerEvent` 已有 overlap + closest 两种降级策略，Phase 2 接受此近似。
- **Popover 数据源切换**：PopoverView 需根据 `appState.speechPipelineMode` 选择不同渲染路径，增加一定 UI 复杂度。通过 `@ViewBuilder` 分支保持清晰。
