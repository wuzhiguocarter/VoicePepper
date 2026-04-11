## ADDED Requirements

### Requirement: 本地 whisper 模型加载
系统 SHALL 在应用启动时从本地文件系统加载 whisper.cpp 模型文件，支持 tiny/base/small 模型规格，加载完成前显示加载状态。

#### Scenario: 模型加载成功
- **WHEN** 应用启动且模型文件存在于 Application Support 目录
- **THEN** 系统在后台线程完成模型加载，状态栏显示就绪状态，加载时间不超过 10 秒（Apple Silicon tiny 模型）

#### Scenario: 模型文件缺失
- **WHEN** 应用首次启动且模型文件不存在
- **THEN** 系统提示用户下载模型，并提供一键下载入口（从 Hugging Face 或 ggerganov CDN）

### Requirement: VAD 分段实时转录
系统 SHALL 通过语音活动检测（VAD）将连续音频流分割为语音段，每段结束后立即触发转录，转录延迟不超过 3 秒。

#### Scenario: 检测到语音停顿
- **WHEN** 音频流中出现超过 500ms 的静默
- **THEN** 系统将前一语音段提交给 whisper.cpp 转录，转录结果追加到显示文本

#### Scenario: 连续语音超时强制转录
- **WHEN** 连续语音超过 30 秒无停顿
- **THEN** 系统强制将当前音频段提交转录，避免无限等待

#### Scenario: 转录结果输出
- **WHEN** whisper.cpp 完成一段音频转录
- **THEN** 系统将转录文本（包含时间戳）通过 Combine Publisher 推送给 UI 层

### Requirement: Apple Silicon 硬件加速
系统 SHALL 在 Apple Silicon 设备上启用 Metal GPU 加速，在 Intel 设备上使用 CPU 路径。

#### Scenario: Apple Silicon 加速启用
- **WHEN** 运行在搭载 M 系列芯片的 Mac 上
- **THEN** whisper.cpp 使用 Metal backend 进行推理，转录速度不低于实时速度的 5x

#### Scenario: Intel 降级
- **WHEN** 运行在 Intel Mac 上
- **THEN** 系统使用 CPU 推理，转录速度不低于实时速度的 1x（tiny 模型）

### Requirement: 并发转录安全
系统 SHALL 保证转录任务串行执行，避免多段音频并发转录导致竞争条件。

#### Scenario: 转录队列
- **WHEN** 前一转录任务尚未完成时新音频段到达
- **THEN** 新音频段进入等待队列，前一任务完成后按序处理
