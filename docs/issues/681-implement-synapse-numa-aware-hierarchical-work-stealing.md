---
ID: 681
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] NUMA-Aware 階層型 Work-Stealing スケジューリングの実装 (ID: 681)

## 1. 概要 / Summary
現在の Synapse Work-Stealing スケジューラ（`scheduler.scm`）は、ワーカーのタスク枯渇時に全ワーカーから一様にランダムスチール（Victim Selection）を行う。
しかし、物理マルチコアやマルチソケット環境（NUMA: Non-Uniform Memory Access）においては、別ソケットや別 NUMA ノード上のデックからタスクをスチールすると、QPI/UPI 相互接続バス経由の高遅延メモリアクセスが発生し、L3 キャッシュのヒット率が低下する。
本 Issue では、同一 NUMA ノード / L3 キャッシュドメイン内のワーカーを優先的にスチールし、枯渇時のみクロスノードスチールを行う階層型 Work-Stealing アルゴリズムを実装し、多コア環境におけるスケーラビリティを飛躍的に向上させる。

---

## 2. トレーサビリティ / Traceability
- 関連設計書: [DSN-37 Synapse Dual-Plane Concurrent Runtime Architecture](../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md)
- 関連評価書: [Synapse Concurrency Benchmark Suite](../benchmarks/concurrency_evaluation.md)
- 先行 Issue: [Issue #675: ネイティブスレッド生成と CPU コアピニング](closed/675-implement-synapse-native-multithread-worker-pool.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/runtime/concurrency/scheduler.scm](../../ulisp/runtime/concurrency/scheduler.scm) (階層型被害者選定ロジック、NUMA トポロジ管理)
- [ ] [ulisp/runtime/concurrency/thread.s](../../ulisp/runtime/concurrency/thread.s) (CPU トポロジ・NUMA ノード問い合わせシステムコールまたは procfs 読取)
- [ ] [tests/concurrency/test_scheduler.scm](../../tests/concurrency/test_scheduler.scm)
- [ ] [tests/concurrency/test_multithread_scheduler.scm](../../tests/concurrency/test_multithread_scheduler.scm)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/681-synapse-numa-aware-hierarchical-work-stealing`

1. **CPU / NUMA トポロジ検出**:
   - 各ワーカー ID が属する NUMA ノード / CPU クラスター ID を初期化時に決定（または親ノード情報からグループ化）。
2. **階層型スチールアルゴリズム (2-Tier Steal)**:
   - Tier 1: 同一 NUMA ノード内のワーカーデックを優先的にランダムスチール。
   - Tier 2: ローカルノードが完全に枯渇した場合のみ、リモートノードのワーカーからスチール。
3. **負荷分散と局所性の両立**:
   - L3 キャッシュ局所性を維持しつつ、システム全体のリソース遊休を防止するフォールバック制御。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] スケジューラがワーカーのクラスタリング（ノードグループ）を認識できること。
- [ ] ワークスティーリング時に同一ノード内ワーカーが優先選択されること。
- [ ] 全ワーカー並行実行時の競合テスト（`test_scheduler`, `test_multithread_scheduler`）が 100% PASS すること。
- [ ] 絶対パスリンクが 0 件であり、全内部リンクが相対パスであること。

