#!/usr/bin/env python3
"""
standalone_eval.py — 基于 VoicePepperEval binary 的 headless WER 评估

用法:
    python3 scripts/standalone_eval.py --dataset aishell1 --n-samples 50
    python3 scripts/standalone_eval.py --dataset ami --n-samples 50 --no-speaker

不依赖 App UI / PyObjC / AX，可在 CI headless macOS runner 上运行。
"""

import sys
import os
import json
import csv
import random
import argparse
import subprocess
import unicodedata
from datetime import datetime
from pathlib import Path

# ── 路径默认值 ────────────────────────────────────────────────────────────────

PROJECT_ROOT = Path(__file__).parent.parent
DEFAULT_BINARY = PROJECT_ROOT / ".build" / "debug" / "VoicePepperEval"
DEFAULT_OUTPUT_DIR = PROJECT_ROOT / "test-results" / "eval"

AISHELL_DATA_DIR = PROJECT_ROOT / "data" / "eval" / "aishell1" / "data_aishell"
AMI_DATA_DIR = PROJECT_ROOT / "data" / "eval" / "ami"


# ── 中文字符级 WER ─────────────────────────────────────────────────────────────

def normalize_zh(text: str) -> list[str]:
    """保留 Unicode Letter/Number 类别字符，去除标点和空格，返回字符列表。"""
    return [
        ch for ch in text
        if unicodedata.category(ch)[0] in ("L", "N")
    ]


def edit_distance(a: list, b: list) -> int:
    m, n = len(a), len(b)
    dp = list(range(n + 1))
    for i in range(1, m + 1):
        prev = dp[0]
        dp[0] = i
        for j in range(1, n + 1):
            temp = dp[j]
            if a[i - 1] == b[j - 1]:
                dp[j] = prev
            else:
                dp[j] = 1 + min(prev, dp[j], dp[j - 1])
            prev = temp
    return dp[n]


def compute_char_wer(hyp: str, ref: str) -> float:
    """中文字符级 WER。"""
    h = normalize_zh(hyp)
    r = normalize_zh(ref)
    if not r:
        return 0.0 if not h else 1.0
    return edit_distance(h, r) / len(r)


# ── 英文词级 WER ───────────────────────────────────────────────────────────────

def word_normalize(text: str) -> list[str]:
    """去标点、转小写、按空格分词。"""
    import string
    text = text.lower()
    text = text.translate(str.maketrans("", "", string.punctuation))
    return [w for w in text.split() if w]


def compute_word_wer(hyp: str, ref: str) -> float:
    """英文词级 WER。"""
    h = word_normalize(hyp)
    r = word_normalize(ref)
    if not r:
        return 0.0 if not h else 1.0
    return edit_distance(h, r) / len(r)


# ── 数据集加载 ─────────────────────────────────────────────────────────────────

def load_aishell1_samples(n_samples: int, seed: int) -> list[dict]:
    """加载 AISHELL-1 测试集样本。"""
    transcript_file = AISHELL_DATA_DIR / "transcript" / "aishell_test_transcript.txt"
    wav_dir = AISHELL_DATA_DIR / "wav" / "test"

    if not transcript_file.exists():
        raise FileNotFoundError(f"找不到 transcript 文件: {transcript_file}")

    samples = []
    with open(transcript_file, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split(None, 1)
            if len(parts) != 2:
                continue
            sample_id, ref_text = parts
            wav_path = wav_dir / f"{sample_id}.wav"
            if wav_path.exists():
                samples.append({"id": sample_id, "wav": str(wav_path), "ref": ref_text})

    random.seed(seed)
    random.shuffle(samples)
    return samples[:n_samples]


def load_ami_samples(n_samples: int, seed: int) -> list[dict]:
    """加载 AMI 测试集样本。"""
    transcript_file = AMI_DATA_DIR / "transcript" / "ami_test_transcript.txt"
    wav_dir = AMI_DATA_DIR / "audio" / "utterances"

    if not transcript_file.exists():
        raise FileNotFoundError(f"找不到 transcript 文件: {transcript_file}")

    samples = []
    with open(transcript_file, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split(None, 1)
            if len(parts) != 2:
                continue
            sample_id, ref_text = parts
            wav_path = wav_dir / f"{sample_id}.wav"
            if wav_path.exists():
                samples.append({"id": sample_id, "wav": str(wav_path), "ref": ref_text})

    random.seed(seed)
    random.shuffle(samples)
    return samples[:n_samples]


# ── binary 调用 ────────────────────────────────────────────────────────────────

def transcribe_via_binary(
    wav_path: str,
    lang: str,
    binary_path: str,
    extra_args: list[str] | None = None,
) -> list[dict]:
    """调用 VoicePepperEval binary，解析 JSON stdout，返回 chunk 列表。"""
    cmd = [binary_path, "--wav", wav_path, "--lang", lang]
    if extra_args:
        cmd.extend(extra_args)

    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=300,
        )
    except subprocess.TimeoutExpired:
        print(f"  [警告] 超时: {wav_path}", file=sys.stderr)
        return []

    if result.returncode != 0:
        print(f"  [错误] binary 退出码 {result.returncode}: {result.stderr[:200]}", file=sys.stderr)
        return []

    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError as e:
        print(f"  [错误] JSON 解析失败: {e}", file=sys.stderr)
        return []


# ── 报告输出 ───────────────────────────────────────────────────────────────────

def write_outputs(results: list[dict], run_dir: Path, elapsed: float, dataset: str) -> None:
    """输出 summary.json / samples.csv / report.md 到 run_dir。"""
    run_dir.mkdir(parents=True, exist_ok=True)

    wers = [r["wer"] for r in results]
    avg_wer = sum(wers) / len(wers) if wers else 0.0
    n_total = len(results)
    n_errors = sum(1 for r in results if r.get("error"))

    summary = {
        "dataset": dataset,
        "n_samples": n_total,
        "n_errors": n_errors,
        "avg_wer": round(avg_wer, 4),
        "elapsed_seconds": round(elapsed, 1),
        "timestamp": datetime.now().isoformat(),
    }

    with open(run_dir / "summary.json", "w", encoding="utf-8") as f:
        json.dump(summary, f, ensure_ascii=False, indent=2)

    fields = ["id", "wav", "ref", "hyp", "wer", "error"]
    with open(run_dir / "samples.csv", "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fields, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(results)

    with open(run_dir / "report.md", "w", encoding="utf-8") as f:
        f.write(f"# VoicePepperEval — {dataset} 评估报告\n\n")
        f.write(f"- 数据集: {dataset}\n")
        f.write(f"- 样本数: {n_total}（含 {n_errors} 个错误）\n")
        f.write(f"- 平均 WER: **{avg_wer:.2%}**\n")
        f.write(f"- 耗时: {elapsed:.1f}s\n")
        f.write(f"- 时间: {summary['timestamp']}\n\n")
        f.write("## 样本明细\n\n")
        f.write("| ID | REF | HYP | WER |\n")
        f.write("|---|---|---|---|\n")
        for r in results[:20]:
            ref = r.get("ref", "")[:50]
            hyp = r.get("hyp", "")[:50]
            f.write(f"| {r['id']} | {ref} | {hyp} | {r['wer']:.2%} |\n")
        if n_total > 20:
            f.write(f"\n_（仅展示前 20 条，共 {n_total} 条）_\n")

    print(f"\n输出目录: {run_dir}")
    print(f"平均 WER: {avg_wer:.2%}（{n_total} 样本，{n_errors} 错误，耗时 {elapsed:.1f}s）")


# ── 主函数 ─────────────────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(description="VoicePepperEval 批量 WER 评估")
    parser.add_argument("--dataset", choices=["aishell1", "ami"], default="aishell1",
                        help="评估数据集（默认 aishell1）")
    parser.add_argument("--n-samples", type=int, default=50,
                        help="评估样本数（默认 50）")
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT_DIR,
                        help="报告输出目录")
    parser.add_argument("--binary", type=str, default=str(DEFAULT_BINARY),
                        help="VoicePepperEval binary 路径")
    parser.add_argument("--whisperkit-model", default="large-v3",
                        help="WhisperKit 模型名称（默认 large-v3）")
    parser.add_argument("--no-speaker", action="store_true",
                        help="禁用 SpeakerKit")
    parser.add_argument("--seed", type=int, default=42,
                        help="随机种子（默认 42）")
    args = parser.parse_args()

    # 校验 binary
    if not Path(args.binary).exists():
        print(f"错误: binary 不存在 {args.binary}", file=sys.stderr)
        print("请先运行: swift build --product VoicePepperEval", file=sys.stderr)
        sys.exit(1)

    # 加载样本
    print(f"加载数据集: {args.dataset}，样本数: {args.n_samples}")
    if args.dataset == "aishell1":
        samples = load_aishell1_samples(args.n_samples, args.seed)
        lang = "zh"
        compute_wer = compute_char_wer
    else:
        samples = load_ami_samples(args.n_samples, args.seed)
        lang = "en"
        compute_wer = compute_word_wer

    print(f"实际加载: {len(samples)} 个样本")

    extra_args = ["--whisperkit-model", args.whisperkit_model]
    if args.no_speaker:
        extra_args.append("--no-speaker")

    # 评估主循环
    results = []
    import time
    start_time = time.time()

    for i, sample in enumerate(samples, 1):
        print(f"[{i}/{len(samples)}] {sample['id']}")
        chunks = transcribe_via_binary(
            wav_path=sample["wav"],
            lang=lang,
            binary_path=args.binary,
            extra_args=extra_args,
        )
        hyp = " ".join(c["text"] for c in chunks if c.get("text"))
        ref = sample["ref"]
        wer = compute_wer(hyp, ref)
        print(f"  REF: {ref[:60]}")
        print(f"  HYP: {hyp[:60]}")
        print(f"  WER: {wer:.2%}")
        results.append({
            "id": sample["id"],
            "wav": sample["wav"],
            "ref": ref,
            "hyp": hyp,
            "wer": round(wer, 4),
            "error": None,
        })

    elapsed = time.time() - start_time

    # 输出报告
    run_dir = args.output_dir / f"run_{datetime.now().strftime('%Y%m%d-%H%M%S')}_{args.dataset}"
    write_outputs(results, run_dir, elapsed, args.dataset)


if __name__ == "__main__":
    main()
