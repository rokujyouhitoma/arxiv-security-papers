---
ID: 918
種別: Feature
優先度: High
ステータス: Open (In Progress)
---

# [FEAT/ENH] C99 構造体・共用体・列挙型・ビットフィールドの SysV AMD64 メモリレイアウト計算の実装 (ID: 918)

## 1. 概要 / Summary
Lua 5.x の中核データ構造（`TValue`, `Value` union, `Table`, `Node`, `GCObject`, `lua_State`, `CallInfo`, `Proto`）を正確に扱うため、SysV AMD64 ABI 準拠の `struct` / `union` / `enum` / 無名複合体 / ビットフィールドのメモリレイアウト・パディング計算（`ulisp/frontend_c/type_layout.scm`）および初期化子リスト・`sizeof` / `_Alignof` / `offsetof` 評価を実装する（Phase S3 / Task T6）。

---

## 2. トレーサビリティ / Traceability
- 関連設計書:
  - [DSN-33-32 §2.1, §3.2](../designs/DSN-33-32-ulisp_lua_c_codebase_compilation_and_self_hosting_architecture.md)
  - [DSN-33-11 §3.3, §4.2](../designs/DSN-33-11-ulisp_multilingual_frontend_and_ctfe_architecture.md)
  - [DSN-33-13 §3.2, §5.2](../designs/DSN-33-13-ulisp_typed_machine_lir_and_multi_target_backend_architecture.md)
- 前提基盤（実装済・先行）:
  - `#825`: CTFE 定数式評価（[ulisp/compiler/eval_in_language.scm](../../ulisp/compiler/eval_in_language.scm)）
  - `#829`: SysV ABI 呼出規約（[ulisp/compiler/calling_convention.scm](../../ulisp/compiler/calling_convention.scm)）
  - `#830`: ELF `.data`/`.rodata`/`.bss` セクション（[ulisp/backend/144_backend_x86_elf.scm](../../ulisp/backend/144_backend_x86_elf.scm)）
  - `#916`: C99 Sema Core ＆ 整数 Lowering（[[#916]](916-implement-c99-sema-core-and-integer-subset-lir-lowering.md)）
- 後続連携 Issue:
  - [[#919]](919-implement-c99-pointer-scaling-array-decay-and-escape-analysis.md), [[#921]](921-implement-sysv-amd64-stdarg-va-list-lowering.md), [[#925]](925-build-lua-5x-c-codebase-compilation-pipeline-with-ulisp.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] `ulisp/frontend_c/type_layout.scm` (新規: `<c-struct-layout>` / `<c-field-layout>`・SysV ABI クラス分類エンジン)
- [ ] `ulisp/frontend_c/sema.scm` (複合型・不完全型解決・Designated Initializer・`sizeof`/`_Alignof`/`offsetof` 統合)
- [ ] `ulisp/frontend_c/lower_to_lir.scm` (構造体コピー `memcpy` / 8-byte コピー・`.data`/`.bss` 静的初期化子・ビットフィールド操作降格)
- [ ] `ulisp/tests/test_c99_struct_union_layout.scm` (新規: GCC `sizeof`/`offsetof` とのビット単位一致検証)
- [ ] [ulisp/Makefile](../../ulisp/Makefile) (`test_c99_struct_union_layout` ターゲットおよび `test` 集約への登録)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/918-implement-c99-struct-union-sysv-layout`

### 4.1 SysV AMD64 レイアウト計算 ＆ ABI 分類 (`ulisp/frontend_c/type_layout.scm`)
1. **`<c-struct-layout>` ＆ `<c-field-layout>` レコード**:
   - 各メンバの `name`, `type`, `offset`（バイト）, `bit-offset`, `bit-width`、および全体の `size`（最大アライメントの倍数へ切上）・`align`・SysV 8バイト分割クラス（`'integer`, `'sse`, `'memory`）を算出。
   - **柔軟配列メンバ / 不完全型**: 前方宣言 `typedef struct lua_State lua_State;` の不完全ポインタ解決および末尾フレキシブル配列メンバ `T data[];` をサポート。
2. **無名 `struct`/`union` ＆ ビットフィールド**:
   - 無名メンバの親構造体へのフラット化展開。
   - ビットフィールド（例: `unsigned int type : 4; int flag : 1;`）の配置ルール（格納単位アライメント跨ぎ判定、`: 0` 境界強制アライン）および読み書き時のビットマスク＋論理/算術シフト演算への降格。

### 4.2 初期化子・`sizeof`/`offsetof`・構造体値渡し
1. **Designated Initializer ＆ `.data`/`.bss` 配置**:
   - `{ .field = v, [idx] = v }` のネスト解決と未指定領域のゼロ埋め正規化。
2. **SysV AMD64 構造体値渡し/戻り値**:
   - `<= 8B`（単一レジスタ）、`9B..16B`（2レジスタペア `{rdi, rsi}` / `{rax, rdx}`）、`> 16B`（隠れ `sret` ポインタ経由 `MEMORY` クラス渡し）を実装。
3. **診断コード (`diagnostic.scm` #833)**:
   - `"C99-LAY-001"`（不完全型への `sizeof`/実体化）、`"C99-LAY-002"`（存在しない構造体メンバ参照）、`"C99-LAY-003"`（ビットフィールド幅超過または `&` アドレス取得違反）、`"C99-LAY-004"`（環状構造体定義）。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] Lua の `TValue`, `Value`, `Table`, `lua_State` 相当のネスト構造体・共用体の `sizeof` / `offsetof` がホスト GCC と 100% 一致すること。
- [ ] 無名共用体・ビットフィールドの読み書きおよびグローバル構造体配列の `.data` 初期化が Reference VM / x86-64 双方で正しく動作すること。
- [ ] SysV ABI の構造体値渡し・戻り値（8B, 16B, >16B `sret`）がホスト libc/GCC と互換動作し、`make -C ulisp test_c99_struct_union_layout` が PASS すること。
