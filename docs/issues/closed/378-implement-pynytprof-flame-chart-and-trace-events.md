---
ID: 378
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT/ENH] PyNYTProf 時系列 Flame Chart 可視化および Chrome Trace Event エクスポーターの実装 (Phase 10) (ID: 378)

## 1. 概要 / Summary

DSN-28（Python版NYTProf高精度プロファイラ統合スイート設計仕様書）の Phase 10 として、`calls=2` モードで収集された時系列コールトレースデータから、Google Chrome Tracing / Perfetto / Speedscope 互換の **Chrome Trace Event JSON フォーマット出力 (`TraceEventExporter`)**、および時系列軸に沿ったインタラクティブな **タイムライン Flame Chart HTML/SVG 生成器 (`FlameChartGenerator`)** を実装する。

従来の Flame Graph はサブルーチン呼び出しを集計（アルファベット順・累積時間幅）してボトルネックを俯瞰するのに対し、Flame Chart は**実際の実行タイムライン（横軸＝経過時間、縦軸＝スタック深度）**を忠実に描画する。これにより、イベントループのレイテンシスパイク、断続的な I/O 待機、周期的なタスク実行の偏りを視覚的に分析可能にする。

---

## 2. トレーサビリティ / Traceability

- 設計仕様書: [DSN-28-python_nytprof_profiler_and_visualization_suite.md](../designs/DSN-28-python_nytprof_profiler_and_visualization_suite.md)
  - Section 2 (用語定義: Flame Chart vs Flame Graph)
  - Section 9.2 (フェーズ一覧 Phase 10: chart.py、時系列 Flame Chart 表示、Chrome Trace Event JSON 生成)
- 関連 Issue:
  - [369](369-implement-pynytprof-core-profiling-engine-and-storage.md) (Phase 1: コア計測エンジン)
  - [370](370-implement-pynytprof-pure-python-flamegraph.md) (Phase 2: Pure Python Flame Graph)
  - [376](376-implement-pynytprof-diff-sampling-cli-and-test-suite.md) (Phase 8: CLI 差分統合 ＆ 品質ゲート)
  - [377](377-implement-pynytprof-asyncio-coroutine-profiling.md) (Phase 9: asyncio コルーチン待機時間分離)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [src/core/profiler/storage.py](../../src/core/profiler/storage.py) (`TimelineEvent` または `timeline_events` の格納・シリアライズ)
- [x] [src/core/profiler/engine.py](../../src/core/profiler/engine.py) (`calls_mode == 2` 時のタイムラインイベント記録)
- [x] [src/core/profiler/chart.py](../../src/core/profiler/chart.py) (新規: `TraceEventExporter` および `FlameChartGenerator`)
- [x] [src/core/profiler/__init__.py](../../src/core/profiler/__init__.py) (公開シンボルのエクスポート)
- [x] [src/core/profiler/cli.py](../../src/core/profiler/cli.py) (`chart` サブコマンド追加)
- [x] [tools/pynytprofchart](../../tools/pynytprofchart) (新規 CLI 実行可能スクリプト)
- [x] [tests/core/test_pynytprof_chart.py](../../tests/core/test_pynytprof_chart.py) (新規単体・結合テスト)
- [x] [docs/issues/README.md](../issues/README.md) (Issue 台帳の同期)
- [x] [docs/designs/DSN-28-python_nytprof_profiler_and_visualization_suite.md](../designs/DSN-28-python_nytprof_profiler_and_visualization_suite.md) (フェーズ表更新)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/378-pynytprof-flame-chart-and-trace-events`

1. **データ構造とイベント収集 (`storage.py`, `engine.py`)**:
   - `TimelineEvent`: `name`, `cat`, `entry_ns`, `exit_ns`, `dur_ns`, `depth`, `caller`, `filename`, `line`, `suspend_ns`, `tid`。
   - `ProfileData` に `timeline_events: List[TimelineEvent]` を追加（シリアライズ対応、互換性維持）。
   - `engine.py` の `calls_mode == 2` において、`_pop_frame` 時にイベントを記録。また、既存データからの再構築フォールバックもサポート。

2. **Chrome Trace Event エクスポーター (`chart.py`)**:
   - `TraceEventExporter.to_dict()` / `export_file()`:
     - Chrome Trace Event Format 準拠の `{"traceEvents": [...]}` を生成。
     - Phase `"X"` (Complete Events) で `ts` (us), `dur` (us), `name`, `cat`, `pid`, `tid`, `args` (filename, line, exc_ms, suspend_ms) を設定。
     - `displayTimeUnit: "ms"` を付与。

3. **タイムライン Flame Chart 生成器 (`chart.py`)**:
   - `FlameChartGenerator.generate_html()` / `generate_svg()`:
     - 外部ライブラリ依存ゼロの純粋 Python でインタラクティブ SVG/HTML を生成。
     - 横軸を経過時間（0ms 〜 total_time_ms）、縦軸をスタック階層として各呼出スパンを長方形ブロックで配置。
     - ホバー時の詳細ツールチップ（関数名、開始時刻、所要時間、自時間、待機時間）、ズーム・スクロール機能、XSS サニタイズ (`html.escape`)。

4. **CLI 統合 (`cli.py`, `tools/pynytprofchart`)**:
   - `pynytprof chart --input prof.out --output-html chart.html --output-trace trace.json`
   - `tools/pynytprofchart` スクリプトの設置と実行権限付与。

5. **テストスイート (`tests/core/test_pynytprof_chart.py`)**:
   - Chrome Trace Event JSON スキーマ検証。
   - Flame Chart HTML / SVG レンダリング構造検証。
   - XSS サニタイズ検証。
   - 空データ・単一イベント時の境界値検証。

---

## 5. 完了条件 / Success Criteria (DoD)

- [x] `TraceEventExporter` が Chrome Trace Event 形式の JSON を正しく出力すること
- [x] `FlameChartGenerator` が時系列 Flame Chart HTML/SVG をゼロ外部依存で生成すること
- [x] `pynytprof chart` サブコマンドおよび `tools/pynytprofchart` が動作すること
- [x] XSS サニタイズが徹底されていること
- [x] `tests/core/test_pynytprof_chart.py` が PASS すること
- [x] `make py_compile` PASS
- [x] `make static_analysis` PASS (xenon rank A, mypy strict)
- [x] `docs/issues/README.md` に反映されていること
