---
ID: 743
種別: Bug / Architecture
優先度: High (P1)
ステータス: Closed (Completed)
---

# [BUG/SEC] Supervisor の独立アクタータスク化と並行再起動競合の排除 (ID: 743)

## 1. 概要 / Summary
子タスクが異常終了（クラッシュ）した際、旧来の実装ではその終了処理（死亡した子タスクを実行していた Worker スレッド上、例外ハンドラの同期コンテキスト内）において直接 Supervisor の再起動処理（`supervisor-handle-child-down!`）が同期的に実行される設計となっていた。

マルチスレッド並行環境において、複数の Worker 上で管理下の子タスクが同時に死亡した場合、同一 Supervisor インスタンスに対する再起動処理が異なる Worker から並行して実行される。これにより、`one_for_all` や `rest_for_one` 戦略における子タスク管理テーブル（`ch-box`）の swap → set 操作や再起動履歴（`restart-history-box`）の更新において競合（Race Condition）が発生し、内部状態の破壊、再起動の二重実行、あるいは停止漏れ（ゾンビタスク化）が生じる重大な不具合が存在した。

本改修では、Supervisor 自身をスケジューラ上で稼働する独立したアクタータスク（`<task-context>`）へと昇華させ、Lock-Free MPSC Work-Draining Loop による排他的直列化機構を確立した。子タスク死亡時は Supervisor のメールボックスへ `DOWN` シグナルを非同期配送して `task-wake!` するのみに留め、状態遷移および再起動ロジックを Supervisor タスク自身のメッセージ処理ループで 1 件ずつ直列に実行するアーキテクチャへと刷新した。

---

### 再現手順 / Steps to Reproduce
1. `one_for_all` 戦略を持つ Supervisor 下で複数の子タスク（例: `w1`, `w2`）を異なる Worker スレッド（Worker 0, Worker 1）上で稼働させる。
2. 両 Worker 上で子タスクを同時にクラッシュさせる。
3. 両スレッドから同期ディスパッチフック経由で `supervisor-handle-child-down!` が同時に呼び出される。
4. `ch-box` に対する `atomic-swap!` および新規生成子リストの `atomic-set!` が交差競合し、一方の Worker による再起動がもう一方の上書きにより消失するか、二重生成された子タスクがゾンビ化する。

---

### 再現環境 / Environment
- OS / Arch: Linux (x86-64 / aarch64), Multi-worker Work-Stealing Scheduler
- 関連コンポーネント:
  - `ulisp/runtime/concurrency/supervisor.scm`
  - `ulisp/runtime/concurrency/links.scm`
  - `ulisp/runtime/concurrency/scheduler.scm`
  - `tests/concurrency/test_supervisor.scm`
- 関連 Issue: #727, #741, #742

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [`ulisp/runtime/concurrency/supervisor.scm`](../../ulisp/runtime/concurrency/supervisor.scm): `<supervisor-context>` への `processing-box` 追加、Lock-Free MPSC Work-Draining Loop 実装、スケジューラ稼働時のアクター非同期委譲 (`%supervisor-enqueue-child!`)
- [x] [`ulisp/runtime/concurrency/links.scm`](../../ulisp/runtime/concurrency/links.scm): `%deliver-monitor-down!` による FIFO メールボックス非同期格納と Wake 連携
- [x] [`tests/concurrency/test_supervisor.scm`](../../tests/concurrency/test_supervisor.scm): Group 13（Supervisor Actor Concurrent Crash Isolation）新設と検証

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
1. **アクター境界の侵犯 (Thread Context Bleed)**:
   Supervisor は論理的には状態を持つ独立プロセス（アクター）であるべきだが、実装上は単なるデータ構造体であり、子タスクの例外ハンドラ（死亡スレッド）から直接関数呼び出しで操作されていた。
2. **非排他的な複合アトミック操作**:
   `%restart-one-for-all!` 等において `(atomic-swap! ch-box (list))` で既存の子を停止した後に、新しい子リストを `(atomic-set! ch-box ...)` している。個々の操作はアトミックであっても、複合操作全体が不可分（Linearizable）ではないため、並行呼び出し時にインターリーブが発生して整合性が破壊されていた。
3. **同期フックの過剰適用**:
   Issue #727 で導入された `set-monitor-down-dispatch-hook!` は、単一スレッドテスト用のショートカットとしてシグナル配送と同時に同期実行する機構であったが、マルチスレッド環境ではこれが排他制御なしの並行実行経路となってしまっていた。

---

## 4. セキュリティ・脅威分析 (Threat Modeling & Mitigation)
- **CWE-662 (Improper Synchronization / Race Condition)**:
  - *脅威*: 複数スレッドからの同時再起動による状態不整合、子タスク管理テーブルの破壊、リソースリーク。
  - *対策*: Supervisor 自身の状態変更はすべて Supervisor のタスクコンテキスト（アクター）上で直列に実行。Lock-Free MPSC Work-Draining Loop により同時に 1 つの実行スレッドのみが Drain を行い、状態破壊を完全に排除。
- **CWE-833 (Deadlock / Lock Hierarchy Inversion)**:
  - *脅威*: 子タスクの例外ハンドラ内で同期的に再起動やチャネル破棄を行うと、スレッド間のリソース確保順序逆転によるデッドロックのリスクがある。
  - *対策*: 通知側（死亡スレッド）と処理側（Supervisor）を非同期メッセージキューで完全に分離し、デッドロックの可能性を排除。
- **CWE-400 (Uncontrolled Resource Consumption)**:
  - *脅威*: 同時クラッシュ時に Supervisor が重複して子タスクを増殖生成するリスク。
  - *対策*: 直列化されたメッセージループにおいて、既に終了・再起動済みの TID に対する重複シグナルを冪等に無視（Drain）し、余剰な多重再起動を抑止。

---

## 5. 恒久対策と実装内容 / Implementation Details
Target Branch: `fix/743-isolate-supervisor-into-independent-actor-task`

### 5.1 Supervisor の独立アクタータスク化と直列化 (`supervisor.scm`)
1. **`<supervisor-context>` への `processing-box` 追加**:
   排他ドレイニング状態を追跡するアトミックボックス（`make-atomic-box #f`）を追加。
2. **Lock-Free MPSC Work-Draining Loop (`supervisor-poll-down-signals!`)**:
   `atomic-cas!` による排他トークン獲得に成功したスレッドのみがメッセージの Drain ループを実行。他スレッドからの並行呼び出し時は安全にスキップされ、メッセージは先行スレッドによって順次直列処理される。
3. **スケジューラ稼働時のアクター非同期委譲**:
   `set-monitor-down-dispatch-hook!` において、スケジューラが稼働中の場合は呼び出し元 Worker 上での同期直接実行を行わず、`obs-task`（Supervisor タスク）を `ready` に設定してスケジューラへ委譲。

### 5.2 テストコードの拡充 (`tests/concurrency/test_supervisor.scm`)
- **Group 13 (Supervisor Actor Concurrent Crash Isolation)**:
  - 複数 Worker から同時に Supervisor メールボックスへ `DOWN` シグナルが着弾したシナリオをシミュレート。
  - 1 つ目の `DOWN` で `one_for_all` 再起動が行われ、2 つ目の `DOWN`（既に停止済みの旧 TID 宛）は直列ループ内で安全に Drain され、重複した多重子インスタンスの生成（二重リーク）が 0 件であることを検証（全 83 テスト PASS）。

---

## 6. 完了条件 (DoD) / Success Criteria
- [x] Supervisor タスク (`sup-task`) が独立したアクターとしてメッセージループで直列に動作すること
- [x] 外部 Worker スレッド上での同期的状態更新が排除され、非同期シグナル通知＋Wake モデルへ移行していること
- [x] マルチ Worker 環境で複数の子が同時にクラッシュしても、Supervisor の内部状態破壊やゾンビタスクが発生しないこと
- [x] 新設される並行性ストレステスト（Group 13）を含む全テストケースが PASS すること (83 passed, 0 failed)
- [x] 既存のテストスイート (`test_supervisor`, `test_links_monitors`, `test_scheduler`, `test_let_it_crash`) が 100% PASS すること
- [x] `make lint_sexpr` (171 files) および Pre-commit 静的解析（Radon, Xenon, Mypy strict）が 100% PASS すること

