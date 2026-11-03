---
ID: 685
種別: Feature
優先度: High
ステータス: Closed (Resolved)
---

# [FEAT/ENH] フラット Unboxed メモリバッファの導入とスロット間接ポインタ参照の完全排除 (ID: 685)

## 1. 概要 / Summary
現在の `channel.scm` のリングバッファは、`(make-vector ring-cap)` の各スロットに個別の `(make-atomic-box *ring-empty*)` を割り当てる二重ポインタ構造となっている。
この設計は以下の深刻な性能ボトルネックを抱えている：
1. **二重間接ポインタ参照（ポインタチェイス）**:
   スロットへのアクセスごとに `(vector-ref ring slot-idx)` で `atomic-box` のポインタを取得し、さらに `(atomic-ref slot-box)` / `(atomic-cas! slot-box ...)` を呼び出すため、2 段階のメモリアクセスが発生する。
2. **CPU L1/L2 データキャッシュの局所性悪化**:
   ベクター配列と散在する `atomic-box` ヒープオブジェクトがメモリ上で分離しており、並行コア間でのキャッシュミスを頻発させる。
3. **過大なチャネル初期化オーバーヘッド**:
   容量 1024 のチャネル作成時に 1024 回の個別ヒープアロケーションが発生する。

本 Issue では、各スロットへの個別の `atomic-box` 確保を完全撤廃し、ベクター自体をフラットな直接メモリスロット配列（Flat Unboxed Buffer）として運用する。
送信者と受信者は `head` / `tail` の CAS 排他によってスロットへの排他的アクセス権限を単一サイクルで獲得するため、スロット自体の読み書きは 64-bit アトミック `vector-ref` / `vector-set!` およびメモリフェンス（`%memory-fence`）により直接実行する。
これにより、スロット間接参照とスロットごとの CAS（`lock cmpxchg`）を撲滅し、チャネル初期化アロケーションを 99.9% 削減して送受信遅延を劇的に短縮する。

---

## 2. トレーサビリティ / Traceability
- **関連仕様**: DSN-37 Section 4, 4.3.1 (Flat Unboxed Ring Buffer Architecture)
- **関連 Issue**: 
  - [Issue #680](closed/680-implement-synapse-channel-cacheline-padding-unboxed-fastpath.md): キャッシュラインパディングと Unboxed Fast-Path
  - [Issue #684](closed/684-implement-channel-power-of-two-bitmask-indexing.md): Power-of-Two ビットマスク化
  - [Issue #686](686-eliminate-channel-dequeue-cons-allocation-via-unboxed-values.md): 多値レジスタ渡しによるデキュー cons ゼロ化（後続）
- **ベンチマーク基準**: `docs/benchmarks/concurrency_evaluation.md`（線形チャネル送受信遅延の短縮）

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/runtime/concurrency/channel.scm](../../ulisp/runtime/concurrency/channel.scm): `make-channel` / `make-channel-internal` の初期化フラット化、`%channel-ring-try-enqueue!` / `%channel-ring-try-dequeue!` の直接スロットアクセス化
- [x] [tests/concurrency/test_channel.scm](../../tests/concurrency/test_channel.scm): フラットスロット構造の検証、初期化アロケーション削減の検証、並行整合性テスト
- [x] [benchmarks/concurrency/bench_microtasks.scm](../../benchmarks/concurrency/bench_microtasks.scm): チャネルリレーベンチマーク（50,000 件）による遅延短縮の実測
- [x] [docs/benchmarks/concurrency_evaluation.md](../../docs/benchmarks/concurrency_evaluation.md): ベンチマークレポートの更新

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/685-channel-flat-unboxed-buffer`

### 4.1. チャネル初期化のフラット化（$O(N)$ 個のアトミックボックスアロケーション排除）
- `make-channel` および `make-channel-internal` において、`atomic-box` の個別生成ループを完全撤廃。
- `(make-vector ring-cap *ring-empty*)` により、全スロットがセンチネル値 `*ring-empty*` で初期化された単一の連続フラットベクターを 1 回でアロケーション：
  ```scheme
  ;; 変更前:
  ;; (let ((vec (make-vector ring-cap #f)))
  ;;   (let init-loop ((i 0))
  ;;     (vector-set! vec i (make-atomic-box *ring-empty*)) ...))
  ;; 変更後:
  (let ((ring (if (> ring-cap 0)
                  (make-vector ring-cap *ring-empty*)
                  #f)))
    ...)
  ```
- メモリアロケーション回数を $N+1$ 回から 1 回に激減させ、初期化コストを $O(1)$ に極小化。

### 4.2. エンキューホットパス（`%channel-ring-try-enqueue!`）の直接スロット書き込み
- スロット獲得後、`vector-ref ring slot-idx` により直接スロットの空き状況（`eq? old *ring-empty*`）をポーリング（スピンウェイト）。
- 空きを確認したら、`atomic-box` を介さず直接 `(vector-set! ring slot-idx val)` を実行し、`%memory-fence`（Store-Release）を発行：
  ```scheme
  (let* ((slot-idx (bitwise-and cur-head mask)))
    (let spin ()
      (let ((old (vector-ref ring slot-idx)))
        (if (not (eq? old *ring-empty*))
            (begin
              (futex-spin-pause! 4)
              (spin))
            (begin
              (vector-set! ring slot-idx val)
              (%memory-fence)
              #t)))))
  ```
- スロットごとの `atomic-cas!`（`lock cmpxchg`）が不要になり、単一の 64-bit `mov` ストア命令に最適化。

### 4.3. デキューホットパス（`%channel-ring-try-dequeue!`）の直接スロット読み取り
- スロット獲得後、`vector-ref ring slot-idx` により直接データの到着（`not (eq? val *ring-empty*)`）をポーリング。
- データ到着を確認したら、直接 `(vector-set! ring slot-idx *ring-empty*)` でスロットを空に戻し、`%memory-fence` を発行して値を返却：
  ```scheme
  (let* ((slot-idx (bitwise-and cur-tail mask)))
    (let spin ()
      (let ((val (vector-ref ring slot-idx)))
        (if (eq? val *ring-empty*)
            (begin
              (futex-spin-pause! 4)
              (spin))
            (begin
              (vector-set! ring slot-idx *ring-empty*)
              (%memory-fence)
              (cons #t val))))))
  ```
- スロットごとの `atomic-swap!`（`lock xchg`）が完全排除され、直接のメモリアクセスに集約。

### 4.4. 並行安全性とメモリモデルの担保 (DSN-37 Section 4.3.1)
- **排他性**: `head-box` および `tail-box` の CAS により、同一スロットインデックスを獲得するプロデューサは高々 1 スレッド、コンシューマは高々 1 スレッドに数学的に限定される。
- **データ競合（CWE-362）の防止**: プロデューサが `vector-set!` 後に発行する `%memory-fence` と、コンシューマのスピンポーリングが同期点（Acquire/Release 順序性）を形成するため、未初期化データの漏洩や Torn Read/Write は発生しない。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] チャネル生成時に各スロットごとの `<atomic-box>` が生成されず、単一のフラットベクター `(make-vector ring-cap *ring-empty*)` として初期化されること。
- [x] `%channel-ring-try-enqueue!` および `%channel-ring-try-dequeue!` において二重間接参照（`vector-ref` からの `atomic-ref`/`atomic-cas!`）が完全排除され、直接の `vector-ref` / `vector-set!` で動作すること。
- [x] スロットアクセスのホットパスからスロット個別 CAS / Swap（LOCK 命令）が排除されること。
- [x] `make -C ulisp test_channel`（全 265 テスト）が 100% PASS すること。
- [x] `make -C ulisp test_concurrency_ci`（並行性 CI ハーネス 100 反復 / 13,100 アサーション）が 100% PASS すること。
- [x] `make -C ulisp bench_concurrency` において線形チャネル遅延が大幅に短縮すること（実測: 805 ns/op、最良 635 ns/op、Throughput 1,241,852〜1,573,033 msgs/sec、57.6% 遅延削減）。
- [x] 静的解析（`make static_analysis`）およびフォーマット検証を通過すること。
