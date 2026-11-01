---
ID: 654
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] R7RS-large (SRFI 28) 基本フォーマット文字列手続き (format) の実装 (ID: 654)

## 1. 概要 / Summary
R7RS-large / SRFI 28 で規定されている基本文字列整形手続き `(format <format-string> <arg> ...)` を ULisp に実装する。
`~a` (display 形式), `~s` (write 形式), `~%` (改行), `~~` (チルダ文字リテラル) などの標準フォーマット指定子を解釈し、整形済み文字列を生成する。テストコード、コンパイラ診断、CLI 出力メッセージの整形を大幅に簡潔化する。

---

## 2. トレーサビリティ / Traceability
- R7RS-large: Tangerine / その他主要仕様 / SRFI 28 (Basic format strings)
- 仕様リファレンス: [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) §2.3
- 関連モジュール: [ulisp/lib/printer.scm](../../ulisp/lib/printer.scm), [ulisp/lib/string.scm](../../ulisp/lib/string.scm), [ulisp/lib/port.scm](../../ulisp/lib/port.scm)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/lib/format.scm](../../ulisp/lib/format.scm) (新規モジュール)
- [ ] [ulisp/lib/srfi/28.sld](../../ulisp/lib/srfi/28.sld) (新規ライブラリ定義)
- [ ] [ulisp/docs/ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md)
- [ ] [ulisp/tests/test_format.scm](../../ulisp/tests/test_format.scm) (新規テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/654-implement-srfi-28-basic-format-string`

1. `open-output-string` と文字列ポートを活用し、フォーマット文字列を1文字ずつ走査するパーサーループを構築。
2. 指定子 `~a` で `display`、`~s` で `write` を呼び出し、引数リストから順次値をバッファへ書き出す。
3. 未知のフォーマット指定子や引数不足時に適切なエラー（`error`）を送出。
4. `get-output-string` で完成した文字列を取得・返却。
5. `(srfi 28)` ライブラリとしてエクスポート。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `(format "Result: ~a, S-expr: ~s~%" 42 '(a b))` が期待通りの文字列を出力すること。
- [ ] 単体テストを追加し、回帰テストを通過すること。
- [ ] `ref_r7rs_compliance.md` の SRFI 28 ステータスを更新すること。

