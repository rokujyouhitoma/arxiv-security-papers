---
ID: 974
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] エスケープ解析の関数間要約・TBAA 責務分離および構造体・非エスケープオブジェクトのスカラー置換（SRA）実装 (ID: 974)

## 1. 概要 / Summary

`120_alias_escape.scm` に混載している TBAA（冗長ロード削除）とエスケープ解析（スタック昇格）を「解析（Analysis Property）」と「変換」に分離し、呼び出し先関数が引数を逃がさないことを判定する関数間エスケープ要約を追加する。
さらに非エスケープの `cons`・クロージャ環境・C99 ローカル構造体の各フィールドを独立した仮想レジスタへ分解するスカラー置換（SRA/SROA）を実装し、不要なメモリ読み書きを 0 回にする。

---

## 2. トレーサビリティ / Traceability

- 関連資料:
  - [Issue #966](966-separate-mir-ssa-and-machine-lir-for-unified-middle-end.md)
  - [Issue #840](closed/840-automate-analysis-cache-invalidation-and-recomputation-in-nanopass.md)
  - [BASELINE.md](../../ulisp/benchmarks/BASELINE.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [120_alias_escape.scm](../../ulisp/frontend/120_alias_escape.scm)
- [ ] [132_lir_braun_ssa.scm](../../ulisp/lir/132_lir_braun_ssa.scm)
- [ ] [pass_manager.scm](../../ulisp/compiler/pass_manager.scm)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/974-escape-sra-and-tbaa-refactor`

1. TBAA・エスケープ解析を `pass_manager.scm` の Analysis Property として切り出し、関数間引数エスケープ要約を導入する。
2. 非エスケープ複合オブジェクト（`cons` / クロージャ環境 / C99 ローカル構造体）の各フィールドを仮想レジスタへ分解し、SSA（`mem2reg`）へ直結する SRA パスを実装する。
3. 詳細手順は `polish-issue` にて精緻化する。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] 非エスケープ複合オブジェクトのフィールドアクセスが仮想レジスタ化され、不要なアロケーション・ロード/ストアが除去されること
- [ ] 関数間エスケープ要約により安全な callee 渡しオブジェクトのスタック昇格/SRA が有効化されること
- [ ] `make format` / `make static_analysis` / `make test` および `verify-quality-gates` が全 PASS すること
