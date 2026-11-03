---
ID: 684
種別: Feature
優先度: High
ステータス: Open (In Progress)
---

# [FEAT/ENH] チャネル容量の Power-of-Two ビットマスク化と剰余除算 (idiv) の完全排除 (ID: 684)

## 1. 概要 / Summary
現在の `ulisp/runtime/concurrency/channel.scm` におけるリングバッファインデックス計算は、`%channel-ring-try-enqueue!` および `%channel-ring-try-dequeue!` 内で `(modulo cur-head cap)` および `(modulo cur-tail cap)` により行われている。
x86-64 アーキテクチャにおいて `idiv`（整数除算）命令は 20〜40 CPU サイクルを消費し、パイプラインの重大なストール要因となっている。
本 Issue では、チャネル生成時に物理リングバッファ容量（`ring-capacity`）を直近の 2 の冪乗（$2^k \ge \text{capacity}$）へ切り上げ、対応するビットマスク `ring-mask`（`ring-capacity - 1`）をレコード内にキャッシュ保持する。
これにより、ホットパスのインデックス計算を `(bitwise-and cur-head ring-mask)` および `(bitwise-and cur-tail ring-mask)` に置換し、1 サイクル（~0.3 ns）の単一ビット演算に最適化し、線形チャネルの送受信遅延を大幅に削減する。

---

## 2. トレーサビリティ / Traceability
- **関連仕様**: DSN-37 Section 4, 4.3.1 (Linear Ownership Transfer Channel & Ring Buffer Architecture)
- **関連 Issue**: 
  - [Issue #680](closed/680-implement-synapse-channel-cacheline-padding-unboxed-fastpath.md): キャッシュラインパディングと Unboxed Fast-Path
  - [Issue #682](closed/682-implement-nanopass-concurrency-hotpath-inlining-and-type-check-elimination.md): Nanopass ホットパスインライン化
  - [Issue #685](685-implement-channel-flat-unboxed-memory-buffer.md): フラット Unboxed メモリバッファ導入（後続）
- **ベンチマーク基準**: `docs/benchmarks/concurrency_evaluation.md`（線形チャネル送受信遅延 681 ns/op からの短縮）

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/runtime/concurrency/channel.scm](../../ulisp/runtime/concurrency/channel.scm): `<channel>` レコード定義、コンストラクタ、エンキュー/デキューホットパスのビットマスク置換
- [x] [ulisp/lib/ulisp/concurrency/channel.sld](../../ulisp/lib/ulisp/concurrency/channel.sld): エクスポート識別子（`channel-ring-mask`）の追加
- [x] [tests/concurrency/test_channel.scm](../../tests/concurrency/test_channel.scm): Power-of-Two ビットマスク検証、非 2 冪論理容量（cap=3 等）の整合性・ラップアラウンド検証
- [x] [benchmarks/concurrency/bench_microtasks.scm](../../benchmarks/concurrency/bench_microtasks.scm): チャネルリレーベンチマークによる遅延短縮の実機実測

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/684-channel-power-of-two-bitmask`

### 4.1. 物理 2 の冪乗切り上げユーティリティの導入
- 最小 $2^k \ge n$ を計算する高速純粋手続き `%round-to-power-of-two` を定義：
  ```scheme
  (define (%round-to-power-of-two n)
    (if (<= n 1)
        1
        (let loop ((p 1))
          (if (>= p n)
              p
              (loop (* p 2))))))
  ```
- `*channel-max-capacity*`（1,048,576 = $2^{20}$）を超えないよう境界ガードを徹底。

### 4.2. `<channel>` レコード拡張と論理容量/物理容量の分離
- 論理容量 `capacity`（ユーザー要求値。例: 3, 1000）を維持しつつ、物理リング容量 `ring-capacity` を 2 の冪乗（例: 4, 1024）とする。
- これにより、`channel-capacity` の戻り値や `channel-full?`（論理満杯判定 `(- cur-head cur-tail) >= capacity`）の仕様・既存テストとの後方互換性を 100% 保持。
- `<channel>` レコードに `ring-mask` フィールドを追加：
  ```scheme
  (define-record-type <channel>
    (%make-channel message-queue recv-wait-queue send-wait-queue
                   capacity current-count closed-box
                   sent-count-box received-count-box
                   backpressure-count-box handoff-count-box
                   ring-buffer ring-head-box ring-tail-box ring-mask)
    channel?
    ...
    (ring-mask              %channel-ring-mask))
  ```

### 4.3. エンキュー・デキューホットパスの `modulo` 排除
- `%channel-ring-try-enqueue!` 内：
  ```scheme
  ;; 変更前: (let* ((slot-idx (modulo cur-head cap)) ...) ...)
  ;; 変更後:
  (let* ((mask (%channel-ring-mask ch))
         (slot-idx (bitwise-and cur-head mask))
         (slot-box (vector-ref ring slot-idx)))
    ...)
  ```
- `%channel-ring-try-dequeue!` 内：
  ```scheme
  ;; 変更前: (let* ((slot-idx (modulo cur-tail cap)) ...) ...)
  ;; 変更後:
  (let* ((mask (%channel-ring-mask ch))
         (slot-idx (bitwise-and cur-tail mask))
         (slot-box (vector-ref ring slot-idx)))
    ...)
  ```
- ホットパスから `modulo`（`idiv` 命令）を完全に撲滅し、単一サイクルの `bitwise-and`（x86 `and` 命令）に置換。

### 4.4. セキュリティ・頑健性対策 (CWE-190, CWE-119)
- **CWE-190 (Integer Overflow)**: `cur-head` / `cur-tail` がラップアラウンドした場合でも、`bitwise-and` は 2 の補数表現において正しく `[0, ring-mask]` の範囲にインデックスを収束させる。
- **CWE-119 (Buffer Overflow)**: `ring-buffer` の長さは厳密に `ring-capacity = ring-mask + 1` で割り当てられるため、範囲外アクセスが物理的に不可能。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `%round-to-power-of-two` が $n=1..1048576$ の全範囲で正確な 2 の冪乗を返すこと。
- [ ] `<channel>` レコードに `ring-mask` が保持され、`channel-ring-mask` アクセサが公開されること。
- [ ] `%channel-ring-try-enqueue!` および `%channel-ring-try-dequeue!` から `modulo` が 100% 排除され、`bitwise-and` が使用されていること。
- [ ] 非 2 冪容量（例: `capacity = 3`）においても、論理満杯（3 件）およびバックプレッシャーが正確に機能すること。
- [ ] `make -C ulisp test_channel`（全 220+ テスト）が 100% PASS すること。
- [ ] `make -C ulisp bench_concurrency` においてチャネル送受信遅延の短縮が確認できること。
- [ ] 作業ツリーの静的解析（`make static_analysis`）およびフォーマット検証を通過すること。
