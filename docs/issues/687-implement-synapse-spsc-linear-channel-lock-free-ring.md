---
ID: 687
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] 線形所有権特化型 SPSC ロックフリーリングによる LOCK プレフィックス命令ゼロ化 (ID: 687)

## 1. 概要 / Summary
現在の Synapse チャネルは、複数ワーカーからの同時アクセスに対応する MPMC（Multi-Producer Multi-Consumer）前提の CAS ループ（`atomic-cas!`）およびアトミック加算（`atomic-fetch-add!`）を用いている。
しかし、DSN-37 の核心である線形型（Affine Type）システムにより、タスク間で 1-to-1 所有権移譲が行われるチャネルは、数学的に「単一生産者・単一消費者（SPSC: Single Producer Single Consumer）」であることが保証される。
本 Issue では、SPSC 特化の Lamport 型ロックフリーリングバッファを導入する。送信者は `head` のみを更新し、受信者は `tail` のみを更新することで、CAS（`lock cmpxchg`）を完全に撤廃し、x86-64 の通常の `mov`（Acquire/Release セマンティクス）のみで送受信を完結させ、ハードウェアバスロックによる遅延を撲滅して Go チャネル（42 ns）と同等以上の領域に到達させる。

---

## 2. トレーサビリティ / Traceability
- 関連仕様: DSN-37 Section 4.1, 4.3.1 (Affine Ownership SPSC Protocol)
- 関連 Issue: [Issue #638](closed/638-implement-nanopass-check-affine-types-and-raii-drop.md), [Issue #680](closed/680-implement-synapse-channel-cacheline-padding-unboxed-fastpath.md), [Issue #684](684-implement-channel-power-of-two-bitmask-indexing.md)
- ベンチマーク基準: `docs/benchmarks/concurrency_evaluation.md` (SPSC チャネル遅延 < 40 ns/op 達成)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/runtime/concurrency/channel.scm](../../ulisp/runtime/concurrency/channel.scm)
- [ ] [ulisp/lib/ulisp/concurrency/channel.sld](../../ulisp/lib/ulisp/concurrency/channel.sld)
- [ ] [ulisp/lib/ulisp/concurrency/passes/pass_check_affine.scm](../../ulisp/lib/ulisp/concurrency/passes/pass_check_affine.scm)
- [ ] [benchmarks/concurrency/bench_microtasks.scm](../../benchmarks/concurrency/bench_microtasks.scm)
- [ ] [ulisp/tests/concurrency/test_channel.scm](../../ulisp/tests/concurrency/test_channel.scm)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/687-spsc-linear-channel-lock-free-ring`

1. **SPSC 専用リングバッファ構造の定義**:
   - `spsc-head` と `spsc-tail` を個別の 64 バイトキャッシュライン（Padding）に配置。
   - `current-count` などの共通アトミック変数を廃止し、差分 `(- head tail)` により局所判定。
2. **LOCK プレフィックスなしの送受信アルゴリズム**:
   - 送信時: `tail`（受信側が更新）を volatile 読み込みし、バッファ空きがあればスロットに値を格納後、Release ストアで `head` を 1 インクリメント（単なる `mov` 命令）。
   - 受信時: `head`（送信側が更新）を volatile 読み込みし、データがあればスロットから読み取り後、Release ストアで `tail` を 1 インクリメント。
3. **アフィン型チェッカーとの連携**:
   - `pass_check_affine.scm` により 1-to-1 であることが証明されたチャネルに SPSC パスを適用。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] SPSC 線形チャネル送受信ホットパスにおいて、LOCK プレフィックス付き命令（`lock cmpxchg`, `lock xadd`）が 0 回で動作すること。
- [ ] キャッシュラインの False Sharing が完全に排除されていること。
- [ ] 単一スレッド内および 1-to-1 並行タスク間でメッセージ損失率 0%（ゼロロス）を達成すること。
- [ ] 送受信ペア遅延が 40 ns 前後まで大幅に短縮すること。
