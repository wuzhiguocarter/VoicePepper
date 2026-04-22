# Spec: standalone-eval-pipeline

## Purpose

定义基于真实 WhisperKit + SpeakerKit + TimelineMerger pipeline 的 headless 批量 WER 评估能力，不依赖 App UI。

## Requirements

### Requirement: VoicePepperCore library 提取
系统 SHALL 将 `WhisperKitASRService`、`SpeakerKitDiarizationService`、`TimelineMerger`、`AudioFileSource`、`RealtimeSpeechPipeline` 及 `RecordingSource`/`SpeechPipelineMode` 枚举从 App target 提取到 `VoicePepperCore` library target。

#### Scenario: App target 保持功能不变
- **WHEN** 完成提取后执行 `swift build`
- **THEN** `VoicePepper` App target 编译成功，运行时行为不变

#### Scenario: CLI target 可访问 pipeline 服务
- **WHEN** `VoicePepperEval` target 依赖 `VoicePepperCore`
- **THEN** 可直接使用 `WhisperKitASRService`、`TimelineMerger` 等服务

### Requirement: VoicePepperEval CLI binary
系统 SHALL 提供 `VoicePepperEval` 命令行工具，接受 WAV 文件路径和语言参数，运行完整 pipeline 后将 `RealtimeTranscriptChunk[]` 以 JSON 格式输出到 stdout。

#### Scenario: 正常转录输出
- **WHEN** 调用 `VoicePepperEval --wav sample.wav --lang zh`
- **THEN** stdout 输出 JSON 数组，每个元素包含 `text`、`start`、`end`、`speaker` 字段

#### Scenario: 禁用 SpeakerKit
- **WHEN** 指定 `--no-speaker` 标志
- **THEN** `speaker` 字段为 null，不初始化 SpeakerKit（减少启动时间）

#### Scenario: WAV 文件不存在
- **WHEN** 指定路径的 WAV 不存在
- **THEN** stderr 输出错误信息，exit code 非零，stdout 无输出

### Requirement: Python 评估驱动层
系统 SHALL 提供 `scripts/standalone_eval.py`，通过 subprocess 驱动 `VoicePepperEval`，支持 AISHELL-1（字符级 WER）和 AMI（词级 WER）两种数据集，输出结构化报告。

#### Scenario: AISHELL-1 评估
- **WHEN** `--dataset aishell1 --n-samples 50`
- **THEN** 从 `data/eval/aishell1/data_aishell/` 抽 50 个样本，调用 `VoicePepperEval --lang zh`，计算字符级 WER，输出报告

#### Scenario: AMI 评估
- **WHEN** `--dataset ami --n-samples 50`
- **THEN** 从 `data/eval/ami/audio/utterances/` 抽 50 个样本，调用 `VoicePepperEval --lang en`，计算词级 WER，输出报告

#### Scenario: 无 AX 依赖
- **WHEN** 在无显示器的 CI macOS runner 上运行 `standalone_eval.py`
- **THEN** 脚本正常执行，不导入 PyObjC/AppKit/ApplicationServices
