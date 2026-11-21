---
ID: 928
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] `musl libc` の ULisp 自前ビルドおよび Pass 144 自前 ELF リンカによる完全静的リンク移行 (ID: 928)

## 1. 概要 / Summary
外部ツールチェーン（システム `ld` およびホスト `libc`）への依存を完全に断ち切るため、ULisp C99 コンパイラ自身を用いて `musl libc`（x86-64 版 `crt1.o`, `libc.a`）を自前ビルドし（J1）、さらに Pass 144 自前 ELF リンカ（Issue #830）を用いて Lua オブジェクト群と `musl libc` を直接静的リンクし、外部ツールチェーン非依存の自己完結 `lua` バイナリを生成する（Step S7 / T16）。

---

## 2. トレーサビリティ / Traceability
- 関連設計書:
  - [DSN-33-32 §5.1, §5.2, §6.1](../designs/DSN-33-32-ulisp_lua_c_codebase_compilation_and_self_hosting_architecture.md)
  - [DSN-33-13 §2.4, §5.2](../designs/DSN-33-13-ulisp_typed_machine_lir_and_multi_target_backend_architecture.md)
- 前提基盤 Issue: #830 (ELF セクション/再配置), #838 (`%inline-asm`), #925, #926

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/backend/144_backend_x86_elf.scm](../../ulisp/backend/144_backend_x86_elf.scm) / [elf64_builder.scm](../../ulisp/backend/elf64_builder.scm) (静的アーカイブ `.a` 解析・複数 `.o` シンボル解決・静的 ELF 生成)
- [ ] `ulisp/driver/c_driver.scm` (`--linker=ulisp` モードおよび `ar`/`.a` 入力対応)
- [ ] `ulisp/tests/test_musl_and_lua_selflink.sh` (新規: musl 自前ビルド + Pass 144 静的リンク Lua E2E 検証)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/928-compile-musl-and-migrate-to-pass144-linker`

1. **J1 (musl 適応)**: `musl libc` の `syscall_arch.h` 等のインラインアセンブリ構文（GCC 拡張 ASM）を `ulisp/frontend_c/` で `%inline-asm`（#838）へ変換し、`musl` の必須 C モジュール群（`stdio`, `stdlib`, `string`, `math`, `malloc`, `unistd`, `setjmp`, `crt1`）を ULisp でコンパイルする。
2. **J2 (Pass 144 静的リンク)**: Pass 144 ELF リンカに Unix 静的アーカイブ（`ar` / `libc.a`）のオンデマンドオブジェクト取り込み・弱シンボル（`weak`）・コモンシンボル・複数セクション結合（`.init_array`, `.rodata`, `.data`, `.bss`）を実装する。
3. システム `ld` を使わずに ULisp 単体で `lua` ＋ 自前 `musl libc.a` を静的リンクし、`ldd` で動的ライブラリ依存がゼロ（`not a dynamic executable`）であることを確認の上、Lua テストを実行する。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `musl libc` の対象モジュール群が ULisp でエラーなくビルドできること。
- [ ] Pass 144 リンカのみで Lua ＋ 自前 musl の静的 ELF バイナリが生成でき、`ld` 呼び出しがゼロであること。
- [ ] 生成された完全静的 `lua` バイナリ上で Lua テストスイートが PASS すること。
