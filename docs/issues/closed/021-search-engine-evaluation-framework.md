---
ID: 021
種別: Feature / Quality
優先度: High
ステータス: Closed (Completed)
---

# [FEAT/EVAL] 情報検索評価フレームワーク（Precision@K / Recall@K / F1 / MAP / MRR / NDCG）の実装 (ID: 021)

## 1. 概要 / Summary
機能設計書 [DSN-10](../../designs/DSN-10-search-engine-evaluation-framework.md) に基づき、**PM / ST / SA / IR** の合同審議を経て、検索エンジンの品質・精度を定量評価する **「IR 評価フレームワーク（IR Evaluation Engine）」**（`src/search/eval/`）を構築しました。
学術標準の IR メトリクス（Precision@K, Recall@K, F1-Score, MAP, MRR, NDCG@K）の計算エンジン、セキュリティ専門評価コレクション（Gold Standard Ground Truth）、ベンチマーク実行ハーネス、および可観測性 MCP サーバー（`evaluate_search_quality`）への統合を完遂しました。

---

## 2. トレーサビリティ / Traceability
- **設計規約**: [AGENTS.md](../../../.agents/AGENTS.md) (PM/ST/SA/IR 合同仕様)
- **設計書**: [DSN-01-high_level_design.md](../../designs/DSN-01-high_level_design.md), [DSN-09-observability-and-performance-profiling.md](../../designs/DSN-09-observability-and-performance-profiling.md), [DSN-10-search-engine-evaluation-framework.md](../../designs/DSN-10-search-engine-evaluation-framework.md)
- **関連Issue**: [020-hotpath-loop-optimization-and-benchmarking.md](020-hotpath-loop-optimization-and-benchmarking.md), [019-observability-mcp-server-for-ai-coding-agents.md](019-observability-mcp-server-for-ai-coding-agents.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] `src/search/eval/__init__.py`
- [x] [src/search/eval/metrics.py](../../../src/search/eval/metrics.py) (Precision, Recall, F1, MAP, MRR, NDCG)
- [x] [src/search/eval/dataset.py](../../../src/search/eval/dataset.py) (Security Gold Standard Ground Truth)
- [x] [src/search/eval/evaluator.py](../../../src/search/eval/evaluator.py) (SearchEvaluator)
- [x] [src/observability_mcp_server.py](../../../src/observability_mcp_server.py) (evaluate_search_quality ツール追加)
- [x] [Makefile](../../../Makefile) (eval_search ターゲット追加)
- [x] [tests/test_search_evaluation.py](../../../tests/test_search_evaluation.py)
- [x] [docs/issues/README.md](../README.md)
- [x] [docs/designs/DSN-10-search-engine-evaluation-framework.md](../../designs/DSN-10-search-engine-evaluation-framework.md)

---

## 4. 実装成果 / Implementation Results
Target Branch: `feat/021-search-engine-evaluation-framework`

1. **IR 評価指標計算エンジン (`metrics.py`)**:
   - `compute_precision_at_k`: 上位 $K$ 件中における正解文書の割合。
   - `compute_recall_at_k`: 全正解文書中における上位 $K$ 件での回収割合。
   - `compute_f1_score`: 適合率と再現率の調和平均（$F_1, F_\beta$）。
   - `compute_average_precision`: クエリごとの順位重み付き平均適合率（AP / MAP）。
   - `compute_reciprocal_rank`: 最初の正解文書が出現した順位の逆数（RR / MRR）。
   - `compute_ndcg_at_k`: 多段階関連度（0〜3）を考慮した正規化割引累積利得（NDCG@K）。
2. **評価データセット (`dataset.py`)**:
   - セキュリティ主要ドメイン（Zero-Trust, LLM Jailbreak, PQC, Side-Channel, WAF）の Gold Standard Ground Truth を定義。
3. **ベンチマーク実行ハーネス (`evaluator.py`)**:
   - 検索関数を受け取り、一括ベンチマーク評価を実行。
   - 構造化 JSON および Markdown レポートテーブルを自動生成。
4. **可観測性 MCP サーバーへの統合**:
   - `observability_mcp_server.py` に `evaluate_search_quality` ツールを追加し、AI エージェントが精度改善・回帰検証を自律実行可能に。
5. **Makefile ターゲット**:
   - `make eval_search` によりワンコマンドでベンチマークレポートを出力。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] 6大 IR 評価指標の数学的正当性と境界値テスト
- [x] 単体テスト (`tests/test_search_evaluation.py`) 8/8 passed (100% PASS)
- [x] 全 57 ソースファイルの `mypy` 静的型解析 0 エラー
- [x] `DSN-10` として設計書のナンバリング整理完了
