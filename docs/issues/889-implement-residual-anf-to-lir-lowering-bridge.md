---
ID: 889
種別: Feature
優先度: High
ステータス: Open (In Progress)
---

# [FEAT] L-Residual-ANF から Middle-End LIR へのローワリング・アダプターブリッジ実装 (ID: 889)

## 1. 概要 / Summary
DSN-33-03 §6.2, §8.1 (Phase P5) および DSN-33-02 §8.4 に基づき、`stage-poly-lower` が出力する `L-Residual-ANF` 構文木（`let-anf`, `let-call`, `atom-value`）を、既存の Middle-End である `pass-130-lir`（`generate-lir`）が要求する仮想レジスタ LIR 形式（`L_lir_raw`）へと直接降格・接続するアダプターブリッジ `lower-residual-anf-to-lir` を実装する。

---

## 2. トレーサビリティ / Traceability
- 関連個別仕様書:
  - [DSN-33-03 §6.2 (L-Residual-ANF 言語定義)](../designs/DSN-33-03-ulisp_stage_polymorphic_metacompiler_and_futamura_projection_architecture.md#62-l-residual-anf-言語定義メタ構文の完全除外--)
  - [DSN-33-02 §8.4 (LIR 統合拡張)](../designs/DSN-33-02-ulisp_multilingual_frontend_and_typed_machine_lir_architecture.md#84-dsn-33-03-ステージ多相メタコンパイラとの-lirelf-統合拡張phase-p5)
- 関連 Issue: #878 (Nanopass Languages), #879 (Stage-Poly-Lower), #885 (Tower Collapse)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/compiler/lir_passes.scm](../../ulisp/compiler/lir_passes.scm)
- [x] [ulisp/compiler/eval_in_language.scm](../../ulisp/compiler/eval_in_language.scm)
- [x] [ulisp/tests/test_lir.scm](../../ulisp/tests/test_lir.scm)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/889-implement-residual-anf-to-lir-lowering-bridge`

1. **構文変換ブリッジ `lower-residual-anf-to-lir` の実装**:
   - `ulisp/compiler/lir_passes.scm` に以下の変換関数を定義：
     - `(let-anf ((v rhs)) body)` $\to$ `rhs` を LIR 命令列として評価し、結果を仮想レジスタ `v` にバインドした上で `body` を継続。
     - `(let-call ((t (fn args ...))) body)` $\to$ 引数レジスタ準備の上 `%call t fn args ...` を発行。
     - `(atom-value v)` $\to$ `%mov dst v`。
     - `(if-anf cnd thn els)` $\to$ `%branch-if-not cnd label-else` + 各ブロックの LIR 列。
2. **`pass-130-lir` との接続**:
   - `generate-lir` の先頭で入力 AST が `L-Residual-ANF` であるかを検知し、必要に応じて正規化・直接ローワリングを実行。
3. **単体テストの作成**:
   - `ulisp/tests/test_lir.scm` に、部分評価（`stage-poly-lower`）で得られた残余 AST を LIR に変換し、LIR Verifier で不変条件を検証するテストケースを追加。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `L-Residual-ANF` AST から `L_lir_raw` 命令列への変換が完全に行われ、LIR Verifier（`verify-core-lir`）をパスすること。
- [ ] 部分評価後の残余コードが LIR 経由で x86-64 / C バックエンドへ正常に出力可能であること。
- [ ] `make test_lir` が 100% PASS すること。
