---
ID: 925
種別: Feature
優先度: High
ステータス: Open (In Progress)
---

# [FEAT/ENH] Lua 5.x 全 C ソースファイル（コア・標準ライブラリ・CLI）の ULisp 一括ビルドパイプライン構築 (ID: 925)

## 1. 概要 / Summary
Phase S2〜S4 で構築した ULisp C99 フロントエンド（[DSN-33-11](../designs/DSN-33-11-ulisp_multilingual_frontend_and_ctfe_architecture.md)）と型付き機械語バックエンド（[DSN-33-13](../designs/DSN-33-13-ulisp_typed_machine_lir_and_multi_target_backend_architecture.md)）を用いて、公式 Lua 5.x（5.4 系）の C ソースコード一式（コア VM 22 ファイル、標準ライブラリ 10 ファイル、`lua.c` / `luac.c` CLI 計約 3 万行）をコンパイル・リンクし、ネイティブ `lua` 実行バイナリを生成するビルドパイプラインを構築する（Phase S5 / Task T13）。

---

## 2. トレーサビリティ / Traceability
- 関連設計書:
  - [DSN-33-32 §1.2, §2.1, §6.1](../designs/DSN-33-32-ulisp_lua_c_codebase_compilation_and_self_hosting_architecture.md)
- 前提基盤 Issue:
  - [[#917]](closed/917-implement-c-compiler-driver-and-host-ld-integration.md), [[#918]](918-implement-c99-struct-union-enum-bitfield-sysv-layout.md), [[#919]](919-implement-c99-pointer-scaling-array-decay-and-escape-analysis.md), [[#920]](920-implement-c99-function-pointers-and-switch-goto-cfg-lowering.md), [[#921]](921-implement-sysv-amd64-stdarg-va-list-lowering.md), [[#922]](closed/922-implement-setjmp-longjmp-inline-asm-and-stack-spill-protection.md), [[#923]](923-implement-c99-floating-point-sema-and-lir-conversion-lowering.md), [[#924]](924-verify-sse2-xmm-abi-and-floating-point-differential-fuzzing.md)
- 後続連携 Issue:
  - [[#926]](926-verify-lua-5x-official-test-suite-e2e-selfhost-ci.md) (公式テストスイート E2E 実証), [[#927]](927-implement-c-header-sbi-pch-and-iterative-mem2reg-optimization.md) (PCH高速化), [[#928]](928-compile-musl-libc-with-ulisp-and-migrate-to-pass-144-elf-linker.md) (`musl libc` 完全静的リンク)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] `ulisp/frontend_c/include/` (新規: 自立C99ヘッダ `stddef.h`, `stdint.h`, `stdbool.h`, `limits.h`, `float.h`, `stdarg.h`, `setjmp.h` および libc 宣言スタブ `stdio.h`, `stdlib.h`, `string.h`, `ctype.h`, `math.h`, `errno.h`, `time.h`, `locale.h`, `signal.h`)
- [ ] `ulisp/tests/test_compile_lua.sh` (新規: Lua 5.x C ソース群のダウンロード/参照検証・全33翻訳単位 `.o` 一括コンパイル＆リンクハーネス)
- [ ] [ulisp/Makefile](../../ulisp/Makefile) (`compile_lua` ターゲット追加)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/925-build-lua-5x-c-codebase-with-ulisp`

### 4.1 組み込み C99 標準ヘッダ整備 (`ulisp/frontend_c/include/`)
1. **自立 C99 ヘッダ (Free-standing + SysV ABI)**:
   - `stddef.h` (`size_t`, `ptrdiff_t`, `NULL`, `offsetof`), `stdint.h` (`int8_t`..`uint64_t`, `intptr_t`), `stdbool.h`, `limits.h`, `float.h` (`DBL_MAX`, `DBL_MANT_DIG` 等), `stdarg.h` (#921), `setjmp.h` (#922)。
2. **Lua 必須 C99 標準ライブラリ宣言ヘッダ**:
   - `stdio.h` (`FILE`, `stdin`/`stdout`/`stderr`, `fopen`/`fread`/`fwrite`/`fprintf`/`snprintf`), `stdlib.h` (`malloc`/`realloc`/`free`/`strtod`/`exit`), `string.h`, `ctype.h`, `math.h`, `errno.h`, `time.h`, `locale.h`, `signal.h` を glibc 固有 GCC 拡張属性なしに純粋 C99 形式で用意（システムヘッダ非依存・決定論的ビルド可能）。

### 4.2 Lua 5.x 全翻訳単位一括コンパイル ＆ 回帰修正
1. **全 33 ファイルコンパイル**:
   - Core VM: `lapi.c`, `lcode.c`, `lctype.c`, `ldebug.c`, `ldo.c`, `ldump.c`, `lfunc.c`, `lgc.c`, `llex.c`, `lmem.c`, `lobject.c`, `lopcodes.c`, `lparser.c`, `lstate.c`, `lstring.c`, `ltable.c`, `ltm.c`, `lundump.c`, `lvm.c`, `lzio.c`
   - Stdlib & CLI: `lauxlib.c`, `lbaselib.c`, `lcorolib.c`, `ldblib.c`, `liolib.c`, `lmathlib.c`, `loadlib.c`, `loslib.c`, `lstrlib.c`, `ltablib.c`, `lutf8lib.c`, `linit.c`, `lua.c`
   - これらを `ulisp/driver/c_driver.scm -DLUA_USE_POSIX` で `.o` 化し、`ld` / `cc -lm -ldl` でネイティブ `build/lua_ulisp` を生成する。
2. **エッジケース回帰テスト追加**:
   - Lua 実コード中で遭遇した未対応 C99 イディオム（複合初期化子・文字型/ポインタ暗黙変換・複雑マクロ）をすべて単体回帰テストとして `ulisp/tests/` へ追加する。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] Lua 5.x 全 C ソースファイルがエラー・停止なしに ULisp で `.o` へコンパイルできること。
- [ ] 生成された `lua` バイナリが対話 REPL およびコマンドラインスクリプト（`./lua -e "print(1 + 2 * 3, math.sqrt(16))"` 等）を正常実行できること。
- [ ] ビルドスクリプト（`ulisp/tests/test_compile_lua.sh`）および `make -C ulisp compile_lua` が再現可能に成功すること。
