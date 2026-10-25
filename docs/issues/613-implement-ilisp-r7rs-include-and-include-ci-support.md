---
ID: 613
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] ILisp における R7RS include / include-ci 構文およびライブラリ宣言 include の実装 (ID: 613)

## 1. 概要 / Summary

ILisp（Pure Python Scheme 実行系）において、R7RS Section 4.1.7（式としての `include` / `include-ci`）および Section 5.6.1（`define-library` 内の `include` / `include-ci` 宣言）が未実装となっている。
このため、ULisp のブートストラップスクリプト（`ulisp/bootstrap.sh`）において、Gauche やネイティブシード（`ulisp-boot`）が存在しない環境のフォールバック実行時、R7RS `(include ...)` で構成された `compiler_entry.scm` や `entry_core.scm` を直接実行することができず、Makefile によるシェルの `cat` 物理結合ファイル（`compiler.scm`）に依存せざるを得ない構造的要因となっている。

本 Issue では、ILisp の評価器（`ilisp/evaluator.py`）、構文定義（`ilisp/syntax.py`）、およびモジュールシステム（`ilisp/module.py`）に `include` / `include-ci` 構文を正式に実装する。
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
  - [Issue 606: ビルド時 cat 結合の廃止と R7RS include 構文によるソース位置追跡基盤の導入](606-replace-cat-bundle-with-r7rs-include-and-source-tracking.md)
  - [Issue 607: 外部シンボル（extern）参照解決と標準ライブラリ・コンパイラの2分割 .o 静的リンク基盤の導入](607-support-extern-symbols-and-split-stdlib-compiler-linking.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [ilisp/evaluator.py](../../ilisp/evaluator.py) (`_SPECIAL_FORM_NAMES` への `include` / `include-ci` 登録および評価・スプライシング処理の実装)
- [ ] [ilisp/syntax.py](../../ilisp/syntax.py) (`include` 構文の検証・AST パースハンドラ)
- [ ] [ilisp/module.py](../../ilisp/module.py) (`execute_define_library` 内での `(include ...)` / `(include-ci ...)` 宣言の読み込みおよび環境への展開)
- [ ] [ilisp/reader.py](../../ilisp/reader.py) (ファイル単位の S 式連続読み込みユーティリティ `read_all_from_file`)
- [ ] [ilisp/tests/test_include.py](../../ilisp/tests/test_include.py) (新規: include 構文、相対パス解決、循環依存検知、パストラバーサル拒絶の単体テスト)
- [ ] [docs/issues/613-implement-ilisp-r7rs-include-and-include-ci-support.md](613-implement-ilisp-r7rs-include-and-include-ci-support.md) (本 Issue ドキュメント)
- [ ] [docs/issues/README.md](README.md) (Issue 管理台帳の更新)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/613-implement-ilisp-r7rs-include-and-include-ci-support`

1. **特殊形式としての `include` / `include-ci` の登録**:
   - `ilisp/evaluator.py` の `_SPECIAL_FORM_NAMES` に `"include"` および `"include-ci"` を追加。
   - トップレベル式または `begin` 内部で `(include "path1" "path2" ...)` が評価された際、指定された各ファイルから全 S 式を読み込み、現在の環境において順次シーケンシャルに評価（`begin` と同等のスプライシングセマンティクス）する。
2. **`define-library` 内の宣言サポート**:
   - `ilisp/module.py` の `execute_define_library` において、`decl_type == "include"` および `decl_type == "include-ci"` を許可。
   - ファイルから読み込まれた式群をライブラリの本体式リスト（`body_exprs`）または宣言リストにスプライシング統合。
3. **ファイル探索とセキュリティ境界**:
   - 探索パス解決：現在の Scheme ソースファイルが存在するディレクトリからの相対パス、および環境変数 `ILISP_LOAD_PATH` / カレント作業ディレクトリを基準とする。
   - 循環インクルード検知：探索中のファイルパスをセットで追跡し、循環参照時に `SchemeException`（`include: circular dependency detected`）を発出。
   - パストラバーサル防止：許可されたプロジェクトルート外への不正遡行を遮断。
4. **ケースインセンシティブ `include-ci`**:
   - `include-ci` の場合、リーダーのシンボル読み込みフラグを一時的に大文字小文字無視（Fold-case）モードにして読み込む。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `ilisp` において `(include "path/to/file.scm")` がトップレベル式として正しく読み込まれ、定義・式が現在の環境に評価・反映されること
- [ ] `(define-library (foo) (include "body.scm") ...)` のように、ライブラリ定義内での `include` 宣言が正しく機能すること
- [ ] 複数のファイルを `(include "a.scm" "b.scm")` のように順序正しくインクルードできること
- [ ] 循環インクルード（`a.scm` ⇄ `b.scm`）が検知され、無限再帰にならず決定論的に例外終了すること
- [ ] パストラバーサルによる意図しないファイルアクセスが安全に拒絶されること
- [ ] `pytest ilisp/tests/test_include.py` が 100% PASS すること
- [ ] `make py_compile` および `make static_analysis` がエラー 0 件で合格すること
