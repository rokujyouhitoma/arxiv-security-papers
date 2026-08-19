---
ID: 037
種別: Feature / Quality / Refactor
優先度: High
ステータス: Closed (Completed)
---

# [FEAT/ENH] Makefile およびパイプラインにおける品質・テスト・ビルド基準の極限厳格化 (ID: 037)

## 1. 概要 / Summary

Makefile に含まれる各種ツール（静的解析、フォーマッタ、型チェック、テスト、ビルド設定）の基準をより厳格（Strict）に改修し、コードベース全体の堅牢性、保守性、およびテスト網羅率を飛躍的に向上させます。

### 必須改修要件（7大項目）

1. **Xenon の複雑度閾値の厳格化**
   - 現状の `--max-absolute F --max-modules D --max-average A` を以下のように厳格化：
     - `--max-absolute B`（絶対最大値を B 以下に制限、関数分割・リファクタリング実施）
     - `--max-modules B`（モジュール複雑度を B 以下に制限）
     - `--max-average A`（コードベース全体平均複雑度 A を維持）

2. **Mypy の型チェック厳格化**
   - `--strict` フラグを追加し、型アノテーションの欠落や曖昧な `Any` の使用を防止。
   - `--disallow-untyped-defs`, `--no-implicit-optional`, `--warn-unused-ignores` を明示。

3. **フォーマッタ検証モード（CI/Gate用）の分離と追加**
   - `black --check --diff` および `isort --check-only --diff` を用いた差分チェック用ターゲット（`check_format`）を作成し、品質ゲート（`check`, `verify_quality`, `pre-commit`）に組み込み。

4. **Pytest の厳格化とカバレッジ基準の導入**
   - `--strict-markers`, `-W error`（警告をエラー扱いにする設定）を追加。
   - `pytest-cov` によるカバレッジ計測と最低カバレッジ基準（`--cov=src --cov-fail-under=80`）を導入。

5. **Google Closure Compiler の厳格化**
   - `--jscomp_error="*"` の追加によりすべての JS コンパイラ警告をエラーとして扱いビルドをブロック。

6. **Python バージョンの厳格な固定**
   - Python 3.14 未満の予期せぬ実行を防ぐため、`which python3` への安易なフォールバックを排除し、指定バージョンが見つからない場合は `$(error ...)` で即時中断。

7. **ソースファイル指定の保守性向上**
   - `PYTHON_SRCS` および `TESTS` の個別手動リストアップから `find` による自動探索へリファクタリング。

---

## 2. トレーサビリティ / Traceability

- 関連資料:
  - [AGENTS.md](../../.agents/AGENTS.md) (第1条 ソフトウェア品質保証専門家・システム監査人ガイドライン、第3条 必須品質ゲート)
  - [verify-quality-gates/SKILL.md](../../.agents/skills/verify-quality-gates/SKILL.md)
  - [pyproject.toml](../../pyproject.toml)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [Makefile](../../Makefile) (Python バージョン固定、ファイル自動探索、check_format 新設、Xenon B、Mypy strict、Pytest cov 80%、Closure Compiler 厳格化)
- [ ] [pyproject.toml](../../pyproject.toml) (pytest, mypy, coverage, flake8 設定の厳格化同期)
- [ ] [.githooks/pre-commit](../../.githooks/pre-commit) (厳格化されたフォーマットチェック・静的解析の適用)
- [ ] `src/database/vdbe.py` (VDBE `step()` の OpCode 別ハンドラ分割リファクタリング)
- [ ] `src/database/sql/executor.py` (`execute_statement()`, `_matches_where_clause()` の文種別・条件別ハンドラ分割)
- [ ] `src/database/storage.py` (`_load_existing_file()` の分割)
- [ ] `src/mcp/base.py` (`run_mcp_server()` の JSON-RPC メソッド別ハンドラ分割)
- [ ] `src/search/vector_engine.py` (`retrieve_candidates()` のインデックス別検索分割)
- [ ] `src/search/query/query_parser.py` (`parse()`, `create_context()` のクエリ構文解析分割)
- [ ] `src/search/core/index/postings.py` (`_levenshtein()` の分割)
- [ ] `src/search/ingestion/fm_index.py` (`count_substring()` の分割)
- [ ] `src/fetcher/reporter/index_updater.py` (モジュール複雑度 B 適合)
- [ ] `src/` 配下の全 Python ソースコード（Mypy `--strict` 適合の型アノテーション追加）
- [ ] `tests/` 配下のテストスイート（カバレッジ 80% 未満モジュールのテスト拡充）

---

## 4. 詳細設計・実装方針 / Implementation Plan

Target Branch: `feat/037-enforce-strict-code-quality-and-test-standards`

### Phase 1: Makefile & 設定基盤の厳格化
1. **Python 3.14 固定 & 自動ファイル探索**:
   - `Makefile` 内で `python3.14` / `python3.14t` を探索し、未検出時は `$(error ...)` で停止。
   - `PYTHON_SRCS := $(shell find src -type f -name "*.py" | sort)`
   - `TESTS := $(shell find tests -type f -name "*.py" | sort)`
2. **フォーマット検査ターゲット `check_format`**:
   - `isort --check-only --diff`, `black --check --diff`, `flake8` を実行するターゲットを追加。
3. **Closure Compiler 厳格化**:
   - `--warning_level VERBOSE --jscomp_error="*"` を設定。

### Phase 2: 循環的複雑度（Xenon ランク B 以下）リファクタリング
1. **`src/database/vdbe.py`**:
   - `step()` の 40 以上の OpCode 分岐を `_exec_init`, `_exec_open_read`, `_exec_seek`, `_exec_insert`, `_exec_vector_ops` 等のハンドラ辞書／メソッドへディスパッチ分割。
2. **`src/database/sql/executor.py`**:
   - `execute_statement()` を `_exec_select`, `_exec_insert`, `_exec_update`, `_exec_delete`, `_exec_ddl`, `_exec_dcl`, `_exec_tcl` に分割。
   - `_matches_where_clause()` を比較演算子ハンドラに分割。
3. **`src/mcp/base.py` & `src/search/vector_engine.py`**:
   - リクエストディスパッチおよびマルチインデックス探索を個別ハンドラに分割。
4. **その他のランク C 超過ブロック**:
   - クエリパーサー、FM-Index、Levenshtein 探索を分割し、全ブロックランク B 以下を達成。

### Phase 3: Mypy `--strict` 全面適合
1. `src/` 配下の全 113 ファイルに対して `--strict` を適用。
2. 未型付け引数・戻り値（`def func() -> None:` 等）、`Optional` / `Union` の厳格指定、ジェネリクス型引数の明示。

### Phase 4: テスト厳格化 & カバレッジ 80% 達成
1. `pytest --strict-markers -W error --cov=src --cov-fail-under=80` の適用。
2. `pyproject.toml` に pytest 厳格設定を同期。
3. カバレッジ不足モジュールに対する単体テストケース追加。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `Makefile` で Python 3.14 が厳格に要求され、未検出時にエラー終了すること
- [ ] `PYTHON_SRCS` および `TESTS` が自動探索となり、新規ファイルが自動で対象となること
- [ ] `xenon --max-absolute B --max-modules B --max-average A src` がエラー 0 件で完全通過すること
- [ ] `mypy --strict src` がエラー 0 件で完全通過すること
- [ ] `make check_format` がエラー 0 件で完全通過すること
- [ ] `pytest --strict-markers -W error --cov=src --cov-fail-under=80 tests` が 100% PASS すること
- [ ] Google Closure Compiler の厳格チェック（`--jscomp_error="*"`）がエラー 0 件で通過すること
- [ ] `.githooks/pre-commit` が厳格な品質ゲートとして機能すること

