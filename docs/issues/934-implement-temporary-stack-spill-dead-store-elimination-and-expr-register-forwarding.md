---
ID: 934
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] C99 式評価の一時スタックスピルに対するデッドストア除去 (DSE) とレジスタ直接受け渡しによるコードサイズ削減 (ID: 934)

## 1. 概要 / Summary

[Issue #925](closed/925-build-lua-5x-c-codebase-compilation-pipeline-with-ulisp.md) で生成した `ulisp/build/lua_ulisp` の `.text` セクション（322,305 命令 / 934,881 B）のうち、**19.3% にあたる 62,176 命令（約 310 KB）が `-offset(%rsp)` に対するスタックメモリ読み書き**である。

現在 [lower_to_lir.scm](../../ulisp/frontend_c/lower_to_lir.scm) は部分式を評価するたびに一時スタックスロットへ `(%store %rsp off %rax)` し、Pass 133 ([133_lir_peephole.scm](../../ulisp/lir/133_lir_peephole.scm)) の `rule-lir-store-load-forward` が後続の `(%load %rcx %rsp off)` を `(%mov %rcx %rax)` へ置換した後も、**誰からも参照されなくなった一時スタックスロットへのデッドストア `(%store %rsp off %rax)` がそのまま残存**している。基本ブロック内・関数内の一時スピルスロットに対するデッドストア除去 (Dead Store Elimination: DSE) および単純二項演算での一時スピル省略を実装し、`.text` サイズを約 200〜250 KB 削減する。

---

## 2. トレーサビリティ / Traceability

- 関連設計書:
  - [DSN-33-12](../../docs/designs/DSN-33-12-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md)
  - [DSN-33-13](../../docs/designs/DSN-33-13-ulisp_typed_machine_lir_and_multi_target_backend_architecture.md)
  - [DSN-33-32](../../docs/designs/DSN-33-32-ulisp_lua_c_codebase_compilation_and_self_hosting_architecture.md)
- 関連 Issue:
  - [#925](closed/925-build-lua-5x-c-codebase-compilation-pipeline-with-ulisp.md) (Lua 5.4.7 ビルド＆バイナリサイズ分析)
  - [#927](927-implement-c-header-sbi-pch-and-iterative-mem2reg-optimization.md) (C ヘッダ `.sbi` PCH ＆ 反復 mem2reg 最適化)
  - [#933](933-eliminate-intraprocedural-label-p2align-nop-bloat-and-enable-short-jumps.md) (`.p2align 4` `nop` パディング廃止)
  - [#935](935-optimize-variable-bit-shift-cl-codegen-and-redundant-sign-zero-extension-folding.md) (変数シフト `%cl` 化 ＆ 冗長拡張畳み込み)
  - [#936](936-hoist-c-tu-function-stack-frame-allocation-and-omit-managed-gc-call-setup.md) (プロローグ一括フレーム確保)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [ulisp/frontend_c/lower_to_lir.scm](../../ulisp/frontend_c/lower_to_lir.scm)（副作用のない単純オペランド・定数・レジスタ結果に対する不要な一時スタックスピル抑制）
- [ ] [ulisp/lir/133_lir_peephole.scm](../../ulisp/lir/133_lir_peephole.scm) ＆ [ulisp/compiler/nanopass_meta.scm](../../ulisp/compiler/nanopass_meta.scm)（エスケープしない一時スタックスロット `%rsp + off` に対する Store-Load Forwarding 後の Dead Store Elimination）
- [ ] [ulisp/compiler.scm](../../ulisp/compiler.scm)（再生成）

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/934-implement-temp-stack-spill-dse`

1. `lower_to_lir.scm` で確保される一時評価スロット（アドレス取得 `&` の対象になり得ない一時スロット領域）を識別可能にするか、関数全体でエスケープしないスタックスロット集合上で「上書きされる前または関数終了までに一度も `%load` / `%load-typed` されない `%store`」を安全に除去する DSE パスを追加する。
2. `setjmp` 呼び出しを含む関数（`returns_twice` スピル保護対象）ではローカル変数スピルを維持し、純粋な式評価一時スロットのみ安全に消去する。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] Store-Load Forwarding 後に残存していた一時スタックスロットへの未参照 `%store` が除去され、`lua_ulisp` の `%rsp` メモリアクセス命令数が 50% 以上削減されること。
- [ ] `test_c99_setjmp_longjmp`, `compile_lua`, および全 C99 / LIR 回帰テストが 100% PASS すること。
