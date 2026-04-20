#!/usr/bin/env python3
"""
eval_pipeline.py — VoicePepper 自动化 WER 评估流水线

用法（必须用 x86_64 arch + PyObjC）:
    arch -x86_64 /Users/wuzhiguo/projects/macos-ui-automation-mcp/.venv/bin/python3 \\
        scripts/eval_pipeline.py \\
        --data-dir data/eval/aishell1/data_aishell \\
        --n-samples 50

前置条件:
    1. VoicePepper App 已启动（.build/debug/VoicePepper）
    2. App 处于 experimentalArgmaxOSS 模式 + filePlayback 录音源
    3. WhisperKit 模型已加载就绪（Popover 状态显示"就绪"）

评估数据集: AISHELL-1 测试集（6920 个样本，4-10s 短句，中文）
"""

import sys
import os
import time
import json
import csv
import random
import argparse
import subprocess
import unicodedata
from datetime import datetime
from pathlib import Path

# PyObjC（需要 arch -x86_64）
sys.path.insert(0, "/Users/wuzhiguo/projects/macos-ui-automation-mcp/src")
import AppKit
import ApplicationServices as AS

BUNDLE_ID = "com.voicepepper.app"


# ── AX 辅助 ──────────────────────────────────────────────────────────────────

def ax_attr(el, attr):
    err, val = AS.AXUIElementCopyAttributeValue(el, attr, None)
    return val if err == 0 else None

def ax_children(el):
    return ax_attr(el, "AXChildren") or []

def ax_press(el):
    return AS.AXUIElementPerformAction(el, "AXPress")

def find_by_id(root, identifier, depth=20):
    if depth <= 0:
        return None
    if ax_attr(root, "AXIdentifier") == identifier:
        return root
    for child in ax_children(root):
        found = find_by_id(child, identifier, depth - 1)
        if found is not None:
            return found
    return None

def collect_elements(el, depth=15, result=None):
    if result is None:
        result = []
    if depth <= 0:
        return result
    result.append({
        "role":       ax_attr(el, "AXRole"),
        "identifier": ax_attr(el, "AXIdentifier"),
        "value":      ax_attr(el, "AXValue"),
    })
    for child in ax_children(el):
        collect_elements(child, depth - 1, result)
    return result

def wait_for(fn, timeout=30, interval=0.5, desc="condition"):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if fn():
            return True
        time.sleep(interval)
    print(f"  [TIMEOUT] 等待 {desc} 超时 ({timeout}s)", file=sys.stderr)
    return False


# ── App/Popover 控制 ──────────────────────────────────────────────────────────

def get_ax_app():
    running = AppKit.NSWorkspace.sharedWorkspace().runningApplications()
    target = None
    for app in running:
        if app.bundleIdentifier() == BUNDLE_ID:
            if target is None or app.processIdentifier() > target.processIdentifier():
                target = app
    if not target:
        return None
    return AS.AXUIElementCreateApplication(target.processIdentifier())

def get_popover(ax_app):
    focused = ax_attr(ax_app, "AXFocusedWindow")
    if focused and ax_attr(focused, "AXRole") == "AXPopover":
        return focused
    return None

def open_popover(ax_app):
    extras = ax_attr(ax_app, "AXExtrasMenuBar")
    if not extras:
        return False
    for child in ax_children(extras):
        if ax_attr(child, "AXIdentifier") == "statusBarMicButton":
            ax_press(child)
            time.sleep(0.8)
            return True
    return False

def ensure_popover_open(ax_app):
    if get_popover(ax_app):
        return True
    open_popover(ax_app)
    time.sleep(0.5)
    return get_popover(ax_app) is not None

def press_in_popover(ax_app, button_id):
    popover = get_popover(ax_app)
    if not popover:
        return False
    btn = find_by_id(popover, button_id)
    if btn is None:
        return False
    ax_press(btn)
    return True

def is_idle(ax_app):
    popover = get_popover(ax_app)
    return popover is not None and find_by_id(popover, "recordingIndicatorIdle") is not None

def is_recording(ax_app):
    popover = get_popover(ax_app)
    return popover is not None and find_by_id(popover, "recordingIndicatorActive") is not None

def has_transcript_entries(ax_app):
    popover = get_popover(ax_app)
    if not popover:
        return False
    elems = collect_elements(popover, depth=10)
    return any("transcriptionEntry-" in (e.get("identifier") or "") for e in elems)


# ── 转录读取（通过 copyAll → pasteboard）────────────────────────────────────

def read_transcript_via_copy(ax_app) -> str:
    """Press copyAllButton → read NSPasteboard → return concatenated text."""
    pb_before = (AppKit.NSPasteboard.generalPasteboard()
                 .stringForType_(AppKit.NSPasteboardTypeString) or "")

    pressed = press_in_popover(ax_app, "copyAllButton")
    if not pressed:
        return ""
    time.sleep(0.3)

    text = (AppKit.NSPasteboard.generalPasteboard()
            .stringForType_(AppKit.NSPasteboardTypeString) or "")
    if text == pb_before:
        return ""

    # 格式: "[S0] 文本\n[S1] 文本"，提取纯文本部分
    parts = []
    for line in text.strip().split("\n"):
        line = line.strip()
        if not line:
            continue
        if line.startswith("[") and "] " in line:
            _, _, rest = line.partition("] ")
            parts.append(rest.strip())
        else:
            parts.append(line)
    return " ".join(parts)


# ── WER（字符级，适合中文）──────────────────────────────────────────────────

def normalize(text: str) -> list:
    return [ch.lower() for ch in text
            if unicodedata.category(ch).startswith(("L", "N"))]

def edit_distance(a: list, b: list) -> int:
    m, n = len(a), len(b)
    dp = list(range(n + 1))
    for i in range(1, m + 1):
        prev, dp[0] = dp[0], i
        for j in range(1, n + 1):
            temp = dp[j]
            dp[j] = prev if a[i-1] == b[j-1] else 1 + min(prev, dp[j], dp[j-1])
            prev = temp
    return dp[n]

def compute_wer(hyp: str, ref: str) -> dict:
    h, r = normalize(hyp), normalize(ref)
    if not r:
        return {"wer": 0.0, "edits": 0, "ref_len": 0}
    edits = edit_distance(h, r)
    return {"wer": edits / len(r), "edits": edits, "ref_len": len(r)}


# ── 数据加载 ──────────────────────────────────────────────────────────────────

def load_test_samples(data_dir: Path, n: int, seed: int) -> list:
    transcript_file = data_dir / "transcript" / "aishell_test_transcript.txt"
    wav_dir = data_dir / "wav" / "test"

    refs = {}
    with open(transcript_file, encoding="utf-8") as f:
        for line in f:
            parts = line.strip().split(None, 1)
            if len(parts) == 2:
                refs[parts[0]] = parts[1]

    samples = []
    for wav_path in sorted(wav_dir.glob("*.wav")):
        stem = wav_path.stem
        if stem in refs:
            samples.append({"id": stem, "wav": wav_path, "ref": refs[stem]})

    if not samples:
        raise FileNotFoundError(f"No test samples found under {wav_dir}")

    rng = random.Random(seed)
    rng.shuffle(samples)
    return samples[:n] if n > 0 else samples


# ── 单样本评估 ────────────────────────────────────────────────────────────────

def eval_sample(ax_app, sample: dict, timeout: int) -> dict:
    result = {
        "id":        sample["id"],
        "wav":       str(sample["wav"]),
        "reference": sample["ref"],
        "hypothesis": "",
        "wer":       None,
        "edits":     None,
        "ref_len":   None,
        "status":    "ok",
        "error":     "",
    }

    # 设置 WAV 路径（eval_pipeline → defaults → AppDelegate.startFilePlayback 读取）
    subprocess.run(
        ["defaults", "write", BUNDLE_ID, "filePlaybackWAVPath", str(sample["wav"])],
        check=True, capture_output=True
    )
    time.sleep(0.5)

    # 清除上次转录
    press_in_popover(ax_app, "clearButton")
    time.sleep(0.3)

    # 触发回放
    if not press_in_popover(ax_app, "testToggleRecordingButton"):
        result["status"] = "error"
        result["error"] = "无法触发 testToggleRecordingButton"
        return result

    # 等待录音开始
    if not wait_for(lambda: is_recording(ax_app), timeout=8, interval=0.3, desc="录音开始"):
        result["status"] = "timeout"
        result["error"] = "录音未能启动"
        return result

    # 等待回放完成（回到 idle）
    if not wait_for(lambda: is_idle(ax_app), timeout=timeout, interval=1.0, desc="回放完成"):
        result["status"] = "timeout"
        result["error"] = f"回放未在 {timeout}s 内完成"
        press_in_popover(ax_app, "testToggleRecordingButton")  # 强制停止
        time.sleep(1.0)
        return result

    # 等待转录结果出现（WhisperKit 处理延迟）
    wait_for(lambda: has_transcript_entries(ax_app), timeout=20, interval=0.5, desc="转录结果")

    # 读取转录文本
    hyp = read_transcript_via_copy(ax_app)
    result["hypothesis"] = hyp

    if not hyp.strip():
        result["status"] = "empty"
        result["error"] = "转录结果为空"
    else:
        w = compute_wer(hyp, sample["ref"])
        result["wer"]     = round(w["wer"], 4)
        result["edits"]   = w["edits"]
        result["ref_len"] = w["ref_len"]

    return result


# ── 报告生成 ──────────────────────────────────────────────────────────────────

def write_outputs(results: list, run_dir: Path, elapsed: float):
    valid = [r for r in results if r["wer"] is not None]
    n_total, n_valid = len(results), len(valid)
    avg_wer = sum(r["wer"] for r in valid) / n_valid if valid else None

    summary = {
        "timestamp":       datetime.now().isoformat(),
        "dataset":         "AISHELL-1 test",
        "n_total":         n_total,
        "n_valid":         n_valid,
        "n_error":         n_total - n_valid,
        "avg_wer":         round(avg_wer, 4) if avg_wer else None,
        "elapsed_seconds": round(elapsed, 1),
    }
    (run_dir / "summary.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8"
    )

    fields = ["id", "wav", "wer", "edits", "ref_len", "status", "reference", "hypothesis", "error"]
    with open(run_dir / "samples.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        w.writerows(results)

    wer_str = f"{avg_wer*100:.2f}%" if avg_wer is not None else "N/A"
    rating = ""
    if avg_wer is not None:
        pct = avg_wer * 100
        rating = ("优秀" if pct < 10 else "良好" if pct < 20
                  else "可接受" if pct < 40 else "较差")

    worst = sorted(valid, key=lambda x: x["wer"], reverse=True)[:10]
    worst_rows = "\n".join(
        f"| {r['id']} | {r['wer']*100:.1f}% "
        f"| {r['reference'][:25]} | {r['hypothesis'][:25]} |"
        for r in worst
    )

    report = f"""# VoicePepper WER 评估报告

**运行时间**: {summary['timestamp']}
**数据集**: AISHELL-1 test（字符级 WER）
**样本数**: {n_valid}/{n_total} 有效（{n_total - n_valid} 失败）
**平均 WER**: {wer_str}  ← {rating}
**耗时**: {elapsed:.1f}s

## 最差 10 个样本

| ID | WER | REF | HYP |
|---|---|---|---|
{worst_rows}

## 失败详情

{chr(10).join(f"- {r['id']}: [{r['status']}] {r['error']}" for r in results if r['wer'] is None)}
"""
    (run_dir / "report.md").write_text(report, encoding="utf-8")


# ── CLI 入口 ──────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="VoicePepper 自动化 WER 评估流水线")
    parser.add_argument("--data-dir", default="data/eval/aishell1/data_aishell",
                        help="AISHELL-1 data_aishell 目录（相对项目根）")
    parser.add_argument("--n-samples", type=int, default=50,
                        help="评估样本数（-1 = 全量 6920）")
    parser.add_argument("--output-dir", default="test-results/eval",
                        help="输出根目录（自动创建带时间戳的子目录）")
    parser.add_argument("--timeout", type=int, default=60,
                        help="单样本超时秒数")
    parser.add_argument("--seed", type=int, default=42)
    args = parser.parse_args()

    # 以项目根为基准解析路径
    project_root = Path(
        subprocess.run(["git", "rev-parse", "--show-toplevel"],
                       capture_output=True, text=True, check=True).stdout.strip()
    )
    data_dir  = project_root / args.data_dir
    run_id    = datetime.now().strftime("run_%Y%m%d-%H%M%S")
    run_dir   = project_root / args.output_dir / run_id
    run_dir.mkdir(parents=True, exist_ok=True)

    print(f"=== VoicePepper WER 评估流水线 ===")
    print(f"数据目录 : {data_dir}")
    print(f"输出目录 : {run_dir}")

    samples = load_test_samples(data_dir, args.n_samples, args.seed)
    print(f"测试样本 : {len(samples)} 个（seed={args.seed}）\n")

    ax_app = get_ax_app()
    if not ax_app:
        print("错误: VoicePepper 未运行，请先启动 App", file=sys.stderr)
        sys.exit(1)

    if not ensure_popover_open(ax_app):
        print("错误: 无法打开 Popover", file=sys.stderr)
        sys.exit(1)

    if not is_idle(ax_app):
        print("错误: App 当前不在空闲状态，请停止录音后重试", file=sys.stderr)
        sys.exit(1)

    eta_min = len(samples) * 20 // 60
    print(f"开始评估（预计约 {eta_min} 分钟）\n")

    results = []
    t0 = time.time()

    for i, sample in enumerate(samples):
        ref_preview = sample["ref"][:20]
        print(f"[{i+1:3d}/{len(samples)}] {sample['id']}  {ref_preview}…", end="", flush=True)

        r = eval_sample(ax_app, sample, args.timeout)
        results.append(r)

        if r["wer"] is not None:
            print(f"  WER={r['wer']*100:.1f}%")
        else:
            print(f"  [{r['status']}] {r['error']}")

        # 每 10 个样本保存一次中间结果
        if (i + 1) % 10 == 0:
            fields = ["id", "wer", "edits", "ref_len", "status", "reference", "hypothesis", "error"]
            with open(run_dir / "samples_partial.csv", "w", newline="", encoding="utf-8") as f:
                w = csv.DictWriter(f, fieldnames=fields)
                w.writeheader()
                w.writerows(results)

    elapsed = time.time() - t0
    write_outputs(results, run_dir, elapsed)

    valid = [r for r in results if r["wer"] is not None]
    avg_wer = sum(r["wer"] for r in valid) / len(valid) if valid else None

    print(f"\n{'='*50}")
    print(f"有效样本 : {len(valid)}/{len(results)}")
    if avg_wer is not None:
        print(f"平均 WER : {avg_wer*100:.2f}%")
    print(f"结果目录 : {run_dir}/")
    print(f"  summary.json  samples.csv  report.md")


if __name__ == "__main__":
    main()
