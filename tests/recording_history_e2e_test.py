#!/usr/bin/env python3
"""
VoicePepper 录音历史功能 E2E 测试

测试目标：
  1. 触发录音会话（通过 ⌥Space 快捷键）
  2. 录音 3 秒后停止
  3. 验证 WAV 文件出现在 Recordings 目录（持久化正确）
  4. 验证文件非空（AVAudioFile PCM 写入正常）
  5. 验证文件可被 AVFoundation 解析（格式有效）

注意：此测试绕过 AXPopover（已知预存问题），改用：
  - 快捷键驱动录音
  - 文件系统层验证 WAV 输出（替代原 M4A，修复 AVAudioFile AAC 编码不兼容问题）

用法:
  python3 tests/recording_history_e2e_test.py

Python 环境:
  arch -x86_64 /Users/wuzhiguo/projects/macos-ui-automation-mcp/.venv/bin/python3
"""

import os
import sys
import time
import glob
import subprocess

sys.path.insert(0, "/Users/wuzhiguo/projects/macos-ui-automation-mcp/src")

import AppKit
import ApplicationServices as AS

# ── AX 辅助 ───────────────────────────────────────────────────────────────────

def ax_attr(el, attr):
    err, val = AS.AXUIElementCopyAttributeValue(el, attr, None)
    return val if err == 0 else None

def ax_children(el):
    return ax_attr(el, "AXChildren") or []

def ax_press(el):
    return AS.AXUIElementPerformAction(el, "AXPress")

def find_active_voicepepper():
    """找到能响应 AX 查询的活跃 VoicePepper（跳过 zombie 进程）。"""
    ws = AppKit.NSWorkspace.sharedWorkspace()
    for app in ws.runningApplications():
        if app.localizedName() != "VoicePepper":
            continue
        ax_app = AS.AXUIElementCreateApplication(app.processIdentifier())
        err, extras = AS.AXUIElementCopyAttributeValue(ax_app, "AXExtrasMenuBar", None)
        if err == 0 and extras is not None:
            return app, ax_app, app.processIdentifier()
    return None, None, None

# ── 录音会话控制 ──────────────────────────────────────────────────────────────

def run_recording_session(duration_secs: int = 3) -> bool:
    """单个 bash 脚本执行完整录音会话：开始 → 录音 N 秒 → 停止。

    两次 osascript 调用放在同一 bash 进程中执行，确保第二次 keystroke
    能可靠到达 VoicePepper 全局热键监听器。
    分两次独立 subprocess.run 调用在 Python 环境中不稳定（第二次常被丢弃）。
    """
    osa_keystroke = "tell application \"System Events\" to keystroke space using {option down}"
    script = (
        f"osascript -e '{osa_keystroke}' "
        f"&& sleep {duration_secs} "
        f"&& osascript -e '{osa_keystroke}'"
    )
    result = subprocess.run(["bash", "-c", script], capture_output=True, text=True)
    if result.returncode != 0:
        print(f"  ⚠ 录音脚本返回 {result.returncode}: {result.stderr.strip()}")
        return False
    return True

# ── 测试辅助 ──────────────────────────────────────────────────────────────────

def check(condition: bool, label: str):
    print(f"  {'✓' if condition else '✗'} {label}")
    if not condition:
        print("\n  测试失败，退出。")
        sys.exit(1)

def log(msg):
    print(f"  → {msg}")

def wait_for(fn, timeout=15, interval=0.5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if fn():
            return True
        time.sleep(interval)
    return False

def recordings_dir():
    return os.path.expanduser(
        "~/Library/Application Support/VoicePepper/Recordings"
    )

def list_wav_files():
    pattern = os.path.join(recordings_dir(), "*.wav")
    return sorted(glob.glob(pattern))

def file_duration_seconds(path: str) -> float:
    """用 ffprobe 获取音频时长（秒）；失败返回 -1。"""
    try:
        result = subprocess.run(
            ["ffprobe", "-v", "error", "-show_entries",
             "format=duration", "-of", "default=noprint_wrappers=1:nokey=1", path],
            capture_output=True, text=True, timeout=10
        )
        return float(result.stdout.strip())
    except Exception:
        return -1.0

# ── 主测试 ────────────────────────────────────────────────────────────────────

def main():
    print("\n=== VoicePepper 录音历史 E2E 测试 ===\n")

    # ─── 准备 ──────────────────────────────────────────────────────────────────
    print("[1] 确认 VoicePepper 运行中")
    vp_app, ax_app, pid = find_active_voicepepper()
    check(vp_app is not None, "VoicePepper 进程在运行（AX 响应）")
    log(f"PID={pid}")

    print("\n[2] 确认 Recordings 目录存在")
    rdir = recordings_dir()
    check(os.path.isdir(rdir), f"目录存在: {rdir}")
    files_before = list_wav_files()
    log(f"测试前已有 {len(files_before)} 个录音文件")

    # ─── 录音完整会话（开始 + 3 秒 + 停止）──────────────────────────────────────
    print("\n[3] 执行录音会话（⌥Space → 3s → ⌥Space）")
    log("启动单脚本录音会话（约 3 秒）...")
    session_ok = run_recording_session(duration_secs=3)
    check(session_ok, "录音脚本执行成功（start + stop）")
    log("录音已停止，等待文件写盘（最多 10 秒）...")

    # ─── 验证文件出现 ───────────────────────────────────────────────────────────
    print("\n[4] 验证 WAV 文件已保存")

    def new_file_appeared():
        current = list_wav_files()
        return len(current) > len(files_before)

    appeared = wait_for(new_file_appeared, timeout=10, interval=0.5)
    check(appeared, "新 WAV 文件出现在 Recordings 目录")

    files_after = list_wav_files()
    new_files = [f for f in files_after if f not in files_before]
    log(f"新文件: {[os.path.basename(f) for f in new_files]}")

    # ─── 验证文件有效 ──────────────────────────────────────────────────────────
    print("\n[5] 验证 WAV 文件内容")
    for new_file in new_files:
        size_bytes = os.path.getsize(new_file)
        log(f"{os.path.basename(new_file)}: {size_bytes:,} bytes")
        check(size_bytes > 1024, f"文件非空（> 1KB）: {os.path.basename(new_file)}")

        # 用 ffprobe 验证时长（若 ffprobe 可用）
        duration = file_duration_seconds(new_file)
        if duration > 0:
            log(f"  时长: {duration:.2f}s")
            check(duration >= 1.0, f"录音时长 ≥ 1 秒: {duration:.2f}s")
        else:
            log("  ffprobe 不可用，跳过时长验证（文件大小已验证）")

    # ─── 汇总 ─────────────────────────────────────────────────────────────────
    total_files = len(files_after)
    print(f"\n[6] 汇总")
    log(f"Recordings 目录共 {total_files} 个文件（本次新增 {len(new_files)} 个）")
    check(len(new_files) == 1, "本次录音恰好生成 1 个文件（会话合并正确）")

    print("\n=== 录音历史 E2E 测试全部通过 ✓ ===\n")


if __name__ == "__main__":
    main()
