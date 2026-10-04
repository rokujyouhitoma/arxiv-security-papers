---
ID: 468
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT] R7RS 型固有等価判定述語および構文エラー構文の実装 (ID: 468)

## 1. 概要 / Summary

R7RS-small (Revised^7 Report on the Algorithmic Language Scheme) 仕様準拠を推進するため、以下の機能および構文を ILISP に実装する：
1. **第6.3節 真偽値等価述語 (`boolean=?`)**:
   - `(boolean=? boolean1 boolean2 boolean3 ...)`
   - 2つ以上の引数を受け取り、すべての引数が真偽値（`#t` または `#f`）であることを厳格に検証（非真偽値が含まれる場合はエラー）。
   - 全引数が同一の真偽値である場合に `#t`、1つでも異なる場合に `#f` を返却する。
2. **第6.5節 シンボル等価述語 (`symbol=?`)**:
   - `(symbol=? symbol1 symbol2 symbol3 ...)`
   - 2つ以上の引数を受け取り、すべての引数がシンボル型であることを厳格に検証（非シンボルが含まれる場合はエラー）。
   - 全引数が同一シンボルである場合に `#t`、1つでも異なる場合に `#f` を返却する。
3. **第4.3.1節 / 第6.11節 構文エラー通知構文 (`syntax-error`)**:
   - `(syntax-error message [irritant ...])`
   - `syntax-rules` 衛生的マクロのパターン展開時や評価時に明示的に構文エラーを送出する特殊形式 / プリミティブ。
   - `LispSyntaxError`（`ErrorObject` / `read-error?` 判定対象）を送出し、詳細なエラーメッセージと引数リストを通知・報告する。

---

## 2. トレーサビリティ / Traceability

- **R7RS 6.3 Booleans**:
  - `(boolean=? boolean1 boolean2 boolean3 ...)`
  - "Returns `#t` if all arguments are `#t` or all are `#f`."
- **R7RS 6.5 Symbols**:
  - `(symbol=? symbol1 symbol2 symbol3 ...)`
  - "Returns `#t` if all arguments are symbols and all have the same name in the sense of `string=?`."
- **R7RS 4.3.1 Binding constructs for syntactic keywords / 6.11 Exceptions**:
  - `(syntax-error message irritant ...)`
  - "syntax-error can be used to report errors in macro transformers, but can also be used outside."
- **ILISP R7RS 仕様準拠マトリクス**:
  - [ilisp/docs/SPEC_R7RS.md](../../ilisp/docs/SPEC_R7RS.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [ilisp/env.py](../../ilisp/env.py): `prim_boolean_eq`, `prim_symbol_eq`, `prim_syntax_error` プリミティブの追加
- [x] [ilisp/evaluator.py](../../ilisp/evaluator.py): `syntax-error` 特殊形式評価サポート（式を評価せずそのまま irritants として送出するか、評価後送出するか）
- [x] [ilisp/syntax.py](../../ilisp/syntax.py): `syntax-rules` マクロ展開器における `syntax-error` キーワードの認識および展開時構文エラーハンドリング
- [x] [tests/ilisp/test_predicates_and_syntax_error.py](../../tests/ilisp/test_predicates_and_syntax_error.py): 新規単体テスト（正常系・型エラー・複数引数・マクロ連携）
- [x] [ilisp/docs/SPEC_R7RS.md](../../ilisp/docs/SPEC_R7RS.md): 実装状況マトリクスの更新 (180 -> 183 / 203)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/468-implement-r7rs-type-predicates-and-syntax-error`

1. **`boolean=?` 実装 (`ilisp/env.py`)**:
   - 引数数チェック: 2 個以上 (`len(args) >= 2`)。
   - 型チェック: 全引数が `isinstance(arg, bool)` であること。非真偽値の場合は `LispRuntimeError` ("boolean=? requires boolean arguments") を送出。
   - 値一致チェック: 全引数が最初の引数と等しいか判定。
2. **`symbol=?` 実装 (`ilisp/env.py`)**:
   - 引数数チェック: 2 個以上 (`len(args) >= 2`)。
   - 型チェック: 全引数が `isinstance(arg, Symbol)` であること。非シンボルの場合は `LispRuntimeError` ("symbol=? requires symbol arguments") を送出。
   - 値一致チェック: 全引数の名前が最初の引数と等しいか判定。
3. **`syntax-error` 実装 (`ilisp/evaluator.py`, `ilisp/env.py`, `ilisp/syntax.py`)**:
   - Evaluator 特殊形式として `syntax-error` をインターセプト、または手続きとして登録。
   - R7RS では `(syntax-error message irritant ...)` は評価時にも呼び出し可能であり、マクロ展開器内部で展開結果として現れた場合にも展開時エラーとなる。
   - Evaluator において `(syntax-error message . irritants)` を受け取った場合、第1引数のメッセージ文字列と後続の irritants を抽出して即座に `LispSyntaxError` を送出する。
   - `syntax-rules` マクロ展開器（`ilisp/syntax.py`）でも、テンプレート先頭が `syntax-error` である場合はマクロ展開フェーズで早期エラー送出可能にする。
4. **単体テスト (`tests/ilisp/test_predicates_and_syntax_error.py`)**:
   - `boolean=?` の 2 引数、3 引数、4 引数テスト（全一致 `#t`、一部不一致 `#f`、非 boolean 例外）。
   - `symbol=?` の 2 引数、3 引数、4 引数テスト（全一致 `#t`、一部不一致 `#f`、非 symbol 例外）。
   - `syntax-error` の直接呼び出し、guard による例外捕捉、マクロ内での `syntax-error` 展開テスト。
5. **品質ゲートとドキュメント同期**:
   - 全体テスト (`pytest tests/ilisp`) パス確認。
   - `flake8`, `mypy --strict ilisp` PASS 確認。
   - `SPEC_R7RS.md` のステータスと円グラフを更新。

---

## 5. 完了条件 / Success Criteria (DoD)

- [x] `boolean=?` が 2 引数以上で R7RS 6.3 準拠で動作し、型検査が厳格に行われること
- [x] `symbol=?` が 2 引数以上で R7RS 6.5 準拠で動作し、型検査が厳格に行われること
- [x] `syntax-error` がメッセージと irritants を伴う構文エラーを送出できること
- [x] 新規単体テストが全件 PASS すること
- [x] 既存の 293 件の ILISP テストがすべて PASS すること (全307件 100% PASS)
- [x] `flake8` 0 警告、`mypy --strict ilisp` 0 エラーであること
- [x] `ilisp/docs/SPEC_R7RS.md` が更新され、整合性が保たれていること
