---
ID: 734
種別: Feature
優先度: Medium
ステータス: Closed
---

# [FEAT/ENH] 4種類のタスク表現の <task-context> への一元化 (ID: 734)

## 1. 概要 / Summary
従来の Synapse 並行性ランタイムでは、`<task-context>`（`channel.scm`）、`<budgeted-task>`（`preempt.scm`）、`<coroutine-context>`（`context.scm`）、および生の `procedure`（thunk）という 4 種類のタスク表現が混在し、スケジューラやプリエンプションハンドラが実行のたびに型判別・分岐を繰り返していた（設計項目 A7）。
本改修では、スケジューラが受け付ける全タスク表現を初期投入時に標準の `<task-context>` へ正規化（`%normalize-task-context`）し、実行・リダクション管理・例外境界・リンク／監視・Ephemeral Arena 管理を単一の統一タスクコンテキストに集約した。

---

## 2. トレーサビリティ / Traceability
- **DSN-37**:
  - Section 6.1: 統一タスクコンテキスト設計（Unified Task Context Architecture）
  - Section 7.1: ワークスティーリングスケジューラとプリエンプティブタスクディスパッチ
- **関連 Issue**:
  - [Issue #644: Dual-Mode Evaluation Adapter](../closed/644-concurrency-dual-mode-eval-adapter.md)
  - [Issue #668: Concurrency Let-It-Crash Semantics](../closed/668-concurrency-let-it-crash-semantics.md)
  - [Issue #732: Separate Completed and Failed Counters in Scheduler Stats](../closed/732-separate-completed-and-failed-task-counters-in-scheduler-stats.md)
  - [Issue #733: Implement Lock-Free Task Table](../closed/733-implement-lock-free-task-table-for-tid-lookup.md)

---

## 3. セキュリティ考慮事項・脅威分析 / Security & Threat Analysis
- **CWE-843 (Type Confusion / Inconsistent State Representation)**:
  - スケジューラキューに異なるデータ構造（ベクタ、クロージャ、レコード型）が混在すると、アクセサ呼び出し（`task-id`, `task-reductions` 等）で想定外の型例外やポインタ不正参照が発生する。
  - **対策**: `scheduler-spawn!` のエントリポイントで `%normalize-task-context` を適用し、キューに投入されるすべての要素を厳格に `<task-context>` インスタンスへ昇格・統一する。
- **CWE-400 (Uncontrolled Resource Consumption / Missing Safepoint Accounting)**:
  - 生の thunk や古いコルーチン表現がスケジューラで実行された場合、リダクションカウンタのデクリメントが行われず、CPU ループによる協調的プリエンプション不能に陥る。
  - **対策**: すべての正規化 `<task-context>` にデフォルトリダクション予算（50 削減単位）を割り当て、セーフポイント判定とアリーナ破棄を保証する。

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [preempt.scm](../../ulisp/runtime/concurrency/preempt.scm): `<task-context>` に対応したポリモーフィックアクセサ（`task-id`, `task-target-obj`, `task-exhaustion-count`, `task-consume-reductions!`, `task-replenish!`, `scheduler-yield!`, `budgeted-task-stats`）の統合
- [x] [scheduler.scm](../../ulisp/runtime/concurrency/scheduler.scm): `%normalize-task-context` 実装、`scheduler-execute-task!` の単一パス一本化
- [x] [test_scheduler.scm](../../tests/concurrency/test_scheduler.scm): 統一タスクコンテキストでのスケジューリング検証
- [x] [test_preemption.scm](../../tests/concurrency/test_preemption.scm): プリエンプション動作の整合性検証
- [x] [test_supervisor.scm](../../tests/concurrency/test_supervisor.scm): Supervisor 子タスク実行の結合検証

---

## 5. 根本原因分析 (RCA) / Root Cause Analysis
- プロジェクト初期の Phase 1〜Phase 5 でタスク機構が段階的（コルーチン → プリエンプティブタスク → アリーナ付きタスク）に追加された結果、各フェーズで個別の構造体が定義され、スケジューラ側に対症療法的な型分岐コードが累積していた。

---

## 6. 実装方針と恒久対策 / Implementation Plan
Target Branch: `refactor/734-unify-task-context-representation`

1. `preempt.scm` のリダクション操作ルーチンを拡張し、`<budgeted-task>` と `<task-context>` の双方を透過的に処理可能とする安全アクセサ（`%budgeted-task-id-safe`, `%budgeted-task-reductions-safe` 等）を配置。
2. `scheduler.scm` に `%normalize-task-context` を実装:
   - `<task-context>`: そのまま返却。
   - `<budgeted-task>`: 内部の target thunk / reductions を引き継ぎ `<task-context>` を生成。
   - `procedure?` (thunk): デフォルト予算（50 reductions）の `<task-context>` を生成。
3. `scheduler-execute-task!` の実装を `<task-context>` 実行フローに一本化。
4. 既存テストコード（`make-budgeted-task` 等）の互換性を完全維持。

---

## 7. 完了条件 / Success Criteria (DoD)
- [x] スケジューラ・プリエンプション・チャネル・Supervisor で扱うタスク表現が `<task-context>` に一元化されていること。
- [x] `make -C ulisp test_scheduler` (164 passed)、`test_preemption` (82 passed)、`test_supervisor` (61 passed) が 100% PASS すること。
- [x] `test_concurrency_ci` (13,600 assertions) において 0 failure を達成すること。

