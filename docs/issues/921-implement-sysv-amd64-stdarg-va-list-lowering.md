---
ID: 921
種別: Feature
優先度: High
ステータス: Open (In Progress)
---

# [FEAT/ENH] `<stdarg.h>` 可変長引数 (`va_list` / `va_start` / `va_arg`) の SysV AMD64 ABI Lowering 実装 (ID: 921)

## 1. 概要 / Summary
Lua の `lua_pushfstring`, `luaL_error`, および C 標準の `vsnprintf` 等を支える `<stdarg.h>`（`va_list`, `va_start`, `va_arg`, `va_end`, `va_copy`）を、SysV AMD64 ABI 規定の Register Save Area（汎用 6 レジスタ + XMM 8 レジスタ）および 24 バイト `__va_list_tag` 構造体として Lowering する機能を実装する（Phase S3 / Task T9）。

---

## 2. トレーサビリティ / Traceability
- 関連設計書:
  - [DSN-33-32 §4.3](../designs/DSN-33-32-ulisp_lua_c_codebase_compilation_and_self_hosting_architecture.md)
  - [DSN-33-13 §3.2](../designs/DSN-33-13-ulisp_typed_machine_lir_and_multi_target_backend_architecture.md)
- 前提基盤（実装済・先行）:
  - `#829`: SysV ABI 呼出規約（[ulisp/compiler/calling_convention.scm](../../ulisp/compiler/calling_convention.scm)）
  - `#918`: 構造体メモリレイアウト（[[#918]](918-implement-c99-struct-union-enum-bitfield-sysv-layout.md)）
- 後続連携 Issue:
  - [[#925]](925-build-lua-5x-c-codebase-compilation-pipeline-with-ulisp.md) (`lua_pushfstring` / `lauxlib.c`)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] `ulisp/frontend_c/include/stdarg.h` (新規: ULisp 組み込み `<stdarg.h>` — `__builtin_va_list`, `va_start`, `va_arg`, `va_end`, `va_copy`)
- [ ] `ulisp/frontend_c/sema.scm` (`__builtin_va_list`, `__builtin_va_start`, `__builtin_va_arg`, `__builtin_va_end`, `__builtin_va_copy` 型検査)
- [ ] `ulisp/frontend_c/lower_to_lir.scm` (Register Save Area 参照 ＆ `va_arg` 分岐 LIR 展開)
- [ ] [ulisp/compiler/calling_convention.scm](../../ulisp/compiler/calling_convention.scm) ＆ [ulisp/backend/140_backend_x86_64.scm](../../ulisp/backend/140_backend_x86_64.scm) (可変長関数プロローグ 176B 退避 ＆ 呼出側 `%al` 設定)
- [ ] `ulisp/tests/test_c99_stdarg.scm` (新規: 多引数・整数/浮動小数点/構造体混合 `va_arg` ・`vsnprintf` 連携テスト)
- [ ] [ulisp/Makefile](../../ulisp/Makefile) (`test_c99_stdarg` ターゲットおよび `test` 集約への登録)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/921-implement-sysv-amd64-stdarg-lowering`

### 4.1 SysV AMD64 `__va_list_tag` ＆ Register Save Area 仕様
1. **`ulisp/frontend_c/include/stdarg.h`**:
   - `typedef __builtin_va_list va_list;`（`struct { unsigned int gp_offset; unsigned int fp_offset; void *overflow_arg_area; void *reg_save_area; }[1];` 相当の 24B 配列型）および `va_start`/`va_arg`/`va_end`/`va_copy` マクロを定義。
2. **プロローグ 176B Register Save Area (`140_backend_x86_64.scm` / `calling_convention.scm`)**:
   - `variadic?` 関数のフレーム上に 176B を確保し、`rdi, rsi, rdx, rcx, r8, r9` をオフセット `0..40` へ保存。さらに `test %al, %al` により `%al != 0` の場合のみ `xmm0..xmm7` をオフセット `48..160` へ退避する。
   - 可変長関数を呼ぶコールサイトでは、使用する XMM レジスタ数（最大 8）を `%al` へセットする規約を徹底。

### 4.2 `va_start` / `va_arg` / `va_copy` LIR Lowering ＆ 堅牢性
1. **`__builtin_va_start(ap, last)`**:
   - `gp_offset = 8 * named_int_args`, `fp_offset = 48 + 16 * named_sse_args`, `overflow_arg_area = caller_stack_arg_base`, `reg_save_area = frame_reg_save_base` で初期化。
2. **`__builtin_va_arg(ap, type)`**:
   - 整数・ポインタ型: `gp_offset <= 40` なら `reg_save_area + gp_offset` からロードして `gp_offset += 8`、それ以外は `overflow_arg_area` からロードして `+ 8` 更新。
   - 浮動小数点型: `fp_offset <= 160` なら `reg_save_area + fp_offset` からロードして `fp_offset += 16`、それ以外は `overflow_arg_area` 経由。
   - `> 16B` またはメモリクラス構造体: 常に `overflow_arg_area` から読み出しアライメント切上げ加算。
3. **診断コード (`diagnostic.scm` #833)**:
   - `"C99-VA-001"`（固定引数関数内での `va_start` 使用または非互換型指定）、`"C99-VA-002"`（C99 既定引数昇格未適合型例: `char`/`float` の `va_arg` 警告・エラー）。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 7個以上の整数引数・8個以上の浮動小数点引数が混在する可変長引数関数（`va_copy`・`va_list` 別関数受け渡し含む）が SysV ABI 準拠で正確に値を取り出せること。
- [ ] ホスト `libc` の `vsnprintf` へ ULisp 生成 `va_list` を渡して正しくフォーマット出力できること。
- [ ] `ulisp/tests/test_c99_stdarg.scm` が全件 PASS すること。
