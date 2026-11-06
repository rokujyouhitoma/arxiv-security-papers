---
ID: 747
種別: Bug
優先度: Medium
ステータス: Open (In Progress)
---

# [BUG/SEC] x86-64 における TLS / worker ID に基づく安全な Worker 判別方式への刷新 (ID: 747)

## 1. 概要 / Summary
x86-64 アーキテクチャにおいて、現在どの worker スレッドで実行中かをヒープポインタ `r12` の 32MB 区画計算（アライメント）によって判別している。
このため、単一スレッドの割り当てが 32MB を超過すると隣接スレッドの領域にはみ出してヒープが破壊され、例外ハンドラ連鎖の取り違えが発生する。また、64 個目以降のスレッドは管理欄を共有してしまい競合する。さらにメインスレッドが最初のスレッド生成までに 32MB 以上を割り当てると、メインスレッドの管理欄がずれる不具合が存在する。

### 再現手順 / Steps to Reproduce
1. スレッド 0 (メインスレッド) で 32MB 以上の巨大なオブジェクトをヒープアロケートする。
2. その後スレッド 1 を生成する。
3. `r12` のベースアドレス計算が狂い、スレッド 0 とスレッド 1 のワーカーコンテキスト領域が重なりヒープ破損またはクラッシュが発生する。

### 再現環境 / Environment
- OS / Env: Linux x86-64
- File: `ulisp/runtime/concurrency/thread.s`, `ulisp/runtime/concurrency/thread.scm`, `ulisp/backend/140_backend_x86_64.scm`
- 関連 Issue: Follow-up of #719

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [`ulisp/runtime/concurrency/thread.s`](../../ulisp/runtime/concurrency/thread.s)
- [ ] [`ulisp/runtime/concurrency/thread.scm`](../../ulisp/runtime/concurrency/thread.scm)
- [ ] [`ulisp/backend/140_backend_x86_64.scm`](../../ulisp/backend/140_backend_x86_64.scm)
- [ ] [`ulisp/tests/test_multithread_scheduler.scm`](../../ulisp/tests/test_multithread_scheduler.scm)

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
スレッドの識別を「固定サイズのヒープ境界 (`r12 & ~(32MB-1)`)」という脆弱な仮定に依存していたため。ヒープサイズが制限され、かつスレッド数が 64 に固定されるなど、スケーラビリティとメモリ安全性において構造的欠陥となっていた。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**: 最大スレッド数を制限し、各スレッドのヒープアロケーション上限を強制する。
* **恒久対策 (Permanent Fix)**: `clone` システムコール実行時にスレッド固有の TLS (Thread Local Storage) バッファを渡し、`%fs:` 相対参照で Worker 構造体または Worker ID を直接参照する。さらに spawn 数上限チェックを設ける。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `fix/747-implement-tls-worker-identification-for-x86-64`

1. `ulisp/runtime/concurrency/thread.s`:
   - `clone` 呼び出し時に `CLONE_SETTLS` フラグを使用し、アーキテクチャ専用レジスタ（`fs_base`）に Worker 固有構造体のアドレスを設定。
   - Worker 判別を `%fs:0`（または `%fs:worker_id`）からの読み出しに変更し、`r12` アライメント計算を全廃。
2. `ulisp/runtime/concurrency/thread.scm`:
   - 最大 Worker スレッド数の上限チェックを実装し、定義上限を超えるスレッド生成要求を安全に拒否する。
3. `ulisp/tests/test_multithread_scheduler.scm`:
   - 32MB を超えるメモリ割り当てを行うスレッドが複数並行稼働しても、Worker 判別が狂わず正常に完走することを検証。

---

## 6. 完了条件 / Success Criteria (DoD)
- [ ] ヒープポインタ `r12` に依存した Worker 判別が全廃され、TLS (`%fs:`) 方式に置換されること
- [ ] 32MB 以上のヒープアロケーションを行っても Worker 構造体や他スレッドの領域が破壊されないこと
- [ ] スレッド生成時の上限チェックが正しく機能すること
- [ ] `ulisp/tests/test_multithread_scheduler.scm` が PASS すること

