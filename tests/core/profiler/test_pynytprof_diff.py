"""
tests/core/test_pynytprof_diff.py
==================================
PyNYTProf 差分プロファイリングエンジン (ProfileDiffer / diff.py) 単体テストスイート。
DSN-28 Section 5.4 準拠。
"""

import os
import shutil
import tempfile
import unittest

from src.core.profiler.diff import LineDiff, ProfileDiffer, SubDiff
from src.core.profiler.storage import (
    LineMetric,
    ProfileData,
    ProfileMetadata,
    ProfileStorage,
    SubroutineMetric,
)


class TestPyNYTProfDiff(unittest.TestCase):
    """ProfileDiffer および SubDiff/LineDiff の単体テスト"""

    def setUp(self):
        self.temp_dir = tempfile.mkdtemp()

    def tearDown(self):
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def test_sub_diff_properties(self):
        """SubDiff のプロパティ計算と差分分類の検証"""
        # 1. Regression (+50% 遅化)
        reg = SubDiff(
            name="func_reg",
            filename="app.py",
            first_line=10,
            before_exclusive_ns=10_000_000,
            after_exclusive_ns=15_000_000,
        )
        self.assertEqual(reg.exclusive_delta_ns, 5_000_000)
        self.assertAlmostEqual(reg.exclusive_ratio, 1.5)
        self.assertEqual(reg.diff_class, "regression")

        # 2. Improvement (-50% 高速化)
        imp = SubDiff(
            name="func_imp",
            filename="app.py",
            first_line=20,
            before_exclusive_ns=10_000_000,
            after_exclusive_ns=5_000_000,
        )
        self.assertEqual(imp.exclusive_delta_ns, -5_000_000)
        self.assertAlmostEqual(imp.exclusive_ratio, 0.5)
        self.assertEqual(imp.diff_class, "improvement")

        # 3. New Hotspot (新規出現)
        new_hot = SubDiff(
            name="func_new",
            filename="app.py",
            first_line=30,
            before_exclusive_ns=0,
            after_exclusive_ns=5_000_000,
        )
        self.assertEqual(new_hot.diff_class, "new-hot")

        # 4. Neutral (変化なしまたは閾値以内)
        neutral = SubDiff(
            name="func_neutral",
            filename="app.py",
            first_line=40,
            before_exclusive_ns=10_000_000,
            after_exclusive_ns=10_500_000,
        )
        self.assertEqual(neutral.diff_class, "neutral")

    def test_line_diff_properties(self):
        """LineDiff のプロパティ計算と差分分類の検証"""
        reg_line = LineDiff(
            filename="app.py",
            lineno=15,
            before_count=100,
            before_time_ns=2_000_000,
            after_count=100,
            after_time_ns=3_000_000,
        )
        self.assertEqual(reg_line.exclusive_delta_ns, 1_000_000)
        self.assertEqual(reg_line.diff_class, "regression")

        imp_line = LineDiff(
            filename="app.py",
            lineno=16,
            before_count=100,
            before_time_ns=2_000_000,
            after_count=100,
            after_time_ns=1_000_000,
        )
        self.assertEqual(imp_line.exclusive_delta_ns, -1_000_000)
        self.assertEqual(imp_line.diff_class, "improvement")

    def test_profile_differ_computation_and_noise_filtering(self):
        """ProfileDiffer の計算とノイズ除去の検証"""
        before_meta = ProfileMetadata(total_time_ns=100_000_000)
        after_meta = ProfileMetadata(total_time_ns=110_000_000)

        before_data = ProfileData(metadata=before_meta)
        after_data = ProfileData(metadata=after_meta)

        # サブルーチン追加
        # 1. 有意な遅化 (10ms -> 20ms)
        before_data.subroutines["heavy_func"] = SubroutineMetric(
            name="heavy_func",
            filename="main.py",
            first_line=10,
            calls=1,
            inclusive_time_ns=10_000_000,
            exclusive_time_ns=10_000_000,
        )
        after_data.subroutines["heavy_func"] = SubroutineMetric(
            name="heavy_func",
            filename="main.py",
            first_line=10,
            calls=1,
            inclusive_time_ns=20_000_000,
            exclusive_time_ns=20_000_000,
        )

        # 2. ノイズ (0.1ms の微小変化: 500,000ns 未満)
        before_data.subroutines["tiny_func"] = SubroutineMetric(
            name="tiny_func",
            filename="main.py",
            first_line=30,
            calls=1,
            inclusive_time_ns=100_000,
            exclusive_time_ns=100_000,
        )
        after_data.subroutines["tiny_func"] = SubroutineMetric(
            name="tiny_func",
            filename="main.py",
            first_line=30,
            calls=1,
            inclusive_time_ns=200_000,
            exclusive_time_ns=200_000,
        )

        # 3. 有意な高速化 (20ms -> 10ms)
        before_data.subroutines["opt_func"] = SubroutineMetric(
            name="opt_func",
            filename="main.py",
            first_line=50,
            calls=1,
            inclusive_time_ns=20_000_000,
            exclusive_time_ns=20_000_000,
        )
        after_data.subroutines["opt_func"] = SubroutineMetric(
            name="opt_func",
            filename="main.py",
            first_line=50,
            calls=1,
            inclusive_time_ns=10_000_000,
            exclusive_time_ns=10_000_000,
        )

        differ = ProfileDiffer.compare_data(before_data, after_data)
        sub_diffs = differ.compute_sub_diffs()

        # tiny_func はノイズとして除外され、heavy_func と opt_func のみ検出されること
        names = [d.name for d in sub_diffs]
        self.assertIn("heavy_func", names)
        self.assertIn("opt_func", names)
        self.assertNotIn("tiny_func", names)

    def test_render_html(self):
        """差分 HTML レポート生成の完全性検証"""
        before_data = ProfileData(
            metadata=ProfileMetadata(total_time_ns=50_000_000),
        )
        before_data.source_files["test.py"] = "def foo():\n    pass\n"
        after_data = ProfileData(
            metadata=ProfileMetadata(total_time_ns=60_000_000),
        )
        after_data.source_files["test.py"] = "def foo():\n    pass\n"

        before_data.subroutines["foo"] = SubroutineMetric(
            name="foo",
            filename="test.py",
            first_line=1,
            calls=10,
            inclusive_time_ns=10_000_000,
            exclusive_time_ns=10_000_000,
        )
        after_data.subroutines["foo"] = SubroutineMetric(
            name="foo",
            filename="test.py",
            first_line=1,
            calls=10,
            inclusive_time_ns=15_000_000,
            exclusive_time_ns=15_000_000,
        )

        before_data.lines["test.py"] = {2: LineMetric(count=10, time_ns=10_000_000)}
        after_data.lines["test.py"] = {2: LineMetric(count=10, time_ns=15_000_000)}

        differ = ProfileDiffer.compare_data(before_data, after_data)
        out_dir = os.path.join(self.temp_dir, "diff_html")
        index_path = differ.render_html(out_dir, title="Test Diff Report")

        self.assertTrue(os.path.exists(index_path))
        with open(index_path, "r", encoding="utf-8") as f:
            content = f.read()

        self.assertIn("Test Diff Report", content)
        self.assertIn("foo", content)
        self.assertIn("regression", content)

    def test_compare_from_files(self):
        """ファイルから ProfileStorage 経由で比較するファクトリの検証"""
        before_file = os.path.join(self.temp_dir, "before.out")
        after_file = os.path.join(self.temp_dir, "after.out")

        p1 = ProfileData(metadata=ProfileMetadata(total_time_ns=1_000_000))
        p2 = ProfileData(metadata=ProfileMetadata(total_time_ns=2_000_000))

        ProfileStorage.save(p1, before_file)
        ProfileStorage.save(p2, after_file)

        differ = ProfileDiffer.compare(before_file, after_file)
        self.assertEqual(differ.before.metadata.total_time_ns, 1_000_000)
        self.assertEqual(differ.after.metadata.total_time_ns, 2_000_000)


if __name__ == "__main__":
    unittest.main()
