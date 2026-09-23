"""
src/core/profiler/chart.py
==========================
PyNYTProf 時系列 Flame Chart 可視化および Chrome Trace Event エクスポーター。
DSN-28 Section 2, 9.2 (Phase 10) 準拠。

- TraceEventExporter: Google Chrome Tracing / Perfetto / Speedscope 互換 JSON 出力。
- FlameChartGenerator: 横軸を経過時間、縦軸をコールスタック深度とした
  インタラクティブな純粋 Python 製タイムライン Flame Chart (SVG/HTML) 生成器。
"""

from __future__ import annotations

import html
import json
import os
from typing import Any, Dict, List, Optional, Tuple

from core.profiler.storage import ProfileData, TimelineEvent


class TraceEventExporter:
    """
    Chrome Trace Event Format (Google Chrome tracing / Perfetto / Speedscope 互換)
    へのエクスポートエンジン。
    """

    @classmethod
    def export_dict(cls, profile_data: ProfileData) -> Dict[str, Any]:
        """ProfileData を Chrome Trace Event 辞書構造へ変換"""
        events: List[Dict[str, Any]] = []
        pid = profile_data.metadata.pid or 1
        tid = 1

        # プロセスおよびスレッドメタデータイベント
        cmd_str = (
            " ".join(profile_data.metadata.cmdline)
            if profile_data.metadata.cmdline
            else "PyNYTProf"
        )
        events.append(
            {
                "name": "process_name",
                "ph": "M",
                "pid": pid,
                "args": {"name": f"Python ({cmd_str})"},
            }
        )
        events.append(
            {
                "name": "thread_name",
                "ph": "M",
                "pid": pid,
                "tid": tid,
                "args": {"name": "MainThread"},
            }
        )

        timeline = profile_data.timeline_events
        if timeline:
            cls._export_from_timeline(timeline, pid, events)
        else:
            cls._export_fallback(profile_data, pid, tid, events)

        return {
            "traceEvents": events,
            "displayTimeUnit": "ms",
            "metadata": {
                "version": "1.0.0",
                "generator": "PyNYTProf",
                "total_time_ns": profile_data.metadata.total_time_ns,
            },
        }

    @classmethod
    def _export_from_timeline(
        cls,
        timeline: List[TimelineEvent],
        pid: int,
        events: List[Dict[str, Any]],
    ) -> None:
        """タイムラインイベント群からトレースイベントを生成"""
        if not timeline:
            return
        base_ns = min(ev.entry_ns for ev in timeline)
        for ev in timeline:
            ts_us = round((ev.entry_ns - base_ns) / 1000.0, 3)
            dur_us = max(0.1, round(ev.inclusive_ns / 1000.0, 3))
            item = {
                "name": ev.name,
                "cat": ev.cat,
                "ph": "X",  # Complete event
                "ts": ts_us,
                "dur": dur_us,
                "pid": pid,
                "tid": ev.tid or 1,
                "args": {
                    "filename": ev.filename,
                    "first_line": ev.first_line,
                    "caller": ev.caller,
                    "exclusive_ms": round(ev.exclusive_ns / 1_000_000.0, 3),
                    "suspend_ms": round(ev.suspend_ns / 1_000_000.0, 3),
                    "task_id": ev.task_id,
                },
            }
            events.append(item)

    @classmethod
    def _export_fallback(
        cls,
        profile_data: ProfileData,
        pid: int,
        tid: int,
        events: List[Dict[str, Any]],
    ) -> None:
        """calls_mode < 2 時のサブルーチン集計フォールバック変換"""
        curr_us = 0.0
        for name, sub in profile_data.subroutines.items():
            dur_us = max(0.1, round(sub.inclusive_time_ns / 1000.0, 3))
            cat = "builtin" if name.startswith("CORE:") else "function"
            item = {
                "name": name,
                "cat": cat,
                "ph": "X",
                "ts": curr_us,
                "dur": dur_us,
                "pid": pid,
                "tid": tid,
                "args": {
                    "filename": sub.filename,
                    "first_line": sub.first_line,
                    "calls": sub.calls,
                    "exclusive_ms": round(sub.exclusive_time_ns / 1_000_000.0, 3),
                    "suspend_ms": round(sub.suspend_time_ns / 1_000_000.0, 3),
                },
            }
            events.append(item)
            curr_us += dur_us

    @classmethod
    def export_file(
        cls, profile_data: ProfileData, filepath: str, indent: int = 2
    ) -> None:
        """Chrome Trace Event JSON をファイルへ保存"""
        data = cls.export_dict(profile_data)
        os.makedirs(os.path.dirname(os.path.abspath(filepath)), exist_ok=True)
        with open(filepath, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=indent)


class FlameChartGenerator:
    """
    時系列コールスタックを描画するインタラクティブ Flame Chart 生成器。
    横軸: 経過時間 (ms), 縦軸: スタック深度
    """

    COLOR_PALETTES = [
        "#f97316",
        "#fb923c",
        "#f59e0b",
        "#fbbf24",
        "#eab308",
        "#10b981",
        "#06b6d4",
        "#3b82f6",
        "#6366f1",
        "#8b5cf6",
        "#ec4899",
        "#14b8a6",
    ]

    @classmethod
    def _pick_color(cls, name: str, cat: str) -> str:
        """関数名とカテゴリから決定論的カラーコードを取得"""
        if cat == "coroutine":
            return "#a855f7"  # 紫系 (非同期コルーチン)
        if cat == "builtin" or name.startswith("CORE:"):
            return "#64748b"  # スレートグレー (組み込み/C関数)
        idx = hash(name) % len(cls.COLOR_PALETTES)
        return cls.COLOR_PALETTES[idx]

    @classmethod
    def _compute_spans_from_timeline(
        cls, timeline: List[TimelineEvent]
    ) -> Tuple[List[Dict[str, Any]], int, int, int]:
        """タイムラインイベント群から描画スパンを計算"""
        min_ns = min(ev.entry_ns for ev in timeline)
        max_ns = max(ev.exit_ns for ev in timeline)
        max_depth = 0
        spans: List[Dict[str, Any]] = []
        for ev in timeline:
            dur = max(1, ev.inclusive_ns)
            depth = max(0, ev.depth - 1)
            if depth > max_depth:
                max_depth = depth
            spans.append(
                {
                    "name": ev.name,
                    "cat": ev.cat,
                    "start_ns": ev.entry_ns - min_ns,
                    "dur_ns": dur,
                    "depth": depth,
                    "exclusive_ns": ev.exclusive_ns,
                    "suspend_ns": ev.suspend_ns,
                    "filename": ev.filename,
                    "line": ev.first_line,
                    "caller": ev.caller,
                }
            )
        total_ns = max(1, max_ns - min_ns)
        return spans, min_ns, total_ns, max_depth

    @classmethod
    def _compute_spans_fallback(
        cls, subroutines: Dict[str, Any]
    ) -> Tuple[List[Dict[str, Any]], int, int, int]:
        """サブルーチン集計から擬似タイムラインスパンを生成"""
        spans: List[Dict[str, Any]] = []
        curr_ns = 0
        for name, sub in subroutines.items():
            dur = max(1, sub.inclusive_time_ns)
            cat = "builtin" if name.startswith("CORE:") else "function"
            spans.append(
                {
                    "name": name,
                    "cat": cat,
                    "start_ns": curr_ns,
                    "dur_ns": dur,
                    "depth": 0,
                    "exclusive_ns": sub.exclusive_time_ns,
                    "suspend_ns": sub.suspend_time_ns,
                    "filename": sub.filename,
                    "line": sub.first_line,
                    "caller": "",
                }
            )
            curr_ns += dur
        total_ns = max(1, curr_ns)
        return spans, 0, total_ns, 0

    @classmethod
    def _compute_spans(
        cls, profile_data: ProfileData
    ) -> Tuple[List[Dict[str, Any]], int, int, int]:
        """描画用スパンリストと最大時間・最大深度を計算"""
        if profile_data.timeline_events:
            return cls._compute_spans_from_timeline(profile_data.timeline_events)
        return cls._compute_spans_fallback(profile_data.subroutines)

    @classmethod
    def generate_svg(
        cls,
        profile_data: ProfileData,
        width: int = 1200,
        row_height: int = 24,
    ) -> str:
        """純粋 Python 製ベクター SVG Flame Chart を生成"""
        spans, _, total_ns, max_depth = cls._compute_spans(profile_data)
        top_offset = 40
        height = max(180, (max_depth + 1) * row_height + top_offset + 30)

        parts: List[str] = [
            f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}" '
            f'width="{width}" height="{height}" class="pynytprof-flamechart">'
        ]
        cls._append_ruler(parts, width, total_ns, top_offset)

        for span in spans:
            cls._append_span_rect(parts, span, width, total_ns, row_height, top_offset)

        parts.append("</svg>")
        return "".join(parts)

    @classmethod
    def _append_ruler(
        cls, parts: List[str], width: int, total_ns: int, top_offset: int
    ) -> None:
        """タイムライン目盛り描画"""
        total_ms = total_ns / 1_000_000.0
        parts.append(
            f'<line x1="0" y1="{top_offset - 10}" x2="{width}" y2="{top_offset - 10}" '
            'stroke="#475569" stroke-width="1"/>'
        )
        ticks = 5
        for i in range(ticks + 1):
            ratio = i / ticks
            x = int(ratio * width)
            ms_val = ratio * total_ms
            parts.append(
                f'<line x1="{x}" y1="{top_offset - 15}" x2="{x}" y2="{top_offset - 5}" '
                'stroke="#64748b" stroke-width="1"/>'
            )
            parts.append(
                f'<text x="{x + 4}" y="{top_offset - 12}" fill="#94a3b8" '
                f'font-size="10" font-family="sans-serif">{ms_val:.1f}ms</text>'
            )

    @classmethod
    def _append_span_rect(
        cls,
        parts: List[str],
        span: Dict[str, Any],
        width: int,
        total_ns: int,
        row_height: int,
        top_offset: int,
    ) -> None:
        """単一のコールスパン矩形とテキストを描画"""
        x = (span["start_ns"] / total_ns) * width
        span_w = max(2.0, (span["dur_ns"] / total_ns) * width)
        y = span["depth"] * row_height + top_offset
        color = cls._pick_color(span["name"], span["cat"])
        safe_name = html.escape(span["name"])
        dur_ms = span["dur_ns"] / 1_000_000.0
        exc_ms = span["exclusive_ns"] / 1_000_000.0
        sus_ms = span["suspend_ns"] / 1_000_000.0

        title_text = (
            f"{safe_name}\n"
            f"Duration: {dur_ms:.3f}ms | Exclusive: {exc_ms:.3f}ms | Suspend: {sus_ms:.3f}ms\n"
            f"Location: {html.escape(span['filename'])}:{span['line']}"
        )

        parts.append(
            f'<g class="chart-block" data-name="{safe_name}" '
            f'data-dur="{dur_ms:.3f}" data-exc="{exc_ms:.3f}" data-sus="{sus_ms:.3f}" '
            f'data-file="{html.escape(span["filename"])}" data-line="{span["line"]}">'
        )
        parts.append(
            f'<rect x="{x:.1f}" y="{y}" width="{span_w:.1f}" height="{row_height - 3}" '
            f'fill="{color}" rx="3" stroke="#0f172a" stroke-width="0.5">'
            f"<title>{title_text}</title></rect>"
        )

        if span_w > 35:
            max_chars = max(3, int(span_w / 7.5))
            label = (
                safe_name[: max_chars - 1] + "…"
                if len(safe_name) > max_chars
                else safe_name
            )
            parts.append(
                f'<text x="{x + 4:.1f}" y="{y + 14}" fill="#ffffff" '
                f'font-size="11" font-family="sans-serif" pointer-events="none">{label}</text>'
            )
        parts.append("</g>")

    @classmethod
    def generate_html(
        cls,
        profile_data: ProfileData,
        out_path: Optional[str] = None,
        title: str = "PyNYTProf Timeline Flame Chart",
    ) -> str:
        """自己完結型インタラクティブ Flame Chart HTML レポートを生成"""
        svg_content = cls.generate_svg(profile_data)
        meta = profile_data.metadata
        safe_title = html.escape(title)
        total_time_ms = meta.total_time_ns / 1_000_000.0
        events_count = len(profile_data.timeline_events) or len(
            profile_data.subroutines
        )

        template = f"""<!DOCTYPE html>
<html lang="ja">
<head>
  <meta charset="utf-8">
  <title>{safe_title}</title>
  <style>
    :root {{
      --bg: #0f172a;
      --card-bg: #1e293b;
      --text: #f8fafc;
      --muted: #94a3b8;
      --border: #334155;
      --accent: #38bdf8;
    }}
    * {{ box-sizing: border-box; margin: 0; padding: 0; }}
    body {{
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      background: var(--bg);
      color: var(--text);
      padding: 24px;
    }}
    header {{
      display: flex;
      justify-content: space-between;
      align-items: center;
      margin-bottom: 24px;
      padding-bottom: 16px;
      border-bottom: 1px solid var(--border);
    }}
    h1 {{ font-size: 1.5rem; font-weight: 700; color: var(--accent); }}
    .stats-row {{
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
      gap: 16px;
      margin-bottom: 24px;
    }}
    .stat-card {{
      background: var(--card-bg);
      border: 1px solid var(--border);
      border-radius: 8px;
      padding: 12px 16px;
    }}
    .stat-card .label {{ font-size: 0.75rem; color: var(--muted); text-transform: uppercase; }}
    .stat-card .value {{ font-size: 1.25rem; font-weight: 700; margin-top: 4px; }}
    .controls {{
      display: flex;
      gap: 12px;
      align-items: center;
      margin-bottom: 16px;
    }}
    input[type="text"] {{
      background: var(--card-bg);
      border: 1px solid var(--border);
      color: var(--text);
      padding: 8px 12px;
      border-radius: 6px;
      flex: 1;
      max-width: 400px;
    }}
    .btn {{
      background: var(--card-bg);
      border: 1px solid var(--border);
      color: var(--text);
      padding: 8px 16px;
      border-radius: 6px;
      cursor: pointer;
    }}
    .btn:hover {{ border-color: var(--accent); }}
    .chart-container {{
      background: var(--card-bg);
      border: 1px solid var(--border);
      border-radius: 8px;
      overflow-x: auto;
      padding: 16px;
      margin-bottom: 24px;
    }}
    .inspector {{
      background: var(--card-bg);
      border: 1px solid var(--border);
      border-radius: 8px;
      padding: 16px;
    }}
    .inspector h2 {{ font-size: 1.1rem; margin-bottom: 8px; color: var(--accent); }}
    .inspector-grid {{
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
      gap: 12px;
      font-size: 0.9rem;
    }}
    .chart-block {{ cursor: pointer; transition: opacity 0.15s; }}
    .chart-block:hover {{ opacity: 0.8; }}
    .chart-block.dimmed {{ opacity: 0.15; }}
  </style>
</head>
<body>
  <header>
    <h1>🔥 {safe_title}</h1>
    <div style="font-size: 0.85rem; color: var(--muted);">PyNYTProf v1.0.0 (Phase 10)</div>
  </header>

  <div class="stats-row">
    <div class="stat-card">
      <div class="label">Total Duration</div>
      <div class="value">{total_time_ms:.2f} ms</div>
    </div>
    <div class="stat-card">
      <div class="label">Call Spans / Events</div>
      <div class="value">{events_count}</div>
    </div>
    <div class="stat-card">
      <div class="label">Process ID</div>
      <div class="value">{meta.pid}</div>
    </div>
    <div class="stat-card">
      <div class="label">Profiler Mode</div>
      <div class="value">{html.escape(meta.mode)} (calls={meta.calls_mode})</div>
    </div>
  </div>

  <div class="controls">
    <input type="text" id="filterInput" placeholder="Filter functions (e.g. sleep, query)...">
    <button class="btn" id="resetBtn">Reset</button>
  </div>

  <div class="chart-container" id="chartWrapper">
    {svg_content}
  </div>

  <div class="inspector" id="inspector">
    <h2>Details Inspector</h2>
    <div class="inspector-grid" id="inspectorContent">
      <div>Click any span above to inspect execution metrics.</div>
    </div>
  </div>

  <script>
    const filterInput = document.getElementById('filterInput');
    const resetBtn = document.getElementById('resetBtn');
    const blocks = document.querySelectorAll('.chart-block');
    const inspector = document.getElementById('inspectorContent');

    filterInput.addEventListener('input', (e) => {{
      const q = e.target.value.toLowerCase().trim();
      blocks.forEach(b => {{
        const name = (b.getAttribute('data-name') || '').toLowerCase();
        if (!q || name.includes(q)) {{
          b.classList.remove('dimmed');
        }} else {{
          b.classList.add('dimmed');
        }}
      }});
    }});

    resetBtn.addEventListener('click', () => {{
      filterInput.value = '';
      blocks.forEach(b => b.classList.remove('dimmed'));
    }});

    blocks.forEach(b => {{
      b.addEventListener('click', () => {{
        const name = b.getAttribute('data-name');
        const dur = b.getAttribute('data-dur');
        const exc = b.getAttribute('data-exc');
        const sus = b.getAttribute('data-sus');
        const file = b.getAttribute('data-file');
        const line = b.getAttribute('data-line');

        inspector.innerHTML = `
          <div><strong>Function:</strong> ${{name}}</div>
          <div><strong>Duration:</strong> ${{dur}} ms</div>
          <div><strong>Exclusive Time:</strong> ${{exc}} ms</div>
          <div><strong>Suspend Time:</strong> ${{sus}} ms</div>
          <div><strong>Location:</strong> ${{file}}:${{line}}</div>
        `;
      }});
    }});
  </script>
</body>
</html>
"""
        if out_path:
            os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
            with open(out_path, "w", encoding="utf-8") as f:
                f.write(template)
        return template
