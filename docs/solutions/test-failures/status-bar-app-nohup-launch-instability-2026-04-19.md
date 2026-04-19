---
title: "Status bar app E2E should prefer TTY launch over nohup"
date: 2026-04-19
category: docs/solutions/test-failures
module: VoicePepper
problem_type: test_failure
component: development_workflow
symptoms:
  - `tests/e2e_test.py` failed with `PID=None` even though the app had just been started
  - `nohup .build/debug/VoicePepper` wrote startup logs but the process exited before AX tests began
root_cause: async_timing
resolution_type: workflow_improvement
severity: low
tags: [macos, status-bar-app, e2e, nohup, tty]
---

# Status bar app E2E should prefer TTY launch over nohup

## Problem
VoicePepper 是 macOS 状态栏应用。用 `nohup` 启动调试包时，进程有时会完成初始化日志输出后提前退出，导致 AX E2E 在查找进程阶段直接失败。

## Symptoms
- `tests/e2e_test.py` 在 `[2] 找到 VoicePepper 进程` 失败
- `pgrep -f ".build/debug/VoicePepper"` 返回空
- `/tmp/voicepepper.log` 里能看到模型加载日志，说明不是立即崩溃

## What Didn't Work
- 继续沿用 `nohup "$PROJECT_ROOT/.build/debug/VoicePepper" > /tmp/voicepepper.log 2>&1 &`
- 只根据日志判断应用已经“启动成功”

## Solution
在仓库内验证时，如果 `nohup` 启动后 UI E2E 找不到进程，切换到前台 TTY 启动：

```bash
"/Users/wuzhiguo/projects/VoicePepper/.build/debug/VoicePepper"
```

然后再运行：

```bash
arch -x86_64 /Users/wuzhiguo/projects/macos-ui-automation-mcp/.venv/bin/python3 tests/e2e_test.py
```

## Why This Works
状态栏应用没有常规窗口生命周期，`nohup` 方式在当前环境下对进程保活不稳定；前台 TTY 会让进程持续附着在当前会话里，AX 自动化可以稳定发现它。

## Prevention
- `kb-dev-workflow` 里的默认 `nohup` 启动可以保留，但要把“找不到进程时改用 TTY 启动”作为标准 fallback
- 不要只看 `/tmp/voicepepper.log` 判断应用还活着，必须用 `pgrep` 或 AX 测试再次确认

## Related Issues
- [macos-native-ui-automation-mcp-2026-04-11.md](/Users/wuzhiguo/projects/VoicePepper/docs/solutions/developer-experience/macos-native-ui-automation-mcp-2026-04-11.md:1)
