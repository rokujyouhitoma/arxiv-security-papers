---
ID: 373
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT/ENH] PyNYTProf CLI ツール群および環境変数 PYNYTPROF 透過インジェクションの実装 (ID: 373)

## 1. 概要 / Summary
DSN-28（Python版NYTProf統合スイート設計仕様書）の Phase 5（最終フェーズ）として、コマンドラインから Python スクリプトを透過的プロファイル実行できる CLI ディスパッチャ（`src/core/profiler/cli.py`）、実行ラッパー（`tools/pynytprof`, `tools/pynytprofhtml`）、環境変数 `PYNYTPROF` パース＆自動注入機構、および全コンポーネントを網羅する E2E 統合テスト（`tests/core/test_pynytprof_cli_e2e.py`）を実装する。

---

## 2. トレーサビリティ / Traceability
- 設計仕様書: [DSN-28-python_nytprof_profiler_and_visualization_suite.md](../designs/DSN-28-python_nytprof_profiler_and_visualization_suite.md) Section 7 (ランタイム制御・API ＆ CLI 仕様)
- 関連設計: `DSN-24` (Unified Management CLI)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [src/core/profiler/cli.py](../../src/core/profiler/cli.py) (新規: CLI ディスパッチャ)
- [x] [tools/pynytprof](../../tools/pynytprof) (新規: 実行用 CLI ランチャー)
- [x] [tools/pynytprofhtml](../../tools/pynytprofhtml) (新規: レポートビルダー CLI ランチャー)
- [x] [src/core/profiler/__init__.py](../../src/core/profiler/__init__.py) (更新: CLI 関数および環境変数オートロード)
- [x] [tests/core/test_pynytprof_cli_e2e.py](../../tests/core/test_pynytprof_cli_e2e.py) (新規: CLI & 環境変数 E2E 統合テスト)
- [x] [docs/issues/README.md](README.md) (Issue台帳の同期)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/373-pynytprof-cli-and-e2e`

1. **環境変数 `PYNYTPROF` パースエンジン (`cli.py`)**:
   - 書式: `file=path:lines=1:calls=1:slowops=1:clock=perf_ns`
   - コロン区切りの key=value 文字列を安全にパースし、プロファイラ設定辞書を生成。

2. **統合 CLI コマンド (`src/core/profiler/cli.py`)**:
   - `run`: 任意スクリプトのプロファイリング実行（`exec` による引数透過受け渡し）。
   - `html`: `pynytprof.out` からの HTML レポート一式生成。
   - `flamegraph`: 単体 Flame Graph SVG 生成。
   - `callgrind`: Callgrind 形式ファイル生成。
   - `merge`: 複数 `.pynytprof.out` の合算統合。

3. **実行ランチャー (`tools/pynytprof`, `tools/pynytprofhtml`)**:
   - Python シェバン付きのスタンドアロンスクリプト（実行権限付与）。

4. **E2E 統合テストスイート (`test_pynytprof_cli_e2e.py`)**:
   - サブプロセス経由で `python3 -m src.core.profiler.cli run ...` を実行し、ファイル出力・終了コード 0 を確認。
   - サブプロセス経由で `python3 -m src.core.profiler.cli html ...` を実行し、`index.html` が完全生成されることを確認。
   - 環境変数 `PYNYTPROF` をセットした実行でプロファイルファイルが自動生成されることを検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `tools/pynytprof` および `tools/pynytprofhtml` が正常に起動し、ヘルプ・実行・HTMLレポート生成が行えること。
- [ ] 環境変数 `PYNYTPROF="file=..."` を与えて実行したスクリプトがコード無改変でプロファイル出力されること。
- [ ] `tests/core/test_pynytprof_cli_e2e.py` を含む全テストが 100% パスすること。
- [ ] `make py_compile` を完全パスすること。
