---
ID: 553
種別: Refactor
優先度: High
ステータス: Open (New)
---

# [REFACTOR] ULisp コンパイラアーキテクチャのモジュール分離（compiler基盤切り出し・3桁ナンバリング・LIRパス解体） (ID: 553)

## 1. 概要 / Summary

現在の `ulisp/passes/*.scm` は、新機能や最適化パスの段階的追加に伴い以下のアーキテクチャ上の課題を抱えている：
1. **パスと基盤の混在**: `00_helpers.scm`（コンパイラ内部ユーティリティ）や `08_driver.scm`（パイプライン起動）が、純粋な変換パスと同列に置かれている。
2. **実行順序と命名の乖離**: `00a`, `00b`, `03b`, `04b`, `04c`, `05b`, `06b` などの枝番が乱立し、Makefile の実際の結合順序とファイル名アルファベット順が不一致になっている（例: `05b_rtyper` が `04c_contify` より前、`06b_alias_escape` が `06_lir` より前）。
3. **単一ファイルの極端な肥大化**: `06_lir.scm` だけが 2,158 行（93KB）に達し、命令選択、GC Safepoint スタックマップ、Braun SSA / CFG エンジン（300行）が1ファイルに同居して可読性を著しく損ねている。

本 Issue では以下を実施し、ULisp のコンパイラコードベースを美しく再編成する：
- **案B（基盤切り出し）**: `ulisp/compiler/` ディレクトリを新設し、コンパイラ専用ユーティリティ（`primitives.scm`, `helpers.scm`）およびドライバ（`driver.scm`）を分離。
- **提案1（3桁ナンバリング）**: `ulisp/passes/` 内の純粋な Nanopass 群をパイプライン適用順序と 100% 一致する 3 桁番号プレフィックス（`010_`, `020_`, ...）に改名。
- **提案2（LIR解体）**: `06_lir.scm` を `130_lir.scm`、`131_lir_safepoint.scm`、`132_lir_braun_ssa.scm` に責務分割。

---

## 2. トレーサビリティ / Traceability
- 関連資料:
  - [DSN-33: ULisp Underlying x86 Native AOT Compiler Architecture Specification](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
  - [ulisp/docs/lir_specification.md](../../ulisp/docs/lir_specification.md)
  - [ulisp/docs/pipeline_architecture.md](../../ulisp/docs/pipeline_architecture.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/compiler/](../../ulisp/compiler/)（新設ディレクトリ）
  - `primitives.scm`（コンパイラプリミティブ分類・述語定義）
  - `helpers.scm`（一意シンボル/ラベル生成、集合演算、AST共通関数）
  - `driver.scm`（旧 `passes/08_driver.scm`）
- [ ] [ulisp/passes/](../../ulisp/passes/)（リネーム・分割）
  - `010_library.scm`（旧 `00a_library.scm`）
  - `020_macro_expander.scm`（旧 `00b_macro_expander.scm`）
  - `030_desugar.scm`（旧 `01_desugar.scm`）
  - `040_analysis.scm`（旧 `02_analysis.scm`）
  - `050_cp0.scm`（旧 `03_cp0.scm`）
  - `060_lvn.scm`（旧 `03b_lvn.scm`）
  - `070_anf.scm`（旧 `04_anf.scm`）
  - `080_annotator.scm`（旧 `04b_annotator.scm`）
  - `090_rtyper.scm`（旧 `05b_rtyper.scm`）
  - `100_contify.scm`（旧 `04c_contify.scm`）
  - `110_closure_convert.scm`（旧 `05_closure_convert.scm`）
  - `120_alias_escape.scm`（旧 `06b_alias_escape.scm`）
  - `130_lir.scm`（旧 `06_lir.scm` の基本変換・命令選択部）
  - `131_lir_safepoint.scm`（`06_lir.scm` から抽出したスタックマップ/Safepoint部）
  - `132_lir_braun_ssa.scm`（`06_lir.scm` から抽出した Braun SSA/CFG部）
  - `140_backend_x86_64.scm`（旧 `07_backend_x86_64.scm`）
  - `150_backend_aarch64.scm`（旧 `07_backend_aarch64.scm`）
  - `160_backend_c.scm`（旧 `07_backend_c.scm`）
- [ ] [ulisp/Makefile](../../ulisp/Makefile)
- [ ] [ulisp/bootstrap.sh](../../ulisp/bootstrap.sh)
- [ ] [ulisp/test.sh](../../ulisp/test.sh)
- [ ] [ulisp/test_c.sh](../../ulisp/test_c.sh)
- [ ] [ulisp/tests/](../../ulisp/tests/) 配下の各テストランナー・設定ファイル

---

## 4. 実装方針 / Implementation Plan
Target Branch: `refactor/553-refactor-ulisp-passes-and-compiler-architecture`

1. **`ulisp/compiler/` の新設と基盤分離**:
   - `00_helpers.scm` のコンパイラ述語・ASTユーティリティ、`08_driver.scm` を `compiler/` に配置。
2. **`06_lir.scm` の3分割**:
   - Braun SSA / CFG エンジン（行 1859〜2159）を `132_lir_braun_ssa.scm` に抽出。
   - Safepoint / GC スタックマップ生成ロジックを `131_lir_safepoint.scm` に抽出。
   - 残りの命令選択・LIR構築を `130_lir.scm` とする。
3. **Pass 群の 3 桁順序化リネーム**:
   - パイプライン結合順と完全一致する命名にリネーム。
4. **ビルドスクリプト・テストの同期**:
   - `ulisp/Makefile` の `PASSES_LIB`、`PASSES` 定義を更新。
   - `bootstrap.sh`, `test.sh`, `test_c.sh`, `tests/` 内のパス参照を追従。
5. **検証**:
   - `make -C ulisp test_passes`, `make -C ulisp test`, `make -C ulisp test_c` の通過確認。
   - 自己ホストブートストラップ固定点（Fixed Point）の一致確認。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `ulisp/compiler/` に基盤ユーティリティ・ドライバが分離されていること
- [ ] `ulisp/passes/` 配下のファイル名がすべて 3 桁（10刻み）でパイプライン順序と完全一致していること
- [ ] `06_lir.scm` が 3 つの単一責務ファイルに分割されていること
- [ ] `ulisp/Makefile` で `compiler.scm` が正常に結合・生成できること
- [ ] 既存の全 Nanopass 単体テストおよび統合テストが 100% PASS すること
- [ ] 3-stage 自己ホストブートストラップが正常に bit-for-bit で完了すること
