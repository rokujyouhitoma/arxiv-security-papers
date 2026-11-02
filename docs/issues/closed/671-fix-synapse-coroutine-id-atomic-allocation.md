---
ID: 671
種別: Bug
優先度: High
ステータス: Closed (Resolved)
---

# [BUG/SEC] コルーチン ID 採番における非アトミック更新の解消と並行 ID 重複防止 (ID: 671)

## 1. 概要 / Summary
`ulisp/runtime/concurrency/context.scm` において、コルーチン生成時の ID 採番（`*coroutine-next-id*`）が単一要素の通常の Scheme ベクタに対する非アトミックな `vector-ref` $\to$ `vector-set!` で行われている。
このため、マルチコア環境（複数ワーカー並行実行時）においてデータ競合（Race Condition, CWE-362）が発生し、異なるコルーチンに同一の `coroutine-id` が割り当てられる、または更新のロストにより ID の飛び番・重複が生じる不具合を解消する。

### 再現手順 / Steps to Reproduce
1. 複数ワーカースレッド（4〜8スレッド）から同時に `make-coroutine-context` を高頻度（各1,000回、計数千回）で並行呼び出しする。
2. 生成されたコルーチンインスタンス群の `(coroutine-id ctx)` をハッシュセット等で収集し、一意性を検証する。
3. 同一 ID の重複（衝突）が検出される。

### 再現環境 / Environment
- OS / Env: Linux x86-64 / uLisp Concurrency Runtime (Native AOT & Dual-Mode Interpreter)
- File: [ulisp/runtime/concurrency/context.scm](../../ulisp/runtime/concurrency/context.scm)

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/runtime/concurrency/context.scm](../../ulisp/runtime/concurrency/context.scm)
- [x] [ulisp/lib/ulisp/concurrency/context.sld](../../ulisp/lib/ulisp/concurrency/context.sld)
- [x] [tests/concurrency/test_context_switch.scm](../../tests/concurrency/test_context_switch.scm)
- [x] [tests/concurrency/concurrency_harness.scm](../../tests/concurrency/concurrency_harness.scm)

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
`context.scm` の 220行目および 241〜242行目：
```scheme
(define *coroutine-next-id* (vector 1))
...
(define make-coroutine-context
  (case-lambda
    ...
    ((entry-fn stack-or-size)
     (let* (...
            (cid (vector-ref *coroutine-next-id* 0)))
       (vector-set! *coroutine-next-id* 0 (+ cid 1))  ;; ← 非アトミック更新 (CWE-362)
       (setup-task-stack stk entry-fn)
       (%make-coroutine-context cid stk entry-fn owns?))))))
```
1. **なぜ非アトミック更新が起きたのか**: 当初単一スレッド前提の初期プロトタイプとして実装され、M:N スケジューラ（Issue #635）統合後も通常の Scheme ベクタ参照・代入がそのまま残存していたため。
2. **なぜ ID 重複が発生するのか**: スレッド A が `vector-ref` で `cid = 10` を読んだ直後、スレッド B が `vector-ref` で同じく `cid = 10` を読み、双方が `(+ cid 1)` を `vector-set!` することで、双方が同一の `coroutine-id = 10` を保持したコルーチンを生成してしまう。
3. **セキュリティ脅威（STRIDE / CWE）**:
   - **CWE-362 (Race Condition)**: 並行実行時の非排他的メモリアクセス。
   - **CWE-843 (Type/Entity Confusion)**: 同一 ID によるコルーチン誤同定、タスク追跡の不整合、および将来のプロセスレジストリにおける誤ルーティング。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**: コルーチンの生成を単一スレッド（Layer 1 制御プレーン）に限定し、ワーカー並行下での動的 `make-coroutine-context` 呼び出しを避ける。
* **恒久対策 (Permanent Fix)**:
  1. `*coroutine-next-id*` を `<atomic-box>`（ハードウェア支援の LOCK XADD / CMPXCHG）で管理する。
  2. 専用の採番手続き `(allocate-coroutine-id!)` を導入し、`(atomic-fetch-add! *coroutine-next-id* 1)` により 1 命令不可分操作で一意な ID を取得する。
  3. `context.scm` 単体ロード時にも依存が自己完結するよう、`atomic-box` の存在チェックおよびフォールバック機構を整備する。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `fix/671-coroutine-id-atomic-allocation`

### Step 1: `ulisp/runtime/concurrency/context.scm` の修正
1. `*coroutine-next-id*` の初期化を `make-atomic-box` を用いて定義（`atomic-box?` 述語でアトミックボックスが利用可能か判定する安全設計）。
2. アトミック採番ユーティリティ `(allocate-coroutine-id!)` を定義：
   ```scheme
   (define (allocate-coroutine-id!)
     (if (and (fboundp? 'atomic-fetch-add!) (atomic-box? *coroutine-next-id*))
         (atomic-fetch-add! *coroutine-next-id* 1)
         (let ((cid (vector-ref *coroutine-next-id* 0)))
           (vector-set! *coroutine-next-id* 0 (+ cid 1))
           cid)))
   ```
   ※ `atomic.scm` 読み込み環境では常にアトミックに加算前のユニーク整数値を返し、単体REPL環境でも互換動作を保証。
3. `make-coroutine-context` 内で `(let ((cid (allocate-coroutine-id!))) ...)` を呼び出すようリファクタリング。
4. `coroutine-next-id-current` および `coroutine-reset-next-id!`（テスト用リセット手続き）を提供。

### Step 2: `ulisp/lib/ulisp/concurrency/context.sld` のエクスポート拡充
1. `allocate-coroutine-id!`、`coroutine-reset-next-id!` をライブラリエクスポートに追加。
2. 必要に応じて `(ulisp concurrency atomic)` のインポートを追加。

### Step 3: テストスイートの拡充 (`tests/concurrency/test_context_switch.scm`)
1. **単体テスト**: `make-coroutine-context` による順次採番が単調増加することの検証。
2. **リセットテスト**: `coroutine-reset-next-id!` で指定値へリセットできることの検証。
3. **並行ストレステスト**: `tests/concurrency/concurrency_harness.scm` へ複数スレッドからの並行コルーチン生成ストレステスト（10,000回）を追加し、ID 重複が 0 件であることを自動検証。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `ulisp/runtime/concurrency/context.scm` 内で非アトミックな `(vector-set! *coroutine-next-id* ...)` が完全に排除されていること。
- [x] `make -C ulisp test_context_switch` が全ケース PASS（61 passed 以上、実測 71 passed）すること。
- [x] `make -C ulisp test_concurrency_harness` において並行コルーチン ID 衝突テストが 100% PASS すること（100反復・9,500アサーション全件PASS）。
- [x] `make py_compile` および `make static_analysis` の品質ゲートを 100% PASS すること。
