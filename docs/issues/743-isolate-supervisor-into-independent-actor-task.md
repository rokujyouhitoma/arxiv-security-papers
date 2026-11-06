---
ID: 743
種別: Bug
優先度: High
ステータス: Open (In Progress)
---

# [BUG/SEC] Supervisor の独立アクタータスク化と並行再起動競合の排除 (ID: 743)

## 1. 概要 / Summary
子タスクが異常終了した際、その終了処理（死亡した子の worker スレッド上、例外ハンドラの中）において同期的に Supervisor の再起動処理が実行されている。
このため、複数の worker スレッド上で管理下の子が同時に死亡した場合、同一 Supervisor インスタンスの再起動処理が並行して実行され、内部状態（`one_for_all` / `rest_for_one` における子タスクリストの swap → set 操作等）が競合破壊される。

### 再現手順 / Steps to Reproduce
1. `one_for_all` 戦略を持つ Supervisor 下で複数の子タスクを稼働させる。
2. マルチスレッド環境において、2つの worker 上で異なる子タスクを同時にクラッシュさせる。
3. 両スレッドから同時に `supervisor-handle-child-down!` が呼ばれ、Supervisor の子タスク管理テーブルやステートがレースコンディションにより破損する。

### 再現環境 / Environment
- OS / Env: Multi-threaded OS workers (Linux x86-64)
- File: `ulisp/runtime/concurrency/supervisor.scm`, `ulisp/runtime/concurrency/links.scm`
- 関連 Issue: Follow-up of #727

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [`ulisp/runtime/concurrency/supervisor.scm`](../../ulisp/runtime/concurrency/supervisor.scm)
- [ ] [`ulisp/runtime/concurrency/links.scm`](../../ulisp/runtime/concurrency/links.scm)
- [ ] [`ulisp/runtime/concurrency/scheduler.scm`](../../ulisp/runtime/concurrency/scheduler.scm)
- [ ] [`ulisp/tests/test_supervisor.scm`](../../ulisp/tests/test_supervisor.scm)

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
Supervisor が自立した独立タスク（アクター）としてスケジューラ上で稼働しておらず、子タスク死亡時のフックコールバックとして同期実行されているため。アクターモデルの原則「状態変更はメッセージ受信ループで直列に処理する」に反し、呼び出し元のスレッドコンテキストで状態遷移を実行してしまっている。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**: Supervisor の状態更新全体をミューテックスまたはアトミック操作で排他ロックする。
* **恒久対策 (Permanent Fix)**: Supervisor 自体を独立した通常タスクとして spawn し、子タスクからの `DOWN` 通知をメールボックス経由で受信するイベントループ構造に移行する。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `fix/743-isolate-supervisor-into-independent-actor-task`

1. `ulisp/runtime/concurrency/supervisor.scm`:
   - Supervisor を独立タスクとして起動する `supervisor-start-task!` を実装。
   - Supervisor のメインループ `supervisor-loop` を構築し、メールボックスからメッセージ (`DOWN`, `EXIT`, 管理コマンド) を 1 つずつ順次取得して直列処理する。
2. `ulisp/runtime/concurrency/links.scm`:
   - 子タスク終了処理時には、Supervisor のコールバックを呼ぶのではなく、Supervisor タスク宛に `DOWN` メッセージを送信するのみにとどめる（非同期・疎結合化）。
3. `ulisp/tests/test_supervisor.scm`:
   - 複数ワーカー上で同時に複数の子が死んだ場合でも、Supervisor の再起動処理が安全に順次実行され、状態破壊が発生しないマルチスレッド並行テストを追加。

---

## 6. 完了条件 / Success Criteria (DoD)
- [ ] Supervisor が独立したアクタータスクとしてメールボックスを受信するループで動作すること
- [ ] 同期コールバックによる他スレッド上での Supervisor 内部状態直接書き換えが排除されること
- [ ] 複数子が同時に死亡した際にも Supervisor の状態が壊れず安全に再起動されること
- [ ] `ulisp/tests/test_supervisor.scm` の並行性ストレステストが PASS すること

