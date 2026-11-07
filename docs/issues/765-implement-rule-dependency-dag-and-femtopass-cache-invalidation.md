---
ID: 765
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] ルール依存関係 DAG (Reads/Writes) 自動構築・独立ルール自動 Fusion・Femtopass 解析キャッシュ維持の実装 (DSN-33-01 T5.1) (ID: 765)

## 1. 概要 / Summary

[[DSN-33-01] ULisp 階層型パス融合 ＆ DAG 最適化基盤設計書](../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md) の第 5.1 節（次元1：パス・ルール依存関係 DAG と自動スケジューリング）およびタスク **T5.1** に基づき、各 Picopass / Femtopass / Attopass の `reads`, `writes`, `eliminates` メタデータから **ルール間データ依存 DAG** を自動構築し、以下の3機能を実装する：

1. **独立ルール集合（アンチチェーン）の自動 Pass Fusion とトポロジカルソート**:
   - 互いに Read/Write 競合を持たないルール群を自動判定して同一走査へ融合し、順序依存があるルール（例: `femto-use-counts` の結果を `rule-cp0-inline` が参照）をトポロジカルソートで正しく配置する。
2. **強連結成分（SCC）検出による局所不動点ループの自動抽出**:
   - 相互に生成・消費し合うルール群（サイクル）を検出し、`picopass-fixpoint` として分離する。
3. **Femtopass 解析キャッシュの維持と選択的無効化（Invalidation Tracking）**:
   - 後続の Picopass が変更した構文タグ集合が先行 Femtopass の参照タグ集合と交差しない場合、あるいは AST ノードが構造共有により無変更（`eq?`）であった場合、計算済みの Femtopass 属性キャッシュを無効化せずにそのまま再利用する。

---

## 2. トレーサビリティ / Traceability

- 関連設計書:
  - [[DSN-33-01] ULisp 階層型パス融合 ＆ DAG 最適化基盤設計書](../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md) (第 5.1 節, 第 9.2 節 タスク **T5.1**)
- 依存関係:
  - 先行 Issue: [Issue #763 (T4.2: 030_desugar.scm の fuse-rules 置換)](763-replace-desugar-030-duplicate-rules-with-fuse-rules.md), [Issue #764 (T4.3: Verifier の attopass 化)](764-migrate-verifier-to-attopass-and-eliminate-triple-traversal.md)
  - 後続 Issue: [Issue #766 (T5.2: Hash-Consing Term DAG)](766-implement-hash-consing-term-dag-and-memoized-catamorphism.md), [Issue #768 (T6.1: define-pipeline 用途別編成)](768-implement-define-pipeline-for-aot-repl-and-check-modes.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [ulisp/compiler/nanopass_meta.scm](../../ulisp/compiler/nanopass_meta.scm)
- [ ] [ulisp/compiler/pass_manager.scm](../../ulisp/compiler/pass_manager.scm)
- [ ] [ulisp/tests/test_nanopass_framework.scm](../../ulisp/tests/test_nanopass_framework.scm)
- [ ] [ulisp/tests/test_pass_manager.scm](../../ulisp/tests/test_pass_manager.scm)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/765-rule-dependency-dag-and-analysis-cache`

1. **ルール依存関係グラフ構築器 `nanopass-build-rule-dag` の実装**:
   - ルール $A$ の `writes`（生成タグ）とルール $B$ の `reads`（入力タグ）が交差する場合に有向辺 $A \to B$ を張り、トポロジカル階層（深さレベル）と強連結成分（SCC）を算出する。
2. **Femtopass 属性キャッシュテーブルと Invalidation API の実装**:
   - AST ノード（またはトップレベル `%function` 名）をキーとする属性キャッシュ `*femto-analysis-cache*` を実装する。
   - パスまたは Picopass がノードを書き換えた際、その変更タグに依存する属性キーのみを選択的に Invalidate し、無変更の関数や直交する属性を再計算なしで取得できる API `(femto-get-cached-attr attr-name node compute-thunk)` を提供する。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `nanopass-build-rule-dag` がルール集合から依存辺・独立グループ（アンチチェーン）・循環グループ（SCC）を正確に算出できること。
- [ ] 無変更の部分木または直交する変換パスの前後で、Femtopass の属性キャッシュが再計算されずにヒットすること。
- [ ] `test_nanopass_framework.scm` および `test_pass_manager.scm` の DAG 解析・キャッシュテストが全件 PASS すること。

