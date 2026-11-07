---
ID: 764
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] verifier.scm の手書き検証ループの define-attopass 化と Nanopass 融合による三重走査の解消 (DSN-33-01 T4.3) (ID: 764)

## 1. 概要 / Summary

[[DSN-33-01] ULisp 階層型パス融合 ＆ DAG 最適化基盤設計書](../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md) の第 8.2 節（課題②）、第 8.4 節、およびタスク **T4.3** に基づき、現在 `ulisp/compiler/verifier.scm` に手書きの再帰ループとして実装されている各フェーズの構文・不変条件検査（`verify-desugared-ast`, `verify-anf-ast`, `verify-closure-ast`）を **`define-attopass`** として再定義し、対応する Nanopass の走査に融合することで、1パスあたり最大3回発生していた重複走査（三重走査）を解消する。

現在、`--verify-ir` 有効時には以下の三重走査が発生している：
1. `define-pass` 入口での `nanopass-verify-ast`
2. `define-pass` 出口での `nanopass-verify-ast`
3. `pass_manager.scm` の `run-single-pass` 直後の `verify-pass-output`（さらに `verify-anf-ast` 内では `nanopass-ast-valid?` を呼んだ後に手書きループで再度走査）

---

## 2. トレーサビリティ / Traceability

- 関連設計書:
  - [[DSN-33-01] ULisp 階層型パス融合 ＆ DAG 最適化基盤設計書](../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md) (第 3.1 節, 第 4.1 節, 第 8.2 節 課題②, 第 8.4 節, 第 9.2 節 タスク **T4.3**)
- 依存関係:
  - 先行 Issue: [Issue #754 (T1.2: カタモルフィズムのスキーマ駆動化)](754-refactor-catamorphism-to-schema-driven-traversal.md), [Issue #760 (T3.2: 5ステップ融合サイクル)](760-implement-local-redispatch-and-extends-eliminates-validation.md), [Issue #763 (T4.2: 030_desugar.scm の fuse-rules 置換)](763-replace-desugar-030-duplicate-rules-with-fuse-rules.md)
  - 後続 Issue: [Issue #765 (T5.1: ルール依存 DAG 自動構築)](765-implement-rule-dependency-dag-and-femtopass-cache-invalidation.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [ulisp/compiler/verifier.scm](../../ulisp/compiler/verifier.scm)
- [ ] [ulisp/compiler/pass_manager.scm](../../ulisp/compiler/pass_manager.scm)
- [ ] [ulisp/compiler/nanopass_meta.scm](../../ulisp/compiler/nanopass_meta.scm)
- [ ] [ulisp/frontend/030_desugar.scm](../../ulisp/frontend/030_desugar.scm)
- [ ] [ulisp/frontend/070_anf.scm](../../ulisp/frontend/070_anf.scm)
- [ ] [ulisp/frontend/110_closure_convert.scm](../../ulisp/frontend/110_closure_convert.scm)
- [ ] [ulisp/tests/test_verifier.scm](../../ulisp/tests/test_verifier.scm)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `refactor/764-migrate-verifier-to-attopass`

1. **`verifier.scm` の各不変条件検査の `define-attopass` 分解**:
   - `atto-no-desugar-sugar`（残存糖衣構文および Named-let `(let <sym> ...)` の禁止検査）
   - `atto-anf-atomic-operands`（ANF における関数呼び出し・プリミティブ引数・`if` 条件式の原子性検査）
   - `atto-closure-no-raw-lambda`（クロージャ変換後の未リフト `lambda` 不在および `%function` 構造検査）
2. **スキーマ検査と Attopass 検査の役割整理**:
   - `L_core` の `(- ...)` と重複していた `*prohibited-desugared-keywords*` は `L_core` の `removed-prods` メタデータを直接参照するように統一する。
   - `verify-desugared-ast`, `verify-anf-ast`, `verify-closure-ast` の公開関数シグネチャ自体は既存テスト（`test_verifier.scm`）互換のため維持しつつ、内部実装は上記の `attopass` 群を呼び出す形に統一する。
   - パイプライン実行時は、前のパスの出口検証と次のパスの入口検証が同一言語（$L_k$）に対して重複実行されないよう、`pass_manager.scm` で検証済み言語タグを記録してスキップする。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `verifier.scm` の不変条件が `define-attopass` として定義され、Nanopass 走査に融合可能であること。
- [ ] `run-pass-pipeline` で `--verify-ir` を有効化した際、同一の AST に対して重複したスキーマ検証走査が発生しないこと。
- [ ] `ulisp/tests/test_verifier.scm` の全テストケースが 100% PASS すること。

