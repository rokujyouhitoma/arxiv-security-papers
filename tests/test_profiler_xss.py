"""
tests/test_profiler_xss.py
==========================
PyNYTProf HTML / SVG / Diff レポートにおける XSS サニタイズ完全性検証テスト。
DSN-28 Section 8.4 準拠。
CWE-79 脆弱性（Cross-site Scripting）の完全排除を検証。
"""

import os
import shutil
import tempfile
import unittest

from src.core.profiler.diff import ProfileDiffer
from src.core.profiler.flamegraph import FlameGraphGenerator
from src.core.profiler.reporter import HTMLReporter
from src.core.profiler.storage import (
    LineMetric,
    ProfileData,
    ProfileMetadata,
    SubroutineMetric,
)


class TestPyNYTProfXSSSanitization(unittest.TestCase):
    """HTML / SVG / Diff レポートの XSS サニタイズ検証"""

    def setUp(self):
        self.temp_dir = tempfile.mkdtemp()
        self.xss_payloads = [
            "<script>alert('xss')</script>",
            '"><img src=x onerror=alert(1)>',
            "<svg/onload=alert(1)>",
            "javascript:alert(1)",
        ]

    def tearDown(self):
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def test_flamegraph_svg_xss_sanitization(self):
        """Flame Graph SVG 内の関数名・スタック文字列の XSS サニタイズ検証"""
        fg = FlameGraphGenerator()

        for payload in self.xss_payloads:
            stack_data = {
                f"main;{payload};safe_leaf": 100_000,
            }
            svg = fg.generate_svg(stack_data, title=f"Title: {payload}")

            # 未エスケープのスクリプトタグがそのまま含まれていないこと
            self.assertNotIn("<script>", svg)
            self.assertNotIn("<img", svg)
            self.assertNotIn("<svg/onload", svg)

    def test_html_reporter_xss_sanitization(self):
        """HTMLReporter によるソースコード・関数名・タイトルの XSS サニタイズ検証"""
        reporter = HTMLReporter()

        for payload in self.xss_payloads:
            data = ProfileData(
                metadata=ProfileMetadata(
                    total_time_ns=10_000_000,
                    cmdline=["python", payload],
                )
            )
            # ソースコードに XSS ペイロード
            data.source_files["xss_test.py"] = (
                f"def {payload}():\n    print('{payload}')\n"
            )
            # 関数名に XSS ペイロード
            data.subroutines[payload] = SubroutineMetric(
                name=payload,
                filename="xss_test.py",
                first_line=1,
                calls=1,
                inclusive_time_ns=10_000_000,
                exclusive_time_ns=10_000_000,
            )
            data.lines["xss_test.py"] = {
                1: LineMetric(count=1, time_ns=5_000_000),
                2: LineMetric(count=1, time_ns=5_000_000),
            }

            out_dir = os.path.join(self.temp_dir, f"report_{hash(payload)}")
            index_path = reporter.generate_report(data, out_dir, title=payload)

            self.assertTrue(os.path.exists(index_path))
            with open(index_path, "r", encoding="utf-8") as f:
                index_html = f.read()

            self.assertNotIn("<script>alert", index_html)
            self.assertNotIn("<img src=x", index_html)
            self.assertNotIn("<svg/onload", index_html)

    def test_diff_reporter_xss_sanitization(self):
        """ProfileDiffer による差分 HTML レポートの XSS サニタイズ検証"""
        for payload in self.xss_payloads:
            before = ProfileData(
                metadata=ProfileMetadata(total_time_ns=1_000_000),
            )
            after = ProfileData(
                metadata=ProfileMetadata(total_time_ns=2_000_000),
            )
            before.source_files["app.py"] = f"# {payload}\n"
            after.source_files["app.py"] = f"# {payload}\n"

            before.subroutines[payload] = SubroutineMetric(
                name=payload,
                filename="app.py",
                first_line=1,
                calls=1,
                inclusive_time_ns=1_000_000,
                exclusive_time_ns=1_000_000,
            )
            after.subroutines[payload] = SubroutineMetric(
                name=payload,
                filename="app.py",
                first_line=1,
                calls=1,
                inclusive_time_ns=2_000_000,
                exclusive_time_ns=2_000_000,
            )

            differ = ProfileDiffer.compare_data(before, after)
            out_dir = os.path.join(self.temp_dir, f"diff_{hash(payload)}")
            diff_index = differ.render_html(out_dir, title=payload)

            self.assertTrue(os.path.exists(diff_index))
            with open(diff_index, "r", encoding="utf-8") as f:
                diff_html = f.read()

            self.assertNotIn("<script>alert", diff_html)
            self.assertNotIn("<img src=x", diff_html)
            self.assertNotIn("<svg/onload", diff_html)


if __name__ == "__main__":
    unittest.main()
