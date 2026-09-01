---
ID: 106
種別: Bug
優先度: High
ステータス: Closed (Resolved)
---

# [BUG/SEC] パイプライン実行時の workspace_dir 誤判定および Raw メタデータパス解決不具合の修正 (ID: 106)

## 1. 概要 / Summary
`python3 src/pipeline/arxiv_okf_fetcher.py` をコマンドラインから直接実行した際、ワークスペース検出関数 `_detect_workspace_dir()` の親ディレクトリ探索が不十分であったため、`workspace_dir` がリポジトリルート（`/workspace/arxiv-security-papers`）ではなくスクリプト設置先（`src/pipeline`）と誤認される。
この結果、原本保存先が `/workspace/arxiv-security-papers/src/pipeline/outputs/raw_data/...` となり、OKF Markdown 変換処理（`_load_raw_paper_meta` / `build_okf_from_raw`）で `FileNotFoundError` が発生してパイプラインが停止する不具合を解消する。

### 再現手順 / Steps to Reproduce
1. コマンドラインから `python3 src/pipeline/arxiv_okf_fetcher.py --start-date 2026-08-26 --end-date 2026-09-01` を実行する。
2. `workspace_dir` が `src/pipeline` と判定され、`outputs/` 配下のファイルパスが不整合となり、`FileNotFoundError: [Errno 2] No such file or directory: '.../src/pipeline/outputs/raw_data/YYYY-MM-DD/...'` で異常終了する。

### 再現環境 / Environment
- OS / Env: Linux / Ubuntu 24.04 (Python 3.14+)
- File: `src/pipeline/arxiv_okf_fetcher.py`, `src/pipeline/transformer/okf_serializer.py`

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [src/pipeline/arxiv_okf_fetcher.py](../../src/pipeline/arxiv_okf_fetcher.py) (`_detect_workspace_dir`, `run_theme_pipeline`)
- [x] [src/pipeline/ingestion/arxiv_client.py](../../src/pipeline/ingestion/arxiv_client.py) (`load_config`)
- [x] [src/pipeline/transformer/okf_serializer.py](../../src/pipeline/transformer/okf_serializer.py) (`_load_raw_paper_meta`, `build_okf_from_raw`)
- [x] [tests/pipeline/test_pipeline.py](../../tests/pipeline/test_pipeline.py)
- [x] [tests/pipeline/test_multi_theme_pipeline.py](../../tests/pipeline/test_multi_theme_pipeline.py)

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
1. **なぜパスが `src/pipeline/outputs/...` になったか**:
   `src/pipeline/arxiv_okf_fetcher.py` の `_detect_workspace_dir()` が `for rel_path in ["..", "..", "."]:` と探索していた。`src/pipeline/` からリポジトリルート（`/workspace/arxiv-security-papers`）までは 2 階層（`../..`）離れているが、探索リストに `../..` が含まれておらず、`config.json` を検出できずにフォールバックで `current_dir` (`src/pipeline`) を返していた。
2. **なぜ `FileNotFoundError` に繋がったか**:
   原本データ保存処理と OKF シリアライザーの間で `workspace_dir` の解決基準がずれ、ファイル書き込み先と読み込み先で異なるパスが参照されたため。
3. **なぜテストで検知されなかったか**:
   単体テストは通常リポジトリルートを作業ディレクトリとして pytest で実行されていたため、相対パス解決の不整合が顕在化しにくかった。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**: 
  ルートディレクトリから `PYTHONPATH=src python3 src/pipeline/arxiv_okf_fetcher.py` を実行するか、`Makefile` の `make pipeline` を経由する。
* **恒久対策 (Permanent Fix)**: 
  - `_detect_workspace_dir()` を親ディレクトリ巡回走査アルゴリズム（`while cur != os.path.dirname(cur)`）に統一し、`config.json`, `pyproject.toml`, `Makefile`, `.agents` のいずれかが存在する真のリポジトリルートを確実に取得する。
  - `run_theme_pipeline` 内の `target_workspace` 解決を `workspace_dir or _detect_workspace_dir()` に統一。
  - ワークスペース検出関数の堅牢性を検証する単体テストを追加。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `fix/106-fix-pipeline-workspace-dir-and-raw-metadata-path`

### Phase 1: ワークスペース検出・パス解決ロジックの刷新
1. `src/pipeline/arxiv_okf_fetcher.py` の `_detect_workspace_dir()` をリファクタリング。
   - `cur = os.path.abspath(os.path.dirname(__file__))` からルート方向へ探索。
   - `config.json`, `pyproject.toml`, `Makefile`, `.agents` を検知して即時リターン。
2. `run_theme_pipeline()` において、引数 `workspace_dir` が空の場合のデフォルト値を `_detect_workspace_dir()` に統一。

### Phase 2: 単体テストと回帰テストの拡充
1. `tests/pipeline/test_pipeline.py` に `test_detect_workspace_dir_resolution()` を追加。
   - サブディレクトリや任意のカレントディレクトリから呼び出しても、常にリポジトリルートを正確に返すことをアサート。
2. `test_multi_theme_pipeline.py` でパスの整合性と OKF 出力先の一致を検証。

### Phase 3: 品質ゲート検証と実機フェッチ確認
1. `make check_format`, `make static_analysis`, `make test` を実行し、全ゲートをパスすることを確認。
2. 実コマンド `python3 src/pipeline/arxiv_okf_fetcher.py --start-date 2026-08-26 --end-date 2026-09-02` を実行し、エラーなく完了することを検証。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `python3 src/pipeline/arxiv_okf_fetcher.py` をどのカレントディレクトリから実行しても、リポジトリルート直下の `outputs/raw_data/` および `outputs/okf_papers/` に正しくデータが保存されること。
- [x] `FileNotFoundError` が発生せず、差分論文の取得・変換・サマリー更新が一気通貫で完了すること。
- [x] `tests/pipeline/` 配下にワークスペースパス解決を検証するテストが追加されていること。
- [x] `make check_format`, `make static_analysis`, `make test` が 100% PASS すること。
