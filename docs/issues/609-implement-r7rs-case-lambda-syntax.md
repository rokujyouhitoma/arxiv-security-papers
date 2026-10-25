---
ID: 609
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] R7RS case-lambda 構文および (scheme case-lambda) ライブラリの実装 (ID: 609)

## 1. 概要 / Summary
R7RS-small §4.2.9 および `(scheme case-lambda)` で規定されている `case-lambda` 構文を実装し、可変個・複数アリティの手続き定義および引数個数ディスパッチを可能にする。
AOT メタコンパイラにおけるマクロ展開器 ([Pass 020](../../ulisp/frontend/020_macro_expander.scm)) または構文脱糖パス ([Pass 028](../../ulisp/frontend/028_desugar_bindings.scm) / [Pass 030](../../ulisp/frontend/030_desugar.scm)) において、レスト引数と引数長判定を用いた `cond` / `length` 分岐への自動脱糖を行う。

---

## 2. トレーサビリティ / Traceability
- R7RS-small:
  - §4.2.9: Case-lambda (`case-lambda`)
  - §5.6 / §5.1: `(scheme case-lambda)`
- 関連仕様書:
  - [R7RS 仕様準拠状況リファレンス](../../ulisp/docs/ref_r7rs_compliance.md) §1.1, §1.4

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/frontend/020_macro_expander.scm](../../ulisp/frontend/020_macro_expander.scm) または [ulisp/frontend/028_desugar_bindings.scm](../../ulisp/frontend/028_desugar_bindings.scm) / [ulisp/frontend/030_desugar.scm](../../ulisp/frontend/030_desugar.scm): `case-lambda` 脱糖ロジックの実装
- [ ] [ulisp/lib/scheme/case-lambda.sld](../../ulisp/lib/scheme/case-lambda.sld): `(scheme case-lambda)` ライブラリ定義およびエクスポート
- [ ] [ulisp/tests/test_case_lambda.scm](../../ulisp/tests/test_case_lambda.scm): `case-lambda` の単体テストスイート
- [ ] [ulisp/docs/ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md): 準拠状況ステータス更新 (0% → 100%)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/609-implement-r7rs-case-lambda-syntax`

1. 構文脱糖またはマクロ展開において、`case-lambda` の各節 `((formals) body ...)` を解析し、固定長引数およびレスト引数 (`(x . rest)`) のアリティ長を判定するロジックを設計。
2. レスト引数 `(lambda args ...)` を受け取り、`args` の長さや構造に応じて適切な節へジャンプする `cond` 式へ脱糖する。
3. `(scheme case-lambda)` SLD を整備し、標準ライブラリとしてインポート可能にする。
4. 固定長アリティ、可変長アリティ、ゼロ引数、マッチ失敗時のエラー送出をテストで検証する。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `(case-lambda ...)` がマクロまたは脱糖パスで正常に処理され、複数の引数パターンで期待通りディスパッチされること。
- [ ] `(import (scheme case-lambda))` により `case-lambda` が使用可能であること。
- [ ] 不正な引数個数で呼び出された場合に適切にエラーが送出されること。
- [ ] `ref_r7rs_compliance.md` の `(scheme case-lambda)` ステータスが更新され、品質ゲートを通過すること。
