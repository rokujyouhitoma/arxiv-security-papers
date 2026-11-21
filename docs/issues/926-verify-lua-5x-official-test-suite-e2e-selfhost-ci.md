---
ID: 926
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] ULisp ビルド版 Lua バイナリによる公式テストスイート完走 E2E 実証ハーネスの構築 (ID: 926)

## 1. 概要 / Summary
Issue #925 で ULisp がビルドしたネイティブ `lua` 実行バイナリ上で、Lua 公式テストスイート（`all.lua`：クロージャ、コルーチン、GC ストレステスト、弱参照テーブル、メタテーブル、`pcall`/`xpcall` エラー復帰、ビット演算、数学・文字列・I/O ライブラリ）を実行し、全項目 PASS を実証する E2E テストハーネスを構築する（Step S5 / T14）。

---

## 2. トレーサビリティ / Traceability
- 関連設計書:
  - [DSN-33-32 §6.1, §6.2](../designs/DSN-33-32-ulisp_lua_c_codebase_compilation_and_self_hosting_architecture.md)
- 前提基盤 Issue: #925 (Lua フルビルド)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] `ulisp/tests/test_lua_selfhost_e2e.sh` (新規: 公式テストスイート自動実行 & GCC ビルド版との比較ハーネス)
- [ ] [ulisp/Makefile](../../ulisp/Makefile) (`test_lua_e2e` ターゲット追加)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/926-verify-lua-official-test-suite-e2e`

1. Lua 公式テストスイートの全カテゴリ（`calls.lua`, `closure.lua`, `coroutine.lua`, `errors.lua`, `gc.lua`, `math.lua`, `nextvar.lua`, `pm.lua`, `strings.lua`, `tpack.lua`, `utf8.lua`, `vararg.lua` 等）を ULisp ビルド版 `lua` で自動実行するハーネスを作成する。
2. GCC/Clang でビルドした参照用 `lua` バイナリと同じテストスクリプト群を実行し、終了コード・標準出力・浮動小数点精度・例外処理の挙動が 100% 一致することを検証する。
3. `gc.lua`（GC ストレス）や `errors.lua`（`setjmp`/`longjmp` 負荷）で発見される ABI・スタック整合の潜在バグをすべて解消する。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] Lua 公式テストスイート全テストが ULisp ビルド版 `lua` 上でエラー 0 件で完走（PASS）すること。
- [ ] GCC ビルド版 `lua` と実行結果・標準出力が一致すること。
- [ ] Phase S5（Lua セルフホスト実証）の完了基準が満たされること。
