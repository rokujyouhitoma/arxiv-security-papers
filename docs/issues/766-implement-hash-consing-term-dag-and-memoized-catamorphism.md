---
ID: 766
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] HIR/MIR Hash-Consing Term DAG と訪問済みノード O(1) メモ化走査および CP0/Contify の Picopass 化 (DSN-33-01 T5.2) (ID: 766)

## 1. 概要 / Summary

[[DSN-33-01] ULisp 階層型パス融合 ＆ DAG 最適化基盤設計書](../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md) の第 5.2 節（(1) HIR / MIR における Hash-Consing Term DAG と $O(1)$ メモ化走査）、第 6.2 節、およびタスク **T5.2** に基づき、Nanopass 走査ドライバに **共有部分木（Shared Term DAG）の $O(1)$ メモ化走査機構** を導入するとともに、MIR 最適化パス群（`050_cp0.scm`, `100_contify.scm`）の主要規則を `define-picopass` / `define-femtopass` として再構築する。

マクロ展開やインライン展開によって同一の部分式が複数箇所で共有（DAG 化）された際、従来の木走査では同じ部分木を重複して変換・解析していたが、走査ドライバが Picopass から分離されたことにより、ドライバ側の `eq?` メモ化テーブル1つで共有ノードの重複走査を完全にゼロ化できる。

---

## 2. トレーサビリティ / Traceability

- 関連設計書:
  - [[DSN-33-01] ULisp 階層型パス融合 ＆ DAG 最適化基盤設計書](../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md) (第 5.2 節, 第 6.2 節, 第 9.2 節 タスク **T5.2**)
- 依存関係:
  - 先行 Issue: [Issue #755 (T1.3: 未変更部分木の構造共有)](755-implement-catamorphism-structural-sharing-and-unify-trace-hooks.md), [Issue #765 (T5.1: ルール依存関係 DAG と解析キャッシュ維持)](765-implement-rule-dependency-dag-and-femtopass-cache-invalidation.md)
  - 後続 Issue: [Issue #767 (T5.3: LIR ピープホールの Picopass 化とデータ依存 DAG)](767-migrate-lir-peephole-to-picopass-and-dependency-dag.md), [Issue #770 (T6.3: 3-Stage セルフホスティング不動点検証)](770-verify-stage3-self-hosting-fixed-point-and-benchmark-pass-fusion.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [ulisp/compiler/nanopass_meta.scm](../../ulisp/compiler/nanopass_meta.scm)
- [ ] [ulisp/frontend/050_cp0.scm](../../ulisp/frontend/050_cp0.scm)
- [ ] [ulisp/frontend/060_lvn.scm](../../ulisp/frontend/060_lvn.scm)
- [ ] [ulisp/frontend/100_contify.scm](../../ulisp/frontend/100_contify.scm)
- [ ] [ulisp/tests/passes/test_050_cp0.scm](../../ulisp/tests/passes/test_050_cp0.scm)
- [ ] [ulisp/tests/passes/test_100_contify.scm](../../ulisp/tests/passes/test_100_contify.scm)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/766-term-dag-memoization-and-mir-picopass`

1. **Hash-Consing コンストラクタと DAG メモ化カタモルフィズムの実装（`nanopass_meta.scm`）**:
   - 純粋な部分式（副作用や可変セルを持たない式）に対して構造共有を行う `nanopass-hash-cons` と、1回の Nanopass 走査中に訪問済みの共有 DAG ノード `(eq? node)` の変換結果をキャッシュする DAG メモ化ドライバを実装する（ただし `unique-symbol` でフレッシュな識別子を生成するパスではメモ化を無効化できるよう制御可能にする）。
2. **`050_cp0.scm` および `100_contify.scm` の Picopass / Femtopass 化**:
   - `050_cp0.scm` の定数畳み込み、自明な条件分岐剪定（`(if #t a b) -> a`）、単一参照変数のインライン化を `define-picopass` / `define-femtopass` として定義する。
   - `100_contify.scm` の末尾継続関数判定を `define-femtopass`、局所 `letrec` 関数の `%cont-fun` / `%cont-call` 変換を `define-picopass` として定義する。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] 共有部分木を持つ Term DAG に対して DAG メモ化カタモルフィズムを実行した際、共有ノードが1回だけ変換され、2回目以降はキャッシュから $O(1)$ で取得されること。
- [ ] `test_050_cp0.scm`, `test_060_lvn.scm`, `test_100_contify.scm` が全件 PASS すること。

