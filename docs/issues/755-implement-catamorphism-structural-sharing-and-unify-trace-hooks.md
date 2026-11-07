---
ID: 755
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] 未変更部分木の構造共有 (Smart Reconstruction) 実装および重複 AST Diff トレースフックの一元化 (DSN-33-01 T1.3) (ID: 755)

## 1. 概要 / Summary

[[DSN-33-01] ULisp 階層型パス融合 ＆ DAG 最適化基盤設計書](../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md) の第 4.3 節（(2) 未変更部分木の構造共有）、第 8.2 節（課題④）、およびタスク **T1.3** に基づき、以下の2点を実装する：

1. **未変更部分木の構造共有（Smart Reconstruction）によるゼロアロケーション再構築**:
   - 現在、`nanopass-catamorphism-step` は子ノードが変換前後で一切変化していなくても、訪問するすべての AST ノードに対して毎回新しい `list` / `cons` セルを割り当てて木全体を再構築（Tree Spine Cloning）しており、1パスあたり $O(N)$ の不要なヒープ消費を引き起こしている。
   - 再帰後の子ノード群が元のサブフォームとすべて `eq?`（ポインタ同一）であった場合、新規コンスセルを割り当てず元のノード `ir` をそのまま返す構造共有を導入する。
2. **`nanopass-display-ast-diff` 重複フックの一元化**:
   - 現在、`define-pass` の展開コード内（`ulisp/compiler/nanopass.scm` L157-159）と `ulisp/compiler/pass_manager.scm` の `run-single-pass`（L441-442, L452-453）の双方に `nanopass-display-ast-diff` 呼び出しが存在し、パイプラインでトレースを有効化すると同じパスの AST Diff が2回出力される問題を解消する。

---

## 2. トレーサビリティ / Traceability

- 関連設計書:
  - [[DSN-33-01] ULisp 階層型パス融合 ＆ DAG 最適化基盤設計書](../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md) (第 4.3 節, 第 4.5 節, 第 8.2 節 課題④, 第 9.2 節 タスク **T1.3**)
- 依存関係:
  - 先行 Issue: [Issue #754 (T1.2: カタモルフィズムのスキーマ駆動化)](754-refactor-catamorphism-to-schema-driven-traversal.md)
  - 後続 Issue: [Issue #756 (T2.1: Rule Descriptor と Picopass DSL 実装)](756-implement-rule-descriptor-and-picopass-femtopass-attopass-dsl.md), [Issue #766 (T5.2: Hash-Consing Term DAG)](766-implement-hash-consing-term-dag-and-memoized-catamorphism.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [ulisp/compiler/nanopass_meta.scm](../../ulisp/compiler/nanopass_meta.scm)
- [ ] [ulisp/compiler/nanopass.scm](../../ulisp/compiler/nanopass.scm)
- [ ] [ulisp/compiler/pass_manager.scm](../../ulisp/compiler/pass_manager.scm)
- [ ] [ulisp/tests/test_nanopass_framework.scm](../../ulisp/tests/test_nanopass_framework.scm)
- [ ] [ulisp/tests/test_nanopass_tracer.scm](../../ulisp/tests/test_nanopass_tracer.scm)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/755-smart-reconstruction-and-trace-unification`

1. **`nanopass-map-sharing` および Smart Reconstruction ヘルパーの実装**:
   - `nanopass_meta.scm` に、リスト `lst` の各要素に `fn` を適用しつつ、すべての要素 `x` について `(eq? (fn x) x)` が成り立つ場合は新しいリストを作らず元の `lst` をそのまま返す `(nanopass-map-sharing fn lst)` を実装する。
   - `nanopass-catamorphism-step` の各再帰構築箇所で、変換後の子ノードと元の子ノードを `eq?` 比較し、無変更であれば元の `ir` をそのまま返すように改修する。
   - また、`nanopass-ast-diff` においても先頭で `(if (eq? old-ir new-ir) #f ...)` を高速判定できるようにする。
2. **AST Diff トレースフックの重複排除**:
   - `trace-define-pass` で明示的にトレース指定された単体パス呼び出し時はそのまま動作しつつ、`run-single-pass`（`pass_manager.scm`）経由の実行時には二重に `nanopass-display-ast-diff` が呼ばれないよう、トレース出力責務を制御フラグまたは `pass_manager.scm` 側に統一する。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] 書き換え対象構文を含まない部分木に対して `define-pass` を適用した際、返却される部分木が入力と `(eq? input-subtree output-subtree)` となり、不要なコンスセル割り当てが発生しないこと。
- [ ] `run-pass-pipeline` を `trace-mode = #t` で実行した際、各パスの AST Diff が重複せず1回ずつ正確に出力されること。
- [ ] `test_nanopass_framework.scm` および `test_nanopass_tracer.scm` が全件 PASS すること。

