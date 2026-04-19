## Overview

本次设计实现的是 `WhisperKit + SpeakerKit` 迁移的 **foundation layer**，而不是完整替换现有转录主链。

核心原则：

1. 默认功能不回归
2. 新栈以实验性方式接入
3. 先统一事件模型与 timeline，再逐步替换引擎

## Key Decisions

### 1. 保留当前默认转录主链

现有 `TranscriptionService`、`WhisperContext` 和 `FluidAudioDiarizationService` 已经在 `main` 上通过真实 E2E。  
本次不会把默认路径切到 `WhisperKit`，只新增实验性路径与基础设施。

### 2. 不依赖开源 SpeakerKit 的“完整实时流式接口”

Argmax 开源 SDK 可直接集成 `WhisperKit` 和 `SpeakerKit`，但“real-time transcription with speakers”在官方 README 中被归类为 Pro SDK 能力。  
因此本次实现按以下边界设计：

- `WhisperKitASRService`：提供引擎初始化与实验性转录入口
- `SpeakerKitDiarizationService`：提供基于音频数组的 diarization 入口
- `TimelineMerger`：提供统一 timeline 基础设施

也就是说，本次为“实时或准实时”的产品路径铺底，但不强行声称开源 SDK 已经提供现成端到端流式带 speaker 接口。

### 3. Timeline 先独立于 UI 存在

新增 `TimelineMerger` actor，不直接耦合 UI。  
这样可在不改现有 UI 主路径的情况下验证：

- ASR 事件进入 merger
- speaker 事件进入 merger
- merger 输出统一 chunk

### 4. 结构化 transcript 增加 engine metadata

当前 `.json` sidecar 只有 speaker 结构。  
为了后续比较 `whisper.cpp` / `WhisperKit`、`FluidAudio` / `SpeakerKit`，需要把引擎来源写入 sidecar。

推荐字段：

```text
engineMetadata
- asrEngine
- diarizationEngine
- modelVersion
- locale
```

## Scope

### In Scope

- 依赖接入
- 数据模型
- timeline merger
- 实验性 WhisperKit / SpeakerKit 服务封装
- 结构化 transcript metadata

### Out of Scope

- 默认 UI 切换到 WhisperKit 实时转录
- 默认 UI 显示实时 speaker 标签
- speaker identification / profile enrollment
- 移除 `whisper.cpp` 或 `FluidAudio`

## Validation Strategy

由于默认路径不变，本次验证重点是：

- `swift build` 通过
- 原有 E2E 不回归
- 新增基础设施能参与编译

如果中途因依赖或 API 不一致导致失败，优先修正适配层，而不是退回“只写文档不落地”。
