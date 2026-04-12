## ADDED Requirements

### Requirement: Runtime model switching
系统 SHALL 支持用户在应用运行期间切换 Whisper 模型，无需重启 app。切换后转录功能 SHALL 使用新模型。

#### Scenario: Switch to already-downloaded model
- **WHEN** 用户在 Preferences 中选择一个本地已存在的模型
- **THEN** 旧模型上下文被释放，新模型在后台加载，加载完成后转录恢复

#### Scenario: Switch to model not yet downloaded
- **WHEN** 用户在 Preferences 中选择一个本地不存在的模型
- **THEN** 系统自动开始下载，下载完成后自动加载，转录功能在加载完成后恢复

---

### Requirement: Download progress UI
系统 SHALL 在 PreferencesView 中为每个模型行实时展示下载进度。

#### Scenario: Model download in progress
- **WHEN** 某模型正在下载
- **THEN** 该模型行显示进度条和百分比数字（如 "43%"），Picker 其余选项可点击但当前加载目标高亮

#### Scenario: Download completes
- **WHEN** 模型下载并加载成功
- **THEN** 进度条消失，该行显示"已下载"绿色徽章，转录功能恢复可用

#### Scenario: Download fails
- **WHEN** 网络错误导致下载失败
- **THEN** 该行显示错误提示文字（红色），Picker 回退到上一个已加载的模型

---

### Requirement: Transcription queue pause during model switch
系统 SHALL 在模型切换期间（从触发切换到新模型 ready 期间）暂停音频段入队，切换完成后自动恢复。

#### Scenario: Audio recorded during switch
- **WHEN** 模型正在切换（loading / downloading 状态）时有音频录制完成
- **THEN** 该音频段被丢弃（不进入队列），UI 可选择性展示"模型切换中"提示

#### Scenario: Queue resumes after switch
- **WHEN** 新模型进入 ready 状态
- **THEN** 后续音频段正常入队，转录恢复

---

### Requirement: Active model indicator
系统 SHALL 在 PreferencesView 中明确标识当前正在使用的模型（已加载到内存中）。

#### Scenario: Loaded model displayed
- **WHEN** 模型处于 ready 状态
- **THEN** 当前活跃模型行有明显视觉区分（如"使用中"标签），与"仅已下载"的模型区分
