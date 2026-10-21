---
ID: 557
種別: Feature
優先度: Medium
ステータス: Closed
---

# [FEAT] R7RS 文字列・リスト・ベクタ相互変換および文字列辞書順比較述語の実装 (ID: 557)

## 1. 概要 / Summary
R7RS 6.7 (Strings) および 6.8 (Vectors) に規定されている文字列とリスト、ベクタの相互変換手続き (`string->list`, `list->string`, `string->vector`, `vector->string`) と、辞書順比較述語 (`string<?`, `string>?`, `string<=?`, `string>=?`) を実装する。
すでに実装済みの `string-length`, `string-ref`, `make-string`, `string-set!`, `vector-ref`, `vector-length` 等を活用することで、高速かつ正確な標準シーケンス相互変換基盤を整備する。

---

## 2. トレーサビリティ / Traceability
- 関連仕様: R7RS-small Section 6.7 (Strings) & 6.8 (Vectors)
  - `(string->list string [start [end]])`: 文字列の部分列を構成文字のリストに変換。
  - `(list->string list)`: 文字のリストから新しい文字列を生成。
  - `(string->vector string [start [end]])`: 文字列の部分列を文字のベクタに変換。
  - `(vector->string vector [start [end]])`: 文字のベクタから文字列を生成。
  - `(string<? s1 s2 s3 ...)` / `string>?` / `string<=?` / `string>=?`: 文字列の辞書式順序比較。
- 関連ドキュメント: [r7rs_specification_compliance.md](../../ulisp/docs/r7rs_specification_compliance.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/lib/string.scm](../../ulisp/lib/string.scm) (文字列変換・辞書順比較手続きの実装)
- [x] [ulisp/lib/vector.scm](../../ulisp/lib/vector.scm) (ベクタ変換手続きの実装)
- [x] [ulisp/tests/test_stdlib_r7rs.scm](../../ulisp/tests/test_stdlib_r7rs.scm) (変換・比較テスト追加)
- [x] [ulisp/docs/r7rs_specification_compliance.md](../../ulisp/docs/r7rs_specification_compliance.md) (適合状況更新)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/557-implement-r7rs-string-vector-list-conversions-and-string-ordering`

1. 変換手続きの実装:
   - `string->list`: `start` 〜 `end` のインデックス範囲をループし、`string-ref` で取得した文字をリスト構築（または末尾から cons）。
   - `list->string`: リストの長さを計測し、`make-string` で領域確保後、`string-set!` で順次設定。
   - `string->vector`: 同様に指定範囲の文字をベクタへ転送。
   - `vector->string`: 文字のベクタから文字列を生成。
2. 辞書順比較述語の実装:
   - 2つの文字列 `s1`, `s2` の長さを取得し、先頭文字から `char=?` でない文字が見つかるまで比較。
   - 共通プレフィックスが等しい場合は文字列の長さで判定。
   - 複数引数（`s1 s2 . rest`）の単調比較に対応。
3. テストの作成・実行:
   - 空文字列・空ベクタ・空リストを含む各種変換テスト。
   - 部分指定（start/end）対応の検証。
   - `string<?` などの辞書順比較（大文字小文字、長さの異なる文字列など）の網羅的テスト。
4. 全体テスト (`./test.sh`, `./test_c.sh`) の通過確認。
5. `ulisp/docs/r7rs_specification_compliance.md` の更新。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `string->list`, `list->string`, `string->vector`, `vector->string` が実装されていること。
- [x] `string<?`, `string>?`, `string<=?`, `string>=?` が複数引数対応で実装されていること。
- [x] `tests/test_stdlib_r7rs.scm` にテストが追加され、すべて PASS すること。
- [x] `./test.sh` および `./test_c.sh` がエラーなく 100% PASS すること。
- [x] `ulisp/docs/r7rs_specification_compliance.md` の対象項目が `[x]` に更新されていること。

