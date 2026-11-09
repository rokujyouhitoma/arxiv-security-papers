---
ID: 787
種別: Bug
優先度: High
ステータス: Closed
---

# [BUG/SEC] コルーチンが yield したあとの例外ハンドラ連鎖復元不具合の修正 (ID: 787)

## 1. 概要 / Summary
Synapse 並行性ランタイムにおいて、コルーチンが `yield` した後の再開（`resume`）時に例外ハンドラ連鎖（`ulisp_handler_chain`）が不正に復元される不具合を修正する。

コルーチンが自身でハンドラを持たない場合、初回の再開時に worker スタック上に作成された境界フレームのアドレスが `yield` 時にタスクコンテキスト（`[rcx - 32]`）に保存される。2回目以降の再開ではこのアドレスが残存しているためそのまま採用されるが、前回のスタックフレームは既に解放されている。そのため、2回目以降の再開で例外が発生すると解放済みフレームへジャンプ（または他ワーカーにスチールされた場合は別スレッドのスタックへジャンプ）し、スタック破壊やセグメンテーションフォールト（CWE-825 / CWE-588）を引き起こす。

### 再現手順 / Steps to Reproduce
1. コルーチン型タスクを起動し、一度 `yield` させる。
2. コルーチンを（可能であれば別の worker スレッドで）再開する。
3. 再開後のコルーチン内で例外を発生させる（例: `(car '())`）。
4. 無効化されたスタックフレームまたは別スレッドのスタックへ不正ジャンプし、ランタイムクラッシュまたはメモリ破壊が発生する。

### 再現環境 / Environment
- OS / Env: Linux x86-64 / Synapse Concurrency Runtime
- Target Files:
  - `ulisp/runtime/concurrency/context.s` (`ulisp_fn__pctasm_yield_task_excl`, `ulisp_fn__pctasm_resume_task_excl`)
  - `ulisp/runtime/concurrency/context.scm` (TCB ヘッダレイアウト & 定数)
  - `ulisp/build/test_context_switch_input.scm` (単体テスト)
  - `ulisp/build/test_multithread_scheduler_input.scm` (並行統合テスト)

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [context.s](../../ulisp/runtime/concurrency/context.s) — `resume_task` および `yield_task` のハンドラ連鎖管理アセンブリ修正
- [ ] [context.scm](../../ulisp/runtime/concurrency/context.scm) — TCB ヘッダレイアウト（境界ハンドラ退避スロット）の定義更新
- [ ] [test_context_switch_input.scm](../../ulisp/build/test_context_switch_input.scm) — yield 後例外送出の単体回帰テスト追加
- [ ] [test_multithread_scheduler_input.scm](../../ulisp/build/test_multithread_scheduler_input.scm) — マルチスレッド・ワークスチール環境下での yield 後例外回復テスト追加

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
### メカニズム詳細
1. **ハンドラフレーム構造**:
   - `140_backend_x86_64.scm` における例外ハンドラフレームは、スタック上に配置される以下の 40 バイト構造体である：
     ```text
     [frame + 0]:  直前のハンドラフレームへのポインタ (prev_handler)
     [frame + 8]:  ハンドラ有効スコープのスタックポインタ (rsp)
     [frame + 16]: ハンドラ有効スコープのベースポインタ (rbp)
     [frame + 24]: キャッチ節のアドレス (catch_target RIP)
     [frame + 32]: ハンドラクロージャ手続き (handler_proc)
     ```
   - `%raise` 発生時は `ulisp_handler_chain` の先頭フレームから `[frame + 8]`（`rsp`）および `[frame + 16]`（`rbp`）を復元して `[frame + 24]`（`jmp r10`）へジャンプする。

2. **境界ハンドラの生成とライフサイクル**:
   - `scheduler.scm` の `with-synapse-task-boundary` により、ワーカー側のスタック上に境界例外ハンドラフレームが push される。
   - `ulisp_fn__pctasm_resume_task_excl`（行 285-293）呼び出し時、ワーカーの `ulisp_handler_chain[worker]` はこの境界フレームを指している。
   - 初回起動時、タスクの `task_handler_chain`（`[rdi - 32]`）は `0` であるため、ワーカーの境界フレームがそのままマイクロスタック実行中も有効となる。

3. **yield 時の不正保存**:
   - `ulisp_fn__pctasm_yield_task_excl`（行 338-340）にて：
     ```x86asm
     lea r9, [rip + ulisp_handler_chain]
     mov rax, [r9 + r8*8]
     mov [rcx - 32], rax
     ```
     コルーチンが自身でハンドラを設定していない場合、ワーカーのスタック上にある境界フレームのアドレスが `[rcx - 32]` に保存される。
   - `yield` が完了してワーカー側へ戻ると、`resume_task` のエピローグおよび `with-synapse-task-boundary` の終了により、ワーカースタック上の境界フレームは巻き戻され解放される。

4. **2回目以降の resume におけるダングリング参照**:
   - 再度 `resume_task` が呼ばれると、`[rdi - 32]` は前回の解放済みスタックアドレスが入っている。
   - `test rax, rax / jz ... / mov [r9], rax` により、解放済みのスタックポインタが `ulisp_handler_chain` にセットされる。
   - 別のワーカーに盗まれた場合は別スレッドのスタックアドレスがセットされる。
   - この状態でコルーチンが `(car '())` 等で例外を送出すると、無効化されたスタック領域のデータを基に `mov rsp, [rbx + 8]` してジャンプするため、クラッシュまたは未定義動作（CWE-825）となる。

---

## 4. セキュリティ・整合性設計 (Security & Integrity Architecture)
### 脅威分析
- **CWE-825 (Expired Pointer Dereference)**: 解放済みスタックフレームへのジャンプによる任意コード実行・クラッシュ。
- **CWE-588 (Attempt to Access Child of Non-structure Type)**: 破壊されたスタック上の値をオブジェクトとして解釈することによる型混乱。
- **CWE-362 (Race Condition / Cross-Thread Stack Smashing)**: ワークスチールにより他ワーカーのスタックポインタを上書きし、他スレッドの正常なスタックフレームを破壊する。

### 防御策 (Mitigation)
- **境界アイデンティティの分離**: タスクスタック（マイクロスタック）内のフレームと、ホストワーカー（OSスレッド）スタック内のフレームを明確に分離する。
- **タスクローカルハンドラ連鎖の厳格な独立**: タスクの TCB ヘッダに「現在のワーカー境界ハンドラ（`boundary_handler_slot`）」を記録する。
- `yield` 時に現在の `ulisp_handler_chain` が `boundary_handler` と一致していれば、タスク固有のハンドラは存在しないため `[rcx - 32]` には `0` を保存する。
- タスク固有のハンドラが存在する場合でも、境界ハンドラを指す最深部リンクを `0` に切り離してタスクスタック内だけで完結させ、次回 `resume` 時に新しいワーカーの境界ハンドラを末尾に再接続する。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `fix/787-coroutine-exception-handler-after-yield`

### Step 1: TCB ヘッダの拡張とレイアウト更新
- [context.scm](../../ulisp/runtime/concurrency/context.scm):
  - TCB ヘッダサイズ `*context-tcb-header-size*` を 64 バイトから 80 バイト（16 バイトアライメント維持、10 スロット）に更新。
  - スロット構成:
    ```text
    top - 80: stack canary (0x1337BEEFCAFE)
    top - 72: reserved / pad
    top - 64: boundary_handler_slot (新規: resume 時に呼び出し元 worker の境界フレームを記録)
    top - 56: switch_count
    top - 48: prev_task_top
    top - 40: task_value_slot
    top - 32: task_handler_chain_slot (タスクローカルなハンドラ連鎖の先頭)
    top - 24: task_state
    top - 16: task_sp_slot
    top - 8:  parent_sp_slot
    ```
  - `make-task-stack` および `setup-task-stack` で `boundary_handler_slot` (`top - 64`) を `0` で初期化。

### Step 2: `context.s` の `resume_task` 改修
- [context.s](../../ulisp/runtime/concurrency/context.s):
  - ワーカー境界ハンドラのアドレス `mov rbx, [r9]` を `[rdi - 64]` (`boundary_handler_slot`) に記録。
  - タスクローカルハンドラ `[rdi - 32]` の判定:
    - `0` の場合: ワーカーのハンドラ連鎖（境界フレーム）を変更せずそのまま維持。
    - `!= 0` の場合: タスクローカル連鎖を辿り、末尾ノード（`prev == 0`）の `prev` ポインタに現在のワーカー境界フレームのアドレスを書き込み、`ulisp_handler_chain[worker]` に `[rdi - 32]` を設定。

### Step 3: `context.s` の `yield_task` 改修
- [context.s](../../ulisp/runtime/concurrency/context.s):
  - 現在の `ulisp_handler_chain`（`rax`）を取得。
  - `mov rdx, [rcx - 64]` (`boundary_handler_slot`) と比較:
    - `rax == rdx`（コルーチンが自身でハンドラを追加していない場合）:
      - タスク自身のハンドラは存在しないため、`mov qword ptr [rcx - 32], 0` を保存。
    - `rax != rdx`（コルーチンが自身でハンドラを追加している場合）:
      - ハンドラ連鎖を先頭からトラバースし、`prev == rdx` である末尾ノードを検出。
      - 末尾ノードの `prev` を `0` に切り離す。
      - 先頭（`rax`）を `[rcx - 32]` に保存。
  - `[rcx - 64]` (`boundary_handler_slot`) を `0` にクリア。

### Step 4: 単体回帰テストの追加
- [test_context_switch_input.scm](../../ulisp/build/test_context_switch_input.scm):
  - テスト 1: コルーチン内でハンドラを持たず、1回 `yield` した後に再開し、再開後に `(car '())` を呼ぶ。
  - 呼び出し元の `with-synapse-task-boundary` で正常に catch され、境界の戻り値として `(panic . error)` が返ることを検証。
  - テスト 2: コルーチン内で 3 回連続 `yield` した後、最終再開で例外を送出し、安全に捕捉されることを検証。

### Step 5: マルチスレッド並行結合テストの追加
- [test_multithread_scheduler_input.scm](../../ulisp/build/test_multithread_scheduler_input.scm):
  - `scheduler-run-parallel!` 上で、コルーチンが Worker 0 で起動 -> `yield` -> Worker 1 にスチールされて再開 -> `(car '())` を実行するシナリオを実行。
  - 別スレッドのスタック破壊（CWE-362）が発生せず、Worker 1 の境界で安全に panic レコードが生成・回収されることを実証。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] コルーチンが複数回 `yield` した後に例外を発生させてもスタック破壊・セグフォ・未定義ジャンプが発生しないこと。
- [x] コルーチンがハンドラを持たない場合、`yield` 時に `task_handler_chain_slot` が確実に `0` にリセットされること。
- [x] コルーチンが自身で `guard` を持つ場合、ローカルハンドラが正しく優先され、捕捉されない例外のみがホストワーカー境界へ伝播すること。
- [x] マルチワーカー環境（`scheduler-run-parallel!`）でワークスチールを伴う yield 後例外テストが 100 回連続で PASS すること。
- [x] `make test` および並行ランタイムの全回帰テストが 100% PASS すること。
