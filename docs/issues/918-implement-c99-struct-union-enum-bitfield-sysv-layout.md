---
ID: 918
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] C99 構造体・共用体・列挙型・ビットフィールドの SysV AMD64 メモリレイアウト計算の実装 (ID: 918)

## 1. 概要 / Summary
Lua 5.x の中核データ構造（`TValue`, `Value` union, `Table`, `Node`, `GCObject`, `lua_State`, `CallInfo`, `Proto`）を正確に扱うため、SysV AMD64 ABI 準拠の `struct` / `union` / `enum` / 無名複合体 / ビットフィールドのメモリレイアウト・パディング計算（`ulisp/frontend_c/type_layout.scm`）および初期化子リスト・`sizeof`/`offsetof` 評価を実装する（Step S3 / T6）。

---

## 2. トレーサビリティ / Traceability
- 関連設計書:
  - [DSN-33-32 §2.1, §3.2](../designs/DSN-33-32-ulisp_lua_c_codebase_compilation_and_self_hosting_architecture.md)
  - [DSN-33-11 §3.3, §4.2](../designs/DSN-33-11-ulisp_multilingual_frontend_and_ctfe_architecture.md)
  - [DSN-33-13 §3.2, §5.2](../designs/DSN-33-13-ulisp_typed_machine_lir_and_multi_target_backend_architecture.md)
- 前提基盤 Issue: #825 (CTFE), #829 (SysV ABI), #830 (.data/.rodata), #916 (Sema Core)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] `ulisp/frontend_c/type_layout.scm` (新規: 構造体/共用体/ビットフィールドレイアウトエンジン)
- [ ] `ulisp/frontend_c/sema.scm` (複合型・Designated Initializer・`sizeof`/`_Alignof` 統合)
- [ ] `ulisp/frontend_c/lower_to_lir.scm` (構造体コピー、`.data`/`.bss` 静的初期化子、ビットフィールド降格)
- [ ] `ulisp/tests/test_c99_struct_union_layout.scm` (新規: GCC `sizeof`/`offsetof` とのビット単位一致検証)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/918-implement-c99-struct-union-sysv-layout`

1. SysV AMD64 ABI 規則に従って `struct` メンバのオフセットと末尾パディング、`union` の最大サイズ・最大アライメントを算出し、前方宣言（不完全型 `struct lua_State;`）の解決を行う。
2. 無名 `struct`/`union` およびビットフィールド（`: width`）のビット位置・マスク抽出・挿入 LIR 命令列への展開を実装する。
3. Designated Initializer（`.field = v`, `[i] = v`）を含むグローバル/ローカル構造体・配列初期化、および 16 バイト超の構造体値渡し・戻り値（SysV `sret` / レジスタペア渡し）を実装する。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] Lua の `TValue`, `Table`, `lua_State` 相当のネスト構造体・共用体の `sizeof` / `offsetof` がホスト GCC と 100% 一致すること。
- [ ] ビットフィールドの読み書きおよびグローバル構造体配列の `.data` 初期化が Reference VM / x86-64 双方で正しく動作すること。
- [ ] SysV ABI の構造体値渡し・戻り値（8B, 16B, >16B）がホスト libc/GCC と互換動作すること。
