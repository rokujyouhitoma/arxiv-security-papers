---
ID: 556
種別: Feature
優先度: Medium
ステータス: Closed (Completed)
完了日: 2026-10-18
---

# [FEAT] R7RS 文字順序比較述語 (char<? / char>? / char<=? / char>=?) の実装 (ID: 556)

## 1. 概要 / Summary
R7RS 6.6 (Characters) に規定されている文字比較述語 `char<?`, `char>?`, `char<=?`, `char>=?` を標準ライブラリに実装する。
ULisp には既に文字等価述語 `char=?` および文字整数変換 `char->integer` が実装されているため、Unicode / ASCII スカラー値の整数大小比較へマップすることで、厳密な単調増加・単調減少判定を複数引数対応で安全かつ簡潔に実現する。

---

## 2. トレーサビリティ / Traceability
- 関連仕様: R7RS-small Section 6.6 (Characters)
  - `(char=? c1 c2 c3 ...)`: すべての文字が同一であるか判定。
  - `(char<? c1 c2 c3 ...)`: 各文字の Unicode スカラー値が厳密な単調増加順であるか判定。
  - `(char>? c1 c2 c3 ...)`: 各文字の Unicode スカラー値が厳密な単調減少順であるか判定。
  - `(char<=? c1 c2 c3 ...)`: 単調非減少順であるか判定。
  - `(char>=? c1 c2 c3 ...)`: 単調非増加順であるか判定。
- 関連ドキュメント: [r7rs_specification_compliance.md](../../ulisp/docs/r7rs_specification_compliance.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/lib/predicates.scm](../../ulisp/lib/predicates.scm) または [ulisp/lib/string.scm](../../ulisp/lib/string.scm) (文字順序比較述語の実装)
- [ ] [ulisp/tests/test_stdlib_r7rs.scm](../../ulisp/tests/test_stdlib_r7rs.scm) (文字比較テストケース追加)
- [ ] [ulisp/docs/r7rs_specification_compliance.md](../../ulisp/docs/r7rs_specification_compliance.md) (適合状況更新)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/556-implement-r7rs-character-comparison-predicates`

1. 文字比較述語の実装:
   - 2引数および複数引数（`c1 c2 . rest`）の再帰的単調比較として実装。
   - `char<?`: `(< (char->integer c1) (char->integer c2))`
   - `char>?`: `(> (char->integer c1) (char->integer c2))`
   - `char<=?`: `(<= (char->integer c1) (char->integer c2))`
   - `char>=?`: `(>= (char->integer c1) (char->integer c2))`
2. テストケースの追加:
   - 2文字の大小比較（`#\a` vs `#\b`、`#\A` vs `#\a` など）。
   - 3文字以上のチェイン比較（例: `(char<? #\a #\b #\c)` は `#t`、`(char<? #\a #\c #\b)` は `#f`）。
   - 等しい文字に対する `<=` / `>=` の振る舞い検証。
3. 全体テストの実行・パス確認 (`./test.sh`, `./test_c.sh`)。
4. `ulisp/docs/r7rs_specification_compliance.md` の適合チェックリスト更新。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `char<?`, `char>?`, `char<=?`, `char>=?` が実装されていること。
- [x] 2引数および可変長引数（3引数以上）で正確に判定できること。
- [x] `tests/test_stdlib_r7rs.scm` にテストが追加され合格すること。
- [x] `./test.sh` および `./test_c.sh` がエラーなく 100% PASS すること。
- [x] `ulisp/docs/r7rs_specification_compliance.md` の該当項目が更新されていること。
