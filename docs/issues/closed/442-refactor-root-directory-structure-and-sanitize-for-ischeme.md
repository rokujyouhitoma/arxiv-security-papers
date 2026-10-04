---
ID: 442
種別: Refactoring
優先度: High
ステータス: Closed (Resolved)
---

# [REFACTOR] トップレベルディレクトリの整理・衛生化と ischeme 統合に向けた構造基盤整備 (ID: 442)

## 1. 概要 / Summary
R7RS Scheme準拠の新言語処理系基盤 `ischeme` の導入に先立ち、現在トップレベルに散在している21個のディレクトリおよび各種設定・成果物ファイルの責務を再評価・整理する。
ルート直下に残存するキャッシュ（`__pycache__`）の完全一掃と `.gitignore` の衛生化、サブシステムの分類整理（Web/UI層、データ/マイグレーション層、文法/ツール層、パイプライン層）、および将来的な `ischeme/` 統合に向けた境界設計とドキュメント同期を実施する。

---

## 2. トレーサビリティ / Traceability
- 関連資料:
  - [AGENTS.md](../../.agents/AGENTS.md) (プロジェクトガバナンス & 品質ゲート規約)
  - [DSN-24 プロジェクト統合管理 CLI (manage.py) および対話型データベースシェル (dbshell) 設計書](../designs/DSN-24-unified_management_cli_and_interactive_database_shell.md)
  - [DSN-29 Python-LISP 統合アーキテクチャ設計仕様書 (pylisp)](../designs/DSN-29-python_lisp_integrated_architecture_specification.md)
  - [DSN-25 Pure-Python Packrat PEG Parser Engine](../designs/DSN-25-pure_python_packrat_peg_parser_engine.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [Makefile](../../Makefile) (クリーンアップターゲット `clean` の強化・ルート衛生化)
- [ ] [.gitignore](../../.gitignore) (ルート `__pycache__` および各種ビルド中間体の除外徹底)
- [ ] [README.md](../../README.md) (リポジトリ構成図の最新化・サブシステム分類の明記)
- [ ] [docs/README.md](../README.md) (アーキテクチャ体系目次とトップレベルディレクトリ対応表の更新)
- [ ] [docs/issues/README.md](README.md) (Issue台帳同期)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `refactor/442-refactor-root-directory-structure-and-sanitize-for-ischeme`

1. **ルート直下の衛生化とクリーンアップ強化**:
   - ルート直下の `__pycache__/` を完全除去。
   - `Makefile` の `clean` ターゲットを改修し、ルート直下および全サブディレクトリの `__pycache__`, `.pytest_cache`, `.mypy_cache` の一掃を確実に実行できるようにする。
   - `.gitignore` にルートキャッシュや中間成果物の漏れがないかを再点検。
2. **トップレベルディレクトリの責務マップと分類の策定**:
   - `manage.py`, `migrations/`, `site/`, `templates/`, `data/`, `grammars/`, `tools/`, `scripts/`, `src/`, `outputs/` の各ディレクトリの責務を [README.md](../../README.md) および [docs/README.md](../README.md) に明確なマップとして構造化。
   - 既存のUnixストリームパイプライン（`manage.py fetch | pdf-extract | ...`）および自作DBエンジン・PEGパーサとの互換性を100%維持。
3. **ischeme（R7RS Scheme基盤）統合に向けたアーキテクチャ受入準備**:
   - 既存の `src/pylisp`（DSN-29）と新設予定の `ischeme` の関係性を定義。
   - 将来的に `ischeme/` をトップレベルに新設しても、既存の `src/`, `manage.py`, `outputs/` と衝突せず共存できる配置規則を策定。
4. **品質ゲートの完全通過検証**:
   - `make check_format`
   - `make static_analysis`
   - `make test`

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] ルート直下の `__pycache__/` が除去され、`make clean` で確実にクリーンアップされること。
- [x] `.gitignore` が適切に更新され、未追跡の不要ファイルが発生しないこと。
- [x] トップレベルの全ディレクトリ・ファイルの役割分担が [README.md](../../README.md) に整理・明記されていること。
- [x] 既存の `manage.py`、Unixストリームパイプライン、DBマイグレーションの動作に一切の後退（回帰）がないこと。
- [x] `make check_format` (black, isort, flake8) がエラー 0 件で通過すること。
- [x] `make static_analysis` (Radon, Xenon, Mypy) がエラー 0 件で通過すること。
- [x] 単体・結合テスト（`make test`）が全件合格すること。
- [x] [docs/issues/README.md](README.md) の台帳が更新されていること。
