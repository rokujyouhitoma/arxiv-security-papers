---
ID: 473
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT] R7RS 文字・文字列完全網羅および (scheme char) ライブラリの検証・同期 (ID: 473)

## 1. 概要 / Summary

R7RS-small (Revised^7 Report on the Algorithmic Language Scheme) 第 6.6 節 (Characters)、第 6.7 節 (Strings)、および標準ライブラリ `(scheme char)` に準拠し、文字・文字列処理機能の完全な整合性を保証する：

1. **文字種別判定・変換・大小文字非依存比較の完備**:
   - `char-alphabetic?`, `char-numeric?`, `char-whitespace?`, `char-upper-case?`, `char-lower-case?`
   - `digit-value` (10進数字 0..9 の整数値化、それ以外は `#f`)
   - `char-upcase`, `char-downcase`, `char-foldcase`
   - `char-ci=?`, `char-ci<?`, `char-ci>?`, `char-ci<=?`, `char-ci>=?`
2. **文字列ケース処理・大小文字非依存比較の完備**:
   - `string-upcase`, `string-downcase`, `string-foldcase`
   - `string-ci=?`, `string-ci<?`, `string-ci>?`, `string-ci<=?`, `string-ci>=?`
3. **マクロ衛生性の保護 (`core_forms`)**:
   - `ilisp/syntax.py` の `core_forms` に `(scheme char)` の全 17 識別子を登録し、マクロ展開時の変数捕捉を防止。
4. **標準ライブラリ `(scheme char)` の完全検証と仕様マトリクス同期**:
   - 全 17 手続きの単体・結合テストによる 100% カバレッジ確保。
   - `ilisp/docs/SPEC_R7RS.md` の `(scheme char)` ステータスを Partially Supported (🟡 30%) から Fully Supported (🟢 100%) へ昇格。

---

## 2. トレーサビリティ / Traceability

- **R7RS 6.6 Characters**:
  - `char-alphabetic?`, `char-numeric?`, `char-whitespace?`, `char-upper-case?`, `char-lower-case?`
  - `digit-value`
  - `char-ci=?`, `char-ci<?`, `char-ci>?`, `char-ci<=?`, `char-ci>=?`
  - `char-upcase`, `char-downcase`, `char-foldcase`
- **R7RS 6.7 Strings**:
  - `string-ci=?`, `string-ci<?`, `string-ci>?`, `string-ci<=?`, `string-ci>=?`
  - `string-upcase`, `string-downcase`, `string-foldcase`
- **R7RS 7.1.1 Standard Libraries**:
  - `(scheme char)`: 上記 17 手続きをエクスポート。
- **ILISP R7RS 仕様準拠マトリクス**:
  - [ilisp/docs/SPEC_R7RS.md](../../ilisp/docs/SPEC_R7RS.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [ilisp/syntax.py](../../ilisp/syntax.py): `core_forms` への `(scheme char)` 識別子群の登録
- [x] [ilisp/module.py](../../ilisp/module.py): `(scheme char)` のエクスポート定義の整合性検証
- [x] [tests/ilisp/test_scheme_char.py](../../tests/ilisp/test_scheme_char.py): `(scheme char)` 全 17 手続きの網羅的単体テスト
- [x] [ilisp/docs/SPEC_R7RS.md](../../ilisp/docs/SPEC_R7RS.md): 仕様マトリクスの `(scheme char)` 100% 昇格および進捗統計更新
- [x] [docs/issues/README.md](README.md): Issue 台帳の更新

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/473-complete-r7rs-scheme-char-library`

1. **`ilisp/syntax.py` の同期**:
   - `core_forms` に `char-alphabetic?`, `char-numeric?`, `char-whitespace?`, `char-upper-case?`, `char-lower-case?`, `digit-value`, `char-upcase`, `char-downcase`, `char-foldcase`, `char-ci=?`, `char-ci<?`, `char-ci>?`, `char-ci<=?`, `char-ci>=?`, `string-upcase`, `string-downcase`, `string-foldcase`, `string-ci=?`, `string-ci<?`, `string-ci>?`, `string-ci<=?`, `string-ci>=?` を追加。
2. **網羅的単体テスト (`tests/ilisp/test_scheme_char.py`)**:
   - `digit-value`: `#\0`..`#\9` -> 0..9, `#\a` -> `#f`
   - `char-foldcase`: 大小文字フォールディング
   - `string-foldcase`: `"Straße"` -> `"strasse"` などの正規化
   - `(import (scheme char))` による全識別子のインポート・動作検証
3. **品質ゲートとドキュメント同期**:
   - 全テスト PASS, `flake8`, `mypy --strict ilisp`。
   - `SPEC_R7RS.md` の更新。

---

## 5. 完了条件 / Success Criteria (DoD)

- [x] `(scheme char)` に規定される全 17 手続きがマクロ展開時にも保護されて正常動作すること
- [x] `digit-value`, `char-foldcase`, `string-foldcase` が R7RS 6.6/6.7 準拠で動作すること
- [x] 新規単体テストが全件 PASS すること
- [x] 既存の全 346 件のテストが 100% PASS すること
- [x] `flake8` 0 警告、`mypy --strict ilisp` 0 エラーであること
- [x] `ilisp/docs/SPEC_R7RS.md` が更新され、`(scheme char)` が Fully Supported (🟢 100%) になること
