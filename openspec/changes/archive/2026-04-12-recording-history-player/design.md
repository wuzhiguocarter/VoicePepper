## Context

VoicePepper 当前的录音流水线：麦克风 → PCM 采样 → VAD 分段 → Whisper 转录 → 文字输出。整个过程数据仅在内存中流动，录音结束后音频即被丢弃，用户无法复听或找到原始录音文件。

需要在不改变现有实时转录流程的前提下，旁路持久化音频数据，并提供历史列表 UI。

## Goals / Non-Goals

**Goals:**
- 每次完整录音自动保存为 M4A 文件（AAC 编码，16kHz 或 44.1kHz）
- 提供历史列表 UI，显示文件名、时长、录制时间
- 每条记录支持：在 Finder 中显示、App 内播放
- 支持删除历史录音（同时删除磁盘文件）

**Non-Goals:**
- 云端备份或跨设备同步
- 转码、导出为其他格式
- 录音内容搜索
- 超过简单列表的排序/过滤

## Decisions

### D1：保存格式选 M4A（AAC）而非 WAV
- WAV 无损但体积大（16kHz mono 约 1.9 MB/min），M4A（AAC 128kbps）约 1 MB/min
- `AVAssetWriter` + `AVAudioConverter` 可直接从 Float32 PCM 写出 M4A，无需额外依赖
- 系统播放器（`AVAudioPlayer`）原生支持 M4A 回放

### D2：存储路径使用 `~/Library/Application Support/VoicePepper/Recordings/`
- `FileManager.urls(for: .applicationSupportDirectory)` 是沙盒友好的标准路径
- 与 Preferences 等应用数据同目录，便于用户手动管理
- 文件名格式：`Recording_YYYYMMDD_HHmmss.m4a`

### D3：录音元数据用内存 + 扫描磁盘，不引入 CoreData
- 录音列表直接枚举目录文件，从文件名和文件属性读取元数据
- 减少复杂度，避免引入持久化存储层（YAGNI）
- 每次打开历史列表时刷新（文件数量预期不超过数百条，扫描开销可忽略）

### D4：录音保存时机——整个会话结束时写一个文件
- 同一次按钮启动到停止之间的所有 VAD 段，其 PCM 样本在内存中依次追加
- 点击停止（`stop()` 被调用）时，`RecordingFileService` 将累积的完整 PCM 一次性编码为一个 M4A 文件
- 避免产生多个碎片文件，一次录音对应一个文件，体验更直观
- `AudioCaptureService.stop()` 发出 `sessionEndPublisher` 信号，携带本次会话全部样本

### D5：播放使用 `AVAudioPlayer`（App 内），不依赖外部播放器
- 简单直接，无需打开 QuickTime 或其他 App
- 一次只允许一条录音播放，切换时停止前一条

## Risks / Trade-offs

- [长录音分段过多] → 每个 VAD 段保存一个文件，可能导致一次讲话产生多个碎片文件。缓解：可按时间合并同一"录音会话"（同一次按钮启动到停止之间）的所有 VAD 段到一个文件；本期优先实现简单版（每段一个文件），后续可优化合并逻辑
- [磁盘空间占用] → 不设自动清理，用户手动删除；可在未来版本加入"保留最近 N 天"策略
- [写盘耗时] → `AVAssetWriter` 写 M4A 为异步操作，不阻塞录音/转录主流程
- [并发安全] → 写盘在后台队列，读取历史列表在 Main Actor；通过 `RecordingFileService` actor 隔离保证线程安全

## Migration Plan

- 首次运行时自动创建目录（`FileManager.createDirectory`），无需迁移
- 无数据库 schema，无需 migration 步骤
- 回滚：删除新增文件即可，不影响现有功能
