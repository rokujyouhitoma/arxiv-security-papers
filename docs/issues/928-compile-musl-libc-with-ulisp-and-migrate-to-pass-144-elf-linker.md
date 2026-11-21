---
ID: 928
種別: Feature
優先度: Medium
ステータス: Open (In Progress)
---

# [FEAT/ENH] `musl libc` の ULisp 自前ビルドおよび Pass 144 自前 ELF リンカによる完全静的リンク移行 (ID: 928)

## 1. 概要 / Summary
外部ツールチェーン（システム `ld` およびホスト `libc`）への依存を完全に断ち切るため、ULisp C99 コンパイラ自身を用いて `musl libc`（x86-64 版 `crt1.o`, `libc.a`）を自前ビルドし（裁定規準 J1）、さらに Pass 144 自前 ELF リンカ（Issue #830）を用いて Lua オブジェクト群と `musl libc` を直接静的リンクし、外部ツールチェーン非依存の自己完結静的 `lua` バイナリを生成する（Phase S7 / Task T16）。

---

## 2. トレーサビリティ / Traceability
- 関連設計書:
  - [DSN-33-32 §5.1, §5.2, §6.1](../designs/DSN-33-32-ulisp_lua_c_codebase_compilation_and_self_hosting_architecture.md)
  - [DSN-33-13 §2.4, §5.2](../designs/DSN-33-13-ulisp_typed_machine_lir_and_multi_target_backend_architecture.md)
- 前提基盤（実装済・先行）:
  - `#830`: ELF セクション/再配置（[ulisp/backend/144_backend_x86_elf.scm](../../ulisp/backend/144_backend_x86_elf.scm), [ulisp/backend/elf64_builder.scm](../../ulisp/backend/elf64_builder.scm)）
  - `#838`: `%inline-asm`（[ulisp/backend/140_backend_x86_64.scm](../../ulisp/backend/140_backend_x86_64.scm)）
  - `#925`, `#926`, `#927`
- 後続連携 Issue:
  - [[#929]](929-implement-ddc-diverse-double-compiling-determinism-verification.md) (DDC 完全静的リンク検証)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/backend/144_backend_x86_elf.scm](../../ulisp/backend/144_backend_x86_elf.scm) ＆ [ulisp/backend/elf64_builder.scm](../../ulisp/backend/elf64_builder.scm) (Unix `ar` 静的アーカイブ `.a` 解析・オンデマンド `.o` 解決・`STB_WEAK`/`SHN_COMMON`・`.init_array`/TLS/プログラムヘッダ静的 ELF 生成)
- [ ] [tools/grammars/c99.peg](../../tools/grammars/c99.peg) ＆ `ulisp/frontend_c/` (GCC 拡張 `asm`/`__asm__ __volatile__` 構文解析 ＆ `%inline-asm` Lowering)
- [ ] `ulisp/driver/c_driver.scm` (`--linker=ulisp`, `-static`, `.a` 入力対応)
- [ ] `ulisp/tests/test_musl_and_lua_selflink.sh` (新規: musl 自前ビルド + Pass 144 静的リンク Lua E2E 検証 ＆ `ldd` 動的依存 0 確認)
- [ ] [ulisp/Makefile](../../ulisp/Makefile) (`test_musl_selflink` ターゲット追加)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/928-compile-musl-and-migrate-to-pass144-linker`

### 4.1 J1: `musl libc` の ULisp 自前ビルド適応
1. **GCC 拡張インラインアセンブリ → `%inline-asm` (#838)**:
   - `musl` x86-64 版の `syscall_arch.h`・`atomic_arch.h`・`crt1.c` で使われる `asm __volatile__ (...)` 制約（`"a"`, `"D"`, `"S"`, `"d"`, `"r10"`, `"r8"`, `"r9"`, `"rcx"`, `"r11"`, `"memory"`）を `c99.peg` + `lower_to_lir.scm` で `#838` `%inline-asm` 命令へ降格。
2. **必須 C モジュールコンパイル ＆ `ar` アーカイブ**:
   - `musl` コア（`crt`, `errno`, `string`, `ctype`, `stdio`, `stdlib`, `malloc`, `math`, `unistd`, `fcntl`, `mmap`, `signal`, `time`, `exit`）をコンパイルし `libc.a` / `crt1.o` を生成。

### 4.2 J2: Pass 144 自前 ELF リンカ 完全静的リンク (`144_backend_x86_elf.scm`)
1. **`ar` (`!<arch>\n`) パーサ ＆ オンデマンドシンボル解決**:
   - Unix 静的アーカイブメンバーヘッダと`/`シンボル索引（または走査）を読み、未定義シンボルを解決するオブジェクトメンバーを不動点ループで取り込む。
   - `STB_GLOBAL`, `STB_WEAK`（強シンボル優先上書き）, `SHN_COMMON`（最大サイズ・アライメント確保）および複数オブジェクトの `.text`/`.rodata`/`.data`/`.bss`/`.init_array` マージと `R_X86_64_PC32`/`PLT32`/`64`/`32S` 再配置を完遂。
2. **検証条件**:
   - システム `ld` 呼び出し 0 回で完全静的 `lua` ELF を出力し、`file` / `ldd` にて動的ライブラリ依存ゼロ（`statically linked` / `not a dynamic executable`）を確認。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `musl libc` の対象モジュール群が ULisp でエラーなくビルドできること。
- [ ] Pass 144 リンカのみで Lua ＋ 自前 musl の完全静的 ELF バイナリが生成でき、システム `ld` 呼び出しが 0 回であること。
- [ ] `ldd` で動的依存がゼロであり、同バイナリ上で Lua テストスイートが PASS すること。
