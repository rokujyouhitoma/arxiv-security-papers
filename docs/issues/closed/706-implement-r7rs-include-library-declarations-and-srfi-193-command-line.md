---
ID: 706
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT/ENH] R7RS-small 残余構文 (include-library-declarations) および SRFI 193 (command-line) の完全実装 (ID: 706)

## 1. 概要 / Summary
ULisp の R7RS-small 言語仕様準拠率を最大化するため、セクション 5.6 (Libraries) で唯一未実装 (`×`) となっているライブラリ宣言分割取り込み構文 `(include-library-declarations <string1> ...)`、およびセクション 6.14 (System Interface) で部分サポート (`△`) となっている `(command-line)` ならびに **SRFI 193 (`(srfi 193)` Command line)** を完全実装し、両項目を **◎（完全サポート）** に引き上げる。

---

## 2. トレーサビリティ / Traceability
- 関連資料:
  - [R7RS 仕様準拠状況リファレンス](../../../ulisp/docs/ref_r7rs_compliance.md) (§1.2, §1.3, §2.5)
  - R7RS-small §5.6.1 (Library Syntax: `include-library-declarations`)
  - R7RS-small §6.14 (System interface: `command-line`)
  - [SRFI 193: Command line](https://srfi.schemers.org/srfi-193/srfi-193.html)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [010_library.scm](../../../ulisp/frontend/010_library.scm)
- [x] [posix.scm](../../../ulisp/lib/posix.scm)
- [x] [process-context.sld](../../../ulisp/lib/scheme/process-context.sld)
- [x] [193.sld](../../../ulisp/lib/srfi/193.sld) (新規)
- [x] [helpers.scm](../../../ulisp/compiler/helpers.scm)
- [x] [Makefile](../../../ulisp/Makefile)
- [x] [test_010_library.scm](../../../ulisp/tests/passes/test_010_library.scm)
- [x] [test_r7rs_cond_expand.scm](../../../ulisp/tests/test_r7rs_cond_expand.scm)
- [x] [ref_r7rs_compliance.md](../../../ulisp/docs/ref_r7rs_compliance.md)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/706-implement-r7rs-include-library-declarations-and-srfi-193-command-line`

1. **`include-library-declarations` の実装 ([010_library.scm](../../../ulisp/frontend/010_library.scm))**:
   - `parse-define-library-form` 内のライブラリ宣言ディスパッチに `((and (pair? d) (eq? (car d) 'include-library-declarations)) ...)` を追加する。
   - `slurp-included-files-mode (cdr d) #f` により指定されたファイル群から S 式リストを読み取り（パストラバーサル防御 `path-traversal?` および循環インクルード検出 `*include-path-stack*` を通過）、`strip-source-loc` した宣言群を残余宣言リスト `(cdr rest)` の先頭に `append` して再帰的に `export`, `import`, `begin`, `include`, `cond-expand`, ネストした `include-library-declarations` を処理する。
2. **R7RS §6.14 `command-line` および SRFI 193 手続き群の実装 ([posix.scm](../../../ulisp/lib/posix.scm), [193.sld](../../../ulisp/lib/srfi/193.sld))**:
   - `*command-line-override*` および `*script-file-override*` セルを導入し、`command-line` を `case-lambda` で 0 引数（現在のコマンドライン文字列リスト返却）および 1 引数（SRFI 193 パラメータオブジェクト互換の動的更新）の両対応とする。
   - `command-name`: `(car (command-line))` が空文字列 `""` の場合は `#f` を返し、それ以外はディレクトリパス（最後の `/` まで）および末尾の `.scm` 拡張子（存在する場合）を除去したベース名を返す。
   - `command-args`: `(cdr (command-line))` を返す。
   - `script-file`: スクリプト実行時パス（AOT バイナリ単体実行時は `#f`、パラメータ指定時はその文字列）を返す `case-lambda` パラメータ手続き。
   - `script-directory`: `(script-file)` が文字列の場合は最後の `/` までのディレクトリ文字列（`/` を含まない場合は `"./"`）、`#f` の場合は `#f` を返す。
   - `(features)` リストおよび `ulisp-supported-feature?` に `srfi-193` を追加し、`builtin-library-name?` に `(srfi 193)` を追加する。
3. **テストと検証**:
   - [test_010_library.scm](../../../ulisp/tests/passes/test_010_library.scm) に `include-library-declarations` の単体テストを追加。
   - [test_r7rs_cond_expand.scm](../../../ulisp/tests/test_r7rs_cond_expand.scm) に `command-line`, `command-name`, `command-args`, `script-file`, `script-directory` の AOT テストを追加。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `parse-define-library-form` が `(include-library-declarations <path> ...)` を正しく展開し、`export`/`import`/`begin` を含む外部宣言ファイルを取り込めること。
- [x] `command-line`, `command-name`, `command-args`, `script-file`, `script-directory` が R7RS §6.14 および SRFI 193 仕様通りに動作すること。
- [x] `ulisp/lib/srfi/193.sld` が作成され、`make verify_r7rs_traceability` および AOT テストが 100% PASS すること。
- [x] [ref_r7rs_compliance.md](../../../ulisp/docs/ref_r7rs_compliance.md) で `include-library-declarations`, `command-line`, `SRFI 193` が **◎** に更新されていること。
