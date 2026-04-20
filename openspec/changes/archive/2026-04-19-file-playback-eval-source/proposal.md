## Why

VoicePepper 的语音识别和说话人分离效果目前只能通过真实录音手动验证，无法在 CI/脚本中做可重复的定量评估（WER/DER）。需要一条旁路通道，能够将本地 WAV 文件注入到现有管道，从而支持自动化回归测试。

## What Changes

- 新增 `AudioFileSource` 服务：读取本地 16kHz 单声道 WAV，按固定时长分块推出 `AudioSegment`，行为与麦克风 VAD 分段等价
- `RecordingSource` 枚举新增 `.filePlayback` case（仅开发模式可用，不暴露到正式 UI）
- `AppDelegate` 增加 `filePlayback` 音频路由分支，复用 WhisperKit + SpeakerKit + TimelineMerger 链路
- 新增评估脚本 `tests/file_playback_eval.py`：传入 WAV 路径 + 参考文本，输出 WER 指标

## Capabilities

### New Capabilities
- `file-playback-source`: 读取 WAV 文件并将 PCM 分块注入音频管道，仅供开发测试使用

### Modified Capabilities
- `audio-capture`: 音频捕获层新增 filePlayback 路由分支（`RecordingSource` 枚举扩展）
- `recording-source-switch`: `RecordingSource` 枚举增加 `filePlayback` case，路由逻辑相应扩展

## Impact

- 新文件：`Sources/VoicePepper/Services/AudioFileSource.swift`
- 修改文件：`Sources/VoicePepper/Models/AppState.swift`（`RecordingSource` 枚举）、`Sources/VoicePepper/App/AppDelegate.swift`（路由分支）
- 新增测试脚本：`tests/file_playback_eval.py`
- 无外部依赖新增（使用系统 `AVAudioFile` 读取 WAV）
- 不影响现有麦克风/BLE 路径，不修改 UI 选择器
