# [FEAT] 自律型インテリジェンス・オーケストレーターにおける検索評価 (IR Eval) 駆動型クエリ自己適応ループの実装 (ID: 082)

| 項目 | 内容 |
| :--- | :--- |
| **ID** | 082 |
| **種別** | Feature |
| **優先度** | Medium |
| **ステータス** | Closed (Resolved) |
| **起票日** | 2026-08-27 |
| **完了日** | 2026-08-27 |
| **担当ロール** | Systems Architect (SA) / SQA Specialist (QA) |
| **対象ブランチ** | `feat/082-orchestrator-eval-driven-query-expansion` |

---

## 1. 概要 / Summary
自律型インテリジェンス・オーケストレーター（`src/orchestrator/`）の 6 大フェーズサイクル（計画 $\rightarrow$ 収集 $\rightarrow$ 処理 $\rightarrow$ 分析 $\rightarrow$ 配布 $\rightarrow$ 評価）において、フェーズ 6 の検索評価（NDCG@K, MRR, MAP）結果に基づいて、フェーズ 1 の PIR（優先インテリジェンス要件）クエリを自律的に拡張・最適化する自己適応閉ループ（Self-Adaptive Feedback Loop）を実装する。

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- `src/orchestrator/pir_manager.py` (PIR 策定とクエリ拡張)
- `src/orchestrator/feedback_evaluator.py` (検索評価メトリクス集計とナレッジギャップ分析)
- `src/orchestrator/dag_workflow.py` (DAG ワークフローの閉ループ連携)
- `src/search/eval/evaluator.py` (IR 評価ベンチマーク)
- `tests/orchestrator/` (オーケストレーター単体 & E2E テスト)

---

## 3. 要件定義と脅威モデル / Requirements & Threat Model
- **機能要件**:
  - `FeedbackEvaluator` が NDCG@5 < 0.70 または再現率不足を検知した場合、関連するセキュリティ同義語・CWE キーワードを `PIRManager` へ自動フィードバック。
  - 次期サイクルの収集クエリに自動反映し、不足分野の論文収集を強化。
- **非機能要件**:
  - クエリ拡張による無限ループや指数関数的なクエリ肥大化の防止（最大拡張深度 2、最大追加キーワード数 5）。

---

## 4. 実装方針 / Implementation Plan
1. **`src/orchestrator/feedback_evaluator.py`**:
   - `generate_adaptation_recommendations(eval_results)` を実装し、低スコアトピックを抽出。
2. **`src/orchestrator/pir_manager.py`**:
   - `adapt_pir_queries(recommendations)` を実装し、次回サイクルの検索タームを自動最適化。
3. **`tests/orchestrator/`**:
   - フィードバックによるクエリ自己適応ループの検証テストを追加。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] 検索評価のフィードバックが次回サイクルの PIR クエリに自動反映されること。
- [x] クエリ拡張ガードが機能し、過度なリクエスト増殖が防止されること。
- [x] `tests/orchestrator/` の全テストが PASS すること。
- [x] `make check` をクリアすること。
