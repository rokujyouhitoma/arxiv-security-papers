---
ID: 716
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] R7RS §6.12 環境指定子オブジェクト (environment, null-environment, scheme-report-environment, interaction-environment) の実装 (ID: 716)

## 1. 概要 / Summary
ULisp における動的評価・REPL サポートの基盤として、R7RS-small §6.12 で規定される第一級環境指定子オブジェクト `<environment>` および環境生成手続き (`environment`, `null-environment`, `scheme-report-environment`, `interaction-environment`) を実装する。`only` / `except` / `prefix` / `rename` のインポート集合修飾子の動的解決および可変/不変環境の区別を完全サポートする。

---

## 2. トレーサビリティ / Traceability
- 関連資料:
  - [R7RS 仕様準拠状況リファレンス](../../ulisp/docs/ref_r7rs_compliance.md) (§1.3.12 環境と動的評価 6.12, §1.4 標準 16 ライブラリ)
  - R7RS-small §6.12 (Environments and evaluation)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [eval.scm](../../ulisp/lib/eval.scm) (新規)
- [ ] [eval.sld](../../ulisp/lib/scheme/eval.sld)
- [ ] [repl.sld](../../ulisp/lib/scheme/repl.sld)
- [ ] [r5rs.sld](../../ulisp/lib/scheme/r5rs.sld)
- [ ] [test_eval_load_repl.scm](../../ulisp/tests/test_eval_load_repl.scm) (新規)
- [ ] [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/716-implement-r7rs-environment-specifiers-and-library-import-environments`

1. `polish-issue` フェーズにて詳細設計および DoD を確定する。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `polish-issue` により実装仕様・境界条件・テスト計画が定義されていること。

