---
ID: 680
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] 線形チャネルの 64 バイト・キャッシュラインパディングと Unboxed Fast-Path による False Sharing 排除 (ID: 680)

## 1. 概要 / Summary
Synapse 並行処理基盤（[DSN-37](../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md)）における線形チャネル（Linear Channel）の P2P メッセージング送受信遅延は 1,207 ns/op であり、Go（34 ns）や Rust（74 ns）と比較して改善余地がある。
この主な要因は、チャネルレコード内の Head / Tail ポインタが同一キャッシュラインに近接することによるマルチコア間の False Sharing（キャッシュライン・バウンシング）と、Scheme レコード・ベクタの動的 boxing / unboxing オーバーヘッドである。
本 Issue では、64 バイト境界キャッシュラインパディングの適用と、8 バイト固定長ポインタ/整数に特化した Unboxed Fast-Path 送受信プリミティブを導入し、チャネル通信遅延を大幅に削減する。

---

## 2. トレーサビリティ / Traceability
- 関連設計書: [DSN-37 Synapse Dual-Plane Concurrent Runtime Architecture](../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md)
- 関連評価書: [Synapse Concurrency Benchmark Suite](../benchmarks/concurrency_evaluation.md)
- 先行 Issue: [Issue #635: 分散 M:N ワークスティーリングスケジューラ](closed/635-implement-synapse-work-stealing-scheduler.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/runtime/concurrency/channel.scm](../../ulisp/runtime/concurrency/channel.scm) (64B パディング構造、Unboxed Fast-Path)
- [ ] [ulisp/runtime/concurrency/atomic.s](../../ulisp/runtime/concurrency/atomic.s) (アトミック Unboxed Swap / CAS プリミティブ)
- [ ] [tests/concurrency/test_channel.scm](../../tests/concurrency/test_channel.scm)
- [ ] [benchmarks/concurrency/bench_microtasks.scm](../../benchmarks/concurrency/bench_microtasks.scm)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/680-synapse-channel-cacheline-padding-unboxed-fastpath`

1. **キャッシュライン独立パディング構造の適用**:
   - チャネルレコード内部のリングバッファにおいて、送信側インデックス（`head`）と受信側インデックス（`tail`）をそれぞれ 64 バイト境界にアライメント配置し、別々のキャッシュラインに分離。
2. **Unboxed Fast-Path プリミティブの実装**:
   - ポインタ値（8 バイト）の送受信において、Scheme レベルのレコード探索・メタデータ割り当てを経由せず、CAS 1 命令でリングバッファスロットに直結する Fast-Path 手続き（`channel-send-unboxed!` / `channel-recv-unboxed!`）を提供。
3. **ベンチマーク検証とレイテンシ測定**:
   - 50,000 メッセージ送受信ベンチマークにて、遅延の短縮（1,207 ns ➔ 300 ns 未満目標）およびゼロメッセージ損失の維持を検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 送信インデックスと受信インデックスが 64 バイト境界で隔離され、マルチコア同時アクセス下での False Sharing が物理的に排除されていること。
- [ ] `channel-send-unboxed!` / `channel-recv-unboxed!` Fast-Path が実装され、既存のチャネルセマンティクスと完全互換であること。
- [ ] `test_channel.scm` および `test_concurrency_harness.scm` の全アサーションが 100% PASS すること。
- [ ] チャネルメッセージング遅延が実測で大幅に低減（目標 < 500 ns/op）すること。
- [ ] 絶対パスリンクが 0 件であり、全内部リンクが相対パスであること。

