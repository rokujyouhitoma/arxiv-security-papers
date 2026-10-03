---
ID: 425
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] JS コードジェネレータにおける CharClass の文字コード範囲判定化と ReDoS 根絶 (ID: 425)

## 1. 概要 / Summary

バックエンドの `src/core/structures/peg.py` では、文字クラス（`CharClass`）の判定を正規表現エンジンを用いず、事前パースされた文字コード範囲リスト `(start_ord, end_ord)` および単一文字集合による直接比較で行うことで、ReDoS（破局的バックトラッキング）を根絶し $O(1)$ 判定を保証している（Phase 4, Issue #298）。
しかし、`JSCodeGenerator`（`src/core/structures/peg_compiler/codegen_js.py`）では、現在 `charClass` コンビネータが実行時に `new RegExp('[' + spec + ']')` を生成している。この実装は、未エスケープ文字（`/` や `]`）によるコンパイル例外のリスクがあり、ブラウザ正規表現エンジンに依存するためバックエンドほどの決定論的安全性・速度保証が得られない。

本 Issue では、AOT コンパイル時に文字クラス式（`CharClassExpr`）を整数文字コード範囲配列 `[[start1, end1], ...]` と単一文字コード配列に事前解決し、JS ランタイム側で `text.charCodeAt(pos)` による完全 $O(1)$ 直接範囲比較を行うコードを出力するよう刷新する。

---

## 2. トレーサビリティ / Traceability

- **設計仕様書**:
  - [`docs/designs/DSN-25-pure_python_packrat_peg_parser_engine.md`](../designs/DSN-25-pure_python_packrat_peg_parser_engine.md) (第11.3節 セルフホスティング Fixpoint 不変性と ReDoS 根絶、第13節 Phase 6 JavaScript コードジェネレータ基盤)
- **関連 Issue**:
  - Issue #298: Bryan Ford 論文（POPL '04）公式文法仕様への改定と実用的拡張
  - Issue #417: WebフロントエンドJS向けPEGインラインパーサー換装およびPEG AOTコンパイラ JavaScriptコードジェネレータ基盤の実装

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [`src/core/structures/peg_compiler/codegen_js.py`](../../src/core/structures/peg_compiler/codegen_js.py)（文字コード範囲展開ロジックおよび JS ランタイム `CharClass` の刷新）
- [ ] [`tests/test_peg_compiler_js.py`](../../tests/test_peg_compiler_js.py)（特殊文字・反転文字クラス・範囲境界値テスト）

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/425-peg-js-charclass-range-evaluation-and-redos-eradication`

1. **コンパイル時範囲展開**:
   - `CharClassExpr.raw_spec` を解析し、Python 側で `ranges: List[Tuple[int, int]]` および `singles: List[int]` を導出。
2. **JS ランタイム `CharClass` の直接比較化**:
   - `function CharClass(ranges, singles, inverted)` を JS ランタイムに実装。
   - `code = ctx.text.charCodeAt(pos)` に対し、ループまたは二分探索で範囲判定を実行。正規表現呼び出しを完全撤廃。
3. **テスト検証**:
   - `[a-zA-Z0-9_]`, `[^0-9]`, `[\x00-\x1f]`, 特殊記号（`/`, `]`, `\`, `-`）を含む文字クラスが期待通り高速かつ安全に判定されることを検証。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] JS 生成コードにおいて `RegExp` による文字クラス判定が撤廃され、文字コード直接判定になること。
- [ ] エスケープ漏れによる JavaScript ランタイムエラーが根絶されること。
- [ ] 反転文字クラス（`[^...]`）が正しく動作すること。
- [ ] Xenon Rank A、flake8、mypy --strict をクリアすること。
- [ ] 単体・回帰テストが 100% PASS すること。
