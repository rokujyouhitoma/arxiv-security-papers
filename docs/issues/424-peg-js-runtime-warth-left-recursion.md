---
ID: 424
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] 内蔵 JavaScript PEG ランタイムへの Warth ('08) 左再帰解消アルゴリズムの移植 (ID: 424)

## 1. 概要 / Summary

バックエンドの `src/core/structures/peg.py` では、Warth et al. ('08) のシード成長アルゴリズム（`_eval_left_recursion`, `Head`, `LRResult`）により、直接・間接左再帰規則を有限回で安全に解決する仕組みが実装されている（Phase 5, Issue #304）。
一方、`JSCodeGenerator`（`src/core/structures/peg_compiler/codegen_js.py`）が出力する内蔵 JS ランタイム（`embedded_runtime`）は現在単純なメモ化 Packrat のみであり、左再帰文法（数式演算子結合や DSL 構文）をコンパイルして実行した場合、ブラウザや Node.js で `RangeError: Maximum call stack size exceeded`（スタック枯渇）が発生する。

本 Issue では、`peg.py` の Warth 式左再帰解消ロジックを `codegen_js.py` の内蔵 JavaScript ランタイムに完全移植し、Python と JavaScript のパーサー表現力・耐障害性の完全なパリティ（等価性）を確立する。

---

## 2. トレーサビリティ / Traceability

- **設計仕様書**:
  - [`docs/designs/DSN-25-pure_python_packrat_peg_parser_engine.md`](../designs/DSN-25-pure_python_packrat_peg_parser_engine.md) (第12.1節 左再帰解消 & カット演算子 Issue #304、第13節 Phase 6 JavaScript コードジェネレータ基盤)
- **関連 Issue**:
  - Issue #304: 左再帰の自然解決とカット演算子によるコミット枝刈り
  - Issue #417: WebフロントエンドJS向けPEGインラインパーサー換装およびPEG AOTコンパイラ JavaScriptコードジェネレータ基盤の実装

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [`src/core/structures/peg_compiler/codegen_js.py`](../../src/core/structures/peg_compiler/codegen_js.py)（内蔵 JS ランタイムへの `Head`, `LRResult`, `growLR` ロジックの追加）
- [ ] [`tests/test_peg_compiler_js.py`](../../tests/test_peg_compiler_js.py)（直接・間接左再帰文法の JS 実行テスト）

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/424-peg-js-runtime-warth-left-recursion`

1. **JS ランタイムへの LR データ構造の導入**:
   - `LR(seed, rule, head, next)` オブジェクトおよび `Head(rule, involvedSet, evalSet)` オブジェクトを JS ランタイムに追加。
2. **`Parser.prototype._evalCached` の LR 対応**:
   - 左再帰検知（コールスタック上の同一規則・同一位置の再入検知）。
   - シード成長ループ（`growLR`）の実装により、最長マッチまで結果を反復更新。
3. **テスト検証**:
   - `expr <- expr '+' term / term` のような直接左再帰文法および相互間接左再帰文法を JS にコンパイルし、正しく左結合 AST が得られることを Node.js 上でテスト。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] 内蔵 JS ランタイムが Warth et al. ('08) 左再帰解消をサポートし、無限再帰スタックオーバーフローを起こさないこと。
- [ ] 直接左再帰および間接左再帰文法のパース結果が、Python 側 `peg.py` の実行結果と完全一致すること。
- [ ] Xenon Rank A、flake8、mypy --strict をクリアすること。
- [ ] `tests/test_peg_compiler_js.py` に左再帰テストが追加され、100% PASS すること。
