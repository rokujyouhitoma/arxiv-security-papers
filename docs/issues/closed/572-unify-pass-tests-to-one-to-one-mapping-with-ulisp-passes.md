---
ID: 572
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT/ENH] ulisp/passes と ulisp/tests/passes の 1:1 完全対応テストスイート網羅および命名整合化 (ID: 572)

## 1. 概要 / Summary
現在、`ulisp/passes/*.scm` には 22 本のコンパイラパスが存在する一方、`ulisp/tests/passes/` には 12 本しかテストが存在せず、残りのパス（`020_macro_expander`, `030_desugar`, `040_analysis`, `050_cp0`, `070_anf`, `110_closure_convert`, `131_lir_safepoint`, `140_backend_x86_64`, `142_backend_x86_freestanding`, `150_backend_aarch64`, `160_backend_c` 等）はモノリシックな `tests/test_passes.scm` や `tests/test_backend_aarch64.scm` に分散・埋没している。
本 Issue では、Nanopass Framework の原則および品質保証標準に従い、`ulisp/passes/<pass>.scm` に対する `ulisp/tests/passes/test_<pass>.scm` の 1:1 完全対応を確立し、命名規則の統一、各パス単体テストの独立実行、および Makefile ターゲットの整理・並列実行 (`make test_passes -j`) を実現する。

---

## 2. トレーサビリティ / Traceability
- Nanopass Framework 原則 (Sarkar, Waddell, Dybvig 2004)
- DSN-33 コンパイラアーキテクチャ仕様
- Issue #553 (ULisp passes モジュール分離)
- 関連資料: [ulisp/passes/](../../ulisp/passes), [ulisp/tests/passes/](../../ulisp/tests/passes)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/tests/passes/common.scm](../../ulisp/tests/passes/common.scm) (新規: 共通テストアサーション・パイプライン部分実行ヘルパー)
- [ ] [ulisp/tests/passes/test_010_library.scm](../../ulisp/tests/passes/test_010_library.scm) (リネーム・統一)
- [ ] [ulisp/tests/passes/test_020_macro_expander.scm](../../ulisp/tests/passes/test_020_macro_expander.scm) (新規)
- [ ] [ulisp/tests/passes/test_025_top_level.scm](../../ulisp/tests/passes/test_025_top_level.scm) (リネーム・統一)
- [ ] [ulisp/tests/passes/test_030_desugar.scm](../../ulisp/tests/passes/test_030_desugar.scm) (新規)
- [ ] [ulisp/tests/passes/test_040_analysis.scm](../../ulisp/tests/passes/test_040_analysis.scm) (新規)
- [ ] [ulisp/tests/passes/test_050_cp0.scm](../../ulisp/tests/passes/test_050_cp0.scm) (新規)
- [ ] [ulisp/tests/passes/test_060_lvn.scm](../../ulisp/tests/passes/test_060_lvn.scm) (リネーム・統一)
- [ ] [ulisp/tests/passes/test_070_anf.scm](../../ulisp/tests/passes/test_070_anf.scm) (新規)
- [ ] [ulisp/tests/passes/test_080_annotator.scm](../../ulisp/tests/passes/test_080_annotator.scm) (リネーム・統一)
- [ ] [ulisp/tests/passes/test_090_rtyper.scm](../../ulisp/tests/passes/test_090_rtyper.scm) (リネーム・統一)
- [ ] [ulisp/tests/passes/test_100_contify.scm](../../ulisp/tests/passes/test_100_contify.scm) (リネーム・統一)
- [ ] [ulisp/tests/passes/test_110_closure_convert.scm](../../ulisp/tests/passes/test_110_closure_convert.scm) (新規)
- [ ] [ulisp/tests/passes/test_120_alias_escape.scm](../../ulisp/tests/passes/test_120_alias_escape.scm) (リネーム・統一)
- [ ] [ulisp/tests/passes/test_128_lir_branch_fusion.scm](../../ulisp/tests/passes/test_128_lir_branch_fusion.scm) (リネーム・統一)
- [ ] [ulisp/tests/passes/test_130_lir.scm](../../ulisp/tests/passes/test_130_lir.scm) (リネーム・統一)
- [ ] [ulisp/tests/passes/test_131_lir_safepoint.scm](../../ulisp/tests/passes/test_131_lir_safepoint.scm) (新規)
- [ ] [ulisp/tests/passes/test_132_lir_braun_ssa.scm](../../ulisp/tests/passes/test_132_lir_braun_ssa.scm) (統合・統一)
- [ ] [ulisp/tests/passes/test_140_backend_x86_64.scm](../../ulisp/tests/passes/test_140_backend_x86_64.scm) (新規)
- [ ] [ulisp/tests/passes/test_141_backend_x86_gc.scm](../../ulisp/tests/passes/test_141_backend_x86_gc.scm) (リネーム・統一)
- [ ] [ulisp/tests/passes/test_142_backend_x86_freestanding.scm](../../ulisp/tests/passes/test_142_backend_x86_freestanding.scm) (新規)
- [ ] [ulisp/tests/passes/test_150_backend_aarch64.scm](../../ulisp/tests/passes/test_150_backend_aarch64.scm) (移動・統一)
- [ ] [ulisp/tests/passes/test_160_backend_c.scm](../../ulisp/tests/passes/test_160_backend_c.scm) (新規)
- [ ] [ulisp/Makefile](../../ulisp/Makefile) (パステスト自動ディスカバリとターゲット統合)
- [ ] [ulisp/test.sh](../../ulisp/test.sh) (単体パステスト実行ステップ更新)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/572-unify-pass-tests-to-one-to-one-mapping-with-ulisp-passes`

1. **テスト共通フレームワークの確立**:
   - `ulisp/tests/passes/common.scm` を配置し、アサーション (`assert-equal`, `assert-true`)、テスト結果集計、およびパイプライン部分実行ヘルパー (`run-pass`, `run-passes-up-to`) を提供。
2. **既存テストのリネームと 1:1 対応化**:
   - `test_library.scm` -> `test_010_library.scm`
   - `test_toplevel_direct_call.scm` -> `test_025_top_level.scm`
   - `test_lvn.scm` -> `test_060_lvn.scm`
   - `test_annotator.scm` -> `test_080_annotator.scm`
   - `test_rtyper.scm` -> `test_090_rtyper.scm`
   - `test_contify.scm` -> `test_100_contify.scm`
   - `test_alias_escape.scm` -> `test_120_alias_escape.scm`
   - `test_branch_fusion.scm` -> `test_128_lir_branch_fusion.scm`
   - `test_lir.scm` -> `test_130_lir.scm`
   - `test_loop_register_allocation.scm` & `test_inplace_shuffle.scm` -> `test_132_lir_braun_ssa.scm` に統合
   - `test_stackmap.scm` -> `test_141_backend_x86_gc.scm`
   - `tests/test_backend_aarch64.scm` -> `tests/passes/test_150_backend_aarch64.scm` に移動
3. **未テストパスの単体テスト抽出・新規実装**:
   - `test_020_macro_expander.scm` (`syntax-rules` パターンマッチ・マクロ展開)
   - `test_030_desugar.scm` (`cond`, `case`, `let*`, `let-values`, `and`, `or`, `parameterize`, `guard` 展開)
   - `test_040_analysis.scm` (スコープ解析、自由変数 `free-vars`)
   - `test_050_cp0.scm` (算術定数畳み込み、真偽値簡約、デッドブランチ削除)
   - `test_070_anf.scm` (ネスト式のアトミック化、let バインド化)
   - `test_110_closure_convert.scm` (クロージャ変換、自由変数のキャプチャ)
   - `test_131_lir_safepoint.scm` (GC セーフポイント挿入とポーリング)
   - `test_140_backend_x86_64.scm` (x86-64 アセンブリ出力形式、即値・レジスタ・スタックオペランド)
   - `test_142_backend_x86_freestanding.scm` (freestanding エントリポイント・exit システムコール)
   - `test_160_backend_c.scm` (C コード出力と基本構文トランスレート)
4. **Makefile および test.sh の更新**:
   - `make test_passes` で `tests/passes/test_*.scm` 全 22 ファイルを自動走査・一括実行。
   - `test.sh` を新構成に適合させ、全テストが 100% PASS することを確認。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `ulisp/passes/` 内の 22 ファイルすべてに対し、`ulisp/tests/passes/test_<pass_basename>.scm` が 1:1 で過不足なく存在すること
- [x] 各単体テストが独立して実行可能であり、すべて PASS すること
- [x] `make test_passes` で 22 パスすべての単体テストが一括実行され、0 failures で完了すること
- [x] `make test` 全体テストスイートおよび言語機能テストがすべて PASS すること


