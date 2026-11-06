---
ID: 748
種別: Feature
優先度: Medium
ステータス: Open (In Progress)
---

# [FEAT/ENH] AArch64 における Worker メモリ領域の個別分離とマルチスレッド基盤整備 (ID: 748)

## 1. 概要 / Summary
AArch64 アーキテクチャにおいて、Worker 管理領域の拡張は行われたものの、現状はすべてのコンテキストが単一の「欄 0 (Worker 0)」のみを使用している。
AArch64 上で本格的なマルチスレッド Worker を導入する前に、x86-64 と同様に各 Worker ごとのコンテキスト・ハンドラ領域を独立して安全に分離できるように設計・実装する。

---

## 2. トレーサビリティ / Traceability
- 関連 Issue: Follow-up of #719, #689
- 関連資料: AArch64 ABI 仕様、Synapse Concurrency Runtime AArch64 設計書

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [`ulisp/backend/150_backend_aarch64.scm`](../../ulisp/backend/150_backend_aarch64.scm)
- [ ] [`ulisp/runtime/concurrency/context.s`](../../ulisp/runtime/concurrency/context.s)
- [ ] [`ulisp/tests/test_backend_aarch64.scm`](../../ulisp/tests/test_backend_aarch64.scm)
- [ ] [`ulisp/tests/test_aarch64_qemu_smoke.scm`](../../ulisp/tests/test_aarch64_qemu_smoke.scm)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/748-isolate-worker-memory-areas-on-aarch64`

1. `ulisp/backend/150_backend_aarch64.scm`:
   - AArch64 のスレッドポインタレジスタ (`TPIDR_EL0`) を活用し、Worker ごとのローカル領域ポインタを保持する。
2. `ulisp/runtime/concurrency/`:
   - 欄 0 固定のハードコーディングを廃止し、AArch64 においても動的に Worker ID またはスレッドローカル領域を解決するアセンブリコードを整備。
3. `ulisp/tests/`:
   - QEMU AArch64 環境下で複数 Worker 領域が正しく分離され、各 Worker が個別のハンドラ連鎖およびコンテキストを保持できることを検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] AArch64 において 欄 0 への固定依存が解消されること
- [ ] `TPIDR_EL0` 等を利用した Worker メモリ領域の分離機構が実装されること
- [ ] QEMU AArch64 回帰テストスイートで正常動作が確認できること

