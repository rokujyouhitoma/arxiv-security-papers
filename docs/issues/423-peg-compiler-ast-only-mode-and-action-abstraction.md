---
ID: 423
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] PEG AOT コンパイラにおける --ast-only 汎用構文木生成とアクション抽象化の実装 (ID: 423)

## 1. 概要 / Summary

現在の `JSCodeGenerator`（`src/core/structures/peg_compiler/codegen_js.py`）は、文法定義（`.peg`）内のセマンティックアクション `{ ... }` をそのまま JavaScript コードとして出力する。
しかし、既存の文法定義（例: `grammars/graph_query.peg`, `grammars/search_query.peg`）のアクション内には、Python 固有のコンストラクタ呼出（`GraphDSLQuery(...)`）やタプル（`(edge, n)`）、Python 辞書操作が記述されているため、JavaScript にコンパイルした際に `ReferenceError` や `SyntaxError` が発生し、文法定義の Single Source of Truth（単一文法定義の多言語共有）が阻害されている。

本 Issue では、CLI オプション `--ast-only`（またはアクションバイパスモード）を導入し、アクションコードの有無にかかわらず、各規則のノード名とマッチ結果を階層型 JSON オブジェクト `{ type: ruleName, value: [...], offset: ..., length: ... }` として決定論的に出力する汎用 AST 生成モードを実装する。

---

## 2. トレーサビリティ / Traceability

- **設計仕様書**:
  - [`docs/designs/DSN-25-pure_python_packrat_peg_parser_engine.md`](../designs/DSN-25-pure_python_packrat_peg_parser_engine.md) (第6節 AOT コンパイラ進化ロードマップ、第13節 Phase 6 JavaScript コードジェネレータ基盤)
- **関連 Issue**:
  - Issue #417: WebフロントエンドJS向けPEGインラインパーサー換装およびPEG AOTコンパイラ JavaScriptコードジェネレータ基盤の実装
  - Issue #419: クライアントサイド CTI グラフクエリ DSL の AOT 生成とダッシュボード統合

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [`src/core/structures/peg_compiler/codegen_js.py`](../../src/core/structures/peg_compiler/codegen_js.py)（`--ast-only` モードの実装、汎用ノードマッパーの出力）
- [ ] [`src/core/structures/peg_compiler/cli.py`](../../src/core/structures/peg_compiler/cli.py)（`--ast-only` CLI 引数の追加と配線）
- [ ] [`tests/test_peg_compiler_js.py`](../../tests/test_peg_compiler_js.py)（Python アクションを含む PEG からの JS AST 生成テスト）

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/423-peg-compiler-ast-only-mode-and-action-abstraction`

1. **`JSCodeGenerator` の AST-only モード拡張**:
   - `ast_only: bool = False` フラグをコンストラクタに追加。
   - `ast_only=True` の場合、`ActionExpr` のユーザー定義コードを無視し、各規則の評価結果を `{ type: ruleName, value: val }` に自動マッピング。
2. **CLI 連携**:
   - `cli.py` に `--ast-only` オプションを追加し、`JSCodeGenerator` へ伝搬。
3. **テスト検証**:
   - `grammars/graph_query.peg` 等の Python アクションを含む文法から `--ast-only --target js` で安全に JS パーサーをコンパイルし、Node.js 上で正常に AST が得られることを検証。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `--ast-only` オプション指定時、Python 依存のアクションコードをバイパスしてクリーンな汎用 AST を返す JS パーサーが生成されること。
- [ ] `grammars/graph_query.peg` が `--target js --ast-only` で構文エラーなく JS にコンパイルされ、Node.js で実行可能であること。
- [ ] Xenon Rank A、flake8、mypy --strict を 100% パスすること。
- [ ] `tests/test_peg_compiler_js.py` のテストがすべて PASS すること。
