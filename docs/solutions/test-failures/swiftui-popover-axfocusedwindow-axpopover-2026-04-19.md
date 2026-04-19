---
title: SwiftUI Popover E2E should accept AXFocusedWindow as AXPopover
date: 2026-04-19
category: docs/solutions/test-failures
module: VoicePepper
problem_type: test_failure
component: testing_framework
symptoms:
  - tests/e2e_test.py failed at "Popover 已打开" even though the status bar button click succeeded
  - AX inspection showed AXFocusedWindow.AXRole was AXPopover, but the test still treated the popover as missing
root_cause: wrong_api
resolution_type: test_fix
severity: medium
tags: [swiftui, macos, accessibility, axpopover, e2e]
---

# SwiftUI Popover E2E should accept AXFocusedWindow as AXPopover

## Problem
VoicePepper 的 UI E2E 在打开状态栏 Popover 后失败，提示找不到 `transcriptionPopover`。实际应用没有回归，失败来自测试对 macOS Accessibility 结构的假设过窄。

## Symptoms
- `tests/e2e_test.py` 在步骤 5 失败，日志显示 `AXPress` 成功
- `AXFocusedWindow.AXRole` 为 `AXPopover`
- 手动 AX 树探查能看到 `transcriptionPopover`、`clearButton`、`copyAllButton`

## What Didn't Work
- 只把 `AXWindow` 当作可接受的焦点容器，再向下查找 `transcriptionPopover`
- 依赖窗口列表兜底搜索。这在当前 SwiftUI Popover 结构下不是主路径

## Solution
在 `tests/e2e_test.py` 中把 `AXFocusedWindow == AXPopover` 视为合法的 Popover 打开结果，再继续收集子元素做后续断言。

```python
focused = ax_attr(ax_app, "AXFocusedWindow")
popover_el = None
if focused:
    role = ax_attr(focused, "AXRole")
    log(f"AXFocusedWindow.AXRole = {role!r}")
    if role == "AXPopover":
        popover_el = focused
    else:
        all_focused = collect_elements(focused, depth=15)
        focused_ids = {e["identifier"] for e in all_focused if e["identifier"]}
        if "transcriptionPopover" in focused_ids:
            popover_el = focused
```

修复后重跑：
- `tests/e2e_test.py`
- `tests/recording_e2e_test.py`
- `tests/transcription_e2e_test.py`

并额外用 10 秒录音确认 `.json` diarization sidecar 正常生成。

## Why This Works
当前 SwiftUI Popover 在 macOS Accessibility 中可以直接暴露为 `AXPopover`，不一定先表现为 `AXWindow`。旧测试把“容器类型”和“内部结构存在性”绑死在一起，导致遇到合法但不同的 AX 结构时误报失败。先接受 `AXPopover`，再检查其子树里的 `transcriptionPopover` 和关键按钮，才能贴合真实 UI 语义。

## Prevention
- 写 macOS AX E2E 时，不要假设 SwiftUI Popover 只会以 `AXWindow` 暴露
- 先验证顶层角色是否为允许集合，例如 `AXPopover` / `AXWindow`，再做内部 identifier 断言
- UI E2E 失败后先做一次 AX 树探查，区分“应用回归”和“测试假设过严”
- 涉及录音或 diarization 的验证，除了 UI 断言，还要检查 `~/Library/Application Support/VoicePepper/Recordings/` 中的 `.wav/.txt/.json`

## Related Issues
- [macos-ax-e2e-testing-swiftui-2026-04-11.md](/Users/wuzhiguo/projects/VoicePepper/docs/solutions/best-practices/macos-ax-e2e-testing-swiftui-2026-04-11.md:1)
- [vad-buffer-not-flushed-before-stop-2026-04-18.md](/Users/wuzhiguo/projects/VoicePepper/docs/solutions/logic-errors/vad-buffer-not-flushed-before-stop-2026-04-18.md:1)
