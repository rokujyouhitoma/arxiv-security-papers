---
ID: 742
種別: Bug / Architecture
優先度: High (P1)
ステータス: Closed (Completed)
---

# [BUG/SEC] 再起動した Supervisor 子タスクのスケジューラ自動投入 (ID: 742)

## 1. 概要 / Summary
Issue #727 において Supervisor が子タスクのクラッシュ・DOWN シグナルを自動検知して再起動処理（子プロセスの再生成）を行う仕組みが導入されたが、再起動により生成された新しい子タスクコンテキスト (`<task-context>`) がスケジューラ (`<work-stealing-scheduler>`) に自動投入（エンキュー）されない不具合が存在した。

現状のテストスイート (`tests/concurrency/test_supervisor.scm` Group 7) では、テストコード側で再起動された子タスクコンテキストを手動で取得し、手動で `(scheduler-spawn! sched t-child-2 0)` を呼び出すことで代用しており、Supervisor 単体での自律的・透過的な再起動・実行サイクルが成立していなかった。

本改修では、Supervisor にアクティブなスケジューラインスタンスへの参照を保持させ、全再起動戦略 (`one_for_one`, `one_for_all`, `rest_for_one`) において新しく生成された子タスクが自律的にスケジューラの実行キューへ自動エンキューされるアーキテクチャを確立した。

---

### 再現手順 / Steps to Reproduce
1. スケジューラ `sched` を生成し、Supervisor `sup` の管理下で子タスク A を起動する。
2. 子タスク A で例外（例: `(car '())`）を発生させ異常終了（クラッシュ）させる。
3. Supervisor が `DOWN` シグナルを受信し、戦略に基づいて新たな子タスク A' を生成する。
4. テストコード等の外部介入なしに `(scheduler-run! sched)` を実行しても、A' がスケジューラに投入されていないため実行されずアイドル停止する。

---

### 再現環境 / Environment
- OS / Arch: Linux (x86-64 / aarch64)
- 関連コンポーネント:
  - `ulisp/runtime/concurrency/channel.scm`
  - `ulisp/runtime/concurrency/supervisor.scm`
  - `ulisp/runtime/concurrency/scheduler.scm`
  - `tests/concurrency/test_supervisor.scm`
- 関連 Issue: #727, #722, #741

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [`ulisp/runtime/concurrency/channel.scm`](../../ulisp/runtime/concurrency/channel.scm): `*supervisor-scheduler-spawn-hook-box*` および `synapse-set-supervisor-scheduler-spawn-hook!` の基本定義
- [x] [`ulisp/runtime/concurrency/supervisor.scm`](../../ulisp/runtime/concurrency/supervisor.scm): `<supervisor-context>` への `scheduler-box` 追加、`make-supervisor` 拡張、再起動ヘルパー (`%supervisor-enqueue-child!`) 実装、全戦略への自動エンキュー組み込み
- [x] [`ulisp/runtime/concurrency/scheduler.scm`](../../ulisp/runtime/concurrency/scheduler.scm): スケジューラ起動・フック接続、`*supervisor-scheduler-spawn-hook-box*` との安全な連携
- [x] [`tests/concurrency/test_supervisor.scm`](../../tests/concurrency/test_supervisor.scm): Group 7 の手動 spawn 排除、自律再起動検証および Group 12 (one_for_all のスケジューラ自動投入検証) 追加

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
1. **結合境界における参照欠落**:
   `supervisor.scm` の `<supervisor-context>` 構造体は `spec`, `sup-task`, `children-box`, `restart-history-box`, `parent-sup`, `state-box` のみを保持しており、タスクを実行管理する `<work-stealing-scheduler>` への参照を持っていなかった。
2. **ロード順序の非循環性**:
   `test_supervisor.scm` や各種エントリポイントにおいて `supervisor.scm` が `scheduler.scm` より前にロードされる構成となっており、直接 `scheduler-spawn!` を呼ぶと未束縛シンボルとなる可能性があったため、モジュール境界でのフック・動的ディスパッチ機構が必要であった。
3. **テストにおける代用放置**:
   Issue #727 実装時に DOWN シグナル配送の検証が先行し、再起動タスクのスケジューラへの自動復帰が外部呼び出し（テストコードの手動 `scheduler-spawn!`）に依存したまま完了とみなされていた。

---

## 4. セキュリティ・脅威分析 (Threat Modeling & Mitigation)
- **CWE-400 (Uncontrolled Resource Consumption / DoS)**:
  - *脅威*: 子タスクがクラッシュを繰り返すフラッピング（Crash Loop）状態に陥った際、自動再起動によって際限なくスケジューラにタスクが注入され、スケジューラの最大タスク上限 (`*scheduler-max-tasks*`) 枯渇やメモリ DoS を引き起こす危険。
  - *対策*: 既存の sliding time-window アルゴリズム (`%record-restart-and-check-limit!`) による `MaxRestarts / MaxTime` 制限を厳格に連動。制限超過時は即時に `supervisor-stop!` および上位通知 (`synapse-panic!`) を発火し、スケジューラへの過剰エンキューを遮断。
- **CWE-662 (Improper Synchronization / Race Condition)**:
  - *脅威*: 複数 Worker から同時に DOWN シグナルが送出された場合や CAS リトライ時に、同一の子タスクが複数回スケジューラに重複エンキューされる危険。
  - *対策*: アトミックな CAS 操作が成功した新規生成子エントリのみに対して排他的に 1 回だけスケジューラ投入 (`%supervisor-enqueue-child!`) を実行。
- **CWE-843 (Type Confusion)**:
  - *脅威*: 不正なオブジェクトがスケジューラ参照として渡された際の実行時不正。
  - *対策*: `supervisor-set-scheduler!` および投入時に `work-stealing-scheduler?` による型チェックを徹底。

---

## 5. 恒久対策と実装内容 / Implementation Details
Target Branch: `fix/742-enqueue-restarted-child-task-to-scheduler`

### 5.1 `ulisp/runtime/concurrency/channel.scm`
- 最基底レイヤにおいて `*supervisor-scheduler-spawn-hook-box*` および登録関数 `synapse-set-supervisor-scheduler-spawn-hook!` を定義。

### 5.2 `ulisp/runtime/concurrency/supervisor.scm`
1. `<supervisor-context>` に `scheduler-box` を追加。
2. アクセサ `supervisor-scheduler` および `supervisor-set-scheduler!` を提供。
3. `make-supervisor` を拡張し、`(make-supervisor spec [parent-sup] [sched])` のシグネチャに対応（後方互換性 100% 維持）。
4. 自動エンキューヘルパー `%supervisor-enqueue-child!` を実装。
5. 全 3 大再起動戦略 (`%restart-one-for-one!`, `%restart-one-for-all!`, `%restart-rest-for-one!`) において、生成された新規子タスクを自律的に `*supervisor-scheduler-spawn-hook-box*` 経由でスケジューラへ投入。

### 5.3 `ulisp/runtime/concurrency/scheduler.scm`
- モジュール末尾で `synapse-set-supervisor-scheduler-spawn-hook!` に `scheduler-spawn!` を接続。

### 5.4 テストコードの改修・拡充 (`tests/concurrency/test_supervisor.scm`)
1. **Group 7 の自律化**:
   - `sup` に `sched` をバインド。手動 `(scheduler-spawn! sched t-child-2 0)` を完全に排除。
   - 1 回の `(scheduler-run! sched)` 内でクラッシュから再起動、スケジューラ自動エンキュー、再実行、正常終了抹消までが自律完走することを検証。
2. **Group 12 の新設**:
   - `one_for_all` 戦略において、障害発生時に複数の再起動子タスクが自動的にスケジューラに投入され、手動介入なしに全タスクが実行完了することを検証。

---

## 6. 完了条件 (DoD) / Success Criteria
- [x] `<supervisor-context>` がスケジューラへの参照を安全に保持できること
- [x] 再起動戦略 (`one_for_one`, `one_for_all`, `rest_for_one`) により生成された子タスクが自律的にスケジューラへ投入されること
- [x] `tests/concurrency/test_supervisor.scm` Group 7 から手動 spawn が完全に排除され、自動再起動サイクルが PASS すること
- [x] 新設されるスケジューラ連携テスト（Group 12）を含む全テストケースが PASS すること (76 passed, 0 failed)
- [x] 既存テストスイート (`test_links_monitors`, `test_scheduler`, `test_let_it_crash`) にリグレッションがないこと (全テスト 100% PASS)
- [x] `make lint_sexpr` (171 files balanced) および Pre-commit 静的解析（Radon, Xenon, Mypy strict）が 100% PASS すること
