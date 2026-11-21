---
ID: 925
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] Lua 5.x 全 C ソースファイル（コア・標準ライブラリ・CLI）の ULisp 一括ビルドパイプライン構築 (ID: 925)

## 1. 概要 / Summary
Phase S2〜S4 で構築した ULisp C99 フロントエンド（[DSN-33-11](../designs/DSN-33-11-ulisp_multilingual_frontend_and_ctfe_architecture.md)）と型付き機械語バックエンド（[DSN-33-13](../designs/DSN-33-13-ulisp_typed_machine_lir_and_multi_target_backend_architecture.md)）を用いて、公式 Lua 5.x（5.4 系）の C ソースコード一式（コア VM 22 ファイル、標準ライブラリ 10 ファイル、`lua.c` / `luac.c` CLI 計約 3 万行）をコンパイル・リンクし、ネイティブ `lua` 実行バイナリを生成するビルドパイプラインを構築する（Step S5 / T13）。

---

## 2. トレーサビリティ / Traceability
- 関連設計書:
  - [DSN-33-32 §1.2, §2.1, §6.1](../designs/DSN-33-32-ulisp_lua_c_codebase_compilation_and_self_hosting_architecture.md)
- 前提基盤 Issue: #917, #918, #919, #920, #921, #922, #923, #924

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] `ulisp/tests/lua_build/` または `ulisp/tests/test_compile_lua.sh` (新規: Lua 5.x ソース取得・ULisp コンパイルハーネス)
- [ ] `ulisp/frontend_c/include/` (必要な最小限のターゲット組み込みヘッダ `limits.h`, `stddef.h`, `stdint.h`, `stdbool.h`, `stdarg.h`, `setjmp.h`)
- [ ] [ulisp/Makefile](../../ulisp/Makefile) (`compile_lua` 検証ターゲット追加)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/925-build-lua-5x-c-codebase-with-ulisp`

1. `ulisp/frontend_c/include/` に C99 自立ヘッダ（`stddef.h`, `stdint.h`, `stdbool.h`, `limits.h`, `float.h`, `stdarg.h`, `setjmp.h`）を整備し、システムヘッダ（`<stdio.h>`, `<stdlib.h>`, `<math.h>`, `<string.h>` 等）と協調できるようにする。
2. Lua 5.x の全 C ファイル（`lapi.c` 〜 `lzio.c`, `lauxlib.c` 〜 `linit.c`, `lua.c`）を `ulisp/driver/c_driver.scm` で個別に `.o` へコンパイルし、システム `ld` 経由で `-lm -ldl` とリンクして `lua` 実行ファイルを生成する。
3. コンパイル中に遭遇する C 構文・暗黙変換・マクロ展開のエッジケースをすべて抽出し、回帰テスト付きでフロントエンド/バックエンドを修正する。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] Lua 5.x 全 C ソースファイルがエラー・警告による停止なしに ULisp で `.o` へコンパイルできること。
- [ ] 生成された `lua` バイナリが対話 REPL およびワンライナー（`./lua -e "print(1 + 2 * 3)"`）を正常実行できること。
- [ ] ビルド手順が再現可能なスクリプト（`test_compile_lua.sh` 等）として自動化されていること。
