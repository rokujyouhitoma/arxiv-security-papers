---
ID: 889
種別: Feature
優先度: High
ステータス: Open (New)
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
- [ ] [ulisp/compiler/lir_passes.scm](../../ulisp/compiler/lir_passes.scm)
- [ ] [ulisp/compiler/eval_in_language.scm](../../ulisp/compiler/eval_in_language.scm)
- [ ] [ulisp/tests/test_lir.scm](../../ulisp/tests/test_lir.scm)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/889-implement-residual-anf-to-lir-lowering-bridge`

1. `L-Residual-ANF` の各ノード（`let-anf`, `let-call`, `atom-value`, `if-anf`, 算術プリミティブ）を巡回し、LIR 仮想レジスタ命令（`%bit-and`, `%add`, `%call`, `%branch` 等）を生成する関数 `lower-residual-anf-to-lir` を実装。
2. 既存の `anf-all`（Pass 070）出力フォーマットとの差異を吸収し、`pass-130-lir` へシームレスにパス可能にする。
3. 単体テストにより、部分評価された残余コードから正常な LIR 命令列が導出されることを検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `L-Residual-ANF` AST から `L_lir_raw` 命令列への変換が完全に行われ、LIR Verifier をパスすること。
- [ ] 部分評価後の残余コードが LIR 経由で x86-64 / C バックエンドへ正常に出力可能であること。
- [ ] `make test_lir` が 100% PASS すること。
