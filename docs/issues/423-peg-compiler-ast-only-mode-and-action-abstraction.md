---
ID: 423
種別: Feature
優先度: High
ステータス: Open (In Progress)
---

# [FEAT/ENH] PEG AOT コンパイラにおける --ast-only 汎用構文木生成とアクション抽象化の実装 (ID: 423)

## 1. 概要 / Summary

現在の `JSCodeGenerator`（`src/core/structures/peg_compiler/codegen_js.py`）は、文法定義（`.peg`）内のセマンティックアクション `{ ... }` をそのまま JavaScript コードとして出力する。
しかし、既存の文法定義（例: `grammars/graph_query.peg`, `grammars/search_query.peg`）のアクション内には、Python 固有のコンストラクタ呼出（`GraphDSLQuery(...)`）やタプル（`(edge, n)`）、Python 辞書操作が記述されているため、JavaScript にコンパイルした際に `ReferenceError` や `SyntaxError` が発生し、文法定義の Single Source of Truth（単一文法定義の多言語共有）が阻害されている。

本 Issue では、CLI オプション `--ast-only`（汎用構文木モード）を導入し、アクションコードの有無にかかわらず、各規則のノード名とマッチ結果を階層型 JSON オブジェクト `{ type: ruleName, value: [...] }` として決定論的に出力する汎用 AST 生成モードを実装する。これにより、Python 依存のアクションコードを含む既存文法から、ブラウザで即座に動作する決定論的パーサーを安全に出力可能とする。

---

## 2. トレーサビリティ / Traceability

- **設計仕様書**:
  - [`docs/designs/DSN-25-pure_python_packrat_peg_parser_engine.md`](../designs/DSN-25-pure_python_packrat_peg_parser_engine.md) (第6節 AOT コンパイラ進化ロードマップ、第13節 Phase 6 JavaScript コードジェネレータ基盤)
- **関連 Issue**:
  - Issue #417: WebフロントエンドJS向けPEGインラインパーサー換装およびPEG AOTコンパイラ JavaScriptコードジェネレータ基盤の実装
  - Issue #419: クライアントサイド CTI グラフクエリ DSL の AOT 生成とダッシュボード統合

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

### コンパイラ基盤
- [ ] [`src/core/structures/peg_compiler/codegen_js.py`](../../src/core/structures/peg_compiler/codegen_js.py)（`ast_only: bool` 引数の追加、アクションバイパス、AST ノード自動ラッピング）
- [ ] [`src/core/structures/peg_compiler/cli.py`](../../src/core/structures/peg_compiler/cli.py)（`--ast-only` CLI 引数の追加と `compile_grammar_to_code` への配線）
- [ ] [`src/core/structures/peg_compiler/__init__.py`](../../src/core/structures/peg_compiler/__init__.py)（公開シグネチャの整合性維持）

### テスト
- [ ] [`tests/test_peg_compiler_js.py`](../../tests/test_peg_compiler_js.py)（`grammars/graph_query.peg` からの `--ast-only` コンパイルと Node.js 実行テスト）

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/423-peg-compiler-ast-only-mode-and-action-abstraction`

### 4.1 `JSCodeGenerator` の `ast_only` オプション対応
1. **コンストラクタ拡張**:
   ```python
   def __init__(
       self,
       grammar: GrammarDef,
       embedded_runtime: bool = True,
       ast_only: bool = False,
   ) -> None:
       self.grammar = grammar
       self.embedded_runtime = embedded_runtime
       self.ast_only = ast_only
       ...
   ```
2. **`_emit_action` のバイパス**:
   - `self.ast_only == True` の場合、セマンティックアクション `{ ... }` のコード生成（`_build_action_method`）を行わず、内部式 `expr.expr` のコードをそのまま返す。
   - これにより、Python 固有の文法やインポートが JavaScript 側に漏洩することを完全に防止。
3. **各規則ノードの自動 AST ラッピング (`_emit_rule_definitions`)**:
   - `self.ast_only == True` の場合、各規則の定義式を以下のように `.map()` で自動ラップする：
     ```javascript
     this._r_ruleName.define((exprCode).map(function(val) {
       return { type: "ruleName", value: val };
     }));
     ```
   - これにより、任意の文法定義からクリーンで階層的な AST JSON オブジェクトが自動的に得られる。

### 4.2 CLI (`cli.py`) の統合
1. **`compile_grammar_to_code` 関数のシグネチャ拡張**:
   - `ast_only: bool = False` 引数を追加。
   - `target="js"` 時に `JSCodeGenerator(grammar_ast, ast_only=ast_only)` へ渡す。
2. **`_build_arg_parser` へのオプション追加**:
   - `--ast-only`: "Bypass embedded semantic actions and emit clean AST tree nodes ({type, value})"（デフォルト: `False`）。
3. **`run_cli` での引数伝搬**:
   - `parsed.ast_only` を `compile_grammar_to_code` へ渡す。

### 4.3 テスト検証の拡充
1. **`tests/test_peg_compiler_js.py` にテストケース追加**:
   - `test_js_code_generator_ast_only_with_python_actions()`:
     - Python 固有のコード（`GraphDSLQuery(kind=...)` やタプル等）を含む `grammars/graph_query.peg` を `--ast-only --target js` でコンパイル。
     - 生成された JS ファイルを `node` で実行し、パース結果が `{ type: "query", value: ... }` の有効な AST オブジェクトであることを検証。
   - CLI オプション `--ast-only` の動作検証。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `JSCodeGenerator` に `ast_only: bool` が追加され、アクションコードを無視して純粋な AST ノード `{ type, value }` を生成できること。
- [ ] `cli.py` に `--ast-only` フラグが追加され、CLI から直接実行可能であること。
- [ ] Python アクションを含む `grammars/graph_query.peg` が `--target js --ast-only` でエラーなくコンパイルされ、Node.js 上で正常に実行できること。
- [ ] Xenon Rank A（循環的複雑度）を全関数・メソッドで維持すること。
- [ ] `flake8`、`mypy --strict src`、`black`、`isort` を 0 エラーでパスすること。
- [ ] `tests/test_peg_compiler_js.py` に新規テストが追加され、全 PASS すること。
