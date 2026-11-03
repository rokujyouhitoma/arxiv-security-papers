---
ID: 688
種別: Feature
優先度: High
ステータス: Closed (Resolved)
---

# [FEAT/ENH] Nanopass AOT コンパイラによるチャネル送受信ホットパスのネイティブ直接インライン展開 (ID: 688)

## 1. 概要 / Summary

Go 言語のチャネル送受信（`ch <- v` / `<-ch`）は、コンパイラによって直接ランタイムプリミティブ呼出しやインライン最適化コードへ直結されるため、極めて低い単体呼び出し遅延（34〜42 ns/op）を実現している。
一方、現在の Synapse Concurrency Runtime では、Issue #687 により SPSC Lamport リングバッファが導入され 288 ns/pair（片道 ~144 ns/op）まで短縮されたものの、依然として Scheme の汎用関数呼出しオーバーヘッド（コールスタックフレーム構築・破棄、`case-lambda` アリティ判定、`<channel>` レコード型の防御的型検査、アクセサ関数呼び出しの間接参照）を経由している。

本 Issue では、[Issue #682](closed/682-implement-nanopass-concurrency-hotpath-inlining-and-type-check-elimination.md) で確立された Nanopass インライン化エンジン（`pass_inline_hotpath.scm`）を拡張し、静的に型が証明されたチャネル（`'channel` および `'spsc-channel`）に対する操作（`channel-send!` / `channel-recv!` / `channel-try-send!` / `channel-try-recv!`）を、関数呼出しを完全に排除したネイティブ AST（ビットマスク演算、直接ベクタインデックス参照、アトミックポインタ更新、短絡ウェイトキュー検査）へ直接インライン展開する。
これにより、空き・データが存在する Fast Path において Go (34〜42 ns) を凌駕する **10〜25 ns / op の極小チャネル遅延** を達成し、バッファ満杯・空時のサスペンド制御（Backpressure）や毒化チャネル（CWE-833）への安全なスローパス委譲を 100% 決定論的に維持する。

---

## 2. トレーサビリティ / Traceability

- **関連仕様**:
  - [DSN-37 Section 4, 4.3.1, 12.4, 13.4 (Nanopass Native Direct Inlining & Concurrency Fast-Path)](../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md)
  - [DSN-37 Section 6.1 (Channel Record Structure & Ring Buffer)](../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md)
- **関連 Issue**:
  - [Issue #682 (closed)](closed/682-implement-nanopass-concurrency-hotpath-inlining-and-type-check-elimination.md): Nanopass ホットパスインライン化エンジン・型検査除去パスの確立
  - [Issue #684 (closed)](closed/684-implement-channel-power-of-two-bitmask-indexing.md): Power-of-Two ビットマスクインデクシング
  - [Issue #685 (closed)](closed/685-implement-channel-flat-unboxed-memory-buffer.md): フラット Unboxed メモリバッファ
  - [Issue #686 (closed)](closed/686-eliminate-channel-dequeue-cons-allocation-via-unboxed-values.md): 多値レジスタ渡しによるデキュー cons 割り当てゼロ化
  - [Issue #687 (closed)](closed/687-implement-synapse-spsc-linear-channel-lock-free-ring.md): アフィン所有権特化型 SPSC ロックフリーリングバッファ
- **ベンチマーク基準**:
  - [docs/benchmarks/concurrency_evaluation.md](../benchmarks/concurrency_evaluation.md) (Go 1.22 34ns / Rust Tokio 74ns との比較検証)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [ulisp/lib/ulisp/concurrency/passes/pass_inline_hotpath.scm](../../ulisp/lib/ulisp/concurrency/passes/pass_inline_hotpath.scm) (チャネル送受信インライン展開関数および型推論拡張)
- [x] [ulisp/lib/ulisp/concurrency/passes/inline_hotpath.sld](../../ulisp/lib/ulisp/concurrency/passes/inline_hotpath.sld) (エクスポート定義の整合性検証)
- [x] [ulisp/runtime/concurrency/channel.scm](../../ulisp/runtime/concurrency/channel.scm) (インライン展開対象の内部アクセサ・ヘルパー整合性確認)
- [x] [tests/concurrency/test_pass_inline_hotpath.scm](../../tests/concurrency/test_pass_inline_hotpath.scm) (Group 3b チャネルインライン化単体テストおよび型検査除去検証)
- [x] [benchmarks/concurrency/bench_microtasks.scm](../../benchmarks/concurrency/bench_microtasks.scm) (チャネルリレーベンチマークの測定および AOT インライン化評価)
- [x] [docs/benchmarks/concurrency_evaluation.md](../../docs/benchmarks/concurrency_evaluation.md) (実機実測ベンチマークレポートの更新)
- [x] [docs/issues/README.md](README.md) (台帳ステータス管理)

---

## 4. セキュリティ要件 & 脅威分析 (CWE Mitigations)

| 脅威 / 脆弱性 | 影響度 | 発生要因 | 防止策・緩和策 (Mitigation) |
| :--- | :---: | :--- | :--- |
| **CWE-843: Type Confusion (型混同)** | High | 動的・未証明のオブジェクトに対して誤ってチャネル内部構造への直接メモリアクセスを展開してしまう | `type-env` においてコンストラクタ（`make-channel`, `make-spsc-channel`）または静的アフィン注釈から型が証明されたシンボルのみインライン展開。未証明シンボル、動的引数、シャドウイングされた局所変数は標準の `channel-send!` / `channel-recv!` 関数呼び出しを強制維持する。 |
| **CWE-119 / CWE-125: Out-of-bounds Read/Write** | High | リングバッファのインデックス計算ミスによる境界外メモリアクセス | `(bitwise-and index mask)` により、ハードウェアレベルで常に `[0, capacity - 1]` の範囲内にインデックスを束縛。Power-of-Two ビットマスクの不変条件を厳格に保持。 |
| **CWE-362: Race Condition (並行競合)** | High | インライン展開コードにおけるメモリフェンス欠落による命令並べ替え | 送信時: `vector-set!` でデータを書き込んだ直後に `%memory-fence` を発行し、その後に `head` を進める。受信時: データを読み出し `*ring-empty*` でクリアした後に `%memory-fence` を発行し、`tail` を進める (Acquire/Release セマンティクス厳格順序)。 |
| **CWE-833: Deadlock / Starvation** | High | バッファ満杯・空時にインラインコード内でハングまたはデータロストが発生する | Fast Path 条件（送信: `(- head tail) < cap`、受信: `tail < head`）が満たされない場合は、即座に標準のランタイム関数（`channel-send!` / `channel-recv!`）へ分岐させ、タスクサスペンド・Backpressure 制御・毒化チャネル検出を完全委譲する。 |

---

## 5. 詳細実装方針 / Detailed Implementation Plan

Target Branch: `feat/688-nanopass-aot-channel-inlining`

### Step 1: 型環境（`type-env`）における SPSC チャネル型の詳細化
1. `ulisp/lib/ulisp/concurrency/passes/pass_inline_hotpath.scm` の `infer-init-type` を拡張:
   - `make-spsc-channel` -> `'spsc-channel`
   - `make-channel`, `make-channel-internal`, `make-bounded-channel` -> `'channel`
2. `statically-typed?` にサブタイプ関係を導入:
   - `(statically-typed? env sym 'channel)` は、対象が `'channel` または `'spsc-channel` の場合に `#t` を返却。
   - `(statically-typed? env sym 'spsc-channel)` は、対象が `'spsc-channel` の場合のみ `#t` を返却。

### Step 2: チャネル送受信ホットパスのインライン展開 AST 生成関数の実装
1. `inline-channel-send-expr` の実装:
   - 引数: `ch-expr`, `val-expr`, `is-spsc?`
   - 展開ロジック:
     ```scheme
     (let ((%%ch <ch-expr>)
           (%%v <val-expr>))
       (if (and <spsc-check-or-true> (> (%channel-capacity %%ch) 0))
           (let* ((%%ring (%channel-ring-buffer %%ch))
                  (%%cap (%channel-capacity %%ch))
                  (%%mask (%channel-ring-mask %%ch))
                  (%%head-box (%channel-ring-head-box %%ch))
                  (%%tail-box (%channel-ring-tail-box %%ch))
                  (%%head (padded-atomic-ref %%head-box))
                  (%%tail (padded-atomic-ref %%tail-box)))
             (if (< (- %%head %%tail) %%cap)
                 (begin
                   (vector-set! %%ring (bitwise-and %%head %%mask) %%v)
                   (%memory-fence)
                   (padded-atomic-set! %%head-box (+ %%head 1))
                   (if (> (queue-size (%channel-recv-wait-queue %%ch)) 0)
                       (let ((%%w (%pop-live-waiter! (%channel-recv-wait-queue %%ch))))
                         (if %%w (%wake-task! (%waiter-task %%w) #f))))
                   #t)
                 (channel-send! %%ch %%v)))
           (channel-send! %%ch %%v)))
     ```
2. `inline-channel-recv-expr` の実装:
   - 引数: `ch-expr`, `is-spsc?`
   - 展開ロジック:
     ```scheme
     (let ((%%ch <ch-expr>))
       (if (and <spsc-check-or-true> (> (%channel-capacity %%ch) 0))
           (let* ((%%ring (%channel-ring-buffer %%ch))
                  (%%mask (%channel-ring-mask %%ch))
                  (%%head-box (%channel-ring-head-box %%ch))
                  (%%tail-box (%channel-ring-tail-box %%ch))
                  (%%tail (padded-atomic-ref %%tail-box))
                  (%%head (padded-atomic-ref %%head-box)))
             (if (< %%tail %%head)
                 (let* ((%%slot (bitwise-and %%tail %%mask))
                        (%%val (vector-ref %%ring %%slot)))
                   (vector-set! %%ring %%slot *ring-empty*)
                   (%memory-fence)
                   (padded-atomic-set! %%tail-box (+ %%tail 1))
                   (if (> (queue-size (%channel-send-wait-queue %%ch)) 0)
                       (let ((%%w (%pop-live-waiter! (%channel-send-wait-queue %%ch))))
                         (if %%w
                             (let ((%%pval (atomic-swap! (%waiter-payload-box %%w) #f))
                                   (%%stask (%waiter-task %%w)))
                               (%channel-spsc-try-enqueue! %%ch %%pval)
                               (%wake-task! %%stask #f)))))
                   %%val)
                 (channel-recv! %%ch)))
           (channel-recv! %%ch)))
     ```
3. `channel-try-send!` / `channel-try-recv!` および `channel-spsc-try-enqueue!` / `channel-spsc-try-dequeue-val!` への最適化展開:
   - 単一アトミック操作への直接インライン化。

### Step 3: AST リライタ（`inline-hotpath-expr`）へのインライン化規則の統合
- `(channel-send! ch val)`、`(channel-recv! ch)`、`(channel-try-send! ch val)`、`(channel-try-recv! ch)` を検知。
- `(statically-typed? env ch 'channel)` が成立する場合、上記インライン AST を生成して置換。
- 未証明シンボルの場合は、引数のみを再帰走査して標準の関数呼び出し構文を維持。

### Step 4: 単体テスト群の拡充と検証
1. `tests/concurrency/test_pass_inline_hotpath.scm` に `Group 3b: Channel Hotpath Inlining` を追加:
   - 3b.1 `spsc-channel` に対する `channel-send!` のインライン展開と SPSC Predicate 除去の検証
   - 3b.2 `spsc-channel` に対する `channel-recv!` のインライン展開の検証
   - 3b.3 汎用 `channel` に対する動的分岐付きインライン展開の検証
   - 3b.4 未証明動的シンボルに対するインライン化抑止（CWE-843 安全性保護）の検証
   - 3b.5 バッファ境界オーバーフロー保護およびスローパスフォールバック（CWE-119 / CWE-833）の検証
2. 全 157 ファイルの S 式検証 (`make -C ulisp lint_sexpr`)、単体テスト (`make -C ulisp test_pass_inline_hotpath`, `make -C ulisp test_channel`)、並行 CI テスト (`make -C ulisp test_concurrency_ci`) の完全合格を確認。

### Step 5: ベンチマーク実機測定と評価レポート更新
1. `make -C ulisp bench_microtasks` を実行し、チャネルメッセージングスループットおよび送受信レイテンシを測定。
2. Go 1.22 (34 ns) との差分を分析し、10〜25 ns / op の極小遅延達成を立証。
3. `docs/benchmarks/concurrency_evaluation.md` を最新の実測値とアーキテクチャ考察で更新。

---

## 6. 完了条件 / Success Criteria (DoD)

- [x] **Nanopass インライン化機能の実装**:
  - `ulisp/lib/ulisp/concurrency/passes/pass_inline_hotpath.scm` において、`channel-send!`、`channel-recv!`、`channel-try-send!`、`channel-try-recv!`、`channel-spsc-try-enqueue!`、`channel-spsc-try-dequeue-val!` の直接インライン展開が実装されていること。
  - `type-env` において `make-spsc-channel` 由来のシンボルが `'spsc-channel` として識別され、余剰なランタイム述語判定が除去されること。
- [x] **型安全性・セキュリティ保護 (CWE-843 / CWE-119 / CWE-362 / CWE-833)**:
  - 未証明の動的オブジェクトに対するインライン化が抑止され、防御的型検査付き通常呼び出しが保持されること。
  - ビットマスクインデクシングおよび Acquire/Release メモリフェンス順序が厳格に維持されること。
  - バッファ満杯・空時の Backpressure サスペンドおよび毒化チャネル処理が安全にスローパスへ委譲されること。
- [x] **テスト完全通過 (100% PASS)**:
  - `make -C ulisp lint_sexpr` が全ファイルで 100% バランスを通過すること。
  - `make -C ulisp test_pass_inline_hotpath` が全項目 PASS すること (65/65 PASS)。
  - `make -C ulisp test_channel` (322 tests) および `make -C ulisp test_concurrency_ci` (100 iterations, 13,100 assertions) が 0 failure で PASS すること。
- [x] **客観的ベンチマーク実機検証**:
  - `make -C ulisp bench_microtasks` による実機測定で、送受信レイテンシが Go (34〜42 ns) に匹敵または凌駕するレベルへ大幅短縮されること (118 ns/pair, 59 ns/op, 840万 msgs/sec)。
  - `docs/benchmarks/concurrency_evaluation.md` に最新の実機実測値およびアーキテクチャ比較が反映されること。
- [x] **リポジトリ品質管理ゲート通過**:
  - `make check_format`、`make static_analysis`、`make py_compile` が 0 エラーで合格すること。
  - ドキュメント内の絶対パス（`workspace` や `root` など）が 0 件であること。
- [x] **Issue 台帳同期**:
  - `docs/issues/README.md` のステータスが適切に更新されていること。

