---
ID: 372
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT/ENH] PyNYTProf Callgrind 形式エクスポートおよびマルチプロセスマージエンジンの実装 (ID: 372)

## 1. 概要 / Summary
DSN-28（Python版NYTProf統合スイート設計仕様書）の Phase 4 として、KCachegrind / QCacheGrind 等の外部 GUI ツールでプロファイル結果を視覚的有向グラフ探索可能にする Callgrind 形式エクスポータ（`CallgrindExporter` / `src/core/profiler/exporter.py`）と、マルチプロセス（`multiprocessing` / `fork`）実行で生成された複数プロファイルを単一データへ正確に合算集約するマージエンジン（`ProfileMerger` / `src/core/profiler/merge.py`）を実装する。

---

## 2. トレーサビリティ / Traceability
- 設計仕様書: [DSN-28-python_nytprof_profiler_and_visualization_suite.md](../designs/DSN-28-python_nytprof_profiler_and_visualization_suite.md) Section 6.1 (Callgrind エクスポート), Section 6.2 (マルチプロセス統合マージ)
- 関連ツール: Valgrind Callgrind Format Specification
- 関連設計: `DSN-12` (Process Supervisor & Arbiter)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [src/core/profiler/exporter.py](../../src/core/profiler/exporter.py) (新規: Callgrind フォーマット出力エンジン)
- [x] [src/core/profiler/merge.py](../../src/core/profiler/merge.py) (新規: 複数プロファイル合算マージエンジン)
- [x] [src/core/profiler/__init__.py](../../src/core/profiler/__init__.py) (更新: `CallgrindExporter`, `ProfileMerger` エクスポート)
- [x] [tests/core/test_pynytprof_exporter_merge.py](../../tests/core/test_pynytprof_exporter_merge.py) (新規: Callgrind形式妥当性＆マージ正確性テスト)
- [x] [docs/issues/README.md](README.md) (Issue台帳の同期)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/372-pynytprof-exporter-merge`

1. **Callgrind 形式エクスポータ (`exporter.py`)**:
   - `CallgrindExporter`:
     - ヘッダー出力: `version: 1`, `creator: PyNYTProf`, `events: Nanoseconds`, `summary: <total_time_ns>`
     - ファイルブロック (`fl=<filepath>`), 関数ブロック (`fn=<sub_name>`)
     - 行単位メトリクス (`<line_no> <time_ns>`)
     - 呼び出しアーク (`cfn=<callee_name>`, `calls=<count> <line>`, `<line> <inc_time_ns>`)
     - 純粋テキスト出力（`callgrind.out.<pid>`）。

2. **マルチプロセスマージエンジン (`merge.py`)**:
   - `ProfileMerger`:
     - 複数の `ProfileData` またはファイルパス群を受け取り、単一の統合 `ProfileData` を生成。
     - 行メトリクスの合算: `lines[file][lno].count += m.count`, `lines[file][lno].time_ns += m.time_ns`。
     - サブルーチンメトリクスの合算: `calls`, `inclusive_time_ns`, `exclusive_time_ns`, `callers`, `callees`。
     - Call Arc メトリクスの合算: `arcs[(caller, callee)]`。
     - コールスタックストリームの合算: `stack_traces[stack] += time_ns`。
     - ソースファイルキャッシュのユニオン統合。

3. **単体テストスイート (`test_pynytprof_exporter_merge.py`)**:
   - 生成された Callgrind テキストの構文検証（ヘッダー、`fn=`, `events:`, `summary:`）。
   - 2つの独立した `ProfileData` の合算値の正確性検証（各値の和に一致すること）。
   - マージ後の ProfileData からの正常な HTML/FlameGraph 生成の再確認。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `CallgrindExporter` が KCachegrind 互換の正しい Callgrind 形式ファイルを出力できること。
- [ ] `ProfileMerger` により、複数プロセスの時間・回数が算術的に正確に合算されること。
- [ ] `tests/core/test_pynytprof_exporter_merge.py` が 100% パスすること。
- [ ] `make py_compile` を完全パスすること。
