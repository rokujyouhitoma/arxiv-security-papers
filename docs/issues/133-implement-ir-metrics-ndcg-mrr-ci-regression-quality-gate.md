---
ID: 133
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] IR評価メトリクス（NDCG@10, MRR, MAP）に基づくCI継続的インテグレーション検索品質回帰防止ゲートの実装 (ID: 133)

## 1. 概要 / Summary
形態素解析ロジック、BM25 ハイパーパラメータ（$k_1, b$）、あるいは Dense ANN 埋め込みベクトルの変更時に、検索性能の意図せぬ低下（リグレッション）を自動検知する評価スイートを CI パイプラインに組み込む。
グラウンドトゥルース・テストクエリ群に対し、Precision@K、Recall@K、MAP、MRR、および NDCG@K を自動計測し、ベースラインと比較して NDCG@10 が 3% 以上低下した場合にビルドを自動失敗させてマージを抑止する厳格な品質ゲートを構築する。

---

## 2. トレーサビリティ / Traceability
- [DSN-10: 可観測性 ＆ 情報検索評価包括フレームワーク](../../docs/designs/DSN-10-observability_and_eval_framework.md)
- [src/search/eval/](../../src/search/eval/)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] `src/search/eval/ci_gate.py`
- [ ] `src/search/eval/benchmark.py`
- [ ] `Makefile`
- [ ] `tests/search/eval/test_ci_gate.py`

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/133-implement-ir-metrics-ndcg-mrr-ci-regression-quality-gate`
1. グラウンドトゥルース・ゴールドクエリデータセットの定義と格納。
2. `make ir_eval` または `make check_ir_regression` ターゲットの実装。
3. ベースライン比較ロジックと 3% 低下時の exit code 1 遮断。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] CI / Makefile コマンドで NDCG@10, MRR, MAP が自動算出されること
- [ ] 許容閾値を超えて悪化した場合にビルドが適切に失敗すること
- [ ] 全品質ゲート（Xenon Rank A, Flake8, Mypy Strict, pytest）を 100% パスすること
