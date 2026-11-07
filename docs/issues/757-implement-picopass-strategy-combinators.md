---
ID: 757
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] Picopass 関数合成コンビネータ群 (picopass-seq / choice / fixpoint / when) の実装と単体テスト整備 (DSN-33-01 T2.2) (ID: 757)

## 1. 概要 / Summary

[[DSN-33-01] ULisp 階層型パス融合 ＆ DAG 最適化基盤設計書](../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md) の第 3.3 節、第 7.1 節、およびタスク **T2.2** に基づき、第一級ルール（Picopass / Femtopass / Attopass）同士を関数合成して新たな複合ルールを構築する **4つの戦略コンビネータ（Strategy Combinators）** を実装する。

1. **`picopass-seq`（直列合成: $p_1 \triangleright p_2$）**: $p_1$ を適用した結果に対し、続けて $p_2$ を適用する（例：`rule-desugar-case` の出力に `rule-desugar-or` を連続適用）。
2. **`picopass-choice`（優先選択合成: $p_1 \oplus p_2$）**: 先に $p_1$ を試行し、マッチしなかった場合のみ $p_2$ を試行する。また、両者の `clauses` と `head-tags` を結合した新しい Rule Descriptor を生成する。
3. **`picopass-fixpoint`（局所不動点反復: $p^*$）**: 単一ノード上でルール $p$ がマッチしなくなるまで（または変換前後が `equal?` になるまで、最大反復上限 `max-steps` 付きで）反復適用する。
4. **`picopass-when`（契約・条件付き適用: $\text{atto/femto} \Rightarrow \text{pico}$）**: 指定した `attopass` または述語関数が真を返したときのみ `picopass` を適用する。

---

## 2. トレーサビリティ / Traceability

- 関連設計書:
  - [[DSN-33-01] ULisp 階層型パス融合 ＆ DAG 最適化基盤設計書](../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md) (第 3.3 節, 第 7.1 節, 第 9.2 節 タスク **T2.2**)
- 依存関係:
  - 先行 Issue: [Issue #756 (T2.1: Rule Descriptor と Picopass DSL 実装)](756-implement-rule-descriptor-and-picopass-femtopass-attopass-dsl.md)
  - 後続 Issue: [Issue #758 (T2.3: Pass 015 への新 DSL 統合)](758-integrate-picopass-dsl-into-pass-015-expander.md), [Issue #759 (T3.1: fuse-rules と O(1) ディスパッチ)](759-implement-fuse-rules-and-head-tag-o1-dispatch.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [ulisp/compiler/nanopass_meta.scm](../../ulisp/compiler/nanopass_meta.scm)
- [ ] [ulisp/compiler/nanopass.scm](../../ulisp/compiler/nanopass.scm)
- [ ] [ulisp/tests/test_nanopass_framework.scm](../../ulisp/tests/test_nanopass_framework.scm)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/757-implement-picopass-combinators`

1. **コンビネータ手続きの実装（`nanopass_meta.scm`）**:
   - セルフホストコンパイラ（Pass 060 LVN 等）の固定アリティ制約に配慮し、2引数基本版（`picopass-seq`, `picopass-choice`, `picopass-when`）とリスト受け取り版（`picopass-compose-list`, `picopass-choice-list`）および `picopass-fixpoint` を実装する。
   - 各コンビネータの戻り値もまた呼び出し可能かつ `Rule Descriptor` メタデータ（合成された `head-tags`, `reads`, `writes`, `eliminates`, `clauses`）を保持するようにし、`define-pass` の `(fuse-rules ...)` へそのまま渡せるようにする。
2. **無限ループ防止ガード**:
   - `picopass-fixpoint` にはデフォルト上限（例: 64ステップ）を設け、万一発散する書き換え規則が与えられた場合は診断エラーを送出する。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `picopass-seq`, `picopass-choice`, `picopass-fixpoint`, `picopass-when` のすべてが単一 S 式に対して正しく合成動作すること。
- [ ] コンビネータで合成したルールが `head-tags` や `reads`/`writes` メタデータを正しく引き継ぐこと。
- [ ] `ulisp/tests/test_nanopass_framework.scm` にて4つのコンビネータの単体テストおよび複合テストが全件 PASS すること。

