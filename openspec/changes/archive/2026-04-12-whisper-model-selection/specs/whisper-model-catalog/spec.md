## ADDED Requirements

### Requirement: Extended model registry
系统 SHALL 提供八个 Whisper 模型选项：tiny、base、small、medium、large-v2、large-v3、large-v3-q5_0、large-v3-turbo-q5_0，每个模型必须包含显示名称、文件大小描述、下载 URL 元数据，量化模型 SHALL 额外携带 `isRecommended: true` 标记。

#### Scenario: All models listed in picker
- **WHEN** 用户打开 Preferences > Whisper 模型
- **THEN** 列表展示八个模型，量化模型行附带"推荐"标签，每项显示名称包含模型大小（如 "Large-v3 Q5_0 (~1.1 GB) · 推荐"）

#### Scenario: Model download URL is valid for quantized models
- **WHEN** 系统需要下载量化模型
- **THEN** 使用 Hugging Face ggerganov/whisper.cpp CDN，文件名为 `ggml-large-v3-q5_0.bin` 和 `ggml-large-v3-turbo-q5_0.bin`

#### Scenario: Model download URL is valid for standard models
- **WHEN** 系统需要下载标准模型
- **THEN** 使用 Hugging Face ggerganov/whisper.cpp CDN 的对应文件名 URL，格式为 `ggml-<name>.bin`

---

### Requirement: Per-model local status detection
系统 SHALL 能检测每个模型是否已下载到本地（`~/Library/Application Support/VoicePepper/models/<filename>`）。

#### Scenario: Model already downloaded
- **WHEN** 对应 `.bin` 文件存在于模型目录
- **THEN** 该模型行显示"已下载"状态徽章（绿色 checkmark）

#### Scenario: Model not yet downloaded
- **WHEN** 对应 `.bin` 文件不存在
- **THEN** 该模型行显示"未下载"状态提示，并标注文件大小

---

### Requirement: Model selection persisted across launches
系统 SHALL 将用户最后选择的模型持久化到 UserDefaults，下次启动时自动加载该模型。

#### Scenario: App restarts after model switch
- **WHEN** 用户上次选择了 medium 模型并退出 app
- **THEN** 下次启动时 Preferences 中 medium 处于选中状态，且 app 自动加载 medium 模型

#### Scenario: First launch defaults to tiny
- **WHEN** UserDefaults 中无 `selectedModel` 记录（全新安装）
- **THEN** 默认选中 tiny 模型
