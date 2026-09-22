---
ID: 374
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT/ENH] PyNYTProf 差分プロファイリングエンジン (ProfileDiffer / pynytprofdiff) の実装 (Phase 6) (ID: 374)

## 1. 概要 / Summary

DSN-28（Python版NYTProf統合スイート設計仕様書）の Phase 6 として、2 つの `ProfileData` を比較して **性能退行（Regression）** と **改善（Improvement）** を自動検出・可視化する差分プロファイリングエンジン（`src/core/profiler/diff.py`）を実装する。

本機能は Perl 版 Devel::NYTProf にも存在しない本実装固有の差別化機能であり、コード変更前後の性能変化を赤/緑のヒートマップ付き自己完結型 HTML レポートとして出力する。

差分分類規則:
- `regression`（🔴）: After Exclusive ÷ Before Exclusive ≥ 1.20（+20% 以上遅化）
- `improvement`（🟢）: After Exclusive ÷ Before Exclusive ≤ 0.80（−20% 以上高速化）
- `new-hot`（🟡）: Before = 0 かつ After > 0（新規ホットスポット）
- `neutral`（灰）: 上記以外（ノイズ範囲内）

ノイズフィルタリング: 絶対差 < 0.5ms または相対差 < 5% は統計的に有意でないとして除外。

---

## 2. トレーサビリティ / Traceability

- 設計仕様書: [DSN-28-python_nytprof_profiler_and_visualization_suite.md](../designs/DSN-28-python_nytprof_profiler_and_visualization_suite.md) Section 5.4 (差分プロファイリング仕様)
- 関連 Issue: [369](closed/369-implement-pynytprof-core-profiling-engine-and-storage.md) (Phase 1), [373](closed/373-implement-pynytprof-cli-and-e2e.md) (Phase 5)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [src/core/profiler/diff.py](../../src/core/profiler/diff.py) (新規: 差分プロファイリングエンジン)
  - `ProfileDiffer` — 2つの ProfileData を比較するコアエンジン
  - `SubDiff` — サブルーチン単位の差分メトリクス (dataclass)
  - `LineDiff` — 行単位の差分メトリクス (dataclass)
- [x] [src/core/profiler/__init__.py](../../src/core/profiler/__init__.py) (更新: `ProfileDiffer` を `__all__` に追加)
- [x] [docs/issues/README.md](README.md) (Issue 台帳の同期)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/374-pynytprof-profilediffer-diff-engine`

1. **`ProfileDiffer` クラス (diff.py)**:
   - `compare(before_path, after_path)` — ファイルパスからファクトリ生成
   - `compare_data(before, after)` — ProfileData オブジェクトから生成
   - `compute_sub_diffs()` → `List[SubDiff]` — サブルーチン差分計算（キャッシュ付き）
   - `compute_line_diffs()` → `Dict[str, Dict[int, LineDiff]]` — 行差分計算（キャッシュ付き）
   - `render_html(output_dir)` → `str` — 自己完結型 HTML Diff レポート生成

2. **差分分類ロジック (`SubDiff.diff_class`, `LineDiff.diff_class` プロパティ)**:
   - `exclusive_ratio` = after_exclusive_ns / before_exclusive_ns
   - 閾値: ≥1.20 → `regression`, ≤0.80 → `improvement`, before=0 かつ after>0 → `new-hot`

3. **ノイズフィルタリング (`_is_significant_sub`)**:
   - `NOISE_THRESHOLD_NS = 500_000` (0.5ms)
   - `NOISE_THRESHOLD_RATIO = 0.05` (5%)

4. **Xenon rank A 準拠**:
   - 複雑度が高いメソッドは小メソッドに分割:
     - `compute_sub_diffs` → `_collect_before_subs` / `_merge_after_subs`
     - `compute_line_diffs` → `_collect_before_lines` / `_merge_after_lines`
     - `_build_file_sections` → `_build_single_file_section`

5. **自己完結型 HTML レポート (Inline CSS)**:
   - サマリーカード（Before Total / After Total / Δ Total / 有意差件数）
   - サブルーチン差分テーブル（差分クラス別背景色）
   - ソースファイル差分テーブル（有意差のある行のみ表示）

---

## 5. 完了条件 / Success Criteria (DoD)

- [x] `src/core/profiler/diff.py` が作成され、`ProfileDiffer`, `SubDiff`, `LineDiff` が使用可能であること
- [x] `ProfileDiffer.compare("before.pynytprof.out", "after.pynytprof.out")` が実行可能であること
- [x] `ProfileDiffer.render_html("diff_report/")` が自己完結型 HTML を生成すること
- [x] `make py_compile` PASS（構文エラー 0 件）
- [x] `make static_analysis` PASS（xenon rank A + mypy strict 544 files 全件 PASS）
- [x] `docs/issues/README.md` の Closed 一覧に Issue 374 が登録済みであること
