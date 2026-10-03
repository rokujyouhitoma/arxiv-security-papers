---
ID: 439
種別: Refactoring
優先度: Medium
ステータス: Closed
---

# [FEAT/ENH] tools/ パッケージ・CLIの再編・統合と PEG コンパイラツールの近代化 (ID: 439)

## 1. 概要 / Summary
`src/core/peg` への移行完了に伴い、`tools/peg_compiler/` を新パッケージ構造に適合した `tools/peg/` へ再編し、`python -m core.peg.compiler` による標準 CLI 起動との統合を行う。同時に、既存の呼び出し元および互換性のための `tools/peg_compiler/compile_peg.py` シムを維持し、`Makefile` のグラマービルド規則を最新体系に更新する。

## 2. トレーサビリティ / Traceability
- 関連資料:
  - `src/core/peg/compiler/`
  - `tools/peg_compiler/compile_peg.py`
  - [DSN-25: Pure-Python Packrat PEG Parser Engine](../../docs/designs/DSN-25-pure_python_packrat_peg_parser_engine.md)
  - Issue #437 (PEG ランタイムおよびコンパイラの src/core/peg への移設)

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [tools/peg/compile_peg.py](file:///workspace/arxiv-security-papers/tools/peg/compile_peg.py)
- [x] [tools/peg/__init__.py](file:///workspace/arxiv-security-papers/tools/peg/__init__.py)
- [x] [tools/peg_compiler/compile_peg.py](file:///workspace/arxiv-security-papers/tools/peg_compiler/compile_peg.py)
- [x] [Makefile](file:///workspace/arxiv-security-papers/Makefile)
- [x] [docs/designs/DSN-25-pure_python_packrat_peg_parser_engine.md](file:///workspace/arxiv-security-papers/docs/designs/DSN-25-pure_python_packrat_peg_parser_engine.md)

## 4. 実装方針 / Implementation Plan
Target Branch: `refactor/439-modernize-and-restructure-tools-peg-and-cli`

1. `tools/peg/` ディレクトリ新設および `tools/peg/compile_peg.py`、`tools/peg/__init__.py` の配置。
2. `tools/peg_compiler/compile_peg.py` を後方互換ラッパーとして整理。
3. `Makefile` 内の `compile_grammars` ターゲットを `PYTHONPATH=src ${VENV_PYTHON} -m core.peg.compiler` または `tools/peg/compile_peg.py` に統一。
4. `make compile_grammars` の実行確認および全グラマーファイルの再ビルド整合性確認。
5. `DSN-25` 設計書の更新（`tools/peg/` への更新と互換性レイヤーの明記）。

## 5. 完了条件 / Success Criteria (DoD)
- [x] `tools/peg/compile_peg.py` および `python -m core.peg.compiler` が正常に動作すること。
- [x] `tools/peg_compiler/compile_peg.py` が後方互換シムとして壊れずに機能すること。
- [x] `make compile_grammars` がエラーなく全パーサーを再コンパイルできること。
- [x] `make check_format` および `make static_analysis` (Xenon A, Mypy Strict) が合格すること。
- [x] DSN-25 および Issue 台帳が更新されていること。
