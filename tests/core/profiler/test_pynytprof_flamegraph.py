"""
tests/core/test_pynytprof_flamegraph.py
=======================================
PyNYTProf Pure-Python Flame Graph SVG 生成器の包括的テストスイート。
DSN-28 Section 5.1 & Section 8 準拠。
ゼロ外部依存: Python 標準 unittest & xml.etree.ElementTree ベース。
"""

import unittest
import xml.etree.ElementTree as ET

from src.core.profiler import FlameGraphGenerator, Profiler


class TestPyNYTProfFlameGraph(unittest.TestCase):
    """Flame Graph 生成器の単体テスト"""

    def setUp(self):
        self.generator = FlameGraphGenerator(width=1000)

    def test_tree_construction(self):
        """スタックツリーの構築と累積時間集計の検証"""
        stack_data = {
            "main;foo": 500_000,
            "main;foo;bar": 300_000,
            "main;baz": 200_000,
        }
        root = self.generator.build_tree(stack_data)

        self.assertEqual(root.name, "all")
        self.assertEqual(root.total_time_ns, 1_000_000)
        self.assertIn("main", root.children)

        main_node = root.children["main"]
        self.assertEqual(main_node.total_time_ns, 1_000_000)
        self.assertIn("foo", main_node.children)
        self.assertIn("baz", main_node.children)

        foo_node = main_node.children["foo"]
        self.assertEqual(foo_node.total_time_ns, 800_000)
        self.assertIn("bar", foo_node.children)

    def test_generate_svg_structure_and_validity(self):
        """生成された SVG が有効な XML であり、各要素を正しく含むことの検証"""
        stack_data = {
            "entrypoint;process": 400_000,
            "entrypoint;process;CORE:read": 200_000,
            "entrypoint;cleanup": 100_000,
        }
        svg_text = self.generator.generate_svg(stack_data, title="Test Benchmark")

        self.assertTrue(svg_text.startswith("<svg"))
        self.assertTrue(svg_text.endswith("</svg>"))

        # XML パースによる構文妥当性検証
        # xlink 名前空間付きでパース
        root_el = ET.fromstring(svg_text)
        self.assertEqual(root_el.tag.split("}")[-1], "svg")

        # タイトル要素
        self.assertIn("Test Benchmark", svg_text)
        # クリック可能リンク
        self.assertIn("xlink:href", svg_text)
        self.assertIn("source_details.html#process", svg_text)
        # ツールチップ
        self.assertIn("<title>", svg_text)
        self.assertIn("CORE:read", svg_text)
        # 暖色系カラー
        self.assertIn("rgb(", svg_text)

    def test_calls_text_format_parsing(self):
        """all_stacks_by_time.calls 形式の複数行テキストからの生成検証"""
        raw_calls = "main;step1 1000\n" "main;step1;sub_a 600\n" "main;step2 400\n"
        svg_text = self.generator.generate_svg(raw_calls, title="From Calls File")
        self.assertIn("step1", svg_text)
        self.assertIn("step2", svg_text)
        self.assertIn("<svg", svg_text)

    def test_empty_stack_data_fallback(self):
        """空データ時のプレースホルダー SVG 生成検証"""
        svg_text = self.generator.generate_svg({}, title="Empty")
        self.assertIn("No stack trace data available.", svg_text)
        self.assertIn("<svg", svg_text)

    def test_e2e_flamegraph_generation_from_profiler(self):
        """Profiler 実行結果 (ProfileData) からの直接 Flame Graph 生成検証"""

        def sub_b():
            return sum(range(50))

        def sub_a():
            return sub_b() * 2

        with Profiler(mode="line", calls_mode=1) as p:
            val = sub_a()
            self.assertGreater(val, 0)

        data = p.profile_data
        self.assertIsNotNone(data)

        svg_text = self.generator.generate_svg(data, title="Live Execution")
        self.assertIn("sub_a", svg_text)
        self.assertIn("sub_b", svg_text)
        self.assertIn("Live Execution", svg_text)


if __name__ == "__main__":
    unittest.main()
