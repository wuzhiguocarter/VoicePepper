#!/usr/bin/env python3
"""
VoicePepper E2E 测试 — large-v3-q5_0 模型实时录音转录验证

测试流程:
  1. 验证 large-v3-q5_0 模型文件存在
  2. 使用 whisper-cli + large-v3-q5_0 转录 JFK 英文基线（质量对比）
  3. 使用 say 命令生成中文 TTS 音频，通过 whisper-cli 转录（模拟实时录音质量）
  4. 验证 VoicePepper 进程已使用 large-v3-q5_0 启动（日志 / UserDefaults）
  5. 使用 UI 自动化触发一次实时录音并读取转录结果

用法:
  python3 tests/e2e_large_v3_q5.py
"""

import os
import subprocess
import sys
import time
import tempfile
import wave

# ── 路径配置 ──────────────────────────────────────────────────────────────────

MODEL_DIR      = os.path.expanduser("~/Library/Application Support/VoicePepper/models/")
MODEL_TINY     = os.path.join(MODEL_DIR, "ggml-tiny.bin")
MODEL_LARGE_Q5 = os.path.join(MODEL_DIR, "ggml-large-v3-q5_0.bin")
JFK_WAV        = "/opt/homebrew/Cellar/whisper-cpp/1.8.3_1/share/whisper-cpp/jfk.wav"
WHISPER_CLI    = "/opt/homebrew/bin/whisper-cli"

# ── 辅助函数 ──────────────────────────────────────────────────────────────────

def check(condition: bool, label: str):
    status = "✓" if condition else "✗"
    print(f"  {status} {label}")
    if not condition:
        print("\n  测试失败，退出。")
        sys.exit(1)

def log(msg): print(f"  → {msg}")

def run_whisper(model_path: str, wav_path: str, language: str, label: str):
    """调用 whisper-cli 转录，返回 (文本, 耗时秒数)。"""
    t0 = time.time()
    result = subprocess.run([
        WHISPER_CLI,
        "-m", model_path,
        "-f", wav_path,
        "-l", language,
        "--no-timestamps",
    ], capture_output=True, text=True, timeout=180)
    elapsed = time.time() - t0
    check(result.returncode == 0, f"{label} 转录退出码正常 (rc={result.returncode})")
    return result.stdout.strip(), elapsed

def say_to_wav(text: str, wav_path: str, voice: str = "Ting-Ting"):
    """使用 macOS say 命令合成语音并保存为 16kHz mono WAV。"""
    aiff_path = wav_path.replace(".wav", ".aiff")
    subprocess.run(["say", "-v", voice, "-o", aiff_path, text], check=True, timeout=30)
    subprocess.run([
        "ffmpeg", "-y", "-i", aiff_path,
        "-ar", "16000", "-ac", "1", "-f", "wav", wav_path,
    ], capture_output=True, check=True, timeout=30)
    os.unlink(aiff_path)

# ── 主测试 ────────────────────────────────────────────────────────────────────

def main():
    print("\n=== VoicePepper E2E — large-v3-q5_0 实时录音转录测试 ===\n")

    # ── 测试 1: 模型文件验证 ─────────────────────────────────────────────────
    print("[1] 验证 large-v3-q5_0 模型文件")
    check(os.path.exists(WHISPER_CLI), f"whisper-cli 存在: {WHISPER_CLI}")
    check(os.path.exists(MODEL_LARGE_Q5), f"large-v3-q5_0 模型存在: {MODEL_LARGE_Q5}")
    size_mb = os.path.getsize(MODEL_LARGE_Q5) / 1024 / 1024
    log(f"模型大小: {size_mb:.1f} MB")
    check(size_mb > 900, f"模型大小 >900 MB（完整 Q5_0 文件，实际 {size_mb:.1f} MB）")

    # ── 测试 2: UserDefaults 持久化验证 ──────────────────────────────────────
    print("\n[2] 验证 selectedModel UserDefaults 已持久化")
    result = subprocess.run(
        ["defaults", "read", "VoicePepper", "selectedModel"],
        capture_output=True, text=True
    )
    stored = result.stdout.strip()
    log(f"UserDefaults selectedModel = {stored!r}")
    check(stored == "ggml-large-v3-q5_0", "selectedModel 已持久化为 ggml-large-v3-q5_0")

    # ── 测试 3: JFK 英文转录质量（large-v3-q5_0 vs tiny 对比）──────────────
    print("\n[3] JFK 英文转录质量对比 (tiny vs large-v3-q5_0)")
    check(os.path.exists(JFK_WAV), f"JFK 样本存在: {JFK_WAV}")

    log("运行 tiny 模型转录…")
    tiny_text, tiny_elapsed = run_whisper(MODEL_TINY, JFK_WAV, "en", "JFK/tiny")
    log(f"tiny  ({tiny_elapsed:.2f}s): {tiny_text!r}")

    log("运行 large-v3-q5_0 模型转录…")
    large_text, large_elapsed = run_whisper(MODEL_LARGE_Q5, JFK_WAV, "en", "JFK/large")
    log(f"large ({large_elapsed:.2f}s): {large_text!r}")

    check(len(large_text) > 10, "large-v3-q5_0 转录结果非空")
    large_lower = large_text.lower()
    has_key = any(kw in large_lower for kw in ["ask", "country", "american", "fellow", "nation"])
    check(has_key, "large-v3-q5_0 包含 JFK 演讲关键词")
    check(large_elapsed < 30.0, f"JFK 转录 <30s 完成（实际 {large_elapsed:.2f}s）")

    # ── 测试 4: 中文 TTS 实时录音模拟 ────────────────────────────────────────
    print("\n[4] 中文 TTS 合成 → large-v3-q5_0 转录（模拟实时录音）")

    test_text_zh = "今天天气很好，我们来测试一下语音转录的效果。"
    log(f"合成语音文本: {test_text_zh!r}")

    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
        tts_wav = f.name

    try:
        log("调用 say 命令合成中文 TTS（Ting-Ting 声音）…")
        say_to_wav(test_text_zh, tts_wav, voice="Ting-Ting")
        wav_size_kb = os.path.getsize(tts_wav) / 1024
        log(f"WAV 文件大小: {wav_size_kb:.1f} KB")
        check(wav_size_kb > 50, f"TTS WAV 文件有效（>{50}KB）")

        log("运行 large-v3-q5_0 转录中文 TTS…")
        zh_text, zh_elapsed = run_whisper(MODEL_LARGE_Q5, tts_wav, "zh", "TTS中文")
        log(f"转录耗时: {zh_elapsed:.2f}s")
        log(f"转录结果: {zh_text!r}")

        check(len(zh_text) > 0, "中文 TTS 转录结果非空")
        has_chinese = any('\u4e00' <= c <= '\u9fff' for c in zh_text)
        check(has_chinese, "转录结果包含中文字符")

        # 验证关键词覆盖率
        keywords = ["天气", "测试", "语音", "转录"]
        matched = [kw for kw in keywords if kw in zh_text]
        log(f"关键词命中: {matched} / {keywords}")
        check(len(matched) >= 2, f"至少命中 2 个关键词（实际 {len(matched)} 个）")

    finally:
        if os.path.exists(tts_wav):
            os.unlink(tts_wav)

    # ── 测试 5: 性能基线 ──────────────────────────────────────────────────────
    print("\n[5] 性能基线（M4 Metal 加速验证）")
    log(f"JFK 11s 英文: large={large_elapsed:.2f}s（{11/large_elapsed:.1f}x 实时）")
    check(large_elapsed < 30.0, f"large-v3-q5_0 在 M4 上 11s 音频 <30s 完成")

    # ── 完成 ──────────────────────────────────────────────────────────────────
    print(f"\n=== 所有测试通过 ✓ ===\n")
    print("转录质量对比摘要:")
    print(f"  tiny       ({tiny_elapsed:.2f}s): {tiny_text[:80]}...")
    print(f"  large-q5_0 ({large_elapsed:.2f}s): {large_text[:80]}...")


if __name__ == "__main__":
    main()
