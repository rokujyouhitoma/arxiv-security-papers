---
ID: 613
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT/ENH] ILisp における R7RS include / include-ci 構文およびライブラリ宣言 include の実装 (ID: 613)

## 1. 概要 / Summary

ILisp（Pure Python Scheme 実行系）において、R7RS Section 4.1.7（式としての `include` / `include-ci`）および Section 5.6.1（`define-library` 内の `include` / `include-ci` / `include-library-declarations` 宣言）が未実装となっている。
このため、ULisp のブートストラップスクリプト（`ulisp/bootstrap.sh`）において、Gauche やネイティブシード（`ulisp-boot`）が存在しない環境のフォールバック実行時、R7RS `(include ...)` で構成されたモジュール群を直接実行することができず、Makefile によるシェルの `cat` 物理結合ファイル（`compiler.scm`）に依存せざるを得ない構造的要因となっている。

本 Issue では、ILisp の評価器（`ilisp/evaluator.py`）、構文定義（`ilisp/syntax.py`）、リーダー（`ilisp/reader.py`）、およびモジュールシステム（`ilisp/module.py`）に `include` / `include-ci` / `include-library-declarations` 構文を正式に実装する。
これにより、ILisp 自身が外部 Scheme ソースファイルを再帰的・動的にスプライシングして読み込めるようにし、ホスト環境としてのポータビリティを飛躍的に向上させ、将来的な `compiler.scm` の物理 `cat` 結合の完全撤廃を可能にする。

---

## 2. トレーサビリティ / Traceability

- **正典仕様書**:
  - [R7RS Small Specification (Revised^7 Report on the Algorithmic Language Scheme)](../../ulisp/docs/r7rs_specification_compliance.md)
    - Section 4.1.7: `include`, `include-ci` (Derived expression types / Splicing)
    - Section 5.6.1: Library declarations (`include`, `include-ci`, `include-library-declarations`)
  - [DSN-33 (ULisp 包括設計仕様書)](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
- **関連 Issue**:
  - [Issue 452: ILisp Phase 2: R7RS Core Features](../closed/452-implement-phase2-r7rs-core-features.md)
  - [Issue 455: ILisp R7RS Module System](../closed/455-implement-r7rs-module-system.md)
  - [Issue 606: ビルド時 cat 結合の廃止と R7RS include 構文によるソース位置追跡基盤の導入](../closed/606-replace-cat-bundle-with-r7rs-include-and-source-tracking.md)
  - [Issue 607: 外部シンボル（extern）参照解決と標準ライブラリ・コンパイラの2分割 .o 静的リンク基盤の導入](../closed/607-support-extern-symbols-and-split-stdlib-compiler-linking.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [ilisp/evaluator.py](../../ilisp/evaluator.py) (`_SPECIAL_FORM_NAMES` への `include` / `include-ci` 登録および評価・スプライシング処理の実装)
- [x] [ilisp/syntax.py](../../ilisp/syntax.py) (`core_forms` への `include` / `include-ci` 登録)
- [x] [ilisp/reader.py](../../ilisp/reader.py) (ファイルパスからの S 式連続読み込みユーティリティ `read_all_from_file(filepath, fold_case=False)`)
- [x] [ilisp/module.py](../../ilisp/module.py) (`execute_define_library` 内での `(include ...)` / `(include-ci ...)` / `(include-library-declarations ...)` 宣言の展開・評価)
- [x] [ilisp/tests/test_include.py](../../ilisp/tests/test_include.py) (新規: include 構文、相対パス解決、循環依存検知、パストラバーサル遮断の網羅的単体テスト)
- [x] [docs/issues/613-implement-ilisp-r7rs-include-and-include-ci-support.md](613-implement-ilisp-r7rs-include-and-include-ci-support.md) (本 Issue ドキュメント)
- [x] [docs/issues/README.md](README.md) (Issue 管理台帳の更新)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/613-implement-ilisp-r7rs-include-and-include-ci-support`

### 4.1 リーダー拡張 (`ilisp/reader.py`)
- `read_all_from_file(filepath: str, fold_case: bool = False) -> List[Any]` 関数を追加。
- 指定されたファイルパスを UTF-8 でオープンし、`Reader` インスタンスを生成して EOF までの全 S 式リストを返却する。
- `fold_case=True` の場合は大文字小文字をフォールド（すべて小文字に正規化）して読み込む。

### 4.2 ファイル探索・循環検知・セキュリティ境界
- **探索パス解決 (`_resolve_include_path`)**:
  1. インクルード元ファイル（現在評価中の式の `loc.filename`）が存在する場合は、その親ディレクトリを最優先の基準ディレクトリとする。
  2. 基準ディレクトリからの相対パスで存在すればその絶対パスを採用。
  3. 存在しない場合、環境変数 `ILISP_LOAD_PATH`（コロン区切り）およびカレント作業ディレクトリ（CWD）から順次探索。
  4. 見つからない場合は `SchemeException`（`file-error` 相当）を発出。
- **循環インクルード検知**:
  - スレッドローカルまたは評価器コンテキストでアクティブなインクルードパスのスタック（`_active_include_files: Set[str]`）を管理。
  - 同一ファイル（正規化絶対パス `os.path.realpath`）が既にスタック内に存在する場合、`SchemeException(f"include: circular dependency detected for '{resolved_path}'")` を発出。
- **セキュリティ・パストラバーサル境界**:
  - 機密システムファイルへの不正アクセスやディレクトリトラバーサル攻撃（例: `/etc/passwd` や `..` 連打）を遮断。安全なプロジェクト境界外への不正エスケープに対して適切に検証を実施。

### 4.3 式としての `include` / `include-ci` (`ilisp/evaluator.py`)
- `_SPECIAL_FORM_NAMES` に `"include"` および `"include-ci"` を登録。
- `eval_expr` 内で `op_name in ("include", "include-ci")` をハンドリング:
  - 引数リストを検証（各引数は文字列であること）。
  - 各ファイルを順次探索・読み込み、全 S 式を 1 つの平坦なリスト `all_exprs` にスプライシング（`begin` セマンティクス）。
  - 式が空の場合は `NIL` を返却。
  - 式が存在する場合、最後の式以外のすべての式を `curr_env` で先行評価し、最後の式を `curr_expr` に設定してトランポリンループを `continue` することで末尾呼出し最適化（TCO）を維持。

### 4.4 `define-library` 内の宣言サポート (`ilisp/module.py`)
- `execute_define_library` において、`decl_type` に `"include"`, `"include-ci"`, `"include-library-declarations"` を追加。
- `include` / `include-ci`:
  - 各ファイルから読み込まれた式群を `lib_env` 内で `eval_expr` により順次評価（`begin` 宣言と同等）。
- `include-library-declarations`:
  - 各ファイルから読み込まれた宣言群（`(export ...)`, `(import ...)`, `(begin ...)`, `(include ...)` 等）を、未処理の宣言キューにスプライシングして再帰的に処理。

---

## 5. 完了条件 / Success Criteria (DoD)

- [x] `ilisp` において `(include "path/to/file.scm")` がトップレベル式として正しく読み込まれ、定義・式が現在の環境に評価・反映されること
- [x] `(define-library (foo) (include "body.scm") ...)` のように、ライブラリ定義内での `include` / `include-ci` / `include-library-declarations` 宣言が正しく機能すること
- [x] 複数のファイルを `(include "a.scm" "b.scm")` のように順序正しくインクルードできること
- [x] ネストしたインクルード（A が B をインクルード）において相対パスが正しく解決されること
- [x] 循環インクルード（`a.scm` ⇄ `b.scm`）が検知され、無限再帰にならず決定論的に `SchemeException` で終了すること
- [x] 存在しないファイルに対して分かりやすいエラーが発出されること
- [x] `include-ci` においてシンボルが大文字小文字を無視して同一シンボルとして読み込まれること
- [x] `pytest tests/ilisp/test_include.py` が 100% PASS すること (19 / 19 passed)
- [x] `make py_compile` および `make static_analysis` がエラー 0 件で合格すること
- [x] `make -C ulisp test` が完全に PASS すること (Phase 1-7, 38 nanopass unit tests, fixed-point bootstrap verification)
