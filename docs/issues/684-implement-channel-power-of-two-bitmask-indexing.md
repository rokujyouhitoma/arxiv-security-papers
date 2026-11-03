---
ID: 684
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] チャネル容量の Power-of-Two ビットマスク化と剰余除算 (idiv) の完全排除 (ID: 684)

## 1. 概要 / Summary
現在の `ulisp/runtime/concurrency/channel.scm` におけるリングバッファインデックス計算は、`(modulo cur-head cap)` および `(modulo cur-tail cap)` により実装されている。
x86-64 アーキテクチャにおいて `idiv`（整数除算）命令は 20〜40 CPU サイクルを消費し、パイプラインの重大なストール要因となっている。
本 Issue では、チャネル生成時に容量（capacity）を直近の 2 の冪乗（$2^k$）へ自動切り上げクランプし、インデックス計算をビットマスク `(bitwise-and cur (- cap 1))` に置換することで、1 サイクル（~0.3 ns）の単一ビット演算に最適化し、チャネル送受信遅延を大幅に削減する。

---

## 2. トレーサビリティ / Traceability
- 関連仕様: DSN-37 Section 4, 4.3.1 (Linear Ownership Transfer Channel)
- 関連 Issue: [Issue #680](closed/680-implement-synapse-channel-cacheline-padding-unboxed-fastpath.md), [Issue #682](closed/682-implement-nanopass-concurrency-hotpath-inlining-and-type-check-elimination.md)
- ベンチマーク基準: `docs/benchmarks/concurrency_evaluation.md` (線形チャネル送受信遅延の高速化)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/runtime/concurrency/channel.scm](../../ulisp/runtime/concurrency/channel.scm)
- [ ] [ulisp/lib/ulisp/concurrency/channel.sld](../../ulisp/lib/ulisp/concurrency/channel.sld)
- [ ] [benchmarks/concurrency/bench_microtasks.scm](../../benchmarks/concurrency/bench_microtasks.scm)
- [ ] [ulisp/tests/concurrency/test_channel.scm](../../ulisp/tests/concurrency/test_channel.scm)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/684-channel-power-of-two-bitmask`

1. **容量の 2 の冪乗切り上げヘルパー (`%round-to-power-of-two`) の導入**:
   - `make-channel` 時に要求された `capacity`（1以上）を最小の $2^k$（例: 1000 -> 1024）に正規化。
   - レコード内に `capacity-mask`（`(- cap 1)`）を保持。
2. **インデックス計算のビットマスク化**:
   - `%channel-ring-try-enqueue!` 内の `(modulo cur-head cap)` を `(bitwise-and cur-head mask)` に変更。
   - `%channel-ring-try-dequeue!` 内の `(modulo cur-tail cap)` を `(bitwise-and cur-tail mask)` に変更。
3. **CWE-190 / CWE-119 境界防御の維持**:
   - オーバーフロー耐性を保ち、マスク演算が常に有効なバッファ範囲 `[0, cap - 1]` を指すことを保証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `make-channel` において容量が自動的に 2 の冪乗に切り上げられ、マスクが正しく初期化される。
- [ ] `%channel-ring-try-enqueue!` および `%channel-ring-try-dequeue!` から `modulo` が完全排除され、`bitwise-and` に置換されている。
- [ ] チャネル単体テストおよび既存並行性テストが 100% PASS すること。
- [ ] 線形チャネル送受信遅延が顕著に低減すること。
