---
ID: 800
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT/PERF] task-context における atomic-box の遅延初期化によるヒープ割り当てと GC 負荷の削減 (ID: 800)

## 1. 概要 / Summary

Synapse 並行処理ランタイム（[DSN-37](../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md)）において、`ulisp/runtime/concurrency/channel.scm` の `%create-task-context-default` では、タスクが生成されるたびに無条件で **11 個の `(make-atomic-box ...)` オブジェクト** をヒープ上に即時割り当てている。
10 万タスクの Spawn ワークロード（`bench_microtasks.scm` 等）においては、これだけで **1,100,000 個（110 万個）以上のヒープオブジェクト** が生成され、メモリ確保オーバーヘッドと GC への多大な圧力をもたらしている。

```scheme
;; channel.scm:317-324 の現状のタスクコンテキスト初期化
(define (%create-task-context-default tid state reductions epoch)
  (%make-task-context tid state reductions 0 0
                      0 0 4096 #f epoch #f 0 0
                      (make-atomic-box #f)      ; 1. handoff-box
                      (make-atomic-box '())     ; 2. links-box
                      (make-atomic-box '())     ; 3. monitors-box
                      (make-atomic-box '())     ; 4. monitored-by-box
                      (make-atomic-box #f)      ; 5. trap-exit-box
                      (make-atomic-box '())     ; 6. owned-channels-box
                      (make-atomic-box #f)      ; 7. arena-box
                      (make-atomic-box #f)      ; 8. escape-k-box
                      (make-atomic-box 0)       ; 9. handler-chain-box
                      (make-atomic-box #f)      ; 10. executing-box
                      (make-atomic-box #f)))    ; 11. resident-box
```

しかし実際には、生成されるマイクロタスクの大多数は `links`, `monitors`, `monitored-by`, `trap-exit`, `owned-channels`, `resident` などの高度なフォールトトレランス構造や、チャンネル受信待機（`handoff-box`）、アリーナ割り当て（`arena-box`）を使用しない。
本 Issue では、これらの使用頻度の低い atomic-box をタスク生成時には `#f` で初期化しておき、実際に link や monitor、チャネル登録、アリーナ操作が呼び出された初回にのみ安全に初期化・確保する「遅延初期化（Lazy Allocation）」を導入する。
これにより、10 万タスク Spawn 時の即時ヒープオブジェクト割り当て数を最大 110 万個削減し、Spawn 性能の向上とヒープメモリ消費・GC ジッターの大幅削減を実現する。

---

## 2. 脅威モデリングと安全性検証 / Threat Modeling & Safety Analysis

| 脅威 / 脆弱性 | 影響度 | 想定攻撃・故障シナリオ | 設計・実装による対策と検証プロトコル |
| :--- | :---: | :--- | :--- |
| **CWE-362 (Race Condition / Concurrent Double Allocation)** | High | 複数ワーカーが同一タスクに対して同時に `task-links-box` や `task-monitor` を呼び出した際、別個の atomic-box が二重生成され、一方の更新が他方によって上書き・消失する。 | 拡張メタコンテキスト（`<task-meta>`）または各スロットの初期化に `atomic-cas!` によるアトミック昇格パターンを適用。初回 CAS に成功したインスタンスのみを採用し、多重生成を物理的に排除する。 |
| **CWE-400 (Uncontrolled Resource Consumption)** | Medium | 10 万タスクの生成時に 110 万個のヒープオブジェクトが一括確保され、メモリ枯渇や GC ストール（レイテンシ増大）を招く。 | タスク初期化時の即時 atomic-box 割り当てを 0〜1 個に抑制。不要なメタデータ領域を一切ヒープ確保しないことで、10 万タスク生成時のメモリフットプリントを半減以下に圧縮。 |
| **CWE-476 (NULL Pointer Dereference / False Invariant)** | High | 遅延初期化によりスロットが `#f` となっている状態で、従来のコードが `atomic-ref` を直接呼び出してクラッシュ（SIGSEGV）する。 | 公開アクセサ（`task-links-box`, `task-monitors-box`, `task-owned-channels-box`, `task-resident?` 等）が透過的に初期化済み `<atomic-box>` を保証して返却する防御的プロトコルを確立。生スロットアクセサの直接呼び出しを禁止。 |
| **CWE-843 (Type Confusion)** | Medium | 遅延初期化前の `#f` 値がリストや真偽値として誤解釈され、ロジック不整合を引き起こす。 | 型述語 `atomic-box?` および各アクセサの事前型チェックを厳格化。`#f` がそのまま外部に漏出しないよう抽象化境界を強制。 |

---

## 3. ガバナンス & 専門家レビュー / Specialist Perspectives

- **Project Manager (PM)**:
  - 10 万並行マイクロタスク耐久ベンチマークにおいて、Spawn 時間（80ms）のさらなる短縮と安定性を狙う重要最適化課題。後続の Phase 9（分散クラスタ・NUMA 最適化）の土台として不可欠。
- **Systems Architect (SA)**:
  - TCB（Task Control Block）のコア制御領域（TID, reductions, continuation-pc, epoch）と、稀少フォールトトレランス領域（links, monitors, channels）の直交分離。関心事の分離により、ランタイムのキャッシュ局所性とメモリ効率を最大化。
- **Software Development (SWD)**:
  - 11 個の atomic-box を単一の遅延拡張メタコンテキスト `<task-meta>` に集約するか、あるいは個別スロットの遅延 CAS パターンを導入。既存コードに対する 100% 透過的な互換性を死守。
- **Software Quality Assurance (SQA)**:
  - `test_channel`, `test_links_monitors`, `test_supervisor`, `test_multithread_scheduler` および 10 回連続の `test_concurrency_stress` を通して、遅延初期化に伴うデータレースが 0 件であることを機械的に検証。
- **Information Security Specialist (SEC)**:
  - タスク終了時のクリーンアップ処理（`task-cleanup-owned-channels!`, `task-handle-termination!`）において、未初期化メタコンテキストに対して不要なバスロック（`LOCK XCHG`）を発行しない Fast-Path を確立。

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [ulisp/runtime/concurrency/channel.scm](../../ulisp/runtime/concurrency/channel.scm) - `<task-context>` 定義、`%create-task-context-default`、遅延初期化アクセサ群の実装
- [x] [ulisp/runtime/concurrency/links.scm](../../ulisp/runtime/concurrency/links.scm) - `task-handle-termination!` 等における未初期化メタ Fast-Path の最適化
- [x] [ulisp/runtime/concurrency/boundary.scm](../../ulisp/runtime/concurrency/boundary.scm) - `task-executing?`, `task-arena` 等の遅延初期化整合性確認
- [x] [tests/concurrency/test_channel.scm](../../tests/concurrency/test_channel.scm) - 遅延初期化アクセサの単体テストおよび並行アクセス検証
- [x] [docs/benchmarks/concurrency_evaluation.md](../benchmarks/concurrency_evaluation.md) - メモリ削減および Spawn 時間短縮の測定結果反映

---

## 5. 実装方針 / Implementation Plan

Target Branch: `feat/800-implement-lazy-allocation-for-task-context-atomic-boxes`

### Step 1: 遅延メタコンテキスト `<task-meta>` の設計と TCB スロット再編
1. 稀少メタデータ（`links`, `monitors`, `monitored-by`, `trap-exit`, `owned-channels`, `resident`）を内包する `<task-meta>` レコードを定義：
   ```scheme
   (define-record-type <task-meta>
     (%make-task-meta links-box monitors-box monitored-by-box trap-exit-box owned-channels-box resident-box)
     task-meta?
     (links-box          %meta-links-box)
     (monitors-box       %meta-monitors-box)
     (monitored-by-box   %meta-monitored-by-box)
     (trap-exit-box      %meta-trap-exit-box)
     (owned-channels-box %meta-owned-channels-box)
     (resident-box       %meta-resident-box))
   ```
2. `<task-context>` に単一の `meta-box`（初期値 `(make-atomic-box #f)` または直接遅延初期化）を導入。
3. 実行時の一時スロット（`handoff-box`, `arena-box`, `escape-k-box`, `handler-chain-box`, `executing-box`）は、初期値を `#f` とし、値がセットされた時または待機時にのみ atomic-box を生成する。

### Step 2: CAS による安全な一回限り遅延初期化（One-time Lazy Init）
1. `(ensure-task-meta! task)` 手続きを実装：
   - `(atomic-ref (%task-meta-box task))` が既に存在する場合は即座にそれを返却。
   - `#f` の場合は `(%create-task-meta-default)` を生成し、`atomic-cas!` で格納。並行競合が発生した場合は CAS に成功した側のインスタンスを採用（CWE-362 ゼロ保証）。
2. 公開アクセサ（`task-links-box`, `task-monitors-box`, `task-monitored-by-box`, `task-owned-channels-box`, `task-resident-box`）を改修し、`ensure-task-meta!` 経由で常に有効な `<atomic-box>` を返却。既存の外部コード変更をゼロに抑える。

### Step 3: 終了処理およびクリーンアップの Fast-Path 最適化
1. `task-cleanup-owned-channels!`:
   - `meta-box` が `#f`（未初期化）なら、所有チャネルは確実に 0 件であるため、即座に 0 を返却（`LOCK XCHG` バスロックを完全回避）。
2. `task-handle-termination!`:
   - `meta-box` が `#f` なら、リンク・モニタ・所有チャネルの終了処理を一切スキップして即座に終了。

### Step 4: テスト拡充とストレステスト検証
1. `tests/concurrency/test_channel.scm` に遅延初期化検証グループを追加：
   - 生成直後は `meta-box` が `#f` であること。
   - `task-links-box` 呼び出しにより透過的に atomic-box が割り当てられること。
   - 複数スレッドからの並行アクセス時にも単一の atomic-box が共有されること。
2. `make -C ulisp test_channel`, `test_links_monitors`, `test_multithread_scheduler` を実行。
3. `make test_concurrency_stress`（10 回連続）が 100% PASS することを確認。

### Step 5: ベンチマーク実測とドキュメント更新
1. `make -C ulisp bench_concurrency_gate` を実行し、10 万タスク Spawn 時間の短縮およびスループット（>1,000,000 tasks/sec）を確認。
2. `docs/benchmarks/concurrency_evaluation.md` を最新の実測値で更新。

---

## 6. 完了条件 / Success Criteria (DoD)

- [x] **ヒープ割り当て削減**: 1 タスク生成あたりの即時 atomic-box 割り当て数が大幅に削減（11 個 $\to$ 1 個以下）されること。
- [x] **並行安全性 (CWE-362 ゼロ)**: 複数ワーカーからの遅延初期化アクセスにおいて、多重生成やデータの競合破壊が発生しないこと。
- [x] **下位互換性 100%**: 既存の `task-links-box`, `task-monitors-box`, `task-owned-channels`, `task-resident?` 等の API 契約が完全に維持されること。
- [x] **Fast-Path 最適化**: メタデータ未使用タスクの終了時クリーンアップにおいて、不要なバスロックやヒープ走査が完全にバイパスされること。
- [x] **単体テスト**: `make -C ulisp test_channel` および `test_links_monitors` が 100% PASS すること。
- [x] **並行ストレステスト**: `make test_concurrency_stress`（10 回反復）が 100% PASS すること。
- [x] **CI リグレッションゲート**: `make -C ulisp bench_concurrency_gate` が 100% PASS すること。
- [x] **相対パス規約遵守**: ドキュメントおよびコードにおいて絶対パスが完全排除されていること。
