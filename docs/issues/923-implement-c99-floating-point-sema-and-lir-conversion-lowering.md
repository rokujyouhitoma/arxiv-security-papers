---
ID: 923
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] C99 浮動小数点型 (`double`/`float`) の意味解析および IEEE 754 / LIR 型変換 Lowering の実装 (ID: 923)

## 1. 概要 / Summary
Lua 5.x のデフォルト数値型 `lua_Number`（`double` / `f64`）および単精度 `float`（`f32`）をサポートするため、C99 フロントエンドに浮動小数点リテラル解析（10進・16進指数表記、Issue #832 `ieee754.scm` 連携）、通常の算術変換（整数 $\leftrightarrow$ 浮動小数点）、および Core LIR の `f32`/`f64` 命令・変換演算への Lowering を実装する（Step S4 / T11）。

---

## 2. トレーサビリティ / Traceability
- 関連設計書:
  - [DSN-33-32 §2.1, §4.4, §6.1](../designs/DSN-33-32-ulisp_lua_c_codebase_compilation_and_self_hosting_architecture.md)
  - [DSN-33-11 §3.4, §4.2](../designs/DSN-33-11-ulisp_multilingual_frontend_and_ctfe_architecture.md)
  - [DSN-33-13 §2.1](../designs/DSN-33-13-ulisp_typed_machine_lir_and_multi_target_backend_architecture.md)
- 前提基盤 Issue: #826 (Typed LIR `f32`/`f64`), #832 (IEEE 754 ライブラリ), #916, #918

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] `ulisp/frontend_c/lexer.scm` / `sema.scm` (`float`/`double` リテラル変換と算術昇格規則)
- [ ] `ulisp/frontend_c/lower_to_lir.scm` (`.rodata` 定数配置、`%fadd`/`%fsub`/`%fmul`/`%fdiv`/`%fcmp`、`%sitofp`/`%fptosi`/`%uitofp`/`%fptoui`/`%fpext`/`%fptrunc`)
- [ ] `ulisp/tests/test_c99_floating_point.scm` (新規: 浮動小数点リテラル・符号なし整数変換・NaN/Inf 比較テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/923-implement-c99-floating-point-sema-and-lowering`

1. `ieee754.scm` を利用し、ホスト処理系に依存しない決定論的アルゴリズムで C ソースの 10進・16進浮動小数点リテラルを正確な IEEE 754 32bit/64bit パターンへ変換する。
2. `sema.scm` に `float`/`double` を含む通常の算術変換および `double` $\leftrightarrow$ `int64_t`/`uint64_t` 間の明示的・暗黙的キャストノードを実装する。
3. `lower_to_lir.scm` で浮動小数点定数を `.rodata`（または即値ビットパターン経由ロード）に配置し、比較演算（`==`, `!=`, `<`, `<=`, `>`, `>=`）における NaN の IEEE 754 規約（`NaN != NaN` が真、`<` 等が偽）と `-0.0 == 0.0` を正確に Core LIR へ降格する。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 16進浮動小数点リテラル（`0x1.8p+1` 等）を含む `float`/`double` 演算が IEEE 754 厳密ビット一致で計算されること。
- [ ] `uint64_t` $\leftrightarrow$ `double` および `int64_t` $\leftrightarrow$ `double` の境界値（$2^{63}$ 前後）変換が正しく機能すること。
- [ ] NaN, `±Inf`, `-0.0` を含む比較式が C99 / IEEE 754 仕様通り評価されること。
