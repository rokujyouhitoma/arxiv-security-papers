---
ID: 922
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] 非局所脱出 (`setjmp` / `longjmp`) の `%inline-asm` 実装および呼び出し関数内の生存変数スピル保護 (ID: 922)

## 1. 概要 / Summary
Lua のエラー回復機構（`ldo.c`: `luaD_rawrunprotected`, `lua_pcall`, `lua_error`）の中核である `setjmp` / `longjmp` を、Issue #838 の `%inline-asm` を用いて x86-64 ABI 準拠で実装する（Step S3 / T10）。さらに、`setjmp`（`returns_twice`）を含む関数において、`longjmp` 復帰後に壊れてはならないローカル変数をレジスタではなくスタックフレームへ保持する保護規約をコンパイラへ組み込む。

---

## 2. トレーサビリティ / Traceability
- 関連設計書:
  - [DSN-33-32 §4.2](../designs/DSN-33-32-ulisp_lua_c_codebase_compilation_and_self_hosting_architecture.md)
  - [DSN-33-13 §2.4, §4.1](../designs/DSN-33-13-ulisp_typed_machine_lir_and_multi_target_backend_architecture.md)
- 前提基盤 Issue: #838 (`%inline-asm`), #827 (Braun SSA), #919, #920

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] `ulisp/frontend_c/include/setjmp.h` (新規: `jmp_buf` 定義とプロトタイプ)
- [ ] `ulisp/lib/builtins.c` (新規: `%inline-asm` ベースの `setjmp`/`longjmp` 等組み込みランタイム、または `builtins.scm`)
- [ ] `ulisp/frontend_c/lower_to_lir.scm` ＆ `ulisp/lir/132_braun_ssa.scm` (`returns_twice` 呼び出しを含む関数の変数スタック退避保護)
- [ ] `ulisp/tests/test_c99_setjmp_longjmp.scm` (新規: 多段ネスト・ループ内 `setjmp`/`longjmp` 復帰テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/922-implement-setjmp-longjmp-inline-asm`

1. `jmp_buf` に Callee-Saved レジスタ（`rbx, rbp, r12, r13, r14, r15`）、呼出元 `rsp`、戻りアドレス `rip` の 8 ワード（64 バイト）を保存・復元する `setjmp` / `longjmp` を `%inline-asm`（または x86-64 LIR 組み込み）で実装し、`longjmp(env, 0)` が `1` を返す C 規格を遵守する。
2. `setjmp` 呼び出し（`returns_twice` 属性）を検知した関数においては、該当関数内の非 volatile ローカル変数について Braun SSA 昇格を抑制（または `setjmp` 越えの変数をスタックスロットへスピル強制）し、`longjmp` による非局所ジャンプ後もスタック上の最新値が一貫して読み出せるように保証する。
3. Lua の保護付き実行パターンを模したネスト例外復帰テストを実行する。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `setjmp` の初回返却値 `0` および `longjmp(env, val)` 復帰後の返却値（`val != 0 ? val : 1`）が仕様通り動作すること。
- [ ] 深い再帰呼び出し先からの `longjmp` 後に、呼び出し元関数のローカル変数が破損せず保持されていること。
- [ ] ホスト libc の `setjmp`/`longjmp` と混在せず ULisp 単独または musl と整合して動作すること。
