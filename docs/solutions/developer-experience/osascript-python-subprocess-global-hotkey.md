---
title: "E2E 测试中 osascript 全局热键：单 bash 脚本优于多次 subprocess"
category: developer-experience
date: "2026-04-12"
module: testing
tags: [e2e, osascript, subprocess, python, global-hotkey, keyboard-shortcuts, automation, rosetta]
problem_type: test-reliability
severity: medium
status: resolved
---

# E2E 测试中 osascript 全局热键：单 bash 脚本优于多次 subprocess

## 问题

在 Python E2E 测试中，两次独立的 `subprocess.run(['osascript', ...])` 调用
发送 ⌥Space 全局热键：**第一次成功**触发 VoicePepper 录音，**第二次丢失**
（VoicePepper 未收到热键事件），导致录音无法停止、WAV 文件不生成。

**运行环境**：`arch -x86_64 /path/to/.venv/bin/python3`（Rosetta 2 venv，macOS）

## 根因

`arch -x86_64 python3`（Rosetta 2 环境）作为父进程发起 `subprocess.run(['osascript', ...])` 时，
macOS TCC（Transparency, Consent, and Control）Automation 权限缓存在 Rosetta 2 上下文中
对第二次调用异常处理：事件被静默丢弃，或延迟到测试超时后才送达。

**关键证据**：从 iTerm2/Terminal shell 直接运行两个连续 `osascript` 命令
（`start && sleep 4 && stop`），两次均成功。仅当通过 x86_64 Python subprocess
依次调用时出现第二次丢失。

## 修复

### 之前（❌ 不可靠）

```python
def send_option_space():
    result = subprocess.run(
        ["osascript", "-e",
         'tell application "System Events" to keystroke space using {option down}'],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        print(f"  ⚠ osascript 返回 {result.returncode}: {result.stderr.strip()}")
    time.sleep(0.1)

send_option_space()   # 开始录音 ← 成功
time.sleep(3)
send_option_space()   # 停止录音 ← 偶发性丢失（VoicePepper 未收到）
```

### 之后（✅ 可靠）

```python
def run_recording_session(duration_secs: int = 3) -> bool:
    """单个 bash 脚本执行完整录音会话：开始 → 录音 N 秒 → 停止。

    两次 osascript 在同一 bash 进程中串行执行，
    行为与 iTerm2 shell 直接调用完全一致。
    """
    osa = 'tell application "System Events" to keystroke space using {option down}'
    script = (
        f"osascript -e '{osa}' "
        f"&& sleep {duration_secs} "
        f"&& osascript -e '{osa}'"
    )
    result = subprocess.run(["bash", "-c", script], capture_output=True, text=True)
    if result.returncode != 0:
        print(f"  ⚠ 录音脚本返回 {result.returncode}: {result.stderr.strip()}")
        return False
    return True
```

## 规则

- **单 bash 脚本**：需要多次连续 osascript 键盘事件时，合并为一个
  `bash -c "osascript ... && sleep N && osascript ..."` 调用。
- **避免多次独立 subprocess.run**：从 x86_64 Python 进程每次单独调用
  osascript 发送全局热键不可靠，即使每次调用都返回 exit code 0。
- **适用范围**：`arch -x86_64 python3`（macos-ui-automation venv）中所有
  全局热键模拟场景均适用此规则。

## 预防措施

1. **环境隔离意识**：Rosetta 2 环境（`arch -x86_64`）对 macOS TCC 权限缓存
   的处理与 native arm64 不同，多次跨进程 Automation 调用需格外注意。

2. **退出码 + stderr 双重校验**：osascript subprocess 完成后，同时检查
   `returncode == 0` 和 `stderr` 为空，任一异常均视为失败并记录完整错误，
   避免"命令返回 0 但实际无效果"的静默错误。

## 测试要点

- **沙箱权限检查**：在集成测试环境中，断言 subprocess 调用 `returncode == 0`
  且 stderr 为空；CI 沙箱环境中，测试应 skip 并输出明确原因，而非静默通过。
- **输出有效性**：不仅检查退出码，还要验证实际效果
  （如 VoicePepper 录音确实开始/停止，WAV 文件确实生成）。

## 相关文档

- `docs/solutions/best-practices/macos-ax-e2e-testing-swiftui-2026-04-11.md`
  — 陷阱 4：KeyboardShortcuts 全局热键注入的替代方案（隐藏 AX 按钮）
- `docs/solutions/developer-experience/macos-native-ui-automation-mcp-2026-04-11.md`
  — 示例三：osascript 方案的完整替代实现（AXPress 触发，避免 Automation 权限依赖）
