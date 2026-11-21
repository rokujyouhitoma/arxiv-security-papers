---
ID: 919
種別: Feature
優先度: High
ステータス: Open (In Progress)
---

# [FEAT/ENH] C99 ポインタスケーリング演算・配列退化およびアドレス取得変数のスタックエスケープ処理の実装 (ID: 919)

## 1. 概要 / Summary
C99 の配列からポインタへの自動退化（Array-to-Pointer Decay）、ポインタ加減算の要素サイズ自動スケーリング（`ptr + n`, `p1 - p2`）、`.` / `->` メンバアクセス、および単項 `&` でアドレス取得されたローカル変数を SSA レジスタ昇格から保護しスタック上に留めるエスケープ解析・Lowering を実装する（Phase S3 / Task T7）。

---

## 2. トレーサビリティ / Traceability
- 関連設計書:
  - [DSN-33-32 §3.4, §4.1](../designs/DSN-33-32-ulisp_lua_c_codebase_compilation_and_self_hosting_architecture.md)
  - [DSN-33-13 §2.1, §4.1](../designs/DSN-33-13-ulisp_typed_machine_lir_and_multi_target_backend_architecture.md)
- 前提基盤（実装済・先行）:
  - `#827`: Pass 132 Braun SSA（[ulisp/lir/132_lir_braun_ssa.scm](../../ulisp/lir/132_lir_braun_ssa.scm)）
  - `#916`: C99 Sema Core ＆ 整数 Lowering（[[#916]](916-implement-c99-sema-core-and-integer-subset-lir-lowering.md)）
  - `#918`: C99 構造体・共用体・SysV レイアウト（[[#918]](918-implement-c99-struct-union-enum-bitfield-sysv-layout.md)）
- 後続連携 Issue:
  - [[#925]](925-build-lua-5x-c-codebase-compilation-pipeline-with-ulisp.md), [[#930]](930-implement-c99-bounds-checking-sanitizer-mode.md) (`--sanitize-bounds`)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] `ulisp/frontend_c/sema.scm` (ポインタ演算型規則・配列退化・左辺値・`const`/配列サイズ検査)
- [ ] `ulisp/frontend_c/lower_to_lir.scm` (アドレス取得エスケープ収集 `c99-collect-escaped-bindings`・スケーリング加算・`%load`/`%store`)
- [ ] [ulisp/lir/132_lir_braun_ssa.scm](../../ulisp/lir/132_lir_braun_ssa.scm) (`%alloca` のうち `:address-taken? #t` 等エスケープ変数を除く非エスケープ変数のみを選択 mem2reg 昇格)
- [ ] `ulisp/tests/test_c99_pointers_and_escape.scm` (新規: ポインタ演算・多次元配列・出力引数 `&status` テスト)
- [ ] [ulisp/Makefile](../../ulisp/Makefile) (`test_c99_pointers_and_escape` ターゲットおよび `test` 集約への登録)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/919-implement-c99-pointer-scaling-and-escape`

### 4.1 配列退化・ポインタスケーリング演算 (ISO C99 §6.3.2.1 / §6.5.6)
1. **配列退化ルール**:
   - 式中の `(array elem len)` 型を原則 `(ptr elem)` へ暗黙変換する。ただし `sizeof expr`, `_Alignof expr`, および `&expr` の直接オペランド時は例外として配列型を保持する（多次元配列 `int a[3][4]` は `int (*)[4]` へ退化）。
2. **スケーリング加減算・ポインタ減算**:
   - `ptr + idx` / `idx + ptr` / `ptr - idx`: `elem_size = (c-type-size elem-type)`（最低 `1`）を用い `(%add ptr (%mul (%sext idx 'i64) elem_size))` へ降格。
   - `p1 - p2`: 同一基底要素型の2ポインタ減算を `(%sdiv (%sub p1 p2) elem_size)`（`ptrdiff_t` / `'i64`）へ降格（`elem_size = 0` や `void *` の不正加減算は拒否）。
   - `p++`, `++p`, `p--`, `--p`: 旧値/新値に応じた返却値と `elem_size` 加減算のメモリ更新を生成。

### 4.2 エスケープ解析 ＆ Pass 132 Braun SSA 協調
1. **アドレス取得集合収集 `(c99-collect-escaped-bindings ast)`**:
   - ローカル変数に対し単項 `&var` が適用された場合、または変数が配列型・複合構造体である場合に `:address-taken? #t` メタデータを `%alloca` ノードへ付与する。
2. **Pass 132 昇格フィルタ**:
   - [132_lir_braun_ssa.scm](../../ulisp/lir/132_lir_braun_ssa.scm) が `:address-taken? #t` の `%alloca` をレジスタ昇格せず常にメモリ（`%load`/`%store`）経由で読み書きすることで、Lua の `lua_getinfo(..., &ar)` / `&status` 出力引数パターンを 100% 保護する。
3. **診断コード (`diagnostic.scm` #833)**:
   - `"C99-PTR-001"`（配列または非ポインタ型に対する不正ポインタ演算）、`"C99-PTR-002"`（異なる型間の非互換ポインタ減算・`void *` 算術）、`"C99-PTR-003"`（非左辺値またはビットフィールドへの `&` アドレス取得）。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 多次元配列（`a[i][j]`）、ポインタの前後置インクリメント（`p++`, `++p`）、ポインタ減算（`p1 - p2`）が C99 仕様通り動作すること。
- [ ] `&status` 等を別関数へ渡して書き換える出力引数パターンが Pass 132 Braun SSA 適用後も正しくメモリ経由で反映されること。
- [ ] `ulisp/tests/test_c99_pointers_and_escape.scm` が全件 PASS し、既存 Scheme テストに回帰がないこと。
