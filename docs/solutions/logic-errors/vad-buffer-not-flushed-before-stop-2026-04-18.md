---
title: VAD 缓冲区在录音停止时未刷新导致短录音丢失
date: 2026-04-18
category: logic-errors
module: AudioCaptureService
problem_type: logic_error
component: service_object
severity: high
symptoms:
  - 短录音（5秒以内）不产生 WAV 文件
  - recording_history_e2e_test.py 失败：3秒录音未生成文件
  - 较长录音（含明显停顿）正常保存，短录音必现问题
root_cause: async_timing
resolution_type: code_fix
tags:
  - vad
  - audio-capture
  - buffer-flush
  - recording-save
  - force-flush
---

# VAD 缓冲区在录音停止时未刷新导致短录音丢失

## Problem

`AudioCaptureService.stop()` 在结束录音时，`VADDetector.speechBuffer` 中未完成的语音段被 `vadDetector.reset()` 直接丢弃，导致短时录音（< 5 秒、环境安静）无法触发 WAV 文件保存。

## Symptoms

- 录制 3 秒左右的短音频后，Recordings 目录中没有出现新文件
- `recording_history_e2e_test.py` 失败：3 秒录音未产生任何 WAV 文件
- 较长录音（说话后有明显停顿 > 500ms）正常保存，短录音必现问题
- App 日志中无 `[RecordingFileService] 已保存` 也无 `保存失败` 输出

## What Didn't Work

调查时发现 `stop()` 中有一段 `ringBuffer.drainAll()` 逻辑，看似意图在停止时补救未保存的样本。但 `processTapBuffer` 中从未向 `ringBuffer` 写入任何数据，所以 `drainAll()` 始终返回空数组，该路径对问题毫无帮助。

## Solution

在 `stop()` 中，于收集 `sessionSamples` 之前，调用 `vadDetector.forceFlush()`，强制将 VAD 内部 `speechBuffer` 中已积累但尚未触发 `onSegmentComplete` 的语音段立即输出。

**Before:**

```swift
func stop() {
    engine.inputNode.removeTap(onBus: 0)
    engine.stop()

    let remaining = ringBuffer.drainAll() // 永远为空，无效
    if !remaining.isEmpty {
        sessionSamples.append(contentsOf: remaining)
    }

    let completedSession = sessionSamples
    if !completedSession.isEmpty {
        sessionEndPublisher.send(completedSession)
    }
    sessionSamples.removeAll()

    vadDetector.reset() // ← BUG：直接丢弃 speechBuffer 中的语音
    ringBuffer.reset()
}
```

**After:**

```swift
func stop() {
    engine.inputNode.removeTap(onBus: 0)
    engine.stop()

    // 先强制刷新 VAD 中尚未完成的语音段，确保短时录音也能保存
    vadDetector.forceFlush()

    let remaining = ringBuffer.drainAll()
    if !remaining.isEmpty {
        sessionSamples.append(contentsOf: remaining)
    }

    let completedSession = sessionSamples
    if !completedSession.isEmpty {
        sessionEndPublisher.send(completedSession)
    }
    sessionSamples.removeAll()

    vadDetector.reset()
    ringBuffer.reset()
}
```

## Why This Works

VAD 的静音检测机制需要在语音结束后积累约 500ms（`silenceThresholdMs`）的静音才会触发 `onSegmentComplete` 回调，该回调负责将语音样本追加到 `sessionSamples`。短时录音在用户停止前这个静音窗口尚未到达，VAD 的 `speechBuffer` 中有数据但回调从未触发，`sessionSamples` 为空，`sessionEndPublisher` 不发送，最终没有 WAV 写入。

`forceFlush()` 绕过静音等待，直接调用 `flushSegment()` 触发 `onSegmentComplete` 回调，使已积累的语音样本在 `stop()` 收集数据之前完成追加。

关键调用链：`forceFlush()` → `flushSegment()` → `onSegmentComplete?(segment)` → `sessionSamples.append(contentsOf:)`

## Prevention

1. **flush-before-reset 契约**：任何流式处理组件（VAD、编码器、缓冲区）若持有内部状态，其 `stop()` / `teardown()` 流程必须在清理前显式刷新，而非直接 reset
2. **短时录音 E2E 测试**：测试套件应覆盖 < 5 秒的短时录音场景，确保 VAD 静音窗口未触发时系统依然能正确保存文件
3. **审查死代码**：`ringBuffer` 在 `processTapBuffer` 中从未被写入，应在后续修复中删除或补全其写入逻辑，避免误导维护者

## Related Issues

- `docs/solutions/integration-issues/avfoundation-wav-vs-m4a-writing.md` — 症状相似（录音后无有效 WAV 文件），但根因不同（AVAudioFile 格式不匹配 vs VAD 缓冲未刷新）
