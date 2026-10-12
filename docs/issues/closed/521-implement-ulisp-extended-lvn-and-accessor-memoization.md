---
ID: 521
種別: Feature
優先度: High
ステータス: Closed (Completed)
担当エージェント:
  - Project Manager (PM) (進行統括・品質ゲート判定)
  - IT Specialist (Programming Languages & Compilers / PLC) (Pass 03b Extended LVN 実装・Nanopass 結合・GC スタックマップ上限整合)
  - Software Quality Assurance Specialist (SQA) (単体テスト 25件・全パス 127件・定量測定検証)
---

# [FEAT/ENH] 拡張局所値番号付け (Extended LVN) による不変アクセサメモ化と代数的等価性最適化の実装 (ID: 521)

## 1. 概要 / Summary
コーネル大学 CS 6120 (Lesson 3) で扱われる局所値番号付け (Local Value Numbering: LVN) フレームワークを拡張し、ULisp の Nanopass コンパイラへ導入した。
単一基本ブロック内において、定数畳み込み、コピー伝播、共通部分式除去 (CSE) を単一ハッシュテーブルで統合するとともに、Scheme 固有の意味論を組み込んだ。不変ペアアクセサ (`car`/`cdr`) のメモ化による冗長なメモリロード命令の完全消去、ペアコンストラクタ簡約 (`(car (cons x y)) -> x`)、型述語 (`fixnum?` 等) の重複検査の真偽値畳み込み、および可換演算子 (`+`, `*`) の引数順序正規化と恒等元除去 (`(+ x 0) -> x`, `(* x 1) -> x`, `(* x 0) -> 0`, `(- x x) -> 0`) を実現し、生成機械語の冗長計算を静的に刈り込んだ。

---

## 2. トレーサビリティ / Traceability
- **関連設計書**:
  - [DSN-33: ULISP 包括設計仕様書 (第8.2節 Extended LVN)](../../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
  - [DSN-35: Continuous Benchmarking Framework](../../designs/DSN-35-ilisp_ulisp_aot_jit_continuous_benchmarking_framework.md)
- **関連先行 Issue**:
  - [Issue #499: ULisp コンパイラへの ANF 正規化および CP0 最適化パスの実装](./499-implement-ulisp-anf-and-cp0-optimizations.md)
  - [Issue #518: ULisp 低水準IR具象化器 (S-RTyper) とアンボクシングによるタグ検査完全消去](./518-implement-ulisp-srtyper-unboxing-and-typed-lir.md)
  - [Issue #519: アンボクシング混在環境向け Exact GC スタックマップ (Stackmap) 自動生成機構の実装](./519-implement-ulisp-exact-gc-stackmap-generation.md)
  - [Issue #520: 静的型知識に基づく JIT ガード命令事前消去 (Guard Elimination) と OSR 復元コード合成の実装](./520-integrate-ulisp-jit-guard-elimination-and-osr.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/passes/03b_lvn.scm](../../../ulisp/passes/03b_lvn.scm) (新規作成: 拡張 LVN 最適化パス `Pass 03b`)
- [x] [ulisp/passes/00_helpers.scm](../../../ulisp/passes/00_helpers.scm) (LVN テーブル操作および代数的同値性ヘルパー群、`cons` の純粋性登録)
- [x] [ulisp/passes/03_cp0.scm](../../../ulisp/passes/03_cp0.scm) (重複ヘルパーのリファクタリング・共有化)
- [x] [ulisp/passes/06_lir.scm](../../../ulisp/passes/06_lir.scm) (スタックマップビットマップ蓄積の 60-bit 上限ガード)
- [x] [ulisp/passes/08_driver.scm](../../../ulisp/passes/08_driver.scm) (パイプライン Pass 03 CP0 と Pass 04 ANF 間への Pass 03b 結合)
- [x] [ulisp/lib/gc.scm](../../../ulisp/lib/gc.scm) (60スロット超過フレームの安全な保守的フォールバックスキャン追加)
- [x] [ulisp/Makefile](../../../ulisp/Makefile) (PASSES_LIB への追加および `test_lvn` ターゲット新設)
- [x] [ulisp/tests/passes/test_lvn.scm](../../../ulisp/tests/passes/test_lvn.scm) (新規作成: LVN 全機能群単体テストスイート 25件 100% PASS)
- [x] [ulisp/tests/test_passes.scm](../../../ulisp/tests/test_passes.scm) (全 Nanopass 単体テストへの Pass 03b 統合 127/127 PASS)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/521-ulisp-extended-lvn-and-accessor-memoization`

1. **LVN ハッシュテーブルと値番号割当機構の実装**:
   - 基本ブロック・スコープ内の各式に対して一意の値番号 (Value Number: VN) を割り当て、同一の計算タプル `(op val1 val2 ...)` をハッシュ化して先行変数の参照へ置換。
2. **言語意味論拡張ポイントの実装**:
   - **不変ペアアクセサメモ化**: `(car p)` / `(cdr p)` に対し、`p` が同一値番号かつブロック内に破壊的代入 (`set-car!`, `set-cdr!`) が存在しない場合、同一値番号を割り当ててロード命令を消去。
   - **ペアコンストラクタ簡約**: `(cons a b)` の生成情報 `('pair vn-a vn-b)` を記録し、直後の `(car (cons a b))` を `a`、`(cdr (cons a b))` を `b` へ直接値縮小。
   - **型述語検査の畳み込み**: 同一値番号に対して `(fixnum? x)` 等の成功が支配している場合、または定数・コンストラクタが既知の場合、後続の型検査を即座に `#t` / `#f` 定数へ畳み込み。
   - **代数的正規化**: 可換演算 (`+`, `*`) の引数を値番号の昇順にソートし、`(+ x 0) -> x`、`(* x 1) -> x`、`(* x 0) -> 0`、`(- x 0) -> x`、`(- x x) -> 0`、`(= x x) -> #t`、`(eq? x x) -> #t` を簡約。
3. **Nanopass パイプラインへの統合**:
   - Pass 03 (CP0) と Pass 04 (ANF) の間に `Pass 03b: LVN` として直列結合。
4. **巨大フレームにおける GC スタックマップの健全性保護**:
   - 巨大なコンパイラフレーム（300スロット超）において、64-bit 整数を超過したビットマスクによる bignum 切り捨て・ルート消失を防止するため、スタックマップビットマップの蓄積上限を 60-bit に制限し、60スロット以降は `lib/gc.scm` にて保守的スキャンを適用する二重安全網を敷設。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] 単一ブロック内の同一ペアに対する連続アクセサ呼び出し（`car`, `cdr`）で、重複メモリアクセス命令が 0 件に削減されること。
- [x] 算術演算の自明な恒等式展開（`(+ x 0)` 等）および重複型述語検査が静的に消去されること。
- [x] `make -C ulisp test_lvn` (25/25 PASS), `make -C ulisp test_passes` (127/127 PASS), `make -C ulisp test_c` (42/42 PASS), `pytest tests/test_bare_metal_ulisp.py` (3/3 PASS) が 100% PASS すること。

---

## 6. 計測結果 / Measurement Results (Baseline vs Post-Optimization)

### 6.1 不変ペアアクセサおよび代数的恒等式の冗長性削減 (Extended LVN 最適化効果)

| 評価項目 | 事前 (Baseline: Pass 03 CP0 のみ) | 事後 (Post-Optimization: Pass 03b Extended LVN) | 削減率 / 改善効果 |
| :--- | :---: | :---: | :---: |
| **連続同一ペアアクセサ (`car`/`cdr`) ロード** | 2 回のメモリアクセス命令 | **1 回 (Let 導入と変数共有による重複ロード 0 件)** | **-50.0% (重複ロード 100% 消去)** |
| **ペアコンストラクタ簡約 (`(car (cons x y))`)** | ペアヒープ割当 + メモリアクセス | **`x` への直接値簡約 (メモリアクセス 0 件)** | **-100.0% (アロケーション・ロード完全消去)** |
| **代数的恒等式 (`(+ x 0)`, `(* x 1)`)** | 冗長な算術命令の生成 | **`x` への直接縮小 (命令数 0 件)** | **-100.0% (恒等演算完全消去)** |
| **零元吸収 (`(* x 0)`)** | 冗長な乗算命令の生成 | **`0` 定数への即時畳み込み** | **-100.0% (乗算命令完全消去)** |
| **自己減算・反射等値 (`(- x x)`, `(= x x)`)** | 減算命令 / 比較分岐命令の生成 | **`0` / `#t` 定数への即時畳み込み** | **-100.0% (演算・分岐完全消去)** |
| **支配領域内型述語重複検査 (`(fixnum? x)`)** | 複数回のタグマスク比較・分岐 | **`#t` 定数への即時畳み込み (重複検査 0 件)** | **-100.0% (重複ガード完全消去)** |

### 6.2 単体テストおよびシステムテスト全件検証

| テストスイート | 事前 (Baseline) | 事後 (Post-Optimization) | 状態 |
| :--- | :---: | :---: | :---: |
| `test_lvn` (新規 Extended LVN 単体テスト) | 未実装 | **25 / 25 PASS** | **新規 PASS (100%)** |
| `test_passes` (全 Nanopass 1〜7c テスト) | 119 / 119 PASS | **127 / 127 PASS** | **+8件 拡充 (100% PASS)** |
| `test_rtyper` (S-RTyper 低水準IR具象化) | 19 / 19 PASS | **19 / 19 PASS** | **100% PASS** |
| `test_stackmap` (GC スタックマップ) | 17 / 17 PASS | **17 / 17 PASS** | **100% PASS** |
| `test_aarch64` (AArch64 バックエンド) | 13 / 13 PASS | **13 / 13 PASS** | **100% PASS** |
| `test_c` (Portable C バックエンド) | 42 / 42 PASS | **42 / 42 PASS** | **100% PASS** |
| `test_jit` (内因的メタトレーシング JIT) | 112 / 112 PASS | **112 / 112 PASS** | **100% PASS** |
| `test_bare_metal_ulisp.py` (ベアメタル x86-64) | 3 / 3 PASS | **3 / 3 PASS** | **100% PASS** |
