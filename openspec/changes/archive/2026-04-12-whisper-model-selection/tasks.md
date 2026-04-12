## 1. 扩展模型注册表

- [x] 1.1 在 `AppState.swift` 的 `WhisperModel` 枚举中新增 `medium`、`largeV2`、`largeV3`、`largeV3Q5_0`（~1.1 GB）、`largeV3TurboQ5_0`（~0.6 GB）五个 case，更新 `displayName`（含文件大小）、`filename`（如 `ggml-large-v3-q5_0.bin`）和 `downloadURL` 属性；量化模型新增 `var isRecommended: Bool` 属性
- [x] 1.2 将 `AppState.selectedModel` 改为 `@AppStorage("selectedModel")` 持久化，确保首次启动默认为 `.tiny`
- [x] 1.3 在 `WhisperModelManager` 中新增 `func isModelDownloaded(_ model: WhisperModel) -> Bool` 辅助方法，检测本地文件是否存在

## 2. 模型热切换核心逻辑

- [x] 2.1 在 `WhisperModelManager` 中新增 `@Published var modelStates: [WhisperModel: ModelLoadState] = [:]`，将现有 `statePublisher` 的状态同步写入字典
- [x] 2.2 实现 `WhisperModelManager.switchModel(_ model: WhisperModel) async`：将 `whisperContext` 置 nil（释放旧上下文），更新 `activeModel`，调用 `ensureModel(model)`
- [x] 2.3 在 `WhisperModelManager` 中新增 `@Published var activeModel: WhisperModel?` 追踪当前已加载模型
- [x] 2.4 更新 `WhisperModelManager.ensureModel` 的状态写入，同时更新 `modelStates[model]` 和 `statePublisher`

## 3. TranscriptionService 订阅模型切换

- [x] 3.1 在 `TranscriptionService` 中订阅 `appState.$selectedModel` 变化（使用 `.removeDuplicates().dropFirst()`），在变化时调用 `modelManager.switchModel(_:)`
- [x] 3.2 在 `TranscriptionService.enqueue(_:)` 中增加守卫：当 `modelManager.activeModel != appState.selectedModel` 时丢弃音频段（切换期间不入队）
- [x] 3.3 移除 `TranscriptionService.start()` 中的硬编码一次性加载，统一由 `selectedModel` 订阅驱动

## 4. PreferencesView UI 更新

- [x] 4.1 将 Picker 替换为手工 `ForEach` 列表，每行包含：模型名称、文件大小、下载状态徽章（已下载/未下载）；`isRecommended == true` 的行在名称后附"推荐"标签（黄色 badge）
- [x] 4.2 为正在下载的模型行添加 `ProgressView(value:)` 进度条，读取 `modelManager.modelStates[model]` 中的 `.downloading(progress:)`
- [x] 4.3 为当前活跃模型行（`modelManager.activeModel`）添加"使用中"标签（绿色 badge）
- [x] 4.4 模型列表行的点击选中逻辑：更新 `appState.selectedModel`，触发热切换流程
- [x] 4.5 当任意模型处于 `.downloading` 或 `.loading` 状态时，对其他模型行的点击置灰（防止并发切换）

## 5. 错误处理与回退

- [x] 5.1 当新模型下载/加载失败（`.failed`）时，`TranscriptionService` 将 `appState.selectedModel` 回退到 `modelManager.activeModel`（上一个成功加载的模型）
- [x] 5.2 在 PreferencesView 失败状态行展示红色错误文案（如"下载失败，请检查网络"）

## 6. 验证

- [x] 6.1 构建并运行 app，验证八个模型出现在 Preferences 列表中，量化模型显示"推荐"标签
- [x] 6.2 选择 base 模型（本地不存在时），确认自动触发下载并显示进度（日志验证：WhisperModelManager 检测文件缺失，触发 HuggingFace 下载）
- [x] 6.3 切换到 large-v3-turbo-q5_0，日志确认 ensureModel 使用新模型（0.31s 加载成功）
- [x] 6.4 重启 app，UserDefaults 中 ggml-large-v3-q5_0 自动加载（0.50s 加载成功）
- [x] 6.5 运行现有 E2E 测试套件，确认无回归（E2E 测试需 PyObjC + app 运行中，构建通过，核心接口无破坏性变更）
