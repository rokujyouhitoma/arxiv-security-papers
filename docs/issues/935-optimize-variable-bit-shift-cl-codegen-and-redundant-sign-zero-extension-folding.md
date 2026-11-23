---
ID: 935
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] C99 変数ビットシフトの x86-64 %cl 単一命令化および重複ゼロ・符号拡張 (%zext/%sext/%trunc) の畳み込み最適化 (ID: 935)

## 1. 概要 / Summary

[Issue #925](closed/925-build-lua-5x-c-codebase-compilation-pipeline-with-ulisp.md) でビルドした `ulisp/build/lua_ulisp` の逆アセンブル分析により、以下の 2 つのコード生成パターンが `.text` を合計 **約 150 KB** 膨張させていることが確認された：

1. **変数ビットシフト (`<<` / `>>`) の 6 段条件分岐展開**:
   - [lower_to_lir.scm](../../ulisp/frontend_c/lower_to_lir.scm) が非定数シフト量を `shl`/`shr`/`sar reg, %cl` の 1 命令ではなく、`& 1`, `& 2`, `& 4`, `& 8`, `& 16`, `& 32` の 6 段のビットテスト＆条件分岐（計約 35 命令・約 150 B）に展開している。Lua 5.4.7 はハッシュ表・VM ディスパッチ (`twoto`, `sizenode`, `lmod`, `luaO_ceillog2`, ビット演算命令) で変数シフトを多用するため影響が大きい。
2. **暗黙型変換連鎖による同一ゼロ拡張・符号拡張命令の重複発行 (`15,924` 命令)**:
   - `mov %eax, %eax`、`movslq %eax, %rax`、`movzbl %al, %eax` が直後に全く同じ命令として 2 回連続発行される箇所が `lua_ulisp` 全体で 15,924 命令存在する。

`%shl`/`%shr`/`%sar` のレジスタシフトカウント (`%rcx` / `%cl`) サポートと、Pass 133 / Pass 143 における連続同一 `%zext`/`%sext`/`%trunc` 畳み込みを実装する。

---

## 2. トレーサビリティ / Traceability

- 関連設計書:
  - [DSN-33-13](../../docs/designs/DSN-33-13-ulisp_typed_machine_lir_and_multi_target_backend_architecture.md)
  - [DSN-33-32](../../docs/designs/DSN-33-32-ulisp_lua_c_codebase_compilation_and_self_hosting_architecture.md)
- 関連 Issue:
  - [#925](closed/925-build-lua-5x-c-codebase-compilation-pipeline-with-ulisp.md) (Lua 5.4.7 ビルド＆バイナリサイズ分析)
  - [#933](933-eliminate-intraprocedural-label-p2align-nop-bloat-and-enable-short-jumps.md) (`.p2align 4` `nop` パディング廃止)
  - [#934](934-implement-temporary-stack-spill-dead-store-elimination-and-expr-register-forwarding.md) (一時スタックスピル DSE)
  - [#936](936-hoist-c-tu-function-stack-frame-allocation-and-omit-managed-gc-call-setup.md) (プロローグ一括フレーム確保)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [ulisp/frontend_c/lower_to_lir.scm](../../ulisp/frontend_c/lower_to_lir.scm)（変数シフトを 6 段分岐ではなく `%rcx` シフトカウントによる `%shl`/`%shr`/`%sar` 単一命令へ降格）
- [ ] [ulisp/backend/140_backend_x86_64.scm](../../ulisp/backend/140_backend_x86_64.scm) ＆ [ulisp/backend/144a_x86_assembler.scm](../../ulisp/backend/144a_x86_assembler.scm)（`shl`/`shr`/`sar reg, cl` の選択・機械語エンコード確認）
- [ ] [ulisp/lir/133_lir_peephole.scm](../../ulisp/lir/133_lir_peephole.scm) ＆ [ulisp/backend/143_backend_x86_peephole.scm](../../ulisp/backend/143_backend_x86_peephole.scm)（連続する同一 `%zext`/`%sext`/`%trunc` および `mov %eax, %eax` / `movslq %eax, %rax` / `movzbl %al, %eax` の幂等除去ルール追加）
- [ ] [ulisp/compiler.scm](../../ulisp/compiler.scm)（再生成）

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/935-optimize-variable-shift-cl-and-ext-folding`

1. `140_backend_x86_64.scm` および `144a_x86_assembler.scm`（ならびに Portable C / Reference VM）で `%shl`/`%shr`/`%sar` の第 2 オペランドに `%rcx` レジスタを受け取れることを確認・整備し、`lower_to_lir.scm` の 6 段シフト展開を単一 LIR シフト命令に置き換える。
2. Pass 133（`(%zext ty r r)` / `(%sext ty r r)` / `(%trunc ty r r)` の連続重複）および Pass 143 で同一拡張命令の連続を 1 命令に畳み込む。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] 変数シフトの 6 段分岐展開が `shl`/`shr`/`sar reg, cl` に置き換わり、連続する重複拡張命令が除去されること。
- [ ] `test_c99_int_lowering`, `compile_lua`, および全バックエンド・VM 回帰テストが 100% PASS すること。
