---
ID: 882
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT] 部分評価後の残余関数における Contification 保証の検証 (ID: 882)

## 1. 概要 / Summary
DSN-33-03 §5.4 に基づき、インタプリタ部分評価で生成された相互再帰する残余関数群が、Pass 100（`100_contify`）および LIR バックエンドにおいて確実に単一の平坦なループ（GOTO）へ融合され、C スタックを消費しないことを保証・検証する。

---

## 2. トレーサビリティ / Traceability
- 関連資料: [DSN-33-03 §5.4](docs/designs/DSN-33-03-ulisp_stage_polymorphic_metacompiler_and_futamura_projection_architecture.md#54-残余関数の-contification-保証条件相互末尾再帰の単一ループ融合制約)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/compiler/nanopass.scm](ulisp/compiler/nanopass.scm)
- [ ] [ulisp/lir/132_braun_ssa.scm](ulisp/lir/132_braun_ssa.scm)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/882-verify-residual-function-contification-guarantees`

1. 共通末尾継続および閉包呼び出しグラフを検証するアサーションを追加。
2. 相互末尾再帰が LIR レベルで単一基本ブロック群間のローカルジャンプへ落とし込まれていることを検証するテストケースを作成。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 相互再帰する残余関数群がアロケーションおよびスタックフレーム消費ゼロの単一ループへ融合されること。
- [ ] `make py_compile` が PASS すること。
