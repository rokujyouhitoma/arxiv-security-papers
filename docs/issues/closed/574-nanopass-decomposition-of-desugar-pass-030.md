---
ID: 574
種別: Feature
優先度: Medium
ステータス: Closed (Completed)
完了日: 2026-10-20
---

# [FEAT/ENH] 構文脱糖パス (030_desugar.scm) の構文別ナノパス分割（条件分岐・束縛・多値・動的環境） (ID: 574)

## 1. 概要 / Summary
現在 `ulisp/passes/030_desugar.scm` は 517 行の中で、条件分岐（`cond`, `case`, `and`, `or`）、局所束縛（`let*`, `named-let`）、多値受取（`let-values`, `let*-values`）、動的パラメータ（`parameterize`）、例外保護（`guard`）、および各種複合リテラル生成子（`list`, `vector`, `bytevector`）の脱糖を単一ファイルで行っていた。
本 Issue では、構文糖衣の領域ごとに独立した Nanopass モジュール（026: コンストラクタ、027: 条件分岐、028: 局所束縛、029: 動的環境・多値）へと分割し、`030_desugar.scm` は AST 再帰走査オーケストレーション（`desugar-all`）に特化させた。
これにより、各構文脱糖処理の中間不変条件を厳密化するとともに、各パスに対応する 1:1 単体テストを新設した。

---

## 2. トレーサビリティ / Traceability
- Nanopass Framework 原則
- DSN-33 コンパイラアーキテクチャ仕様
- R7RS-small (Section 4.2 Derived expression types)
- 関連資料: [ulisp/passes/030_desugar.scm](../../ulisp/passes/030_desugar.scm)
- 関連テスト: [ulisp/tests/passes/test_030_desugar.scm](../../ulisp/tests/passes/test_030_desugar.scm)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/passes/026_desugar_constructors.scm](../../ulisp/passes/026_desugar_constructors.scm) (新規: `list`, `vector`, `bytevector`, `string-append` 等)
- [x] [ulisp/passes/027_desugar_conditionals.scm](../../ulisp/passes/027_desugar_conditionals.scm) (新規: `cond`, `case`, `and`, `or`, `chain-cmp`)
- [x] [ulisp/passes/028_desugar_bindings.scm](../../ulisp/passes/028_desugar_bindings.scm) (新規: `let*`, `named-let`, `make-body-expr`)
- [x] [ulisp/passes/029_desugar_dynamic.scm](../../ulisp/passes/029_desugar_dynamic.scm) (新規: `guard`, `parameterize`, `let-values`, `let*-values`)
- [x] [ulisp/passes/030_desugar.scm](../../ulisp/passes/030_desugar.scm) (スリム化: `desugar-all` メイン走査のみ保持)
- [x] [ulisp/tests/passes/test_026_desugar_constructors.scm](../../ulisp/tests/passes/test_026_desugar_constructors.scm) (新規)
- [x] [ulisp/tests/passes/test_027_desugar_conditionals.scm](../../ulisp/tests/passes/test_027_desugar_conditionals.scm) (新規)
- [x] [ulisp/tests/passes/test_028_desugar_bindings.scm](../../ulisp/tests/passes/test_028_desugar_bindings.scm) (新規)
- [x] [ulisp/tests/passes/test_029_desugar_dynamic.scm](../../ulisp/tests/passes/test_029_desugar_dynamic.scm) (新規)
- [x] [ulisp/tests/passes/test_030_desugar.scm](../../ulisp/tests/passes/test_030_desugar.scm) (既存テスト維持・確認)
- [x] [ulisp/Makefile](../../ulisp/Makefile) (`PASSES_LIB` および `NANOPASS_TESTS` リスト更新)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/574-nanopass-decomposition-of-desugar-pass-030`

1. **モジュール抽出 (Pass 026〜029)**:
   - `ulisp/passes/026_desugar_constructors.scm`: `desugar-list`, `desugar-string-append`, `desugar-bytevector`, `desugar-bytevector-append`, `desugar-vector`, `desugar-vector-append` を定義。
   - `ulisp/passes/027_desugar_conditionals.scm`: `desugar-cond`, `desugar-case-test`, `desugar-case`, `desugar-and`, `desugar-or`, `desugar-chain-cmp` を定義。
   - `ulisp/passes/028_desugar_bindings.scm`: `make-body-expr`, `desugar-let*`, `desugar-named-let` を定義。
   - `ulisp/passes/029_desugar_dynamic.scm`: `desugar-guard-clauses`, `desugar-guard`, `desugar-let-values`, `desugar-let*-values`, `desugar-parameterize` を定義。
2. **Pass 030 のスリム化**:
   - `ulisp/passes/030_desugar.scm` から上記関数を削除し、`desugar-all` と組み込みプリミティブ引数正規化のみを残す。
3. **Makefile 連携**:
   - `ulisp/Makefile` の `PASSES_LIB` に `passes/026_desugar_constructors.scm` 〜 `passes/029_desugar_dynamic.scm` を `passes/030_desugar.scm` の前に追加。
   - `NANOPASS_TESTS` に各テスト（`test_026_...` 〜 `test_029_...`）を追加（計27パス）。
4. **1:1 単体テスト新設**:
   - 各新設パスに対応する単体テストスクリプトを作成。
5. **品質検証**:
   - 各テストランナーおよび `make -C ulisp test_all_passes`（全27パステスト）の全件 PASS を確認。
   - `make -C ulisp test_record test_promise` 等の既存 AOT テストが正常に通過することを確認。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `030_desugar.scm` の各構文脱糖処理が `026`〜`029` の 4 つの独立パスに分割されていること
- [x] 各パスに対して 1:1 単体テスト（`test_026_...`〜`test_029_...`）が整備され、構文変換の不変条件が検証されていること
- [x] `ulisp/Makefile` の `PASSES_LIB` および `NANOPASS_TESTS` が正しく更新されていること
- [x] `make -C ulisp test_all_passes`（全27パス）が 100% PASS すること
- [x] 相対パスのみを使用し、絶対パスが含まれないこと
