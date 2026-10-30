---
ID: 643
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT] 10 万並行マイクロタスク耐久ベンチマークおよび STW-GC ゼロ検証スイートの実装 (ID: 643)

## 1. 概要 / Summary
[DSN-37] Phase 5 Task 5.1 & Task 5.2 に基づき、Synapse-Core 並行処理基盤の極限耐久性能を実証するベンチマークスイートを構築する。
10 万個の短命マイクロタスクの一斉生成・P2P チャネルリレー試験、およびホスト GC 誘発下でも Synapse-Core 側のレイテンシスパイクが発生しない「STW-GC ゼロ」の決定論的性能を定量検証する。

---

## 2. トレーサビリティ / Traceability
- 設計仕様書: [DSN-37: Synapse 二層分離型並行処理基盤 ＆ AOT コンパイルパイプライン包括的アーキテクチャ設計書](../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md#147-phase-5-統合検証--性能ベンチマーク) (第 14.7 節 Task 5.1 & Task 5.2)
- 関連仕様書: [DSN-35: ILISP/ULISP AOT/JIT 継続的性能ベンチマークフレームワーク設計書](../designs/DSN-35-ilisp_ulisp_aot_jit_continuous_benchmarking_framework.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] `benchmarks/synapse/bench_microtasks.scm` (新規: 10 万並行マイクロタスクベンチマーク)
- [ ] `benchmarks/synapse/bench_latency_under_gc.scm` (新規: GC 干渉下レイテンシ測定)
- [ ] `docs/benchmarks/synapse_evaluation.md` (新規: 性能評価レポート)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/643-synapse-benchmark-suite`

1. **10 万並行マイクロタスク試験 (`bench_microtasks.scm`)**:
   - 10 万個のタスクを一斉に `spawn-task`。
   - P2P チャネルを通じてトークンをリング状またはツリー状にバケツリレー。
   - スループット（タスク/秒）、平均切り替え時間、ピーク RSS メモリを記録。
2. **STW-GC ゼロ実証試験 (`bench_latency_under_gc.scm`)**:
   - コントロールプレーン側で巨大な循環リストを継続生成し、ホスト GC を意図的に連続トリガー。
   - 同時に Synapse-Core 側でパケット処理タスクを高頻度（1ms間隔）で回し、ジッター（レイテンシ分散）を測定。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 10 万個のタスクがクラッシュやスタックオーバーフローなしに正常完了すること
- [ ] ホスト GC が走る最中でも、Synapse-Core タスクの P99 レイテンシが一定（スパイクなし）を維持すること
- [ ] メモリリークが 0 バイトであり、全アリーナが即時解放されること

