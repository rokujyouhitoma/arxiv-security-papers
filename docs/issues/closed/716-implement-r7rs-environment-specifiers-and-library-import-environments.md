---
ID: 716
種別: Feature
優先度: High
ステータス: Open (In Progress)
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
- [ ] [Makefile](../../ulisp/Makefile)
- [ ] [test_eval_load_repl.scm](../../ulisp/tests/test_eval_load_repl.scm) (新規)
- [ ] [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/716-implement-r7rs-environment-specifiers-and-library-import-environments`

1. **第一級環境指定子オブジェクト `<environment>` の設計 ([eval.scm](../../ulisp/lib/eval.scm))**:
   - `#(ulisp-env-tag <bindings-box> <macros-box> <parent> <mutable?>)` 形式のタグ付きベクタにより環境オブジェクトを表現し、`environment?` 述語・`%env-lookup`・`%env-bound?`・`%env-define!`・`%env-set!`（不変環境への `define` / `set!` 時エラー送出保護）を提供する。
2. **標準ライブラリエクスポートレジストリとインポート集合修飾子の解決 ([eval.scm](../../ulisp/lib/eval.scm))**:
   - `(scheme base)`, `(scheme inexact)`, `(scheme complex)`, `(scheme char)`, `(scheme cxr)`, `(scheme case-lambda)`, `(scheme eval)`, `(scheme file)`, `(scheme lazy)`, `(scheme load)`, `(scheme process-context)`, `(scheme read)`, `(scheme repl)`, `(scheme time)`, `(scheme write)`, `(scheme r5rs)` 等の標準ライブラリ識別子と第一級束縛リストの対応表を構築する。
   - インポート集合修飾子 `(only <import-set> <id> ...)`, `(except <import-set> <id> ...)`, `(prefix <import-set> <prefix-sym>)`, `(rename <import-set> (<old> <new>) ...)` を再帰的に解決する `%resolve-import-set` を実装する。
3. **R7RS §6.12 環境生成手続き群の実装 ([eval.scm](../../ulisp/lib/eval.scm), [eval.sld](../../ulisp/lib/scheme/eval.sld), [repl.sld](../../ulisp/lib/scheme/repl.sld), [r5rs.sld](../../ulisp/lib/scheme/r5rs.sld))**:
   - `(environment list1 ...)`: 指定されたインポート集合群をマージした不変環境 (`mutable? = #f`) を返す。
   - `(null-environment version)`: `version = 5` (または `7`) に対してコア構文マクロ定義のみを含む不変環境を返す（それ以外のバージョンは `error` を送出）。
   - `(scheme-report-environment version)`: `version = 5` (または `7`) に対して R5RS/R7RS 標準手続き・構文一式を含む不変環境を返す（それ以外のバージョンは `error` を送出）。
   - `(interaction-environment)`: 全標準手続き・構文を初期束縛として持ち、`define` / `set!` による新規定義・破壊的代入が可能な可変環境 (`mutable? = #t`) のシングルトン（または現在の対話環境）を返す。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `environment`, `null-environment`, `scheme-report-environment`, `interaction-environment` および `only` / `except` / `prefix` / `rename` 修飾子解決が実装され、[test_eval_load_repl.scm](../../ulisp/tests/test_eval_load_repl.scm) が PASS すること。
- [ ] `make -C ulisp lint_sexpr test_r7rs_traceability test_eval_load_repl` が 100% PASS すること。
- [ ] [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) の該当項目が更新されていること。

