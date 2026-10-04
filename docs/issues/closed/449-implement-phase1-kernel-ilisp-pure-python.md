---
ID: 449
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT] Phase 1: Kernel ILISP 最小構成の実装 (ID: 449)

## 1. 概要 / Summary
[DSN-31](../../docs/designs/DSN-31-ilisp_r7rs_intelligence_lisp_architecture_specification.md) および [ilisp/docs/BOOTSTRAP.md](../../ilisp/docs/BOOTSTRAP.md) に定義された「Phase 1: Kernel ILISP 最小構成」を純粋 Python（標準ライブラリのみ、外部依存ゼロ）で実装する。
手書き再帰下降 Reader、最小 S式 AST（Cons, Symbol, Cell, SequenceView）、23個のコアプリミティブを備えたレキシカル環境フレーム、Tree-walk 評価器、マクロ展開器（`define-macro`）、および対話型 REPL / CLI を構築し、初期ブートストラップ核として機能させる。

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [x] `ilisp/__init__.py` (ILISP パッケージエクスポート API)
- [x] `ilisp/types.py` (SourceLocation, Cons, Nil, Symbol, Cell, SequenceView, Procedure)
- [x] `ilisp/reader.py` (手書き再帰下降パーサ: Tokenizer, Reader, リーダーマクロ `'`, ```, `,`, `,@`)
- [x] `ilisp/env.py` (Environment レキシカルスコープ, 23個のコアプリミティブ, 基本 Python Interop)
- [x] `ilisp/evaluator.py` (Tree-walk 評価器, コア基本式 `quote`, `if`, `lambda`, `define`, `set!`, `begin`, `define-macro`)
- [x] `ilisp/repl.py` (対話型 REPL, 式評価, ファイル実行 CLI)
- [x] `tests/ilisp/test_kernel.py` (Kernel ILISP 単体テストスイート)
- [x] `docs/issues/README.md` (Issue 449 登録)

---

## 3. 実装方針 / Implementation Plan
Target Branch: `feat/449-implement-phase1-kernel-ilisp-pure-python`

1. **データ構造と型体系 (`ilisp/types.py`)**:
   - `SourceLocation`: ファイル、行、列情報の不変レコード。
   - `Cons`: `car`, `cdr`, `loc` を保持するペアノード。イテレータ対応、Scheme 記法文字列化（ドット対表示対応）。
   - `Nil`: 空リストシングルトン `()`。
   - `Symbol`: グローバルインターン機構（`Symbol.intern(name)`）を持つ識別子。
   - `Cell`: `set!` 対象変数をボックス化するミュータブルコンテナ。
   - `SequenceView`: Python リスト・タプルを $O(1)$ で `car`/`cdr` 走査する不透明ラッパー。
   - `Procedure`: クロージャおよび構文マクロ呼び出しオブジェクト。
2. **手書き再帰下降パーサ (`ilisp/reader.py`)**:
   - `Tokenizer`: 空白・コメント（`;` および `#;`）をスキップし、数値、文字列（エスケープ対応）、シンボル、カッコ、クォート記号をトークン化。
   - `Reader`: 再帰下降で S式を解析。リーダーマクロ（`'`, ```, `,`, `,@`）を `quote`, `quasiquote`, `unquote`, `unquote-splicing` に展開。
   - ストリーム処理 (`read_one`, `read_all`) の提供。
3. **レキシカル環境フレームとコアプリミティブ (`ilisp/env.py`)**:
   - 親環境ポインタを持つ `Environment`。
   - 23 個のコアプリミティブ：
     - リスト: `cons`, `car`, `cdr`, `pair?`, `null?`, `list`
     - シンボル・文字列: `symbol?`, `symbol->string`, `string?`, `string-append`, `string=?`
     - 等価性・真偽値: `eq?`, `eqv?`, `boolean?`, `not`
     - 四則演算・比較: `+`, `-`, `*`, `quotient`, `remainder`, `=`, `<`, `>`
     - 入出力: `read-char`, `write-char`, `peek-char`, `eof-object?`
   - Python 連携: `py-eval`, `py-call`, `py-import`, `py-get`, `py-set!`。
4. **Tree-walk 評価器 (`ilisp/evaluator.py`)**:
   - コア基本式: `quote`, `if`, `lambda`, `define`, `set!`, `begin`
   - マクロ展開: `define-macro` による構文置換
   - 高階関数、レキシカルスコープ、再帰の忠実な評価。
5. **REPL & CLI (`ilisp/repl.py`)**:
   - `ilisp` コマンドとして起動可能な対話型シェルおよびスクリプト実行インターフェース。
6. **テストと品質ゲート**:
   - 基本式、コアプリミティブ、高階関数、再帰ループ、マクロ、Python 相互運用のテスト網羅。
   - `make check_format`, `make static_analysis`, `make test` の 100% PASS。

---

## 4. 完了条件 / Success Criteria (DoD)
- [x] `ilisp` モジュールが純粋 Python 標準ライブラリのみで自律稼働すること
- [x] 手書き Reader がソース位置情報を保持し、リーダーマクロを含む S 式を正確に解析できること
- [x] 23 個のコアプリミティブと 6 大基本式が正確に動作すること
- [x] `define-macro` による構文マクロ展開が機能し、`when` や `let` を Scheme 側で定義・実行できること
- [x] Python リストとの $O(1)$ ゼロコピー走査 (`SequenceView`) が機能すること
- [x] 単体テストスイート（`tests/ilisp/test_kernel.py`）がすべて PASS すること
- [x] リポジトリの全品質ゲート（`flake8`, `isort`, `black`, `mypy --strict`, `pytest`）が 100% PASS すること
