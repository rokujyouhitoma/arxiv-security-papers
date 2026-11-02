---
ID: 677
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] Linux io_uring 統合による非同期ゼロコピー I/O イベント駆動およびタスクサスペンド・リジューム機構の実装 (ID: 677)

## 1. 概要 / Summary
Synapse タスクがファイル読み書きやソケット通信（ネットワーク I/O）を行う際、従来の同期 POSIX システムコール（`read` / `write`）を使用すると、OS スレッド全体がブロックされ、そのコアで待機中の他の軽量タスクが実行不能となる「ヘッドオブラインブロッキング（Head-of-Line Blocking）」が発生する。
Linux の最新非同期 I/O フレームワーク **`io_uring`**（共有サブミッションキュー SQ / コンプリーションキュー CQ）を Synapse スケジューラに直結し、タスクが I/O を発行した際に即座に状態を `'waiting-io` に遷移させて CPU を別タスクに譲渡し、I/O 完了イベント検知時に自動でスケジューラへ `'ready` タスクとして再キューイングするゼロシステムコール・ノンブロッキング I/O エンジンを確立する。

---

## 2. トレーサビリティ / Traceability
- 関連設計書: [DSN-37 ホスト・カーネル分離型 階層 CSP/アクター並行処理基盤](../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md)
- 関連 Issue:
  - [Issue #633 (第一級 P2P チャネル)](closed/633-implement-synapse-first-class-p2p-channel.md)
  - [Issue #634 (System V AMD64 Callee-saved コンテキストスイッチ)](closed/634-implement-synapse-callee-saved-context-switch.md)
  - [Issue #635 (M:N ワークスティーリングスケジューラ)](closed/635-implement-synapse-work-stealing-scheduler.md)
  - [Issue #675 (物理マルチコア並列実行エンジン)](675-implement-synapse-native-multithread-worker-pool.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/runtime/concurrency/io_uring.scm](../../ulisp/runtime/concurrency/io_uring.scm)
- [ ] [ulisp/runtime/concurrency/io_uring.s](../../ulisp/runtime/concurrency/io_uring.s)
- [ ] [ulisp/lib/ulisp/concurrency/io_uring.sld](../../ulisp/lib/ulisp/concurrency/io_uring.sld)
- [ ] [ulisp/runtime/concurrency/scheduler.scm](../../ulisp/runtime/concurrency/scheduler.scm)
- [ ] [ulisp/runtime/concurrency/channel.scm](../../ulisp/runtime/concurrency/channel.scm)
- [ ] [tests/concurrency/test_io_uring.scm](../../tests/concurrency/test_io_uring.scm)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/677-io-uring-event-loop`

1. **Linux `io_uring` リング初期化 (`io_uring.s`, `io_uring.scm`)**:
   - `SYS_io_uring_setup`（syscall 425）により SQ / CQ リングをカーネル空間と共有 mmap。
   - SQE（Submission Queue Entry）および CQE（Completion Queue Entry）の構造体定義。
2. **非同期 I/O プリミティブとタスクサスペンド (`io_uring.scm`, `channel.scm`)**:
   - `(async-read! fd buf offset task)` / `(async-write! fd buf offset task)`:
     SQE にリクエストを登録し、`task` の状態を `'waiting-io` に遷移させ、コンテキストスイッチ（`context-swap!`）で別タスクへ CPU を譲渡。
   - SQE の `user_data` フィールドにタスクポインタまたは TID を格納し、完了イベントとの対応付けを行う。
3. **スケジューラインベントループポーリング (`scheduler.scm`)**:
   - スケジューラのアイドル時または一定リダクションごとに CQ リングをチェック（`io_uring_enter`）。
   - 完了した CQE からタスクを取り出し、状態を `'ready` に戻して Chase-Lev Deque に再投入。
4. **テスト検証**:
   - 複数の並行タスクが同時にディスク/ソケット I/O を行っても、OS スレッドが停止せず別タスクが継続実行されることを検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `io_uring` のセットアップおよび SQ/CQ リングの mmap が正常に行われること。
- [ ] 非同期 I/O 発行時にタスクが正しくサスペンドし、ワーカーが別タスクを実行できること。
- [ ] I/O 完了時にタスクが自動起床し、データ送受信結果を正しく取得できること。
- [ ] `make -C ulisp test_io_uring` が 100% PASS すること。
- [ ] 相対パス規則（Gate 3）の完全適合（絶対パス 0 件）。

