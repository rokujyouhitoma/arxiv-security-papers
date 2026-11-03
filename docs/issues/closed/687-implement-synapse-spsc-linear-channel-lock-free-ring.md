---
ID: 687
種別: Feature
優先度: High
ステータス: Closed (Resolved)
---

# [FEAT/ENH] 線形所有権特化型 SPSC ロックフリーリングによる LOCK プレフィックス命令ゼロ化 (ID: 687)

## 1. 概要 / Summary
現在の Synapse 線形チャネル（`channel.scm`）は、複数プロデューサ・複数コンシューマの並行アクセスに対応可能な MPMC（Multi-Producer Multi-Consumer）アルゴリズムに基づき設計されている。
しかし、この汎用性の代償として、以下のホットパスにおいて x86-64 のハードウェアバスロック（LOCK プレフィックス命令）が毎回実行されている：
1. **エンキュー時**:
   - `(atomic-cas! head-box ...)` $\rightarrow$ `lock cmpxchg` (1回)
   - `(atomic-fetch-add! current-count 1)` $\rightarrow$ `lock xadd` (1回)
   - `(atomic-fetch-add! sent-count-box 1)` $\rightarrow$ `lock xadd` (1回)
2. **デキュー時**:
   - `(atomic-cas! tail-box ...)` $\rightarrow$ `lock cmpxchg` (1回)
   - `(atomic-fetch-add! current-count -1)` $\rightarrow$ `lock xadd` (1回)
   - `(atomic-fetch-add! received-count-box 1)` $\rightarrow$ `lock xadd` (1回)

1 回のメッセージ送受信ペアあたり **合計 6 回の `lock` プレフィックス命令（バスロック / キャッシュライン無効化ブロードキャスト）** が強制され、CPU コア間の MESI キャッシュコヒーレンシトラフィックが最大の遅延要因（約 619 ns/pair）となっている。

DSN-37 の核心である **線形型（Affine Type）システム**（`pass_check_affine.scm`）により、タスク間で 1-to-1 所有権移譲が行われるチャネルは、数学的・静的に **「単一生産者・単一消費者（SPSC: Single Producer Single Consumer）」** であることが保証される。
SPSC においては、`head` は生産者のみが書き込み、`tail` は消費者のみが書き込むため、CAS（`lock cmpxchg`）やアトミック加算（`lock xadd`）は完全に不要であり、**x86-64 の通常のアトミック `mov` 命令（Acquire/Release セマンティクス）のみで送受信を完結** させることができる。

本 Issue では、SPSC 特化の Lamport 型ロックフリーリングバッファ機構を導入し、LOCK プレフィックス命令数を **6 回から 0 回（完全ゼロ化）** に削減することで、チャネル送受信遅延を Go 言語（34 ns）や Rust（74 ns）に迫る超極小遅延領域へと突入させる。

---

## 2. 背景とボトルネック分析 / Problem & Analysis

### 2.1. ハードウェアバスロックと MESI キャッシュライン無効化のコスト
- x86-64 アーキテクチャにおいて、`lock` プレフィックス付き命令（`lock cmpxchg`, `lock xadd`, `lock add` 等）は、同一キャッシュラインを共有する他コアの L1/L2 キャッシュを無効化（Invalidate）し、ストアバッファを強制フラッシュする。
- 現代のプロセッサ（Intel Raptor Lake / AMD Zen 4 等）であっても、単一の `lock` 命令には 15〜30 ns のパイプラインストールが発生する。
- 1 ペアあたり 6 回の `lock` 命令を実行すると、純粋なハードウェア待機時間だけで **90〜180 ns** を消費し、これに加えて同一キャッシュライン（`current-count`）のコア間ピンポン（False Sharing / True Sharing）が発生していた。

### 2.2. SPSC Lamport リングバッファの数学的無矛盾性
- **単一生産者（Single Producer）**:
  - `head` を進める権利を持つのは唯一の生産者タスクのみ。他のスレッドが `head` を書き換えることはないため、競合検知用の CAS（Compare-And-Swap）は不要であり、単なるローカルインクリメントと Release ストア（`mov` + メモリフェンス）で安全に公開できる。
- **単一消費者（Single Consumer）**:
  - `tail` を進める権利を持つのは唯一の消費者タスクのみ。CAS は不要であり、値取得後に Release ストアで `tail` を進めるだけでよい。
- **要素数の局所算出**:
  - バッファ内のメッセージ数は `(- head tail)` であり、双方が書き込み競合する共有 `current-count` 変数は不要である。
- **キャッシュライン完全分離**:
  - `head`（生産者が書き込み、消費者が読み込み）と `tail`（消費者が書き込み、生産者が読み込み）はそれぞれ独立した 64 バイトのキャッシュラインにパディング配置（`make-padded-atomic-box`）されているため、キャッシュラインのピンポンが原理的に発生しない。

---

## 3. セキュリティ分析 & 防御設計 (CWE Mitigations)

| 脆弱性 ID | リスク内容 | 防御設計 / 対策 |
| :--- | :--- | :--- |
| **CWE-362 (Race Condition)** | 複数コアからの同時読み書きによるリングインデックスの破壊 | SPSC 型セマンティクスにより `head` は送信者のみ、`tail` は受信者のみが書き込む。メモリフェンス（`%memory-fence`）により、スロットへのデータ書き込み完了が `head` 更新前に全コアへ不可分に可視化される。 |
| **CWE-843 (Type Confusion)** | 空バッファ番兵値 `*ring-empty*` とペイロード `#f` や `0` の混同 | 番兵値 `*ring-empty*` はユニークなポインタ（シンボル）であり、値の有無判定には厳格な `eq?` 比較を使用。 |
| **CWE-400 (Resource Exhaustion)** | バッファオーバーフローによるメモリ破壊や無制限メモリ確保 | 論理容量上限 `capacity` を超える送信要求は直ちに拒否またはサスペンド（バックプレッシャー）され、Power-of-Two ビットマスクによりリング境界外アクセスを物理遮断。 |
| **CWE-416 (Use-After-Free)** | チャネル送信後のオブジェクト不正参照 | アフィン型システム（`pass_check_affine.scm`）による Move セマンティクス強制。送信されたオブジェクトへの後続アクセスをコンパイル時に静的排除。 |

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/runtime/concurrency/channel.scm](../../ulisp/runtime/concurrency/channel.scm):
  - `<channel>` レコードに `spsc?` 属性を追加、または専用コンストラクタ `make-spsc-channel` を新設。
  - `%channel-spsc-try-enqueue!`: LOCK プレフィックス命令 0 回の SPSC エンキュー関数。
  - `%channel-spsc-try-dequeue-val!`: LOCK プレフィックス命令 0 回の SPSC デキュー関数。
  - `channel-send!`, `channel-try-send!`, `channel-recv!`, `channel-try-recv!`, `channel-try-recv-values!` における SPSC 高速ディスパッチ。
- [x] [ulisp/lib/ulisp/concurrency/channel.sld](../../ulisp/lib/ulisp/concurrency/channel.sld):
  - `make-spsc-channel`, `channel-spsc?`, `channel-spsc-try-enqueue!`, `channel-spsc-try-dequeue-val!` のエクスポート宣言。
- [x] [ulisp/lib/ulisp/concurrency/passes/pass_check_affine.scm](../../ulisp/lib/ulisp/concurrency/passes/pass_check_affine.scm):
  - アフィン型検証により 1-to-1 所有権移譲が確認されたチャネル生成式 `(make-channel cap)` を自動的に `(make-spsc-channel cap)` へ特化変換する最適化パスの実装。
- [x] [tests/concurrency/test_channel.scm](../../tests/concurrency/test_channel.scm):
  - Group 11: SPSC ロックフリーリング検証テスト（基本送受信、ラップアラウンド FIFO、バックプレッシャー、空・満杯判定、10,000 件高負荷連続送受信、ゼロロス実証）。
- [x] [benchmarks/concurrency/bench_microtasks.scm](../../benchmarks/concurrency/bench_microtasks.scm) & [docs/benchmarks/concurrency_evaluation.md](../../docs/benchmarks/concurrency_evaluation.md):
  - SPSC ロックフリーリングによるベンチマーク測定の追加とレポート更新。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/687-spsc-linear-channel-lock-free-ring`

### 5.1. SPSC 専用 Lamport ロックフリーリングの設計
```
  [Producer Core]                              [Consumer Core]
        │                                             │
        ▼ (Single Writer)                             ▼ (Single Writer)
   ┌─────────┐                                   ┌─────────┐
   │head-box │ (Cache Line 0, 64B padded)        │tail-box │ (Cache Line 1, 64B padded)
   └────┬────┘                                   └────┬────┘
        │                                             │
        ▼ (Write payload then mov head)               ▼ (Read payload then mov tail)
┌───────┴─────────────────────────────────────────────┴───────┐
│               Flat Unboxed Vector Ring Buffer               │
│  [ Slot 0 ] [ Slot 1 ] [ Slot 2 ] ... [ Slot 2^k - 1 ]      │
└─────────────────────────────────────────────────────────────┘
  ★ LOCK プレフィックス命令（lock cmpxchg / lock xadd）= 0 回！
```

### 5.2. `%channel-spsc-try-enqueue!` のコアアルゴリズム
```scheme
(define (%channel-spsc-try-enqueue! ch val)
  (let ((ring (%channel-ring-buffer ch)))
    (if (not ring)
        #f
        (let* ((cap (%channel-capacity ch))
               (mask (%channel-ring-mask ch))
               (head-box (%channel-ring-head-box ch))
               (tail-box (%channel-ring-tail-box ch))
               (head (padded-atomic-ref head-box))
               (tail (padded-atomic-ref tail-box)))
          (if (>= (- head tail) cap)
              #f ;; バッファ満杯
              (let ((slot-idx (bitwise-and head mask)))
                (vector-set! ring slot-idx val)
                (%memory-fence)
                (padded-atomic-set! head-box (+ head 1))
                #t))))))
```

### 5.3. `%channel-spsc-try-dequeue-val!` のコアアルゴリズム
```scheme
(define (%channel-spsc-try-dequeue-val! ch)
  (let ((ring (%channel-ring-buffer ch)))
    (if (not ring)
        *ring-empty*
        (let* ((mask (%channel-ring-mask ch))
               (head-box (%channel-ring-head-box ch))
               (tail-box (%channel-ring-tail-box ch))
               (tail (padded-atomic-ref tail-box))
               (head (padded-atomic-ref head-box)))
          (if (>= tail head)
              *ring-empty* ;; バッファ空
              (let* ((slot-idx (bitwise-and tail mask))
                     (val (vector-ref ring slot-idx)))
                (vector-set! ring slot-idx *ring-empty*)
                (%memory-fence)
                (padded-atomic-set! tail-box (+ tail 1))
                val))))))
```

### 5.4. アフィン最適化パス (`pass_check_affine.scm`) の自動特化
- アフィン型検証において、チャネルインスタンスへの参照が単一の送信タスクおよび単一の受信タスクにのみ Move されている（1-to-1 線形所有権が成立している）構文木を検出。
- 該当する `(make-channel n)` を `(make-spsc-channel n)` へ AST レベルで透過的にリライト。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `make-spsc-channel` コンストラクタおよび述語 `channel-spsc?` が実装され、`channel.sld` からエクスポートされること。
- [x] SPSC 線形チャネル送受信ホットパスにおいて、LOCK プレフィックス付き命令（`lock cmpxchg`, `lock xadd`）が 0 回で動作すること。
- [x] キャッシュラインの False Sharing が完全に排除され、`head` と `tail` が独立キャッシュライン上で管理されること。
- [x] 空バッファ判定、満杯判定、ラップアラウンド FIFO、および `#f` ペイロードの保持が正確に行われること。
- [x] バックプレッシャー発生時、待機送信者・受信者のサスペンドおよび起床（Handoff）が正確に動作すること。
- [x] `make -C ulisp test_channel`（全 322 テスト）が 100% PASS すること。
- [x] `make -C ulisp test_concurrency_ci`（並行性 CI ハーネス 100 反復 / 13,100 アサーション）が 100% PASS すること。
- [x] `bench_microtasks` において SPSC チャネル送受信遅延が 288 ns/pair（片道実質 ~144 ns/op）、スループット 3,466,482 msgs/sec へと大幅に向上すること。
- [x] 品質ゲート（`make check_format`, `make static_analysis`, `make py_compile`）をすべて通過すること。
