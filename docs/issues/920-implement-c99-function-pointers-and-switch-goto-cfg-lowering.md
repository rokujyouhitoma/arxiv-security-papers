---
ID: 920
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] C99 関数ポインタ間接呼び出しおよび巨大 switch/goto 複雑 CFG の Braun SSA Lowering 実装 (ID: 920)

## 1. 概要 / Summary
Lua C API の中核である関数ポインタ（`typedef int (*lua_CFunction)(lua_State *L);`）の型検査・間接呼び出し（`%call-indirect`）と、`lvm.c` (`luaV_execute`) 等に見られる巨大な `switch-case`（フォールスルー・Duff's device 的飛び込みを含む）および任意 `goto` 制御フローグラフの Core LIR Lowering・Braun SSA `seal-block` 検証を実装する（Step S3 / T8）。

---

## 2. トレーサビリティ / Traceability
- 関連設計書:
  - [DSN-33-32 §3.3, §4.4](../designs/DSN-33-32-ulisp_lua_c_codebase_compilation_and_self_hosting_architecture.md)
  - [DSN-33-13 §4.1, §5.2](../designs/DSN-33-13-ulisp_typed_machine_lir_and_multi_target_backend_architecture.md)
- 前提基盤 Issue: #827 (Braun SSA 任意 CFG 対応), #829 (SysV ABI), #830 (`.rodata` ジャンプテーブル), #915, #916

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] `ulisp/frontend_c/sema.scm` (関数ポインタ型比較・関数指示子からの暗黙変換)
- [ ] `ulisp/frontend_c/lower_to_lir.scm` (`%call-indirect`, `switch`/`case`/`default`/`break`/`goto` CFG 生成)
- [ ] `ulisp/backend/140_backend_x86_64.scm` (`%switch` ジャンプテーブルまたは二分探索展開・間接 `call *reg`)
- [ ] `ulisp/tests/test_c99_funcptr_and_switch_cfg.scm` (新規: 関数ポインタ配列・フォールスルー `switch`・後方 `goto` テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/920-implement-c99-funcptr-and-switch-goto-cfg`

1. 関数指示子（Function Designator）から関数ポインタへの自動変換と、シグネチャの一致検査を `sema.scm` に実装する。
2. `lower_to_lir.scm` で関数ポインタ経由の呼び出しを `'sysv` 規約付きの `%call-indirect` へ変換し、`140_backend_x86_64.scm` で正しい間接コール機械語を生成する。
3. 関数内のすべての `goto` ラベルおよび `switch` ケースを基本ブロックとして生成し、ブロック内のすべての先行エッジ登録完了後に `seal-block` を呼ぶプロトコルで前方/後方ジャンプの Phi 解決を完結させる。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 関数ポインタの配列・構造体メンバ経由の呼び出しが Reference VM・x86-64・C Backend で一致動作すること。
- [ ] 80分岐以上の `switch-case`（フォールスルー・ネスト・`goto` 併用）が Braun SSA でクラッシュせず正しく SSA 化・実行されること。
- [ ] `ulisp/tests/test_c99_funcptr_and_switch_cfg.scm` が全件 PASS すること。
