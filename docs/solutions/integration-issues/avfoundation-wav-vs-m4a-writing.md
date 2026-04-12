---
title: "AVAudioFile 写盘格式：WAV PCM 优于 M4A AAC"
category: integration-issues
date: "2026-04-12"
module: audio
tags: [avfoundation, avaudiofile, recording, wav, m4a, pcm, encoding, macos]
problem_type: integration
severity: high
status: resolved
---

# AVAudioFile 写盘格式：WAV PCM 优于 M4A AAC

## 问题

使用 `AVAudioFile(forWriting:settings:)` 以 `kAudioFormatMPEG4AAC` 写 M4A 时，
录音后文件只有 **557 字节**（仅 MPEG-4 容器 header），无实际音频内容。
`AVAudioPlayer` 播放无声，时长显示 0:00，且 **不抛出任何 Swift Error**。

**错误码**：`com.apple.coreaudio.avfaudio error 560226676`

十六进制解析：`0x21646174` → ASCII `!dat`（= 数据格式错误）

## 根因

`AVAudioFile` 以 AAC 格式写文件时，其内部编码器要求输入 buffer 格式与
encoder 的 processing format 完全匹配。Float32 16kHz mono non-interleaved PCM
与 AAC encoder 期望的格式不匹配，编码器返回 `!dat` 错误。

**关键陷阱**：`AVAudioFile` 对此错误**静默处理**——只写了文件头（metadata），
未写入任何音频帧，但 API 不抛出异常，也不在返回值中体现失败。

## 修复

### 之前（❌ 失败）

```swift
let m4aSettings: [String: Any] = [
    AVFormatIDKey: kAudioFormatMPEG4AAC,
    AVSampleRateKey: 16000.0,
    AVNumberOfChannelsKey: 1,
    AVEncoderBitRateKey: 128000,
]
let audioFile = try AVAudioFile(forWriting: outputURL, settings: m4aSettings)
// 结果：写入后文件大小 557 字节，仅容器 header，无音频帧
```

### 之后（✅ 正确）

```swift
let wavSettings: [String: Any] = [
    AVFormatIDKey: kAudioFormatLinearPCM,
    AVSampleRateKey: sampleRate,         // 16000
    AVNumberOfChannelsKey: 1,
    AVLinearPCMBitDepthKey: 32,
    AVLinearPCMIsFloatKey: true,
    AVLinearPCMIsBigEndianKey: false,
    AVLinearPCMIsNonInterleaved: false
]
let audioFile = try AVAudioFile(forWriting: outputURL, settings: wavSettings)
// 结果：文件大小与时长成比例（~64 KB/s for 16kHz float32 mono）
// AVAudioPlayer 完整支持 WAV 回放，无需额外转换
```

文件扩展名使用 `.wav`。

## 预防措施

1. **格式匹配规则**：Float32 PCM 输入流只能写入 PCM 容器（WAV/AIFF）。
   如需 M4A/AAC 输出，必须使用 `AVAssetWriter` + `AVAssetWriterInput` 管道，
   由系统编码器处理格式转换，不能直接用 `AVAudioFile`。

2. **静默失败防御**：`AVAudioFile` 写入完成后，用
   `FileManager.default.attributesOfItem(atPath:)[.size]` 验证文件大小 > 0，
   不能仅依赖 API 是否抛出异常来判断成功。

3. **Debug 断言**：构造 `settings` 字典时，在 Debug 构建中断言
   `AVFormatIDKey` 与输入 `AVAudioFormat.commonFormat` 一致，
   提前在编译期或运行时暴露格式不匹配问题。

## 测试要点

- **文件大小断言**：录音停止后，`XCTAssertGreaterThan(fileSize, 1024)` 验证
  输出文件至少包含有效音频数据（建议阈值 ≥ 1 KB）。
- **格式矩阵测试**：参数化测试覆盖 `(WAV, Float32)`、`(AIFF, Float32)`
  和 `(M4A, Float32 → 预期走 AVAssetWriter 路径)` 三组。
- **零字节回归**：CI 中保留专项回归用例，模拟 0.5 秒录音后写盘，
  断言文件大小 > 0，防止格式配置意外回退。

## 权衡

| | WAV | M4A/AAC |
|---|---|---|
| 文件大小 | 较大（~64 KB/s for 16kHz float32） | 较小（有损压缩） |
| 可靠性 | 高（无编码器依赖） | 低（编码器版本相关） |
| `AVAudioPlayer` 兼容性 | 完整 | 完整 |
| 适用场景 | 内部存储、离线用途 | 分发/云同步（需 AVAssetWriter） |

## 相关文档

- `docs/solutions/integration-issues/whisper-cpp-ggml-backend-integration-swift-2026-04-11.md`
  — Whisper 转录流水线中 WAV 格式音频的使用（上下游关联）
