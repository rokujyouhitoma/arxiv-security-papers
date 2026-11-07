---
ID: 755
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT/ENH] 未変更部分木の構造共有 (Smart Reconstruction) 実装および重複 AST Diff トレースフックの一元化 (DSN-33-01 T1.3) (ID: 755)

## 1. 概要 / Summary

[[DSN-33-01] ULisp 階層型パス融合 ＆ DAG 最適化基盤設計書](../../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md) の第 4.3 節（(2) 未変更部分木の構造共有）、第 8.2 節（課題④）、およびタスク **T1.3** に基づき、以下の2点を実装する：

1. **未変更部分木の構造共有（Smart Reconstruction）によるゼロアロケーション再構築**:
   - 現在、[ulisp/compiler/nanopass_meta.scm](../../../ulisp/compiler/nanopass_meta.scm) の `nanopass-catamorphism-step`（および `nanopass-schema-transform-*` / `nanopass-fallback-transform-node`）は、子ノードが変換前後で一切変化していなくても、訪問するすべての AST ノードに対して毎回新しい `list` / `cons` セルを割り当てて木全体を再構築（Tree Spine Cloning）しており、1パスあたり $O(N)$ の不要なヒープ消費を引き起こしている。
   - 再帰後の子ノード群が元のサブフォームとすべて `eq?`（ポインタ同一）であった場合、新規コンスセルを割り当てず元のノード `ir`（およびサブフォームリスト）をそのまま返す構造共有を導入する。
2. **`nanopass-display-ast-diff` 重複フックの一元化**:
   - 現在、`define-pass` の展開コード内（[ulisp/compiler/nanopass.scm](../../../ulisp/compiler/nanopass.scm) L154-162）と [ulisp/compiler/pass_manager.scm](../../../ulisp/compiler/pass_manager.scm) の `run-single-pass`（L441-442, L452-453）の双方に `nanopass-display-ast-diff` 呼び出しが存在し、さらに `run-pass-pipeline`（L471-472）で `(if trace-mode (enable-nanopass-trace!))` が呼ばれるため、パイプラインでトレースを有効化すると `define-pass` で実装されたパス（`desugar-all`, `lir-fuse-branches`, `lir-peephole-optimize` 等）の AST Diff が2回重複出力される問題を解消する。

---

## 2. トレーサビリティ / Traceability

- 関連設計書:
  - [[DSN-33-01] ULisp 階層型パス融合 ＆ DAG 最適化基盤設計書](../../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md) (第 4.3 節, 第 4.5 節, 第 8.2 節 課題④, 第 9.2 節 タスク **T1.3**)
- 依存関係:
  - 先行 Issue: [Issue #754 (T1.2: カタモルフィズムのスキーマ駆動化)](754-refactor-catamorphism-to-schema-driven-traversal.md)
  - 後続 Issue: [Issue #756 (T2.1: Rule Descriptor と Picopass DSL 実装)](../756-implement-rule-descriptor-and-picopass-femtopass-attopass-dsl.md), [Issue #766 (T5.2: Hash-Consing Term DAG)](../766-implement-hash-consing-term-dag-and-memoized-catamorphism.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [ulisp/compiler/nanopass_meta.scm](../../../ulisp/compiler/nanopass_meta.scm)
  - `nanopass-cons-sharing`, `nanopass-map-sharing` を実装し、`nanopass-schema-transform-subpattern`, `nanopass-schema-transform-subforms`, `nanopass-schema-transform-node`, `nanopass-fallback-transform-node` の全経路で未変更部分木のポインタ同一性（`eq?`）を維持する。
  - `nanopass-ast-diff` および `nanopass-ast-diff-list` の先頭に `(eq? old-ir new-ir)` 高速ショートサーキットを追加する。
  - パイプライン実行中の二重トレース抑止フラグ `*nanopass-in-pipeline-runner*`（および `nanopass-in-pipeline-runner?` / `set-nanopass-in-pipeline-runner!`）を追加する。
- [x] [ulisp/compiler/nanopass.scm](../../../ulisp/compiler/nanopass.scm)
  - `nanopass-expand-define-pass-with-trace` におけるトレース出力条件を `(and (or force-trace? (nanopass-trace-enabled?)) (not (nanopass-in-pipeline-runner?)))` に更新し、単体パス直接呼び出し時は従来通りトレース出力しつつ、`run-single-pass` 経由の実行時は `pass_manager.scm` 側の1回のみ出力されるように統一する。
- [x] [ulisp/compiler/pass_manager.scm](../../../ulisp/compiler/pass_manager.scm)
  - `run-single-pass` 実行中に `*nanopass-in-pipeline-runner*` を `#t` に設定（完了後に復元）し、パイプライン内の全パスの AST Diff トレース出力を `run-single-pass` に一元化する。
- [x] [ulisp/tests/test_nanopass_framework.scm](../../../ulisp/tests/test_nanopass_framework.scm)
  - 未変更部分木に対する `eq?` 構造共有の単体テスト（全ノード未変更時、および一部ブランチのみ変更時の兄弟未変更サブツリーの `eq?` 保存）を追加する。
- [x] [ulisp/tests/test_nanopass_tracer.scm](../../../ulisp/tests/test_nanopass_tracer.scm)
  - 単体 `define-pass` / `trace-define-pass` のトレース動作と、`run-single-pass` / `run-pass-pipeline` 実行時に AST Diff が重複せず1回のみ出力されることの検証テストを追加する。

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/755-smart-reconstruction-and-trace-unification`

1. **`nanopass-cons-sharing` / `nanopass-map-sharing` と Smart Reconstruction の実装 ([ulisp/compiler/nanopass_meta.scm](../../../ulisp/compiler/nanopass_meta.scm))**:
   - ペア `orig-pair` に対して新しい `new-car`, `new-cdr` がそれぞれ `(and (eq? new-car (car orig-pair)) (eq? new-cdr (cdr orig-pair)))` を満たす場合は `orig-pair` をそのまま返し、異なる場合のみ `(cons new-car new-cdr)` を生成する `nanopass-cons-sharing` を実装する。
   - リスト `lst` の各要素に `fn` を適用しつつ、すべての要素が `eq?` で不変なら元の `lst`（テール部分リストの共有含む）を返す `nanopass-map-sharing` を実装する。
   - `nanopass-schema-transform-subpattern`, `nanopass-schema-transform-subforms`, `nanopass-schema-transform-node`, および `nanopass-fallback-transform-node` を `nanopass-cons-sharing` / `nanopass-map-sharing` ベースに更新する：
     - これにより、たとえば `(if test then-branch else-branch)` で `then-branch` だけが書き換わった場合、`else-branch` の部分木は1セルも再割り当てされず元のポインタと `eq?` 同一のまま共有される。またノード全体が無変更であればルート `ir` 自体が `(eq? (pass ir) ir) => #t` となる。
   - `nanopass-ast-diff` と `nanopass-ast-diff-list` の先頭で `(eq? old-ir new-ir)` をチェックし、構造共有された未変更部分木の深い `equal?` 走査を $O(1)$ でスキップする。

2. **AST Diff トレースフックの重複排除・一元化 ([ulisp/compiler/nanopass_meta.scm](../../../ulisp/compiler/nanopass_meta.scm), [ulisp/compiler/nanopass.scm](../../../ulisp/compiler/nanopass.scm), [ulisp/compiler/pass_manager.scm](../../../ulisp/compiler/pass_manager.scm))**:
   - `nanopass_meta.scm` にボックス化された状態フラグ `*nanopass-in-pipeline-runner*` とアクセサ `(nanopass-in-pipeline-runner?)`, `(set-nanopass-in-pipeline-runner! flag)`、および呼び出し回数検証用の `*nanopass-ast-diff-display-count*` カウンタ（`(nanopass-ast-diff-display-count)` / `(reset-nanopass-ast-diff-display-count!)`）を追加する。
   - `nanopass.scm` の `nanopass-expand-define-pass-with-trace` では、`(not (nanopass-in-pipeline-runner?))` のときのみ `nanopass-display-ast-diff` を呼ぶように展開コードを生成する。
   - `pass_manager.scm` の `run-single-pass` では、パス関数 `(fn input-ast)` の呼び出し前後で `nanopass-in-pipeline-runner` フラグをスコープ管理し、`trace-mode` が真のときに `run-single-pass` 側で正確に1回だけ `(nanopass-display-ast-diff id input-ast output-ast)` を呼び出す。

3. **単体テストの追加 ([ulisp/tests/test_nanopass_framework.scm](../../../ulisp/tests/test_nanopass_framework.scm), [ulisp/tests/test_nanopass_tracer.scm](../../../ulisp/tests/test_nanopass_tracer.scm))**:
   - `test_nanopass_framework.scm` に Section 15 として Smart Reconstruction 構造共有テスト（`L_src`, `L_core`, `L_lir_canonical`, `L_asm_x86` における完全未変更時の `(eq? in out)`、および部分変更時の未変更兄弟ブランチの `eq?` 共有）を追加する。
   - `test_nanopass_tracer.scm` に Section 6 として、単体パス呼び出し時と `run-single-pass` 呼び出し時の双方で `nanopass-ast-diff-display-count` がちょうど1回だけインクリメントされる（二重出力されない）ことを検証するテストを追加する。

---

## 5. 完了条件 / Success Criteria (DoD)

- [x] 書き換え対象構文を含まない AST または部分木に対して `define-pass` を適用した際、返却される部分木が入力と `(eq? input-subtree output-subtree)` となり、不要なコンスセル割り当てが発生しないこと。
- [x] 部分木の一方のブランチのみが書き換わった場合でも、他方の未変更ブランチは元の AST のサブツリーと `eq?`（ポインタ同一）が維持されること。
- [x] `run-single-pass` / `run-pass-pipeline` を `trace-mode = #t` で実行した際、`define-pass` で定義されたパスを含め各パスの AST Diff が重複せず1回ずつ正確に出力されること。
- [x] [ulisp/tests/test_nanopass_framework.scm](../../../ulisp/tests/test_nanopass_framework.scm) および [ulisp/tests/test_nanopass_tracer.scm](../../../ulisp/tests/test_nanopass_tracer.scm) が全件 PASS し、3大品質ゲート（`make format`, `make static_analysis`, `make test`）をすべて PASS すること。


