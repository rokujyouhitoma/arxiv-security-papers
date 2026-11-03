---
ID: 680
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT/ENH] 線形チャネルの 64 バイト・キャッシュラインパディングと Unboxed Fast-Path による False Sharing 排除 (ID: 680)

## 1. 概要 / Summary
Synapse 並行処理基盤（[DSN-37](../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md)）における線形チャネル（Linear Channel）の P2P メッセージング送受信遅延は現在 1,031 ns/op であり、Go（34 ns）や Rust Tokio（74 ns）と比較して改善余地がある。
この主な要因は以下の 2 点である：
1. **マルチコア間の False Sharing（Cache Line Bouncing）**: 送信側インデックス（Head）と受信側インデックス（Tail）が同一キャッシュライン（64 バイト境界）内に近接し、並行送受信時に L1/L2 キャッシュ無効化が頻発している。
2. **ノード動的確保オーバーヘッド**: 内部のメッセージキュー（Michael-Scott キュー）がメッセージごとに `<queue-node>` レコードをアロケーション・破棄している。

本 Issue では、64 バイト以上のパディングを持つ `<padded-atomic-box>` を導入して Head と Tail を別キャッシュラインへ物理隔離し、さらに `capacity > 0` の有界チャネルにおいてゼロアロケーションで循環利用可能な固定長リングバッファ（Unboxed Fast-Path）を実装する。これにより、チャネル通信遅延を大幅に削減（目標 < 500 ns/op）する。

---

## 2. トレーサビリティ / Traceability
- 関連設計書: [DSN-37 Synapse Dual-Plane Concurrent Runtime Architecture](../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md) (Section 4, 4.3.1, 6.1)
- 関連評価書: [Synapse Concurrency Benchmark Suite](../benchmarks/concurrency_evaluation.md)
- 先行 Issue: [Issue #633: 線形チャネルとバックプレッシャー機構](633-implement-synapse-linear-channel-and-backpressure.md)
- 先行 Issue: [Issue #679: 適応的スピンによる Futex 削減](679-implement-synapse-adaptive-spinning-futex-reduction.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/runtime/concurrency/atomic.scm](../../ulisp/runtime/concurrency/atomic.scm) (`<padded-atomic-box>`, `make-padded-atomic-box`, `padded-atomic-ref`, `padded-atomic-set!`, `padded-atomic-cas!`, `padded-atomic-fetch-add!`)
- [x] [ulisp/lib/ulisp/concurrency/atomic.sld](../../ulisp/lib/ulisp/concurrency/atomic.sld)
- [x] [ulisp/runtime/concurrency/channel.scm](../../ulisp/runtime/concurrency/channel.scm) (`<channel>` へのリングバッファスロット内蔵、パディング付き Head/Tail 適用、`channel-send-unboxed!`, `channel-recv-unboxed!`, 既存 `channel-send!` / `channel-recv!` のゼロアロケーション Fast-Path 化)
- [x] [ulisp/lib/ulisp/concurrency/channel.sld](../../ulisp/lib/ulisp/concurrency/channel.sld)
- [x] [tests/concurrency/test_channel.scm](../../tests/concurrency/test_channel.scm) (Unboxed Fast-Path、リングバッファ循環、境界条件・CWE テスト)
- [x] [benchmarks/concurrency/bench_microtasks.scm](../../benchmarks/concurrency/bench_microtasks.scm)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/680-synapse-channel-cacheline-padding-unboxed-fastpath`

1. **キャッシュラインパディング付きアトミックボックスの実装 (`atomic.scm`)**:
   - `<padded-atomic-box>` レコード型を 8 フィールド（`val` + 7 つのパディングスロット = 72 バイト）で定義。
   - `Slot 1` の `val` は通常の `<atomic-box>` と同一オフセット（11 バイト）に位置するため、ネイティブ `%atomic-cas!` および `%atomic-box-val` を直接適用可能。
   - 複数コアが Head と Tail を同時に CAS 更新しても、キャッシュラインの無効化（False Sharing）が物理的に発生しないことを保証。
2. **有界リングバッファ Fast-Path の統合 (`channel.scm`)**:
   - `capacity > 0` の場合、固定長ベクタ（サイズ `capacity`）を事前確保し、`<channel>` に保持。
   - `channel-send!` / `channel-send-unboxed!`:
     - 待ち受けレシーバーがいれば直接ゼロコピーハンドオフ。
     - バッファに空きがある場合、`make-queue-node` を行わずリングバッファのスロットへ直接 `vector-set!` し、パディングされた `head` をアトミック加算。
   - `channel-recv!` / `channel-recv-unboxed!`:
     - リングバッファから直接 `vector-ref` で取得し、スロットをクリア（メモリ保持防止）。パディングされた `tail` をアトミック加算。
     - 待ち受け送信者がいれば直ちにスロットへ昇格＆起床（Backpressure relief）。
3. **ゼロコピー線形所有権と CWE 防御の維持**:
   - **CWE-416 (Use-After-Free)**: 送信済みオブジェクトへのアクセス遮断。
   - **CWE-400 (Resource Exhaustion)**: `capacity` 上限（1,048,576）の厳格遵守。リングバッファ周回時のインデックス境界クランプ。
   - **CWE-843 (Type Confusion)**: 引数アサーション。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `atomic.scm` に `<padded-atomic-box>` が実装され、64 バイト以上のキャッシュライン境界分離が担保されること。
- [x] `channel.scm` の有界チャネル（`capacity > 0`）において、メッセージ送受信時のノードアロケーションがゼロ化されること。
- [x] `channel-send-unboxed!` および `channel-recv-unboxed!` API が提供され、既存の `channel-send!` / `channel-recv!` と完全互換であること。
- [x] `tests/concurrency/test_channel.scm` にパディングおよび Unboxed Fast-Path のテストが追加され、全件 100% PASS すること。
- [x] 既存の並行テストスイート（`test_channel`, `test_scheduler`, `test_multithread_scheduler`, `test_concurrency_harness`）が 100% PASS すること。
- [x] ベンチマーク `bench_microtasks` において、チャネルメッセージング遅延が大幅に短縮（目標 < 500 ns/op）すること。
- [x] S式構文バランス検査（`lint_sexpr`）、Python 静的解析が 100% PASS すること。
- [x] 絶対パスリンクが 0 件であり、全内部リンクが相対パスであること。

---

## 6. 検証結果 / Verification Results
- **Channel P2P Messaging Latency**:
  - 改修前: 1,031 ns/op (往復 2,062 ns)
  - 改修後: **320 ns/op** (往復 640 ns, 目標 < 500 ns/op を大幅達成、**3.2倍高速化**)
  - スループット: **1,560,068 msgs/sec**
- **テストスイート PASS**:
  - `test_channel`: 221 passed, 0 failed (100% PASS)
  - `test_atomic`: 50 passed, 0 failed (100% PASS)
  - `test_queue`: 102 passed, 0 failed (100% PASS)
  - `test_concurrency_harness`: 100/100 Iterations PASS (13,100 assertions verified, 0 failures)
  - `bench_microtasks` & `bench_latency_under_gc`: 100% PASS (P99 2 us under GC)
  - `lint_sexpr`: 154 files checked, 100% balanced
  - `mypy --strict src`: 617 files, 0 issues
