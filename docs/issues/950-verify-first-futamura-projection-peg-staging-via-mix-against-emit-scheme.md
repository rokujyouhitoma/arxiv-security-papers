---
ID: 950
種別: Feature
優先度: Low
ステータス: Open (New)
---

# [FEAT/ENH] Direct-Style PEG インタプリタ × `mix`（第1二村射影）による小規模文法自動段階化と `emit_scheme.scm` 生成パーサーとの双対検証 (ID: 950)

## 1. 概要 / Summary

現行の [runtime.scm](../../ulisp/peg/runtime.scm) は二重 CPS クロージャと破壊的循環ボックス `rule-cells` を前提とするため、そのままでは [#942](942-connect-specialize-or-widen-in-eval-in-stage-apply-for-futamura-mix.md) の部分評価器 `mix`（`eval-in-stage` + `specialize-or-widen`）に投入できない。

[#942](942-connect-specialize-or-widen-in-eval-in-stage-apply-for-futamura-mix.md)（`mix` 接続）および [#948](948-implement-direct-style-static-scheme-peg-parser-generator-backend.md)（Direct-Style 静的 `.scm` 生成バックエンド `emit_scheme.scm`）の完了後に、純粋・第一階に近い小さな Direct-Style PEG インタプリタを用意し、小規模文法（[calc.peg](../../tools/grammars/calc.peg) や [cti_ql.peg](../../ulisp/workbench/examples/cti_ql.peg)）に対して `mix(peg-interp, grammar-ast)` による第1二村射影を実行する。機械的に射影された残余パーサーから文法 AST 解釈ディスパッチが蒸発することを確認し、`#948` の手書きコード生成器 `emit_scheme.scm` の出力と動作・残余構造を双対検証（Dual Verification）する。

---

## 2. トレーサビリティ / Traceability

- 関連資料:
  - [DSN-33-21](../designs/DSN-33-21-ulisp_stage_polymorphic_metacompiler_and_futamura_projection_architecture.md)
  - [DSN-33-24](../designs/DSN-33-24-ulisp_futamura_projection_scheme_interpreter_synthesis_architecture.md)
  - [Issue #942](942-connect-specialize-or-widen-in-eval-in-stage-apply-for-futamura-mix.md)
  - [Issue #948](948-implement-direct-style-static-scheme-peg-parser-generator-backend.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [compiler.scm](../../ulisp/compiler.scm) (`stage-poly-lower`, `specialize-or-widen` の PEG 特殊化適合確認)
- [ ] `ulisp/peg/compiler/emit_scheme.scm` (双対比較オラクル)
- [ ] [calc.peg](../../tools/grammars/calc.peg)
- [ ] [cti_ql.peg](../../ulisp/workbench/examples/cti_ql.peg)
- [ ] [test_futamura_projection.scm](../../ulisp/tests/test_futamura_projection.scm) (または新規 `ulisp/tests/test_peg_futamura_staging.scm`)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/950-verify-peg-futamura-staging-via-mix`

1. `#942` の `mix` で部分評価可能な最小の Direct-Style PEG AST インタプリタ（ルール表は連想リスト・純粋な再帰構成）をテストハーネス上に実装する。
2. `calc.peg` および `cti_ql.peg` の文法 AST を静的入力として `stage-poly-lower`（`mix`）を実行し、文法 AST 解釈記号が消滅した残余パーサーを生成する。
3. `#948` の `emit_scheme.scm` が生成したパーサーをオラクルとして、同一入力群に対するパース結果・エラー位置の一致と残余コード品質を双対検証する（詳細は `polish-issue` にて精緻化する）。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `calc.peg` / `cti_ql.peg` に対して `mix(peg-interp, grammar-ast)` が文法 AST 記号を含まない残余パーサーを生成すること。
- [ ] `mix` 射影版パーサーと `emit_scheme.scm` 生成パーサーが同一入力群に対して完全に同一のパース結果・エラー位置を返すこと（詳細ゲートは `polish-issue` 時に確定）。
