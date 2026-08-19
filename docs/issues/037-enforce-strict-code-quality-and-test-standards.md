---
ID: 037
種別: Feature / Quality / Refactor
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] Makefile およびパイプラインにおける品質・テスト・ビルド基準の極限厳格化 (ID: 037)

## 1. 概要 / Summary

Makefile に含まれる各種ツール（静的解析、フォーマッタ、型チェック、テスト、ビルド設定）の基準をより厳格（Strict）に改修し、コードベース全体の堅牢性、保守性、およびテスト網羅率を飛躍的に向上させます。

### 必須改修要件（7大項目）

1. **Xenon の複雑度閾値の厳格化**
   - 現状の `--max-absolute F --max-modules D --max-average A` を以下のように厳格化：
     - `--max-absolute B`（絶対最大値を B 以下に制限、関数分割・リファクタリング実施）
     - `--max-modules A` または `B`
     - `--max-average A`

2. **Mypy の型チェック厳格化**
   - `--strict` フラグを追加し、型アノテーションの欠落や曖昧な `Any` の使用を防止。
   - `--disallow-untyped-defs`, `--no-implicit-optional` などを明示。

3. **フォーマッタ検証モード（CI/Gate用）の分離と追加**
   - `black --check --diff` および `isort --check-only --diff` を用いた差分チェック用ターゲット（例: `check_format`）を作成し、品質ゲート（`check`, `verify_quality`, `pre-commit`）に組み込み。

4. **Pytest の厳格化とカバレッジ基準の導入**
   - `--strict-markers`, `-W error`（警告をエラー扱いにする設定）を追加。
   - `pytest-cov` によるカバレッジ計測と最低カバレッジ基準（`--cov=src --cov-fail-under=80`）を導入。

5. **Google Closure Compiler の厳格化**
   - `--compilation_level ADVANCED_OPTIMIZATIONS` への引き上げ、または警告をエラーにする `--jscomp_error=*` の追加。

6. **Python バージョンの厳格な固定**
   - Python 3.14 未満の予期せぬ実行を防ぐため、`which python3` への安易なフォールバックを排除し、指定バージョンが見つからない場合はエラー終了するように改修。

7. **ソースファイル指定の保守性向上**
   - `PYTHON_SRCS` の個別手動リストアップから `src` ディレクトリ配下の一括探索（`find` またはワイルドカード）へのリファクタリング、新規追加ファイルが自動で解析対象に入る仕組みを確立。

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [Makefile](../../Makefile) (品質チェックターゲット、コンパイラ設定、Python バインディング、ファイル探索の刷新)
- [ ] [pyproject.toml](../../pyproject.toml) (pytest, mypy, coverage, flake8 設定の厳格化同期)
- [ ] [.githooks/pre-commit](../../.githooks/pre-commit) (厳格化されたフォーマットチェック・静的解析の適用)
- [ ] `src/` 配下の全 Python ソースコード（複雑度ランク B 超過関数の分割、厳格型アノテーション対応）
- [ ] `site/` 配下の JavaScript ソースコードおよび externs 定義（Closure Compiler Advanced 最適化適合）

---

## 3. 実装方針 / Implementation Plan

Target Branch: `feat/037-enforce-strict-code-quality-and-test-standards`

1. **Python バージョン検査 & `PYTHON_SRCS` 自動探索化**:
   - Makefile 内で Python 3.14.x の厳格チェックを実装。
   - `PYTHON_SRCS := $(shell find src -name "*.py" | sort)` に刷新。
2. **フォーマッタ検証ターゲット `check_format` 新設**:
   - `isort --check-only --diff`, `black --check --diff` による非破壊検査ターゲットを追加。
3. **Xenon 複雑度 B 適合リファクタリング**:
   - `step()`, `execute_statement()`, `_matches_where_clause()`, `retrieve_candidates()` 等のランク C/D/E/F 関数をヘルパーメソッドへ分割し、全ブロックランク B 以下を達成。
4. **Mypy `--strict` 適合**:
   - 全関数・メソッドの型定義完全化、厳格型推論の適用。
5. **Pytest `--strict-markers -W error --cov=src --cov-fail-under=80` 導入**:
   - 警告の根絶、テストカバレッジ 80% 以上の達成と保証。
6. **Closure Compiler 厳格化**:
   - `--jscomp_error=*` / ADVANCED_OPTIMIZATIONS の適用と externs 整合。

---

## 4. 完了条件 / Success Criteria (DoD)

- [ ] `Makefile` で Python 3.14 が厳格に要求され、未検出時にエラー終了すること
- [ ] `PYTHON_SRCS` が自動探索となり、全 Python ファイルが漏れなく対象となること
- [ ] `xenon --max-absolute B --max-modules B --max-average A src` がエラー 0 件で通過すること
- [ ] `mypy --strict src` がエラー 0 件で通過すること
- [ ] `make check_format` が正常終了すること
- [ ] `pytest --strict-markers -W error --cov=src --cov-fail-under=80` が 100% PASS すること
- [ ] Google Closure Compiler の厳格チェックがエラー 0 件で通過すること
