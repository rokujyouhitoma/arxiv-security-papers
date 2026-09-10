---
ID: 248
種別: Feature
優先度: Medium
ステータス: Closed (2026-09-11)
担当エージェント: Software Development (SWD) / IT Service Manager / Systems Architect
---

# [FEAT/CORE] Count-Min Sketch および t-digest の共通コア実装と可観測性・分析メトリクス要約の省メモリ化 (ID: 248)

## 1. 概要 / Summary

本リポジトリの可観測性サブシステム [`src/observability/`](../../src/observability/) および分析エンジン [`src/analytics/`](../../src/analytics/) では、アクセスログ、MCP ツール呼び出し、検索レイテンシ、および CTI 脅威シグネチャの集約を行っている。

現在、頻度推定やパーセンタイル（p50/p90/p99/p99.9）の計算は、インメモリの生配列保持や完全ソートに頼っており、データ規模の拡大に伴いメモリ消費が線形に増加する。

本タスクでは、ストリーミングデータ要約の標準アルゴリズムである以下 2 つを共通コア基盤 [`src/core/structures/probabilistic.py`](../../src/core/structures/probabilistic.py) にゼロ外部依存で実装する：
1. **Count-Min Sketch**: 固定サイズの 2 次元ハッシュテーブルを用いて、高頻度アイテム（Heavy Hitters / 頻出脅威アクター等）の出現回数を劣線形メモリで推定。
2. **t-digest**: クラスタ重心（Centroid）の動的クラスタリングにより、ストリーミングログの極値・テールレイテンシパーセンタイル（p99 等）を高精度かつ定数メモリで推定。

---

## 2. トレーサビリティ / Traceability

- **設計書**:
  - [`docs/designs/DSN-21-system_wide_observability_and_distributed_tracing.md`](../designs/DSN-21-system_wide_observability_and_distributed_tracing.md) (Observability Metrics)
- **学術・技術参照**:
  - Cormode, G., & Muthukrishnan, S. (2005). "An improved data stream summary: the count-min sketch and its applications", *Journal of Algorithms*.
  - Dunning, T., & Ertl, O. (2019). "Computing Extremely Accurate Quantiles Using t-Digests", *arXiv:1902.04023*.
- **規約**:
  - ゼロ外部依存（Python 3.14 Standard Library Only）
  - Xenon Rank A (CC <= 4), `mypy --strict` 準拠

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [`src/core/structures/probabilistic.py`](../../src/core/structures/probabilistic.py) (新規):
  - `CountMinSketch`: `add(item, count=1)`, `estimate(item)`, `merge(other)`
  - `TDigest`: `add(value, weight=1)`, `quantile(q)`, `compress()`
- [x] [`src/core/structures/__init__.py`](../../src/core/structures/__init__.py):
  - `CountMinSketch`, `TDigest`, `Centroid` のエクスポート
- [x] [`tests/core/test_probabilistic.py`](../../tests/core/test_probabilistic.py) (新規):
  - 頻度推定誤差限界テスト、分位点（Quantile）推定精度テスト、マージ演算検証

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/248-implement-count-min-sketch-and-t-digest-for-observability`

1. `src/core/structures/probabilistic.py` に `CountMinSketch` と `TDigest` を実装。
2. ハッシュ関数には高速・高品質な SHA-256 / FNV-1a を活用。
3. `TDigest` は重心（Centroid）のバッファ蓄積とソートベースのマージ圧縮アルゴリズムを採用。
4. 単体テスト作成と品質ゲート（Xenon Rank A, mypy）のクリア。

---

## 5. 完了条件 / Success Criteria (DoD)

- [x] `src/core/structures/probabilistic.py` に `CountMinSketch` および `TDigest` が実装されていること。
- [x] Count-Min Sketch の推定値が過小評価せず、誤差上限（$\epsilon$）以内に収まること。
- [x] t-digest の p50, p90, p99 推定値が実測パーセンタイルに対して許容誤差（< 1%）以内に収まること。
- [x] `tests/core/test_probabilistic.py` が 100% PASS すること。
- [x] Xenon Rank A (CC <= 4)、`mypy --strict` 0 エラー、フォーマッタ 100% 合格であること。
