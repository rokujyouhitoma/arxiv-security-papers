---
ID: 905
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] Implement Freestanding Demand-Paged BSS Bump Allocator and GC (ID: 905)

## 1. 概要 / Summary
[[DSN-33-07]](../designs/DSN-33-07-ulisp_zero_libc_pure_scheme_bare_metal_runtime.md) 第 4 章に基づき、外部 `malloc` や libc を介さず、Linux カーネルが自動提供するデマンドページング BSS セクション（16MB）を初期ヒープとして利用するベアメタル自立型バンプアロケータ、および Raw Syscall `sys-mmap` と連動する Zero-libc Cheney's 2-Space コピー GC を実装する。

---

## 2. トレーサビリティ / Traceability
- 関連設計書:
  - [[DSN-33-07] ULisp Zero-libc / Freestanding Pure Scheme ベアメタルランタイム包括設計書 (第4章 メモリ管理と GC)](../designs/DSN-33-07-ulisp_zero_libc_pure_scheme_bare_metal_runtime.md)
  - [[DSN-33] ULISP 包括設計仕様書 (第2.3節 黄金比 Cheney's 2-Space GC)](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/runtime/gc.scm](../../ulisp/runtime/gc.scm)
- [ ] [ulisp/backend/141_backend_x86_gc.scm](../../ulisp/backend/141_backend_x86_gc.scm)
- [ ] [ulisp/backend/elf64_builder.scm](../../ulisp/backend/elf64_builder.scm)
- [ ] [ulisp/tests/test_freestanding_gc.scm](../../ulisp/tests/test_freestanding_gc.scm)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/905-implement-freestanding-demand-paged-bss-bump-allocator-and-gc`

1. ELF の `.bss` セクションに 16MB の初期静的バッファ `__ulisp_initial_heap` を定義し、OS ロード時の物理メモリ消費ゼロ（Demand-Paged）で即座にヒープポインタを初期化。
2. ヒープ枯渇時に Linux システムコール `mmap(NULL, size, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0)` を直接呼び出す拡張アロケータを実装。
3. Cheney's 2-Space コピー GC ループを Pure Scheme アセンブリとしてコンパイルし、libc を一切介さずにポインタ反転・ルート走査を完遂。
4. 単体テスト `test_freestanding_gc.scm` を作成し、大量のペア生成下で GC が自立して回収・メモリ再利用を行うことを検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] BSS 初期ヒープおよび Raw `sys-mmap` によるゼロ・外部依存メモリアロケーションが機能すること。
- [ ] Cheney's 2-Space GC がベアメタル環境で正常に世代交代・メモリ回収を完遂すること。
- [ ] `make -C ulisp test_freestanding_gc` が PASS すること。
- [ ] `make py_compile && make static_analysis` が PASS すること。
