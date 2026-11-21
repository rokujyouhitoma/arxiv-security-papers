---
ID: 921
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] `<stdarg.h>` 可変長引数 (`va_list` / `va_start` / `va_arg`) の SysV AMD64 ABI Lowering 実装 (ID: 921)

## 1. 概要 / Summary
Lua の `lua_pushfstring`, `luaL_error`, および C 標準の `vsnprintf` 等を支える `<stdarg.h>`（`va_list`, `va_start`, `va_arg`, `va_end`, `va_copy`）を、SysV AMD64 ABI 規定の Register Save Area（汎用 6 レジスタ + XMM 8 レジスタ）および 24 バイト `va_list` 構造体として Lowering する機能を実装する（Step S3 / T9）。

---

## 2. トレーサビリティ / Traceability
- 関連設計書:
  - [DSN-33-32 §4.3](../designs/DSN-33-32-ulisp_lua_c_codebase_compilation_and_self_hosting_architecture.md)
  - [DSN-33-13 §3.2](../designs/DSN-33-13-ulisp_typed_machine_lir_and_multi_target_backend_architecture.md)
- 前提基盤 Issue: #829 (SysV ABI), #918 (構造体レイアウト)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] `ulisp/frontend_c/include/stdarg.h` (新規: ULisp 組み込み `<stdarg.h>` ヘッダ)
- [ ] `ulisp/frontend_c/sema.scm` (`__builtin_va_list`, `__builtin_va_start`, `__builtin_va_arg`, `__builtin_va_end`, `__builtin_va_copy` 認識)
- [ ] `ulisp/frontend_c/lower_to_lir.scm` (Register Save Area 確保と `va_arg` 展開)
- [ ] `ulisp/compiler/calling_convention.scm` / `ulisp/backend/140_backend_x86_64.scm` (可変長関数プロローグ退避＆コールサイト `%al` 設定)
- [ ] `ulisp/tests/test_c99_stdarg.scm` (新規: 多引数・整数/浮動小数点/構造体混合 `va_arg` テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/921-implement-sysv-amd64-stdarg-lowering`

1. 可変長引数関数（`...` を持つ関数）のスタックフレーム先頭付近に 176 バイトの Register Save Area（`rdi..r9`: 48B、`xmm0..xmm7`: 128B）を確保し、プロローグでレジスタ引数を退避する（`%al != 0` のとき XMM を退避）。
2. `va_start(ap, last)` により 24 バイト `va_list` 構造体 `{ gp_offset, fp_offset, overflow_arg_area, reg_save_area }` を固定引数の個数に応じた初期オフセットで初期化する。
3. `va_arg(ap, type)` について、整数・ポインタ型（`gp_offset <= 40`）、浮動小数点型（`fp_offset <= 160`）、およびメモリ溢れ（`overflow_arg_area` 読み出し＋ポインタ加算）への条件分岐 LIR を生成する。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 7個以上の整数引数・8個以上の浮動小数点引数が混在する可変長引数関数（`va_list` 受け渡し含む）が SysV ABI 準拠で正確に値を取り出せること。
- [ ] ホスト `libc` の `vsnprintf` へ ULisp 生成 `va_list` を渡して正しくフォーマット出力できること。
- [ ] `ulisp/tests/test_c99_stdarg.scm` が全件 PASS すること。
