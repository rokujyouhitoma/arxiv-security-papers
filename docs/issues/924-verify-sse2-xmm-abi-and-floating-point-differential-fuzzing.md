---
ID: 924
種別: Feature
優先度: High
ステータス: Open (In Progress)
---

# [FEAT/ENH] Pass 140/144a/160 における SSE2 XMM 命令・SysV XMM ABI 配線と 3者差分ファジング検証 (ID: 924)

## 1. 概要 / Summary
Core Machine LIR の `f32`/`f64` 命令および SysV AMD64 ABI の XMM 引数・戻り値渡し（`xmm0`〜`xmm7`）が、Pass 140（x86-64 命令選択 ＆ レジスタ割り当て）・Pass 144a（SSE2 アセンブラエンコーディング）・Pass 160（Portable C バックエンド）・Reference VM のすべてで完全に同期動作することを確立・検証する（Phase S4 / Task T12）。

---

## 2. トレーサビリティ / Traceability
- 関連設計書:
  - [DSN-33-32 §4.4, §6.1](../designs/DSN-33-32-ulisp_lua_c_codebase_compilation_and_self_hosting_architecture.md)
  - [DSN-33-13 §3.2, §5.1, §6.2](../designs/DSN-33-13-ulisp_typed_machine_lir_and_multi_target_backend_architecture.md)
- 前提基盤（実装済・先行）:
  - `#829`: SysV ABI（[ulisp/compiler/calling_convention.scm](../../ulisp/compiler/calling_convention.scm)）
  - `#831`: C バックエンド差分ファジング（[ulisp/backend/160_backend_c.scm](../../ulisp/backend/160_backend_c.scm)）
  - `#834`: Reference VM（[ulisp/vm/lir_interpreter.scm](../../ulisp/vm/lir_interpreter.scm)）
  - `#923`: C99 浮動小数点 Sema ＆ Lowering（[[#923]](closed/923-implement-c99-floating-point-sema-and-lir-conversion-lowering.md)）
- 後続連携 Issue:
  - [[#925]](925-build-lua-5x-c-codebase-compilation-pipeline-with-ulisp.md) (`lmathlib.c` / `lvm.c`), [[#926]](926-verify-lua-5x-official-test-suite-e2e-selfhost-ci.md) (`math.lua`)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/backend/140_backend_x86_64.scm](../../ulisp/backend/140_backend_x86_64.scm) (XMM レジスタ割り当て・スピル・`xmm0-7` 引数/戻り値渡し・`libm` 呼び出し配線)
- [ ] [ulisp/backend/144a_x86_assembler.scm](../../ulisp/backend/144a_x86_assembler.scm) (SSE2 命令バイナリエンコーディング: `movsd`/`movss`/`addsd`/`subsd`/`mulsd`/`divsd`/`ucomisd`/`cvtsi2sd`/`cvttsd2si`/`cvtss2sd`/`cvtsd2ss`/`pxor`/`xorpd`)
- [ ] [ulisp/backend/160_backend_c.scm](../../ulisp/backend/160_backend_c.scm) (`f32`/`f64` 演算・`uint64_t` 変換および NaN/`-0.0` セマンティクス同期)
- [ ] [ulisp/vm/lir_interpreter.scm](../../ulisp/vm/lir_interpreter.scm) (`f32`/`f64` 命令 ＆ ビット同一実行サポート)
- [ ] `ulisp/tests/test_fuzz_xmm_float.sh` (新規: Reference VM / x86-64 ELF / Portable C バックエンド 3 者差分ファジング)
- [ ] [ulisp/Makefile](../../ulisp/Makefile) (`test_fuzz_xmm_float` ターゲットおよび `test` 集約への登録)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/924-verify-sse2-xmm-abi-and-differential-fuzzing`

### 4.1 SSE2 命令エンコーディング ＆ XMM レジスタ割り当て (`140` / `144a`)
1. **XMM レジスタファイル (`xmm0`–`xmm15`)**:
   - GPR (`rax..r15`) とは独立した浮動小数点レジスタクラスで干渉グラフ彩色・スタックスピル（8/16バイト整列）を実行。
   - `ucomisd` / `ucomiss` 後のフラグ判定においてパリティフラグ (`PF`, `setp`/`jp`) を組み合わせ、`NaN` Unordered 条件を C99 仕様と 100% 一致させる。
2. **`uint64_t` ↔ `double` 変換シーケンス**:
   - MSB ビット立上り領域（`>= 2^63`）に対し分岐または右シフト補正＋乗算加算シーケンスを生成し、`cvtsi2sdq`/`cvttsd2siq` の符号付き上限オーバーフローを回避する。

### 4.2 SysV XMM ABI ＆ 3者差分ファジング
1. **混合引数 ＆ `libm` リンク**:
   - 整数・XMM 混合呼び出しおよび 9個目以降の XMM 引数スタック渡しを配線し、外部 `-lm`（`sin`, `cos`, `sqrt`, `pow`, `floor`, `fmod`）を呼び出せるようにする。
2. **3者差分ファジング (`ulisp/tests/test_fuzz_xmm_float.sh`)**:
   - 数千パターンのランダム `f32`/`f64` 算術・比較・整数変換・構造体混合テストを生成し、Reference VM・x86-64 ネイティブ ELF・Pass 160 C バックエンドの結果（IEEE 754 生64bitハッシュ値）を突合する。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `libm`（`sin`/`cos`/`sqrt`/`pow`/`fmod`）を呼び出す C99 プログラムが ULisp で正しくビルド・実行できること。
- [ ] Reference VM・x86-64 ネイティブ ELF・Portable C バックエンドの 3 者差分ファジング（`make -C ulisp test_fuzz_xmm_float`）でビット不一致 0 件であること。
- [ ] Phase S4（浮動小数点数完全対応）の完了条件を満たすこと。
