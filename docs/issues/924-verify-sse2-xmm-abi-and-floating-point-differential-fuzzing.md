---
ID: 924
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] Pass 140/144a/160 における SSE2 XMM 命令・SysV XMM ABI 配線と 3者差分ファジング検証 (ID: 924)

## 1. 概要 / Summary
Core Machine LIR の `f32`/`f64` 命令および SysV AMD64 ABI の XMM 引数・戻り値渡し（`xmm0`〜`xmm7`）が、Pass 140（x86-64 命令選択 ＆ レジスタ割り当て）・Pass 144a（SSE2 アセンブラエンコーディング）・Pass 160（Portable C バックエンド）・Reference VM のすべてで完全に同期動作することを確立・検証する（Step S4 / T12）。

---

## 2. トレーサビリティ / Traceability
- 関連設計書:
  - [DSN-33-32 §4.4, §6.1](../designs/DSN-33-32-ulisp_lua_c_codebase_compilation_and_self_hosting_architecture.md)
  - [DSN-33-13 §3.2, §5.1, §6.2](../designs/DSN-33-13-ulisp_typed_machine_lir_and_multi_target_backend_architecture.md)
- 前提基盤 Issue: #829 (SysV ABI), #831 (C バックエンド差分ファジング), #834 (Reference VM), #923

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/backend/140_backend_x86_64.scm](../../ulisp/backend/140_backend_x86_64.scm) (XMM レジスタ割り当て・`movsd`/`movss`/`ucomisd`/`cvtsi2sd`/`cvttsd2si`・`xmm0-7` 引数渡し)
- [ ] [ulisp/backend/144a_x86_assembler.scm](../../ulisp/backend/144a_x86_assembler.scm) (SSE2 命令エンコーディング網羅)
- [ ] [ulisp/backend/160_backend_c.scm](../../ulisp/backend/160_backend_c.scm) (`f32`/`f64` 演算および `-0.0`/NaN セマンティクス同期)
- [ ] `ulisp/tests/test_fuzz_xmm_float.sh` (新規: Reference VM / x86-64 / C バックエンド 3 者差分ファジング)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/924-verify-sse2-xmm-abi-and-differential-fuzzing`

1. Pass 140/144a において `xmm0`〜`xmm15` に対するグラフ彩色レジスタ割り当て・XMM スピルコード生成、および `uint64_t` $\leftrightarrow$ `double` の高速 x86-64 変換シーケンスを完全整備する。
2. SysV ABI における整数＋浮動小数点混合引数（8個以上の XMM 引数によるスタックスピル、および SSE クラス構造体受け渡し）を検証し、`libm`（`sin`, `cos`, `pow`, `floor`, `fmod`）とのリンク呼び出しを通す。
3. Reference VM（[lir_interpreter.scm](../../ulisp/vm/lir_interpreter.scm)）、x86-64 ネイティブ ELF、Portable C バックエンドの 3 者間で数千件のランダム浮動小数点式・混在構造体テストを差分ファジングし、ビット一致（`memcmp` 相当）をアサートする。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `libm`（`sin`/`cos`/`sqrt`/`pow` 等）を呼び出す C99 プログラムが ULisp で正しくビルド・実行できること。
- [ ] Reference VM・x86-64・C バックエンドの 3 者差分ファジングで不一致 0 件であること。
- [ ] Phase S4（浮動小数点数完全対応）の完了条件を満たすこと。
