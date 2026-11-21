---
ID: 922
種別: Feature
優先度: High
ステータス: Open (In Progress)
---

# [FEAT/ENH] 非局所脱出 (`setjmp` / `longjmp`) の `%inline-asm` 実装および呼び出し関数内の生存変数スピル保護 (ID: 922)

## 1. 概要 / Summary
Lua のエラー回復機構（`ldo.c`: `luaD_rawrunprotected`, `lua_pcall`, `lua_error`）の中核である `setjmp` / `longjmp` を、Issue #838 の `%inline-asm` を用いて x86-64 ABI 準拠で実装する（Phase S3 / Task T10）。さらに、`setjmp`（`returns_twice`）を含む関数において、`longjmp` 復帰後に壊れてはならないローカル変数をレジスタではなくスタックフレームへ保持する保護規約（ISO C99 §7.13.2.1）をコンパイラへ組み込む。

---

## 2. トレーサビリティ / Traceability
- 関連設計書:
  - [DSN-33-32 §4.2](../designs/DSN-33-32-ulisp_lua_c_codebase_compilation_and_self_hosting_architecture.md)
  - [DSN-33-13 §2.4, §4.1](../designs/DSN-33-13-ulisp_typed_machine_lir_and_multi_target_backend_architecture.md)
- 前提基盤（実装済・先行）:
  - `#827`: Pass 132 Braun SSA（[ulisp/lir/132_lir_braun_ssa.scm](../../ulisp/lir/132_lir_braun_ssa.scm)）
  - `#838`: `%inline-asm`（[ulisp/backend/140_backend_x86_64.scm](../../ulisp/backend/140_backend_x86_64.scm)）
  - `#919`: エスケープ解析（[[#919]](919-implement-c99-pointer-scaling-array-decay-and-escape-analysis.md)）
  - `#920`: 複雑 CFG ＆ `goto` Lowering（[[#920]](920-implement-c99-function-pointers-and-switch-goto-cfg-lowering.md)）
- 後続連携 Issue:
  - [[#925]](925-build-lua-5x-c-codebase-compilation-pipeline-with-ulisp.md), [[#926]](926-verify-lua-5x-official-test-suite-e2e-selfhost-ci.md) (`errors.lua` 例外テスト)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] `ulisp/frontend_c/include/setjmp.h` (新規: `typedef long jmp_buf[8];` と `setjmp` / `longjmp` プロトタイプ)
- [ ] `ulisp/lib/c_runtime_builtins.scm` または `ulisp/frontend_c/builtins.c` (新規: `%inline-asm` ベース `setjmp` / `longjmp` 実装)
- [ ] `ulisp/frontend_c/lower_to_lir.scm` ＆ [ulisp/lir/132_lir_braun_ssa.scm](../../ulisp/lir/132_lir_braun_ssa.scm) (`returns_twice` 呼び出し関数の全ローカル変数メモリ退避強制)
- [ ] `ulisp/tests/test_c99_setjmp_longjmp.scm` (新規: 多段ネスト・ループ内・`longjmp(env, 0)`→`1` 復帰テスト)
- [ ] [ulisp/Makefile](../../ulisp/Makefile) (`test_c99_setjmp_longjmp` ターゲットおよび `test` 集約への登録)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/922-implement-setjmp-longjmp-inline-asm`

### 4.1 x86-64 `setjmp` / `longjmp` コンテキスト退避・復元仕様
1. **`jmp_buf` 64 バイトレイアウト**:
   - スロット `0..7`（各 8B）: `rbx` (0), `rbp` (8), `r12` (16), `r13` (24), `r14` (32), `r15` (40), 呼出後 `rsp` (`rsp + 8`, 48), 戻りアドレス `(%rsp)` (`rip`, 56)。
2. **`setjmp(env)` (`%inline-asm` / SysV ABI)**:
   - `%rdi` の指す `env` へ Callee-Saved 6 レジスタ、`(rsp + 8)`、およびスタックトップの戻りアドレス `(%rsp)` を保存し、`xor %eax, %eax` で初回 `0` を返却。
3. **`longjmp(env, val)` (`returns` non-0)**:
   - `%esi` (`val`) を確認し `test %esi, %esi` で `0` ならば `1` へ正規化（`%eax` へセット）。
   - `env` から 6 レジスタおよび `rsp` を復元し、保存済み `rip` へ `jmp *rdx` で直接ジャンプする。

### 4.2 `returns_twice` 関数内の生存変数スピル保護
1. **`has-setjmp?` 関数属性解析**:
   - `lower_to_lir.scm` にて関数本体に `setjmp` / `_setjmp` / `sigsetjmp` 呼び出しが含まれる場合、その関数の全ローカル `%alloca` に `:address-taken? #t`（または `:volatile? #t`）を付与して Pass 132 Braun SSA によるレジスタ昇格を抑止し、`longjmp` 後の未定義読み出し破損を防止する。
2. **診断コード (`diagnostic.scm` #833)**:
   - `"C99-JMP-001"`（不正な `jmp_buf` 引数型または引数の個数不整合）。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `setjmp` の初回返却値 `0` および `longjmp(env, val)` 復帰後の返却値（`val != 0 ? val : 1`）が ISO C99 仕様通り動作すること。
- [ ] 深い再帰呼び出し先からの `longjmp` 後に、呼び出し元関数のローカル変数が破損せず保持されていること。
- [ ] Lua `luaD_rawrunprotected` 相当のネスト例外保護コードがビルド・正常実行でき、`make -C ulisp test_c99_setjmp_longjmp` が全件 PASS すること。
