---
ID: 659
種別: Feature
優先度: Medium
ステータス: Closed (Completed)
---

# [FEAT/ENH] R7RS §4.1.7 大文字小文字無視ファイル包含構文 (include-ci) の実装 (ID: 659)

## 1. 概要 / Summary
R7RS-small §4.1.7 (Inclusion: `include-ci`) に準拠し、外部ファイルを読み込む際に大文字・小文字を同一視（Case-insensitive / Case-folding）して S 式をパースしプログラムへ静的結合する `include-ci` 構文を完全実装する。
ULisp では通常の `include` は実装済み（△）であるが、大文字小文字無視版である `include-ci` が未実装（×）であるため、大文字混じりやレガシー R5RS/R7RS コード、大文字で記述された標準ライブラリ（例: `LAMBDA`, `DEFINE`, `COND`）を透過的に読み込めるようにする。
`include-ci` はライブラリ宣言内（`define-library` 内）およびトップレベルファイル包含の両方で透過的に動作する。

---

## 2. トレーサビリティ / Traceability
- 関連仕様:
  - R7RS-small §4.1.7: Inclusion (`include-ci`)
  - R7RS-small §5.6.1: Library declarations (`include-ci`)
  - [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) §1.1 式とコア構文
  - [DSN-33 (ULisp 包括設計仕様書)](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/frontend/010_library.scm](../ulisp/frontend/010_library.scm) (ライブラリ宣言内およびトップレベル式での `include-ci` 包含処理・case-folding 式変換)
- [x] [ulisp/frontend/020_macro_expander.scm](../ulisp/frontend/020_macro_expander.scm) (`core-form-or-primitive?` への `include-ci` 登録)
- [x] [ulisp/lib/scheme/base.sld](../ulisp/lib/scheme/base.sld) (`include-ci` のエクスポート)
- [x] [ulisp/lib/reader.scm](../ulisp/lib/reader.scm) (リーダー補助・case-folding ユーティリティ)
- [x] [ulisp/docs/ref_r7rs_compliance.md](../ulisp/docs/ref_r7rs_compliance.md) (R7RS 準拠状況テーブル更新: × から ◎)
- [x] [ulisp/tests/test_r7rs_include_ci.scm](../ulisp/tests/test_r7rs_include_ci.scm) (新規単体テスト)
- [x] [ulisp/Makefile](../ulisp/Makefile) (テストターゲット統合)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/659-implement-r7rs-include-ci-syntax`

1. **Case-Folding 再帰変換ユーティリティの実装**:
   - `fold-case-datum`: 任意の S 式に対し、シンボル（識別子）を小文字に正規化する。
     - シンボル: `(string->symbol (string-downcase (symbol->string sym)))`
     - ペア/リスト: `(cons (fold-case-datum (car p)) (fold-case-datum (cdr p)))`
     - ベクタ: 各要素を再帰的に変換
     - `%source-loc`: 内部の式のみを変換し位置情報を維持
     - 文字列、文字、数値、真偽値、バイトベクタ: 不変のまま保持（文字列リテラルや文字定数の大文字小文字は破壊しない）。

2. **ファイル包含処理の拡充 (`slurp-included-files-ci`)**:
   - `slurp-single-file` に `case-fold?` 引数を追加するか、または `slurp-single-file-ci` を導入。
   - `(include-ci "path" ...)` 検出時に、ファイルを読み込んだ各フォームを `fold-case-datum` で正規化。

3. **`define-library` 内およびトップレベルでの結合**:
   - `parse-define-library-form` において `(include-ci ...)` 節を検出し、小文字変換されたボディ式をライブラリの `body-forms` に結合。
   - `expand-includes-in-forms` において `(include-ci ...)` を検出し、再帰的にファイル読み込み・正規化・スプライシング。

4. **単体テストの作成**:
   - 大文字で書かれた `(DEFINE (ADD-TWO X Y) (+ X Y))` 等の外部ファイルを `include-ci` で読み込み、`add-two` として正しく呼び出せることを検証。
   - 通常の `include` は大文字シンボルがそのまま保持されることを確認（副作用なし）。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `include-ci` で指定されたファイル内の大文字シンボル（変数名、キーワード等）が小文字に正規化されてインライン展開される
- [x] 文字列リテラル `"FOO"` や文字 `#\A` の大文字が小文字化されずにそのまま維持される
- [x] `define-library` 宣言内およびトップレベルの両方で `include-ci` が正常動作する
- [x] 既存の `include`（Case-sensitive）の動作に影響を与えない
- [x] `ref_r7rs_compliance.md` のステータスが × から ◎ に更新される
- [x] `make test` を通過する
