---
ID: 424
種別: Feature
優先度: High
ステータス: Open (In Progress)
---

# [FEAT/ENH] 内蔵 JavaScript PEG ランタイムへの Warth ('08) 左再帰解消アルゴリズムの移植 (ID: 424)

## 1. 概要 / Summary

バックエンドの `src/core/structures/peg.py` では、Warth et al. ('08) のシード成長アルゴリズム（`_eval_left_recursion`, `Head`, `LRResult`）により、直接・間接左再帰規則を有限回で安全に解決する仕組みが実装されている（Phase 5, Issue #304）。
一方、`JSCodeGenerator`（`src/core/structures/peg_compiler/codegen_js.py`）が出力する内蔵 JS ランタイム（`embedded_runtime`）は現在単純なメモ化 Packrat のみであり、左再帰文法（数式演算子結合や DSL 構文）をコンパイルして実行した場合、ブラウザや Node.js で `RangeError: Maximum call stack size exceeded`（スタック枯渇）が発生する。

本 Issue では、`peg.py` の Warth 式左再帰解消ロジック（`inProgress`, `lrDetected`, `_growLrSeed`, `_clearLrDependentMemo`）を `codegen_js.py` の内蔵 JavaScript ランタイムに完全移植し、Python と JavaScript のパーサー表現力・耐障害性の完全なパリティ（等価性）を確立する。

---

## 2. トレーサビリティ / Traceability

- **設計仕様書**:
  - [`docs/designs/DSN-25-pure_python_packrat_peg_parser_engine.md`](../designs/DSN-25-pure_python_packrat_peg_parser_engine.md) (第12.1節 左再帰解消 & カット演算子 Issue #304、第13節 Phase 6 JavaScript コードジェネレータ基盤)
- **関連 Issue**:
  - Issue #304: 左再帰の自然解決とカット演算子によるコミット枝刈り
  - Issue #417: WebフロントエンドJS向けPEGインラインパーサー換装およびPEG AOTコンパイラ JavaScriptコードジェネレータ基盤の実装
  - Issue #423: PEG AOT コンパイラにおける --ast-only 汎用構文木生成とアクション抽象化の実装

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

### コンパイラ & ランタイム基盤
- [ ] [`src/core/structures/peg_compiler/codegen_js.py`](../../src/core/structures/peg_compiler/codegen_js.py)（内蔵 JS ランタイムへの `inProgress`, `lrDetected`, `_growLrSeed`, `_clearLrDependentMemo` の追加）

### テスト
- [ ] [`tests/test_peg_compiler_js.py`](../../tests/test_peg_compiler_js.py)（直接左再帰・算術演算子結合・相互間接左再帰文法の JS 実行テスト）

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/424-peg-js-runtime-warth-left-recursion`

### 4.1 `ParseContext` のデータ構造拡張
- `ParseContext` コンストラクタに `this.inProgress = new Set();` および `this.lrDetected = new Set();` を追加。
- 最大再帰深度チェック（`this.currDepth >= this.maxDepth`）を厳格に適用。

### 4.2 `Parser.prototype._clearLrDependentMemo` の実装
- `(key & 0xFFFFF) >= pos && key !== lrKey` となるメモ化エントリーを削除し、シード成長時の依存規則キャッシュを確実にリセット。

### 4.3 `Parser.prototype._growLrSeed` の実装
- 初期シード（非左再帰選択肢のマッチ結果）を `ctx.memo` に保存。
- `newRes = this.parseAt(ctx, pos)` をループ実行し、`newRes.success && newRes.nextPos > curr.nextPos` である限りシードを最長マッチへと成長。
- 成長が停止した時点で固定点（Fixpoint）に到達したと判定し、最終結果をキャッシュして返却。

### 4.4 `Parser.prototype._evalCached` の LR 対応
- `key in ctx.memo`: キャッシュヒット時は即座に返却。
- `ctx.inProgress.has(key)`: 左再帰の検出。`ctx.lrDetected.add(key)` を行い、探索シード生成のため一時的に失敗結果を返却。
- `try/finally` で `ctx.inProgress` の登録・解除を確実に行い、`ctx.lrDetected.has(key)` が真かつパース成功時に `this._growLrSeed` を起動。

### 4.5 テスト検証
- `tests/test_peg_compiler_js.py` に以下のテストケースを追加：
  1. 直接左再帰算術文法（`expr <- expr '+' num / num`）を JS にコンパイルし、`1 + 2 + 3` が左結合で正しくパースされ、無限ループやスタックオーバーフローが発生しないことを検証。
  2. `--ast-only` モードと組み合わせ、左再帰文法から正常な階層型 AST が得られることを検証。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] 内蔵 JS ランタイムが Warth et al. ('08) 左再帰解消をサポートし、直接左再帰文法でスタックオーバーフロー（RangeError）を起こさないこと。
- [ ] 直接左再帰文法におけるシード成長が正常に機能し、最長マッチのパース結果が得られること。
- [ ] Xenon Rank A（循環的複雑度）を維持すること。
- [ ] `flake8`、`mypy --strict src`、`black`、`isort` を 0 エラーでパスすること。
- [ ] `tests/test_peg_compiler_js.py` に左再帰テストが追加され、全 PASS すること。
