---
ID: 203
種別: Bug
優先度: High
ステータス: Closed (Completed)
---

# [BUG] SOTA ベンチマークレポートにおける全指標 0.0000 出力および「最高精度達成」結論矛盾の修正 (ID: 203)

## 1. 概要 / Summary

`docs/benchmarks/sota_evaluation.md`（SOTA 情報検索客観的性能評価レポート）において、総合評価サマリーテーブルの全指標（NDCG@10, Recall@10, MAP, MRR）が `0.0000` と出力されているにもかかわらず、結論セクションで「最高精度のハイブリッド検索性能を達成しています」と記載される深刻な結果・結論の矛盾が発生していた。

この不具合の原因を特定し、メトリクス集計・抽出キーの整合、モデルタイプ判定ロジックの修正、結論セクションと実測値の動的連動、および回帰防止テストを実装する。

### 再現手順 / Steps to Reproduce
1. `make benchmark_ir`（または `python -m search.eval.sota_runner --output docs/benchmarks/sota_evaluation.md`）を実行する。
2. 生成された `docs/benchmarks/sota_evaluation.md` を確認する。
3. 全モデル（BM25, Dense Vector, Hybrid SOTA）の NDCG@10, Recall@10, MAP, MRR がすべて `0.0000` になる。
4. にもかかわらず「最高精度のハイブリッド検索性能を達成しています」と矛盾した結論が出力される。

### 再現環境 / Environment
- OS / Env: Ubuntu Linux / Python 3.14.7
- File: `src/search/eval/sota_runner.py`, `docs/benchmarks/sota_evaluation.md`

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [src/search/eval/sota_runner.py](../../src/search/eval/sota_runner.py) (メトリクス抽出キー取得、モデルタイプ判定、結論動的生成)
- [x] [docs/benchmarks/sota_evaluation.md](../../docs/benchmarks/sota_evaluation.md) (ベンチマークレポートの再生成)
- [x] [tests/search/eval/test_sota_runner.py](../../tests/search/eval/test_sota_runner.py) (全指標 0.0000 出力防止の回帰検証テスト)

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis

1. **メトリクス辞書キーの不一致**:
   - `SearchEvaluator._summarize_metrics` が返す辞書のキーは `mean_NDCG_at_k`, `mean_recall_at_k`, `MAP`, `MRR` であった。
   - しかし `sota_runner.py` の `_format_summary_table_rows()` において、`ir.get("ndcg", 0.0)`, `ir.get("recall", 0.0)`, `ir.get("map", 0.0)`, `ir.get("mrr", 0.0)` のように小文字のキーで取得していたため、常にデフォルト値 `0.0` が返されていた。
2. **モデル種別 (`m_type`) 判定ロジックの不一致**:
   - `models` リスト定義では BM25 モデルの種別が `"lexical"` であったが、抽出処理では `m_type == "bm25"` で判定していたため、NDCG 向上率計算用の `bm25_ndcg` が 0.0 のままとなり向上率も `+0.00%` に固定されていた。
3. **静的テキスト結論と実測値の乖離**:
   - レポート結論セクションが静的文字列であり、`hybrid_ndcg` の実測値に基づかない記述となっていた。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**: なし
* **恒久対策 (Permanent Fix)**:
  1. `sota_runner.py` の `_format_summary_table_rows()` で `ir.get("mean_NDCG_at_k", ir.get("ndcg", 0.0))` 等のフォールバック付き正規化キーアクセスを実装。
  2. `m_type in ("lexical", "bm25") or "BM25" in model_name` による堅牢なモデル種別判定を導入。
  3. `_format_analysis_section()` に `hybrid_ndcg` を渡し、実測値（NDCG@10 1.0000 等）を結論に明記し、万一指標が 0 の場合は過剰な最高精度主張を行わない動的ガードを実装。
  4. 回帰テスト `test_sota_runner.py` に `self.assertNotIn("| 0.0000 | 0.0000 | 0.0000 | 0.0000 |", md)` を追加。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `main` (直列ホットフィックス)

1. `sota_runner.py` のキー参照・モデル判定・分析結論ロジック改修
2. `tests/search/eval/test_sota_runner.py` への回帰検証テスト追加
3. `make benchmark_ir` による `docs/benchmarks/sota_evaluation.md` の再生成
4. `make check_format` および `make static_analysis` による品質ゲート検証

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `docs/benchmarks/sota_evaluation.md` に実際の評価結果（NDCG@10, Recall@10, MAP, MRR）が正しく出力されていること。
- [x] 結論セクションが実測値（NDCG@10 1.0000）を反映し、矛盾のない客観的表現になっていること。
- [x] `pytest tests/search/eval/test_sota_runner.py` が PASS し、回帰テストが機能すること。
- [x] `make check_format` および `make static_analysis` がエラー 0 件であること。
