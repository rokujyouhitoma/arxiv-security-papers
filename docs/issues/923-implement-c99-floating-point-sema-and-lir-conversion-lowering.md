---
ID: 923
種別: Feature
優先度: High
ステータス: Open (In Progress)
---

# [FEAT/ENH] C99 浮動小数点型 (`double`/`float`) の意味解析および IEEE 754 / LIR 型変換 Lowering の実装 (ID: 923)

## 1. 概要 / Summary
Lua 5.x のデフォルト数値型 `lua_Number`（`double` / `f64`）および単精度 `float`（`f32`）をサポートするため、C99 フロントエンドに IEEE 754 ビットパターン変換（`#832` [ieee754.scm](../../ulisp/lib/ieee754.scm) 連携）、浮動小数点を含む通常の算術変換（整数 ↔ `float`/`double`、および単精度 ↔ 倍精度）、ならびに Core Machine LIR の `f32`/`f64` 命令・変換演算への Lowering を実装する（Phase S4 / Task T11）。

---

## 2. トレーサビリティ / Traceability
- 関連設計書:
  - [DSN-33-32 §2.1, §4.4, §6.1](../designs/DSN-33-32-ulisp_lua_c_codebase_compilation_and_self_hosting_architecture.md)
  - [DSN-33-11 §3.4, §4.2](../designs/DSN-33-11-ulisp_multilingual_frontend_and_ctfe_architecture.md)
  - [DSN-33-13 §2.1](../designs/DSN-33-13-ulisp_typed_machine_lir_and_multi_target_backend_architecture.md)
- 前提基盤（実装済・先行）:
  - `#826`: Typed Machine LIR `f32`/`f64`（[ulisp/lir/lir_lang.scm](../../ulisp/lir/lir_lang.scm)）
  - `#832`: IEEE 754 ライブラリ（[ulisp/lib/ieee754.scm](../../ulisp/lib/ieee754.scm)）
  - `#913`: C99 Lexer — 10進/16進浮動小数点リテラル解析済み（[ulisp/frontend_c/lexer.scm](../../ulisp/frontend_c/lexer.scm), [[#913]](closed/913-implement-c99-lexer-and-token-stream-with-source-span.md)）
  - `#916`: C99 Sema Core ＆ Lowering（[[#916]](916-implement-c99-sema-core-and-integer-subset-lir-lowering.md)）
  - `#918`: 複合型メモリレイアウト（[[#918]](918-implement-c99-struct-union-enum-bitfield-sysv-layout.md)）
- 後続連携 Issue:
  - [[#924]](924-verify-sse2-xmm-abi-and-floating-point-differential-fuzzing.md) (SSE2 XMM 命令 ＆ 差分ファジング), [[#925]](925-build-lua-5x-c-codebase-compilation-pipeline-with-ulisp.md) (`lmathlib.c` / `lua_Number`)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] `ulisp/frontend_c/c_lang.scm` / `ulisp/frontend_c/sema.scm` (`f32`/`f64` 型・通常算術変換・整数 ↔ 浮動小数点キャスト規則)
- [ ] `ulisp/frontend_c/lower_to_lir.scm` (`.rodata` IEEE 754 32/64bit 定数配置、`%fadd`/`%fsub`/`%fmul`/`%fdiv`/`%fneg`/`%fcmp-*`/`%sitofp`/`%uitofp`/`%fptosi`/`%fptoui`/`%fpext`/`%fptrunc`)
- [ ] [ulisp/lib/ieee754.scm](../../ulisp/lib/ieee754.scm) (必要に応じ C99 リテラル精度変換ヘルパ連携確認)
- [ ] `ulisp/tests/test_c99_floating_point.scm` (新規: 10/16進浮動小数点リテラル・`uint64_t` 境界変換・NaN/±Inf/-0.0 比較テスト)
- [ ] [ulisp/Makefile](../../ulisp/Makefile) (`test_c99_floating_point` ターゲットおよび `test` 集約への登録)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/923-implement-c99-floating-point-sema-and-lowering`

### 4.1 決定論的 IEEE 754 定数変換 ＆ 通常算術変換
1. **ホスト非依存ビットエンコーディング (`ieee754.scm` 連携)**:
   - 10進・16進浮動小数点リテラル（`0x1.8p+1`, `3.14f` 等）を `float64->bits` / `float32->bits` により正確な IEEE 754 32bit/64bit ビット列へ確定し、`.rodata`（または即値ビットパターン）として配置する。
2. **型昇格と変換規則 (`sema.scm`)**:
   - `double` 混在時は他方を `f64` へ昇格、`float` 混在時は整数または単精度規則に従い変換。
   - `double`/`float` ↔ `int8..int64` / `uint8..uint64` / `_Bool` の暗黙・明示変換に対し適切な Core LIR 変換ノード（`%sitofp`, `%uitofp`, `%fptosi`, `%fptoui`, `%fpext`, `%fptrunc`, ゼロ比較 `(%fcmp-une x 0.0)`）を生成。

### 4.2 NaN / Inf / 負ゼロのセマンティクス ＆ 診断
1. **順序比較と非順序比較 (`%fcmp-*`)**:
   - `==`, `<`, `<=`, `>`, `>=` は Ordered 比較（`NaN` を含む場合すべて偽）、`!=` は Unordered 許容比較（`NaN != NaN` が真、`-0.0 == 0.0` が真）として正確に降格。
2. **診断コード (`diagnostic.scm` #833)**:
   - `"C99-FP-001"`（浮動小数点型へのビット演算 `&`/`|`/`^`/`~`/`<<`/`>>`/`%` 適用エラー）、`"C99-FP-002"`（無効な浮動小数点定数リテラルまたは範囲外変換）。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 16進浮動小数点リテラル（`0x1.8p+1` 等）を含む `float`/`double` 演算が IEEE 754 厳密ビット一致で計算・降格されること。
- [ ] `uint64_t` ↔ `double` および `int64_t` ↔ `double` の境界値（$2^{63}$ 前後）変換が正しく機能すること。
- [ ] `NaN`, `±Inf`, `-0.0` を含む比較式が C99 / IEEE 754 仕様通り Reference VM 上で評価され、`make -C ulisp test_c99_floating_point` が全件 PASS すること。
