---
ID: 692
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT] Synapse 並行性ランタイム向け AArch64 ネイティブコンテキストスイッチ (context_aarch64.s) の実装 (ID: 692)

## 1. 概要 / Summary
現在 x86-64 System V AMD64 ABI に特化している `ulisp/runtime/concurrency/context.s`（`swap_context`）を、ARM64 AAPCS64 呼出規約に完全準拠した `ulisp/runtime/concurrency/context_aarch64.s` として新設・実装する。
Callee-saved レジスタ群（`x19`〜`x28`, `x29/fp`, `x30/lr`, `sp`）の退避・復元、16 バイト境界スタックアライメント保証、およびタスクトランポリンを整備し、コルーチンスイッチが AArch64 QEMU 上で安全に機能することを検証する。

---

## 2. トレーサビリティ / Traceability
- **DSN-37**: §5, §7.3 (Native Context Switch Architecture)
- **関連 Issue**: #634 (Native Context Switch), #675 (Native Worker Pool), #691 (AArch64 AOT Verification)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/runtime/concurrency/context_aarch64.s](../../ulisp/runtime/concurrency/context_aarch64.s): AAPCS64 準拠ネイティブコンテキストスイッチ
- [ ] [ulisp/runtime/concurrency/context.scm](../../ulisp/runtime/concurrency/context.scm): アーキテクチャに応じたトランポリン・スイッチルーチンのバインディング
- [ ] [ulisp/tests/test_context_switch_aarch64.scm](../../ulisp/tests/test_context_switch_aarch64.scm): AArch64 コルーチンスイッチ単体テスト

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/692-implement-aarch64-native-context-switch`

1. AAPCS64 準拠 `swap_context(old_sp_ptr, new_sp)` の実装：
   - 引数: `x0` = `old_sp_ptr`, `x1` = `new_sp`
   - 退避: `x19`〜`x28`, `x29` (FP), `x30` (LR) をスタック（16バイト整列）へ `stp` 命令等でプッシュ。
   - スタックポインタ更新: `mov x2, sp; str x2, [x0]; mov sp, x1`
   - 復元: 新スタックから `ldp` 命令等で Callee-saved レジスタを復元し、`ret`。
2. タスク起動トランポリン（`ulisp_task_entry_trampoline`）の実装（ヒープフロントポインタ `x19` / 旧 `r12` の初期化とアライメント維持）。
3. `qemu-aarch64` 上で複数のコルーチン間でタスク切り替えを反復実行するストレステスト。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `context_aarch64.s` が GNU as (aarch64) で正常にアセンブルできること。
- [ ] 2 つ以上の独立タスク間での `swap_context` による交互実行・値受け渡しが QEMU 上で正常に完了すること。
- [ ] SP Alignment Fault やレジスタ破壊によるセグメンテーション違反が 0 件であること。
