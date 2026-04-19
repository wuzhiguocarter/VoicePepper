---
title: "Speaker Diarization / Identification 选型决策：VoicePepper 短期采用 FluidAudio，长期优先评估 WhisperKit + SpeakerKit"
date: 2026-04-19
category: best-practices
module: transcription
problem_type: architecture_decision
component: speaker-attribution
severity: high
applies_when:
  - 为 VoicePepper 增加 Speaker Diarization（谁在什么时候说话）
  - 为 VoicePepper 增加 Speaker Identification（已知说话人识别）
  - 需要在 macOS 原生 Swift 应用中保持本地离线处理
  - 当前项目已基于 whisper.cpp 完成实时转录链路
related_components:
  - AudioCaptureService
  - BLERecorderService
  - TranscriptionService
  - WhisperContext
  - AppState
  - RecordingFileService
tags:
  - speaker-diarization
  - speaker-identification
  - whisperkit
  - speakerkit
  - fluidaudio
  - whisper-cpp
  - pyannote
  - sherpa-onnx
  - coreml
  - apple-silicon
  - architecture
  - macos
---

# Speaker Diarization / Identification 选型决策：VoicePepper 短期采用 FluidAudio，长期优先评估 WhisperKit + SpeakerKit

## Context

VoicePepper 当前已经具备一条稳定的本地实时转录链路：

```text
Mic / BLE audio
  -> VAD 分段
  -> AudioSegment(samples, capturedAt)
  -> TranscriptionService 串行 whisper.cpp 推理
  -> AppState.entries 追加纯文本
  -> session end 保存 WAV + txt
```

当前实现的几个关键特征：

- `AudioCaptureService` 和 `BLERecorderService` 都输出单声道 16kHz `AudioSegment`
- `TranscriptionService` 通过串行 `OperationQueue` 调用 `WhisperContext.transcribe()`
- `TranscriptionEntry` 目前只有 `text / timestamp / duration`
- `RecordingFileService` 在会话结束后保存整段 WAV，并配套保存纯文本 `.txt`

这条链路已经满足实时语音转录，但**没有 speaker 维度**，因此无法回答：

- 哪个时间段是谁在说话
- 当前说话人是否是一个已知人物
- 历史录音中同一个 speaker 是否能跨会话复用身份

为支持这些需求，需要引入：

1. **Speaker Diarization**：输出匿名 speaker 标签和时间段
2. **Speaker Identification**：基于已注册声纹或 embedding，将匿名标签映射为具体人名

## 要解决的不是“换模型”，而是补一条 Speaker Pipeline

现有 VoicePepper 以 ASR 为中心：

```text
音频 -> whisper.cpp -> 文本
```

增加 speaker 能力后，架构会变成：

```text
音频
 ├─ ASR pipeline
 │   └─ text
 └─ speaker pipeline
     ├─ diarization -> SPEAKER_00 / SPEAKER_01 + 时间段
     └─ identification -> speaker profile / voiceprint 匹配
```

这意味着选型标准不能只看某个项目“支不支持 diarization”，而要看它是否适合：

- macOS 原生 Swift 应用
- 本地离线处理
- Apple Silicon / CoreML / ANE 加速
- 与现有 `whisper.cpp` 链路共存或可渐进迁移
- 后续扩展到 speaker identification

## 候选方案对比

### 1. WhisperKit + SpeakerKit

**定位**：Apple Silicon 端侧实时 ASR + speaker diarization 组合，面向 iOS / macOS 本地离线推理。

**优点**

- Apple 平台栈一致性最强，适合作为统一端侧语音栈
- `WhisperKit` 对实时 ASR 的定位比当前 `whisper.cpp` 更接近长期目标
- `SpeakerKit` 与 `WhisperKit` 同属 Apple Silicon 端侧路线，协同关系清晰
- 完全本地、ANE 加速、高隐私，符合 VoicePepper 的产品定位

**缺点**

- 需要重新评估与现有 `whisper.cpp` 实时链路的替换成本
- 当前项目还没有围绕其完成真实工程落地与兼容性验证
- 它解决的是 ASR + diarization 的长期统一栈，不等于 speaker identification 已完整解决

**判断**

如果目标是 **Apple Silicon 端侧统一语音栈**，这是 VoicePepper 更优先的**长期主方案候选**。

### 2. FluidAudio

**定位**：Apple 平台原生音频推理库，Swift 集成，支持本地 ASR / diarization / VAD，并朝 speaker embedding / identification 方向扩展。

**优点**

- Swift Package 可直接集成，符合当前代码栈
- 明确面向 macOS / iOS / Apple Silicon
- CoreML / ANE 方向与 VoicePepper 产品定位一致
- speaker diarization 与 speaker identification 能在同一技术栈内演进
- 避免引入 Python / PyTorch 运行时和桌面分发负担

**缺点**

- 若直接替换现有 ASR，改动面较大
- 需要重新验证转录质量、延迟、模型下载和历史兼容策略

**判断**

这是 VoicePepper **当前最现实的增量落地方案**，尤其适合作为 diarization 后处理能力先接入产品。

### 3. pyannote-audio

**定位**：speaker diarization 学术和工程基准方案，适合做高质量离线 diarization 与 speaker embedding。

**优点**

- diarization 精度高
- 生态成熟，适合做 baseline
- 可以与 Whisper / WhisperX 组合使用

**缺点**

- Python / PyTorch 体系，分发成本高
- 对 Swift 原生桌面 App 不友好
- identification 需要自己再包装产品化流程

**判断**

适合做研究基线和离线验证，不适合作为 VoicePepper 的主集成方案。

### 4. whisper-diarization

**定位**：`Whisper + pyannote` 的快捷入口。

**优点**

- 上手快
- 可快速验证“Whisper + diarization”的可用性

**缺点**

- 本质仍依赖 Python 生态
- 不解决 identification
- 对现有 Swift 应用只是临时外挂，不是长期结构

**判断**

适合快速 POC，不适合正式选型。

### 5. sherpa-onnx

**定位**：全栈离线语音工具箱，覆盖 ASR / diarization / VAD / TTS 等能力。

**优点**

- 完全离线
- 多语言和多平台支持强
- 文档中包含 speaker diarization 和 speaker embedding 路径

**缺点**

- 对当前项目来说过于“另起一套栈”
- 若引入，通常意味着重构现有 ASR 主链
- 与当前基于 `whisper.cpp` 的集成思路不完全一致

**判断**

适合从零构建统一语音平台，不是 VoicePepper 当前阶段的最优路径。

### 6. 3D-Speaker

**定位**：更偏 speaker recognition / verification / diarization 的研究和工程框架。

**优点**

- identification / verification 能力完整
- 很适合研究 speaker profile / voiceprint 建档流程

**缺点**

- Python-heavy
- 不适合直接嵌入当前 Swift/macOS 主架构
- 引入成本高于其对当前产品的收益

**判断**

适合作为 speaker identification 方法参考，不适合作为 VoicePepper 主栈。

### 7. Meetily

**定位**：完整产品，不是底层能力库。

**优点**

- 可借鉴交互、工作流和会议产品能力组合

**缺点**

- 不是为嵌入 VoicePepper 而设计的依赖库

**判断**

适合产品参考，不适合作为核心技术选型。

## 最终决策

### 长期 Apple Silicon 主方案：WhisperKit + SpeakerKit

如果以 Apple Silicon 设备上的**端侧实时 ASR + diarization 统一栈**为目标，VoicePepper 的长期优先方向应调整为 **WhisperKit + SpeakerKit**。

原因不是某个项目更热门，而是它更符合本文前面列出的关键约束：

- **Apple 平台统一栈**：ASR 与 diarization 更接近同一体系内协同
- **本地离线**：符合项目核心卖点
- **Apple Silicon 路线**：ANE 加速与产品未来方向一致
- **长期方向更明确**：比“继续维持 `whisper.cpp + 单独 speaker pipeline`”更像最终形态

对于 VoicePepper 这种 Apple 原生、菜单栏、低延迟、本地隐私优先的应用，`WhisperKit + SpeakerKit` 的统一端侧方向，比单独把 `FluidAudio` 视为长期终局更合理。

### 当前工程落地方案：保留 whisper.cpp，先用 FluidAudio 增量演进

虽然长期路线调整为 `WhisperKit + SpeakerKit`，但当前不建议直接推翻已经稳定运行的 `whisper.cpp` 链路。

当前最稳妥的路径是：

```text
Phase 1
保留现有 whisper.cpp 实时转录
+ 使用 FluidAudio 增加会话结束后的 diarization 后处理
+ transcript 升级为结构化 speaker-attributed 结果

Phase 2
增加 speaker rename / speaker profile 存储

Phase 3
评估将 ASR + diarization 统一迁移到 WhisperKit + SpeakerKit

Phase 4
再为 speaker identification 单独补齐 enrollment / profile / embedding 方案
```

这样做的原因：

- 现有实时转录已经工作稳定，直接替换 ASR 风险高
- diarization 更适合基于整段音频的全局后处理
- 可以先升级数据模型和历史存储格式，不被推理引擎切换阻塞
- `FluidAudio` 已经更适合作为当前阶段的过渡实现，而不是必须被视为长期终局

### Speaker Identification 仍需单独决策

即使长期路线转向 `WhisperKit + SpeakerKit`，也不能把它等同于“speaker identification 已经解决”。

本文讨论的两个问题需要继续拆开看：

- `Speaker Diarization`：谁在什么时候说话
- `Speaker Identification`：把匿名 speaker 标签映射为具体人物

`WhisperKit + SpeakerKit` 更像是在 Apple Silicon 端侧把 **ASR + diarization** 的长期基础设施补齐；  
而 `speaker identification` 仍需要补充：

- speaker profile / enrollment
- embedding / voiceprint 存储
- 跨会话匹配与阈值策略
- 用户可编辑的人名映射

## 为什么不直接做“实时 speaker 标签”

当前链路的输入单位是 VAD 切出的 `AudioSegment`，这对实时转录足够，但对 diarization 并不理想。

speaker diarization 往往依赖更长的上下文来判断：

- 说话人切换点
- 多段 speech 的聚类归并
- 重叠语音处理
- 跨句子的身份稳定性

因此更合理的产品形态是：

```text
录音中
  -> 实时文本，先不强制标 speaker

录音结束后
  -> 对整段 WAV 做 diarization / identification
  -> 回填 speaker attribution
```

这既符合现有实现形态，也能减少前台 UI 抖动和错误 speaker label 带来的体验损害。

## 对数据模型的影响

当前 `TranscriptionEntry` 只适合纯文本转录，不足以承载 speaker 能力。

建议升级为类似结构：

```text
TranscriptChunk
- id
- startTime
- endTime
- text
- speakerLabel
- speakerProfileID?
- confidence?
- words?
```

同时新增：

```text
SpeakerProfile
- id
- displayName
- embedding / voiceprint
- createdAt
- source
```

历史存储也应从：

- `.wav`
- `.txt`

升级为：

- `.wav`
- `.json`（结构化 transcript / speakers / metadata）

否则后续无法稳定支持：

- speaker rename
- identification 回填
- 重跑 diarization
- 历史记录中的 speaker 统计和复用

## 分阶段落地建议

### Phase 1：Diarization MVP

目标：

- 保留现有 `whisper.cpp` 实时转录
- 会话结束后通过 `FluidAudio` 跑 speaker diarization
- 历史记录展示 `SPEAKER_00 / 01`

这一步不要求真正 identification。

### Phase 2：Speaker Rename 与 Profile 基础设施

目标：

- 允许用户将 `SPEAKER_00` 重命名为“我”“客户”“主持人”
- 将映射保存到结构化 transcript
- 为后续自动识别打下 profile 数据基础

### Phase 3：Speaker Identification

目标：

- 引入 speaker profile enrollment
- 允许从历史音频中为某人建立 voiceprint / embedding
- 在新录音中自动匹配已知 speaker

### Phase 4：统一迁移评估

当 speaker 能力被证明有持续价值后，再评估：

- 是否将 `whisper.cpp` ASR 迁移到 `WhisperKit`
- 是否将 diarization 统一迁移到 `SpeakerKit`
- 是否统一使用一个 Apple 平台本地推理栈
- 是否保留旧链路作为 fallback

## 不推荐的路线

### 不推荐直接把 pyannote / whisper-diarization 作为正式产品主方案

理由：

- 引入 Python / PyTorch 分发成本
- 破坏当前 Swift/macOS 本地产品的轻量性
- identification 仍需自行补齐

### 不推荐当前阶段直接切到 sherpa-onnx

理由：

- 现有 `whisper.cpp` 已经稳定工作
- 切换成本高于短期收益
- speaker 能力的关键瓶颈不在 ASR 引擎本身，而在数据模型和 speaker pipeline

## 参考资料

- VoicePepper 代码实现：
  - `Sources/VoicePepper/Services/AudioCaptureService.swift`
  - `Sources/VoicePepper/Services/TranscriptionService.swift`
  - `Sources/VoicePepper/Services/WhisperContext.swift`
  - `Sources/VoicePepper/Models/AppState.swift`
  - `Sources/VoicePepper/Services/RecordingFileService.swift`

- 外部资料：
  - WhisperKit / SpeakerKit（用户补充资料，Apple Silicon 端侧路线）
  - [FluidAudio](https://github.com/FluidInference/FluidAudio)
  - [pyannote-audio](https://github.com/pyannote/pyannote-audio)
  - [sherpa-onnx speaker diarization docs](https://k2-fsa.github.io/sherpa/onnx/speaker-diarization/index.html)
  - [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx)
  - [Meetily](https://github.com/Zackriya-Solutions/meetily)
  - [pyannoteAI features](https://docs.pyannote.ai/features)
  - [pyannoteAI voiceprint identification tutorial](https://docs.pyannote.ai/tutorials/identification-with-voiceprints)

## 结论摘要

对于 VoicePepper：

- **长期 Apple Silicon 主方案**：优先评估 `WhisperKit + SpeakerKit`
- **当前工程落地方案**：保留 `whisper.cpp`，先用 `FluidAudio` 做 diarization 后处理和结构化 transcript
- **Identification 边界**：不把 `SpeakerKit` 直接等同于 speaker ID 完整方案
- **演进顺序**：FluidAudio Diarization MVP → Rename/Profile → Identification → 再评估迁移到 `WhisperKit + SpeakerKit`

这条路径兼顾了：

- 当前代码资产复用
- 本地离线产品定位
- Apple 平台原生体验
- 长期统一端侧栈的可能性
- 后续 speaker identification 的可扩展性
