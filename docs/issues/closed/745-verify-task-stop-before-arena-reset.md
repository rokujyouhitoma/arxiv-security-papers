---
ID: 745
種別: Bug / Security Fix
優先度: High
ステータス: Closed
関連PR: -
ブランチ: fix/745-verify-task-stop-before-arena-reset
CWE: CWE-416 (Use-After-Free), CWE-362 (Race Condition)
---

# [BUG/SEC] タスク完全停止確認後の安全な Ephemeral Arena リセット (ID: 745)

## 1. 概要 / Summary
タスク終了クリーンアップ処理（`synapse-cleanup-task-resources!` および `abort-task!`）における「タスクが停止したか」の判定ロジックが、直前に代入された `reductions <= 0` および `task-state = 'terminated` に依存しているため、タスクが実際にはまだ OS スレッドやコルーチン境界内で実行中であっても常に「停止済み」と誤判定されてしまう。

その結果、別スレッドからの `brutal_kill`、リンク/モニタのシグナルカスケード、または外部強制終了が発生した際、他スレッドでまだ動作中（境界内）のタスクの Ephemeral Arena が先行してリセット（メモリ解放・再利用）され、稼働中タスクが解放済みメモリにアクセスする **Use-After-Free (CWE-416)** やヒープ破損・SEGV を引き起こす重大な脆弱性がある。

### 再現手順 / Steps to Reproduce
1. ワーカー上で長時間計算またはループを実行中のタスク `T` に対し、別スレッドから `task-exit!` または `synapse-cleanup-task-resources!` を発行する。
2. `task-handle-termination!` 内で直前に `(%task-state-set! task 'terminated)` および `(%task-reductions-set! task 0)` が実行される。
3. `synapse-cleanup-task-resources!` が `(and (eq? (task-state task) 'terminated) (<= (task-reductions task) 0))` を評価し、タスクがまだ境界内で実行中であるにもかかわらず「停止済み」と誤判定。
4. 稼働中タスク `T` の Ephemeral Arena が先行して `arena-reset!` または `arena-secure-reset!` される。
5. タスク `T` が Safepoint に到達するまでの間、リセット済みの Arena メモリ領域にアクセスし、Use-After-Free (CWE-416) やデータ破損が発生する。

### 再現環境 / Environment
- OS / Architecture: Linux x86-64 (Multi-threaded & Preemptive Synapse Concurrency Runtime)
- 関連モジュール:
  - `ulisp/runtime/concurrency/channel.scm`
  - `ulisp/runtime/concurrency/panic.scm`
  - `ulisp/runtime/concurrency/boundary.scm`
  - `ulisp/runtime/concurrency/epoch.scm`
  - `ulisp/tests/test_let_it_crash.scm`
- 関連 Issue: #723, #724, #741, #744

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [`ulisp/runtime/concurrency/channel.scm`](../../ulisp/runtime/concurrency/channel.scm):
  - `<task-context>` にタスク境界実行状態を追跡するアトミックボックス（`executing-box`）およびアクセサ（`task-executing?`, `task-executing-set!`）を追加。
  - `case-lambda` のスタックフレーム深さ安全化のため `%create-task-context-default` ヘルパーを導入。
- [x] [`ulisp/runtime/concurrency/panic.scm`](../../ulisp/runtime/concurrency/panic.scm):
  - `%panic-with-synapse-task-boundary` のプロローグで `task-executing-set! #t`、エピローグ（巻き戻し完了後）で `task-executing-set! #f` を設定。
  - `synapse-cleanup-task-resources!` における `reductions <= 0` 直前代入による誤判定を排除。境界実行中のタスクに対しては Arena 即時リセットを抑止し、タスク自身が境界を完全脱出したエピローグ（`%reclaim-terminated-task-arena!`）に委ねる。
  - 境界外にあるタスク（未実行または停止確定済み）についてのみ、安全な Arena 即時リセットを許可。
- [x] [`ulisp/runtime/concurrency/epoch.scm`](../../ulisp/runtime/concurrency/epoch.scm):
  - `abort-task!` において、タスクが境界実行中である場合は即時 `arena-reset!` を行わず、Safepoint 脱出後の境界エピローグで回収させる安全ガードを導入。
- [x] [`tests/concurrency/test_let_it_crash.scm`](../../tests/concurrency/test_let_it_crash.scm):
  - 境界実行中タスクへの外部終了要求時に Arena が先行破壊されないこと、および境界脱出後に確実に解放されることを検証するテストケース（Group 11: 14項目）を追加。

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
1. **停止判定と終了フラグ設定の循環依存**:
   `synapse-cleanup-task-resources!` は終了処理の中で `task-handle-termination!` を呼び出しており、その中で `task-state = 'terminated` と `reductions = 0` が無条件に書き込まれる。その直後に同一関数内で `(and (eq? (task-state task) 'terminated) (<= (task-reductions task) 0))` を判定しているため、タスクが CPU 上で実行中であるかどうかにかかわらず**常に真**となり、判定としての意味を失っていた。
2. **境界実行状態（In-Boundary Execution State）の追跡欠如**:
   タスクが現在 `with-synapse-task-boundary` の内側で実行中（スタックフレームが存在し Arena を参照可能）であるか、それとも境界を脱出して完全に停止した（スタック巻き戻し完了）かを判別するアトミックなステートが存在しなかった。
3. **早すぎるクリーンアップ（Premature Cleanup）**:
   自身がパニックした場合でも、脱出用コンティニュエーションやハンドラチェーンの復旧処理が完了する前に Arena をリセットすると、脱出処理途中でメモリ破壊が起きる。境界脱出確定時（エピローグ）こそが Arena を安全に解放できる唯一のポイントである。

---

## 4. 恒久対策 / Permanent Fix
1. **境界実行状態の追跡 (In-Flight Execution Tracking)**:
   `<task-context>` にアトミックな `executing-box` を新設。
   - `with-synapse-task-boundary` 開始時: `(task-executing-set! task #t)`
   - `with-synapse-task-boundary` 終了時（ガード脱出後、ハンドラ復帰後）: `(task-executing-set! task #f)`
2. **Arena リセットの完全停止後実行保証 (Post-Stop Arena Reclamation)**:
   - `synapse-cleanup-task-resources!` では：
     - もし `(task-executing? task)` が真であれば、タスクは現在境界内を実行中であるため、`task-state = 'terminated` と reductions=0 を設定して Safepoint での脱出をトリガーするにとどめ、**Arena リセットを一切行わない**。
     - タスクが Safepoint で境界を脱出し、スタック巻き戻しとエピローグが完了した段階で、境界側エピローグの `%reclaim-terminated-task-arena!` がアトミックに Arena をリセットする。
     - もし `(task-executing? task)` が偽（タスクは境界外にあり停止確定済み）であれば、その場で安全に Arena をリセットする。
3. **`reductions <= 0` 判定の廃止**:
   直前代入される reductions に頼る判定コードを全廃し、`(and (not (task-executing? task)) (eq? (task-state task) 'terminated))` を正式な停止確認条件とする。

---

## 5. 実装手順 / Implementation Steps

### Step 1: ブランチ作成
```bash
git checkout -b fix/745-verify-task-stop-before-arena-reset
```

### Step 2: `<task-context>` に実行中追跡ボックスを追加 (`ulisp/runtime/concurrency/channel.scm`)
- `<task-context>` のレコードフィールドに `executing-box` を追加。
- コンストラクタ `%make-task-context` および初期化ヘルパーで初期値 `(make-atomic-box #f)` を設定。
- アクセサ `(task-executing? task)` および `(task-executing-set! task bool)` を定義。

### Step 3: 境界プロローグ・エピローグでの実行状態更新 (`ulisp/runtime/concurrency/panic.scm`)
- `%panic-with-synapse-task-boundary` において、実行開始時に `(task-executing-set! task #t)` を設定。
- 例外ハンドラおよび正常終了後、`prev-task` / `prev-k` / `prev-hc` を復元した直後に `(task-executing-set! task #f)` をアトミックに設定。
- その直後に `(%reclaim-terminated-task-arena! task secure-scrub?)` を実行することで、境界完全脱出後の安全なリセットを保証。

### Step 4: 外部クリーンアップ時の早すぎる Arena 解放の抑止 (`ulisp/runtime/concurrency/panic.scm`, `epoch.scm`)
- `synapse-cleanup-task-resources!` 内の Arena リセット条件を以下に変更：
  - タスクが実行中でない `(not (task-executing? task))` かつ `terminated` である場合のみ即時リセット。
  - 実行中であればリセットをスキップし、境界脱出時エピローグに委ねる。
- `epoch.scm` の `abort-task!` においても同様に、実行中タスクに対する即時 `arena-reset!` を防止。

### Step 5: テストケース実装 (`tests/concurrency/test_let_it_crash.scm`)
- Group 11: タスク完全停止前の Arena リセット抑止および完全停止後の安全なリセット検証（14項目）。
  - 実行中タスクに対して `synapse-cleanup-task-resources!` を発行しても、実行中は Arena のオフセットやデータが保持されていることの確認。
  - 境界を脱出した時点で `(%reclaim-terminated-task-arena!)` により Arena が初期化されることの確認。
  - `(task-executing? task)` のプロローグ/エピローグでの遷移確認。

### Step 6: 品質ゲート一括検証とコミット
- `make -C ulisp test_let_it_crash test_preemption test_links_monitors test_supervisor test_scheduler lint_sexpr`
- pre-commit hooks (Python & S-expression) の通過確認。
- `docs/issues/745-verify-task-stop-before-arena-reset.md` を `docs/issues/closed/` へ移動。

---

## 6. 完了条件 / Definition of Done (DoD)
- [x] `<task-context>` に `task-executing?` / `task-executing-set!` が整備され、境界実行状態が追跡されていること
- [x] 境界実行中のタスクに対して外部からクリーンアップが要求された際、Arena が先行リセットされず保護されること
- [x] タスクが境界を完全に脱出（エピローグ完了）した段階で、安全に Arena がリセットされること
- [x] 直前代入 `reductions <= 0` に依存した誤判定が完全に排除されていること
- [x] `tests/concurrency/test_let_it_crash.scm` に新規テストケースが追加され、全テストが 100% PASS すること (113 passed, 0 failed)
- [x] `make -C ulisp test_let_it_crash test_preemption test_supervisor test_links_monitors test_scheduler lint_sexpr` がすべて PASS すること
- [x] CWE-416 (Use-After-Free) の脆弱性が解消されていること



