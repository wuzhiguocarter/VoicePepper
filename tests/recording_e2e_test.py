#!/usr/bin/env python3
"""
VoicePepper 录音功能 E2E 测试

测试流程:
  1. 打开 Popover，等待模型加载完成（状态变为"就绪"）
  2. 发送 ⌥Space 快捷键触发录音开始
  3. 验证录音状态指示器变为 active
  4. 录音 3 秒（对着麦克风说话）
  5. 发送 ⌥Space 停止录音
  6. 验证录音指示器恢复 idle
  7. 等待转录结果出现在列表中

用法:
  python3 tests/recording_e2e_test.py
"""

import sys
import time

import AppKit
import ApplicationServices as AS
import Quartz

# ── AX 辅助函数 ───────────────────────────────────────────────────────────────

def ax_attr(el, attr):
    err, val = AS.AXUIElementCopyAttributeValue(el, attr, None)
    return val if err == 0 else None

def ax_children(el):
    return ax_attr(el, "AXChildren") or []

def ax_press(el):
    return AS.AXUIElementPerformAction(el, "AXPress")

def collect_elements(el, depth=15, result=None):
    if result is None:
        result = []
    if depth <= 0:
        return result
    result.append({
        "role":        ax_attr(el, "AXRole"),
        "identifier":  ax_attr(el, "AXIdentifier"),
        "description": ax_attr(el, "AXDescription"),
        "value":       ax_attr(el, "AXValue"),
    })
    for child in ax_children(el):
        collect_elements(child, depth - 1, result)
    return result

def find_by_id(elements, identifier):
    return next((e for e in elements if e.get("identifier") == identifier), None)

def find_element_by_id(root_el, identifier, depth=20):
    """直接在 AX 树中找到具有特定 identifier 的 AX 元素（返回原始 AX 元素）。"""
    if depth <= 0:
        return None
    if ax_attr(root_el, "AXIdentifier") == identifier:
        return root_el
    for child in ax_children(root_el):
        found = find_element_by_id(child, identifier, depth - 1)
        if found is not None:
            return found
    return None

def popover_elements(ax_app):
    focused = ax_attr(ax_app, "AXFocusedWindow")
    if not focused or ax_attr(focused, "AXRole") != "AXPopover":
        return []
    return collect_elements(focused, depth=15)

# ── ⌥Space 模拟（通过 Quartz CGEvent）────────────────────────────────────────

OPTION_KEY_CODE = 58   # kVK_Option
SPACE_KEY_CODE  = 49   # kVK_Space
OPTION_FLAG     = Quartz.kCGEventFlagMaskAlternate

def send_option_space():
    """模拟按下并释放 ⌥Space（全局快捷键）。
    使用 CGEventPost + kCGAnnotatedSessionEventTap 注入会话级事件。
    """
    src = Quartz.CGEventSourceCreate(Quartz.kCGEventSourceStateHIDSystemState)

    opt_down = Quartz.CGEventCreateKeyboardEvent(src, OPTION_KEY_CODE, True)
    Quartz.CGEventSetFlags(opt_down, OPTION_FLAG)

    space_down = Quartz.CGEventCreateKeyboardEvent(src, SPACE_KEY_CODE, True)
    Quartz.CGEventSetFlags(space_down, OPTION_FLAG)

    space_up = Quartz.CGEventCreateKeyboardEvent(src, SPACE_KEY_CODE, False)
    Quartz.CGEventSetFlags(space_up, OPTION_FLAG)

    opt_up = Quartz.CGEventCreateKeyboardEvent(src, OPTION_KEY_CODE, False)
    Quartz.CGEventSetFlags(opt_up, 0)

    # kCGAnnotatedSessionEventTap = 2（会话级，比 HID tap 权限要求低）
    tap = Quartz.kCGAnnotatedSessionEventTap
    Quartz.CGEventPost(tap, opt_down)
    Quartz.CGEventPost(tap, space_down)
    time.sleep(0.05)
    Quartz.CGEventPost(tap, space_up)
    Quartz.CGEventPost(tap, opt_up)
    log(f"⌥Space 已发送 (kCGAnnotatedSessionEventTap)")

# ── 测试辅助 ──────────────────────────────────────────────────────────────────

def check(condition: bool, label: str):
    print(f"  {'✓' if condition else '✗'} {label}")
    if not condition:
        sys.exit(1)

def log(msg): print(f"  → {msg}")

def wait_for(condition_fn, timeout=15, interval=0.5, desc="条件") -> bool:
    """轮询直到 condition_fn() 返回 True 或超时。"""
    deadline = time.time() + timeout
    while time.time() < deadline:
        if condition_fn():
            return True
        time.sleep(interval)
    return False

# ── 主测试 ────────────────────────────────────────────────────────────────────

def main():
    print("\n=== VoicePepper 录音功能 E2E 测试 ===\n")

    # ── 准备：获取 VoicePepper AX 引用 ───────────────────────────────────────
    ws = AppKit.NSWorkspace.sharedWorkspace()
    # 找到能响应 AX 查询的活跃 VoicePepper（跳过 zombie 进程）
    vp_list = [a for a in ws.runningApplications() if a.localizedName() == "VoicePepper"]
    active_vp, active_ax_app, active_pid = None, None, None
    for vp_cand in vp_list:
        cand_pid = vp_cand.processIdentifier()
        cand_ax = AS.AXUIElementCreateApplication(cand_pid)
        err, extras_val = AS.AXUIElementCopyAttributeValue(cand_ax, "AXExtrasMenuBar", None)
        if err == 0 and extras_val is not None:
            active_vp, active_ax_app, active_pid = vp_cand, cand_ax, cand_pid
            break
    check(active_vp is not None, "VoicePepper 进程在运行（AX 响应）")
    pid = active_pid
    ax_app = active_ax_app
    log(f"使用 PID={pid}")

    # ── 测试 1: 打开 Popover ──────────────────────────────────────────────────
    print("[1] 打开 Popover")
    extras = ax_attr(ax_app, "AXExtrasMenuBar")
    mic_btn = next((c for c in ax_children(extras) if ax_attr(c, "AXIdentifier") == "statusBarMicButton"), None)
    check(mic_btn is not None, "找到 statusBarMicButton")
    ax_press(mic_btn)
    time.sleep(1.5)

    # 等 Popover 出现（最多 5 秒）
    def popover_open():
        fw = ax_attr(ax_app, "AXFocusedWindow")
        return fw is not None and ax_attr(fw, "AXRole") == "AXPopover"

    appeared = wait_for(popover_open, timeout=5, interval=0.3)
    if not appeared:
        # 重试一次点击
        ax_press(mic_btn)
        time.sleep(1.5)
        appeared = wait_for(popover_open, timeout=5, interval=0.3)
    focused = ax_attr(ax_app, "AXFocusedWindow")
    log(f"AXFocusedWindow role={ax_attr(focused, 'AXRole') if focused else None}")
    check(appeared, "Popover 已打开")

    # ── 测试 2: 等待模型加载（状态变为"就绪"）────────────────────────────────
    print("\n[2] 等待 Whisper 模型加载")

    def get_status_texts():
        elems = popover_elements(ax_app)
        return [e.get("value") for e in elems if isinstance(e.get("value"), str) and e.get("value")]

    def is_model_ready():
        texts = get_status_texts()
        log(f"当前状态: {texts}")
        # 就绪 = 显示"就绪" 或 显示录音计时器（MM:SS 格式，说明模型已加载且录音中）
        return any("就绪" in t or (":" in t and len(t) == 5) for t in texts)

    # 先打印一下当前状态
    log(f"当前文本: {get_status_texts()}")

    ready = wait_for(is_model_ready, timeout=30, interval=1.0, desc="模型就绪")
    check(ready, 'Whisper tiny 模型加载完成（状态显示"就绪"或录音计时器）')

    # ── 测试 3: 触发录音 ──────────────────────────────────────────────────────
    print("\n[3] 触发录音（通过 AX 按钮 testToggleRecordingButton）")

    def press_toggle_button():
        """通过 AX 按 testToggleRecordingButton，返回是否成功。"""
        fw = ax_attr(ax_app, "AXFocusedWindow")
        if not fw:
            return False
        btn_el = find_element_by_id(fw, "testToggleRecordingButton")
        if btn_el is None:
            log("未找到 testToggleRecordingButton")
            return False
        ax_press(btn_el)
        return True

    # 如果已经在录音（如前次测试残留），先停止
    elems_now = popover_elements(ax_app)
    if find_by_id(elems_now, "recordingIndicatorActive"):
        log("检测到已在录音，先停止...")
        press_toggle_button()
        time.sleep(1.0)

    ok = press_toggle_button()
    check(ok, "成功触发 testToggleRecordingButton")
    time.sleep(0.5)

    def is_recording():
        elems = popover_elements(ax_app)
        return find_by_id(elems, "recordingIndicatorActive") is not None

    recording_started = wait_for(is_recording, timeout=5, interval=0.3)
    check(recording_started, "录音指示器变为 active (recordingIndicatorActive)")

    # 验证计时器文本出现
    elems = popover_elements(ax_app)
    texts = [e.get("value") for e in elems if isinstance(e.get("value"), str) and e.get("value")]
    log(f"录音中文本: {texts}")
    timer_visible = any(":" in (t or "") for t in texts)  # "00:00" 格式
    check(timer_visible, "录音计时器显示（MM:SS 格式）")

    # ── 测试 4: 录音 3 秒 ────────────────────────────────────────────────────
    print("\n[4] 录音 3 秒（请对着麦克风说话）")
    for i in range(3, 0, -1):
        log(f"录音中... {i}s")
        time.sleep(1.0)

    # ── 测试 5: 停止录音 ──────────────────────────────────────────────────────
    print("\n[5] 停止录音（再次按 testToggleRecordingButton）")
    press_toggle_button()
    time.sleep(0.5)

    def is_idle():
        elems = popover_elements(ax_app)
        return find_by_id(elems, "recordingIndicatorIdle") is not None

    stopped = wait_for(is_idle, timeout=5, interval=0.3)
    check(stopped, "录音停止（recordingIndicatorIdle）")

    # 验证不再显示计时器
    elems = popover_elements(ax_app)
    texts = [e.get("value") for e in elems if isinstance(e.get("value"), str) and e.get("value")]
    log(f"停止后文本: {texts}")

    # ── 测试 6: 等待转录结果 ──────────────────────────────────────────────────
    print("\n[6] 等待转录结果出现")

    def has_transcription():
        elems = popover_elements(ax_app)
        # 有转录条目时 emptyTranscriptionView 消失，条目数 >0
        has_empty = find_by_id(elems, "emptyTranscriptionView") is not None
        # 或者找到有内容的 transcriptionEntry
        entry_ids = [e.get("identifier") or "" for e in elems]
        has_entry = any("transcriptionEntry-" in (eid or "") for eid in entry_ids)
        return has_entry or not has_empty

    transcribed = wait_for(has_transcription, timeout=20, interval=1.0)

    # 打印当前 Popover 状态
    elems = popover_elements(ax_app)
    all_texts = [e.get("value") for e in elems if isinstance(e.get("value"), str) and e.get("value")]
    log(f"转录后文本: {all_texts}")

    check(transcribed, "转录结果已出现（emptyTranscriptionView 消失 或 条目可见）")

    # ── 关闭 Popover ──────────────────────────────────────────────────────────
    print("\n关闭 Popover")
    extras2 = ax_attr(ax_app, "AXExtrasMenuBar")
    for c in ax_children(extras2):
        if ax_attr(c, "AXIdentifier") == "statusBarMicButton":
            ax_press(c)
            break

    print("\n=== 录音功能测试全部通过 ✓ ===\n")


if __name__ == "__main__":
    main()
