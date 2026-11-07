---
ID: 753
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] 言語定義ファイルの統廃合と L_cst から L_lir_canonical への連続 extends 継承連鎖の確立 (DSN-33-01 T1.1) (ID: 753)

## 1. 概要 / Summary

[[DSN-33-01] ULisp 階層型パス融合（Pipeline / Pass / Nanopass / Picopass）＆ DAG 最適化基盤設計書](../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md) の第 8.3 節およびタスク **T1.1** に基づき、現在 ULisp コードベース内で分散・断絶している `define-language` 定義群を統廃合し、フロントエンドから LIR・バックエンドに至る連続した `extends` 継承チェーンを確立する。

現在、以下の3つの構造的不整合が存在する：
1. **汎用フレームワークへの具体言語の混入**: `ulisp/compiler/nanopass.scm` の末尾（L269-324）に Scheme フロントエンド固有の `L_src` と `L_core` が直書きされており、エンジンと具体言語の分離が破れている。
2. **`extends` 継承チェーンの断絶**: `ulisp/frontend/frontend_lang.scm` の `L_anf` が `L_core` を `(extends L_core)` しておらず、ゼロから再定義されているため、`language-diff` や `language-parent-chain` が `L_core -> L_anf` 間で断絶している。
3. **未定義の幽霊言語シンボル (`L_lir_raw`)**: `ulisp/compiler/pass_manager.scm`（L543-549）において `pass-130-lir` の出力言語および `pass-128`/`pass-133` の入力言語として `'L_lir_raw` が指定されているにもかかわらず、`ulisp/lir/lir_lang.scm` には `L_lir_canonical` しか定義されておらず、`nanopass-verify-ast` が `L_lir_raw` の検証をスキップしている。

本 Issue ではこれらを解消し、`compiler/nanopass.scm` を純粋な DSL エンジンに純化するとともに、`frontend_lang.scm`, `lir_lang.scm`, `backend_lang.scm` の3ファイルに全中間言語を集約する。

---

## 2. トレーサビリティ / Traceability

- 関連設計書:
  - [[DSN-33] ULISP 包括設計仕様書](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md) (第 2.5 節)
  - [[DSN-33-01] ULisp 階層型パス融合 ＆ DAG 最適化基盤設計書](../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md) (第 6.2 節, 第 8.3 節, 第 9.2 節 タスク **T1.1**)
- 依存関係:
  - 先行 Issue: なし（Phase 1 の起点タスク）
  - 後続 Issue: [Issue #754 (T1.2: カタモルフィズムのスキーマ駆動化)](754-refactor-catamorphism-to-schema-driven-traversal.md), [Issue #760 (T3.2: extends (-) 対 eliminates 自動整合性検査)](760-implement-local-redispatch-and-extends-eliminates-validation.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [ulisp/compiler/nanopass.scm](../../ulisp/compiler/nanopass.scm)
- [ ] [ulisp/frontend/frontend_lang.scm](../../ulisp/frontend/frontend_lang.scm)
- [ ] [ulisp/lir/lir_lang.scm](../../ulisp/lir/lir_lang.scm)
- [ ] [ulisp/backend/backend_lang.scm](../../ulisp/backend/backend_lang.scm)
- [ ] [ulisp/Makefile](../../ulisp/Makefile)
- [ ] [ulisp/compiler.scm](../../ulisp/compiler.scm)
- [ ] [ulisp/tests/test_nanopass_framework.scm](../../ulisp/tests/test_nanopass_framework.scm)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `refactor/753-consolidate-define-language-hierarchy`

1. **`ulisp/compiler/nanopass.scm` からの具体言語定義の移管**:
   - `nanopass.scm` L269-324 の `L_src` および `L_core` 定義を `ulisp/frontend/frontend_lang.scm` の先頭へ移動する。
   - `ulisp/Makefile` およびテストランナーにおけるファイル結合順序を確認し、`frontend_lang.scm` が `010_library.scm`〜`030_desugar.scm` より前にロードされるよう調整する（現在 `nanopass.scm` 直後に `frontend_lang.scm` が配置されているかを確認し、すべてのビルドターゲットで整合させる）。
2. **`ulisp/frontend/frontend_lang.scm` における5言語 `extends` 連鎖の構築**:
   - `L_cst`（具象構文木：`define-library`, `import`, `define-syntax`, `syntax-rules`, `let-syntax`, `letrec-syntax`, `define-pass`, `define-language` 等を含む最表層言語）を基底言語として定義する。
   - `L_src` を `(extends L_cst)` として定義し、マクロ・ライブラリ宣言構文を `(- ...)` で除去した言語とする。
   - `L_core` を `(extends L_src)` として定義（既存の除去構文リストを維持）。
   - `L_anf` を `(extends L_core)` として再構成し、`Atom` 非終端記号の導入と複合式の引数制限を `+` / `-` 差分で表現する。
   - `L_lifted` を `(extends L_anf)` として維持する。
3. **`ulisp/lir/lir_lang.scm` における `L_lir_raw` の正式定義**:
   - 生成直後の LIR（分岐融合前の `%cmp` + `%set-boolean` + `%jump-if-false` 等を含む）を表す `L_lir_raw` を定義し、`L_lir_canonical` を `(extends L_lir_raw)` として定義する。
4. **`ulisp/backend/backend_lang.scm` の拡充**:
   - 既存の `L_asm_x86` に加え、AArch64 バックエンド（`150_backend_aarch64.scm`）向けの機械語スキーマ `L_asm_aarch64` を定義する。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `ulisp/compiler/nanopass.scm` に特定言語（`L_src`, `L_core` 等）の定義が一切残っておらず、純粋な DSL 展開器となっていること。
- [ ] `(language-parent-chain 'L_lifted)` が `'(L_cst L_src L_core L_anf L_lifted)` を返し、`(language-parent-chain 'L_lir_canonical)` が `'(L_lir_raw L_lir_canonical)` を返すこと。
- [ ] `pass_manager.scm` に登録されている全パスの `in-lang` / `out-lang` シンボルが `(nanopass-get-all-languages)` に 100% 登録されており、未定義の幽霊言語シンボルが 0 件であること。
- [ ] `ulisp/tests/test_nanopass_framework.scm` および全パス単体テスト・セルフホスティングビルドがエラー 0 件で PASS すること。

