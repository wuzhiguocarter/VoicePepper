---
title: "BLE 录音笔音频编码格式逆向确认：Opus SILK 12kHz"
category: integration-issues
date: 2026-04-18
module: BLE
tags: [CoreBluetooth, Opus, audio-codec, reverse-engineering, libopus, SILK]
problem_type: unknown-audio-format
severity: high
---

## 问题

蓝牙录音笔(A06)通过 BLE 实时转写通道推送音频数据，协议文档未说明编码格式。初始假设 PCM 16kHz 16-bit LE 导致 Whisper 产生幻觉输出（"Thanks for watching"），波形无变化。

## 症状

- Whisper 转录出无关英文文本（典型的噪音/无意义输入幻觉）
- UI 波形几乎无变化
- 数据率 ~2000 bytes/sec，远低于 PCM 16kHz 16-bit 的 32000 bytes/sec

## 逆向工程过程

### 1. 抓取原始数据

在 `BLERecorderService` 中添加 raw dump，将 BLE 音频负载写入 `/tmp/ble_audio_raw.bin`。

### 2. 发现子帧结构

分析 160 字节/包的负载，发现每包含 **4 个 40 字节子帧**：
- byte[0] = `0x4B`（每帧固定）
- byte[1] = `0x41`（大部分帧）
- byte[2] = 尾部零填充字节数
- 有效数据长度 = 36 - byte[2]，平均约 12 字节

### 3. 逐格式排除

| 尝试 | 结果 |
|---|---|
| PCM 16-bit LE 8/16kHz | 咔嗒声 |
| PCM 8-bit unsigned | 噪音 |
| G.711 A-law / µ-law | 噪音 |
| IMA ADPCM | 咔嗒声 |
| Signed 8-bit PCM | 噪音 |

### 4. Opus 确认

关键线索：`0x4B` 作为 Opus TOC byte 解析 = SILK 12kHz, 20ms, mono (config=9, stereo=0)。

用 ctypes 调用系统 libopus，以 40 字节子帧为独立 Opus 帧解码：
- `raw40_16000.wav`：**1112/1112 帧全部解码成功，22.2 秒音频**（完美匹配录音时长）
- 用户试听确认为正确语音

## 解决方案

### 格式参数

```
编码: Opus SILK mode
带宽: 12 kHz (narrowband+)
帧长: 20ms
帧大小: 40 bytes (固定槽位，含零填充)
每 BLE 包: 4 帧 × 40 bytes = 160 bytes
输出采样率: 16kHz (恰好匹配 Whisper)
```

### 集成方式

1. 创建 `COpus` SPM 桥接模块（与 CWhisper 相同模式）
2. 创建 `BLEOpusDecoder` Swift 封装，逐 40 字节帧调用 `opus_decode`
3. `BLERecorderService` 用 `opusDecoder.decodePacket(payload)` 替换 `convertInt16ToFloat32(payload)`

```swift
// OpusDecoder.swift 核心逻辑
func decodePacket(_ payload: Data) -> [Float] {
    var allSamples: [Float] = []
    for offset in stride(from: 0, to: payload.count, by: 40) {
        let frame = payload[offset..<min(offset + 40, payload.count)]
        let samples = decode(frame: Data(frame))  // opus_decode → Int16 → Float32
        allSamples.append(contentsOf: samples)
    }
    return allSamples
}
```

## 预防

当 BLE 设备协议文档未说明音频编码时，**先抓取原始数据再分析**，不要假设 PCM。诊断步骤：
1. Dump 原始字节到文件
2. 分析帧结构（固定偏移的重复字节模式）
3. 计算数据率（与已知编码的理论速率对比）
4. 用 libopus/ffmpeg 逐格式尝试解码
5. 以"全部帧解码成功 + 时长匹配"作为确认标准

## 相关文档

- [BLE SwiftUI 实例不一致](ble-swiftui-instance-identity.md) — 同一开发周期发现的另一个 BLE 问题
