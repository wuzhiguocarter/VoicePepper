## Context

VoicePepper 现在的转录架构是：

- `AudioCaptureService` / `BLERecorderService` 输出 16kHz mono `AudioSegment`
- `TranscriptionService` 使用 `WhisperContext` 对每个 segment 进行串行实时转录
- `AppState.entries` 暂存每条实时转录文本
- `RecordingFileService` 在会话结束后保存整段 WAV，并配对保存纯文本 `.txt`

这个架构非常适合“低延迟实时文本”，但不适合直接做 speaker attribution，因为 diarization 更依赖整段音频的全局上下文和说话人聚类结果。与此同时，项目已经确定 Apple 原生的长期技术路线应优先采用 `FluidAudio`，因此本次实现选择先将 FluidAudio 作为“录音后 speaker pipeline”接入，而不是一次性替换当前 whisper.cpp ASR 主链。

## Goals / Non-Goals

**Goals:**
- 在 macOS 原生 Swift 代码栈中引入 `FluidAudio`
- 录音会话结束后，对完整录音 WAV 运行离线 speaker diarization
- 把现有纯文本转录升级为结构化 transcript sidecar（JSON）
- 历史录音界面能够读取并展示带 speaker 标签的转录内容
- 为未来的 speaker rename / speaker identification 预留数据结构

**Non-Goals:**
- 不在本次变更中替换现有 `whisper.cpp` 实时转录
- 不在本次变更中实现自动 speaker identification
- 不实现实时“当前说话人是谁”的前台 UI
- 不做全文搜索、说话人统计或手动编辑 transcript

## Decisions

### 1. 推理路径：保留 whisper.cpp 实时 ASR，新增 FluidAudio 离线 diarization

**选择：** 实时转录仍由 `whisper.cpp` 提供；录音结束后，使用 `FluidAudio` 对完整 WAV 做离线 diarization。

**理由：**
- 当前实时转录已经稳定工作，替换 ASR 风险高
- 离线 diarization 更符合该类模型的上下文需求
- 可以先把产品的数据模型和存储格式升级起来，不被 ASR 迁移阻塞

**备选：** 直接用 FluidAudio 替换全部 ASR + diarization  
**不选原因：** 改动面过大，验证成本高，不适合作为第一版切入

### 2. 结构化 transcript 存储格式：与录音同名的 `.json` sidecar

**选择：** 每次会话除了 `.wav` 和现有 `.txt`，再写一个同名 `.json` 文件。

示例：
- `Recording_20260419_193000.wav`
- `Recording_20260419_193000.txt`
- `Recording_20260419_193000.json`

**理由：**
- 便于 Finder 中直接定位和迁移
- 不引入数据库
- 足以承载 speaker segments、未来 speaker profile ID、置信度等结构化字段

### 3. Speaker-attributed transcript 模型：以现有 `TranscriptionEntry` 为输入，附加 diarization 输出

**选择：** 新增独立的持久化模型，而不是立刻重构 `AppState.entries`。

建议结构：

```text
TranscriptDocument
- schemaVersion
- createdAt
- fullText
- chunks[]

TranscriptChunk
- id
- startTimeSeconds?
- endTimeSeconds?
- timestamp
- text
- speakerLabel?
- speakerProfileID?
```

**理由：**
- 不强迫实时 UI 立即切换数据源
- 与当前 `AppState.entries` 兼容
- 未来可以逐步将前台 UI 迁移到结构化 transcript

### 4. Speaker 标签回填策略：按时间顺序将实时文本条目映射到 diarization segments

**选择：** 第一版采用启发式回填：基于每条 `TranscriptionEntry.timestamp` 在会话中的相对时间位置，将其分配给覆盖该时间点的 diarization segment。

**理由：**
- 当前 `TranscriptionEntry` 没有精确的 start/end 时间，只有 `timestamp`
- 这能在不重构实时转录链路的前提下得到可用结果
- 先解决 80% 的历史阅读问题，后续再引入更精确的 word/segment alignment

**备选：** 立即引入逐词时间戳和精确对齐  
**不选原因：** 会拉大当前变更范围

### 5. UI 呈现：历史录音优先展示 speaker-attributed 文本，缺失时回退纯文本

**选择：** `RecordingHistoryView` 中“查看转录”优先读取 JSON 中的格式化 speaker 文本；若 JSON 不存在，则继续使用现有 `.txt`。

**理由：**
- 向后兼容旧录音
- 不破坏当前历史记录交互
- 让新老数据可以共存

## Risks / Trade-offs

- **[模型下载首次延迟]** 初次运行 diarization 需要下载并编译 FluidAudio 模型 → 在后台执行，并在失败时保留 `.txt` 结果作为回退
- **[speaker 回填不够精确]** 当前基于条目时间戳回填 speaker，可能与真实句边界有偏差 → 接受第一版误差，后续再引入更精细时间轴
- **[存储格式并存]** 同时维护 `.txt` 和 `.json` 会增加一点复杂度 → `.txt` 继续服务旧 UI/可读性，`.json` 负责结构化数据
- **[依赖体积上升]** 引入 `FluidAudio` 增加编译和模型管理复杂度 → 只把它用于录音后处理，不影响录音中的前台延迟

## Migration Plan

1. 新增 `FluidAudio` 依赖和 diarization 服务封装
2. 扩展 `RecordingFileService`，支持 speaker-attributed transcript JSON 的保存、加载与删除
3. 在 `AppDelegate` 的录音会话结束回调中触发 diarization 并回填 transcript
4. 历史录音界面优先读取 speaker-attributed transcript
5. 通过 `swift build` 和现有 E2E 回归验证现有录音/转录链路未被破坏

如果 `FluidAudio` 模型准备或 diarization 失败：

- WAV 仍然保存
- `.txt` 仍然保存
- `.json` 可缺失
- UI 继续回退到纯文本显示

## Open Questions

- 第一版是否需要在历史录音列表中显示“已分离 speaker”的视觉标记，而不仅是文本预览时显示
- 后续 speaker rename / identification 是写回同一 `.json`，还是拆分出独立 profile 存储
