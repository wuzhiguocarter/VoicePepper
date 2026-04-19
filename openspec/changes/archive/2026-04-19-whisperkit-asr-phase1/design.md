## Context

当前音频链路在 `AppDelegate.setupAudioServices()` 中硬连线：

```
audioService.audioSegmentPublisher
  .sink { transcriptionSvc?.enqueue(segment) }  // 固定路由到 whisper.cpp
```

`AudioSegment`（16kHz mono Float32，VAD 分段）是唯一产物；`TranscriptionService` 消费它并推送到 `AppState.entries`。`WhisperKitASRService` 已实现 `transcribe(audioArray: [Float])` 接口，接收相同格式数据，但从未被调用。

Phase 1 的核心工程问题是：**在不破坏现有链路的前提下，让同一个 `AudioSegment` 在实验性模式下到达 WhisperKit，并把结果写回 AppState。**

## Goals / Non-Goals

**Goals:**
- 实验性模式下，麦克风 VAD 分段音频路由给 WhisperKitASRService
- WhisperKit 模型能在实验性模式激活时自动下载并缓存
- WhisperKit 转录结果以与现有 UI 兼容的方式写入 AppState.entries
- Preferences 页新增引擎模式选择器

**Non-Goals:**
- 不改变 AudioCaptureService 内部结构（保持其为纯音频采集层）
- 不引入 SpeakerKit 实时路径（Phase 2 任务）
- 不修改 AppState.entries 数据结构（保持向后兼容）
- 不处理 BLE 链路的实验性路由
- 不实现 WhisperKit 流式转录（用 batch 接口）

## Decisions

### Decision 1：路由在 AppDelegate，不在 AudioCaptureService

**选择**：在 AppDelegate 的 `audioSegmentPublisher` 订阅处根据 `appState.speechPipelineMode` 做分叉，而不是修改 `AudioCaptureService`。

**理由**：
- `AudioCaptureService` 是纯采集层，不应感知业务逻辑（pipeline 模式选择）
- `AppDelegate` 已是管道组装点，改动最小，风险最低
- 两种模式可以并行接收（旁路验证），也可以互斥（替换运行）
- Phase 1 选择**互斥模式**：实验性模式时仅路由给 WhisperKit，不同时喂给 whisper.cpp

```swift
// AppDelegate 改造后的路由逻辑（伪代码）
audioService.audioSegmentPublisher
    .sink { [weak self] segment in
        guard let self else { return }
        if appState.speechPipelineMode == .experimentalArgmaxOSS {
            Task { await self.experimentalWhisperKitService?.enqueue(segment) }
        } else {
            transcriptionSvc?.enqueue(segment)
        }
    }
```

### Decision 2：WhisperKitASRService 改为 lazy 加载 + 队列化

**选择**：在 `WhisperKitASRService` 内部维护串行 Task 队列，首次收到音频时触发模型下载/加载，后续段等待模型就绪后串行处理。

**理由**：
- 与现有 `TranscriptionService` 的串行队列模式一致（避免并发转录）
- 模型加载（最长约 5-10s）只发生一次，后续段无额外延迟
- `load: false, download: true` 配置让 WhisperKit 按需下载模型到系统缓存目录
- 不在 app 启动时阻塞主线程

### Decision 3：WhisperKit 输出兼容 AppState.entries

**选择**：将 `ASRTranscriptEvent` 映射为现有 `TranscriptionEntry` 写入 `AppState.entries`，不引入新的状态属性。

**理由**：
- `AppState.entries` 驱动 Popover UI（`TranscriptionListView`），无需改 UI 代码
- Phase 1 是验证阶段，不需要 speaker 标签，简单映射即可
- `TimelineMerger` 在 Phase 1 暂不接入（无 speaker events 需合并）；Phase 2 引入

映射规则：
```
ASRTranscriptEvent(text, startTimeSeconds) → TranscriptionEntry(text, timestamp=Date(timeInterval: startTimeSeconds, since: sessionStart))
```

### Decision 4：模型配置固定为 tiny，不暴露给用户选择

**选择**：Phase 1 硬编码 `WhisperKitConfig(model: "tiny")`，不在 UI 提供 WhisperKit 模型选择。

**理由**：
- tiny 模型下载小（约 150MB），验证速度快
- whisper.cpp 已有完整的模型选择 UI，Phase 1 不需要重复
- Phase 3（正式迁移）再统一模型管理

### Decision 5：Preferences 引擎选择器触发 AppState 变更，App 重启后生效

**选择**：引擎切换写入 `UserDefaults`，下次启动时生效；不支持运行时热切换。

**理由**：
- 热切换需要在录音中途停止当前引擎、重置状态，风险高
- 用户预期是"设置后下次录音生效"，符合常规 app 设置语义
- 实现简单：picker 绑定 `appState.speechPipelineMode`（已有 didSet → UserDefaults）

## Risks / Trade-offs

| 风险 | 缓解 |
|---|---|
| WhisperKit 模型下载失败（无网络） | 首次录音时显示加载状态文字；捕获错误后回退到 whisper.cpp，并在 UI 提示 |
| WhisperKit 首次加载耗时（首段音频可能丢失） | 第一段音频等待模型加载完成；实验阶段用户可接受 |
| ASRTranscriptEvent → TranscriptionEntry 映射时间偏差 | 使用会话开始时间 + startTimeSeconds 计算，误差在毫秒级，可接受 |
| 实验模式下 BLE 音频仍路由给 whisper.cpp | 明确 Non-Goal，Phase 1 只做麦克风链路；BLE 路由不变 |
| 引擎切换后旧的 AppState.entries 混入新引擎输出 | 切换引擎后在 UI 展示提示（"已切换引擎，下次录音生效"）；录音开始时 clearSession() |

## Migration Plan

1. 修改 `WhisperKitASRService`：添加内部串行队列和 `enqueue(_ segment: AudioSegment)` 方法
2. 修改 `AppDelegate.setupAudioServices()`：在 `audioSegmentPublisher` 订阅处添加路由分叉
3. 在 `AppDelegate` 中新增 `handleWhisperKitASREvent(_ event: ASRTranscriptEvent)` 将结果写入 `AppState.entries`
4. 修改 `PreferencesView`：新增 "语音引擎" Picker（绑定 `appState.speechPipelineMode`）
5. 手动测试验证：切到实验性模式 → 录音 → 确认 Popover 出现 WhisperKit 文字输出

回滚：将 `speechPipelineMode` 切回 `legacyWhisperCPP`，无代码回滚需要。

## Open Questions

- WhisperKit 的模型缓存目录是否与 whisper.cpp 的缓存目录隔离？（需实测，避免冲突）
- WhisperKit `tiny` 模型在实测下延迟是否可接受（目标 < 3s/段）？（Phase 1 验证指标之一）
