---
ID: 920
種別: Feature
優先度: High
ステータス: Open (In Progress)
---

# [FEAT/ENH] C99 関数ポインタ間接呼び出しおよび巨大 switch/goto 複雑 CFG の Braun SSA Lowering 実装 (ID: 920)

## 1. 概要 / Summary
Lua C API の中核である関数ポインタ（`typedef int (*lua_CFunction)(lua_State *L);`）の型検査・間接呼び出し（`%call-indirect`）と、`lvm.c` (`luaV_execute`) 等に見られる巨大な `switch-case`（フォールスルー・Duff's device 的飛び込みを含む）および任意 `goto` 制御フローグラフの Core LIR Lowering・Braun SSA `seal-block` 検証を実装する（Phase S3 / Task T8）。

---

## 2. トレーサビリティ / Traceability
- 関連設計書:
  - [DSN-33-32 §3.3, §4.4](../designs/DSN-33-32-ulisp_lua_c_codebase_compilation_and_self_hosting_architecture.md)
  - [DSN-33-13 §4.1, §5.2](../designs/DSN-33-13-ulisp_typed_machine_lir_and_multi_target_backend_architecture.md)
- 前提基盤（実装済・先行）:
  - `#827`: Pass 132 Braun SSA 任意 CFG 対応（[ulisp/lir/132_lir_braun_ssa.scm](../../ulisp/lir/132_lir_braun_ssa.scm)）
  - `#829`: SysV ABI 呼出規約（[ulisp/compiler/calling_convention.scm](../../ulisp/compiler/calling_convention.scm)）
  - `#830`: `.rodata` ジャンプテーブル（[ulisp/backend/144_backend_x86_elf.scm](../../ulisp/backend/144_backend_x86_elf.scm)）
  - `#915`: C99 Parser（[[#915]](915-implement-c99-parser-and-nanopass-c-ast-definitions.md)）
  - `#916`: C99 Sema Core ＆ 整数 Lowering（[[#916]](916-implement-c99-sema-core-and-integer-subset-lir-lowering.md)）
- 後続連携 Issue:
  - [[#925]](925-build-lua-5x-c-codebase-compilation-pipeline-with-ulisp.md) (`lvm.c` / `lapi.c` ビルド)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] `ulisp/frontend_c/sema.scm` (関数ポインタ型比較・関数指示子からの暗黙退化・`switch`/`goto`/ラベルスコープ検証)
- [ ] `ulisp/frontend_c/lower_to_lir.scm` (`%call-indirect`, `switch`/`case`/`default`/`break`/`goto` CFG 降格)
- [ ] [ulisp/backend/140_backend_x86_64.scm](../../ulisp/backend/140_backend_x86_64.scm) (`%switch` ジャンプテーブル/二分探索展開・間接 `call *reg`)
- [ ] `ulisp/tests/test_c99_funcptr_and_switch_cfg.scm` (新規: 関数ポインタ配列・フォールスルー `switch`・前後方 `goto` テスト)
- [ ] [ulisp/Makefile](../../ulisp/Makefile) (`test_c99_funcptr_and_switch_cfg` ターゲットおよび `test` 集約への登録)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/920-implement-c99-funcptr-and-switch-goto-cfg`

### 4.1 関数ポインタ型解決 ＆ `%call-indirect` 降格
1. **関数指示子 ＆ 関数ポインタ**:
   - `sema.scm` にて関数識別子の `(fn ...)` 型から `(ptr (fn ...))` への自動退化、`fp(args)` および `(*fp)(args)` の統一型検査、ならびに関数ポインタ配列 `int (*ops[])(int, int)` の要素型比較を実装。
2. **SysV 間接コール**:
   - `lower_to_lir.scm` で `(%call-indirect 'sysv ret-ty fn-ptr arg-vals ...)` を出力し、`140_backend_x86_64.scm` にて引数レジスタ (`rdi..r9`) 設定後にスクラッチレジスタ経由の `call *%r10` / `call *%rax` を生成。

### 4.2 巨大 `switch`・フォールスルー・任意 `goto` の Braun SSA Lowering
1. **2パス基本ブロック生成と遅延 `seal-block`**:
   - 関数内の全ラベル `label:` 用 LIR ブロックを先行生成し、関数本体の CFG 下ろし中に前方・後方 `goto` の `%jump` エッジを登録する。
   - `switch (cond)` では定数評価済みの各 `case val:`・`default:` への分岐先ブロックを収集し、`%switch cond default-lbl ((v1 . lbl1) ...)` を出力（`case` 間のフォールスルーは終端 `%jump next-case-lbl` として明示し、`break` ターゲットスタックで脱出）。
   - 関数のすべての基本ブロックのエッジ登録完了後にのみ `seal-block` を呼び出し、還元不可能なループを含む `lvm.c` 級 CFG の Phi 挿入を安全に完結させる。
2. **診断コード (`diagnostic.scm` #833)**:
   - `"C99-CFG-001"`（未定義 `goto` ラベル・重複ラベル）、`"C99-CFG-002"`（重複 `case` 定数・複数 `default`）、`"C99-CFG-003"`（`switch` 外の `case`/`default`、ループ外 `break`/`continue`）、`"C99-CFG-004"`（非関数ポインタに対する呼び出し）。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 関数ポインタの配列・構造体メンバ経由の間接呼び出しが Reference VM・x86-64・Portable C Backend で一致動作すること。
- [ ] 80分岐以上の `switch-case`（フォールスルー・ネスト・前方/後方 `goto` 併用）が Pass 132 Braun SSA でクラッシュせず正しく SSA 化・実行されること。
- [ ] `ulisp/tests/test_c99_funcptr_and_switch_cfg.scm` が全件 PASS すること。
