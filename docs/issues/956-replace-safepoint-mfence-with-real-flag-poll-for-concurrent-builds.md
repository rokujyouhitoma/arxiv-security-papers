---
ID: 956
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] 並行処理ビルド向け safepoint の `mfence` 単体展開を実フラグ poll（`cmp` + `jne slow`）へ置換 (ID: 956)

## 1. 概要 / Summary

`129_lir_primitives.scm` L37-39 と `131_lower_managed_dialect.scm` L72-73 は safepoint poll を `mfence` 1 命令に展開しており、プリエンプションフラグも予算カウンタも見ていないため、インライン poll としては機能していない（1 回数十サイクルのコストのみ発生）。

#809 は CWE-662（メモリ可視性）を理由に `mfence` / `dmb ish` を DoD としていたが、x86-64 は TSO のためフラグ読み出しのみの poll にフェンスは不要。AArch64 は `ldar` 等の acquire load で代替できる。#809 の DoD を改訂し、`runtime/concurrency/preempt.scm` の `%synapse-safepoint-poll!` を slow path として呼ぶ形にする。

- 計測基準 (2026-11-25, Linux x86-64, `main` 3f838e355): `ulisp-boot` 13MB / `.text` 8.86MB / `.symtab`+`.strtab` 2.29MB / `mfence` 3,915 / `seto` 3,763 / `nop` 116,321 命令 615KB / `[rsp]` mov 書込 253,768・読出 262,656 / 7 バイト `mov r64, imm32` 158,179。`ulisp-cc` 16MB / `.text` 10.95MB / `.symtab`+`.strtab` 3.16MB / `mfence` 3,915 / `seto` 5,042。

---

## 2. トレーサビリティ / Traceability

- 関連資料:
  - ULisp 速度・サイズ監査（`ulisp-boot` 逆アセンブル実測, 2026-11-25）
  - [Issue #945](945-profile-lua-547-c99-build-phase-breakdown-on-linux.md)（Lua 5.4.7 ビルドプロファイル・計測基盤を共有）
  - [Issue #809](closed/809-fix-safepoint-poll-lir-code-emission-and-add-aarch64-stub.md)
  - [Issue #808](closed/808-add-hardware-safepoint-preemption-tests-and-clean-makefile-disables.md)
  - [Issue #951](closed/951-disable-safepoint-injection-in-single-threaded-compiler-modules.md)（前提）

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [129_lir_primitives.scm](../../ulisp/lir/129_lir_primitives.scm) (L37-39)
- [ ] [131_lower_managed_dialect.scm](../../ulisp/lir/131_lower_managed_dialect.scm) (L72-73)
- [ ] [preempt.scm](../../ulisp/runtime/concurrency/preempt.scm) (フラグ / 予算カウンタ, L275-283)
- [ ] [140_backend_x86_64.scm](../../ulisp/backend/140_backend_x86_64.scm)
- [ ] [150_backend_aarch64.scm](../../ulisp/backend/150_backend_aarch64.scm)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `perf/956-real-safepoint-flag-poll`

1. グローバル（またはスレッドローカル）のプリエンプション要求フラグを定義する。
2. poll を `cmp byte ptr [flag], 0; jne .safepoint_slow`（AArch64: `ldarb` + `cbnz`）に展開し、slow path で `%synapse-safepoint-poll!` を呼ぶ。
3. #951 から移管: poll 直後の `(%mov %rax (repr-encode-void))` を、結果が使われない注入位置では出さない（現状 `rule-lir-dead-reg-overwrite-elim` で消えずに残るのは 1,032 箇所）。
4. 代替案として予算カウンタ `dec` + `jz` 方式を比較評価する。
5. 詳細手順は `polish-issue` にて精緻化する。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `test_preemption` 等（#808）で実際にタスク切替が発生することを確認
- [ ] safepoint 有効ビルドのベンチで `mfence` 版より高速
- [ ] `make format` / `make static_analysis` / `make test`（または `make check`）が全 PASS
- [ ] `make -C ulisp bootstrap` で stage2 → stage3 の自己コンパイル不動点（SHA-256 一致）を維持
- [ ] 施策前後の計測（自己コンパイル時間中央値 5 回・ELF/`.text` サイズ・`objdump` 命令数）を Issue に記録
- [ ] `verify-quality-gates` 全 PASS（相対リンクのみ・絶対パス 0 件）
