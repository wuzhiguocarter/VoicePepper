#!/usr/bin/env python3
"""
VoicePepper E2E Test
使用 macOS Accessibility API (PyObjC) 验证核心 UI 流程

测试流程:
  1. 确认 Accessibility 权限
  2. 确认 VoicePepper 进程在运行
  3. 在 AXExtrasMenuBar 中找到 statusBarMicButton
  4. 点击按钮 → 打开 Popover
  5. 验证 Popover 已打开（AXFocusedWindow = AXPopover）
  6. 验证 Popover 内关键元素存在（支持 identifier + description 双重匹配）
  7. 再次点击关闭 Popover
"""

import sys
import time

sys.path.insert(0, "/Users/wuzhiguo/projects/macos-ui-automation-mcp/src")

import AppKit
import ApplicationServices as AS
import Quartz


# ── 辅助函数 ──────────────────────────────────────────────────────────────────

def ax_attr(element, attr):
    err, val = AS.AXUIElementCopyAttributeValue(element, attr, None)
    return val if err == 0 else None


def ax_children(element):
    return ax_attr(element, "AXChildren") or []


def ax_press(element):
    return AS.AXUIElementPerformAction(element, "AXPress")


def ax_get_point(element, attr):
    """Decode AXValue CGPoint"""
    err, val = AS.AXUIElementCopyAttributeValue(element, attr, None)
    if err != 0 or val is None:
        return None
    _, point = AS.AXValueGetValue(val, AS.kAXValueCGPointType, None)
    return point


def ax_get_size(element, attr):
    """Decode AXValue CGSize"""
    err, val = AS.AXUIElementCopyAttributeValue(element, attr, None)
    if err != 0 or val is None:
        return None
    _, size = AS.AXValueGetValue(val, AS.kAXValueCGSizeType, None)
    return size


def cg_click(element):
    """Click an AX element using CGEvent (works reliably with status bar buttons)."""
    pos = ax_get_point(element, "AXPosition")
    size = ax_get_size(element, "AXSize")
    if pos is None or size is None:
        return False
    px = pos.x + size.width / 2
    py = pos.y + size.height / 2
    down = Quartz.CGEventCreateMouseEvent(None, Quartz.kCGEventLeftMouseDown, (px, py), Quartz.kCGMouseButtonLeft)
    Quartz.CGEventPost(Quartz.kCGHIDEventTap, down)
    time.sleep(0.05)
    up = Quartz.CGEventCreateMouseEvent(None, Quartz.kCGEventLeftMouseUp, (px, py), Quartz.kCGMouseButtonLeft)
    Quartz.CGEventPost(Quartz.kCGHIDEventTap, up)
    return True


def collect_elements(element, depth=15, result=None):
    """收集所有 AX 元素，返回 (role, identifier, description, value) 列表。"""
    if result is None:
        result = []
    if depth <= 0:
        return result
    result.append({
        "role": ax_attr(element, "AXRole"),
        "identifier": ax_attr(element, "AXIdentifier"),
        "description": ax_attr(element, "AXDescription"),
        "value": ax_attr(element, "AXValue"),
        "enabled": ax_attr(element, "AXEnabled"),
    })
    for child in ax_children(element):
        collect_elements(child, depth - 1, result)
    return result


def find_element(elements, *, identifier=None, description=None, role=None):
    """在元素列表中按条件查找元素。"""
    for e in elements:
        if identifier and e.get("identifier") == identifier:
            return e
        if description and e.get("description") == description:
            if role is None or e.get("role") == role:
                return e
    return None


def check(condition: bool, label: str):
    status = "✓" if condition else "✗"
    print(f"  {status} {label}")
    if not condition:
        print("\n  测试失败，退出。")
        sys.exit(1)


def log(msg: str):
    print(f"  → {msg}")


# ── 主测试 ────────────────────────────────────────────────────────────────────

def main():
    print("\n=== VoicePepper E2E Test ===\n")

    # 1. Accessibility 权限
    print("[1] 检查 Accessibility 权限")
    trusted = AS.AXIsProcessTrusted()
    log(f"AXIsProcessTrusted = {trusted}")
    check(trusted, "Accessibility 权限已授予")

    # 2. 找到 VoicePepper 进程
    print("\n[2] 找到 VoicePepper 进程")
    ws = AppKit.NSWorkspace.sharedWorkspace()
    vp_app = next(
        (a for a in ws.runningApplications() if a.localizedName() == "VoicePepper"),
        None
    )
    log(f"PID={vp_app.processIdentifier() if vp_app else None}")
    check(vp_app is not None, "VoicePepper 在运行中")

    pid = vp_app.processIdentifier()
    ax_app = AS.AXUIElementCreateApplication(pid)

    # 3. 找 statusBarMicButton
    print("\n[3] 查找 statusBarMicButton")
    extras_bar = ax_attr(ax_app, "AXExtrasMenuBar")
    check(extras_bar is not None, "AXExtrasMenuBar 可访问")

    mic_button = None
    for child in ax_children(extras_bar):
        if ax_attr(child, "AXIdentifier") == "statusBarMicButton":
            mic_button = child
            break
    check(mic_button is not None, "statusBarMicButton 找到")

    # 4. 点击按钮
    print("\n[4] 点击 statusBarMicButton 打开 Popover")
    err = ax_press(mic_button)
    log(f"AXPress 结果: {err} (0=成功)")
    check(err == 0, "成功点击按钮")
    time.sleep(1.5)

    # 5. 验证 Popover 已打开
    print("\n[5] 验证 Popover 已打开")
    focused = ax_attr(ax_app, "AXFocusedWindow")
    popover_el = None
    if focused:
        role = ax_attr(focused, "AXRole")
        log(f"AXFocusedWindow.AXRole = {role!r}")
        # Check if focused window is the popover (AXPopover or AXWindow with transcriptionPopover inside)
        all_focused = collect_elements(focused, depth=15)
        focused_ids = {e["identifier"] for e in all_focused if e["identifier"]}
        if "transcriptionPopover" in focused_ids:
            popover_el = focused

    # If not found in focused window, search all windows
    if popover_el is None:
        all_windows = ax_attr(ax_app, "AXWindows") or []
        for w in all_windows:
            w_elements = collect_elements(w, depth=15)
            w_ids = {e["identifier"] for e in w_elements if e["identifier"]}
            if "transcriptionPopover" in w_ids:
                popover_el = w
                break

    # Also check under the status bar button (Popover may be a child of AXMenuBarItem)
    if popover_el is None:
        extras_bar2 = ax_attr(ax_app, "AXExtrasMenuBar")
        if extras_bar2:
            for child in ax_children(extras_bar2):
                if ax_attr(child, "AXIdentifier") == "statusBarMicButton":
                    for sub in ax_children(child):
                        sub_role = ax_attr(sub, "AXRole")
                        if sub_role == "AXPopover":
                            popover_el = sub
                            break

    check(popover_el is not None, "Popover 已打开")

    # 6. 收集 Popover 内所有元素
    print("\n[6] 验证 Popover 内关键元素")
    all_elements = collect_elements(popover_el, depth=15)
    identifiers_found = {e["identifier"] for e in all_elements if e["identifier"]}
    descriptions_found = {e["description"] for e in all_elements if e["description"]}
    log(f"Identifiers: {identifiers_found}")
    log(f"Descriptions: {descriptions_found}")

    # 根据修复状态选择验证策略
    # 若 .accessibilityElement(children: .contain) 生效，子元素有独立 identifier
    # 若未生效（未重新构建），降级用 AXDescription 验证
    popover_visible = "transcriptionPopover" in identifiers_found
    check(popover_visible, "transcriptionPopover identifier 存在")

    # 验证清除按钮（identifier 或 description）
    clear_by_id = find_element(all_elements, identifier="clearButton")
    clear_by_desc = find_element(all_elements, description="清除", role="AXButton")
    check(
        clear_by_id is not None or clear_by_desc is not None,
        "清除按钮可访问 (clearButton 或 description='清除')"
    )

    # 验证复制全部按钮
    copy_by_id = find_element(all_elements, identifier="copyAllButton")
    copy_by_desc = find_element(all_elements, description="复制全部", role="AXButton")
    check(
        copy_by_id is not None or copy_by_desc is not None,
        "复制全部按钮可访问 (copyAllButton 或 description='复制全部')"
    )

    # 验证状态文字（加载中 或 就绪）
    status_texts = [e["value"] for e in all_elements if e.get("value") and isinstance(e["value"], str)]
    log(f"文本内容: {status_texts}")
    has_status = any("加载" in t or "就绪" in t or "按下" in t for t in status_texts)
    check(has_status, "状态文字显示正常")

    # 7. 关闭 Popover
    print("\n[7] 再次点击关闭 Popover")
    extras_bar2 = ax_attr(ax_app, "AXExtrasMenuBar")
    if extras_bar2:
        for child in ax_children(extras_bar2):
            if ax_attr(child, "AXIdentifier") == "statusBarMicButton":
                cg_click(child)
                break
    time.sleep(0.5)
    closed_focused = ax_attr(ax_app, "AXFocusedWindow")
    log(f"关闭后 AXFocusedWindow: {ax_attr(closed_focused, 'AXRole') if closed_focused else 'None'}")

    print("\n=== 所有测试通过 ✓ ===\n")


if __name__ == "__main__":
    main()
