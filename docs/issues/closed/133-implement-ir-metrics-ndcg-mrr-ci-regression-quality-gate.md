---
ID: 133
種別: Feature
優先度: Medium
ステータス: Closed (Completed)
---

# [FEAT/ENH] IR評価メトリクス（NDCG@10, MRR, MAP）に基づくCI継続的インテグレーション検索品質回帰防止ゲートの実装 (ID: 133)

## 1. 概要 / Summary
トークナイザーの形態素解析ルール変更、BM25 ハイパーパラメータ（$k_1, b$）の調整、あるいは Dense ANN 埋め込みモデルの更新時に、検索精度の意図せぬ低下（リグレッション）を機械的・自動的に検知・防止するため、情報検索評価メトリクス（IR Metrics）に基づく CI 継続的品質ゲートを構築する。

標準グラウンドトゥルースデータセット（`DEFAULT_SECURITY_GOLD_STANDARD`）に対し、Precision@10, Recall@10, MAP（Mean Average Precision）, MRR（Mean Reciprocal Rank）, NDCG@10（Normalized Discounted Cumulative Gain）を自動計測する。リポジトリ内にコミット管理されたベースライン指標（`baseline_metrics.json`）と比較し、NDCG@10 が許容閾値（3% 超）低下した場合に CI ビルドを exit code 1 で自動遮断する仕組みを Pure Python（ゼロ外部依存）で実装し、`Makefile` に統合する。

---

## 2. トレーサビリティ / Traceability
- [DSN-10: 可観測性 ＆ 情報検索評価包括フレームワーク](../../docs/designs/DSN-10-observability_and_eval_framework.md)
- [REQ-03: プロジェクトユースケース台帳 (UC-OPS-01, UC-DEV-02)](../requirements/REQ-03-use_case_ledger.md)
- [Issue 124: BM25語彙検索とDense ANN意味検索を統合するRRFハイブリッドスコアラー](closed/124-implement-bm25-dense-ann-reciprocal-rank-fusion-scorer.md)
- [src/search/eval/metrics.py](../../src/search/eval/metrics.py)
- [src/search/eval/evaluator.py](../../src/search/eval/evaluator.py)
- [src/search/eval/dataset.py](../../src/search/eval/dataset.py)
- [Makefile](../../Makefile)

---

## 3. 脅威モデリングとセキュリティ要件 (Threat Modeling & Mitigations)
- **T-133-01: 同点タイブレークの非決定性による CI の偽陽性障害 (Flaky CI)**
  - *脅威*: 検索スコアが同点のドキュメントの順序が実行ごとに変動し、NDCG@10 が微小に揺らいで CI が不安定化（Flaky）する。
  - *対策*: 同一スコア時のタイブレーク規則として `doc_id` 昇順ソートを強制し、100% 決定論的（再現可能）な評価結果を保証。
- **T-133-02: ベースライン JSON の不正改ざん・目標値の過度な引き下げ (Gate Bypass)**
  - *脅威*: 開発者がリグレッションを隠蔽するためにベースラインの NDCG スコアを意図的に低く書き換えてコミットする。
  - *対策*: ベースライン JSON にハッシュチェックサムと最終更新コミットハッシュ・タイムスタンプを埋め込み、更新時の差分レビュー要件を明示。
- **T-133-03: 評価データセット肥大化による CI パイプライン停止 (CI Pipeline Starvation)**
  - *脅威*: 評価クエリ数が数千件に達し、PR ごとの CI 実行時間が数十倍に膨張して開発サイクルが停滞する。
  - *対策*: CI 用の Fast-Fail クエリセット（主要 50 クエリ）と詳細フル評価（200+ クエリ）を階層化し、CI ゲートは 5 秒以内に完了するよう最適化。

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files
- [x] `src/search/eval/ci_gate.py` (CI 回帰判定ロジックおよび CLI エントリポイント)
- [x] `src/search/eval/baseline_metrics.json` (コミット管理されるベースライン評価指標)
- [x] `Makefile` (`ir_eval`, `check_ir_regression` ターゲットの追加)
- [x] `tests/search/eval/test_ci_gate.py` (閾値超過判定、ベースライン更新、決定論的ソートの単体テスト)

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/133-implement-ir-metrics-ndcg-mrr-ci-regression-quality-gate`

1. **ステップ 1: 回帰判定ゲートの実装 (`src/search/eval/ci_gate.py`)**:
   - `IRRegressionGate` クラスを実装。
   - `run_gate(threshold_drop: float = 0.03) -> int`:
     - 既存の `SearchEvaluator` を用いて現在の検索エンジン実装に対する総合評価を実行。
     - `baseline_metrics.json` を読み込み、`ndcg_at_10`, `mrr`, `map` の相対変動率 $\Delta = \frac{\text{current} - \text{baseline}}{\text{baseline}}$ を算出。
     - $\Delta < -threshold\_drop$（例: -3%）の場合、劣化要因となったクエリ一覧を詳細フォーマットして標準エラー出力に出力し、`sys.exit(1)` を送出。
2. **ステップ 2: ベースライン指標の初期生成と更新コマンド**:
   - `python -m search.eval.ci_gate --update-baseline` フラグをサポート。
   - 現在の検索エンジン健全状態のメトリクスを `src/search/eval/baseline_metrics.json` に構造化出力。
3. **ステップ 3: `Makefile` へのターゲット統合**:
   - `ir_eval`: 現在の IR メトリクス（P@10, R@10, MAP, MRR, NDCG@10）をターミナルに美しい表形式で出力。
   - `check_ir_regression`: CI 用の回帰チェックターゲット。`make test` または `make check` の連動対象に追加可能とする。
4. **ステップ 4: テストスイートと品質検証**:
   - `tests/search/eval/test_ci_gate.py` で、意図的に検索エンジンが劣化したモックを与えた場合に正しく exit code 1 で終了すること、向上または許容範囲内であれば exit code 0 で成功することをテスト。
   - `make format`, `make static_analysis` (Xenon Rank A, Mypy Strict), `pytest` 100% PASS を達成。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `make ir_eval` により NDCG@10, MRR, MAP, P@10, R@10 が 5 秒以内に計測・表示されること
- [x] `make check_ir_regression` において、NDCG@10 がベースラインより 3% 超低下した際にビルドが適切に失敗（exit code 1）すること
- [x] タイブレーク処理が完全に決定論的であり、複数回実行してもメトリクスの数値が一切ぶれないこと
- [x] `--update-baseline` コマンドによりベースライン JSON が正しく更新されること
- [x] 全品質ゲート（Xenon Rank A, Flake8 0 errors, Mypy Strict 0 errors, pytest 100% PASS）を満たすこと
