# [FEAT/ENH] PEG ランタイムおよびコンパイラの src/core/peg への移設と Backend 分離のアーキテクチャ刷新 (ID: 437)

## メタデータ
- **ID**: 437
- **種別**: Refactoring / Architecture Enhancement
- **優先度**: High
- **ステータス**: Closed (Completed)
- **作成日**: 2026-10-04
- **完了日**: 2026-10-04
- **ブランチ**: `refactor/437-migrate-peg-compiler-to-core-peg-with-backend-separation`

---

## 1. 概要 / Summary

現在、Packrat PEG 構文解析ランタイム（`peg.py`）および事前 AOT コンパイラ（`peg_compiler/`）が `src/core/structures/` 配下に配置されている。しかし、`structures/` は本来 BloomFilter や SkipList などの純粋なデータ構造を収容する責務を負っており、言語処理系・コンパイラ基盤としての責務を併せ持つことでパッケージの凝集度が低下し、責務分離（Single Responsibility Principle）の観点で不自然な状態となっていた。

本 Issue では、PEG ランタイムおよびコンパイラ群を独立したドメインパッケージ `src/core/peg/` に集約・移設する。
さらに、LLVM のコンパイラ設計思想（Frontend / Middle-End / Backend の明確な責務分離）を取り入れ、ターゲットコード生成器を `backend/` サブパッケージ配下に `python.py` および `javascript.py` として対称化し、共通基底クラス `BaseCodeGenerator` を導入して将来の多言語ターゲット拡張を容易にする。
テストスイート側も対称に `tests/core/peg/` 配下へ再編（`runtime`、`compiler`、`backend`）し、一貫性を確立した。
既存の呼び出し元および生成コードに対する無停止・完全な後方互換性（Backward Compatibility）を担保するための shim（`# noqa` 非依存）も併せて整備した。
また、基本設計仕様書 `docs/designs/DSN-25-pure_python_packrat_peg_parser_engine.md` を最新アーキテクチャに合わせて更新した。

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files

### 新規作成 / 移設先ファイル (`src/core/peg/`)
- `src/core/peg/__init__.py` (公開 API エクスポート)
- `src/core/peg/runtime.py` (旧 `src/core/structures/peg.py`)
- `src/core/peg/compiler/__init__.py` (コンパイラ公開 API エクスポート)
- `src/core/peg/compiler/ast_nodes.py` (旧 `src/core/structures/peg_compiler/ast_nodes.py`)
- `src/core/peg/compiler/parser.py` (旧 `src/core/structures/peg_compiler/meta_grammar.py`)
- `src/core/peg/compiler/generated_meta_parser.py` (セルフホスティング生成メタパーサー)
- `src/core/peg/compiler/optimizer.py` (旧 `src/core/structures/peg_compiler/optimizer.py`)
- `src/core/peg/compiler/cli.py` (旧 `src/core/structures/peg_compiler/cli.py`)
- `src/core/peg/compiler/backend/__init__.py`
- `src/core/peg/compiler/backend/base.py` (`BaseCodeGenerator` 共通抽象基底クラス)
- `src/core/peg/compiler/backend/python.py` (旧 `src/core/structures/peg_compiler/codegen.py`)
- `src/core/peg/compiler/backend/javascript.py` (旧 `src/core/structures/peg_compiler/codegen_js.py`)

### 後方互換性 shim ファイル (`src/core/structures/`)
- `src/core/structures/peg.py` (明示的 `__all__` 再エクスポート shim)
- `src/core/structures/peg_compiler/__init__.py`
- `src/core/structures/peg_compiler/ast_nodes.py`
- `src/core/structures/peg_compiler/cli.py`
- `src/core/structures/peg_compiler/codegen.py`
- `src/core/structures/peg_compiler/codegen_js.py`
- `src/core/structures/peg_compiler/meta_grammar.py`
- `src/core/structures/peg_compiler/optimizer.py`
- `src/core/structures/peg_compiler/generated_meta_parser.py`
- `src/core/structures/__init__.py`

### テストスイートの対称化 (`tests/core/peg/`)
- `tests/core/peg/test_runtime.py`
- `tests/core/peg/test_cut_and_resilient.py`
- `tests/core/peg/test_expected_tokens.py`
- `tests/core/peg/test_left_recursion.py`
- `tests/core/peg/test_fuzzing.py`
- `tests/core/peg/test_package_architecture.py`
- `tests/core/peg/compiler/test_compiler.py`
- `tests/core/peg/compiler/test_bootstrap.py`
- `tests/core/peg/compiler/test_optimizer.py`
- `tests/core/peg/compiler/test_paper_syntax.py`
- `tests/core/peg/compiler/backend/test_python.py`
- `tests/core/peg/compiler/backend/test_javascript.py`

### ビルドツール・文法・設計書
- `tools/peg_compiler/compile_peg.py`
- `Makefile` (`compile_grammars`, `build_cti_query_parser`, `verify_peg_bootstrap` ルール等)
- `grammars/peg_meta.peg`
- `docs/designs/DSN-25-pure_python_packrat_peg_parser_engine.md`

---

## 3. 完了条件 (Definition of Done)

- [x] `src/core/peg/` 配下に `runtime.py`、`compiler/`、`compiler/backend/` が構築されていること。
- [x] `BaseCodeGenerator` が導入され、`python.py` および `javascript.py` が統一的に抽象化されていること。
- [x] `tests/core/peg/` に `runtime`、`compiler`、`backend` の対称テストツリーが配備され、全 75 テストが PASS すること。
- [x] `src/core/structures/peg.py` および `src/core/structures/peg_compiler/` に `# noqa` を使わない明示的 `__all__` shim が配置され、既存コードの完全な後方互換性が維持されていること。
- [x] `make compile_grammars` が正常終了し、すべての自動生成パーサーが新パッケージ構成でクリーンに再生成されること。
- [x] `docs/designs/DSN-25-pure_python_packrat_peg_parser_engine.md` が最新アーキテクチャに更新されていること。
- [x] `make format`、`make static_analysis`（Xenon Rank A, Mypy Strict）、`make test` が 100% PASS すること。
