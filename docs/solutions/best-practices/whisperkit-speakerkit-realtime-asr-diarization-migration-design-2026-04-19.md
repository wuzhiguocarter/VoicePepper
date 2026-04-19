---
title: "WhisperKit + SpeakerKit 实时 ASR 与说话人分离改造方案设计"
date: 2026-04-19
category: best-practices
module: transcription
problem_type: architecture_decision
component: speaker-attribution
severity: high
applies_when:
  - 计划将 VoicePepper 从 whisper.cpp 逐步迁移到 Apple Silicon 端侧统一语音栈
  - 希望同时获得实时 ASR 与实时 Speaker Diarization
  - 需要在 macOS 原生 Swift 应用中保持本地离线处理
related_components:
  - AudioCaptureService
  - BLERecorderService
  - TranscriptionService
  - WhisperContext
  - AppState
  - RecordingFileService
tags:
  - whisperkit
  - speakerkit
  - realtime-asr
  - speaker-diarization
  - apple-silicon
  - migration
  - architecture
  - macos
---
# WhisperKit + SpeakerKit 实时 ASR 与说话人分离改造方案设计

## Context

VoicePepper 当前链路是：

```text
Mic / BLE audio
  -> VAD 分段
  -> whisper.cpp 串行转录
  -> AppState.entries 追加纯文本
  -> session end 保存 wav + txt + json
```

这条链路已经能稳定完成：

- 本地实时转录
- 会话结束后的结构化 transcript 保存
- 基于 `FluidAudio` 的离线 diarization 后处理

但它仍有三个结构性限制：

1. **ASR 与 diarization 是两条分离链路**
2. **speaker attribution 主要发生在会话结束后，不是实时体验**
3. **长期目标栈不统一**，`whisper.cpp`、`FluidAudio`、未来 identification 方案仍是拼接式组合

如果 VoicePepper 决定向 Apple Silicon 端侧统一栈演进，那么更合理的长期目标是：

```text
音频输入
  -> WhisperKit 实时 ASR
  -> SpeakerKit 实时 / 准实时 diarization
  -> 统一 transcript timeline
  -> 历史持久化与后续 identification
```

## 设计目标

本次改造方案要解决的不是“把库换掉”，而是把 VoicePepper 的语音主链从“ASR 优先 + speaker 后补”演进成“统一 timeline 驱动”的实时语音系统。

目标如下：

- 用 `WhisperKit` 替代 `whisper.cpp` 作为长期实时 ASR 引擎
- 用 `SpeakerKit` 提供实时或准实时 speaker diarization
- 在 UI 中支持“边说边出字，边出匿名 speaker 标签”
- 保留会话结束后的结构化落盘与历史回放能力
- 为未来 speaker identification 预留 profile / enrollment 接口
- 在迁移过程中不一次性推翻现有链路，允许双栈并行验证

## 非目标

这份方案**不直接解决**下面几件事：

- 不把 `SpeakerKit` 直接当成完整 speaker identification 方案
- 不在第一阶段支持跨会话自动识别人名
- 不要求 BLE 音频和麦克风音频一开始就完全统一时钟校准与混音
- 不要求首个版本就达到最终实时 speaker 标签精度

## 目标架构

### 目标形态

```text
Audio Source
 ├─ MicCapture
 └─ BLECapture
      ↓
 AudioFrameStream
      ↓
 Realtime Speech Pipeline
 ├─ WhisperKit ASR Engine
 │   └─ partial / final transcript events
 ├─ SpeakerKit Diarization Engine
 │   └─ speaker segment events
 └─ Timeline Merger
      └─ unified transcript chunks
            ↓
 AppState / UI
      ↓
 Recording Persistence
 ├─ wav
 ├─ txt
 └─ json (chunks + speaker segments + metadata)
```

### 关键思想：统一 Timeline，而不是“先文字、后 speaker”

新的核心抽象不应再是当前的 `TranscriptionEntry(text, timestamp, duration)`，而应变成：

```text
RealtimeTranscriptChunk
- id
- startTimeSeconds
- endTimeSeconds
- text
- isFinal
- speakerLabel?
- speakerConfidence?
- source
```

也就是说：

- `WhisperKit` 负责不断产出文本片段
- `SpeakerKit` 负责不断产出说话人片段
- 中间用一个 `Timeline Merger` 把两者合并成 UI 和存储都能用的统一 chunk

这一步是整个改造的真正核心。

## 组件设计

### 1. AudioFrameStream

新增统一音频输入层，替代“VAD 分段直接喂给转录”的思路。

职责：

- 把麦克风和 BLE 音频都规范化成统一格式
- 统一输出 `16kHz / mono / Float32` frame
- 每个 frame 附带相对会话时间戳

建议抽象：

```swift
struct AudioFrame: Sendable {
    let samples: [Float]
    let startTimeSeconds: Double
    let endTimeSeconds: Double
    let source: RecordingSource
}
```

建议新增：

- `RealtimeAudioBus`
- `AudioFrameClock`
- `AudioFrameRingBuffer`

这里的关键变化是：**VAD 不再是主驱动器，只是辅助信息**。
实时 ASR 和实时 diarization 都应该围绕连续 frame stream 工作。

### 2. WhisperKitASRService

新增 `WhisperKitASRService`，作为新的实时转录引擎适配层。

职责：

- 初始化模型和运行时
- 接收连续音频 frame
- 输出 partial / final transcript event
- 把底层库事件转换成应用自己的统一事件模型

建议事件模型：

```swift
struct ASRTranscriptEvent: Sendable {
    let id: UUID
    let startTimeSeconds: Double
    let endTimeSeconds: Double
    let text: String
    let isFinal: Bool
}
```

不要把 WhisperKit 直接暴露给 UI。
应用层只依赖 `ASRTranscriptEvent`。

### 3. SpeakerKitDiarizationService

新增 `SpeakerKitDiarizationService`，作为实时或准实时 diarization 适配层。

职责：

- 接收连续音频 frame
- 输出匿名 speaker segment
- 在会话中维护稳定的 speaker label

建议事件模型：

```swift
struct SpeakerSegmentEvent: Sendable {
    let id: UUID
    let startTimeSeconds: Double
    let endTimeSeconds: Double
    let speakerLabel: String
    let confidence: Float?
}
```

第一阶段不要追求“字级别 speaker attribution”，只需要做到：

- chunk 级别 speaker 归属
- speaker label 在同一会话中尽量稳定

### 4. TimelineMerger

新增 `TimelineMerger`，把 ASR 和 diarization 统一成可展示、可持久化的数据结构。

职责：

- 接收 `ASRTranscriptEvent`
- 接收 `SpeakerSegmentEvent`
- 为 transcript chunk 分配最合适的 speaker
- 处理 partial -> final 替换
- 维护当前会话的结构化 transcript 状态

这里建议使用 actor：

```swift
actor TimelineMerger {
    func applyASREvent(_ event: ASRTranscriptEvent) -> [RealtimeTranscriptChunk]
    func applySpeakerEvent(_ event: SpeakerSegmentEvent) -> [RealtimeTranscriptChunk]
    func finalizeSession() -> SpeakerAttributedTranscriptDocument
}
```

### 5. SessionTranscriptStore

当前 `AppState.entries` 更适合纯文本列表，不适合承载实时 speaker timeline。

建议新增：

```text
SessionTranscriptStore
- chunks
- speakerSegments
- activeSpeakers
- currentPartialText
- currentRecordingState
```

UI 层直接订阅结构化状态，而不是自己拼接 speaker 标签。

## UI 改造建议

### 实时转录页

当前页只展示纯文本列表。改造后应展示：

- 文本
- speaker 标签
- partial / final 状态

建议 UI 表现：

- `S1` / `S2` 用轻量 badge 展示
- partial transcript 颜色更浅
- final transcript 固定落盘

示例：

```text
[S1] 大家下午好
[S2] 我先补充一下
[S1] 那我们开始
```

### 历史录音页

已有 `.json` sidecar 能继续复用，但数据来源变成实时统一 timeline。

建议增加：

- speaker 数量摘要
- 是否存在 speaker segment
- 后续可扩展“重命名 speaker”

## 数据模型调整

### 替换/扩展当前 `TranscriptionEntry`

建议保留旧模型用于兼容，但新增长期主模型：

```text
SpeakerAttributedTranscriptDocument
- schemaVersion
- createdAt
- fullText
- chunks
- diarizationSegments
- speakerCount
- engineMetadata
```

新增 `engineMetadata`：

```text
engineMetadata
- asrEngine: whisperkit
- diarizationEngine: speakerkit
- modelVersion
- deviceClass
- locale
```

这对后续排查模型差异和兼容迁移很重要。

### SpeakerProfile 预留

虽然第一阶段不做 identification，但模型要预留：

```text
SpeakerProfile
- id
- displayName
- embeddingRef?
- createdAt
- updatedAt
```

## 持久化设计

建议继续保持：

- `.wav`
- `.txt`
- `.json`

但 `.json` 的角色从“后处理产物”升级为“主事实记录”。

推荐：

- `.txt` 只是给 Finder / 快速阅读的降级视图
- `.json` 才是历史记录、speaker rename、未来 identification 的真实源数据

## 与现有实现的过渡策略

### Phase 0：双栈基线期

先不移除任何现有实现。

保留：

- `WhisperContext`
- `TranscriptionService`
- `FluidAudioDiarizationService`

新增：

- `WhisperKitASRService`
- `SpeakerKitDiarizationService`
- `TimelineMerger`

目标：

- 同一段录音可同时跑老链路与新链路
- 比较延迟、稳定性、文本质量、speaker 稳定性

### Phase 1：WhisperKit 替代实时 ASR

优先替换 ASR，而不是先替换历史存储。

目标：

- 让 UI 实时文本来自 `WhisperKit`
- 旧的 `.txt/.json` 持久化逻辑仍可继续使用
- `SpeakerKit` 可暂时只做旁路验证，不先驱动 UI


  Phase 1 真正需要做什么

  当前音频路径（活跃）：
  AudioCaptureService
    ─ VAD 分段 ──────────────→ TranscriptionService
                                      │
                                WhisperContext (whisper.cpp)
                                      │
                                AppState.entries → UI

  实验性路径（需接通）：
  AudioCaptureService
    ─ 音频帧 ───────────────→ WhisperKitASRService
                                      │
                                ASRTranscriptEvent
                                      │
                                TimelineMerger
                                      │
                              RealtimeTranscriptChunk → AppState → UI

### Phase 2：SpeakerKit 接入实时 speaker timeline

目标：

- UI 中实时显示匿名 speaker 标签
- `TimelineMerger` 成为会话内主事实源
- `.json` 落盘来自统一 timeline，而不是录音结束后再做回填

### Phase 3：移除 whisper.cpp 主路径

在满足以下条件后再做：

- WhisperKit 文本质量不低于当前主链
- 启动与推理延迟可接受
- BLE 输入链路稳定
- 历史记录和导出路径无回归

到这一步，`whisper.cpp` 才退为 fallback 或完全移除。

## 关键风险

### 1. BLE 实时流与新引擎的时钟对齐

当前 BLE 与麦克风输入虽然都能转成 16kHz mono，但时序语义未必已经为实时统一 timeline 准备好。

风险：

- chunk 时间漂移
- diarization segment 错位
- partial transcript 与 speaker label 错位

缓解：

- 引入统一 `AudioFrameClock`
- 所有事件都基于相对会话时间而不是 wall-clock `Date`

### 2. Partial transcript 抖动

实时 ASR 一定会有 partial 文本更新。

风险：

- UI 抖动
- speaker label 频繁跳变
- chunk 结构不稳定

缓解：

- partial 与 final 分层
- UI 只对 final chunk 持久化
- `TimelineMerger` 只在 final 时做稳定归档

### 3. SpeakerKit 实时标签稳定性

真实使用中，speaker label 最容易出问题的是“同一人被拆成多个 speaker”。

缓解：

- 第一阶段允许“准实时”而不是极致实时
- 优先保证稳定，再优化刷新频率

### 4. 模型分发与首次加载

`WhisperKit + SpeakerKit` 带来的另一个工程问题不是推理，而是模型获取、缓存、首次初始化和升级策略。

建议：

- 单独设计模型缓存目录
- 在设置页暴露模型状态
- 首次进入录音前做预热

## 验证指标

改造不是“能跑就行”，至少要比较这些指标：

- 首字延迟
- partial transcript 刷新稳定性
- final transcript 文本质量
- speaker segment 稳定性
- 长录音下内存占用
- 首次模型下载/初始化耗时
- BLE 与麦克风两条链路的一致性

## 推荐实施顺序

```text
1. 先引入 AudioFrameStream 和 TimelineMerger 抽象
2. 接入 WhisperKit，替换实时 ASR 主路径
3. 接入 SpeakerKit，先旁路跑 diarization
4. 再让 SpeakerKit 驱动 UI 中的实时 speaker 标签
5. 最后收敛历史存储、speaker rename、future identification
```

## 最终建议

对于 VoicePepper，这不是一个“立刻删除 whisper.cpp”的改造，而是一个**两阶段迁移**：

### 当前建议

- 继续保留已落地的 `whisper.cpp + FluidAudio`
- 先把结构化 transcript、timeline、speaker 数据模型沉淀好

### 长期建议

- 以 `WhisperKit + SpeakerKit` 作为 Apple Silicon 端侧统一栈的目标形态
- 用双栈验证方式逐步替换，而不是一次性切换

一句话总结：

**短期先把数据结构和实时事件模型做对，长期再把 ASR / diarization 引擎统一到 WhisperKit + SpeakerKit。**
