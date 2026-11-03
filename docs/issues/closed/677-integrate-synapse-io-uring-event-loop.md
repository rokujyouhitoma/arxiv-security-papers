---
ID: 677
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT] Linux io_uring 統合による非同期ゼロコピー I/O イベント駆動およびタスクサスペンド・リジューム機構の実装 (ID: 677)

## 1. 概要 / Summary
Synapse タスクがファイル読み書きやソケット通信（ネットワーク I/O）を行う際、従来の同期 POSIX システムコール（`read` / `write`）を使用すると、OS スレッド全体がブロックされ、そのコアで待機中の他の軽量タスクが実行不能となる「ヘッドオブラインブロッキング（Head-of-Line Blocking）」が発生する。

Linux の最新非同期 I/O フレームワーク **`io_uring`**（共有サブミッションキュー SQ / コンプリーションキュー CQ）を Synapse スケジューラに直結し、タスクが I/O を発行した際に即座に状態を `'waiting-io` に遷移させて CPU を別タスクに譲渡し、I/O 完了イベント検知時に自動でスケジューラへ `'ready` タスクとして再キューイングするゼロシステムコール・ノンブロッキング I/O エンジンを確立する。

また、コンテナ環境や CI サンドボックスにおける Seccomp 制限（`EPERM` / `ENOSYS`）を検知した場合に、非同期イベントループ・シミュレーションへ透過的に切り替わる堅牢なフォールバック機構（Graceful Degradation）を内蔵し、あらゆる環境での決定論的動作と 100% のテスト完走を保証する。

---

## 2. 背景とアーキテクチャ上の位置づけ

### 2.1 DSN-37 設計仕様との対応
- **DSN-37 Section 7.4.3**: 「物理マルチコア並列化・CPU飽和アーキテクチャ」
- **DSN-37 Section 14.9 Task 7.3**: 「Linux io_uring 統合によるゼロシステムコール非同期 I/O とタスクサスペンド (`io_uring.s`, `io_uring.scm`)」
  - 目的: I/O ブロックによる OS スレッドの停止（Head-of-Line Blocking）を排除し、ストレージ/ネットワーク帯域を飽和。
  - 実装内容:
    - `SYS_io_uring_setup`（syscall 425）による SQ/CQ リングバッファの共有 mmap。
    - `async-read!` / `async-write!` 発行時のタスク状態 `'waiting-io` 遷移と即時 CPU 譲渡。
    - 完了イベント（CQE）検知時の自動 `'ready` 復帰と Deque 再投入。
  - DoD: 並行 I/O 実行下で OS スレッドがブロックされず、他タスクの計算が継続すること。

### 2.2 二重プレーン分離とゼロコピー I/O
1. **カーネル・ユーザー空間共有リング**:
   - `SYS_io_uring_setup` によりカーネルと共有メモリ（mmap）を確立し、SQE（Submission Queue Entry）への書き込みと CQE（Completion Queue Entry）の読み出しにおいてシステムコール呼び出しを最小化。
2. **協調的サスペンドとイベント駆動リジューム**:
   - I/O 要求を発行したタスクは、自身の TID を SQE の `user_data` に紐づけて `'waiting-io` に遷移。
   - スケジューラはワーカーの Chase-Lev Deque から即座に次の実行可能タスクをディスパッチ。
   - スケジューラのポーリング時に CQE を検知すると、対応する TID のタスクを即座に `'ready` へ復帰させ、Deque へ再投入。
3. **Seccomp / 環境制約への耐性と Graceful Degradation**:
   - サンドボックスや旧カーネル等で `SYS_io_uring_setup` が拒絶された場合、ユーザー空間イベントループ・シミュレータに自動退行し、上位コードの挙動を完全に維持。

---

## 3. トレーサビリティ / Traceability
- **関連設計書**:
  - [DSN-37 ホスト・カーネル分離型 階層 CSP/アクター並行処理基盤](../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md) (Section 7.4.3 & Section 14.9 Task 7.3)
- **関連 Issue**:
  - [Issue #633: 第一級 P2P チャネルの実装](closed/633-implement-synapse-first-class-p2p-channel.md)
  - [Issue #634: System V AMD64 Callee-saved コンテキストスイッチの実装](closed/634-implement-synapse-callee-saved-context-switch.md)
  - [Issue #635: M:N ワークスティーリングスケジューラの実装](closed/635-implement-synapse-work-stealing-scheduler.md)
  - [Issue #668: エフェメラルアリーナ即時破棄と Fail-Fast セマンティクスの確立](closed/668-implement-synapse-fail-fast-let-it-crash-semantics.md)
  - [Issue #675: 物理マルチコア並列実行エンジンと CPU コアピニングの実装](closed/675-implement-synapse-native-multithread-worker-pool.md)
  - [Issue #676: Linux SYS_futex による省電力ワーカー待機・起床機構の実装](closed/676-implement-synapse-futex-park-unpark-primitives.md)

---

## 4. セキュリティと堅牢性設計 (STRIDE / CWE)

| 脅威カテゴリ | 対象 CWE | 潜在リスク | 対策方針 |
|---|---|---|---|
| **Memory Corruption** | CWE-119 / CWE-787 | 非同期読み書き時のバッファ境界超過・メモリエラー | バッファ長（Bytevector または Arena 領域）と I/O 要求長の整合性を厳格検証 |
| **Use-After-Free** | CWE-416 | I/O 完了待機中にタスクがパニック・破棄され、完了通知が不正ポインタへ書き込み | タスクポインタ直接参照ではなく TID による安全な間接引き当てと、破棄済みタスクの CQE ドロップ |
| **Denial of Service** | CWE-400 | SQ リング溢れによる I/O 発行失敗やメモリ枯渇 | 有界リング容量（最大 4096 エントリ）と、満杯時のノンブロッキング `'queue_full` バックプレッシャー |
| **Deadlock** | CWE-833 | I/O 完了待ちタスクが起床せずワーカー全体がハング | ノンブロッキング CQE ポーリングと、タイムアウト・エラーハンドリングの徹底 |
| **Type Confusion** | CWE-843 | 不正なファイルディスクリプタやオブジェクト型を渡すことによるクラッシュ | `integer?`, `bytevector?`, `task-context?` 等の厳格な引数型ガード |

---

## 5. 影響範囲と関連ファイル / Scope and Affected Files

### 新規作成ファイル
- `ulisp/runtime/concurrency/io_uring.s`: System V AMD64 アセンブリ（`sys_io_uring_setup`, `sys_io_uring_enter`, mmap/munmap リングバインディング）
- `ulisp/runtime/concurrency/io_uring.scm`: `<io-uring>` レコード型、SQE サブミット、CQE 回収、タスクサスペンド/リジューム、フォールバックシミュレータ
- `ulisp/lib/ulisp/concurrency/io_uring.sld`: R7RS ライブラリ定義 `(ulisp concurrency io-uring)`
- `tests/concurrency/test_io_uring.scm`: 単体テスト、並行非同期 I/O、フォールバック、セキュリティ境界テスト

### 修正対象ファイル
- `ulisp/runtime/concurrency/scheduler.scm`: スケジューラインベントループにおける CQE ポーリングとタスク起床フック
- `ulisp/runtime/concurrency/channel.scm`: タスク状態 `'waiting-io` のサポート
- `ulisp/runtime/concurrency/eval_adapter.scm`: 評価環境への `io_uring` API バインドとスタブ
- `ulisp/Makefile`: `build/io_uring.o` ビルド、`test_io_uring` ターゲット追加、`lint_sexpr` および `test:` への統合

---

## 6. 実装方針 / Implementation Plan

Target Branch: `feat/677-synapse-io-uring-event-loop`

### Step 1: System V AMD64 アセンブリ `io_uring.s` の実装
1. システムコールラッパー:
   - `ulisp_sys_io_uring_setup(entries, params_ptr)`: syscall 425
   - `ulisp_sys_io_uring_enter(ring_fd, to_submit, min_complete, flags)`: syscall 426
   - `ulisp_sys_mmap_ring(fd, offset, size)`: syscall 9 によるカーネル共有メモリマッピング
   - `ulisp_sys_munmap_ring(addr, size)`: syscall 11
2. エラーハンドリング:
   - 負のエラーリターン（`-EPERM`, `-ENOSYS`, `-EINVAL` 等）を Scheme の `#f` またはエラーコードとして返却。

### Step 2: Scheme コアランタイム `io_uring.scm` の実装
1. レコード型 `<io-uring>`:
   ```scheme
   (define-record-type <io-uring>
     (%make-io-uring fd capacity sq-ring cq-ring sqes active? fallback-mode? pending-tasks-box)
     io-uring?
     (fd                 io-uring-fd)
     (capacity           io-uring-capacity)
     (active?            io-uring-active?)
     (fallback-mode?     io-uring-fallback-mode?)
     (pending-tasks-box  io-uring-pending-tasks-box))
   ```
2. 初期化関数 `(make-io-uring [entries])`:
   - `ulisp_sys_io_uring_setup` を呼び出し。成功した場合はネイティブ mmap モードで初期化。
   - `EPERM` / `ENOSYS` / `ENOENT` で失敗した場合は、自動的に `fallback-mode? = #t` としてユーザー空間シミュレータを起動。
3. 非同期 I/O サブミットプリミティブ:
   - `(io-uring-submit-read! ring fd bytevec offset len task)`:
     - SQE を獲得し、opcode `IORING_OP_READ`（22）を設定。
     - `user_data` に `task-tid` をセット。
     - タスク状態を `'waiting-io` に遷移。
   - `(io-uring-submit-write! ring fd bytevec offset len task)`:
     - opcode `IORING_OP_WRITE`（23）を設定。
   - `(io-uring-submit-nop! ring user-data task)`:
     - 疎通・ベンチマーク用の NOP サブミット。
4. イベント完了回収とタスクリジューム:
   - `(io-uring-poll-completions! ring)`:
     - CQE を読み出し、完了した結果（読み書きバイト数または負のエラーコード）を取得。
     - 対応するタスクコンテキストを取り出し、結果をタスクの handoff 領域に格納。
     - タスク状態を `'ready` に変更し、スケジューラへ再投入。

### Step 3: スケジューラ (`scheduler.scm`) との統合
1. デフォルト I/O リング `*current-io-uring-box*` を配備。
2. スケジューラのメインディスパッチループにおいて、アイドル時または定期的に `(io-uring-poll-completions! ring)` を実行し、I/O 完了タスクを即座に再開。

### Step 4: 堅牢なフォールバック機構
1. ネイティブ `io_uring` が使用不可能な場合でも、`io_uring.scm` 内部の非同期キューイング機構によって同一の API セマンティクス（サスペンド $\to$ 完了 $\to$ リジューム）を完全エミュレート。
2. CI 環境やコンテナ環境（GitHub Actions, Docker 等）でも一切スキップ・クラッシュすることなくテストが全件 PASS することを保証。

### Step 5: テストスイート拡充と Makefile 統合
1. `tests/concurrency/test_io_uring.scm`:
   - **Group 1**: 基本リング初期化とクローズ（ネイティブおよびフォールバック判定）。
   - **Group 2**: NOP / 非同期 I/O サブミットとタスクサスペンド（`'waiting-io` 遷移）。
   - **Group 3**: 完了ポーリングとタスク自動起床（`'ready` 復帰と結果引き渡し）。
   - **Group 4**: 複数並行タスクによる非同期ファイル読み書きテスト。
   - **Group 5**: 高スループット耐久テスト（1,000 件連続非同期 I/O 発行と回収）。
   - **Group 6**: セキュリティ・境界ガード（CWE-119, CWE-400, CWE-416, CWE-843）。
2. `ulisp/Makefile` への `build/io_uring.o`、`test_io_uring` 統合。

---

## 7. 完了条件 / Success Criteria (DoD)

- [x] `io_uring.s`, `io_uring.scm`, `io_uring.sld` が実装され、`make-io-uring`, `io-uring-submit-read!`, `io-uring-submit-write!`, `io-uring-poll-completions!` が提供されること。
- [x] カーネル `SYS_io_uring_setup` 成功時はゼロコピー・ノンブロッキング SQ/CQ リングが使用され、Seccomp/コンテナ等での制限時はフォールバックシミュレーションへ自動退行すること。
- [x] 非同期 I/O 発行時にタスクが `'waiting-io` に正しくサスペンドされ、ワーカーが別タスクを実行できること。
- [x] I/O 完了時にタスクが自動で `'ready` に復帰し、データ送受信結果を正しく取得できること。
- [x] メモリ安全性（CWE-119）、リソース上限（CWE-400）、UAF排除（CWE-416）、型アサーション（CWE-843）が完備されていること。
- [x] `make -C ulisp test_io_uring`（全テスト PASS）および全体の `make -C ulisp test` が 100% エラーなく完走すること。
- [x] Python 品質ゲート（`make py_compile` および `make static_analysis`）が 100% PASS すること。
- [x] 相対パス規則（Gate 3）の完全適合（絶対パス 0 件）。

---

## 8. レビューア・担当エージェント
- **主幹**: IT Specialist (Programming Languages & Compilers / PLC)
- **並行・OS/カーネル基盤設計**: Systems Architect & Software Development (SWD)
- **セキュリティ・監査**: Information Security Specialist & Systems Auditor
- **品質保証**: Software Quality Assurance Specialist
