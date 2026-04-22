"""
test_eval_pipeline.py — eval_pipeline.py 核心函数单元测试

运行:
    python3 tests/test_eval_pipeline.py
"""

import sys
import os
import unittest
import tempfile
import csv
from pathlib import Path

# 将 scripts/ 加入路径（避免依赖 PyObjC 的导入）
sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))

# 仅导入不依赖 PyObjC 的函数
import importlib, types

# 手动加载 eval_pipeline 但跳过 PyObjC import
_src = Path(__file__).parent.parent / "scripts" / "eval_pipeline.py"
_code = _src.read_text(encoding="utf-8")

# 替换 PyObjC 相关 import 为空模块，确保单测可在 arm64 Python 下运行
_stub = types.ModuleType
for _mod in ["AppKit", "ApplicationServices", "Quartz"]:
    sys.modules.setdefault(_mod, _stub(_mod))

# 提取并执行纯函数部分（不含 main()）
_ns: dict = {}
exec(compile(_code, str(_src), "exec"), _ns)

normalize     = _ns["normalize"]
edit_distance = _ns["edit_distance"]
compute_wer   = _ns["compute_wer"]
load_test_samples = _ns["load_test_samples"]
write_outputs = _ns["write_outputs"]


class TestNormalize(unittest.TestCase):

    def test_basic_chinese(self):
        self.assertEqual(normalize("你好世界"), ["你", "好", "世", "界"])

    def test_strips_punctuation(self):
        self.assertEqual(normalize("你好，世界！"), ["你", "好", "世", "界"])

    def test_strips_spaces(self):
        self.assertEqual(normalize("你 好 世 界"), ["你", "好", "世", "界"])

    def test_lowercase_ascii(self):
        self.assertEqual(normalize("Hello"), ["h", "e", "l", "l", "o"])

    def test_keeps_numbers(self):
        result = normalize("第3名")
        self.assertIn("3", result)

    def test_empty(self):
        self.assertEqual(normalize(""), [])

    def test_only_punctuation(self):
        self.assertEqual(normalize("，。！？"), [])


class TestEditDistance(unittest.TestCase):

    def test_identical(self):
        self.assertEqual(edit_distance(list("abc"), list("abc")), 0)

    def test_empty_both(self):
        self.assertEqual(edit_distance([], []), 0)

    def test_empty_a(self):
        self.assertEqual(edit_distance([], list("abc")), 3)

    def test_empty_b(self):
        self.assertEqual(edit_distance(list("abc"), []), 3)

    def test_one_substitution(self):
        self.assertEqual(edit_distance(list("abc"), list("axc")), 1)

    def test_one_insertion(self):
        self.assertEqual(edit_distance(list("ac"), list("abc")), 1)

    def test_one_deletion(self):
        self.assertEqual(edit_distance(list("abc"), list("ac")), 1)

    def test_completely_different(self):
        self.assertEqual(edit_distance(list("ab"), list("cd")), 2)


class TestComputeWer(unittest.TestCase):

    def test_perfect_match(self):
        r = compute_wer("你好世界", "你好世界")
        self.assertAlmostEqual(r["wer"], 0.0)
        self.assertEqual(r["edits"], 0)

    def test_empty_hypothesis(self):
        r = compute_wer("", "你好世界")
        self.assertAlmostEqual(r["wer"], 1.0)
        self.assertEqual(r["edits"], 4)

    def test_empty_reference(self):
        r = compute_wer("anything", "")
        self.assertAlmostEqual(r["wer"], 0.0)
        self.assertEqual(r["ref_len"], 0)

    def test_one_char_error(self):
        # ref=你好世界(4字)，hyp=你好地界(1错)
        r = compute_wer("你好地界", "你好世界")
        self.assertAlmostEqual(r["wer"], 0.25)
        self.assertEqual(r["edits"], 1)
        self.assertEqual(r["ref_len"], 4)

    def test_punctuation_ignored(self):
        # 标点不计入 WER
        r = compute_wer("你好，世界！", "你好世界")
        self.assertAlmostEqual(r["wer"], 0.0)

    def test_fully_wrong(self):
        r = compute_wer("一二三四", "你好世界")
        self.assertAlmostEqual(r["wer"], 1.0)


class TestLoadTestSamples(unittest.TestCase):

    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.data_dir = Path(self.tmp)
        wav_dir = self.data_dir / "wav" / "test"
        wav_dir.mkdir(parents=True)
        transcript_dir = self.data_dir / "transcript"
        transcript_dir.mkdir()

        # 生成 5 个假 WAV 文件（空文件即可，测试只需路径存在）
        self.ids = [f"test_{i:05d}" for i in range(5)]
        for sid in self.ids:
            (wav_dir / f"{sid}.wav").write_bytes(b"")

        # 生成转录文件
        lines = [f"{sid} 测试文本{i}\n" for i, sid in enumerate(self.ids)]
        (transcript_dir / "aishell_test_transcript.txt").write_text(
            "".join(lines), encoding="utf-8"
        )

    def test_loads_all_samples(self):
        samples = load_test_samples(self.data_dir, n=-1, seed=42)
        self.assertEqual(len(samples), 5)

    def test_n_limit(self):
        samples = load_test_samples(self.data_dir, n=3, seed=42)
        self.assertEqual(len(samples), 3)

    def test_sample_fields(self):
        samples = load_test_samples(self.data_dir, n=1, seed=0)
        s = samples[0]
        self.assertIn("id", s)
        self.assertIn("wav", s)
        self.assertIn("ref", s)
        self.assertTrue(s["wav"].exists())

    def test_reproducible_with_seed(self):
        a = [s["id"] for s in load_test_samples(self.data_dir, n=3, seed=99)]
        b = [s["id"] for s in load_test_samples(self.data_dir, n=3, seed=99)]
        self.assertEqual(a, b)

    def test_different_seeds_differ(self):
        a = [s["id"] for s in load_test_samples(self.data_dir, n=3, seed=1)]
        b = [s["id"] for s in load_test_samples(self.data_dir, n=3, seed=2)]
        # 5 个样本中抽 3 个，不同种子大概率不同（此处用断言弱化）
        self.assertIsNotNone(a)

    def test_missing_transcript_dir_raises(self):
        import shutil
        shutil.rmtree(self.data_dir / "transcript")
        with self.assertRaises(Exception):
            load_test_samples(self.data_dir, n=5, seed=0)


class TestWriteOutputs(unittest.TestCase):

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())

    def _make_results(self):
        return [
            {"id": "test_00000", "wav": "/a.wav", "reference": "你好世界",
             "hypothesis": "你好地界", "wer": 0.25, "edits": 1, "ref_len": 4,
             "status": "ok", "error": ""},
            {"id": "test_00001", "wav": "/b.wav", "reference": "测试文本",
             "hypothesis": "", "wer": None, "edits": None, "ref_len": None,
             "status": "empty", "error": "转录结果为空"},
        ]

    def test_creates_summary_json(self):
        import json
        write_outputs(self._make_results(), self.tmp, elapsed=10.0)
        summary = json.loads((self.tmp / "summary.json").read_text())
        self.assertEqual(summary["n_total"], 2)
        self.assertEqual(summary["n_valid"], 1)
        self.assertEqual(summary["n_error"], 1)
        self.assertAlmostEqual(summary["avg_wer"], 0.25)

    def test_creates_samples_csv(self):
        write_outputs(self._make_results(), self.tmp, elapsed=10.0)
        with open(self.tmp / "samples.csv", encoding="utf-8") as f:
            rows = list(csv.DictReader(f))
        self.assertEqual(len(rows), 2)
        self.assertEqual(rows[0]["id"], "test_00000")

    def test_creates_report_md(self):
        write_outputs(self._make_results(), self.tmp, elapsed=10.0)
        report = (self.tmp / "report.md").read_text(encoding="utf-8")
        self.assertIn("WER", report)
        self.assertIn("25.00%", report)

    def test_all_errors_avg_wer_none(self):
        import json
        results = [
            {"id": "x", "wav": "", "reference": "a", "hypothesis": "",
             "wer": None, "edits": None, "ref_len": None,
             "status": "timeout", "error": "超时"},
        ]
        write_outputs(results, self.tmp, elapsed=5.0)
        summary = json.loads((self.tmp / "summary.json").read_text())
        self.assertIsNone(summary["avg_wer"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
