---
ID: 521
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] 拡張局所値番号付け (Extended LVN) による不変アクセサメモ化と代数的等価性最適化の実装 (ID: 521)

## 1. 概要 / Summary
コーネル大学 CS 6120 (Lesson 3) で扱われる局所値番号付け (Local Value Numbering: LVN) フレームワークを拡張し、ULisp の Nanopass コンパイラへ導入する。
単一基本ブロック内において、定数畳み込み、コピー伝播、共通部分式除去 (CSE) を単一ハッシュテーブルで統合するとともに、Scheme 固有の意味論を組み込む。不変ペアアクセサ (`car`/`cdr`) のメモ化による冗長なメモリロード命令の完全消去、型述語 (`fixnum?` 等) の重複検査の真偽値畳み込み、および可換演算子 (`+`, `*`) の引数順序正規化と恒等元除去 (`(+ x 0) -> x`) を実現し、生成機械語の冗長計算を静的に刈り込む。

---

## 2. トレーサビリティ / Traceability
- **関連設計書**:
  - [DSN-33: ULISP 包括設計仕様書 (第8.2節 Extended LVN)](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
- **関連先行 Issue**:
  - Issue #499: ULisp コンパイラへの ANF 正規化および CP0 最適化パスの実装
  - Issue #518: ULisp 低水準IR具象化器 (S-RTyper) とアンボクシングによるタグ検査完全消去

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/passes/03b_lvn.scm](../../ulisp/passes/03b_lvn.scm) (新規作成: 拡張 LVN 最適化パス)
- [ ] [ulisp/passes/00_helpers.scm](../../ulisp/passes/00_helpers.scm) (LVN テーブル操作および代数的同値性ヘルパー)
- [ ] [ulisp/passes/08_driver.scm](../../ulisp/passes/08_driver.scm) (パイプラインへの Pass 03b 組み込み)
- [ ] [ulisp/Makefile](../../ulisp/Makefile) (PASSES_LIB への追加)
- [ ] [ulisp/tests/passes/test_lvn.scm](../../ulisp/tests/passes/test_lvn.scm) (新規作成: LVN 単体テストスイート)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/521-ulisp-extended-lvn-and-accessor-memoization`

1. **LVN ハッシュテーブルと値番号割当機構の実装**:
   - 基本ブロック内の各式に対して一意の値番号 (Value Number) を割り当て、同一の計算タプル `(op val1 val2 ...)` をハッシュ化して先行変数の参照へ置換。
2. **言語意味論拡張ポイントの実装**:
   - **不変ペアアクセサメモ化**: `(car p)` / `(cdr p)` に対し、`p` が同一値番号かつブロック内に破壊的代入 (`set-car!`, `set-cdr!`) が存在しない場合、同一値番号を割り当ててロード命令を消去。
   - **型述語検査の畳み込み**: 同一値番号に対して `(fixnum? x)` 等の成功が支配している場合、後続の型検査を即座に `#t` 定数へ畳み込み。
   - **代数的正規化**: 可換演算 (`+`, `*`) の引数を値番号の昇順にソートし、`(+ x 0) -> x`、`(* x 1) -> x`、`(- x x) -> 0` を簡約。
3. **Nanopass パイプラインへの統合**:
   - Pass 03 (CP0) と Pass 04 (ANF) の間に `Pass 03b: LVN` として直列結合。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 単一ブロック内の同一ペアに対する連続アクセサ呼び出し（`car`, `cdr`）で、重複メモリアクセス命令が 0 件に削減されること。
- [ ] 算術演算の自明な恒等式展開（`(+ x 0)` 等）および重複型述語検査が静的に消去されること。
- [ ] `make -C ulisp test_passes` およびセルフホストブートストラップ（`make -C ulisp bootstrap`）が 100% PASS すること。
