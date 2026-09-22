"""
src/core/profiler/diff.py
==========================
PyNYTProf 差分プロファイリングエンジン (pynytprofdiff)。
DSN-28 Section 5.4 準拠。

2 つの ProfileData を比較し、:

- 「退行（遅化）」した関数・行を赤ハイライト
- 「改善（高速化）」した関数・行を緑ハイライト
- 統計的に有意でない差分はグレーアウト

Pure Python / ゼロ外部依存で完全自己完結型 HTML Diff レポートを出力する。
既存の Devel::NYTProf (Perl 版含む) にも存在しない Python 独自機能。
"""

from __future__ import annotations

import html
import os
from dataclasses import dataclass
from typing import Dict, List, Optional

from core.profiler.storage import ProfileData, ProfileStorage

# ------------------------------------------------------------------
# データクラス
# ------------------------------------------------------------------


@dataclass
class SubDiff:
    """サブルーチン単位の差分メトリクス"""

    name: str
    filename: str
    first_line: int

    # Before (baseline) メトリクス
    before_calls: int = 0
    before_inclusive_ns: int = 0
    before_exclusive_ns: int = 0

    # After (target) メトリクス
    after_calls: int = 0
    after_inclusive_ns: int = 0
    after_exclusive_ns: int = 0

    @property
    def exclusive_delta_ns(self) -> int:
        """Exclusive Time の差分（正 = 遅化、負 = 高速化）"""
        return self.after_exclusive_ns - self.before_exclusive_ns

    @property
    def exclusive_ratio(self) -> float:
        """Exclusive Time の変化率（1.0 = 変化なし）"""
        if self.before_exclusive_ns <= 0:
            return float("inf") if self.after_exclusive_ns > 0 else 1.0
        return self.after_exclusive_ns / self.before_exclusive_ns

    @property
    def diff_class(self) -> str:
        """差分の方向を示す CSS クラス文字列"""
        ratio = self.exclusive_ratio
        if ratio > 1.20:
            return "regression"  # 20% 以上遅化
        if ratio < 0.80:
            return "improvement"  # 20% 以上高速化
        return "neutral"


@dataclass
class LineDiff:
    """行単位の差分メトリクス"""

    filename: str
    lineno: int

    before_count: int = 0
    before_time_ns: int = 0
    after_count: int = 0
    after_time_ns: int = 0

    @property
    def time_delta_ns(self) -> int:
        return self.after_time_ns - self.before_time_ns

    @property
    def diff_class(self) -> str:
        if self.before_time_ns <= 0:
            return "new-hot" if self.after_time_ns > 0 else "neutral"
        ratio = self.after_time_ns / self.before_time_ns
        if ratio > 1.20:
            return "regression"
        if ratio < 0.80:
            return "improvement"
        return "neutral"


# ------------------------------------------------------------------
# 差分比較エンジン
# ------------------------------------------------------------------


class ProfileDiffer:
    """
    2 つの ProfileData を比較して差分レポートを生成するエンジン。

    使用例::

        diff = ProfileDiffer.compare("before.pynytprof.out", "after.pynytprof.out")
        diff.render_html("diff_report/")
    """

    # 統計的有意差のしきい値（絶対ナノ秒 & 相対比率の両方を使用）
    NOISE_THRESHOLD_NS = 500_000  # 0.5 ms 未満は誤差とみなす
    NOISE_THRESHOLD_RATIO = 0.05  # ±5% 未満は誤差とみなす

    def __init__(
        self,
        before: ProfileData,
        after: ProfileData,
    ) -> None:
        self.before = before
        self.after = after
        self._sub_diffs: Optional[List[SubDiff]] = None
        self._line_diffs: Optional[Dict[str, Dict[int, LineDiff]]] = None

    # ------------------------------------------------------------------
    # ファクトリ
    # ------------------------------------------------------------------

    @classmethod
    def compare(
        cls,
        before_path: str,
        after_path: str,
    ) -> "ProfileDiffer":
        """ファイルパスから ProfileDiffer を構築する。"""
        before = ProfileStorage.load(before_path)
        after = ProfileStorage.load(after_path)
        return cls(before, after)

    @classmethod
    def compare_data(
        cls,
        before: ProfileData,
        after: ProfileData,
    ) -> "ProfileDiffer":
        """ProfileData オブジェクトから ProfileDiffer を構築する。"""
        return cls(before, after)

    # ------------------------------------------------------------------
    # 差分計算
    # ------------------------------------------------------------------

    def compute_sub_diffs(self) -> List[SubDiff]:
        """サブルーチン差分を計算してキャッシュする。"""
        if self._sub_diffs is not None:
            return self._sub_diffs
        diffs = self._collect_before_subs()
        self._merge_after_subs(diffs)
        result = [d for d in diffs.values() if self._is_significant_sub(d)]
        result.sort(key=lambda d: abs(d.exclusive_delta_ns), reverse=True)
        self._sub_diffs = result
        return result

    def _collect_before_subs(self) -> "Dict[str, SubDiff]":
        """before プロファイルのサブルーチンメトリクスを収集する。"""
        diffs: Dict[str, SubDiff] = {}
        for name, sub in self.before.subroutines.items():
            diffs[name] = SubDiff(
                name=name,
                filename=sub.filename,
                first_line=sub.first_line,
                before_calls=sub.calls,
                before_inclusive_ns=sub.inclusive_time_ns,
                before_exclusive_ns=sub.exclusive_time_ns,
            )
        return diffs

    def _merge_after_subs(self, diffs: "Dict[str, SubDiff]") -> None:
        """after プロファイルのサブルーチンメトリクスを diffs にマージする。"""
        for name, sub in self.after.subroutines.items():
            if name not in diffs:
                diffs[name] = SubDiff(
                    name=name,
                    filename=sub.filename,
                    first_line=sub.first_line,
                )
            d = diffs[name]
            d.after_calls = sub.calls
            d.after_inclusive_ns = sub.inclusive_time_ns
            d.after_exclusive_ns = sub.exclusive_time_ns

    def compute_line_diffs(self) -> Dict[str, Dict[int, LineDiff]]:
        """行単位差分を計算してキャッシュする。"""
        if self._line_diffs is not None:
            return self._line_diffs
        result: Dict[str, Dict[int, LineDiff]] = {}
        self._collect_before_lines(result)
        self._merge_after_lines(result)
        self._line_diffs = result
        return result

    def _collect_before_lines(self, result: Dict[str, Dict[int, LineDiff]]) -> None:
        """before プロファイルの行メトリクスを result に収集する。"""
        for fname, file_lines in self.before.lines.items():
            if fname not in result:
                result[fname] = {}
            for lno, m in file_lines.items():
                result[fname][lno] = LineDiff(
                    filename=fname,
                    lineno=lno,
                    before_count=m.count,
                    before_time_ns=m.time_ns,
                )

    def _merge_after_lines(self, result: Dict[str, Dict[int, LineDiff]]) -> None:
        """after プロファイルの行メトリクスを result にマージする。"""
        for fname, file_lines in self.after.lines.items():
            if fname not in result:
                result[fname] = {}
            for lno, m in file_lines.items():
                if lno not in result[fname]:
                    result[fname][lno] = LineDiff(filename=fname, lineno=lno)
                d = result[fname][lno]
                d.after_count = m.count
                d.after_time_ns = m.time_ns

    def _is_significant_sub(self, d: SubDiff) -> bool:
        """差分が統計的に有意かどうか判定する。"""
        abs_delta = abs(d.exclusive_delta_ns)
        if abs_delta < self.NOISE_THRESHOLD_NS:
            return False
        max_time = max(d.before_exclusive_ns, d.after_exclusive_ns)
        if max_time <= 0:
            return False
        ratio = abs_delta / max_time
        return ratio >= self.NOISE_THRESHOLD_RATIO

    # ------------------------------------------------------------------
    # HTML レポート生成
    # ------------------------------------------------------------------

    def render_html(
        self,
        output_dir: str,
        title: str = "PyNYTProf Differential Profile Report",
    ) -> str:
        """差分 HTML レポートを出力ディレクトリに生成する。"""
        os.makedirs(output_dir, exist_ok=True)
        index_path = os.path.join(output_dir, "index.html")

        sub_diffs = self.compute_sub_diffs()
        line_diffs = self.compute_line_diffs()

        sub_rows = self._build_sub_rows(sub_diffs)
        file_sections = self._build_file_sections(line_diffs)

        before_meta = self.before.metadata
        after_meta = self.after.metadata
        before_total = self.before.metadata.total_time_ns
        after_total = self.after.metadata.total_time_ns
        total_delta_ns = after_total - before_total
        total_delta_class = "regression" if total_delta_ns > 0 else "improvement"

        html_content = f"""<!DOCTYPE html>
<html lang="ja">
<head>
    <meta charset="UTF-8">
    <title>{html.escape(title)}</title>
    <style>{self._CSS}</style>
</head>
<body>
<div class="container">
    <header>
        <h1>{html.escape(title)}</h1>
        <div class="meta-bar">
            <span><b>Before:</b> {html.escape(before_meta.start_time_iso)}</span>
            &nbsp;→&nbsp;
            <span><b>After:</b> {html.escape(after_meta.start_time_iso)}</span>
        </div>
    </header>

    <div class="summary-grid">
        <div class="card">
            <div class="card-label">Before Total Time</div>
            <div class="card-value">{_fmt_ns(before_total)}</div>
        </div>
        <div class="card">
            <div class="card-label">After Total Time</div>
            <div class="card-value">{_fmt_ns(after_total)}</div>
        </div>
        <div class="card">
            <div class="card-label">Total Delta</div>
            <div class="card-value {total_delta_class}">
                {'+' if total_delta_ns >= 0 else ''}{_fmt_ns(total_delta_ns)}
            </div>
        </div>
        <div class="card">
            <div class="card-label">Significant Changes</div>
            <div class="card-value">{len(sub_diffs)}</div>
        </div>
    </div>

    <div class="legend">
        <span class="pill regression">▲ Regression (≥+20%)</span>
        <span class="pill improvement">▼ Improvement (≥−20%)</span>
        <span class="pill neutral">● Neutral (&lt;±20%)</span>
        <span class="pill new-hot">★ New Hotspot</span>
    </div>

    <div class="section-box">
        <h2>Subroutine Diff (Exclusive Time)</h2>
        <table>
            <thead>
                <tr>
                    <th>Subroutine</th>
                    <th class="num">Before Exc</th>
                    <th class="num">After Exc</th>
                    <th class="num">Δ Exclusive</th>
                    <th class="num">Ratio</th>
                    <th>Source</th>
                </tr>
            </thead>
            <tbody>
                {sub_rows}
            </tbody>
        </table>
    </div>

    {file_sections}
</div>
</body>
</html>
"""
        with open(index_path, "w", encoding="utf-8") as f:
            f.write(html_content)
        return index_path

    # ------------------------------------------------------------------
    # HTML ヘルパー
    # ------------------------------------------------------------------

    @staticmethod
    def _build_sub_rows(diffs: List[SubDiff]) -> str:
        rows: List[str] = []
        for d in diffs:
            delta_sign = "+" if d.exclusive_delta_ns >= 0 else ""
            ratio_pct = (d.exclusive_ratio - 1.0) * 100.0
            ratio_sign = "+" if ratio_pct >= 0 else ""
            rows.append(f"""
            <tr class="{html.escape(d.diff_class)}">
                <td><code>{html.escape(d.name)}</code></td>
                <td class="num">{_fmt_ns(d.before_exclusive_ns)}</td>
                <td class="num">{_fmt_ns(d.after_exclusive_ns)}</td>
                <td class="num"><b>{delta_sign}{_fmt_ns(d.exclusive_delta_ns)}</b></td>
                <td class="num">{ratio_sign}{ratio_pct:.1f}%</td>
                <td class="muted">{html.escape(os.path.basename(d.filename))}:{d.first_line}</td>
            </tr>""")
        return (
            "".join(rows)
            or '<tr><td colspan="6" class="muted">No significant differences found.</td></tr>'
        )

    def _build_file_sections(self, line_diffs: Dict[str, Dict[int, LineDiff]]) -> str:
        # ソース共通ファイルのみ対象
        common_files = set(self.before.source_files.keys()) & set(
            self.after.source_files.keys()
        )
        sections: List[str] = []
        for fname in sorted(common_files):
            section = self._build_single_file_section(fname, line_diffs)
            if section:
                sections.append(section)
        return "".join(sections)

    def _build_single_file_section(
        self,
        fname: str,
        line_diffs: Dict[str, Dict[int, LineDiff]],
    ) -> str:
        """単一ソースファイルの差分セクション HTML を生成する。"""
        file_line_diffs = line_diffs.get(fname, {})
        significant = {
            lno: ld for lno, ld in file_line_diffs.items() if ld.diff_class != "neutral"
        }
        if not significant:
            return ""
        src_content = self.after.source_files.get(fname, "")
        src_lines = src_content.splitlines()
        rows = self._build_line_rows(src_lines, significant)
        if not rows:
            return ""
        return f"""
    <div class="section-box">
        <h2>Source Diff: <code>{html.escape(fname)}</code></h2>
        <table class="source-table">
            <thead>
                <tr>
                    <th class="line-no">Line</th>
                    <th class="num">Before</th>
                    <th class="num">After</th>
                    <th class="num">Δ</th>
                    <th>Source</th>
                </tr>
            </thead>
            <tbody>{rows}</tbody>
        </table>
    </div>"""

    @staticmethod
    def _build_line_rows(
        src_lines: List[str],
        significant: Dict[int, LineDiff],
    ) -> str:
        rows: List[str] = []
        for lno, ld in sorted(significant.items()):
            code = src_lines[lno - 1] if 0 < lno <= len(src_lines) else ""
            delta_sign = "+" if ld.time_delta_ns >= 0 else ""
            rows.append(f"""
                <tr class="{html.escape(ld.diff_class)}">
                    <td class="line-no">{lno}</td>
                    <td class="num">{_fmt_ns(ld.before_time_ns)}</td>
                    <td class="num">{_fmt_ns(ld.after_time_ns)}</td>
                    <td class="num">{delta_sign}{_fmt_ns(ld.time_delta_ns)}</td>
                    <td class="line-code">{html.escape(code or '&nbsp;')}</td>
                </tr>""")
        return "".join(rows)

    # ------------------------------------------------------------------
    # CSS（インライン自己完結型）
    # ------------------------------------------------------------------

    _CSS = """
    :root {
        --bg: #f8f9fa;
        --card-bg: #ffffff;
        --text: #212529;
        --muted: #6c757d;
        --border: #dee2e6;
        --regression-bg: #fff0f0;
        --regression-text: #c0392b;
        --improvement-bg: #f0fff4;
        --improvement-text: #27ae60;
        --neutral-bg: transparent;
        --new-hot-bg: #fff8e1;
        --new-hot-text: #e67e22;
        --code-font: 'JetBrains Mono', 'Fira Code', Menlo, Monaco, Consolas, monospace;
    }
    body { margin: 0; padding: 20px; font-family: -apple-system, BlinkMacSystemFont,
           "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
           background: var(--bg); color: var(--text); line-height: 1.5; }
    .container { max-width: 1400px; margin: 0 auto; }
    header { margin-bottom: 20px; border-bottom: 2px solid var(--border); padding-bottom: 12px; }
    h1, h2 { margin-top: 0; }
    .meta-bar { font-size: 13px; color: var(--muted); margin-top: 4px; }
    .summary-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
                    gap: 16px; margin-bottom: 20px; }
    .card { background: var(--card-bg); border: 1px solid var(--border); border-radius: 6px;
            padding: 16px; box-shadow: 0 1px 3px rgba(0,0,0,.05); }
    .card-label { font-size: 11px; color: var(--muted); text-transform: uppercase;
                  font-weight: 700; letter-spacing: .05em; }
    .card-value { font-size: 22px; font-weight: 700; margin-top: 4px; }
    .section-box { background: var(--card-bg); border: 1px solid var(--border);
                   border-radius: 6px; padding: 20px; margin-bottom: 24px; }
    table { width: 100%; border-collapse: collapse; font-size: 13px; }
    th, td { padding: 7px 10px; text-align: left; border-bottom: 1px solid var(--border); }
    th { background: #e9ecef; font-weight: 600; }
    .num { text-align: right; font-family: var(--code-font); }
    .muted { color: var(--muted); font-size: 12px; }
    code { font-family: var(--code-font); font-size: 12px; }
    /* 差分クラス */
    tr.regression td { background: var(--regression-bg); }
    tr.regression .num b { color: var(--regression-text); }
    tr.improvement td { background: var(--improvement-bg); }
    tr.improvement .num b { color: var(--improvement-text); }
    tr.new-hot td { background: var(--new-hot-bg); }
    .card-value.regression { color: var(--regression-text); }
    .card-value.improvement { color: var(--improvement-text); }
    /* legend */
    .legend { display: flex; gap: 12px; margin-bottom: 16px; flex-wrap: wrap; }
    .pill { font-size: 12px; padding: 3px 10px; border-radius: 100px;
            font-weight: 600; border: 1px solid var(--border); }
    .pill.regression { background: var(--regression-bg); color: var(--regression-text); }
    .pill.improvement { background: var(--improvement-bg); color: var(--improvement-text); }
    .pill.neutral { background: #f1f3f5; color: var(--muted); }
    .pill.new-hot { background: var(--new-hot-bg); color: var(--new-hot-text); }
    /* ソーステーブル */
    .source-table { font-family: var(--code-font); font-size: 12px; }
    .line-no { text-align: right; color: var(--muted); width: 50px; user-select: none; }
    .line-code { white-space: pre-wrap; word-break: break-all; }
    """


# ------------------------------------------------------------------
# フォーマットユーティリティ
# ------------------------------------------------------------------


def _fmt_ns(ns: int) -> str:
    """ナノ秒を読みやすい単位に変換する。"""
    sign = ""
    if ns < 0:
        sign = "−"
        ns = -ns
    if ns >= 1_000_000_000:
        return f"{sign}{ns / 1_000_000_000:.3f}s"
    if ns >= 1_000_000:
        return f"{sign}{ns / 1_000_000:.2f}ms"
    if ns >= 1_000:
        return f"{sign}{ns / 1_000:.1f}µs"
    return f"{sign}{ns}ns"
