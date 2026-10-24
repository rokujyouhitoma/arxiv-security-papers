---
ID: 601
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] ネイティブランタイムにおけるシンボル名表示の復元および未捕捉例外メッセージの構造化整形 (ID: 601)

## 1. 概要 / Summary
現在、ULisp ネイティブバイナリ（`bin/ulisp-boot` やフリースタンディング実行系）において、未捕捉例外（`unhandled exception`）が発生した際に、例外オブジェクト内のシンボルが一律 `#<symbol>` とマスクされて出力される。
そのため、例えば `(error "Unbound variable in LIR: car" 'car)` が投げられた場合でも、以下のように表示され、例外種別や引数シンボルが不可視となってしまう：
```text
*** ERROR: unhandled exception: (#<symbol> "Unbound variable in LIR: car" #<symbol>)
```

本 Issue では、`142_backend_x86_freestanding.scm` 等のネイティブランタイム出力ルーチン（`ulisp_print_value`）を改修し、シンボルポインタからシンボル名（文字列）を辿って正しく出力できるように復元する。また、例外オブジェクトが `(error msg irritants...)` 形式の場合に、人間可読な構造化メッセージとして整形出力する例外フォーマッタを実装する。

---

## 2. トレーサビリティ / Traceability
- **正典仕様書**:
  - [DSN-33 (ULisp 包括設計仕様書)](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
  - [R7RS 例外仕様準拠ドキュメント](../../ulisp/docs/r7rs_specification_compliance.md)
- **関連 Issue**:
  - Issue 531: 軽量大域脱出ハンドラスタックに基づく R7RS 例外処理機構の実装
  - Issue 552: ULisp自己ホストブートストラップにおけるLIR内car未束縛変数例外の修正
  - Issue 580: runtime.c の完全廃止と低水準 Scheme による完全自己完結ランタイムの実現

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/backend/142_backend_x86_freestanding.scm](../../ulisp/backend/142_backend_x86_freestanding.scm) (`ulisp_print_value` のシンボル出力処理および `ulisp_unhandled_exception`)
- [ ] [ulisp/backend/160_backend_c.scm](../../ulisp/backend/160_backend_c.scm) (C バックエンドの例外ハンドラ表示整合)
- [ ] [ulisp/runtime/printer.scm](../../ulisp/runtime/printer.scm) (Pure Scheme プリンタのシンボル表示確認)
- [ ] [ulisp/tests/passes/test_140_backend_x86.scm](../../ulisp/tests/passes/test_140_backend_x86.scm) (シンボル印字および例外出力テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/601-restore-symbol-printing-and-format-unhandled-exceptions`

1. **シンボル印字ルーチン（`ulisp_print_symbol`）のネイティブ実装**:
   - シンボルオブジェクトの内部構造（タグ、長さ、文字列バッファへのポインタ）を解析。
   - `ulisp_print_value` においてシンボルタグ（tag 2）検出時、`#<symbol>` ではなく実際のシンボル名文字列を出力するアセンブリルーチンを実装。
2. **未捕捉例外（`ulisp_unhandled_exception`）のメッセージ構造化**:
   - 単なるリストとしての印字 `(#<symbol> ...)` を廃止。
   - 先頭が `'error` や `'error-object` の場合、エラーメッセージ文字列と引数（irritants）を分離して改行インデント表示：
     ```text
     *** ERROR: Unbound variable in LIR: car
         Irritants: car
     ```
3. **単体テストと検証**:
   - `ulisp-boot` を通じた例外出力のテストケースを追加。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] ネイティブ実行系でシンボルが `#<symbol>` ではなく実名（例: `'car`, `'error`）として正確に出力されること。
- [ ] 未捕捉例外発生時に、エラー種別・メッセージ・対象変数が明瞭に区別されて標準エラー出力に整形表示されること。
- [ ] `make test_unit` および `bash ulisp/test.sh` が 100% PASS すること。
