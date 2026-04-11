---
title: Whisper 命令 Cheat Sheet
category: reference
tags:
  - whisper
  - whisper-cpp
  - openai-whisper
  - cli
  - speech-to-text
date: 2026-04-11
---

# Whisper 命令 Cheat Sheet

这份速查表整理的是当前机器上能看到的 `whisper*` 命令，以及它们各自的安装来源、用途和常见用法。

## 1. 安装来源总览

| 命令 | 安装来源 | 当前路径 | 主要用途 |
|------|---------|----------|----------|
| `whisper` | `pipx` 安装的 `openai-whisper` | `~/.local/bin/whisper` → `~/.local/pipx/venvs/openai-whisper/bin/whisper` | OpenAI Whisper Python 版主命令，做音频转写 |
| `whisper-cli` | Homebrew `whisper-cpp` | `/opt/homebrew/bin/whisper-cli` | 命令行转写 |
| `whisper-server` | Homebrew `whisper-cpp` | `/opt/homebrew/bin/whisper-server` | 启动本地服务/API |
| `whisper-stream` | Homebrew `whisper-cpp` | `/opt/homebrew/bin/whisper-stream` | 流式/实时识别 |
| `whisper-bench` | Homebrew `whisper-cpp` | `/opt/homebrew/bin/whisper-bench` | 性能基准测试 |
| `whisper-quantize` | Homebrew `whisper-cpp` | `/opt/homebrew/bin/whisper-quantize` | 模型量化/压缩 |
| `whisper-command` | Homebrew `whisper-cpp` | `/opt/homebrew/bin/whisper-command` | 语音命令/指令类工具 |
| `whisper-vad-speech-segments` | Homebrew `whisper-cpp` | `/opt/homebrew/bin/whisper-vad-speech-segments` | VAD 语音分段 |
| `whisper-talk-llama` | Homebrew `whisper-cpp` | `/opt/homebrew/bin/whisper-talk-llama` | Whisper + Llama 交互式联动 |
| `whisper-lsp` | Homebrew `whisper-cpp` | `/opt/homebrew/bin/whisper-lsp` | LSP/编辑器集成相关工具 |

## 2. 一眼看懂：它们属于哪一套

### A. Python 版 Whisper

- 命令：`whisper`
- 包名：`openai-whisper`
- 安装方式：`pipx install openai-whisper`
- 特点：
  - 更接近 OpenAI 官方 Python 生态
  - 适合脚本化调用、研究、快速转写

### B. C/C++ 版 whisper.cpp

- 命令：一组 `whisper-*`
- 包名：`whisper-cpp`
- 安装方式：`brew install whisper-cpp`
- 特点：
  - 原生二进制，终端体验更直接
  - 通常更适合本地推理、工具链集成、实时场景

## 3. 常见场景速查

| 场景 | 推荐命令 |
|------|----------|
| 转写单个音频文件 | `whisper` / `whisper-cli` |
| 需要本地 API 服务 | `whisper-server` |
| 会议录音边说边转写 | `whisper-stream` |
| 测试模型速度/性能 | `whisper-bench` |
| 模型压缩、节省资源 | `whisper-quantize` |
| 先切分语音片段再处理 | `whisper-vad-speech-segments` |
| 语音驱动命令/自动化 | `whisper-command` |
| 语音 + LLM 联动 | `whisper-talk-llama` |
| 编辑器/语言服务器式集成 | `whisper-lsp` |

## 4. 如何确认你当前装的是哪一个

```bash
command -v whisper
command -v whisper-cli
command -v whisper-server
command -v whisper-stream
command -v whisper-bench
command -v whisper-quantize
command -v whisper-command
command -v whisper-vad-speech-segments
command -v whisper-talk-llama
command -v whisper-lsp
```

如果是当前这台机器，结果会是：

```bash
whisper -> ~/.local/bin/whisper
whisper-cli -> /opt/homebrew/bin/whisper-cli
whisper-server -> /opt/homebrew/bin/whisper-server
whisper-stream -> /opt/homebrew/bin/whisper-stream
whisper-bench -> /opt/homebrew/bin/whisper-bench
whisper-quantize -> /opt/homebrew/bin/whisper-quantize
whisper-command -> /opt/homebrew/bin/whisper-command
whisper-vad-speech-segments -> /opt/homebrew/bin/whisper-vad-speech-segments
whisper-talk-llama -> /opt/homebrew/bin/whisper-talk-llama
whisper-lsp -> /opt/homebrew/bin/whisper-lsp
```

## 5. 安装来源溯源结论

### `whisper`

```bash
pipx list
pip show openai-whisper
```

- 由 `openai-whisper` 提供
- 版本：`20250625`
- Home page：`https://github.com/openai/whisper`

### `whisper-*`

```bash
brew info whisper-cpp
brew list whisper-cpp
```

- 由 Homebrew formula `whisper-cpp` 提供
- 当前安装版本：`1.8.3_1`
- Home page：`https://github.com/ggml-org/whisper.cpp`

## 6. 常见注意点

- `whisper` 和 `whisper-cli` 不是同一个实现。
- `whisper` 是 Python 包，`whisper-cli` 是 whisper.cpp 的原生二进制。
- whisper.cpp 的这些子命令通常依赖模型文件，模型不会自动下载。
- 如果你只想跑脚本转写，`whisper` 更轻量；如果你要本地服务、流式、量化、VAD 这类能力，优先看 `whisper-cpp` 这一套。

## 7. 最短命令模板

```bash
# Python 版
whisper audio.mp3 --model small

# whisper.cpp CLI
whisper-cli -m models/ggml-base.bin -f audio.wav

# 启动服务
whisper-server -m models/ggml-base.bin
```

> 具体参数以 `--help` 输出为准，不同版本可能略有差异。
