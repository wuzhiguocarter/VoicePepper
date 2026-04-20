## Context

VoicePepper 的音频管道以 `AudioSegment`（16kHz mono float32 块）为统一接口，`AudioCaptureService` 负责麦克风采集和 VAD 分段。`AppDelegate` 订阅 `audioSegmentPublisher` 并按 `RecordingSource` 路由到 `WhisperKitASRService`（实验性模式）或 `TranscriptionService`（默认模式）。

## Goals / Non-Goals

**Goals:**
- 新增 `AudioFileSource`，读取本地 WAV 文件，产出与麦克风等价的 `AudioSegment` 流
- `RecordingSource` 新增 `.filePlayback` case，AppDelegate 增加对应路由分支
- 复用现有 WhisperKit → TimelineMerger → `realtimeChunks` 链路，无需额外适配
- 提供 `tests/file_playback_eval.py` 计算 WER，用于 AISHELL-1 等数据集的可重复评估

**Non-Goals:**
- 不在 UI 选择器中暴露 filePlayback（仅开发内部使用）
- 不实现 DER 评估（仅 WER）
- 不支持非 16kHz WAV（调用方负责预处理）
- 不修改 BLE 路径

## Decisions

### 1. AudioFileSource 设计

```swift
final class AudioFileSource {
    let audioSegmentPublisher = PassthroughSubject<AudioSegment, Never>()
    let sessionEndPublisher   = PassthroughSubject<RecordingSessionData, Never>()

    func play(url: URL, chunkDuration: TimeInterval = 1.5) async
    func stop()
}
```

- 用 `AVAudioFile` 读取 WAV（系统原生，无依赖）
- 按 `chunkDuration`（默认 1.5s）分块，不做 VAD（模拟 VAD 已切好的 segment）
- 播放完成后自动发 `sessionEndPublisher`，触发持久化流程
- 使用 `Task.sleep` 控制时序，避免 CPU 爆满

### 2. RecordingSource 扩展

在 `AppState.RecordingSource` 枚举新增：
```swift
case filePlayback = "filePlayback"
```

`displayName` 返回 `"文件回放"` 但不加入 UI Picker（`allCases` 不包含它，或通过 `#if DEBUG` 控制）。

### 3. AppDelegate 路由

在 `setupServices()` 中，与 `audioCaptureService` 并列初始化 `audioFileSource`：

```swift
// filePlayback 分支（仅实验性模式 + filePlayback source 时激活）
audioFileSource.audioSegmentPublisher
    .sink { [weak self] segment in
        guard self?.appState.recordingSource == .filePlayback,
              self?.appState.speechPipelineMode == .experimentalArgmaxOSS,
              let wk = self?.experimentalWhisperKitService else { return }
        Task { await wk.enqueue(segment) }
        if let sk = self?.experimentalSpeakerKitService {
            Task { await sk.enqueue(segment) }
        }
    }
```

### 4. 评估脚本设计（tests/file_playback_eval.py）

```
用法: python3 tests/file_playback_eval.py --wav <path> --ref <text|txt_file>

流程:
  1. 启动 App（若未运行）
  2. 通过 AX API 切换 RecordingSource 到 filePlayback
  3. 触发 audioFileSource.play(url:)（通过 XPC 或写临时配置文件）
  4. 等待 sessionEnd（轮询 appState.realtimeChunks 停止增长）
  5. 计算 WER（jiwer 或手写 edit-distance）
  6. 输出 WER、转录文本对比表
```

**简化方案（阶段一）：** 不走 AX，直接在测试 target 里调用 `AudioFileSource.play` + `WhisperKitASRService`，不启动 App 进程。这样更稳定、无 AX 依赖。

## Risks / Trade-offs

- `filePlayback` source 的 `handleToggleRecording` 需要跳过权限检查（麦克风权限对文件回放不适用）
- WAV 必须是 16kHz mono float32；非标格式需调用方用 `ffmpeg` 预转换
- 阶段一评估脚本不走完整 App UI 路径（可能遗漏 UI 层 Bug），但已覆盖核心 ASR 链路
