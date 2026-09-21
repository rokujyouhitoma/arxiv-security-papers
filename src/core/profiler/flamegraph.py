"""
src/core/profiler/flamegraph.py
===============================
PyNYTProf Pure-Python インタラクティブ Flame Graph SVG 生成器。
DSN-28 Section 5.1 準拠。

- 外部 Perl / flamegraph.pl への依存ゼロ。
- Brendan Gregg 仕様準拠のスタック深度 (Y軸) ＆ 時間比率 (X軸幅) ベクター描画。
- 暖色系ハッシュカラーパレットによる視覚的一貫性。
- クリック可能ハイパーリンク (<a xlink:href="...">) およびツールチップ完備。
"""

from __future__ import annotations

import html
import os
from typing import Any, Dict, List, Optional, Union

from core.profiler.storage import ProfileData


class FlameNode:
    """Flame Graph 用のコールスタックツリーノード"""

    def __init__(self, name: str) -> None:
        self.name = name
        self.total_time_ns: int = 0
        self.children: Dict[str, FlameNode] = {}

    def add_stack(self, parts: List[str], time_ns: int) -> None:
        """スタック経路に時間を加算"""
        self.total_time_ns += time_ns
        if not parts:
            return
        head = parts[0]
        tail = parts[1:]
        if head not in self.children:
            self.children[head] = FlameNode(head)
        self.children[head].add_stack(tail, time_ns)


class FlameGraphGenerator:
    """
    Pure Python Flame Graph SVG 生成エンジン。
    """

    DEFAULT_WIDTH = 1200
    ROW_HEIGHT = 16
    FONT_SIZE = 12

    def __init__(self, width: int = DEFAULT_WIDTH) -> None:
        self.width = width
        self.row_height = self.ROW_HEIGHT
        self.font_size = self.FONT_SIZE

    @staticmethod
    def _hsl_to_rgb(hue: float, sat: float, lum: float) -> str:
        """HSL から RGB 文字列へ変換"""
        c = (1.0 - abs(2.0 * (lum / 100.0) - 1.0)) * (sat / 100.0)
        x = c * (1.0 - abs((hue / 60.0) % 2.0 - 1.0))
        m = (lum / 100.0) - c / 2.0
        r1, g1, b1 = (c, x, 0.0) if hue < 60 else (x, c, 0.0)
        r = int((r1 + m) * 255)
        g = int((g1 + m) * 255)
        b = int((b1 + m) * 255)
        return f"rgb({r}, {g}, {b})"

    @classmethod
    def _get_hash_color(cls, name: str) -> str:
        """関数名に基づいて暖色系カラーコードを一意に算出"""
        if name.startswith("CORE:"):
            return "rgb(180, 140, 220)"
        if name in ("<root>", "all"):
            return "rgb(230, 230, 230)"

        h_val = sum(ord(c) * (i + 1) for i, c in enumerate(name))
        hue = 10 + (h_val % 48)
        sat = 70 + ((h_val >> 3) % 25)
        lum = 50 + ((h_val >> 6) % 25)
        return cls._hsl_to_rgb(hue, sat, lum)

    @staticmethod
    def _format_time(ns: int) -> str:
        """ナノ秒を読みやすい単位にフォーマット"""
        if ns < 1_000:
            return f"{ns} ns"
        if ns < 1_000_000:
            return f"{ns / 1_000:.2f} µs"
        if ns < 1_000_000_000:
            return f"{ns / 1_000_000:.2f} ms"
        return f"{ns / 1_000_000_000:.3f} s"

    def build_tree(self, stack_data: Dict[str, int]) -> FlameNode:
        """セミコロン区切りコールスタック辞書から FlameNode ツリーを構築"""
        root = FlameNode("all")
        for stack_str, time_ns in stack_data.items():
            parts = [p.strip() for p in stack_str.split(";") if p.strip()]
            if parts:
                root.add_stack(parts, time_ns)
        return root

    def get_max_depth(self, node: FlameNode, current_depth: int = 1) -> int:
        """ツリーの最大スタック深度を取得"""
        if not node.children:
            return current_depth
        return max(
            self.get_max_depth(child, current_depth + 1)
            for child in node.children.values()
        )

    @staticmethod
    def _parse_source_lines(lines_iter: Any) -> Dict[str, int]:
        """行テキストからスタック辞書を抽出"""
        stack_data: Dict[str, int] = {}
        for line in lines_iter:
            line = line.strip()
            if not line or " " not in line:
                continue
            stack, t_str = line.rsplit(" ", 1)
            try:
                stack_data[stack] = int(t_str)
            except ValueError:
                pass
        return stack_data

    @classmethod
    def _parse_source_data(
        cls, source: Union[ProfileData, Dict[str, int], str]
    ) -> Dict[str, int]:
        """入力をスタック辞書へ正規化"""
        if isinstance(source, ProfileData):
            return source.stack_traces
        if isinstance(source, dict):
            return source
        if isinstance(source, str):
            if os.path.isfile(source):
                with open(source, "r", encoding="utf-8") as f:
                    return cls._parse_source_lines(f)
            return cls._parse_source_lines(source.splitlines())
        return {}

    def _render_rect(
        self,
        node: FlameNode,
        depth: int,
        x_start: float,
        x_width: float,
        y: float,
        link_url: str,
        total_time: int,
    ) -> str:
        """単一のFlameブロックSVG要素を生成"""
        color = self._get_hash_color(node.name)
        escaped_name = html.escape(node.name)
        time_str = self._format_time(node.total_time_ns)
        pct = (node.total_time_ns / total_time) * 100.0
        # <title> はテキストコンテンツなので html.escape 済みで問題なし
        tooltip = f"{escaped_name} ({time_str}, {pct:.2f}%)"
        # 属性値に埋め込む URL は必ずエスケープ（<root> など角括弧を含む関数名対策）
        escaped_link = html.escape(link_url, quote=True)
        rect_w = max(0.5, x_width - 1.0)

        element = (
            f'<g class="func_g">'
            f"<title>{tooltip}</title>"
            f'<a xlink:href="{escaped_link}" target="_top">'
            f'<rect x="{x_start:.2f}" y="{y:.2f}" width="{rect_w:.2f}" height="{self.row_height - 1}" '
            f'fill="{color}" rx="2" ry="2" stroke="#ffffff" stroke-width="0.5"/>'
        )
        if rect_w > 30:
            # split('.') で得られる末尾部分にも <> が含まれる可能性があるためエスケープ
            short_name = html.escape(node.name.split(".")[-1])
            element += (
                f'<text x="{x_start + 4:.2f}" y="{y + 11:.2f}" '
                f'font-family="sans-serif" font-size="{self.font_size - 2}" fill="#111111" '
                f'clip-path="url(#clip_{depth}_{int(x_start)})">{short_name}</text>'
            )
        return element + "</a></g>"

    def generate_svg(
        self,
        source: Union[ProfileData, Dict[str, int], str],
        title: str = "PyNYTProf - Interactive Flame Graph",
        link_prefix: str = "source_details.html#",
        sub_link_map: Optional[Dict[str, str]] = None,
    ) -> str:
        """インタラクティブ Flame Graph SVG を生成"""
        stack_data = self._parse_source_data(source)
        if not stack_data:
            return (
                f'<svg xmlns="http://www.w3.org/2000/svg" width="{self.width}" height="60">'
                f'<rect width="100%" height="100%" fill="#f8f9fa"/>'
                f'<text x="20" y="35" font-family="sans-serif" font-size="14" fill="#6c757d">'
                f"No stack trace data available.</text></svg>"
            )

        root = self.build_tree(stack_data)
        total_time = root.total_time_ns or 1
        padding_x: float = 10.0
        canvas_width: float = float(self.width)
        canvas_height = (self.get_max_depth(root) + 2) * self.row_height + 40
        elements: List[str] = []

        def render_node(node: FlameNode, depth: int, x: float, w: float) -> None:
            if w < 0.5 or node.total_time_ns <= 0:
                return
            if sub_link_map and node.name in sub_link_map:
                link = sub_link_map[node.name]
            elif link_prefix:
                link = link_prefix + node.name
            else:
                link = ""
            y = canvas_height - 25 - (depth * self.row_height)
            elements.append(self._render_rect(node, depth, x, w, y, link, total_time))
            child_x = x
            for child_node in node.children.values():
                child_w = w * (child_node.total_time_ns / node.total_time_ns)
                render_node(child_node, depth + 1, child_x, child_w)
                child_x += child_w

        # ルートから再帰レンダリング
        render_node(root, 0, padding_x, canvas_width - (2 * padding_x))

        svg_header = (
            f'<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" '
            f'width="{canvas_width}" height="{canvas_height}" viewBox="0 0 {canvas_width} {canvas_height}">'
        )
        title_text = f"{html.escape(title)} (Total: {self._format_time(total_time)})"
        svg_content = f"""{svg_header}
<style>
    .func_g rect {{ transition: fill 0.15s ease, opacity 0.15s ease; cursor: pointer; }}
    .func_g:hover rect {{ opacity: 0.8; stroke: #000000; stroke-width: 1.2px; }}
    .func_g text {{ pointer-events: none; font-weight: 500; }}
</style>
<rect width="100%" height="100%" fill="#ffffff" rx="4"/>
<text x="12" y="18" font-family="sans-serif" font-size="14" font-weight="bold" fill="#212529">{title_text}</text>
<g id="frames">
{''.join(elements)}
</g>
</svg>"""
        return svg_content
