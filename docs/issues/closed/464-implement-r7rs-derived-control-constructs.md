# Issue #464: R7RS 制御構造・派生構文の完備 (case-lambda, cond/case =>, lazy evaluation)

## 1. 概要 (Overview)
R7RS-small 第4.2節「Derived expressions（派生式）」に規定されている高度な制御構造と派生構文群を ILISP に実装・完備する。
具体的には、アリティ多重ディスパッチ構文 `case-lambda`、`cond` および `case` における一級関数レシーバ連携構文 `=>` (arrow syntax)、ならびに遅延評価機構（`delay`, `delay-force`, `force`, `promise?`, `make-promise`）を実装する。

## 2. 背景・動機 (Background & Motivation)
- **R7RS 4.2 派生式の完全準拠**: ILISP は `if`, `begin`, `lambda`, `let`, `do`, `when`, `unless` 等の基本制御構造を備えているが、R7RS 4.2 に規定される多重アリティ関数定義 `case-lambda`、条件評価値を関数へ渡す `=>` 構文、およびストリームや無限列を扱う遅延評価 (`delay` / `force`) が未実装であった。
- **柔軟な API 定義**: `case-lambda` により、引数の個数（0個、1個、2個、可変長など）に応じたオーバーロードが単一の関数オブジェクトとして宣言可能となり、標準ライブラリの利便性が飛躍的に向上する。
- **安全な関数型パイプライン**: `cond` / `case` の `=>` 構文により、述語判定結果（例えば連想リスト検索 `assoc` の結果）を一時変数を手動定義することなく後続の手続きへ安全に渡すことができる。
- **メモリ効率の高い遅延計算**: `delay` / `delay-force` による反復的アンロールとメモ化（Promise）により、空間計算量 $O(1)$ の末尾再帰的遅延ストリーム処理が可能となる。

## 3. 要件仕様 (Requirements Specification)
### 3.1 case-lambda (R7RS 4.2.9)
- `(case-lambda (<formals> <body> ...) ...)`
  - 呼び出し時に渡された実引数の個数と、各節の `<formals>`（固定引数リスト、ドット付き可変長リスト、単一シンボル）を上から順に照合。
  - 最初に合致した節の `<body>` を実行。合致する節が存在しない場合はエラーを送出。
  - レキシカルスコープおよびトランポリン TCO を正しく維持する。

### 3.2 cond および case の => 構文 (R7RS 4.2.1)
- `cond`:
  - `(<test> => <recipient>)`: `<test>` が真（`#f` 以外）の場合、その評価値を単一引数として `<recipient>`（1引数関数）に適用した結果を返却。
  - `(<test>)`: `<test>` の評価値自身を返却。
- `case`:
  - `((<datum> ...) => <recipient>)`: キーがマッチした場合、キー評価値を `<recipient>` に適用。
  - `(else => <recipient>)`: マッチしなかった場合、キー評価値を `<recipient>` に適用。

### 3.3 遅延評価 (Lazy evaluation) (R7RS 4.2.5)
- `(delay <expression>)`: `<expression>` の評価を遅延させる Promise オブジェクトを返却。
- `(delay-force <expression>)`: Promise を返す式の評価を遅延させ、強制評価時に再帰的にフラット化（末尾再帰安全）。
- `(force <promise>)`: Promise を評価し、結果をメモ化。2回目以降の `force` ではメモ化された値を即座に返却。
- `(promise? <obj>)`: Promise オブジェクトかどうかの型述語。
- `(make-promise <obj>)`: 即座に `<obj>` を値とする解決済 Promise を返却（既に Promise の場合はそのまま返却）。

## 4. 影響範囲・対象ファイル (Target Files)
- `ilisp/types.py`: `Promise` 型および `is_promise` 述語の定義
- `ilisp/env.py`: `apply`, `promise?`, `force`, `make-promise`, `__make-promise-from-thunk` の登録
- `ilisp/stdlib/base.ilisp`:
  - `cond` マクロの `=>` および `(test)` 拡張
  - `case` マクロの `=>` 拡張
  - `case-lambda` マクロの実装
  - `delay`, `delay-force` マクロの実装
- `ilisp/backend/py_codegen/compiler.py`:
  - `Promise`, `to_lisp_list` のランタイムインポート追加
  - 可変長引数（Symbol, Dotted list）コンパイルおよび Scheme リスト変換サポート
- `tests/ilisp/test_derived_control.py`: 新規テストスイート
- `ilisp/docs/SPEC_R7RS.md`: 準拠ステータス更新
- `docs/issues/closed/464-implement-r7rs-derived-control-constructs.md`: 本 Issue ファイル

## 5. DoD (Definition of Done)
- [x] `case-lambda` で固定長・可変長引数のアリティディスパッチが正しく動作する。
- [x] `cond` および `case` で `=>` (arrow syntax) が正しく動作する。
- [x] `delay`, `force`, `delay-force`, `make-promise`, `promise?` によるメモ化・遅延評価が正しく動作する。
- [x] Backend A (トランスパイラ) でのコンパイル・実行が正しくパスする。
- [x] `tests/ilisp/test_derived_control.py` を含む全テストが 100% PASS。
- [x] `flake8` 0 警告、`mypy --strict` 0 エラー。
- [x] `ilisp/docs/SPEC_R7RS.md` の特殊形式・コア構文および遅延評価カテゴリが更新される。

## 6. 実装成果と品質検証 (Verification & Results)
- `ilisp/types.py`:
  - `Promise` クラス新設（反復的アンロールによるスタックオーバーフロー耐性、遅延ストリーム対応、メモ化）。
- `ilisp/env.py`:
  - `prim_apply`: 先行引数と末尾リストを展開した多引数関数適用。
  - `prim_promise_p`, `prim_make_promise`, `prim_force`: 遅延評価プリミティブ。
- `ilisp/stdlib/base.ilisp`:
  - `cond` / `case`: `=>` (arrow recipient) 構文および `(test)` 単一要素構文の完全脱糖マクロ。
  - `case-lambda`: 引数個数に応じた多重クロージャ節ディスパッチマクロ（固定長、ドット付き可変長、単一シンボル対応）。
  - `delay`, `delay-force`: サンク生成マクロ。
- `ilisp/backend/py_codegen/compiler.py`:
  - 可変長引数（`*args`）の AST コード生成と `to_lisp_list` による Scheme リスト変換サポート。
- テストと品質ゲート:
  - `tests/ilisp/test_derived_control.py`（22件）を含む全 243 件の ilisp テストが 100% PASS。
  - `flake8` 0 警告、`mypy --strict ilisp` 0 エラー。
  - `ilisp/docs/SPEC_R7RS.md` の特殊形式・コア構文カテゴリ準拠率 100% (18/18)、遅延評価カテゴリ準拠率 100% (5/5) を達成。
