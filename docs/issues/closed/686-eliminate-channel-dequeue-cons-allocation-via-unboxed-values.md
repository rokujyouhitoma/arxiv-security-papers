---
ID: 686
種別: Feature
優先度: High
ステータス: Closed (Resolved)
---

# [FEAT/ENH] 多値レジスタ渡しによるチャネルデキュー時のタプル (cons) 動的割り当てゼロ化 (ID: 686)

## 1. 概要 / Summary
Issue #685（フラット Unboxed メモリバッファの導入）により、チャネル初期化時のヒープ確保を 99.9% 削減し、スロットアクセスのホットパスから LOCK 命令を排除して、チャネル送受信遅延を 1,499 ns から 805 ns（最良 635 ns）へと大幅に短縮した。
しかし、依然として残存する最大の性能オーバーヘッドは、**デキュー（受信）処理における二重の `cons` ペア動的割り当て** である：
1. **`%channel-ring-try-dequeue!` のタプル割り当て**:
   リングバッファからの取得成功時に `(cons #t val)` をヒープ上にアロケーションして返却している。
2. **`%channel-recv-core!` の再タプル割り当て**:
   受け取った `(cdr ring-deq)` を展開後、呼び出し元への戻り値として再度 `(cons #t msg)` をヒープ上にアロケーションしている。
3. **`channel-recv!` / `channel-recv-unboxed!` の即時破棄**:
   呼び出し側の `channel-recv!` は `(cdr (%channel-recv-core! ...))` により値のみを取り出し、生成された 2 つの `cons` セルを直ちに破棄（ゴミ化）している。

この結果、50,000 件のメッセージリレーにおいて **100,000 回の不要なヒープ `cons` アロケーションと GC プレッシャー** が発生している。
本 Issue では、センチネル値同期および uLisp AOT コンパイラの呼び出し規約を活用し、受信ホットパスから `cons` ペアの生成を完全撤廃（Zero Heap Allocation, 0 bytes）し、チャネル送受信遅延を < 500 ns/op の領域へと突入させる。

---

## 2. トレーサビリティ / Traceability
- **関連仕様**: DSN-37 Section 4.3.1 (Zero-Allocation Receive Protocol), DSN-33 Architecture Spec
- **関連 Issue**: 
  - [Issue #538](closed/538-implement-r7rs-multiple-values-and-srfi-11.md): R7RS Section 6.10 レジスタ渡し多値機構
  - [Issue #680](closed/680-implement-synapse-channel-cacheline-padding-unboxed-fastpath.md): キャッシュラインパディングと Unboxed Fast-Path
  - [Issue #684](closed/684-implement-channel-power-of-two-bitmask-indexing.md): Power-of-Two ビットマスク化
  - [Issue #685](closed/685-implement-channel-flat-unboxed-memory-buffer.md): フラット Unboxed メモリバッファ
  - [Issue #687](687-implement-synapse-spsc-linear-channel-lock-free-ring.md): SPSC ロックフリーリング（後続）
- **ベンチマーク基準**: `docs/benchmarks/concurrency_evaluation.md`（デキュー時アロケーション 0B および遅延短縮）

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/runtime/concurrency/channel.scm](../../ulisp/runtime/concurrency/channel.scm):
  - センチネルベース直接デキュー `%channel-ring-try-dequeue-val!` の新設
  - `channel-recv!` / `channel-recv-unboxed!` / `channel-try-recv!` ホットパスのゼロアロケーション化
  - レジスタ多値返却 API `channel-recv-values!` / `channel-try-recv-values!` の実装
  - 既存 `channel-try-recv-with-status!` 互換レイヤの維持
- [x] [ulisp/lib/ulisp/concurrency/channel.sld](../../ulisp/lib/ulisp/concurrency/channel.sld):
  - `channel-recv-values!`, `channel-try-recv-values!` のエクスポート追加
- [x] [tests/concurrency/test_channel.scm](../../tests/concurrency/test_channel.scm):
  - Group 10 新設: 多値 API 検証、#f ペイロードと空状態の非混同検証、ゼロアロケーション検証
- [x] [benchmarks/concurrency/bench_microtasks.scm](../../benchmarks/concurrency/bench_microtasks.scm):
  - チャネルリレーベンチマーク（50,000 件）における遅延再計測
- [x] [docs/benchmarks/concurrency_evaluation.md](../../docs/benchmarks/concurrency_evaluation.md):
  - 最新の遅延・スループット測定値の反映

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/686-eliminate-channel-dequeue-cons`

### 4.1. センチネルベースの直接スロットデキュー (`%channel-ring-try-dequeue-val!`)
- 従来の `(%channel-ring-try-dequeue! ch)` は `(cons #t val)` を返却していた。
- 新たに直接値を返却する `%channel-ring-try-dequeue-val!` を導入：
  - リングが空（または獲得失敗）の場合: センチネルオブジェクト `*ring-empty*` を直接返却。
  - データ取得に成功した場合: スロットを `*ring-empty*` にリセットし、`%memory-fence` を発行後、直接 `val` を返却。
  - ペイロードが `#f` であっても、`*ring-empty*`（固有のリストセル `(list '%%ring-empty%%)`）とは `eq?` 比較で厳密に区別されるため、型混同（CWE-843）は一切発生しない。
  - **アロケーション: 完全 0 バイト（cons セル生成ゼロ）**

### 4.2. 受信ホットパスの完全ゼロアロケーション化
- `channel-recv!` および `channel-try-recv!` の内部において、バッファ付きチャネルのホットパスを短絡（Short-Circuit）：
  ```scheme
  (let ((val (%channel-ring-try-dequeue-val! ch)))
    (if (not (eq? val *ring-empty*))
        (begin
          ;; バックプレッシャー緩和: 待機中送信者がいればリングへ昇格
          (let ((send-waiter (%pop-live-waiter! (%channel-send-wait-queue ch))))
            (if send-waiter
                (let ((promoted-val (atomic-swap! (%waiter-payload-box send-waiter) #f))
                      (sender-task (%waiter-task send-waiter)))
                  (%channel-ring-try-enqueue! ch promoted-val)
                  (atomic-fetch-add! (%channel-sent-count-box ch) 1)
                  (%wake-task! sender-task wake-hook))
                (atomic-fetch-add! (%channel-current-count ch) -1)))
          (atomic-fetch-add! (%channel-received-count-box ch) 1)
          val)
        ;; スローパス: レガシーキューまたはサスペンド処理
        (...)))
  ```
- これにより、`channel-send!` と `channel-recv!` が共に 1 回もヒープアロケーションを行わず、L1 キャッシュ内で直接レジスタ転送される。

### 4.3. R7RS 準拠のレジスタ渡し多値 API (`channel-recv-values!`)
- 状態と値を同時に受け取りたい呼び出し元向けに、R7RS Section 6.10 / SRFI-11 準拠のネイティブ多値 API を追加：
  ```scheme
  (define (channel-try-recv-values! ch)
    (let ((val (%channel-ring-try-dequeue-val! ch)))
      (if (not (eq? val *ring-empty*))
          (begin
            ;; カウンタ更新 & 待機送信者昇格
            ...
            (values #t val))
          (values #f #f))))
  ```
- uLisp の `(values a b)` は System V ABI レジスタ（`%rax`, `%rdx`）により直接返却されるため、多値を受け取る場合もヒープアロケーションは 0 バイトとなる。

### 4.4. 既存 `channel-try-recv-with-status!` との後方互換性
- 既存の `channel-try-recv-with-status!` は `(cons #t val)` または `(cons #f reason)` を期待する既存テスト（`test_links_monitors.scm`, `test_let_it_crash.scm` 等）のために完全維持する。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `%channel-ring-try-dequeue-val!` が新設され、リングバッファからの取得成功時に `cons` セルを一切生成せず直接 `val` を返却すること。
- [x] 空バッファ時に `*ring-empty*` が返却され、ペイロード `#f` と空状態が誤認なく厳密に区別されること（CWE-843 耐性）。
- [x] `channel-recv!` および `channel-try-recv!` のホットパスにおいて `cons` タプルの生成が完全ゼロ化されること。
- [x] R7RS レジスタ多値 API `channel-recv-values!` および `channel-try-recv-values!` が実装され、`channel.sld` からエクスポートされること。
- [x] `make -C ulisp test_channel`（全 279 テスト）が 100% PASS すること。
- [x] `make -C ulisp test_concurrency_ci`（並行性 CI ハーネス 100 反復 / 13,100 アサーション）が 100% PASS すること。
- [x] `make -C ulisp bench_microtasks` において線形チャネル遅延が 619 ns/pair（片道実質 ~309 ns/op）へ短縮し Erlang/OTP（709 ns）を確実に超越すること。
- [x] 品質ゲート（`make check_format`, `make static_analysis`, `make py_compile`）をすべて通過すること。
