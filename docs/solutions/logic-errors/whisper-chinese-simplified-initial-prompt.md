---
title: "whisper.cpp 中文转录默认输出繁体，通过 initial_prompt 强制简体"
module: "Services/Transcription"
tags:
  - whisper-cpp
  - transcription
  - simplified-chinese
  - traditional-chinese
  - initial-prompt
  - language-detection
  - swift-c-interop
  - nsstring
problem_type: "logic-error"
date: 2026-04-12
related_files:
  - Sources/VoicePepper/Services/WhisperContext.swift
---

## 问题描述

使用 `language = "auto"` 或 `language = "zh"` 进行中文语音转录，输出结果为**繁体中文**（如「傳輸」「設定」「語音轉錄」），而用户说的是大陆普通话，期望**简体中文**输出。

## 根本原因

`language = "zh"` 只告知 whisper.cpp 识别中文音频，**不控制简繁字形**。whisper 的训练语料同时包含简体（大陆）和繁体（台湾、香港）文本，模型在无上下文偏好时，特定语音特征（女声、台湾腔、部分普通话口音）会触发繁体输出概率更高的解码路径。

`initial_prompt` 是 whisper.cpp 原生支持的解码引导机制，在解码前注入文本上下文，有效偏置输出字形，**无需更换模型，无需后处理转换**。

## 修复方案

在 `WhisperContext.transcribe()` 中，设置语言参数后注入简体提示词：

```swift
// WhisperContext.swift — transcribe() 方法

var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
params.language = (language as NSString).utf8String

// 注入简体中文 initial_prompt，引导解码器优先输出简体字形。
// ⚠️ 内存安全：NSString.utf8String 返回的裸指针生命周期由 NSString 对象管理。
// 必须将 NSString 保存为局部变量，确保其生命周期覆盖整个 whisper_full() 同步调用。
let promptNS = "以下是普通话的转录，请使用简体中文。" as NSString
params.initial_prompt = promptNS.utf8String

let whisperRet = samples.withUnsafeBufferPointer { ptr in
    whisper_full(ctx, params, ptr.baseAddress, Int32(samples.count))
}
// promptNS 在此之后才离开作用域 — 安全
```

### ⚠️ Swift-C 互操作内存陷阱

```swift
// ❌ 危险：临时 NSString 可能在 whisper_full 调用前被释放
params.initial_prompt = ("以下是普通话的转录，请使用简体中文。" as NSString).utf8String

// ✅ 安全：局部变量生命周期覆盖调用
let promptNS = "以下是普通话的转录，请使用简体中文。" as NSString
params.initial_prompt = promptNS.utf8String
whisper_full(ctx, params, ...)
```

同样的模式已用于 `language` 参数：`params.language = (language as NSString).utf8String`。

## 验证

```bash
# 用 whisper-cli 直接验证 initial_prompt 效果
whisper-cli -m ~/Library/Application\ Support/VoicePepper/models/ggml-large-v3-q5_0.bin \
  -f test_zh.wav -l zh --no-timestamps \
  --prompt "以下是普通话的转录，请使用简体中文。"
# 输出：今天天气很好,我们来测试一下语音转录的效果。  ✅ 简体
```

实际录音测试：说「传输」「软件」「网络」等简繁差异词，确认输出为简体字形。

## 预防清单

- 中文转录**必须同时设置** `language = "zh"` 和 `initial_prompt` 含简体示例句
- `initial_prompt` 内容应为 10–20 字日常简体中文，避免含繁体字
- 分段音频处理时**每段都需传入** `initial_prompt`，否则后续段落可能退化为繁体
- 更换模型版本或量化精度后，**必须重新验证**简繁输出行为（量化影响 softmax 分布）
- 混合语言场景（中英夹杂）：`initial_prompt` 只影响中文部分字形，不干扰英文识别

## 常见陷阱

| 陷阱 | 说明 |
|---|---|
| `language = "zh"` ≠ 简体中文 | 语言代码只控制语言识别，不控制字形变体 |
| `language = "auto"` 更不稳定 | 部分口音会被识别为"台湾中文"上下文，繁体概率更高 |
| 量化模型行为不等于全精度 | `q5_0` 等量化版本需独立验证简繁倾向 |
| `utf8String` 裸指针生命周期 | 临时 NSString 被 ARC 回收后指针悬空，是常见 Swift-C 互操作 bug |

## 相关文档

- [`docs/solutions/best-practices/whisper-model-selection-rationale-2026-04-11.md`](../best-practices/whisper-model-selection-rationale-2026-04-11.md) — 中文转录模型选型背景（为何 large 级模型对普通话效果更好）
- [`docs/solutions/integration-issues/whisper-cpp-ggml-backend-integration-swift-2026-04-11.md`](../integration-issues/whisper-cpp-ggml-backend-integration-swift-2026-04-11.md) — whisper.cpp Swift 集成基础，WhisperContext 设计
