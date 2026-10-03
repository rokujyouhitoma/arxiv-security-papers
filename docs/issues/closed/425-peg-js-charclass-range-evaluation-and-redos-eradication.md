---
ID: 425
種別: Feature
優先度: High
ステータス: Closed (Completed)
完了日: 2026-10-03
---

# [FEAT/ENH] JS コードジェネレータにおける CharClass の文字コード範囲判定化と ReDoS 根絶 (ID: 425)

## 1. 概要 / Summary

バックエンドの `src/core/structures/peg.py` では、文字クラス（`CharClass`）の判定を正規表現エンジンを用いず、事前パースされた文字コード範囲リスト `(start_ord, end_ord)` および単一文字集合による直接比較で行うことで、ReDoS（破局的バックトラッキング）を根絶し $O(1)$ 判定を保証している（Phase 4, Issue #298）。
しかし、`JSCodeGenerator`（`src/core/structures/peg_compiler/codegen_js.py`）では、現在 `charClass` コンビネータが実行時に `new RegExp('[' + spec + ']')` を生成している。この実装は、未エスケープ文字（`/` や `]`、`-`）による構文エラーや正規表現コンパイル例外のリスクがあり、ブラウザ正規表現エンジンに依存するためバックエンドほどの決定論的安全性・速度保証が得られない。

本 Issue では、AOT コンパイル時に文字クラス式（`CharClassExpr`）を整数文字コード範囲配列 `[[start1, end1], ...]` と単一文字コード配列 `[ord1, ord2, ...]` に事前解決し、JS ランタイム側で `text.charCodeAt(pos)` による完全 $O(1)$ 直接範囲比較を行うクラス `CharClass` を出力するよう刷新する。併せて `anyChar()` も正規表現（`reg(/[\s\S]/)`）から純粋な文字長判定 `AnyChar` に刷新し、生成 JS パーサーから不要な正規表現オブジェクトを徹底排除する。

---

## 2. トレーサビリティ / Traceability

- **設計仕様書**:
  - [`docs/designs/DSN-25-pure_python_packrat_peg_parser_engine.md`](../designs/DSN-25-pure_python_packrat_peg_parser_engine.md) (第11.3節 セルフホスティング Fixpoint 不変性と ReDoS 根絶、第13.6節 文字クラス（CharClass）の文字コード範囲判定化と ReDoS 根絶)
- **関連 Issue**:
  - Issue #298: Bryan Ford 論文（POPL '04）公式文法仕様への改定と実用的拡張
  - Issue #417: WebフロントエンドJS向けPEGインラインパーサー換装およびPEG AOTコンパイラ JavaScriptコードジェネレータ基盤の実装
  - Issue #423: PEG AOT コンパイラにおける --ast-only 汎用構文木生成とアクション抽象化の実装
  - Issue #424: 内蔵 JavaScript PEG ランタイムへの Warth ('08) 左再帰解消アルゴリズムの移植

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

### コンパイラ & ランタイム基盤
- [x] [`src/core/structures/peg_compiler/codegen_js.py`](../../src/core/structures/peg_compiler/codegen_js.py)
  - 文字クラス解析ヘルパー `_parse_char_class_spec(spec: str) -> Tuple[List[List[int]], List[int]]` の実装（Xenon Rank A 遵守）
  - `_emit_char_class(expr: CharClassExpr) -> str` の刷新（範囲配列・単一コード配列・反転フラグのコード生成）
  - 内蔵 JS ランタイムにおける `CharClass` クラス、`AnyChar` クラス、およびファクトリ関数の刷新（`RegExp` 全廃）

### テスト
- [x] [`tests/test_peg_compiler_js.py`](../../tests/test_peg_compiler_js.py)
  - 英数字範囲 `[a-zA-Z0-9_]` のマッチ検証
  - 反転文字クラス `[^0-9 \t\r\n]` のマッチ検証
  - エスケープ文字・特殊記号（`[\]\-\/\n\t]`）の安全性検証
  - EOF 境界値、マッチ失敗時の `maxPos` / 診断メッセージ検証

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/425-peg-js-charclass-range-evaluation-and-redos-eradication`

### 4.1 Python 側 AOT 文字クラス仕様解析 (`codegen_js.py`)
- `_tokenize_class_spec(spec: str) -> List[Tuple[str, bool]]` および `_parse_class_tokens(tokens: List[Tuple[str, bool]]) -> Tuple[List[List[int]], List[int]]` を実装。
- バックスラッシュエスケープ（`\n`, `\t`, `\r`, `\\`, `\]`, `\-`, `\/`）を正確にデコード。
- エスケープされたハイフン `\-` と範囲区切り文字 `-` を厳格に分離。
- 範囲（`a-z`）を `[ord('a'), ord('z')]` のタプルとして抽出し、重複のないソート済みリストに正規化。
- 単一文字は単一 ord の昇順ソート済みリストとして抽出。

### 4.2 JavaScript 内蔵ランタイムにおける `CharClass` クラス
- `function CharClass(ranges, singles, inverted, name)`:
  - `Parser.call(this, name || 'CharClass', false);` (memoize: false)
  - `pos >= ctx.length` の EOF ガード。
  - `var code = ctx.text.charCodeAt(pos);`
  - `ranges` のループ判定（`code >= r[0] && code <= r[1]`）。
  - `singles` の判定（要素数 > 8 の場合は `Set` キャッシュ、それ以外は線形ループ）。
  - `this.inverted ? !matched : matched` による判定。
  - 成功時は `new ParseResult(true, ctx.text[pos], pos + 1)`、失敗時は `ctx.updateMaxPos` とエラーメッセージ返却。

### 4.3 JavaScript 内蔵ランタイムにおける `AnyChar` クラス
- `function AnyChar()`:
  - `reg(/[\s\S]/)` を廃止し、`pos < ctx.length` であれば `ctx.text[pos]` を返却する純粋 O(1) コンビネータに刷新。

### 4.4 テストケース追加 (`tests/test_peg_compiler_js.py`)
- `test_char_class_range_evaluation_in_generated_js`:
  - 複数範囲 + 単一文字 + 反転文字クラスを含む文法をコンパイル。
  - 特殊エスケープ（`\n`, `\t`, `\]`, `\-`）を含む文字クラスの Node.js 実行検証。
  - 生成コード内に `new RegExp('['` が存在しないことを検証。

---

## 5. 完了条件 / Success Criteria (DoD)

- [x] JS 生成コードにおいて `RegExp` による文字クラス判定（`new RegExp('[' + spec + ']')`）が完全に撤廃され、文字コード直接判定になること。
- [x] エスケープ漏れによる JavaScript ランタイム構文エラーが根絶されること。
- [x] 反転文字クラス（`[^...]`）が正しく動作すること。
- [x] `anyChar()` が純粋な `AnyChar` クラスに刷新され、余計な正規表現呼び出しがないこと。
- [x] Xenon Rank A（循環的複雑度）を維持すること。
- [x] `flake8`、`mypy --strict src`、`black`、`isort` を 0 エラーでパスすること。
- [x] `tests/test_peg_compiler_js.py` にテストが追加され、全 PASS すること。
