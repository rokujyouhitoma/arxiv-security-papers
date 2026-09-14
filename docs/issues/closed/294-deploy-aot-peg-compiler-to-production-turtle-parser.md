---
ID: 294
種別: Feature
優先度: High
ステータス: Closed (Resolved)
---

# [FEAT] AOT PEG コンパイラ実戦投入: W3C Turtle 1.1 パーサーの AOT 化と運用パイプライン統合 (ID: 294)

## 1. 概要 / Summary
Issue #293 で構築した純粋 Python Packrat PEG 事前コンパイラ（`src/core/structures/peg_compiler/`、`tools/peg_compiler/compile_peg.py`）を本番環境へ実戦投入した。
W3C 規格として厳密な構文仕様を持つ **W3C Turtle 1.1 パーサー (`src/ontology/turtle_parser.py`)** を対象に、文法規則を宣言的な `.peg` ファイル（`grammars/turtle.peg`）として抽出し、AOT コンパイルによって静的パーサー（`src/ontology/generated_turtle_parser.py`）を自動生成して透過的に統合した。
さらに `Makefile` に文法コンパイルパイプライン（`compile_grammars`）を組み込み、パフォーマンステスト・DSN-25 設計書の更新を完遂した。
また、コード生成器（`codegen.py`）における使用シンボルの動的インポート解析を実装し、`# flake8: noqa` ゼロ方針を完全達成した。

---

## 2. トレーサビリティ / Traceability
- 設計文書: [docs/designs/DSN-25-pure_python_packrat_peg_parser_engine.md](../designs/DSN-25-pure_python_packrat_peg_parser_engine.md) (第7節 AOT コンパイラ実戦投入と本番運用)
- 先行 Issue:
  - [Issue #284 (Closed)](closed/284-implement-pure-python-packrat-peg-parser-core.md): 純粋 Python Packrat PEG コアランタイム
  - [Issue #290 (Closed)](closed/290-refactor-turtle-parser-with-packrat-peg.md): Turtle パーサーの PEG 化
  - [Issue #293 (Closed)](closed/293-implement-dsn25-phase2-peg-ahead-of-time-compiler.md): PEG 事前コンパイラ基盤の実装

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] 文法定義: `grammars/turtle.peg`
- [x] 自動生成パーサー: `src/ontology/generated_turtle_parser.py`
- [x] パーサー本体統合: `src/ontology/turtle_parser.py`
- [x] ビルドパイプライン: `Makefile`
- [x] パフォーマンステスト: `tests/ontology/test_turtle_benchmark.py`
- [x] 既存テスト検証: `tests/ontology/test_turtle_parser.py`
- [x] ドキュメント更新: `docs/designs/DSN-25-pure_python_packrat_peg_parser_engine.md`
- [x] 管理インデックス: `docs/issues/README.md`

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/294-deploy-aot-peg-compiler-to-production-turtle-parser`

1. **文法ファイル設計 (`grammars/turtle.peg`)**:
   - W3C Turtle 1.1 構文仕様（Directives, Triples, Blank Nodes, Literals, Data Types, Comments）を PEG 規則として記述。
   - `@header` にて AST クラス群をインポート。
   - セマンティックアクション `{ ... }` により、トリプルおよびプレフィックス辞書を宣言的に構築。
2. **AOT コンパイル & コード生成**:
   - `tools/peg_compiler/compile_peg.py` を実行し、`src/ontology/generated_turtle_parser.py` を生成。
3. **透過的統合 (`src/ontology/turtle_parser.py`)**:
   - `TurtlePEGParser` が内部で `generated_turtle_parser.TurtleParser` を呼び出すようリファクタリング。
   - 既存の公開 API（`parse_turtle`, `TurtleDocument`, `TurtleTriple`, `TurtleTerm`）と 100% 互換性を保持。
4. **ビルドパイプライン組み込み (`Makefile`)**:
   - `compile_grammars` ターゲットを追加し、CI/ビルド時に自動コンパイル・整合性検証を担保。
5. **ベンチマーク & 品質検証**:
   - `tests/ontology/test_turtle_benchmark.py` によるパース速度・スループット測定。
   - `make format`, `make static_analysis` (xenon A, mypy --strict), `make test`。
6. **ドキュメント & Issue クローズ**:
   - DSN-25 設計書に第 7 節を追記。
   - Issue を `docs/issues/closed/` に移動し、Conventional Commit で記録。

---

## 5. 完了条件 (Definition of Done)
- [x] `grammars/turtle.peg` が W3C Turtle 1.1 仕様に準拠して定義されていること。
- [x] `tools/peg_compiler/compile_peg.py` により `src/ontology/generated_turtle_parser.py` が正常に自動生成されること。
- [x] `src/ontology/turtle_parser.py` が生成パーサーを利用し、`tests/ontology/test_turtle_parser.py` の全テストが PASS すること。
- [x] `Makefile` に `compile_grammars` ターゲットが追加され正常実行できること。
- [x] パフォーマンステスト `tests/ontology/test_turtle_benchmark.py` が PASS すること。
- [x] `mypy --strict` で全ファイルエラー 0 件であること。
- [x] Xenon 循環的複雑度 Grade A ($CC \le 4$) を維持していること。
- [x] DSN-25 設計書が更新されていること。
