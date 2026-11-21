---
ID: 908
種別: Feature
優先度: High
ステータス: Open (New)
---

# [REFACTOR/ENH] Migrate tools/grammars/*.peg to CPython PEG Grammar Syntax (ID: 908)

## 1. 概要 / Summary
[[DSN-25]](../designs/DSN-25-pure_python_packrat_peg_parser_engine.md) および [[Issue #907]](907-support-cpython-peg-grammar-specification-in-core-peg.md) の成果に基づき、リポジトリ内の `tools/grammars/` 配下に存在する全 PEG 文法ファイル（13ファイル）を、CPython 公式の PEG 文法仕様（PEP 617 / [Grammar/python.gram](https://github.com/python/cpython/tree/main/Grammar)）の構文（`rule: choice1 | choice2`、`name=expr`、`[expr]`、`~` 等）へ統一移行（Migrate）する。

これにより、プロジェクト内のすべての構文定義が業界標準の CPython PEG 仕様に一元化され、Python 側の `src/core/peg` と Pure Scheme 側の `ulisp/workbench/peg.scm`（[[Issue #894]](894-implement-pure-scheme-compile-time-peg-parser-generator.md)）の両方から共通の文法ソースとして直接コンパイル可能になる。

---

## 2. トレーサビリティ / Traceability
- 関連設計書:
  - [[DSN-25] Pure Python Packrat PEG Parser Engine Specification](../designs/DSN-25-pure_python_packrat_peg_parser_engine.md)
  - [[DSN-33-04] ULisp 言語ワークベンチ・インタプリタ自動生成 ＆ ゲスト言語ランタイムアーキテクチャ設計書 (第3章 PEG/Packrat 構文解析フロントエンド)](../designs/DSN-33-04-ulisp_language_workbench_interpreter_generator_and_guest_runtime_architecture.md)
- 関連 Issue:
  - [[Issue #907] Support CPython PEG Grammar Specification in src/core/peg](907-support-cpython-peg-grammar-specification-in-core-peg.md) (前提タスク)
  - [[Issue #894] Implement Pure Scheme Compile-Time PEG Parser Generator](894-implement-pure-scheme-compile-time-peg-parser-generator.md) (後続ビルド統合)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [tools/grammars/bibtex.peg](../../tools/grammars/bibtex.peg)
- [ ] [tools/grammars/calc.peg](../../tools/grammars/calc.peg)
- [ ] [tools/grammars/graph_query.peg](../../tools/grammars/graph_query.peg)
- [ ] [tools/grammars/pdf_cmap.peg](../../tools/grammars/pdf_cmap.peg)
- [ ] [tools/grammars/peg_meta.peg](../../tools/grammars/peg_meta.peg)
- [ ] [tools/grammars/search_query.peg](../../tools/grammars/search_query.peg)
- [ ] [tools/grammars/sql_admin.peg](../../tools/grammars/sql_admin.peg)
- [ ] [tools/grammars/sql_ddl.peg](../../tools/grammars/sql_ddl.peg)
- [ ] [tools/grammars/sql_dml.peg](../../tools/grammars/sql_dml.peg)
- [ ] [tools/grammars/sql_dql.peg](../../tools/grammars/sql_dql.peg)
- [ ] [tools/grammars/sql_expr.peg](../../tools/grammars/sql_expr.peg)
- [ ] [tools/grammars/turtle.peg](../../tools/grammars/turtle.peg)
- [ ] [tools/grammars/yaml_frontmatter.peg](../../tools/grammars/yaml_frontmatter.peg)
- [ ] 各パーサー生成物・関連テストスイート (`tests/core/test_peg_*.py`, `tests/database/`, `tests/ontology/`, 等)
- [ ] [docs/issues/README.md](README.md) (Issue 台帳更新)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/908-migrate-tools-grammars-to-cpython-peg-grammar-syntax`

1. **構文置換ルールの適用**:
   - ルール定義: `rule <- expr` → `rule: expr`
   - 選択演算子: `/` → `|`
   - 変数束縛: `item:rule` → `item=rule`
   - オプショナル: `(?:\s+expr)?` → `[expr]` または `expr?`
   - 必要箇所へのカット演算子 `~` の導入
2. **対象文法ファイルの順次マイグレーション**:
   - Phase 1: 基本文法（`calc.peg`, `search_query.peg`, `graph_query.peg`）
   - Phase 2: データフォーマット（`bibtex.peg`, `pdf_cmap.peg`, `turtle.peg`, `yaml_frontmatter.peg`）
   - Phase 3: SQL エンジン文法群（`sql_expr.peg`, `sql_dql.peg`, `sql_dml.peg`, `sql_ddl.peg`, `sql_admin.peg`, `peg_meta.peg`）
3. **AOT パーサー再生成と回帰テスト**:
   - `src/core/peg` コンパイラを用いて各文法から Python パーサーを再生成。
   - SQL, Turtle, YAML, BibTeX 等の全パーサーテストを実行し、100% 互換性を検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `tools/grammars/` 配下の全 13 個の `.peg` ファイルが CPython PEG 構文に統一移行されていること。
- [ ] `src/core/peg` コンパイラにより、全 13 文法ファイルが正常にコンパイルできること。
- [ ] 生成されたパーサーを用いた既存のテスト（SQL、Turtle、YAML Frontmatter、BibTeX 等）が 100% PASS すること。
- [ ] `make py_compile && make static_analysis` が PASS すること。
