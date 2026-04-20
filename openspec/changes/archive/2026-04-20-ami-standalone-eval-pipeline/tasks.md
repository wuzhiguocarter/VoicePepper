# Tasks: ami-standalone-eval-pipeline

## Task 1: 创建 VoicePepperCore library target 目录与 Package.swift 重构

- [x] 创建 `Sources/VoicePepperCore/` 目录
- [x] 将以下文件从 `Sources/VoicePepper/` 移动到 `Sources/VoicePepperCore/`：
  - `Services/WhisperKitASRService.swift`
  - `Services/SpeakerKitDiarizationService.swift`
  - `Services/TimelineMerger.swift`
  - `Services/AudioFileSource.swift`
  - `Models/SpeakerAttributedTranscript.swift`
  - `Models/RealtimeSpeechPipeline.swift`
- [x] 从 `Models/AppState.swift` 提取 `RecordingSource` 和 `SpeechPipelineMode` 枚举到 `Sources/VoicePepperCore/PipelineTypes.swift`，从 `AppState.swift` 删除这两个定义
- [x] 更新 `Package.swift`：
  - 新增 `.target(name: "VoicePepperCore", ...)` library（依赖 WhisperKit, SpeakerKit, FluidAudio）
  - `VoicePepper` executable target 添加 `"VoicePepperCore"` 依赖
  - `AppState.swift` 顶部添加 `import VoicePepperCore`
- [x] 运行 `swift build` 验证编译通过

## Task 2: 实现 VoicePepperEval CLI binary

- [x] 创建 `Sources/VoicePepperEval/` 目录
- [x] 在 `Package.swift` 中新增 `.executableTarget(name: "VoicePepperEval", dependencies: ["VoicePepperCore"])`
- [x] 实现 `Sources/VoicePepperEval/main.swift`：
  - 解析 CLI 参数：`--wav <path>`, `--lang <zh|en>`, `--whisperkit-model <name>`, `--no-speaker`
  - 初始化 `WhisperKitASRService`（预热模型）
  - 初始化 `SpeakerKitDiarizationService`（可选，`--no-speaker` 跳过）
  - 初始化 `TimelineMerger`
  - 设置 Combine 订阅链：ASR callback → `merger.applyASREvent()`，SpeakerKit callback → `merger.applySpeakerEvent()`
  - 调用 `AudioFileSource.play(url: wavURL, chunkDuration: 15.0)` 并等待完成
  - 调用 `merger.snapshot()` 获取 `RealtimeTranscriptChunk[]`
  - 将结果序列化为 JSON，写入 stdout
- [x] 验证 `swift build --product VoicePepperEval` 编译成功
- [x] 用一个 AISHELL-1 测试 WAV 手动验证输出：`echo` 可见 JSON

## Task 3: 验证 SpeakerKit headless 可用性

- [x] 以 `--no-speaker` 模式测试 CLI：`VoicePepperEval --wav sample.wav --lang zh --no-speaker`，确认正常输出
- [x] 以完整模式（含 SpeakerKit）测试 CLI，观察是否需要 UI 上下文
- [x] SpeakerKit headless 可用，无需 UI 上下文，自动降级逻辑无需实现

## Task 4: 实现 standalone_eval.py Python 驱动层

- [x] 新建 `scripts/standalone_eval.py`
- [x] 实现数据加载：`--dataset aishell1` 加载 AISHELL-1 样本，`--dataset ami` 加载 AMI 句子样本
- [x] 实现 `transcribe_via_binary(wav_path, lang, binary_path, extra_args) -> list[dict]`：subprocess 调用 `VoicePepperEval`，解析 JSON stdout，返回 chunk 列表
- [x] 实现英文词级 WER：`word_normalize(text) -> list[str]`（去标点、转小写）+ `compute_word_wer(hyp, ref)`
- [x] 实现中文字符级 WER：`normalize_zh()` + `edit_distance()` + `compute_char_wer()`
- [x] 实现评估主循环：逐样本调用 binary → 解析 chunks → 拼接文本 → 计算 WER
- [x] 实现 `write_outputs(results, run_dir, elapsed)`：输出 summary.json / samples.csv / report.md
- [x] CLI 参数：`--dataset`, `--n-samples`, `--output-dir`, `--binary`, `--whisperkit-model`, `--no-speaker`, `--seed`

## Task 5: 编写单元测试

- [x] 新建 `tests/test_standalone_eval.py`
- [x] 测试英文词级 `word_normalize`：大写→小写、标点去除、多余空格
- [x] 测试 `compute_word_wer`：完全匹配、完全错误、一词错误、空 hypothesis
- [x] 测试 AISHELL-1 + AMI 数据加载函数（用临时目录）
- [x] 测试 `write_outputs`：输出文件内容正确
- [x] 运行 `python3 tests/test_standalone_eval.py` 全部通过（27 个测试）

## Task 6: 端到端验证

- [x] 构建 VoicePepperEval binary：`swift build --product VoicePepperEval`
- [x] 运行 AISHELL-1 小批量评估（3 个样本）：平均 WER 12.3%，报告完整
- [x] 运行 AMI 小批量评估（3 个样本）：长片段 WER 13.3%，报告完整
- [x] 确认两份报告 summary.json / report.md 输出完整，WER 数值合理
