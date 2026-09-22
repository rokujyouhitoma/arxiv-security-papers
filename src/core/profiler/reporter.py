"""
src/core/profiler/reporter.py
=============================
PyNYTProf ヒートマップ付きソースコード HTML アノテータ ＆ Caller/Callee 双方向レポート生成器。
DSN-28 Section 5.2 & Section 5.3 準拠。

- 外部 CDN 不要の自己完結型 HTML/CSS/SVG レポート出力。
- 行単位消費時間に応じた 6 段階ヒートマップ表示。
- Caller (呼び出し元) / Callee (呼び出し先) 双方向解析テーブル。
- インライン Flame Graph 統合。
- 100% XSS サニタイズ。
"""

from __future__ import annotations

import hashlib
import html
import os
from typing import Any, Dict, List, Tuple

from core.profiler.flamegraph import FlameGraphGenerator
from core.profiler.storage import ProfileData


class HTMLReporter:
    """
    自己完結型 PyNYTProf HTML レポートビルダー。
    """

    CSS_STYLES = """
    :root {
        --bg-color: #f8f9fa;
        --card-bg: #ffffff;
        --text-color: #212529;
        --text-muted: #6c757d;
        --border-color: #dee2e6;
        --primary-color: #0d6efd;
        --table-header: #e9ecef;
        --code-font: 'JetBrains Mono', 'Fira Code', Menlo, Monaco, Consolas, monospace;
    }
    body {
        margin: 0;
        padding: 20px;
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
        background-color: var(--bg-color);
        color: var(--text-color);
        line-height: 1.5;
    }
    .container {
        max-width: 1400px;
        margin: 0 auto;
    }
    header {
        margin-bottom: 24px;
        border-bottom: 2px solid var(--border-color);
        padding-bottom: 12px;
    }
    h1, h2, h3 { margin-top: 0; }
    .meta-grid {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
        gap: 16px;
        margin-bottom: 24px;
    }
    .card {
        background: var(--card-bg);
        border: 1px solid var(--border-color);
        border-radius: 6px;
        padding: 16px;
        box-shadow: 0 1px 3px rgba(0,0,0,0.05);
    }
    .card-label { font-size: 12px; color: var(--text-muted); text-transform: uppercase; font-weight: bold; }
    .card-value { font-size: 20px; font-weight: bold; margin-top: 4px; }
    .section-box {
        background: var(--card-bg);
        border: 1px solid var(--border-color);
        border-radius: 6px;
        padding: 20px;
        margin-bottom: 24px;
    }
    table {
        width: 100%;
        border-collapse: collapse;
        margin-top: 12px;
        font-size: 14px;
    }
    th, td {
        padding: 8px 12px;
        text-align: left;
        border-bottom: 1px solid var(--border-color);
    }
    th { background: var(--table-header); font-weight: 600; }
    tr:hover { background-color: rgba(0,0,0,0.02); }
    .num { text-align: right; font-family: var(--code-font); }
    a { color: var(--primary-color); text-decoration: none; }
    a:hover { text-decoration: underline; }
    .badge {
        display: inline-block;
        padding: 2px 6px;
        font-size: 11px;
        font-weight: 600;
        border-radius: 4px;
        background: #e9ecef;
    }
    /* ソースコードテーブル */
    .source-table {
        font-family: var(--code-font);
        font-size: 13px;
        line-height: 1.4;
    }
    .source-table td { padding: 3px 8px; vertical-align: top; }
    .line-no { color: var(--text-muted); text-align: right; width: 50px; user-select: none; }
    .line-count { width: 60px; text-align: right; color: var(--text-muted); }
    .line-time { width: 90px; text-align: right; }
    .line-code { white-space: pre-wrap; word-break: break-all; }

    /* ヒートマップ背景色 */
    .heat-0 { background: transparent; }
    .heat-1 { background-color: #ffffcc; }
    .heat-2 { background-color: #ffe599; }
    .heat-3 { background-color: #f6b26b; }
    .heat-4 { background-color: #e69138; }
    .heat-5 { background-color: #cc4125; color: #ffffff !important; font-weight: bold; }
    .heat-5 a { color: #ffffff !important; }
    /* 最適化ヒント (DSN-28 Section 5.5) */
    .hint-icon { cursor: help; font-size: 12px; margin-left: 6px; }
    .hint-wrap { position: relative; display: inline-block; }
    .hint-wrap .hint-tip {
        visibility: hidden;
        background: #212529;
        color: #f8f9fa;
        font-size: 11px;
        padding: 4px 8px;
        border-radius: 4px;
        white-space: nowrap;
        position: absolute;
        z-index: 100;
        bottom: 125%;
        left: 50%;
        transform: translateX(-50%);
        pointer-events: none;
    }
    .hint-wrap:hover .hint-tip { visibility: visible; }
    """

    HEAT_THRESHOLDS = (
        (30.0, "heat-5"),
        (15.0, "heat-4"),
        (5.0, "heat-3"),
        (1.0, "heat-2"),
        (0.1, "heat-1"),
    )

    @classmethod
    def _format_time(cls, ns: int) -> str:
        """ナノ秒を可読な単位 (s, ms, µs, ns) に変換"""
        if ns >= 1_000_000_000:
            return f"{ns / 1_000_000_000:.3f}s"
        if ns >= 1_000_000:
            return f"{ns / 1_000_000:.2f}ms"
        if ns >= 1_000:
            return f"{ns / 1_000:.1f}µs"
        return f"{ns}ns"

    @classmethod
    def _get_heat_class(cls, line_time_ns: int, total_time_ns: int) -> str:
        """消費時間比率に応じたヒートマップ CSS クラスを判定"""
        if total_time_ns <= 0 or line_time_ns <= 0:
            return "heat-0"
        pct = (line_time_ns / total_time_ns) * 100.0
        for threshold, heat_class in cls.HEAT_THRESHOLDS:
            if pct >= threshold:
                return heat_class
        return "heat-0"

    @classmethod
    def _file_to_slug(cls, filepath: str) -> str:
        """ファイルパスから一意で安全な HTML ファイル名を生成"""
        if not filepath or filepath in ("<root>", "<built-in>"):
            return "special"
        h = hashlib.md5(filepath.encode("utf-8")).hexdigest()[:8]
        base = os.path.basename(filepath).replace(".", "_")
        return f"source_{base}_{h}.html"

    @staticmethod
    def _resolve_total_time(profile: ProfileData) -> int:
        """プロファイルデータから全体の計測時間を解決"""
        total = profile.metadata.total_time_ns
        if total <= 0 and profile.subroutines:
            total = max(
                (s.inclusive_time_ns for s in profile.subroutines.values()), default=1
            )
        return max(total, 1)

    def generate_report(
        self,
        profile: ProfileData,
        output_dir: str,
        title: str = "PyNYTProf Performance Report",
    ) -> str:
        """自己完結型 HTML レポート一式を出力"""
        os.makedirs(output_dir, exist_ok=True)
        total_time_ns = self._resolve_total_time(profile)

        file_slug_map = {
            fname: self._file_to_slug(fname) for fname in profile.source_files.keys()
        }

        for filepath, content in profile.source_files.items():
            slug = file_slug_map[filepath]
            out_path = os.path.join(output_dir, slug)
            self._generate_source_page(
                filepath, content, profile, total_time_ns, out_path, title
            )

        index_path = os.path.join(output_dir, "index.html")
        self._generate_index_page(
            profile, total_time_ns, index_path, title, file_slug_map
        )
        return index_path

    @classmethod
    def _format_index_row(
        cls,
        sub: Any,
        rank: int,
        total_time_ns: int,
        file_slug_map: Dict[str, str],
    ) -> str:
        """Index ページのサブルーチンテーブル行を整形"""
        exc_pct = (sub.exclusive_time_ns / total_time_ns) * 100.0
        inc_pct = (sub.inclusive_time_ns / total_time_ns) * 100.0
        slug = file_slug_map.get(sub.filename, "")
        sub_id = html.escape(sub.name)
        sub_link = (
            f'<a href="{slug}#{sub_id}">{sub_id}</a>'
            if slug
            else f'<a href="#sub_{sub_id}">{sub_id}</a>'
        )
        loc_link = (
            f'<a href="{slug}#L{sub.first_line}">{html.escape(os.path.basename(sub.filename))}:{sub.first_line}</a>'
            if slug
            else html.escape(sub.filename)
        )
        return f"""
        <tr id="sub_{sub_id}">
            <td class="num">{rank}</td>
            <td>{sub_link}</td>
            <td class="num">{sub.calls:,}</td>
            <td class="num">{cls._format_time(sub.inclusive_time_ns)} ({inc_pct:.1f}%)</td>
            <td class="num font-bold">{cls._format_time(sub.exclusive_time_ns)} ({exc_pct:.1f}%)</td>
            <td>{loc_link}</td>
        </tr>
        """

    def _generate_index_page(
        self,
        profile: ProfileData,
        total_time_ns: int,
        out_path: str,
        title: str,
        file_slug_map: Dict[str, str],
    ) -> None:
        """Index ページの生成"""
        sub_link_map: Dict[str, str] = {}
        for sub in profile.subroutines.values():
            slug = file_slug_map.get(sub.filename, "")
            target = (
                f"{slug}#{html.escape(sub.name)}"
                if slug
                else f"#sub_{html.escape(sub.name)}"
            )
            sub_link_map[sub.name] = target

        flame_gen = FlameGraphGenerator(width=1360)
        flame_svg = flame_gen.generate_svg(
            profile,
            title="Execution Call Stacks",
            link_prefix="",
            sub_link_map=sub_link_map,
        )

        sorted_subs = sorted(
            profile.subroutines.values(),
            key=lambda s: (s.exclusive_time_ns, s.inclusive_time_ns),
            reverse=True,
        )

        rows = [
            self._format_index_row(sub, rank, total_time_ns, file_slug_map)
            for rank, sub in enumerate(sorted_subs[:100], 1)
        ]

        meta = profile.metadata
        html_content = f"""<!DOCTYPE html>
<html lang="ja">
<head>
    <meta charset="UTF-8">
    <title>{html.escape(title)}</title>
    <style>{self.CSS_STYLES}</style>
</head>
<body>
<div class="container">
    <header>
        <h1>{html.escape(title)}</h1>
        <div style="color: var(--text-muted); font-size: 14px;">
            Generated by PyNYTProf (DSN-28) • {html.escape(meta.start_time_iso)}
        </div>
    </header>

    <div class="meta-grid">
        <div class="card">
            <div class="card-label">Total Execution Time</div>
            <div class="card-value">{self._format_time(total_time_ns)}</div>
        </div>
        <div class="card">
            <div class="card-label">Profile Mode</div>
            <div class="card-value">{html.escape(meta.mode)} (calls={meta.calls_mode})</div>
        </div>
        <div class="card">
            <div class="card-label">Subroutines</div>
            <div class="card-value">{len(profile.subroutines):,}</div>
        </div>
        <div class="card">
            <div class="card-label">Source Files</div>
            <div class="card-value">{len(profile.source_files):,}</div>
        </div>
    </div>

    <div class="section-box">
        <h2>Interactive Flame Graph (Execution Call Stacks)</h2>
        <div style="overflow-x: auto;">
            {flame_svg}
        </div>
    </div>

    <div class="section-box">
        <h2>Top Subroutines by Exclusive Time</h2>
        <table>
            <thead>
                <tr>
                    <th class="num" style="width: 50px;">Rank</th>
                    <th>Subroutine</th>
                    <th class="num">Calls</th>
                    <th class="num">Inclusive Time</th>
                    <th class="num">Exclusive Time</th>
                    <th>Source Location</th>
                </tr>
            </thead>
            <tbody>
                {''.join(rows)}
            </tbody>
        </table>
    </div>
</div>
</body>
</html>
"""
        with open(out_path, "w", encoding="utf-8") as f:
            f.write(html_content)

    @classmethod
    def _format_caller_callee_rows(cls, items: Any) -> str:
        """Caller/Callee 行 HTML を生成"""
        rows = []
        for name, (c_count, c_inc, c_exc) in items:
            rows.append(f"""
            <tr>
                <td>{html.escape(name or '<root>')}</td>
                <td class="num">{c_count:,}</td>
                <td class="num">{cls._format_time(c_inc)}</td>
                <td class="num">{cls._format_time(c_exc)}</td>
            </tr>
            """)
        return "".join(rows)

    @classmethod
    def _build_subroutine_card(cls, sub: Any) -> str:
        """単一サブルーチンの Caller/Callee カード HTML を生成"""
        c_items = sorted(sub.callers.items(), key=lambda i: i[1][1], reverse=True)
        e_items = sorted(sub.callees.items(), key=lambda i: i[1][1], reverse=True)
        caller_html = (
            cls._format_caller_callee_rows(c_items)
            or '<tr><td colspan="4" style="color:var(--text-muted)">None (Top level)</td></tr>'
        )
        callee_html = (
            cls._format_caller_callee_rows(e_items)
            or '<tr><td colspan="4" style="color:var(--text-muted)">None (Leaf function)</td></tr>'
        )
        sub_id = html.escape(sub.name)
        return f"""
        <div id="{sub_id}" class="card" style="margin-bottom: 16px;">
            <h3>Subroutine: <code>{sub_id}</code> <span class="badge">Line {sub.first_line}</span></h3>
            <div style="font-size: 13px; color: var(--text-muted); margin-bottom: 8px;">
                Calls: <b>{sub.calls:,}</b> •
                Inclusive: <b>{cls._format_time(sub.inclusive_time_ns)}</b> •
                Exclusive: <b>{cls._format_time(sub.exclusive_time_ns)}</b>
            </div>
            <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 16px;">
                <div>
                    <b>Callers (呼出元)</b>
                    <table>
                        <thead><tr><th>Caller</th><th class="num">Calls</th>
                        <th class="num">Inc</th><th class="num">Exc</th></tr></thead>
                        <tbody>{caller_html}</tbody>
                    </table>
                </div>
                <div>
                    <b>Callees (呼出先)</b>
                    <table>
                        <thead><tr><th>Callee</th><th class="num">Calls</th>
                        <th class="num">Inc</th><th class="num">Exc</th></tr></thead>
                        <tbody>{callee_html}</tbody>
                    </table>
                </div>
            </div>
        </div>
        """

    @classmethod
    def _extract_line_metric_strs(
        cls, m: Any, total_time_ns: int
    ) -> Tuple[str, str, str, str]:
        """行メトリクスから表示用文字列とヒートクラスを抽出"""
        if not m:
            return ("", "", "", "heat-0")
        count_str = f"{m.count:,}"
        time_str = cls._format_time(m.time_ns) if m.time_ns > 0 else ""
        avg_str = (
            cls._format_time(m.time_ns // m.count)
            if m.count > 0 and m.time_ns > 0
            else ""
        )
        heat_class = cls._get_heat_class(m.time_ns, total_time_ns)
        return (count_str, time_str, avg_str, heat_class)

    @staticmethod
    def _hint_high_freq_loop(m: Any) -> str:
        """ループ内高頻度実行ヒント (Rule 1)。"""
        if m.count > 10_000 and m.time_ns > 0 and (m.time_ns // m.count) > 10_000:
            return "🔁 ループ内高頻度実行—キャッシュ化を検討"
        return ""

    @staticmethod
    def _hint_regex_not_compiled(m: Any, code_strip: str) -> str:
        """正規表現非コンパイルヒント (Rule 2)。"""
        patterns = ("re.search", "re.match", "re.findall")
        if any(p in code_strip for p in patterns) and m.count > 100:
            return "🔍 re.関数の多用—re.compile()で事前コンパイル済オブジェクトを使用"
        return ""

    @staticmethod
    def _hint_json_loads(m: Any, code_strip: str) -> str:
        """JSON デシリアライズ多用ヒント (Rule 3)。"""
        if "json.loads" in code_strip and m.count > 1_000:
            return "📦 json.loads多用—orjson/ujson等高速ライブラリへの移行を検討"
        return ""

    @staticmethod
    def _hint_high_freq_return(m: Any, code_strip: str) -> str:
        """高頻度 return ヒント (Rule 4)。"""
        if "return" in code_strip and m.count > 50_000:
            return "↩️ 高頻度 return—再帰を反復法に書き換えることを検討"
        return ""

    @classmethod
    def _get_optimization_hints(cls, m: Any, line_code: str) -> list[str]:
        """行メトリクスとソースコードからルールベースの最適化ヒントを抽出する。

        DSN-28 Section 5.5 準拠。
        高頻度実行・正規表現非コンパイル・ JSON 多用・深いスタックを自動検出。
        """
        if m is None:
            return []
        code_strip = line_code.strip()
        candidates = [
            cls._hint_high_freq_loop(m),
            cls._hint_regex_not_compiled(m, code_strip),
            cls._hint_json_loads(m, code_strip),
            cls._hint_high_freq_return(m, code_strip),
        ]
        return [h for h in candidates if h]

    @classmethod
    def _format_source_line(
        cls, lno: int, code_str: str, m: Any, total_time_ns: int
    ) -> str:
        """ソースコード1行の HTML を整形"""
        count_str, time_str, avg_str, heat_class = cls._extract_line_metric_strs(
            m, total_time_ns
        )
        escaped_code = html.escape(code_str) or "&nbsp;"

        # 最適化ヒントアイコン生成 (C-3)
        hints = cls._get_optimization_hints(m, code_str)
        hint_html = ""
        for hint in hints:
            escaped_hint = html.escape(hint)
            hint_html += (
                f'<span class="hint-wrap">'
                f'<span class="hint-icon" aria-label="{escaped_hint}">⚡</span>'
                f'<span class="hint-tip">{escaped_hint}</span>'
                f"</span>"
            )

        return f"""
        <tr id="L{lno}" class="{heat_class}">
            <td class="line-no"><a href="#L{lno}">{lno}</a></td>
            <td class="line-count">{count_str}</td>
            <td class="line-time">{time_str}</td>
            <td class="line-time" style="color: var(--text-muted);">{avg_str}</td>
            <td class="line-code">{escaped_code}{hint_html}</td>
        </tr>
        """

    @staticmethod
    def _build_sub_sec_content(sub_tables: List[str]) -> str:
        """サブルーチンセクション HTML を生成"""
        if sub_tables:
            return "".join(sub_tables)
        return '<p style="color: var(--text-muted);">No subroutines defined in this file.</p>'

    def _generate_source_page(
        self,
        filepath: str,
        content: str,
        profile: ProfileData,
        total_time_ns: int,
        out_path: str,
        title: str,
    ) -> None:
        """ソースファイル詳細ページの生成"""
        lines_metrics = profile.lines.get(filepath, {})
        file_subs = [s for s in profile.subroutines.values() if s.filename == filepath]
        sorted_subs = sorted(file_subs, key=lambda s: s.exclusive_time_ns, reverse=True)
        sub_tables = [self._build_subroutine_card(s) for s in sorted_subs]

        line_rows = [
            self._format_source_line(lno, line, lines_metrics.get(lno), total_time_ns)
            for lno, line in enumerate(content.splitlines(), 1)
        ]
        sub_sec_content = self._build_sub_sec_content(sub_tables)
        page_html = f"""<!DOCTYPE html>
<html lang="ja">
<head>
    <meta charset="UTF-8">
    <title>{html.escape(os.path.basename(filepath))} - {html.escape(title)}</title>
    <style>{self.CSS_STYLES}</style>
</head>
<body>
<div class="container">
    <header>
        <div><a href="index.html">← Back to Overview</a></div>
        <h1 style="margin-top: 8px;">Source: <code>{html.escape(filepath)}</code></h1>
    </header>

    <div class="section-box">
        <h2>Subroutines & Call Arcs</h2>
        {sub_sec_content}
    </div>

    <div class="section-box" style="padding: 0; overflow-x: auto;">
        <table class="source-table">
            <thead>
                <tr>
                    <th class="line-no">Line</th>
                    <th class="line-count">Count</th>
                    <th class="line-time">Time</th>
                    <th class="line-time">Avg</th>
                    <th>Source Code</th>
                </tr>
            </thead>
            <tbody>
                {''.join(line_rows)}
            </tbody>
        </table>
    </div>
</div>
</body>
</html>
"""
        with open(out_path, "w", encoding="utf-8") as f:
            f.write(page_html)
