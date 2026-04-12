## Context

VoicePepper 当前硬编码三个小模型（tiny/base/small，最大 ~244 MB）。whisper.cpp 官方还提供 medium（~769 MB）和 large 系列（~1.5 GB+）。用户反映 tiny/base 准确率不足，尤其中文方言和专有名词识别差。

现有架构已具备下载+加载基础：`WhisperModelManager.ensureModel()` 封装了下载与加载；`AppState.selectedModel` 作为单一数据源；`TranscriptionService.start()` 仅在 app 启动时加载一次，不支持运行时切换。

## Goals / Non-Goals

**Goals:**
- 新增 medium、large-v2、large-v3 模型选项
- 用户在 Preferences 切换模型后，运行时热切换（卸载旧上下文 → 下载/加载新模型）
- Preferences UI 逐行展示每个模型的本地状态（已下载/未下载/下载中%）
- 切换时暂停转录入队，切换完成后恢复
- `selectedModel` 持久化到 UserDefaults

**Non-Goals:**
- 同时加载多个模型
- 模型量化/转换
- 自定义模型路径
- 下载断点续传

## Decisions

### D1: 模型切换由 TranscriptionService 统一驱动

**方案 A（选用）**：`TranscriptionService` 订阅 `appState.$selectedModel`，在变化时调用 `modelManager.switchModel(_:)`。

**方案 B**：AppDelegate 或 PreferencesView 直接调用 `modelManager`。

**选用 A 的理由**：转录暂停/恢复逻辑天然在 `TranscriptionService` 内，集中在一处避免 AppDelegate 膨胀；PreferencesView 只负责展示，不持有业务逻辑。

---

### D2: WhisperModelManager 新增 `switchModel` 方法

当前 `WhisperContext` 无显式 `deinit` 释放 C 内存的接口。新增 `func switchModel(_ model: WhisperModel) async`：先将 `whisperContext` 置 nil（ARC 触发 deinit），再调用 `ensureModel`。

---

### D3: Per-model 下载状态用独立 Published 字典

`WhisperModelManager` 新增：
```swift
@Published var modelStates: [WhisperModel: ModelLoadState] = [:]
```
`activeModel` 属性指向当前加载目标，供 UI 区分"当前正在使用"与"下载状态"。

**替代方案**：单一 `statePublisher`（当前做法）只能表达一个 model 状态，切换时 UI 无法同时展示多个模型的下载进度。

---

### D4: selectedModel 持久化

使用 `@AppStorage("selectedModel")` in `AppState`：

```swift
@AppStorage("selectedModel") var selectedModel: WhisperModel = .tiny
```

`WhisperModel.RawValue` 为 String，AppStorage 原生支持。

---

### D5: 不支持下载取消（本次范围外）

下载取消需要 URLSession task 管理层，复杂度较高，列入 Non-Goals。UI 仅展示进度，不提供取消按钮。

## Risks / Trade-offs

- **大模型磁盘占用**：large-v3 约 3 GB，首次下载耗时长。→ 在 UI 展示文件大小标注，让用户知情后选择。
- **切换期间内存峰值**：旧 WhisperContext 释放后才分配新上下文，依赖 ARC 即时释放。如果 whisper.cpp C 层有延迟释放，可能短暂峰值。→ 接受此风险，实际影响有限（macOS 有充足虚拟内存）。
- **切换期间录音丢失**：正在录音时用户切换模型，已录音频段可能被丢弃。→ 切换期间 UI 提示"正在切换模型，请稍候"，切换完成后恢复。

## Migration Plan

1. 仅新增枚举 case 和 UI，不修改现有存储格式。
2. `UserDefaults` 键 `selectedModel` 若不存在则默认 `tiny`，与旧版行为一致。
3. 无需数据迁移脚本。

## Open Questions

- whisper.cpp 的 `WhisperContext.deinit` 是否确实释放 C 层内存？需要实测确认。
- 下载进度 KVO 方式（当前用 `countOfBytesReceived`）在大文件下是否足够精确？
