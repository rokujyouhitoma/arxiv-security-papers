---
ID: 718
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] R7RS-small (scheme load), (scheme repl), (scheme r5rs) 完全準拠化と動的ロードの実装 (ID: 718)

## 1. 概要 / Summary
R7RS-small §6.14 `(scheme load)` の動的ソースファイル読込・評価手続き `(load <filename> [<environment-specifier>])`、`(scheme repl)` の対話環境、および `(scheme r5rs)` の全 R5RS 互換エクスポート（`exact->inexact`, `inexact->exact`, `eval`, `load`, `null-environment`, `scheme-report-environment`, `interaction-environment` を含む）を完全実装し、R7RS-small 全 16 標準ライブラリの 100% 完全サポート (**◎**) を達成する。

---

## 2. トレーサビリティ / Traceability
- 関連資料:
  - [R7RS 仕様準拠状況リファレンス](../../ulisp/docs/ref_r7rs_compliance.md) (§1.3.14, §1.4 `(scheme load)`, `(scheme repl)`, `(scheme r5rs)`)
  - R7RS-small §6.14 (`load`), §7.1.10, §7.1.13, §7.1.16
  - 先行依存: [Issue #716](716-implement-r7rs-environment-specifiers-and-library-import-environments.md), [Issue #717 (`eval`)](717-implement-r7rs-scheme-eval-embedded-metacircular-evaluator.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [eval.scm](../../ulisp/lib/eval.scm)
- [ ] [load.sld](../../ulisp/lib/scheme/load.sld)
- [ ] [repl.sld](../../ulisp/lib/scheme/repl.sld)
- [ ] [r5rs.sld](../../ulisp/lib/scheme/r5rs.sld)
- [ ] [helpers.scm](../../ulisp/compiler/helpers.scm)
- [ ] [Makefile](../../ulisp/Makefile)
- [ ] [test_eval_load_repl.scm](../../ulisp/tests/test_eval_load_repl.scm)
- [ ] [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/718-implement-r7rs-scheme-load-repl-and-r5rs-full-compliance`

1. `polish-issue` フェーズにて詳細設計および DoD を確定する。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `polish-issue` により実装仕様・境界条件・テスト計画が定義されていること。

