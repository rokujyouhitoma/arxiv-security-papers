---
ID: 645
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT] CI 向けマルチコア並行競合テストハーネス (concurrency_harness.scm) の実装 (ID: 645)

## 1. 概要 / Summary
[DSN-37] Phase 5 Task 5.4 および全 16 専門エージェント審査決議（第 15 章 QA 所見）に基づき、CI パイプライン（GitHub Actions）上でデータ競合、ライブロック、デッドロック、および ABA 問題の再発を完全防止する並行自動テストハーネスを実装する。

---

## 2. トレーサビリティ / Traceability
- 設計仕様書: [DSN-37: ホスト・カーネル分離型 階層 CSP/アクター・ハイブリッド並行処理基盤 ＆ AOT コンパイルパイプライン包括的アーキテクチャ設計書](../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md#task-54-ci-向けマルチコア並行競合テストハーネス-testsconcurrencyconcurrency_harnessscm) (第 14.7 節 Task 5.4、第 15 章 QA 所見)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] `tests/concurrency/concurrency_harness.scm` (新規: 並行テストハーネス)
- [ ] `Makefile` (変更: `make test_concurrency_ci` ターゲット追加)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/645-concurrency-ci-harness`

1. **カオス的ジッター（Jitter）注入**:
   - CAS ループの前後やチャネル送受信の合間にランダムな微小スリープ（ナノ秒〜マイクロ秒）を意図的に挿入し、極限の競合状況を再現。
2. **ABA パターン検証**:
   - 高速に Dequeue されたノードポインタが即座に別スレッドで再利用されるストレステストを実施し、誤更新が発生しないことを検証。
3. **自動反復実行**:
   - CI ターゲットとして 100 反復連続実行を行い、非決定論的なレースコンディションを 100% 検出。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `make test_concurrency_ci` が CI 上で 100 反復連続で 100% PASS すること
- [ ] メモリ可視性違反、CAS 無限ループ、デッドロックが 0 件であること
- [ ] すべての内部リンクが相対パスリンク規約に準拠していること
