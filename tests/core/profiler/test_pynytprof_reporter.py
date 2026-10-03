"""
tests/core/test_pynytprof_reporter.py
=====================================
PyNYTProf HTML レポート生成器の包括的テストスイート。
DSN-28 Section 5.2, 5.3 & Section 8 準拠。
ゼロ外部依存: Python 標準 unittest ベース。
"""

import os
import tempfile
import unittest

from src.core.profiler import HTMLReporter, Profiler
from src.core.profiler.storage import ProfileData, ProfileMetadata


def dummy_caller(x: int) -> int:
    return dummy_callee(x) + 1


def dummy_callee(x: int) -> int:
    return x * 2


class TestPyNYTProfReporter(unittest.TestCase):
    """HTMLReporter の単体テスト"""

    def setUp(self):
        self.reporter = HTMLReporter()

    def test_full_report_generation(self):
        """プロファイリング実行から完全な HTML レポート群が生成されることの検証"""
        with Profiler(mode="line", calls_mode=1) as p:
            val = dummy_caller(10)
            self.assertEqual(val, 21)

        data = p.profile_data
        self.assertIsNotNone(data)

        with tempfile.TemporaryDirectory() as tmpdir:
            index_path = self.reporter.generate_report(
                data, tmpdir, title="Unit Test Run"
            )

            self.assertTrue(os.path.isfile(index_path))
            self.assertTrue(index_path.endswith("index.html"))

            # index.html の検証
            with open(index_path, "r", encoding="utf-8") as f:
                index_html = f.read()
                self.assertIn("Unit Test Run", index_html)
                self.assertIn("Interactive Flame Graph", index_html)
                self.assertIn("<svg", index_html)
                self.assertIn("Top Subroutines by Exclusive Time", index_html)
                self.assertIn("dummy_caller", index_html)
                self.assertIn("dummy_callee", index_html)

            # source_*.html の検証
            source_files = [
                f
                for f in os.listdir(tmpdir)
                if f.startswith("source_") and f.endswith(".html")
            ]
            self.assertGreater(len(source_files), 0)

            first_source = os.path.join(tmpdir, source_files[0])
            with open(first_source, "r", encoding="utf-8") as f:
                source_html = f.read()
                self.assertIn("Subroutines & Call Arcs", source_html)
                self.assertIn("Source Code", source_html)
                self.assertIn("heat-", source_html)
                self.assertIn("Callers", source_html)
                self.assertIn("Callees", source_html)

    def test_xss_sanitization(self):
        """悪意ある関数名・文字列に対する 100% XSS 無害化の検証"""
        meta = ProfileMetadata(python_version="3.12 <script>alert(1)</script>")
        data = ProfileData(metadata=meta)
        malicious_sub = "<script>alert('pwned')</script>"
        data.record_subroutine_exit(
            sub_name=malicious_sub,
            filename="<root>",
            first_line=1,
            caller_name="<img src=x onerror=alert(2)>",
            inclusive_ns=1000,
            exclusive_ns=500,
        )

        with tempfile.TemporaryDirectory() as tmpdir:
            index_path = self.reporter.generate_report(data, tmpdir)
            with open(index_path, "r", encoding="utf-8") as f:
                content = f.read()
                # 生のスクリプトタグが含まれていないこと
                self.assertNotIn("<script>alert(1)</script>", content)
                self.assertNotIn("<script>alert('pwned')</script>", content)
                self.assertNotIn("<img src=x onerror=alert(2)>", content)
                # エスケープされていること
                self.assertIn("&lt;script&gt;", content)

    def test_zero_external_network_dependencies(self):
        """外部 CDN へのスクリプト・CSS・画像通信が一切含まれていないことの検証"""
        with Profiler(mode="line") as p:
            dummy_callee(5)

        with tempfile.TemporaryDirectory() as tmpdir:
            index_path = self.reporter.generate_report(p.profile_data, tmpdir)
            with open(index_path, "r", encoding="utf-8") as f:
                content = f.read()
                # 外部CDNからの読み込み（<link href="http", <script src="http" 等）が存在しないこと
                self.assertNotIn('src="http', content)
                self.assertNotIn('src="//', content)
                self.assertNotIn(
                    'href="http://', content.replace("http://www.w3.org", "")
                )

    def test_flamegraph_links_resolved(self):
        """Flame Graph 内のリンクが有効なソースコードまたはアンカーに解決されていることの検証"""
        with Profiler(mode="line", calls_mode=1) as p:
            val = dummy_caller(10)
            self.assertEqual(val, 21)

        with tempfile.TemporaryDirectory() as tmpdir:
            index_path = self.reporter.generate_report(p.profile_data, tmpdir)
            with open(index_path, "r", encoding="utf-8") as f:
                content = f.read()

            import re

            # xlink:href 属性を抽出
            links = re.findall(r'xlink:href="([^"]+)"', content)
            self.assertGreater(len(links), 0)
            for link in links:
                # リンクは source_*.html#... または #sub_... でなければならない
                self.assertTrue(
                    link.startswith("source_") or link.startswith("#sub_"),
                    f"Broken flamegraph link detected: {link}",
                )


if __name__ == "__main__":
    unittest.main()
