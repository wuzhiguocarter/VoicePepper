## Why

VoicePepper 当前只有实时文本转录，没有“谁在什么时候说话”这一层信息，导致会议、访谈和多人讨论场景下的历史记录可读性和可检索性都很弱。既然项目已经决定长期采用 Apple 原生的 FluidAudio 路线，就需要先把一个可交付的第一版落地到现有产品中。

## What Changes

- 引入 `FluidAudio` Swift Package，并在录音会话结束后对完整 WAV 运行离线 speaker diarization
- 保留现有 `whisper.cpp` 实时转录链路，不在本次变更中替换实时 ASR 引擎
- 将每次录音的转录结果升级为结构化 transcript 元数据并保存为同名 `.json` 文件
- 历史录音列表支持检测和展示 speaker-attributed transcript，并在查看转录时显示 speaker 标签
- 增加最小可用的 speaker-attributed transcript 数据模型，为后续 speaker rename / identification 留出扩展位

## Capabilities

### New Capabilities
- `speaker-attributed-transcript`: 使用 FluidAudio 对录音会话执行离线 speaker diarization，并将带 speaker 标签的结构化 transcript 持久化到录音目录

### Modified Capabilities
- `recording-history`: 历史录音列表需要识别结构化 transcript 是否存在，并在预览中展示 speaker 标签文本
- `recording-persistence`: 录音持久化从“仅保存 WAV/纯文本”扩展为保存 WAV + speaker-attributed transcript JSON

## Impact

- **Dependencies**: `Package.swift` 新增 `FluidAudio`
- **Services**: 新增 diarization 服务，扩展 `RecordingFileService` 的保存/加载逻辑
- **Models**: 新增结构化 transcript / speaker segment 模型，并扩展 `RecordingItem`
- **UI**: `RecordingHistoryView` 的转录预览改为展示 speaker 标签文本
- **Storage**: `~/Library/Application Support/VoicePepper/Recordings/` 目录新增与录音同名的 `.json` transcript sidecar
