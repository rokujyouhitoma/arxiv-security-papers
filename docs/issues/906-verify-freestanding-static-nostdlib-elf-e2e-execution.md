---
ID: 906
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] Verify Freestanding Static -nostdlib ELF E2E Execution (ID: 906)

## 1. 概要 / Summary
[[DSN-33-07]](../designs/DSN-33-07-ulisp_zero_libc_pure_scheme_bare_metal_runtime.md) 第 5 章に基づき、ULisp AOT コンパイラが `-nostdlib -static` フラグのみで出力した完全自立型静的 ELF64 バイナリの E2E 実行可能性を検証し、動的リンカや C ランタイムが存在しない Scratch コンテナ環境での動作を保証する。

---

## 2. トレーサビリティ / Traceability
- 関連設計書:
  - [[DSN-33-07] ULisp Zero-libc / Freestanding Pure Scheme ベアメタルランタイム包括設計書 (第5章 検証とテスト)](../designs/DSN-33-07-ulisp_zero_libc_pure_scheme_bare_metal_runtime.md)
  - [[DSN-33] ULISP 包括設計仕様書](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/Makefile](../../ulisp/Makefile)
- [ ] [ulisp/tests/test_freestanding_e2e.sh](../../ulisp/tests/test_freestanding_e2e.sh)
- [ ] [ulisp/backend/elf64_builder.scm](../../ulisp/backend/elf64_builder.scm)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/906-verify-freestanding-static-nostdlib-elf-e2e-execution`

1. `Makefile` に `build/ulisp-baremetal` ターゲットを追加し、`-nostdlib -static` による直接リンクを自動化。
2. `readelf -l` および `ldd` コマンドで、生成バイナリが `INTERP` ヘッダ（`ld-linux.so` 要求）および動的依存ライブラリを一切持たないことを静的に検査。
3. E2E 検証スクリプト `test_freestanding_e2e.sh` を作成し、純粋な Linux Raw Syscall のみで計算、文字列出力、メモリ確保、正常終了コード返却が行われることをテスト。
4. 全テストスイートと統合し、ベアメタルモードがリグレッションなくビルド可能であることを検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `ldd` 実行結果が「not a dynamic executable」となり、外部共有ライブラリ依存が 0 件であること。
- [ ] バイナリサイズが数十 KB 以内の超軽量 ELF64 として出力されること。
- [ ] `make -C ulisp test_freestanding_e2e` が PASS すること。
- [ ] `make py_compile && make static_analysis` が PASS すること。
