#!/usr/bin/env python3
"""
VoicePepper 转录 E2E 功能测试

使用 whisper-cli（与 libwhisper 相同引擎）验证 tiny 模型能正确转录真实音频文件。

用法:
  python3 tests/transcription_e2e_test.py

测试用例:
  1. whisper-cli 可执行（验证安装）
  2. 转录 JFK 英文样本（验证英文基线）
  3. 转录真实中文录音（30s 片段）
  4. 验证转录用时符合预期
"""

import os
import subprocess
import sys
import time
import wave

# ── 路径配置 ─────────────────────────────────────────────────────────────────

MODEL_TINY    = os.path.expanduser("~/Library/Application Support/VoicePepper/models/ggml-tiny.bin")
JFK_WAV       = "/opt/homebrew/Cellar/whisper-cpp/1.8.3_1/share/whisper-cpp/jfk.wav"
CHINESE_M4A   = (
    "/Users/wuzhiguo/Library/Containers/com.tencent.xinWeChat/Data/Documents/"
    "xwechat_files/wxid_0966169663812_64da/msg/file/2026-04/4月7日 牛斌.m4a"
)
CHINESE_WAV   = "/tmp/test_input.wav"
WHISPER_CLI   = "/opt/homebrew/bin/whisper-cli"

# ── 辅助函数 ──────────────────────────────────────────────────────────────────

def check(condition: bool, label: str):
    status = "✓" if condition else "✗"
    print(f"  {status} {label}")
    if not condition:
        print("\n  测试失败，退出。")
        sys.exit(1)

def log(msg): print(f"  → {msg}")


def prepare_chinese_wav():
    """将 M4A 转换为 16kHz mono WAV（如需要）。"""
    if os.path.exists(CHINESE_WAV):
        with wave.open(CHINESE_WAV) as f:
            if f.getnchannels() == 1 and f.getframerate() == 16000:
                log(f"复用已有文件: {CHINESE_WAV}")
                return
    log("使用 ffmpeg 转换 M4A → 16kHz WAV (前30s)...")
    result = subprocess.run([
        "ffmpeg", "-y",
        "-i", CHINESE_M4A,
        "-t", "30",
        "-ar", "16000",
        "-ac", "1",
        "-f", "wav",
        CHINESE_WAV,
    ], capture_output=True, timeout=60)
    check(result.returncode == 0, f"ffmpeg 转换成功 (rc={result.returncode})")


def run_whisper(wav_path: str, language: str, label: str) -> tuple[str, float]:
    """调用 whisper-cli 转录，返回 (文本, 耗时秒数)。"""
    t0 = time.time()
    result = subprocess.run([
        WHISPER_CLI,
        "-m", MODEL_TINY,
        "-f", wav_path,
        "-l", language,
        "--no-timestamps",
        "--print-progress", "0",
    ], capture_output=True, text=True, timeout=120)
    elapsed = time.time() - t0
    check(result.returncode == 0, f"{label} whisper-cli 正常退出 (rc={result.returncode})")
    text = result.stdout.strip()
    return text, elapsed

# ── 主测试 ────────────────────────────────────────────────────────────────────

def main():
    print("\n=== VoicePepper 转录 E2E 功能测试 ===\n")

    # ── 测试 1: 验证 whisper-cli 可用 ─────────────────────────────────────
    print("[1] 验证 whisper-cli 安装")
    log(f"whisper-cli: {WHISPER_CLI}")
    log(f"模型: {MODEL_TINY}")
    check(os.path.exists(WHISPER_CLI), "whisper-cli 可执行文件存在")
    check(os.path.exists(MODEL_TINY), "tiny 模型文件存在")
    model_size_mb = os.path.getsize(MODEL_TINY) / 1024 / 1024
    log(f"模型大小: {model_size_mb:.1f} MB")
    check(model_size_mb > 70, f"模型大小 >70MB（真实模型，非测试占位）")

    # ── 测试 2: 转录 JFK 英文样本 ──────────────────────────────────────────
    print("\n[2] 转录 JFK 英文基线 (jfk.wav, ~11s)")
    check(os.path.exists(JFK_WAV), "jfk.wav 存在")

    jfk_text, jfk_elapsed = run_whisper(JFK_WAV, "en", "JFK")
    log(f"转录耗时: {jfk_elapsed:.2f}s")
    log(f"转录文本: {jfk_text!r}")

    check(len(jfk_text) > 10, "英文转录文本非空（>10字符）")
    jfk_lower = jfk_text.lower()
    has_key = any(kw in jfk_lower for kw in ["ask", "country", "american", "fellow"])
    check(has_key, "包含 JFK 演讲关键词 (ask/country/american/fellow)")
    check(jfk_elapsed < 15.0, f"11s 英文转录 <15s 完成 (实际 {jfk_elapsed:.2f}s)")

    # ── 测试 3: 转录中文真实录音 ────────────────────────────────────────────
    print("\n[3] 转录真实中文录音 (30s 片段)")
    prepare_chinese_wav()

    zh_text, zh_elapsed = run_whisper(CHINESE_WAV, "zh", "中文")
    log(f"转录耗时: {zh_elapsed:.2f}s")
    log(f"转录文本: {zh_text!r}")

    check(len(zh_text) > 0, "中文转录文本非空")
    has_chinese = any('\u4e00' <= c <= '\u9fff' for c in zh_text)
    check(has_chinese, "转录文本包含中文字符")
    check(zh_elapsed < 30.0, f"30s 中文转录 <30s 完成 (实际 {zh_elapsed:.2f}s)")

    # ── 测试 4: 性能基线 ────────────────────────────────────────────────────
    print("\n[4] 性能基线验证")
    zh_ratio = zh_elapsed / 30.0
    log(f"实时比率: {zh_ratio:.2f}x (zh, tiny, Metal)")
    check(zh_ratio < 1.0, f"中文转录快于实时 (比率 {zh_ratio:.2f}x < 1.0x)")

    print(f"\n=== 所有测试通过 ✓ ===\n")
    print("中文转录结果预览:")
    print(f"  {zh_text[:300]}{'...' if len(zh_text) > 300 else ''}\n")


if __name__ == "__main__":
    main()
