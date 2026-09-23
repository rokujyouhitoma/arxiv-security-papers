---
ID: 376
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT/ENH] PyNYTProf CLI 差分サブコマンド・Trace フィルタ統合および Diff/Sampling テスト・品質ゲート整備 (ID: 376)

## 1. 概要 / Summary

DSN-28（Python版NYTProf高精度プロファイラ統合スイート設計仕様書）の Phase 6（`diff.py`）および Phase 7（`sampling.py`）で追加されたコア機能について、CLI インターフェース統合と包括的品質テストゲートを整備する。

具体的には以下を実施した:
1. `src/core/profiler/cli.py` に `diff` サブコマンドを追加し、CLI から直接差分プロファイル HTML レポートを出力可能にした。
2. `tools/pynytprofdiff` CLI ラッパースクリプトを新設。
3. `cli.py` の `html` コマンドに `--trace-filter` オプションを実装し、W3C TraceContext (`trace_id`) による特定トランザクションのプロファイル抽出を可能にした (DSN-28 Section 8.2 準拠)。
4. `diff.py` および `sampling.py` に対する包括的ユニットテスト（`tests/core/test_pynytprof_diff.py`, `tests/core/test_pynytprof_sampling.py`）を作成。
5. DSN-28 Section 8.4 / 8.5 準拠のセキュリティ・堅牢性テスト（`tests/test_profiler_xss.py`, `tests/test_profiler_leak.py`）を作成。
6. 全品質ゲート（`make py_compile`, `make static_analysis`, `make test`）の PASS を達成した。

---

## 2. トレーサビリティ / Traceability

- 設計仕様書: [DSN-28-python_nytprof_profiler_and_visualization_suite.md](../designs/DSN-28-python_nytprof_profiler_and_visualization_suite.md)
  - Section 5.4 (差分プロファイリング)
  - Section 4.5 (統計的サンプリングエンジン)
  - Section 7.3 (CLI ツール仕様)
  - Section 8.2 (DSN-10 W3C TraceContext 相関)
  - Section 8.4 (HTML サニタイズ / XSS 排除)
  - Section 8.5 (メモリリーク・リソース保護)
  - Section 8.6 (品質ゲート定量仕様)
- 関連 Issue:
  - [373](closed/373-implement-pynytprof-cli-and-e2e.md) (Phase 5: CLI ツール群)
  - [374](closed/374-implement-pynytprof-profilediffer-diff-engine.md) (Phase 6: 差分プロファイリング)
  - [375](closed/375-implement-pynytprof-sampling-engine.md) (Phase 7: サンプリングエンジン)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [src/core/profiler/cli.py](../../src/core/profiler/cli.py) (`diff` サブコマンド、`--trace-filter` オプション追加)
- [x] [tools/pynytprofdiff](../../tools/pynytprofdiff) (新規: 差分プロファイル CLI 起動ラッパー)
- [x] [tests/core/test_pynytprof_diff.py](../../tests/core/test_pynytprof_diff.py) (新規: 差分プロファイリング単体テスト)
- [x] [tests/core/test_pynytprof_sampling.py](../../tests/core/test_pynytprof_sampling.py) (新規: サンプリングエンジン単体テスト)
- [x] [tests/test_profiler_xss.py](../../tests/test_profiler_xss.py) (新規: HTML / SVG XSS サニタイズ検証テスト)
- [x] [tests/test_profiler_leak.py](../../tests/test_profiler_leak.py) (新規: 再帰・スタックアンワインド・メモリリーク検証テスト)
- [x] [docs/issues/README.md](README.md) (Issue 台帳の同期)
- [x] [docs/designs/DSN-28-python_nytprof_profiler_and_visualization_suite.md](../designs/DSN-28-python_nytprof_profiler_and_visualization_suite.md) (フェーズ・Issue マッピング更新)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/376-pynytprof-diff-sampling-cli-and-test-suite`

1. **CLI 拡張 (`src/core/profiler/cli.py`)**:
   - `build_parser` に `diff` サブパーサを追加:
     - `--before`: ベースライン `.pynytprof.out` パス (必須)
     - `--after`: 比較対象 `.pynytprof.out` パス (必須)
     - `--output-dir` / `-o`: HTML 出力先ディレクトリ (デフォルト: `./diff_report/`)
     - `--noise-threshold-ns`: ノイズ除去ナノ秒閾値 (デフォルト: 500000)
     - `--noise-threshold-ratio`: ノイズ除去比率閾値 (デフォルト: 0.05)
   - `cmd_diff(args)` ハンドラを実装し、`ProfileDiffer.compare()` から `render_html()` を実行。
   - `html` サブパーサに `--trace-filter` オプションを追加し、`ProfileData.metadata.trace_id` と照合して一致しない場合に警告またはフィルタリングを行うロジックを実装。

2. **CLI ラッパースクリプト (`tools/pynytprofdiff`)**:
   - `chmod +x` 可能なシェルラッパー。`python3 -m src.core.profiler.cli diff "$@"` を透過呼び出し。

3. **差分プロファイラテスト (`tests/core/test_pynytprof_diff.py`)**:
   - `ProfileData` モックを 2 つ作成し、`SubDiff` / `LineDiff` の `regression`, `improvement`, `new-hot`, `neutral` 判定を網羅。
   - `ProfileDiffer.render_html()` を実行し、出力された `index.html` に期待されるクラス・スタイルが含まれることを検証。
   - ノイズ閾値以下の変化が正しく無視されることを検証。

4. **サンプリングエンジンテスト (`tests/core/test_pynytprof_sampling.py`)**:
   - `SamplingEngine(interval_sec=0.005, use_signal=True)` の起動・停止とサンプル採取カウントの検証。
   - `SamplingEngine(interval_sec=0.005, use_signal=False)` (Timer フォールバック) の検証。
   - `with SamplingProfiler(interval_sec=0.005, output_file=...)` のコンテキストマネージャ動作とファイル保存検証。

5. **セキュリティ & リークテスト (`tests/test_profiler_xss.py`, `tests/test_profiler_leak.py`)**:
   - XSS テスト: スクリプト名や関数名、ソースコード行に `<script>alert(1)</script>` や `"><svg onload=alert(1)>` が含まれるケースで HTML/SVG 生成を行い、適切にエスケープされていることをアサート。
   - メモリリークテスト: 10,000 回の関数呼出、深い再帰 (100+ フレーム)、例外送出時のスタックアンワインドで `call_stack` が確実に空になることをアサート。

---

## 5. 完了条件 / Success Criteria (DoD)

- [x] `python -m src.core.profiler.cli diff --help` が正常にヘルプを出力すること
- [x] `tools/pynytprofdiff` が実行可能であること
- [x] `tests/core/test_pynytprof_diff.py` が PASS すること
- [x] `tests/core/test_pynytprof_sampling.py` が PASS すること
- [x] `tests/test_profiler_xss.py` が PASS すること
- [x] `tests/test_profiler_leak.py` が PASS すること
- [x] `make py_compile` PASS（構文エラー 0 件）
- [x] `make static_analysis` PASS（xenon rank A + mypy strict 全件 PASS）
- [x] `docs/issues/README.md` に Issue 376 が登録されていること
