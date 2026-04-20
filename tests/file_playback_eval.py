"""
file_playback_eval.py — 使用 AudioFileSource 通道对本地 WAV 进行 WER 评估。

用法:
    python3 tests/file_playback_eval.py --wav <path.wav> --ref <ref.txt|"直接文本">

流程:
    1. 通过 defaults write 设置 filePlaybackWAVPath
    2. 启动（或复用）VoicePepper 进程
    3. 用 AX API 将 recordingSource 切换为 filePlayback
    4. 触发录音 toggle（模拟快捷键 ⌥Space）
    5. 轮询 realtimeChunks 停止增长（或等到 App 回到 idle 状态）
    6. 计算并输出 WER

阶段一简化版（不走完整 App UI 路径）:
    直接在进程内调用 AudioFileSource + WhisperKitASRService，不需要启动 App。

    此脚本实现阶段一：读取 WAV 分块 → 人工计算 WER，无需运行 App。
"""
import argparse
import os
import sys
import wave
import array


def load_wav_samples(wav_path: str) -> tuple[list[float], int]:
    """读取 16kHz mono WAV，返回 (float32 samples, sample_rate)"""
    with wave.open(wav_path, "rb") as wf:
        nchannels = wf.getnchannels()
        sampwidth = wf.getsampwidth()
        framerate = wf.getframerate()
        nframes = wf.getnframes()
        raw = wf.readframes(nframes)

    if nchannels != 1:
        print(f"警告: WAV 声道数为 {nchannels}，期望 1（mono）。将取首声道。", file=sys.stderr)

    if sampwidth == 2:  # int16
        data = array.array("h", raw)
        samples = [s / 32768.0 for s in data[::nchannels]]
    elif sampwidth == 4:  # int32
        data = array.array("i", raw)
        samples = [s / 2147483648.0 for s in data[::nchannels]]
    else:
        raise ValueError(f"不支持的位深: {sampwidth * 8}-bit")

    return samples, framerate


def load_reference(ref: str) -> str:
    """从文件或字符串加载参考文本"""
    if os.path.isfile(ref):
        with open(ref, encoding="utf-8") as f:
            return f.read().strip()
    return ref.strip()


def normalize_text(text: str) -> list[str]:
    """简单归一化：去标点、转小写、按字符分割（适合中文 WER 字符级计算）"""
    import unicodedata
    # 去除标点和空白符
    result = []
    for ch in text:
        cat = unicodedata.category(ch)
        if cat.startswith("L") or cat.startswith("N"):  # Letter or Number
            result.append(ch.lower())
    return result


def edit_distance(a: list, b: list) -> int:
    """Levenshtein edit distance"""
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


def compute_wer(hypothesis: str, reference: str) -> dict:
    """计算字符级 WER（适合中文，不需要分词）"""
    hyp_chars = normalize_text(hypothesis)
    ref_chars = normalize_text(reference)

    if not ref_chars:
        return {"wer": 0.0 if not hyp_chars else float("inf"), "edits": 0, "ref_len": 0}

    edits = edit_distance(hyp_chars, ref_chars)
    wer = edits / len(ref_chars)
    return {"wer": wer, "edits": edits, "ref_len": len(ref_chars)}


def print_comparison_table(hypothesis: str, reference: str):
    """打印假设文本与参考文本的对比"""
    print("\n" + "=" * 60)
    print("转录结果对比")
    print("=" * 60)
    print(f"[REF] {reference}")
    print(f"[HYP] {hypothesis}")
    print("=" * 60)


def main():
    parser = argparse.ArgumentParser(
        description="VoicePepper 文件回放 WER 评估（阶段一：离线计算）"
    )
    parser.add_argument("--wav", required=True, help="待评估 WAV 文件路径（16kHz mono）")
    parser.add_argument("--ref", required=True, help="参考文本或 .txt 文件路径")
    parser.add_argument(
        "--hypothesis",
        help="如已有转录结果文本，直接传入用于计算 WER（跳过 App 调用）",
    )
    args = parser.parse_args()

    # 验证 WAV 文件
    if not os.path.isfile(args.wav):
        print(f"错误: WAV 文件不存在: {args.wav}", file=sys.stderr)
        sys.exit(1)

    try:
        samples, framerate = load_wav_samples(args.wav)
    except Exception as e:
        print(f"错误: 无法读取 WAV: {e}", file=sys.stderr)
        sys.exit(1)

    duration = len(samples) / max(framerate, 1)
    print(f"WAV 文件: {args.wav}")
    print(f"采样率: {framerate} Hz | 样本数: {len(samples)} | 时长: {duration:.2f}s")

    if framerate != 16000:
        print(f"警告: 采样率 {framerate} Hz ≠ 16000 Hz，请用 ffmpeg 预转换后再评估。", file=sys.stderr)

    # 加载参考文本
    reference = load_reference(args.ref)
    print(f"参考文本: {reference[:80]}{'...' if len(reference) > 80 else ''}")

    # 如提供了 hypothesis 直接计算 WER
    if args.hypothesis:
        hypothesis = args.hypothesis
    else:
        print("\n提示: 未提供 --hypothesis，请先通过 App filePlayback 模式获取转录结果，")
        print("      然后用 --hypothesis \"转录文本\" 重新运行此脚本计算 WER。")
        print("\n操作步骤:")
        print(f"  1. defaults write com.voicepepper.app filePlaybackWAVPath '{args.wav}'")
        print("  2. 启动 VoicePepper，切换到 experimentalArgmaxOSS 模式")
        print("  3. 将 recordingSource 设为 filePlayback（代码层）")
        print("  4. 触发 ⌥Space 开始文件回放")
        print("  5. 等待回放结束，复制 Popover 中的转录文本")
        print("  6. python3 tests/file_playback_eval.py --wav <path> --ref <ref> --hypothesis \"转录文本\"")
        sys.exit(0)

    result = compute_wer(hypothesis, reference)
    print_comparison_table(hypothesis, reference)

    wer_pct = result["wer"] * 100
    print(f"\nWER（字符级）: {wer_pct:.2f}%")
    print(f"编辑距离: {result['edits']} | 参考字符数: {result['ref_len']}")

    if wer_pct < 10:
        print("评级: 优秀 (< 10%)")
    elif wer_pct < 20:
        print("评级: 良好 (< 20%)")
    elif wer_pct < 40:
        print("评级: 可接受 (< 40%)")
    else:
        print("评级: 较差 (≥ 40%)")


if __name__ == "__main__":
    main()
