---
ID: 904
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] Eliminate External C Runtime and Establish Pure Scheme _start Entry (ID: 904)

## 1. 概要 / Summary
[[DSN-33-07]](../designs/DSN-33-07-ulisp_zero_libc_pure_scheme_bare_metal_runtime.md) 第 2 章・第 3 章に基づき、C 言語ランタイム（`runtime.c`）および libc への依存を完全に排除し、Pure Scheme アセンブリ `_start` エントリポイントおよび Linux x86-64 Raw Syscall（`sys-exit`, `sys-write`, `sys-read`, `sys-mmap`）直結アーキテクチャを確立する。

---

## 2. トレーサビリティ / Traceability
- 関連設計書:
  - [[DSN-33-07] ULisp Zero-libc / Freestanding Pure Scheme ベアメタルランタイム包括設計書 (第2章・第3章)](../designs/DSN-33-07-ulisp_zero_libc_pure_scheme_bare_metal_runtime.md)
  - [[DSN-33] ULISP 包括設計仕様書 (第2章 ハードウェア・ABI 整合)](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/lib/posix.scm](../../ulisp/lib/posix.scm)
- [ ] [ulisp/runtime/entry.scm](../../ulisp/runtime/entry.scm)
- [ ] [ulisp/backend/142_backend_x86_freestanding.scm](../../ulisp/backend/142_backend_x86_freestanding.scm)
- [ ] [ulisp/backend/elf64_builder.scm](../../ulisp/backend/elf64_builder.scm)
- [ ] [ulisp/tests/test_freestanding_syscall.scm](../../ulisp/tests/test_freestanding_syscall.scm)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/904-eliminate-external-c-runtime-and-establish-pure-scheme-start-entry`

1. `runtime/entry.scm` において、カーネルから直接制御を受け取る `_start` シンボル（スタックポインタ `rsp` から `argc`, `argv`, `envp` を取得）をアセンブリ直書きなしで Scheme レベルで表現。
2. `lib/posix.scm` において、`syscall` 命令（`rax, rdi, rsi, rdx, r10, r8, r9` レジスタ規約）を発行するインラインシステムコールプリミティブを完全配線。
3. `142_backend_x86_freestanding.scm` で `-nostdlib` リンク時に libc ヘッダや C スタートアップコードをリンクしないモードを有効化。
4. 単体テスト `test_freestanding_syscall.scm` を作成し、外部 C ライブラリなしで `sys-write` による標準出力と `sys-exit` による正常終了を検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `runtime.c` をリンクせずに生成された ELF バイナリが単体で起動・終了できること。
- [ ] Linux Raw Syscall 経由での文字列出力（`sys-write`）が正常に動作すること。
- [ ] `make -C ulisp test_freestanding_syscall` が PASS すること。
- [ ] `make py_compile && make static_analysis` が PASS すること。
