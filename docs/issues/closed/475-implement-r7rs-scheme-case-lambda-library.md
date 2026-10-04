---
ID: 475
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT/ENH] R7RS (scheme case-lambda) 引数個数多重ディスパッチ構文ライブラリの独立モジュール化と完全準拠 (ID: 475)

## 1. 概要 / Summary
R7RS-small Section 4.2.9 および 7.1.1 で規定される `(scheme case-lambda)` 標準ライブラリを独立モジュールとして完全サポートする。
`case-lambda` は引数個数に応じた多重クロージャ節ディスパッチを行う構文形式であり、ILISP では `ilisp/stdlib/base.ilisp` にマクロとして実装され、`map` や `for-each` 等の多引数処理でも利用されている。
本 Issue では、マクロ衛生性（`core_forms` への登録）、`ilisp/module.py` への `(scheme case-lambda)` 登録・エクスポート、個別インポート `(import (scheme case-lambda))` の検証、包括的テストスイートの作成、および `ilisp/docs/SPEC_R7RS.md` の準拠マトリクス更新を実施する。

---

## 2. トレーサビリティ / Traceability
- R7RS-small Section 4.2.9 (Case-lambda): `(case-lambda <clause> ...)`
- R7RS-small Section 7.1.1 (Standard Libraries): `(scheme case-lambda)`
- [SPEC_R7RS.md](../../ilisp/docs/SPEC_R7RS.md): コア構文および標準ライブラリ仕様マトリクス

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ilisp/syntax.py](../../ilisp/syntax.py): `core_forms` への `case-lambda` 識別子登録
- [x] [ilisp/module.py](../../ilisp/module.py): `LibraryRegistry` に `(scheme case-lambda)` の定義・エクスポート追加
- [x] [tests/ilisp/test_scheme_case_lambda.py](../../tests/ilisp/test_scheme_case_lambda.py): 新規テストスイート
- [x] [ilisp/docs/SPEC_R7RS.md](../../ilisp/docs/SPEC_R7RS.md): 準拠状況の更新
- [x] [docs/issues/README.md](README.md): Issue 台帳の更新

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/475-implement-scheme-case-lambda`

1. **マクロ衛生性と識別子保護**:
   - `ilisp/syntax.py` の `core_forms` に `case-lambda` を追加。
2. **ライブラリ登録**:
   - `ilisp/module.py` の `_register_builtin_libraries` に `(scheme case-lambda)` を追加。
   - `case-lambda` を `base_env` からエクスポート。
3. **テストスイート実装**:
   - `tests/ilisp/test_scheme_case_lambda.py` を作成し、以下を検証:
     - `(import (scheme base) (scheme case-lambda))` 経由でのインポート
     - 引数なし、1引数、2引数の固定アリティディスパッチ
     - 可変長引数（ドットペア `(a b . rest)`）ディスパッチ
     - 単一シンボル引数（全引数リスト受け取り `args`）ディスパッチ
     - 一致する節がない場合の例外送出
4. **仕様マトリクス更新**:
   - `ilisp/docs/SPEC_R7RS.md` の `(scheme case-lambda)` を Fully Supported (🟢 100%) に更新。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `ilisp/syntax.py` の `core_forms` に `case-lambda` が登録されていること
- [x] `(import (scheme case-lambda))` が正常に動作し、`case-lambda` が利用可能であること
- [x] `tests/ilisp/test_scheme_case_lambda.py` のテストがすべて PASS すること
- [x] 全テストが PASS し、`flake8`、`mypy --strict ilisp` が 0 エラーであること
- [x] `ilisp/docs/SPEC_R7RS.md` の準拠ステータスが更新されていること

