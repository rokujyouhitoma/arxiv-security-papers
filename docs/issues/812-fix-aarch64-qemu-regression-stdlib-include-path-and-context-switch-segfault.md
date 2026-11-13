---
ID: 812
種別: Bug
優先度: Medium
ステータス: Open (New)
---

# [BUG/SEC] AArch64 QEMU 回帰ターゲットにおける stdlib include パス解決失敗とコンテキストスイッチテストの SIGSEGV (ID: 812)

## 1. 概要 / Summary

Issue #809 の回帰検証中に、`main` ブランチ（変更前）でも再現する AArch64 実機（QEMU）系ターゲットの既存不具合を 2 件検出した。

1. `make -C ulisp test_aarch64_qemu` の依存ターゲット `build/ulisp_stdlib_aarch64.s` が、`cd $(ROOT_DIR)` 後に `ulisp/compiler.scm` を実行するため、`stdlib_entry.scm` 内の `(include "lib/posix.scm")` 等の相対パスが解決できず `couldn't open input file: "lib/posix.scm"` で失敗する。
2. `make -C ulisp test_context_switch_aarch64` が Group 1（`<task-stack>` 割り当て・16 バイトアライメント・カナリア）の途中で `qemu: uncaught target signal 11 (Segmentation fault)` により異常終了する。

### 再現手順 / Steps to Reproduce
1. `git checkout main && make -C ulisp compiler`
2. `make -C ulisp build/ulisp_stdlib_aarch64.s` → include パスエラー (Error 70)
3. `make -C ulisp test_context_switch_aarch64` → QEMU 上で SIGSEGV

### 再現環境 / Environment
- OS / Env: Linux x86-64 ホスト + `aarch64-linux-gnu-as/ld` + `qemu-aarch64`
- 確認日: 2026-11-13（Issue #809 作業ブランチおよび `main` の双方で同一結果）

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files

- [ulisp/Makefile](../../ulisp/Makefile)（`build/ulisp_stdlib_aarch64.s`, `test_context_switch_aarch64`, `test_aarch64_qemu`）
- [ulisp/backend/150_backend_aarch64.scm](../../ulisp/backend/150_backend_aarch64.scm)
- [ulisp/runtime/concurrency/context.scm](../../ulisp/runtime/concurrency/context.scm)
- [tests/concurrency/test_context_switch_aarch64.scm](../../tests/concurrency/test_context_switch_aarch64.scm)
- 関連: [Issue #809](closed/809-fix-safepoint-poll-lir-code-emission-and-add-aarch64-stub.md)

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis

（polish-issue フェーズで記入）

---

## 4. 実装方針 / Implementation Plan

（polish-issue フェーズで記入）

---

## 5. 完了条件 / Success Criteria (DoD)

（polish-issue フェーズで記入）
