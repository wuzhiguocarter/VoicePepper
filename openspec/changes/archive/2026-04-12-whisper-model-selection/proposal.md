## Why

当前应用仅内置 tiny/base/small 三个小型 Whisper 模型，转录质量受限。用户需要能在偏好设置中自由选择更大的模型（含量化版本），并在切换后自动触发模型重载；若本地尚未下载对应模型，应展示进度并自动下载。目标机器为 M4 + 32GB，主推 large-v3-q5_0（~1.1 GB）和 large-v3-turbo-q5_0（~0.6 GB）量化模型。

## What Changes

- **扩展模型列表**：在 `WhisperModel` 枚举中新增 `medium`、`large-v2`、`large-v3`、`large-v3-q5_0`、`large-v3-turbo-q5_0`，并补充准确文件大小标注；量化版本标注"推荐"
- **模型热切换**：用户在 Preferences 中切换模型后，`TranscriptionService` 监听 `AppState.selectedModel` 变化，自动卸载旧模型并加载新模型
- **下载进度 UI**：PreferencesView 模型列表中每一项显示"已下载 / 未下载 / 下载中(xx%)"状态；下载中时展示进度条，并支持取消下载
- **持久化选择**：将 `selectedModel` 持久化到 `UserDefaults`，下次启动时自动加载上次选择的模型

## Capabilities

### New Capabilities

- `whisper-model-catalog`: 扩展模型注册表，包含 medium/large-v2/large-v3/large-v3-q5_0/large-v3-turbo-q5_0，附带文件大小、显示名称、下载 URL 元数据，以及检测本地是否已下载的能力；量化模型标注推荐标签
- `model-hot-switch`: 用户在运行时切换模型时，安全地卸载旧上下文、触发新模型的下载/加载流程，并向 UI 反映实时状态（idle / downloading / loading / ready / failed）

### Modified Capabilities

<!-- 无现有 spec 文件，无需列出 -->

## Impact

- `Sources/VoicePepper/Models/AppState.swift` — 扩展 `WhisperModel` 枚举；`selectedModel` 改为从 `UserDefaults` 读写
- `Sources/VoicePepper/Services/WhisperModelManager.swift` — 新增 `switchModel(_:)` 方法，安全释放旧 `WhisperContext` 后调用 `ensureModel`；暴露 per-model 下载状态
- `Sources/VoicePepper/Services/TranscriptionService.swift` — 订阅 `appState.$selectedModel`，在变化时调用 `modelManager.switchModel(_:)`，期间暂停入队操作
- `Sources/VoicePepper/UI/PreferencesView.swift` — 每个模型行显示本地状态 badge + 下载进度条；model-picker 在加载中期间置灰
- 无外部依赖变更（whisper.cpp 二进制不变，仅模型文件更大）
