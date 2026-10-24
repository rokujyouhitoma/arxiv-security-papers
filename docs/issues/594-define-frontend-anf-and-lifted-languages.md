---
ID: 594
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] Frontend層: define-language L_anf / L_lifted の導入と不変条件自動検証 (ID: 594)

## 1. 概要 / Summary
現在、Frontend の前半（構文脱糖〜CP0）では `L_src` および `L_core` が Nanopass DSL として定義されているが、後半の Pass 070（ANF 正規化）、Pass 100（Contification）、Pass 110（Closure Conversion）においては中間言語が明示的に定義されておらず、手続き的な再帰走査と部分的な S 式書き換えが行われている。

本 Issue では、Frontend 後半の主要なチェックポイントとなる `define-language L_anf`（3番地コード形式・引数アトミック化）および `define-language L_lifted`（トップレベル `%function` 巻き上げおよび明示的 `%make-closure` 形式）を形式定義する。これにより、各パス通過時に「複合引数が残っていないか」「未リフトの無名ラムダが存在しないか」等の AST 不変条件（Invariants）を自動検証（`nanopass-ast-valid?`）可能にし、LIR 層への入力境界契約を堅牢化する。

---

## 2. トレーサビリティ / Traceability
- **正典仕様書**:
  - [DSN-33 (ULisp 包括設計仕様書)](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
  - [ULisp パイプライン・Nanopass 詳細仕様書](../../ulisp/docs/spec_pipeline.md)
- **関連 Issue**:
  - Issue 587: Pass 015 Nanopass DSL 手続き型展開器
  - Issue 593: LIR層 `L_lir_canonical` の導入（LIR 入力境界の対抗先）
  - 依存 Issue: Issue 593

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/compiler/nanopass.scm](../../ulisp/compiler/nanopass.scm) または [ulisp/frontend/frontend_lang.scm](../../ulisp/frontend/frontend_lang.scm) (新規: `L_anf`, `L_lifted` 言語定義)
- [ ] [ulisp/frontend/070_anf.scm](../../ulisp/frontend/070_anf.scm) (`L_anf` 適合性検証フック)
- [ ] [ulisp/frontend/110_closure_convert.scm](../../ulisp/frontend/110_closure_convert.scm) (`L_lifted` 適合性検証フック)
- [ ] [ulisp/tests/passes/test_070_anf.scm](../../ulisp/tests/passes/test_070_anf.scm) (単体テスト)
- [ ] [ulisp/tests/passes/test_110_closure_convert.scm](../../ulisp/tests/passes/test_110_closure_convert.scm) (単体テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/594-define-frontend-anf-and-lifted-languages`

1. **`L_anf` の文法定義 (`extends L_core`)**:
   - 複合式引数の排除:
     - `Atom`: Symbol, Constant
     - `Expr`:
       - `(let ((x e_rhs)) body)` (3番地代入)
       - `(op a1 a2 ...)` (演算子/関数の引数はすべて `Atom`)
       - `(if a_test e_then e_else)`
       - `(lambda (x ...) body)`
2. **`L_lifted` の文法定義 (`extends L_anf`)**:
   - ラムダ式のトップレベル化:
     - 局所 `(lambda ...)` を文法から除外 (`- (lambda (x ...) body)`)。
     - `%program` 構造に `%function` 定義リストを強制。
     - クロージャ操作プリミティブ（`%make-closure`, `%closure-ref`, `%closure-set!`）を正典構文として承認。
3. **パス境界不変条件チェッカーの結合**:
   - `070_anf.scm` の出力に対し `(assert-true (L_anf? result))` を検証フックとして導入。
   - `110_closure_convert.scm` の出力に対し `(assert-true (L_lifted? result))` を検証フックとして導入。
4. **テストスイートの拡充**:
   - 多重ネストラムダや複雑な条件式が、`L_anf` および `L_lifted` の文法仕様に 100% 適合することを確認する単体テストを追加。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `L_anf` および `L_lifted` が `define-language` として定義されていること。
- [ ] `anf-all` の出力が `L_anf?` 述語テストを 100% パスすること。
- [ ] `closure-convert` の出力が `L_lifted?` 述語テストを 100% パスし、局所 `lambda` が 0 件であることが保証されること。
- [ ] `make test_unit` および `bash ulisp/test.sh` が 100% PASS すること。
- [ ] LIR 入力として渡される `%program` 形式が完全に `L_lifted` 準拠となること。
