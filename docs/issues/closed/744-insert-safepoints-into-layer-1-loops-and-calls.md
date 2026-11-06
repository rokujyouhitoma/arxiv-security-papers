---
ID: 744
種別: Feature / Architecture
優先度: High (P1)
ステータス: Closed (Completed)
---

# [FEAT/ENH] Layer 1 (R7RS) ループおよび関数呼び出しへの強制終了 Safepoint 自動挿入 (ID: 744)

## 1. 概要 / Summary
タスクの中断、協調的プリエンプション、および Link による強制終了 (`task-kill!` / `brutal_kill`) を可能にするための状態確認 Safepoint が、現状 ASC カーネル（`%asc-kernel` 低レベルプリミティブ構文）にしか挿入されない実装となっていた。

このため、標準的な Scheme (R7RS Layer 1) で書かれた純粋な計算ループ（`named let`）や再帰関数呼び出し（`define`, `lambda`）を行うタスクは、外部から `kill` シグナルを受け取っても実行中に Safepoint を一切通過せず、停止要求を検知できずに CPU を占有して走り続けてしまう（Unkillable Task による DoS, CWE-400）。

本改修では、コンパイラパス `pass_inject_safepoints.scm` を拡張し、ASC カーネル構文に限定せず通常の R7RS トップレベル関数、ラムダプロローグ、およびループバックエッジに対しても自動的に `%synapse-safepoint-poll!` を挿入するアーキテクチャを確立した。あわせてランタイム側で Worker TLS の現行タスクコンテキスト (`current-synapse-task`) と直結したポーリング関数を実装し、純粋な R7RS コードで記述されたタスクであっても外部からの強制終了シグナルによって有界時間内に確実に停止・脱出できるようにした。

---

### 再現手順 / Steps to Reproduce
1. 通常の R7RS 構文で書かれた純粋なループタスク `(let loop () (loop))` をタスク A として起動する（`%asc-kernel` 構文を用いない）。
2. 別タスクまたはテストコードからタスク A に対し `task-handle-termination!` または `task-link!` 経由で強制終了（`'link-killed`）を発行し、タスク A の状態を `'terminated` に更新する。
3. タスク A はコンパイル時に Safepoint が挿入されていないため、シグナルを検知できず無限ループを継続し、スケジューラやスレッドをブロックし続ける。

---

### 再現環境 / Environment
- OS / Arch: Linux (x86-64 / aarch64), Synapse Concurrency Runtime
- 関連コンポーネント:
  - `ulisp/lib/ulisp/concurrency/passes/pass_inject_safepoints.scm`
  - `ulisp/runtime/concurrency/preempt.scm`
  - `ulisp/runtime/concurrency/channel.scm`
  - `tests/concurrency/test_pass_inject_safepoints.scm`
  - `tests/concurrency/test_preemption.scm`
- 関連 Issue: #723, #740, #741, #743

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [`ulisp/lib/ulisp/concurrency/passes/pass_inject_safepoints.scm`](../../ulisp/lib/ulisp/concurrency/passes/pass_inject_safepoints.scm): `inject-safepoints-form` を導入し R7RS Layer 1 の `define`, `lambda`, `named let` 全体に Safepoint 注入を適用
- [x] [`ulisp/runtime/concurrency/channel.scm`](../../ulisp/runtime/concurrency/channel.scm): グローバルフォールバックポーリング関数の定義
- [x] [`ulisp/runtime/concurrency/preempt.scm`](../../ulisp/runtime/concurrency/preempt.scm): 無引数の `%synapse-safepoint-poll!` / `%safepoint-poll!` を実装し、`current-synapse-task` の reductions 減算・強制終了脱出と接続
- [x] [`tests/concurrency/test_pass_inject_safepoints.scm`](../../tests/concurrency/test_pass_inject_safepoints.scm): R7RS Layer 1 構文への Safepoint 注入検証テストへの刷新・拡充 (29 passed, 0 failed)
- [x] [`tests/concurrency/test_preemption.scm`](../../tests/concurrency/test_preemption.scm): 手動 Safepoint を持たない純粋 R7RS ループタスクの強制終了・即時停止検証 (Group 9) の新設 (88 passed, 0 failed)

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
1. **Pass エントリポイントの過剰フィルタリング**:
   `ulisp/lib/ulisp/concurrency/passes/pass_inject_safepoints.scm` の `inject-safepoints-pass` が:
   ```scheme
   (define (inject-safepoints-pass forms)
     (map (lambda (form)
            (if (asc-kernel-form? form)
                (inject-safepoints-kernel form)
                form))
          forms))
   ```
   と実装されており、`%asc-kernel` 以外のフォームを無条件に素通りさせていた。
2. **ランタイム無引数ポーリング API の欠落**:
   AST に挿入される `(%synapse-safepoint-poll!)` は引数を取らないが、`preempt.scm` には `(check-safepoint! btask)` など明示的タスク引数を要求する API しか存在せず、Worker TLS (`current-synapse-task`) から現行タスクを解決するグルー関数が未定義であった。

---

## 4. セキュリティ・脅威分析 (Threat Modeling & Mitigation)
- **CWE-400 (Uncontrolled Resource Consumption / Unkillable Task DoS)**:
  - *脅威*: 悪意あるコードまたはバグを含む無限ループタスクが外部からの kill 命令を無視して CPU を恒久占有し、スケジューラ全体をスタベーションに陥れる。
  - *対策*: コンパイラレベルですべてのループバックエッジおよび関数プロローグに Safepoint を不可避的に挿入し、実行コンテキストが有界ステップ内（最大 1 ループ周期）で必ずシグナル状態を確認し脱出するようにした。
- **CWE-843 (Type Confusion)**:
  - *脅威*: スタンドアロン実行時やタスク境界外で `%synapse-safepoint-poll!` が呼ばれた際に、`(current-synapse-task)` が `#f` を返してクラッシュする危険。
  - *対策*: `(current-synapse-task)` が `#f` または非タスクの場合は安全に no-op (`#t`) を返す型安全ガードを実装。

---

## 5. 恒久対策と実装内容 / Implementation Details
Target Branch: `feat/744-insert-safepoints-into-layer-1-loops-and-calls`

### 5.1 コンパイラパスの拡張 (`pass_inject_safepoints.scm`)
1. **`inject-safepoints-form` の新設**:
   - `%asc-kernel`: 既存の `inject-safepoints-kernel` を実行。
   - `(define (name . args) . body)`: 関数プロローグに `(%synapse-safepoint-poll!)` を挿入し、本体内のループ・ラムダを再帰変換。
   - `(define name expr)`: 式 `expr` を再帰変換。
   - `(begin . forms)`: 各フォームを再帰変換。
   - その他の式: `inject-safepoints-expr` で変換。
2. **`inject-safepoints-pass` の更新**:
   - `(map inject-safepoints-form forms)` に変更し、Layer 1 コード全体へ Safepoint 注入を解放。

### 5.2 ランタイムポーリング関数の実装 (`preempt.scm`)
1. **`%synapse-safepoint-poll!` の実装**:
   ```scheme
   (define (%synapse-safepoint-poll!)
     (let ((cur (current-synapse-task)))
       (if (and cur (or (budgeted-task? cur) (task-context? cur)))
           (check-safepoint! cur)
           #t)))
   (define (%safepoint-poll!)
     (%synapse-safepoint-poll!))
   ```
2. **強制終了時の脱出パス保証**:
   - `check-safepoint!` において、タスク状態が `'terminated` の場合、`task-escape-continuation` を呼び出して直ちに境界外へ脱出。

### 5.3 テストコードの改修と新設
1. **`tests/concurrency/test_pass_inject_safepoints.scm`**:
   - Group 5 を「Layer 1 (R7RS) Functions & Loops Safepoint Injection」に改修。
   - 通常の `(define (f x) ...)` や `(let loop () ...)` に自動的に Safepoint が注入されることを検証 (29 passed, 0 failed)。
2. **`tests/concurrency/test_preemption.scm`**:
   - Group 9（Layer 1 Loop Safepoint Exit）を新設。
   - 手動の `check-safepoint!` を一切書かない純粋な Scheme コードのループタスクをリンクし、親タスクのクラッシュによって確実に停止・脱出することを実証 (88 passed, 0 failed)。

---

## 6. 完了条件 (DoD) / Success Criteria
- [x] コンパイラパス `pass_inject_safepoints.scm` が Layer 1 (R7RS) の関数およびループ構文に対して自動的に Safepoint を挿入すること
- [x] ランタイムにおいて引数なしの `%synapse-safepoint-poll!` が提供され、`current-synapse-task` の状態確認・脱出が機能すること
- [x] ASC カーネル API を呼ばない純粋 R7RS ループタスクが、外部 kill / link 終了シグナルで確実に停止すること
- [x] `make -C ulisp test_pass_inject_safepoints` が全件 PASS すること (29 passed, 0 failed)
- [x] `make -C ulisp test_preemption` が Group 9 を含め全件 PASS すること (88 passed, 0 failed)
- [x] 既存の並行性テストスイート (`test_links_monitors`, `test_supervisor`, `test_scheduler`, `test_let_it_crash`) にリグレッションがないこと (全テスト 100% PASS)
- [x] `make lint_sexpr` (171 files) および Pre-commit 静的解析（Radon, Xenon, Mypy strict）が 100% PASS すること
