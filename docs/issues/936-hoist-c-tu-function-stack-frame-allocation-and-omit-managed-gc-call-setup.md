---
ID: 936
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] c-tu モードにおける関数プロローグ一括スタックフレーム確保と非 GC 呼び出し時の不要 %rsp シフト・xor r10 廃止 (ID: 936)

## 1. 概要 / Summary

[Issue #925](closed/925-build-lua-5x-c-codebase-compilation-pipeline-with-ulisp.md) でビルドした `ulisp/build/lua_ulisp` の `.text` セクションには、関数呼び出しサイトごとに毎回発行される `sub $N, %rsp` / `xor %r10, %r10` / `call` / `add $N, %rsp` が **8,520 命令（約 55 KB）** 含まれている。

現行の [140_backend_x86_64.scm](../../ulisp/backend/140_backend_x86_64.scm) はローカル変数を `%rsp` 負オフセット領域に配置し、各 `%direct-call` / `%c-call` / `%call-indirect` の直前で `sub rsp, frame_shift` と Managed GC 用の `xor r10, r10` を出力し、直後に `add rsp, frame_shift` で戻している。`c-tu` モードにおいて：
1. Managed GC 専用レジスタ初期化である `xor r10, r10` を省略する。
2. 関数のプロローグ (`sub rsp, frame_size`) とエピローグ (`add rsp, frame_size`) で 16 バイト境界整合済みのスタックフレームを 1 回だけ確保・解放する方式へ移行することで、全コールサイト前後の `sub`/`add %rsp` を不要にし、コードサイズ削減（約 55 KB）と実行速度・デバッガ (`gdb`) スタックトレース精度を向上させる。

---

## 2. トレーサビリティ / Traceability

- 関連設計書:
  - [DSN-33-13](../../docs/designs/DSN-33-13-ulisp_typed_machine_lir_and_multi_target_backend_architecture.md)
  - [DSN-33-32](../../docs/designs/DSN-33-32-ulisp_lua_c_codebase_compilation_and_self_hosting_architecture.md)
- 関連 Issue:
  - [#922](closed/922-implement-setjmp-longjmp-inline-asm-and-stack-spill-protection.md) (`setjmp`/`longjmp` スタックフレーム整合)
  - [#925](closed/925-build-lua-5x-c-codebase-compilation-pipeline-with-ulisp.md) (Lua 5.4.7 ビルド＆バイナリサイズ分析)
  - [#933](933-eliminate-intraprocedural-label-p2align-nop-bloat-and-enable-short-jumps.md) (`.p2align 4` `nop` パディング廃止)
  - [#934](934-implement-temporary-stack-spill-dead-store-elimination-and-expr-register-forwarding.md) (一時スタックスピル DSE)
  - [#935](935-optimize-variable-bit-shift-cl-codegen-and-redundant-sign-zero-extension-folding.md) (変数シフト `%cl` 化 ＆ 冗長拡張畳み込み)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [ulisp/backend/140_backend_x86_64.scm](../../ulisp/backend/140_backend_x86_64.scm)（`c-tu` モードでの `xor r10, r10` 抑制およびプロローグ/エピローグ一括フレーム確保）
- [ ] [ulisp/frontend_c/lower_to_lir.scm](../../ulisp/frontend_c/lower_to_lir.scm)（フレームサイズ・コールサイト `frame-shift` および `setjmp`/`va_start` スタックオフセットとの整合）
- [ ] [ulisp/compiler.scm](../../ulisp/compiler.scm)（再生成）

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/936-hoist-c-tu-stack-frame-and-omit-xor-r10`

1. 第一段階として、`c-tu` モードにおける `%direct-call` / `%c-call` / `%call-indirect` / `%direct-jump` の不要な `xor r10, r10` を抑制する。
2. 第二段階として、`va_start`（親フレーム引数領域 `[rsp + 8]` 参照）および `__ulisp_setjmp` との `%rsp` 相対オフセット整合を保ちながら、関数プロローグ/エピローグでの一括フレーム確保へ移行する。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `c-tu` モードで不要な `xor r10, r10` および各コールサイト毎の重複 `%rsp` 加減算が削減されること。
- [ ] `test_c99_stdarg`, `test_c99_setjmp_longjmp`, `compile_lua`, および全 C99 回帰テストが 100% PASS すること。
