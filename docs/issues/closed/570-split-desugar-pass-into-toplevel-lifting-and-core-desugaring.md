---
ID: 570
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT/ENH] 構文脱糖パスの分離：トップレベル巻き上げ (025) と Core 構文脱糖 (030) の独立 Nanopass 化 (ID: 570)

## 1. 概要 / Summary
現在 `ulisp/passes/030_desugar.scm` 内で同居しているトップレベル定義の解析・単一 `letrec` 巻き上げ処理 (`rewrite-top-level`) と、Core 構文への展開処理 (`desugar-all`) を独立した Nanopass として物理的・論理的に分離する。
トップレベル定義の集約を `ulisp/passes/025_top_level.scm`（Pass 025: `toplevel-lift`）として独立させることで、Pass 030 の入力 AST が「単一の式（正規化された `letrec`）」であるという厳密な不変条件（Invariants）を確立し、Nanopass コンパイラとしての検証可能性と保守性を高める。

---

## 2. トレーサビリティ / Traceability
- 関連仕様書:
  - [DSN-33 (ULisp アーキテクチャ包括設計仕様書)](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
  - [ULisp パイプライン・Nanopass 仕様書](../ulisp/docs/pipeline_architecture.md)
  - Issue #529 (トップレベル定義の独立コンパイル構造化)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/passes/025_top_level.scm](../../ulisp/passes/025_top_level.scm)
- [x] [ulisp/passes/030_desugar.scm](../../ulisp/passes/030_desugar.scm)
- [x] [ulisp/compiler/driver.scm](../../ulisp/compiler/driver.scm)
- [x] [ulisp/Makefile](../../ulisp/Makefile)
- [x] [ulisp/docs/pipeline_architecture.md](../../ulisp/docs/pipeline_architecture.md)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/570-split-desugar-pass-into-toplevel-lifting-and-core-desugaring`

1. `030_desugar.scm` から `rewrite-top-level` およびその関連ヘルパー関数を抽出し、新パス `ulisp/passes/025_top_level.scm` を作成。
2. `030_desugar.scm` は純粋な式レベル脱糖 (`desugar-all`, `desugar-expr`) に特化させる。
3. `compiler/driver.scm` のパイプラインステージを更新し、`ast025 (lift-top-level ast020)` を明示的に接続。
4. `ulisp/Makefile` の `PASSES_LIB` に `passes/025_top_level.scm` を追加。
5. 単体テストおよびセルフホスティングを含む全テストが正常に完了することを検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `rewrite-top-level` が `025_top_level.scm` に独立して存在し、Pass 025 として機能すること。
- [x] `030_desugar.scm` からトップレベル巻き上げロジックが排除され、式脱糖に専念していること。
- [x] `driver.scm` および `ulisp/Makefile` が新パイプライン構成に対応していること。
- [x] 全テストスイート (`make test`) が PASS すること。

