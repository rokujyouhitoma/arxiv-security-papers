---
ID: 441
種別: Refactoring
優先度: Medium
ステータス: Closed
---

# [FEAT/ENH] src/pdf_engine 配下の BibTeX および CMap モジュールのサブパッケージ化 (ID: 441)

## 1. 概要 / Summary
`src/pdf_engine/` 直下にフラットに配置されていた BibTeX 関連モジュール（`bibtex_extractor.py`, `bibtex_helpers.py`, `generated_bibtex_parser.py`）および CMap デコード関連モジュール（`cmap_helpers.py`, `generated_cmap_parser.py`）を、凝集度の高い独立したサブパッケージ `src/pdf_engine/bibtex/` および `src/pdf_engine/cmap/` へ構造化・再編する。
既存のコードベース・テストコードに対する 100% の後方互換性を保証するため、`src/pdf_engine/` 直下の旧ファイルパスには `# noqa` を一切使わない型安全な再エクスポート shim を配置する。

## 2. トレーサビリティ / Traceability
- 関連資料:
  - `src/pdf_engine/bibtex_extractor.py`
  - `src/pdf_engine/bibtex_helpers.py`
  - `src/pdf_engine/generated_bibtex_parser.py`
  - `src/pdf_engine/cmap_helpers.py`
  - `src/pdf_engine/generated_cmap_parser.py`
  - `grammars/bibtex.peg`
  - `grammars/pdf_cmap.peg`
  - [DSN-13: Pure Python PDF Text Extractor](../../docs/designs/DSN-13-pure_python_pdf_text_extractor.md)
  - [DSN-25: Pure-Python Packrat PEG Parser Engine](../../docs/designs/DSN-25-pure_python_packrat_peg_parser_engine.md)

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [src/pdf_engine/bibtex/__init__.py](file:///workspace/arxiv-security-papers/src/pdf_engine/bibtex/__init__.py)
- [x] [src/pdf_engine/bibtex/extractor.py](file:///workspace/arxiv-security-papers/src/pdf_engine/bibtex/extractor.py)
- [x] [src/pdf_engine/bibtex/helpers.py](file:///workspace/arxiv-security-papers/src/pdf_engine/bibtex/helpers.py)
- [x] [src/pdf_engine/bibtex/generated_parser.py](file:///workspace/arxiv-security-papers/src/pdf_engine/bibtex/generated_parser.py)
- [x] [src/pdf_engine/cmap/__init__.py](file:///workspace/arxiv-security-papers/src/pdf_engine/cmap/__init__.py)
- [x] [src/pdf_engine/cmap/helpers.py](file:///workspace/arxiv-security-papers/src/pdf_engine/cmap/helpers.py)
- [x] [src/pdf_engine/cmap/generated_parser.py](file:///workspace/arxiv-security-papers/src/pdf_engine/cmap/generated_parser.py)
- [x] [src/pdf_engine/bibtex_extractor.py](file:///workspace/arxiv-security-papers/src/pdf_engine/bibtex_extractor.py) (shim)
- [x] [src/pdf_engine/bibtex_helpers.py](file:///workspace/arxiv-security-papers/src/pdf_engine/bibtex_helpers.py) (shim)
- [x] [src/pdf_engine/generated_bibtex_parser.py](file:///workspace/arxiv-security-papers/src/pdf_engine/generated_bibtex_parser.py) (shim)
- [x] [src/pdf_engine/cmap_helpers.py](file:///workspace/arxiv-security-papers/src/pdf_engine/cmap_helpers.py) (shim)
- [x] [src/pdf_engine/generated_cmap_parser.py](file:///workspace/arxiv-security-papers/src/pdf_engine/generated_cmap_parser.py) (shim)
- [x] [grammars/bibtex.peg](file:///workspace/arxiv-security-papers/grammars/bibtex.peg)
- [x] [grammars/pdf_cmap.peg](file:///workspace/arxiv-security-papers/grammars/pdf_cmap.peg)
- [x] [Makefile](file:///workspace/arxiv-security-papers/Makefile)

## 4. 実装方針 / Implementation Plan
Target Branch: `refactor/441-modularize-pdf-engine-bibtex-and-cmap-subpackages`

1. `src/pdf_engine/bibtex/` ディレクトリ新設:
   - `extractor.py`: `core.peg` 参照是正および `bibtex` サブパッケージ内相対インポート。
   - `helpers.py`: `BibTeXEntry` およびヘルパー関数。
   - `__init__.py`: 主要関数・データクラスのエクスポート。
2. `src/pdf_engine/cmap/` ディレクトリ新設:
   - `helpers.py`: CMap デコード関数。
   - `__init__.py`: 主要パーサー・ヘルパーのエクスポート。
3. `grammars/bibtex.peg` および `grammars/pdf_cmap.peg` の `@header` インポートを新サブパッケージパスへ更新。
4. `Makefile` の `compile_grammars` ターゲットを新生成先（`src/pdf_engine/bibtex/generated_parser.py` および `src/pdf_engine/cmap/generated_parser.py`）に更新し、`make compile_grammars` を実行。
5. `src/pdf_engine/` 直下に後方互換性 shim を配置（`# noqa` 完全不使用、`__all__ = [...]` による明示的エクスポート）。
6. テスト実行（`pytest tests/pdf_engine/`）により全機能が正常稼働することを確認。
7. `make check_format` および `make static_analysis` (Xenon Rank A, Mypy Strict) による品質ゲート検証。

## 5. 完了条件 / Success Criteria (DoD)
- [x] `src/pdf_engine/bibtex/` および `src/pdf_engine/cmap/` が適切にサブパッケージとして構築されていること。
- [x] 旧ファイルパスに配置された shim モジュールが `# noqa` なしで型安全にエクスポートされていること。
- [x] `make compile_grammars` が新パスでクリーンにパーサーを生成できること。
- [x] `pytest tests/pdf_engine/` が全件合格すること。
- [x] `make check_format` および `make static_analysis` がエラー0件でパスすること。
- [x] Issue 台帳および Git 履歴の更新完了。

