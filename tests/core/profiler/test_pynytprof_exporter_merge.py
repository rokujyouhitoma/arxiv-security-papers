"""
tests/core/test_pynytprof_exporter_merge.py
===========================================
PyNYTProf Callgrind エクスポータ ＆ マルチプロセスマージエンジンのテストスイート。
DSN-28 Section 6.1, 6.2 & Section 8 準拠。
ゼロ外部依存: Python 標準 unittest ベース。
"""

import os
import tempfile
import unittest

from src.core.profiler import (
    CallgrindExporter,
    FlameGraphGenerator,
    HTMLReporter,
    ProfileMerger,
    Profiler,
)


def task_a(n: int) -> int:
    return sum(i * 2 for i in range(n))


def task_b(n: int) -> int:
    return sum(i * 3 for i in range(n))


class TestPyNYTProfExporterMerge(unittest.TestCase):
    """Callgrind エクスポートおよびマージの単体テスト"""

    def test_callgrind_exporter_format(self):
        """Callgrind 形式テキスト出力の書式および必須フィールドの検証"""
        with Profiler(mode="line") as p:
            val = task_a(50)
            self.assertGreater(val, 0)

        data = p.profile_data
        self.assertIsNotNone(data)

        with tempfile.TemporaryDirectory() as tmpdir:
            cg_file = os.path.join(tmpdir, "callgrind.out.1234")
            CallgrindExporter.export(data, cg_file)

            self.assertTrue(os.path.isfile(cg_file))
            with open(cg_file, "r", encoding="utf-8") as f:
                content = f.read()
                # 必須ヘッダー
                self.assertIn("version: 1", content)
                self.assertIn("creator: PyNYTProf (DSN-28)", content)
                self.assertIn("events: Nanoseconds", content)
                self.assertIn("summary:", content)
                self.assertIn("fl=", content)
                self.assertIn("fn=", content)
                self.assertIn("task_a", content)

    def test_profile_merger_arithmetic_precision(self):
        """複数プロファイルの合算マージにおける回数・時間の算術的一致検証"""
        # プロファイル 1
        with Profiler(mode="line", calls_mode=1) as p1:
            task_a(20)
        prof1 = p1.profile_data
        self.assertIsNotNone(prof1)

        # プロファイル 2
        with Profiler(mode="line", calls_mode=1) as p2:
            task_b(30)
            task_a(20)
        prof2 = p2.profile_data
        self.assertIsNotNone(prof2)

        # マージ実行
        merged = ProfileMerger.merge_profiles([prof1, prof2])
        self.assertIsNotNone(merged)

        # サブルーチン集計の検証
        # task_a は両方で呼ばれているため、calls の合計に一致
        sub_a1 = next((s for n, s in prof1.subroutines.items() if "task_a" in n), None)
        sub_a2 = next((s for n, s in prof2.subroutines.items() if "task_a" in n), None)
        self.assertIsNotNone(sub_a1)
        self.assertIsNotNone(sub_a2)

        merged_sub_a = next(s for n, s in merged.subroutines.items() if "task_a" in n)
        self.assertEqual(merged_sub_a.calls, sub_a1.calls + sub_a2.calls)
        self.assertEqual(
            merged_sub_a.inclusive_time_ns,
            sub_a1.inclusive_time_ns + sub_a2.inclusive_time_ns,
        )
        self.assertEqual(
            merged_sub_a.exclusive_time_ns,
            sub_a1.exclusive_time_ns + sub_a2.exclusive_time_ns,
        )

        # task_b もマージ結果に存在すること
        self.assertTrue(any("task_b" in n for n in merged.subroutines))

        # コールスタックストリームも合算されていること
        self.assertGreater(len(merged.stack_traces), 0)

    def test_merge_files_end_to_end(self):
        """ファイル保存された複数プロファイルのロード・マージ・レポート生成 E2E 検証"""
        with tempfile.TemporaryDirectory() as tmpdir:
            f1 = os.path.join(tmpdir, "p1.out")
            f2 = os.path.join(tmpdir, "p2.out")
            f_merged = os.path.join(tmpdir, "merged.out")

            with Profiler(output_file=f1):
                task_a(10)
            with Profiler(output_file=f2):
                task_b(10)

            # ファイルベースのマージ
            merged = ProfileMerger.merge_files([f1, f2], output_file=f_merged)
            self.assertTrue(os.path.isfile(f_merged))

            # マージ結果からの Flame Graph 生成
            svg = FlameGraphGenerator().generate_svg(merged)
            self.assertIn("task_a", svg)
            self.assertIn("task_b", svg)

            # マージ結果からの HTML レポート生成
            report_dir = os.path.join(tmpdir, "html")
            index_path = HTMLReporter().generate_report(merged, report_dir)
            self.assertTrue(os.path.isfile(index_path))


if __name__ == "__main__":
    unittest.main()
