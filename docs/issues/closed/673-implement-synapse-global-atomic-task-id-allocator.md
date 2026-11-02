---
ID: 673
種別: Feature
優先度: High
ステータス: Closed (Resolved)
---

# [FEAT/ENH] グローバルアトミック Task ID (TID) 自動採番機構の導入と手動指定衝突の防止 (ID: 673)

## 1. 概要 / Summary
現在の Synapse 並行ランタイムにおいて、タスク生成プリミティブ `make-task-context`（`channel.scm`）および `make-budgeted-task`（`preempt.scm`）は呼び出し元が手動で固定整数 ID を渡す設計となっている。
このため、複数モジュール連携時やマルチワーカー並行下でタスク生成時に ID の衝突・重複（CWE-843 / CWE-362）が発生し、将来のプロセスレジストリ（Issue #669）やリンク・モニタ機構（Issue #666）において重大な誤動作を招くリスクがある。
グローバルアトミックな Task ID 採番器（`*task-next-id*`）を導入し、引数なし `(make-task-context)` で一意な TID を自動不可分割り当てする堅牢な基盤を確立する。

---

## 2. トレーサビリティ / Traceability
- 関連設計書: [DSN-37 ホスト・カーネル分離型 階層 CSP/アクター並行処理基盤](../../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md)
- 関連 Issue:
  - [Issue #633 (第一級 P2P チャネル・TaskContext)](633-implement-synapse-first-class-p2p-channel.md)
  - [Issue #635 (M:N ワークスティーリングスケジューラ)](635-implement-synapse-work-stealing-scheduler.md)
  - [Issue #636 (リダクション方式プリエンプション)](636-implement-synapse-fuel-preemption-mechanism.md)
  - [Issue #666 (タスク間リンク・モニタ)](../666-implement-synapse-task-links-and-monitors.md)
  - [Issue #669 (プロセス名レジストリ)](../669-implement-synapse-process-registry-and-dynamic-rebinding.md)
  - [Issue #671 (コルーチン ID アトミック化)](671-fix-synapse-coroutine-id-atomic-allocation.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/runtime/concurrency/channel.scm](../../../ulisp/runtime/concurrency/channel.scm)
- [x] [ulisp/lib/ulisp/concurrency/channel.sld](../../../ulisp/lib/ulisp/concurrency/channel.sld)
- [x] [ulisp/runtime/concurrency/preempt.scm](../../../ulisp/runtime/concurrency/preempt.scm)
- [x] [ulisp/lib/ulisp/concurrency/preempt.sld](../../../ulisp/lib/ulisp/concurrency/preempt.sld)
- [x] [tests/concurrency/test_channel.scm](../../../tests/concurrency/test_channel.scm)
- [x] [tests/concurrency/test_preemption.scm](../../../tests/concurrency/test_preemption.scm)
- [x] [tests/concurrency/concurrency_harness.scm](../../../tests/concurrency/concurrency_harness.scm)

---

## 4. 根本原因分析 (RCA) & セキュリティ脅威分析
1. **根本原因**:
   初期実装時のテスト容易性を優先し、`make-task-context` に引数なし自動採番のオーバーロードが用意されず、`tid` を第1引数として必須としていた。
2. **セキュリティ脅威（STRIDE / CWE）**:
   - **CWE-843 (Type/Entity Confusion)**: 手動で `1001` などの固定値を渡した場合、別スレッドが生成したタスクと TID が衝突。リンクやモニタ通知、チャネル待機起床時に別のタスクと混同される。
   - **CWE-362 (Race Condition)**: 複数ワーカーが独自に連番をインクリメントしようとした際、非排他処理により同一 TID が生成される。
   - **CWE-400 (Uncontrolled Resource Consumption)**: 衝突した TID を基にメッセージを送信し、ゾンビタスクへキューイングされてメモリリークやデッドロックを誘発。

---

## 5. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**: 呼び出し元が慎重に手動でユニークな範囲（例: スレッド毎に 1000000 オフセット）を分割して TID を指定する。
* **恒久対策 (Permanent Fix)**:
  1. `channel.scm` 内に `*task-next-id*`（`<atomic-box>`、初期値 1）を配置。
  2. `(allocate-task-id!)` $\to$ `(atomic-fetch-add! *task-next-id* 1)` により、1命令の不可分操作でグローバル一意な TID を採番。
  3. `make-task-context` の `case-lambda` を拡張し、0引数 `()` で自動採番 TID を付与。
  4. `preempt.scm` の `make-budgeted-task` にも 1引数 `(task-obj)`、2引数 `(task-obj budget)` オーバーロードを追加し、手動 ID 指定を省略可能にする。
  5. 既存のテストコードに対する 100% 後方互換性を厳格に維持。

---

## 6. 実装方針 / Implementation Plan
Target Branch: `feat/673-global-atomic-task-id-allocator`

### Step 1: `ulisp/runtime/concurrency/channel.scm` の拡張
1. `*task-next-id*`（初期値 1）の定義。
2. 手続きの追加:
   - `(allocate-task-id!)`
   - `(task-next-id-current)`
   - `(task-reset-next-id! val)`
3. `make-task-context` の `case-lambda` オーバーロード拡張:
   - `()`: `(let ((tid (allocate-task-id!))) (%make-task-context tid 'ready ...))`
   - `(epoch)`: `(let ((tid (allocate-task-id!))) (%make-task-context tid 'ready *task-default-reductions* 0 0 0 0 4096 #f epoch #f 0 0 (make-atomic-box #f)))` ※第1引数が整数の場合は既存の `(tid)` と解釈し互換維持。

### Step 2: `ulisp/runtime/concurrency/preempt.scm` の拡張
1. `make-budgeted-task` に自動 TID 付与オーバーロードを追加：
   - `(task-obj)`: 自動 TID 割り当て + デフォルトバジェット 4096。
   - `(task-obj budget)`: 自動 TID 割り当て + 指定バジェット。
   - 既存の `(id task-obj)`、`(id task-obj budget)` も型述語判別により完全維持。

### Step 3: ライブラリ定義 (`channel.sld`, `preempt.sld`) のエクスポート更新
1. `*task-next-id*`, `allocate-task-id!`, `task-next-id-current`, `task-reset-next-id!` をエクスポート。

### Step 4: テストスイート拡充
1. `tests/concurrency/test_channel.scm`:
   - 引数なし `(make-task-context)` による自動採番・一意性アサーション。
   - `task-reset-next-id!` によるリセット動作検証。
2. `tests/concurrency/test_preemption.scm`:
   - `(make-budgeted-task thunk)` による自動 TID アサーション。
3. `tests/concurrency/concurrency_harness.scm`:
   - Jitter 注入下での並行タスク生成時の一意性検証（衝突 0 件）。

---

## 7. 完了条件 / Success Criteria (DoD)
- [x] 引数なし `(make-task-context)` で呼び出した際、グローバルに厳密に一意な TID が割り当てられること。
- [x] `task-reset-next-id!` で指定した整数値へリセットできること。
- [x] 既存の全テスト（`test_channel.scm`, `test_scheduler.scm`, `test_epoch.scm` 等）が後方互換で 100% PASS すること。
- [x] `make -C ulisp test_concurrency_harness` が 100 反復すべて 100% PASS すること。
- [x] 相対パス規則（Gate 3）の完全適合（絶対パス 0 件）。
