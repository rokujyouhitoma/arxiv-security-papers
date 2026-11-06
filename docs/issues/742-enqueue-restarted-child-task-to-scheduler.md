---
ID: 742
種別: Bug
優先度: High
ステータス: Open (In Progress)
---

# [BUG/SEC] 再起動した Supervisor 子タスクのスケジューラ自動投入 (ID: 742)

## 1. 概要 / Summary
Supervisor が子タスクのクラッシュを検知して再起動処理（子プロセスの再生成）を行っても、生成された新しい子タスクコンテキストがスケジューラに投入（エンキュー）されない。
現在のテストスイートでは、テストコード側で手動で DOWN シグナルを受け取り、手動で spawn を呼び出すことで代用しており、Supervisor 単独での自律的再起動が成立していない。

### 再現手順 / Steps to Reproduce
1. Supervisor の管理下で子タスク A を起動する。
2. 子タスク A をクラッシュさせる。
3. Supervisor が `DOWN` を検知し、再起動仕様に従って新たなタスクコンテキストを生成する。
4. スケジューラの実行キューに新タスクが投入されないため、新しい子が実行されずアイドル状態のまま停止する。

### 再現環境 / Environment
- OS / Env: All Platforms
- File: `ulisp/runtime/concurrency/supervisor.scm`, `ulisp/runtime/concurrency/scheduler.scm`
- 関連 Issue: Follow-up of #727

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [`ulisp/runtime/concurrency/supervisor.scm`](../../ulisp/runtime/concurrency/supervisor.scm)
- [ ] [`ulisp/runtime/concurrency/scheduler.scm`](../../ulisp/runtime/concurrency/scheduler.scm)
- [ ] [`ulisp/tests/test_supervisor.scm`](../../ulisp/tests/test_supervisor.scm)

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
Issue #727 において `supervisor-handle-child-down!` のハンドリングロジックが接続されたが、Supervisor 構造体内部にスケジューラインスタンスへの参照（ポインタ）が存在せず、タスク生成関数がコンテキストを返すのみで `scheduler-enqueue!` を呼び出せていなかった。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**: Supervisor を実行する外部ループ側で再起動された子をポーリングして手動 spawn する。
* **恒久対策 (Permanent Fix)**: Supervisor の生成時または起動時にアクティブなスケジューラへの参照を渡し、再起動時に内部から直接 `scheduler-enqueue!` を実行させる。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `fix/742-enqueue-restarted-child-task-to-scheduler`

1. `ulisp/runtime/concurrency/supervisor.scm`:
   - `<supervisor>` レコード定義に `scheduler` フィールドを追加。
   - `make-supervisor` または `start-supervisor!` 引数でスケジューラを受け取るように拡張（または `(current-scheduler)` パラメータを参照）。
   - 子タスクの再生成を行う `supervisor-restart-child!` 内部で、生成したタスクを直ちに `scheduler-enqueue!` に渡す。
2. `ulisp/tests/test_supervisor.scm`:
   - 手動の spawn 代用コードを排除し、Supervisor が自律的に再起動した子がスケジューラによってスケジューリングされ実行を完了することを検証。

---

## 6. 完了条件 / Success Criteria (DoD)
- [ ] Supervisor が子タスクの再起動時に自律的にスケジューラへ投入すること
- [ ] テストコード側での手動 spawn や手動介入なしに再起動後の子が実行されること
- [ ] `ulisp/tests/test_supervisor.scm` が PASS すること

