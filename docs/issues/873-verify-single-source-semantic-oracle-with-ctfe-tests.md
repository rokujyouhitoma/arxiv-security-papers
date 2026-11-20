---
ID: 873
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT] 単一ソース意味論オラクルによる CTFE 既存テスト回帰検証 (ID: 873)

## 1. 概要 / Summary
DSN-33-03 §3.6 に基づき、`Now` 辞書を「完全決定論的で仕様乖離のない正解（Ground Truth）オラクル」として位置づけ、既存の全 CTFE 単体テストスイートを `eval-in-stage`（Now 辞書）経由で実行・回帰検証する。

---

## 2. トレーサビリティ / Traceability
- 関連資料: [DSN-33-03 §3.6](docs/designs/DSN-33-03-ulisp_stage_polymorphic_metacompiler_and_futamura_projection_architecture.md#36-単一ソース意味論オラクルsingle-source-semantic-oracleと多層差分検証)
- 関連 Issue: #825 (eval-in-language)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/tests/test_scheme_runtime.scm](ulisp/tests/test_scheme_runtime.scm)
- [ ] [ulisp/compiler/eval_in_language.scm](ulisp/compiler/eval_in_language.scm)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/873-verify-single-source-semantic-oracle-with-ctfe-tests`

1. `eval_in_language.scm` の既存テストケースを `Now` 辞書経由で実行するハーネスを作成。
2. ホスト Scheme の直接評価結果と `eval-in-stage (Now)` の評価値の一致を検証。
3. 仕様乖離（Semantic Drift）がゼロであることを確認。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 既存の全 CTFE テストが `Now` 辞書上で 100% PASS すること。
- [ ] 単一ソース意味論オラクルとして機能することがテストで証明されること。
