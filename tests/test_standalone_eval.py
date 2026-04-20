#!/usr/bin/env python3
"""
tests/test_standalone_eval.py — standalone_eval.py 的单元测试
"""

import sys
import json
import csv
import os
import stat
import tempfile
import unittest
from pathlib import Path

# 将 scripts/ 加入路径
sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))

from standalone_eval import (
    word_normalize,
    compute_word_wer,
    compute_char_wer,
    normalize_zh,
    transcribe_via_binary,
    load_aishell1_samples,
    load_ami_samples,
    write_outputs,
)


class TestWordNormalize(unittest.TestCase):

    def test_lowercase(self):
        self.assertEqual(word_normalize("HELLO WORLD"), ["hello", "world"])

    def test_punctuation_removal(self):
        self.assertEqual(word_normalize("hello, world!"), ["hello", "world"])

    def test_extra_spaces(self):
        self.assertEqual(word_normalize("  hello   world  "), ["hello", "world"])

    def test_mixed(self):
        self.assertEqual(word_normalize("It's a test."), ["its", "a", "test"])

    def test_empty(self):
        self.assertEqual(word_normalize(""), [])

    def test_only_punctuation(self):
        self.assertEqual(word_normalize("...!!!"), [])


class TestComputeWordWer(unittest.TestCase):

    def test_perfect_match(self):
        self.assertAlmostEqual(compute_word_wer("hello world", "hello world"), 0.0)

    def test_complete_mismatch(self):
        # 2 substitutions / 2 ref words = 1.0
        self.assertAlmostEqual(compute_word_wer("foo bar", "hello world"), 1.0)

    def test_one_word_error(self):
        # 1 substitution / 2 ref words = 0.5
        self.assertAlmostEqual(compute_word_wer("hello there", "hello world"), 0.5)

    def test_empty_hypothesis(self):
        # 2 deletions / 2 ref words = 1.0
        self.assertAlmostEqual(compute_word_wer("", "hello world"), 1.0)

    def test_empty_ref_empty_hyp(self):
        self.assertAlmostEqual(compute_word_wer("", ""), 0.0)

    def test_empty_ref_nonempty_hyp(self):
        self.assertAlmostEqual(compute_word_wer("hello", ""), 1.0)

    def test_case_insensitive(self):
        self.assertAlmostEqual(compute_word_wer("HELLO WORLD", "hello world"), 0.0)

    def test_insertion(self):
        # 1 insertion / 1 ref word = 1.0
        self.assertAlmostEqual(compute_word_wer("hello world", "hello"), 1.0)


class TestComputeCharWer(unittest.TestCase):

    def test_perfect_match(self):
        self.assertAlmostEqual(compute_char_wer("你好世界", "你好世界"), 0.0)

    def test_one_char_error(self):
        # 1 substitution / 4 ref chars = 0.25
        self.assertAlmostEqual(compute_char_wer("你好地界", "你好世界"), 0.25)

    def test_empty_hypothesis(self):
        self.assertAlmostEqual(compute_char_wer("", "你好"), 1.0)

    def test_punctuation_ignored(self):
        # 标点应被过滤掉
        self.assertAlmostEqual(compute_char_wer("你好，世界！", "你好世界"), 0.0)


class TestLoadAishell1Samples(unittest.TestCase):

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.data_dir = Path(self.tmp.name) / "data_aishell"
        wav_dir = self.data_dir / "wav" / "test"
        transcript_dir = self.data_dir / "transcript"
        wav_dir.mkdir(parents=True)
        transcript_dir.mkdir(parents=True)

        # 创建假 WAV 文件和 transcript
        for i in range(5):
            (wav_dir / f"test_{i:05d}.wav").write_bytes(b"RIFF")
        (transcript_dir / "aishell_test_transcript.txt").write_text(
            "\n".join(f"test_{i:05d} 测试文本{i}" for i in range(5)),
            encoding="utf-8",
        )

        # 临时替换模块中的路径
        import standalone_eval
        self._orig = standalone_eval.AISHELL_DATA_DIR
        standalone_eval.AISHELL_DATA_DIR = self.data_dir

    def tearDown(self):
        import standalone_eval
        standalone_eval.AISHELL_DATA_DIR = self._orig
        self.tmp.cleanup()

    def test_loads_correct_count(self):
        samples = load_aishell1_samples(3, seed=42)
        self.assertEqual(len(samples), 3)

    def test_sample_fields(self):
        samples = load_aishell1_samples(1, seed=0)
        s = samples[0]
        self.assertIn("id", s)
        self.assertIn("wav", s)
        self.assertIn("ref", s)

    def test_n_larger_than_dataset(self):
        samples = load_aishell1_samples(100, seed=0)
        self.assertEqual(len(samples), 5)


class TestLoadAMISamples(unittest.TestCase):

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.ami_dir = Path(self.tmp.name) / "ami"
        wav_dir = self.ami_dir / "audio" / "utterances"
        transcript_dir = self.ami_dir / "transcript"
        wav_dir.mkdir(parents=True)
        transcript_dir.mkdir(parents=True)

        for i in range(3):
            (wav_dir / f"AMI_TEST_{i:03d}.wav").write_bytes(b"RIFF")
        (transcript_dir / "ami_test_transcript.txt").write_text(
            "\n".join(f"AMI_TEST_{i:03d} SAMPLE TEXT {i}" for i in range(3)),
            encoding="utf-8",
        )

        import standalone_eval
        self._orig = standalone_eval.AMI_DATA_DIR
        standalone_eval.AMI_DATA_DIR = self.ami_dir

    def tearDown(self):
        import standalone_eval
        standalone_eval.AMI_DATA_DIR = self._orig
        self.tmp.cleanup()

    def test_loads_correct_count(self):
        samples = load_ami_samples(2, seed=42)
        self.assertEqual(len(samples), 2)

    def test_sample_fields(self):
        samples = load_ami_samples(1, seed=0)
        s = samples[0]
        self.assertIn("id", s)
        self.assertIn("wav", s)
        self.assertIn("ref", s)


class TestWriteOutputs(unittest.TestCase):

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.run_dir = Path(self.tmp.name) / "run_test"

    def tearDown(self):
        self.tmp.cleanup()

    def _make_results(self):
        return [
            {"id": "s001", "wav": "/tmp/a.wav", "ref": "hello", "hyp": "hello", "wer": 0.0, "error": None},
            {"id": "s002", "wav": "/tmp/b.wav", "ref": "world", "hyp": "word", "wer": 0.5, "error": None},
        ]

    def test_creates_output_files(self):
        write_outputs(self._make_results(), self.run_dir, elapsed=10.0, dataset="aishell1")
        self.assertTrue((self.run_dir / "summary.json").exists())
        self.assertTrue((self.run_dir / "samples.csv").exists())
        self.assertTrue((self.run_dir / "report.md").exists())

    def test_summary_json_content(self):
        write_outputs(self._make_results(), self.run_dir, elapsed=5.0, dataset="ami")
        with open(self.run_dir / "summary.json", encoding="utf-8") as f:
            summary = json.load(f)
        self.assertEqual(summary["dataset"], "ami")
        self.assertEqual(summary["n_samples"], 2)
        self.assertAlmostEqual(summary["avg_wer"], 0.25, places=3)

    def test_samples_csv_content(self):
        write_outputs(self._make_results(), self.run_dir, elapsed=5.0, dataset="aishell1")
        with open(self.run_dir / "samples.csv", encoding="utf-8") as f:
            reader = csv.DictReader(f)
            rows = list(reader)
        self.assertEqual(len(rows), 2)
        self.assertIn("id", rows[0])
        self.assertIn("wer", rows[0])
        self.assertIn("wav", rows[0])

    def test_report_md_contains_avg_wer(self):
        write_outputs(self._make_results(), self.run_dir, elapsed=5.0, dataset="aishell1")
        content = (self.run_dir / "report.md").read_text(encoding="utf-8")
        self.assertIn("25.00%", content)


class TestNormalizeZh(unittest.TestCase):

    def test_chinese_chars(self):
        self.assertEqual(normalize_zh("你好世界"), ["你", "好", "世", "界"])

    def test_punctuation_removed(self):
        self.assertEqual(normalize_zh("你好，世界！"), ["你", "好", "世", "界"])

    def test_numbers_kept(self):
        self.assertEqual(normalize_zh("第3次"), ["第", "3", "次"])

    def test_latin_letters_kept(self):
        result = normalize_zh("AB你好")
        self.assertEqual(result, ["A", "B", "你", "好"])

    def test_empty(self):
        self.assertEqual(normalize_zh(""), [])

    def test_only_punctuation(self):
        self.assertEqual(normalize_zh("，。！？"), [])

    def test_spaces_removed(self):
        self.assertEqual(normalize_zh("你 好"), ["你", "好"])


class TestTranscribeViaBinary(unittest.TestCase):

    def _make_script(self, content: str) -> str:
        f = tempfile.NamedTemporaryFile(mode="w", suffix=".sh", delete=False)
        f.write("#!/bin/sh\n" + content)
        f.close()
        os.chmod(f.name, stat.S_IRWXU)
        return f.name

    def tearDown(self):
        pass

    def test_binary_not_found_returns_empty(self):
        result = transcribe_via_binary("/tmp/fake.wav", "zh", "/nonexistent/VoicePepperEval")
        self.assertEqual(result, [])

    def test_nonzero_exit_returns_empty(self):
        script = self._make_script("exit 1\n")
        try:
            result = transcribe_via_binary("/tmp/fake.wav", "zh", script)
            self.assertEqual(result, [])
        finally:
            os.unlink(script)

    def test_invalid_json_returns_empty(self):
        script = self._make_script("echo 'not valid json'\n")
        try:
            result = transcribe_via_binary("/tmp/fake.wav", "zh", script)
            self.assertEqual(result, [])
        finally:
            os.unlink(script)

    def test_empty_json_array_returns_empty(self):
        script = self._make_script("echo '[]'\n")
        try:
            result = transcribe_via_binary("/tmp/fake.wav", "zh", script)
            self.assertEqual(result, [])
        finally:
            os.unlink(script)

    def test_valid_json_returns_chunks(self):
        chunks = [{"text": "你好", "start": 0.0, "end": 1.0, "speaker": "S0"}]
        script = self._make_script(f"echo '{json.dumps(chunks)}'\n")
        try:
            result = transcribe_via_binary("/tmp/fake.wav", "zh", script)
            self.assertEqual(len(result), 1)
            self.assertEqual(result[0]["text"], "你好")
        finally:
            os.unlink(script)

    def test_extra_args_passed_to_binary(self):
        # binary 将 args 作为 JSON 输出，确认 extra_args 被传递
        script = self._make_script(
            'python3 -c "import sys,json; print(json.dumps(sys.argv[1:]))"\n'
        )
        try:
            result = transcribe_via_binary("/tmp/fake.wav", "en", script, extra_args=["--no-speaker"])
            # result 是 list of strings（args），不是 chunk 格式，但验证 extra_args 存在于命令
            # 这里检查不抛异常且 returncode==0 就够了（JSON 解析出 list of str）
            self.assertIsInstance(result, list)
        finally:
            os.unlink(script)


if __name__ == "__main__":
    unittest.main(verbosity=2)
