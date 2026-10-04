---
ID: 451
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT] Backend A: Python AST トランスパイラ (py_codegen) の実装 (ID: 451)

## 1. 概要 / Summary
[DSN-31](../../docs/designs/DSN-31-ilisp_r7rs_intelligence_lisp_architecture_specification.md) セクション 3.1 に規定された「Backend A: Python AST トランスパイラ」を実装する。
ILISP の S式 AST を Python 標準の `ast.AST`（`ast.Module`, `ast.FunctionDef`, `ast.If`, `ast.Call` 等）に直接コンパイルし、`compile(tree, filename, 'exec')` を通じて CPython バイトコードとしてネイティブ実行させる。
静的代入解析（Mutated Variable Analysis）による `set!` 変数の `Cell` ボックス化昇格、および自己末尾再帰（Self Tail Call）の `while True:` ループ展開最適化を実装し、Tree-walk 評価器と比較して桁違いの実行速度を達成する。

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [x] `ilisp/backend/__init__.py` (バックエンド抽象基盤)
- [x] `ilisp/backend/py_codegen/__init__.py` (Python AST コード生成パッケージ)
- [x] `ilisp/backend/py_codegen/compiler.py` (S式 AST -> Python ast.AST コンパイラ & 自己TCO & 代入解析)
- [x] `ilisp/repl.py` (CLI に `--backend` オプションを追加しトランスパイル実行を統合)
- [x] `tests/ilisp/test_py_codegen.py` (Python AST トランスパイラ単体テスト & 評価器等価性検証)
- [x] `docs/issues/README.md` (Issue 451 登録)

---

## 3. 実装方針 / Implementation Plan
Target Branch: `feat/451-implement-backend-a-python-ast-transpiler`

1. **静的代入解析 (Mutated Variable Analysis)**:
   - 式全体を走査し、どの識別子が `set!` によって変更されるかを検出。
   - `set!` 対象変数はスコープ導入時に `Cell(initial_value)` に昇格させ、参照時は `cell.get()`、更新時は `cell.set(val)` にコンパイルすることで、Python の `nonlocal` 構文エラーを根本排除。
2. **自己末尾再帰最適化 (Self Tail Call Optimization)**:
   - 関数本体の末尾位置にある自分自身の呼び出しを検出し、Python の `while True:` ループと引数再代入（`param = new_val`）に直接トランスパイル。
   - 関数呼出オーバーヘッドゼロ、スタック消費ゼロで深層ループをネイティブ実行。
3. **S式から Python AST への写像 (`PythonASTCompiler`)**:
   - リテラル（数、文字列、真偽値、NIL） -> `ast.Constant`
   - シンボル変数参照 -> `ast.Name`（Cell の場合は `cell.get()`）
   - 基本式:
     - `quote` -> `ast.Constant` または intern された `Symbol`
     - `if` -> `ast.If`（文脈に応じて `ast.IfExp`）
     - `begin` -> 文のリスト（ブロック）
     - `define` -> `ast.Assign` または `ast.FunctionDef`
     - `set!` -> `cell.set(val)` 呼出
     - `lambda` -> `ast.FunctionDef`
     - マクロ展開 -> コンパイル前にマクロを展開（Macro Expand Phase）
     - 関数呼出 -> `ast.Call`
4. **CLI & ランタイム統合**:
   - `compile_ilisp(exprs)` API を提供。
   - `run_string` / `run_file` において backend 選択（`--backend interp|py_ast`）を可能にし、Tree-walk 評価器と完全互換を担保。
5. **包括テストと品質ゲート**:
   - 四則演算、高階関数、再帰ループ、マクロ展開後の AST コンパイル検証。
   - 100,000 回ループのベンチマーク実行（深層再帰のネイティブループ化確認）。
   - `flake8`, `isort`, `black`, `mypy --strict`, `pytest`。

---

## 4. 完了条件 / Success Criteria (DoD)
- [x] `ilisp/backend/py_codegen/compiler.py` が正常に S式 AST を Python `ast.AST` へコンパイルできること
- [x] 自己末尾再帰が `while True:` ループに変換され、深層再帰がスタックゼロ消費でネイティブ実行されること
- [x] `set!` 対象変数が `Cell` に昇格され、スコープ内外からの変異が正確に機能すること
- [x] Tree-walk 評価器と Python AST トランスパイラの間で計算結果が 100% 一致すること
- [x] 新規単体テスト（`tests/ilisp/test_py_codegen.py`）を含む全テストが PASS すること
- [x] リポジトリの全品質ゲート（`flake8`, `isort`, `black`, `mypy --strict`, `pytest`）が 100% PASS すること
