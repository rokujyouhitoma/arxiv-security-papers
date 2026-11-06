---
ID: 740
種別: Bug
優先度: High
ステータス: Closed
---

# [BUG/SEC] コルーチン型タスクの例外境界接続とハンドラ連鎖初期化 (ID: 740)

## 1. 概要 / Summary
コルーチン型タスク内で未捕捉の例外（`(car '())`、`(error ...)`、`(raise ...)` 等）が発生した際、外側の例外ハンドラ境界 (`with-synapse-task-boundary`) に到達せず、プロセス全体がクラッシュ・強制終了する。
スケジューラが `resume_task` (`ulisp_fn__pctasm_resume_task_excl`) を呼び出す際、Worker のハンドラ連鎖 (`ulisp_handler_chain[worker]`) をタスク構造体に保存された値 (`[rdi - 32]`) で置き換える。しかしタスク初期化時の値は `0` (NULL) であるため、コルーチン実行開始直後に例外ハンドラが喪失し、未捕捉例外となってプロセス全体がクラッシュする (CWE-248 / CWE-703)。

### 再現手順 / Steps to Reproduce
1. `(scheduler-spawn! sched (make-coroutine-context (lambda () (car '()))))` を実行する。
2. スケジューラが `scheduler-execute-task!` 内で `with-synapse-task-boundary` を介して `(context-resume! nxt)` を呼ぶ。
3. `context.s` の `ulisp_fn__pctasm_resume_task_excl` が実行され、`ulisp_handler_chain[worker]` に `[rdi - 32]` (値: `0`) が代入される。
4. コルーチン内で `(car '())` が評価され、`140_backend_x86_64.scm` の型チェックから `ulisp_pair_type_error` が呼ばれる。
5. `ulisp_handler_chain` が `0` (NULL) であるため、例外を捕捉できずハードウェア例外またはプロセス abort により即死する。

### 再現環境 / Environment
- OS / Env: Linux x86-64 / QEMU AArch64
- 対象ファイル:
  - [`ulisp/runtime/concurrency/context.s`](../../ulisp/runtime/concurrency/context.s)
  - [`ulisp/runtime/concurrency/context.scm`](../../ulisp/runtime/concurrency/context.scm)
  - [`ulisp/runtime/concurrency/scheduler.scm`](../../ulisp/runtime/concurrency/scheduler.scm)
  - [`ulisp/runtime/concurrency/panic.scm`](../../ulisp/runtime/concurrency/panic.scm)
  - [`ulisp/tests/test_boundary.scm`](../../ulisp/tests/test_boundary.scm)
- 関連 Issue: Follow-up of #720

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [`ulisp/runtime/concurrency/context.s`](../../ulisp/runtime/concurrency/context.s) (L232-237: ハンドラ連鎖ロード処理)
- [ ] [`ulisp/runtime/concurrency/context.scm`](../../ulisp/runtime/concurrency/context.scm) (L123: TCB ヘッダのハンドラ初期化、`make-coroutine-context`)
- [ ] [`ulisp/runtime/concurrency/scheduler.scm`](../../ulisp/runtime/concurrency/scheduler.scm) (L386-390: コルーチン再開呼び出し)
- [ ] [`ulisp/runtime/concurrency/panic.scm`](../../ulisp/runtime/concurrency/panic.scm) (タスク例外境界)
- [ ] [`ulisp/tests/test_boundary.scm`](../../ulisp/tests/test_boundary.scm) (コルーチン例外隔離テスト)
- [ ] [`ulisp/tests/test_scheduler.scm`](../../ulisp/tests/test_scheduler.scm) (スケジューラ統合テスト)

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
1. **コンテキストスイッチ時の無条件ゼロ上書き (`context.s` L236-237)**:
   ```asm
   lea r9, [rip + ulisp_handler_chain]
   lea r9, [r9 + r8*8]
   push qword ptr [r9]       # 呼出元 (with-synapse-task-boundary) のハンドラをスタック退避
   push r9
   mov rax, [rdi - 32]       # タスク固有のハンドラ退避値を取得 (初期値は 0)
   mov [r9], rax             # ハンドラ連鎖先頭を 0 (NULL) で上書き！
   ```
   `with-synapse-task-boundary` が Worker の `ulisp_handler_chain` に例外ハンドラを設定していても、`resume_task` の瞬間にタスク側退避値 (`0`) で上書きされ、コルーチン実行中のハンドラ連鎖が空になる。
2. **タスクスタック初期化時の未接続 (`context.scm` L123)**:
   `make-task-stack` において `(%context-raw-u64-set! top -32 0)` とハードコードされており、境界ハンドラが引き継がれていない。
3. **エントリ関数側の防壁不在**:
   コルーチンの `entry-fn` 実行時、コルーチンのスタックフレーム側で `with-synapse-task-boundary` が適用されていないため、コルーチン内で発生した例外がスケジューラ側の継続に巻き戻せない。

---

## 4. セキュリティ・脅威分析 (Threat Modeling & CWE)
- **CWE-248: Uncaught Exception**: コルーチン内での些細な型エラーや事前条件不整合が、プロセス全体のクラッシュに直結する。
- **CWE-703: Improper Check or Handling of Exceptional Conditions**: 堅牢な "Let It Crash"（Supervisor による局所的障害回復）を標榜しながら、コルーチン型タスクのクラッシュがシステム全体の停止を引き起こす。
- **DoS (Denial of Service)**: 攻撃者が意図的にコルーチン内で例外を起こす入力を与えることで、サービス全体をサービス不能に追い込むことが可能。

---

## 5. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**: コルーチンの `entry-fn` 定義内で、ユーザ自身が手動で最外周に `(guard (e (else (synapse-panic! e))))` を記述する。
* **恒久対策 (Permanent Fix)**:
  1. **[アセンブリ層]**: `context.s` の `resume_task` において、`[rdi - 32]` が 0（タスク固有ハンドラ未登録）である場合は親（Worker）のハンドラ連鎖をクリアせずそのまま継承する。
  2. **[Scheme 層]**: `make-coroutine-context` またはエントリトランポリンにおいて、コルーチン内部の最外周でも `with-synapse-task-boundary` を呼び出し、多重防衛（Defense in Depth）を確立する。

---

## 6. 実装方針 / Implementation Plan
Target Branch: `fix/740-fix-coroutine-task-exception-boundary`

### Step 1: `ulisp/runtime/concurrency/context.s` のハンドラ継承修正
`ulisp_fn__pctasm_resume_task_excl` において、タスクの退避ハンドラが 0 の場合は親ハンドラを維持するよう分岐を追加：
```asm
    lea r9, [rip + ulisp_handler_chain]
    lea r9, [r9 + r8*8]
    push qword ptr [r9]
    push r9
    mov rax, [rdi - 32]
    test rax, rax
    jz .L_resume_keep_handler
    mov [r9], rax
.L_resume_keep_handler:
```

### Step 2: `ulisp/runtime/concurrency/context.scm` の初期値・エントリ防壁
1. コルーチンのスタック構築時、Worker の現在ハンドラ連鎖を `top - 32` に初期値として設定できるようにヘルパーを提供。
2. `make-coroutine-context` において、与えられた `entry-fn` をラップし、コルーチンの実行コンテキスト内部でも `with-synapse-task-boundary` を通すようにガードする。

### Step 3: `ulisp/runtime/concurrency/scheduler.scm` の戻り値処理
コルーチン内で例外が発生して `with-synapse-task-boundary` が捕捉した場合、タスク状態を `'crashed` / `'terminated` に更新し、Supervisor へ `DOWN` 通知が伝播することを確認。

### Step 4: テストケースの追加と検証
`ulisp/tests/test_boundary.scm` および `test_scheduler.scm` に以下のテストを追加：
1. コルーチン内で `(car '())` を実行してもプロセスがクラッシュせず、境界で捕捉されること。
2. コルーチン内で `(error "fail")` や `(raise 'foo)` が発生した際、タスク単位で安全に終了すること。
3. コルーチンが正常終了した場合は戻り値が正常に得られること。

---

## 7. 完了条件 / Success Criteria (DoD)
- [x] コルーチン型タスク内で `(car '())`、`(error "boom")`、`(raise 'test)` が発生しても、プロセス全体がクラッシュせず安全に例外境界で捕捉されること
- [x] `context.s` において、タスクのハンドラが未登録 (`0`) の場合に親の `ulisp_handler_chain` が破壊されないこと
- [x] 捕捉された例外が `%execute-task-panic!` に送られ、タスク状態が適切に終了・遷移すること
- [x] `ulisp/tests/test_boundary.scm` および `ulisp/tests/test_scheduler.scm` にコルーチン例外テストが追加され PASS すること
- [x] `make -C ulisp test_boundary test_scheduler test_let_it_crash lint_sexpr` がすべて PASS すること
