---
ID: 788
種別: Bug
優先度: High
ステータス: Open (New)
---

# [BUG/SEC] Supervisor タスクのメールボックス処理完了に伴う誤った正常終了 (task-exit!) の防止 (ID: 788)

## 1. 概要 / Summary
Synapse の Supervisor タスクが、受信メールボックス内のメッセージ（DOWN シグナル等）を1回処理し終えるたびに、スケジューラによって `(task-exit! 'normal)` が実行され誤って終了状態（`terminated`）に遷移する不具合を修正する。

Supervisor のタスクはゼロ引数の手続き（thunk）として登録されているため、スケジューラの thunk 実行パスにおいて処理が完了すると無条件に `task-exit! 'normal` が呼ばれる。その結果、上位の監視者（親 Supervisor 等）へ不要な DOWN (normal) が配信され、タスク登録やリンクが解除される。次の障害で下位から DOWN が届いた際にディスパッチフックが再度 `ready` に戻して再実行するが、入れ子の Supervisor では親側が「子 Supervisor が終了した」と判断して再起動を誤発動させる。

### 再現手順 / Steps to Reproduce
1. 親 Supervisor の配下に子 Supervisor（ツリー構造の監視ツリー）を配置して起動する。
2. 子 Supervisor が一度メールボックスのポーリングを完了する。
3. スケジューラが子 Supervisor のタスクを正常終了（`task-exit! 'normal`）させる。
4. 親 Supervisor に子 Supervisor の DOWN (normal) が届き、誤って子 Supervisor の再起動処理がトリガーされる。

### 再現環境 / Environment
- OS / Env: Linux x86-64 / Synapse Concurrency Runtime
- File: `ulisp/runtime/concurrency/supervisor.scm`, `ulisp/runtime/concurrency/scheduler.scm`

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [supervisor.scm](../../ulisp/runtime/concurrency/supervisor.scm)
- [ ] [scheduler.scm](../../ulisp/runtime/concurrency/scheduler.scm)
- [ ] [test_supervisor_input.scm](../../ulisp/build/test_supervisor_input.scm)

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
- `ulisp/runtime/concurrency/supervisor.scm` の `make-supervisor`（行 385-392）にて、`sup-task` の `task-next-run` にゼロ引数 thunk を設定している。
- `ulisp/runtime/concurrency/scheduler.scm` の `scheduler-execute-task!`（行 419-425）において、thunk 手続きが正常に値を返すと無条件で `(task-exit! ctx 'normal)` を呼ぶ仕様となっている。
- これにより、Supervisor のタスクはメールボックスを処理した後に常駐せず、毎回 `terminated` 状態となりリンクの切断や登録解除が走ってしまう。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**: DOWN ディスパッチフック側で都度 `ready` への巻き戻しと親 Supervisor 側の DOWN フィルタリングを行う。
* **恒久対策 (Permanent Fix)**:
  - Supervisor タスクを終了しない常駐型アクターとして定義する。
  - または、タスクコンテキストに「常駐（daemon / persistent）」フラグを導入し、スケジューラの thunk 完了パスで `task-exit! 'normal` を呼び出さずにアイドル状態（`waiting` / `suspended`）として維持する。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `fix/788-supervisor-task-persistent-resident`

1. タスクコンテキストまたは属性に `task-resident?` フラグを設けるか、Supervisor タスクの実行ループをメッセージ待機型（または exit を呼ばない形式）へ改修。
2. `scheduler.scm` のタスク実行完了パスで、常駐型タスクに対しては `task-exit! 'normal` をスキップするように保護。
3. ネストした Supervisor（親 Supervisor -> 子 Supervisor -> Worker タスク）において、子 Supervisor がメールボックス処理後も正常終了せず親から誤再起動されないことを検証するテストを追加。

---

## 6. 完了条件 / Success Criteria (DoD)
- [ ] Supervisor タスクがメールボックス処理完了後も `terminated` にならず常駐状態を維持すること。
- [ ] 親 Supervisor を持つ入れ子 Supervisor 構成において、正常終了誤検知による不正な子 Supervisor 再起動が発生しないこと。
- [ ] 既存の単一 Supervisor テストおよびネスト監視テストが全て PASS すること。

