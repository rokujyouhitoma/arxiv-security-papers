---
ID: 305
種別: Feature
優先度: High
ステータス: Open (In Progress)
---

# [FEAT] PEG AOT コンパイラにおける静的最適化パス（定数畳み込み・左因数分解・冗長性剪定）の実装 (ID: 305)

## 1. 概要 / Summary
DSN-25 Phase 2 Ahead-of-Time (AOT) PEG コンパイラ基盤において、文法 AST に対する静的最適化パス (`GrammarOptimizer`) を導入する。
隣接する文字リテラルの事前結合 (Constant Folding)、共通接頭辞の自動左因数分解 (Left-Factoring)、および単一要素ノードや空文字の冗長性剪定 (Redundancy Pruning) を自動適用することで、生成される AOT パーサーの実行時ノード数と評価ステップを劇的に削減する。

---

## 2. トレーサビリティ / Traceability
- 関連設計書: [`DSN-25`](../designs/DSN-25-pure_python_packrat_peg_parser_engine.md)
- 関連 Issue: [#293](closed/293-implement-dsn25-phase2-peg-ahead-of-time-compiler.md), [#303](closed/303-optimize-packrat-peg-parser-engine.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [`src/core/structures/peg_compiler/optimizer.py`](../../src/core/structures/peg_compiler/optimizer.py)
- [x] [`src/core/structures/peg_compiler/ast_nodes.py`](../../src/core/structures/peg_compiler/ast_nodes.py)
- [x] [`src/core/structures/peg_compiler/codegen.py`](../../src/core/structures/peg_compiler/codegen.py)
- [x] [`src/core/structures/peg_compiler/cli.py`](../../src/core/structures/peg_compiler/cli.py)
- [ ] [`tests/core/test_peg_optimizer.py`](../../tests/core/test_peg_optimizer.py)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/305-peg-compiler-ast-optimizer`

1. **AST 最適化パス (`src/core/structures/peg_compiler/optimizer.py`)**:
   - `_fold_literals`: `SeqExpr` 内の連続する `LitExpr("A")` と `LitExpr("B")` を単一の `LitExpr("AB")` へ結合。
   - `_factor_alternatives`: `ChoiceExpr` 内の共通接頭辞を持つ選択肢（`A B / A C`）を `A (B / C)` へ自動左因数分解。
   - `_prune_seq_elements`: シーケンス内の不要な空文字 `LitExpr("")` を安全に除去。
   - `_optimize_seq` / `_optimize_choice`: 単一要素の Sequence/Choice を直接の子式へ昇格（アンラップ）。
2. **コンパイラ CLI 統合 (`src/core/structures/peg_compiler/cli.py`)**:
   - `compile_grammar_to_code` に `optimize=True` を統合。
   - CLI 引数 `--no-optimize` を追加し、最適化無効化オプションを提供。
3. **AST ノード拡張とコード生成対応 (`ast_nodes.py`, `codegen.py`)**:
   - `CutExpr` ノードの定義および `CutOp()` コード生成エミッターの追加。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `GrammarOptimizer` が隣接リテラルを正しく単一リテラルに結合すること。
- [x] 共通接頭辞を持つ Choice 選択肢が正しく因数分解されること。
- [x] 単一要素 Sequence / Choice が無駄なくアンラップされること。
- [x] CLI オプション `--no-optimize` が機能すること。
- [x] `tests/core/test_peg_optimizer.py` が新規作成され 100% PASS すること。
- [x] 循環的複雑度 $CC \le 4$ (Xenon Grade A) および型安全性が 100% PASS すること。
