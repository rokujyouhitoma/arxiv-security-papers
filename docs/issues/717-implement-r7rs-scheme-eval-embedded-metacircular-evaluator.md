---
ID: 717
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] R7RS-small (scheme eval) オンデマンド埋め込み型メタ循環評価器 (eval) の実装 (ID: 717)

## 1. 概要 / Summary
AOT バイナリのスタンドアロン独立性を維持したまま R7RS-small §6.12 `(scheme eval)` の動的評価手続き `(eval <expr-or-def> <environment-specifier>)` を完全サポートするため、ULisp ネイティブ手続き・クロージャ・継続 (`call/cc`, `dynamic-wind`)・多値 (`values`)・例外機構 (`guard`, `raise`) とシームレスに統合されたオンデマンド埋め込み型メタ循環評価器（動的 `syntax-rules` マクロ展開器を含む）を実装する。

---

## 2. トレーサビリティ / Traceability
- 関連資料:
  - [R7RS 仕様準拠状況リファレンス](../../ulisp/docs/ref_r7rs_compliance.md) (§1.3.12 環境と動的評価 6.12, §1.4 `(scheme eval)`)
  - R7RS-small §6.12 (`eval`)
  - 先行依存: [Issue #716 (Environment Specifiers)](716-implement-r7rs-environment-specifiers-and-library-import-environments.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [eval.scm](../../ulisp/lib/eval.scm)
- [ ] [eval.sld](../../ulisp/lib/scheme/eval.sld)
- [ ] [helpers.scm](../../ulisp/compiler/helpers.scm)
- [ ] [Makefile](../../ulisp/Makefile)
- [ ] [test_eval_load_repl.scm](../../ulisp/tests/test_eval_load_repl.scm)
- [ ] [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/717-implement-r7rs-scheme-eval-embedded-metacircular-evaluator`

1. `polish-issue` フェーズにて詳細設計および DoD を確定する。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `polish-issue` により実装仕様・境界条件・テスト計画が定義されていること。

