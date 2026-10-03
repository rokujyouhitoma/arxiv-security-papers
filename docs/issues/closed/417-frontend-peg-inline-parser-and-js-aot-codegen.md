---
ID: 417
種別: Feature
優先度: High
ステータス: Closed
完了日: 2026-10-03
---

# [FEAT/ENH] WebフロントエンドJS向けPEGインラインパーサー換装およびPEG AOTコンパイラ JavaScriptコードジェネレータ基盤の実装 (Phase 1 & Phase 2) (ID: 417)

## 1. 概要 / Summary

現在、Webフロントエンド（`site/js/evaluator.js`）におけるインラインマークダウン（強調・コード・リンク等）の処理は、単純な正規表現置換（`.replace(/\*\*(.*?)\*\*/g, ...)` 等）で行われており、コードスパン内の強調記法の誤爆、入れ子構造やエスケープシーケンスの破綻リスクが存在していた。
本 Issue では、2つの段階（Phase 1 & Phase 2）によりフロントエンドにおける構文解析の堅牢性と開発効率を飛躍的に向上させた。

1. **Phase 1 (JS PEG インラインパーサー換装)**:
   `site/js/frameworks/query-validator.js` で提供されている Pure JavaScript 製の Packrat PEG コンビネータ基盤（`window.Application.frameworks.peg`）を活用し、`site/js/evaluator.js` のインラインマークダウン解析を正規表現置換から PEG パーサーに刷新した。
   コードスパン（`` `code` ``）内の特殊文字保護、エスケープシーケンス（`\*`, `\[` 等）の適正処理、リンクネストの確実な解決を保証した。
2. **Phase 2 (Python PEG AOT コンパイラの JavaScript コードジェネレータ実装)**:
   DSN-25 仕様に基づく事前コンパイラ `src/core/structures/peg_compiler/` に `--target js`（JavaScript コードジェネレータ `codegen_js.py`）を実装し、`.peg` 文法ファイルから純粋 JavaScript 向けの最適化パーサーを AOT 自動生成可能にした。
   CLI（`tools/peg_compiler/compile_peg.py` および `cli.py`）に統合し、単体テストを整備した。

---

## 2. トレーサビリティ / Traceability

- 関連設計書:
  - [DSN-25: Pure-Python Packrat PEG 構文解析エンジン設計書](../designs/DSN-25-pure_python_packrat_peg_parser_engine.md) (第7節 AOT コンパイラ実戦投入)
  - [DSN-27: モジュール型 Web フロントエンド・フレームワーク ＆ クライアントアーキテクチャ設計仕様書](../designs/DSN-27-modular_frontend_framework_and_client_architecture.md) (セクション 6.5, 8)
- 関連 Issue:
  - [Issue 284: 純粋 Python 製汎用 Packrat PEG コアランタイム基盤の実装](closed/284-implement-pure-python-packrat-peg-parser-core.md)
  - [Issue 293: DSN-25 Phase 2: Packrat PEG 事前コンパイラ (AOT Compiler) 基盤の実装](closed/293-implement-dsn25-phase2-peg-ahead-of-time-compiler.md)
  - [Issue 347: QueryValidator: src/core/structures/peg.py クエリ構文の JS 移植と構文検証](closed/347-port-peg-query-validator-to-frontend-search-input.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [`site/js/evaluator.js`](../../site/js/evaluator.js) (PEG インラインパーサーの統合・置換)
- [x] [`site/js/frameworks/query-validator.js`](../../site/js/frameworks/query-validator.js) (Node.js/ブラウザ環境エクスポートの整合性確認)
- [x] [`src/core/structures/peg_compiler/codegen_js.py`](../../src/core/structures/peg_compiler/codegen_js.py) (新規: JSコードジェネレータ)
- [x] [`src/core/structures/peg_compiler/cli.py`](../../src/core/structures/peg_compiler/cli.py) (`--target` 引数対応)
- [x] [`src/core/structures/peg_compiler/__init__.py`](../../src/core/structures/peg_compiler/__init__.py) (`JSCodeGenerator` エクスポート)
- [x] [`tools/peg_compiler/compile_peg.py`](../../tools/peg_compiler/compile_peg.py) (CLI 連携確認)
- [x] [`tests/web/test_frontend_frameworks.py`](../../tests/web/test_frontend_frameworks.py) (インラインパーサーテスト追加)
- [x] [`tests/test_peg_compiler_js.py`](../../tests/test_peg_compiler_js.py) (新規: JSコード生成単体テスト)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/417-frontend-peg-inline-parser-and-js-aot-codegen`

### Step 1: JS PEG インラインパーサーの実装 (`site/js/evaluator.js`)
1. **PEG 文法定義 (インラインマークダウン)**:
   - `CodeSpan`: バッククォート `` `([^`]+)` `` にマッチし、内部を `<code class="inline-code">...</code>` に変換。最優先で評価し、内部の記号（`*`, `[`, `]` 等）を保護。
   - `Escaped`: `\\([*`\\[\\]])` にマッチし、エスケープされた文字をプレーンテキストとして返却。
   - `Bold`: `\*\*([^*]+)\*\*` にマッチし、内部を `<strong>...</strong>` に変換。
   - `Link`: `\[([^\]]+)\]\(([^)]+)\)` にマッチし、`<a href="..." target="_blank" rel="noopener noreferrer">...</a>` に変換。
   - `PlainText`: 特殊文字以外の文字塊、またはマッチしなかった単一特殊文字を順次消費。
2. **ランタイム連携とフォールバック**:
   - `window.Application.frameworks.peg` または CommonJS `require` から PEG コンビネータを取得。
   - 万一 PEG ランタイムが未初期化の場合でも安全に動作するフォールバックを備え、堅牢性を担保。
3. **テスト検証**:
   - `` `**not bold**` `` が太字にならずコードとして出力されること。
   - `[**Bold Label**](http://example.com)` が正しく解釈されること。
   - `\*not bold\*` がエスケープされること。

### Step 2: Python PEG AOT コンパイラ JS コードジェネレータ (`codegen_js.py`)
1. **`JSCodeGenerator` の設計**:
   - `GrammarDef` AST を走査し、スタンドアロンで動作する JavaScript パーサークラスを出力。
   - 出力コード構造:
     - 軽量ランタイム（`ParseContext`, `ParseResult`, `PEGSyntaxError`, `Parser` 基底クラス）
     - 各文法規則に対応するパーサーコンビネータの組み立て（または関数ベースの再帰下降）
     - UMD / CommonJS / Browser グローバル対応のモジュールラッパー
2. **CLI 拡張**:
   - `src/core/structures/peg_compiler/cli.py` に `--target {python,js}`（デフォルト: `python`）を追加。
   - `--target js` 指定時に `JSCodeGenerator` を呼び出して出力。
3. **テストケース (`tests/test_peg_compiler_js.py`)**:
   - 簡易文法（数式、識別子、ペア等）をコンパイルし、有効な JavaScript コードが生成されることを検証。
   - Node.js 環境で実際に実行しパース結果（AST / 値）およびシンタックスエラーを検証。

---

## 5. 完了条件 / Success Criteria (DoD)

- [x] `site/js/evaluator.js` のインラインマークダウンパースが PEG コンビネータに刷新され、コードスパン内保護・エスケープ処理・リンク解析が正常に機能すること。
- [x] `compile_peg.py grammar.peg --target js -o parser.js` でスタンドアロン JS パーサーが正常に生成されること。
- [x] 生成された JS パーサーが構文エラーおよび正常系を正しくパースできること。
- [x] `pytest tests/test_peg_compiler_js.py` および `pytest tests/web/test_frontend_frameworks.py` がすべて PASS すること。
- [x] `make py_compile` および `make static_analysis` がエラー 0 件であること。
- [x] 完了後、Issue 417 を `docs/issues/closed/` に移動し、Issue 台帳を更新すること。
