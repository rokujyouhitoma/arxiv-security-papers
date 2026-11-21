---
ID: 926
種別: Feature
優先度: High
ステータス: Open (In Progress)
---

# [FEAT/ENH] ULisp ビルド版 Lua バイナリによる公式テストスイート完走 E2E 実証ハーネスの構築 (ID: 926)

## 1. 概要 / Summary
Issue #925 で ULisp がビルドしたネイティブ `lua` 実行バイナリ上で、Lua 公式テストスイート（`all.lua`：クロージャ、コルーチン、GC ストレステスト、弱参照テーブル、メタテーブル、`pcall`/`xpcall` エラー復帰、ビット演算、数学・文字列・I/O ライブラリ）を実行し、全項目 PASS を実証する E2E テストハーネスを構築する（Phase S5 / Task T14）。

---

## 2. トレーサビリティ / Traceability
- 関連設計書:
  - [DSN-33-32 §6.1, §6.2](../designs/DSN-33-32-ulisp_lua_c_codebase_compilation_and_self_hosting_architecture.md)
- 前提基盤 Issue:
  - [[#925]](925-build-lua-5x-c-codebase-compilation-pipeline-with-ulisp.md) (Lua 5.x フルビルド)
- 後続連携 Issue:
  - [[#927]](927-implement-c-header-sbi-pch-and-iterative-mem2reg-optimization.md) (`-O2` 最適化), [[#928]](928-compile-musl-libc-with-ulisp-and-migrate-to-pass-144-elf-linker.md) (静的リンク), [[#929]](929-implement-ddc-diverse-double-compiling-determinism-verification.md) (DDC 検証), [[#930]](930-implement-c99-bounds-checking-sanitizer-mode.md) (`--sanitize-bounds`)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] `ulisp/tests/test_lua_selfhost_e2e.sh` (新規: 公式テストスイート自動実行 ＆ GCC リファレンス版との差分検証ハーネス)
- [ ] [ulisp/Makefile](../../ulisp/Makefile) (`test_lua_e2e` ターゲット追加)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/926-verify-lua-official-test-suite-e2e`

### 4.1 テストスイート段階別自動検証 ＆ リファレンス突合
1. **網羅スイート実行**:
   - ULisp ビルド版 `lua` 上で Lua 公式テストモジュール群（`calls.lua`, `closure.lua`, `coroutine.lua`, `errors.lua`, `events.lua`, `gc.lua`, `gengc.lua`, `locals.lua`, `math.lua`, `nextvar.lua`, `pm.lua`, `strings.lua`, `tpack.lua`, `utf8.lua`, `vararg.lua`, `all.lua`）を順次自動実行し、各フェーズの終了ステータスとタイムアウトガード（CWE-400 無限ループ監視）を記録。
2. **GCC ビルド版との挙動・結果一致検証**:
   - 同一ソースをシステム GCC でビルドした参照用 `lua_gcc` と同じ決定論的テストケース群（`-e` スクリプト＋公式単体スクリプト）を実行し、終了コード・標準出力・IEEE 754 計算値・`pcall`/`xpcall` スタックトレースの等価性をアサートする。
3. **負荷耐性バグ根絶**:
   - `gc.lua`（GC ストレス・長大なコールチェーン）および `errors.lua`（深いネストの `setjmp`/`longjmp`）で顕在化するレジスタ退避やポインタエスケープ漏れがあればすべて修正し回帰テスト化する。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] Lua 公式テストスイート全テストが ULisp ビルド版 `lua` 上でエラー 0 件で完走（PASS）すること。
- [ ] GCC ビルド版 `lua` と終了コードおよび標準出力が完全一致すること。
- [ ] Phase S5（Lua セルフホスト実証）の完了基準が `make -C ulisp test_lua_e2e` で満たされること。
