---
ID: 908
種別: Feature
優先度: High
ステータス: Closed (Completed)
完了日: 2026-11-21
---

# [REFACTOR/ENH] Migrate tools/grammars/*.peg to CPython PEG Grammar Syntax (ID: 908)

## 1. 概要 / Summary
[[DSN-25]](../designs/DSN-25-pure_python_packrat_peg_parser_engine.md) および [[Issue #907]](closed/907-support-cpython-peg-grammar-specification-in-core-peg.md) の完了成果に基づき、リポジトリ内の `tools/grammars/` 配下に存在する全 PEG 文法ファイル（全13ファイル）を、CPython 公式の PEG 文法仕様（PEP 617 / [Grammar/python.gram](https://github.com/python/cpython/tree/main/Grammar)）の構文（`rule: choice1 | choice2`、`name=expr`、`[expr]`、`sep.rule+`、`~` 等）へ統一マイグレーション（Migrate）する。

これにより、プロジェクト内のすべての構文定義が業界標準の CPython PEG 仕様に一元化され、Python 側の `src/core/peg` と Pure Scheme 側の `ulisp/workbench/peg.scm`（[[Issue #894]](894-implement-pure-scheme-compile-time-peg-parser-generator.md)）の両方から共通の文法ソースとして直接コンパイル可能になる。

---

## 2. トレーサビリティ / Traceability
- 関連設計書:
  - [[DSN-25] Pure Python Packrat PEG Parser Engine Specification](../designs/DSN-25-pure_python_packrat_peg_parser_engine.md)
  - [[DSN-33-04] ULisp 言語ワークベンチ・インタプリタ自動生成 ＆ ゲスト言語ランタイムアーキテクチャ設計書 (第3章 PEG/Packrat 構文解析フロントエンド)](../designs/DSN-33-04-ulisp_language_workbench_interpreter_generator_and_guest_runtime_architecture.md)
- 依存 Issue:
  - [[Issue #907] Support CPython PEG Grammar Specification in src/core/peg](closed/907-support-cpython-peg-grammar-specification-in-core-peg.md) (**完了済み**)
- 後続 Issue:
  - [[Issue #894] Implement Pure Scheme Compile-Time PEG Parser Generator](894-implement-pure-scheme-compile-time-peg-parser-generator.md) (Pure Scheme 上での CPython PEG 文法直接コンパイル検証)

---

## 3. 影響範囲と対象文法ファイル / Scope and Affected Files

### 3.1 対象文法ファイル (`tools/grammars/*.peg` 全13ファイル)
全13ファイルの文法記述を Bryan Ford 記法（`<-`, `/`, `name:expr`）から CPython PEG 記法（`rule:`, `|`, `name=expr`, `[expr]`, `sep.rule+`）へと刷新する。

| # | 文法ファイル | ドメイン / 用途 | 対応する生成パーサー | 主要回帰テスト |
|---|---|---|---|---|
| 1 | [tools/grammars/peg_meta.peg](../../tools/grammars/peg_meta.peg) | PEG 自己ホスティング・メタ文法 | `src/core/peg/compiler/generated_meta_parser.py` | `tests/core/peg/compiler/test_bootstrap.py` |
| 2 | [tools/grammars/calc.peg](../../tools/grammars/calc.peg) | 四則演算・括弧計算文法 | なし (テスト・リファレンス用) | `tests/core/peg/compiler/test_cpython_grammar.py` |
| 3 | [tools/grammars/search_query.peg](../../tools/grammars/search_query.peg) | 論文・CTI検索クエリ文法 | `src/search/query/generated_search_query_parser.py` | `tests/search/test_query_parser_peg.py` |
| 4 | [tools/grammars/graph_query.peg](../../tools/grammars/graph_query.peg) | ナレッジグラフクエリ文法 | `src/graph/generated_graph_query_parser.py`<br>`src/web/site/js/frameworks/cti-query-parser.js` | `tests/graph/test_graph_query_peg.py` |
| 5 | [tools/grammars/yaml_frontmatter.peg](../../tools/grammars/yaml_frontmatter.peg) | OKF v0.2 YAML フロントマター文法 | `src/pipeline/transformer/generated_yaml_frontmatter_parser.py` | `tests/pipeline/test_okf_peg_frontmatter.py` |
| 6 | [tools/grammars/bibtex.peg](../../tools/grammars/bibtex.peg) | BibTeX / LaTeX 引用文法 | `src/pdf_engine/bibtex/generated_parser.py` | `tests/pdf_engine/test_bibtex_peg.py` |
| 7 | [tools/grammars/pdf_cmap.peg](../../tools/grammars/pdf_cmap.peg) | PDF ToUnicode CMap マッピング文法 | `src/pdf_engine/cmap/generated_parser.py` | `tests/pdf_engine/test_cmap_peg.py` |
| 8 | [tools/grammars/turtle.peg](../../tools/grammars/turtle.peg) | W3C RDF 1.1 Turtle オントロジー文法 | `src/ontology/turtle/generated_parser.py` | `tests/ontology/test_turtle_peg.py` |
| 9 | [tools/grammars/sql_expr.peg](../../tools/grammars/sql_expr.peg) | SQL 式評価文法 | `src/database/sql/generated_sql_expr_parser.py` | `tests/database/test_sql_expr_peg.py` |
| 10 | [tools/grammars/sql_dql.peg](../../tools/grammars/sql_dql.peg) | SQL SELECT/CTE/JOIN 構文 | `src/database/sql/generated_sql_dql_parser.py` | `tests/database/test_sql_dql_peg.py` |
| 11 | [tools/grammars/sql_dml.peg](../../tools/grammars/sql_dml.peg) | SQL INSERT/UPDATE/DELETE/UPSERT 構文 | `src/database/sql/generated_sql_dml_parser.py` | `tests/database/test_sql_dml_peg.py` |
| 12 | [tools/grammars/sql_ddl.peg](../../tools/grammars/sql_ddl.peg) | SQL CREATE/ALTER/DROP 構文 | `src/database/sql/generated_sql_ddl_parser.py` | `tests/database/test_sql_ddl_peg.py` |
| 13 | [tools/grammars/sql_admin.peg](../../tools/grammars/sql_admin.peg) | SQL PRAGMA/VACUUM/INDEX 管理構文 | `src/database/sql/generated_sql_admin_parser.py` | `tests/database/test_sql_admin_peg.py` |

---

## 4. セキュリティ・堅牢性設計 / Security and Robustness
1. **構文解析の等価性（Semantic Equivalence）**:
   - Ford 記法から CPython 記法への変換において、演算子の結合性（左結合・右結合）や優先順位、セマンティックアクション内の変数スコープおよび戻り値構造が 100% 保持されること。
   - 変数束縛 `name=expr` への置換後も、Python アクションブロック `{ return ... }` 内で参照される変数名との完全一致を担保する。
2. **自己ホスティング不動点（Bootstrap Fixpoint Invariant）**:
   - `peg_meta.peg` を更新した際、生成される `generated_meta_parser.py`（AOT 自己ホストパーサー）が自身の文法および他12文法すべてを正常にパースできる不動点を保証する。
3. **バックトラック爆発・無限ループの防止**:
   - 複数行オルタナティブ化に伴う選択肢順序の意図しない変更を排除。
   - セパレータ付きリスト（`sep.rule+`）への置換時、空セパレータや空要素による無限ループガード（`Gather` コンビネータ）の安全性を担保。
4. **ReDoS / スタックオーバーフロー防御**:
   - 外部入力を直接受ける `yaml_frontmatter.peg`、`search_query.peg`、`bibtex.peg`、`pdf_cmap.peg` において、悪意ある過大ネスト入力やバックトラック誘発入力に対する耐性を維持する。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/908-migrate-tools-grammars-to-cpython-peg-grammar-syntax`

### 5.1 構文変換ルール標準表
| 構文要素 | 旧構文 (Ford POPL '04) | 新構文 (CPython PEP 617 / python.gram) | 変換方針・注意事項 |
|---|---|---|---|
| **ルール定義** | `rule <- expr` | `rule: expr`<br>またはインデント複数行 `\|` | 行頭コロン `:` とインデントの整形 |
| **選択 (Choice)** | `e1 / e2` | `e1 \| e2`<br>または先行パイプ `\| e1` | スラッシュ `/` をパイプ `\|` へ置換 |
| **変数束縛** | `name:expr` | `name=expr` | アクション内の変数参照名を完全一致させる |
| **オプショナル** | `expr?` または `(?:...)?` | `[expr]` または `expr?` | 複合オプショナル式には `[ ... ]` を積極活用 |
| **セパレータリスト** | `first:e rest:(sep e)*` | `sep.e+` | 簡潔な CPython 記法へ統一（アクション適合性確認の上） |
| **カット演算子** | `^` (手動バックトラック遮断) | `~` | コミットポイントとして明示 |
| **ディレクティブ** | `@header { ... }` | `@header '''...'''` または `@header { ... }` | 既存アクション記法も完全互換で動作 |

### 5.2 段階的マイグレーション手順 (Phased Execution)

#### Phase 1: ブートストラップメタ文法の刷新と自己ホスト再生成
- [tools/grammars/peg_meta.peg](../../tools/grammars/peg_meta.peg) を CPython PEG 構文へマイグレーション。
  - ルール定義を `rule: ...` に変更。
  - 選択肢区切りを `|` に変更。
  - 変数束縛を `name=expr` に変更。
  - セパレータリスト記法 `sep.rule+` のパースルールを追加。
- `PYTHONPATH=src .venv/bin/python tools/peg/compile_peg.py tools/grammars/peg_meta.peg -o src/core/peg/compiler/generated_meta_parser.py` を実行。
- `make verify_peg_bootstrap`（`tests/core/peg/compiler/test_bootstrap.py`）を実行し、AOT パーサーの自己ホスト等価性を検証。

#### Phase 2: コア・リファレンス文法のマイグレーション
- [tools/grammars/calc.peg](../../tools/grammars/calc.peg)
- [tools/grammars/search_query.peg](../../tools/grammars/search_query.peg)
- [tools/grammars/graph_query.peg](../../tools/grammars/graph_query.peg)
- パーサー再生成と検証:
  - `PYTHONPATH=src .venv/bin/python tools/peg/compile_peg.py tools/grammars/search_query.peg -o src/search/query/generated_search_query_parser.py`
  - `PYTHONPATH=src .venv/bin/python tools/peg/compile_peg.py tools/grammars/graph_query.peg -o src/graph/generated_graph_query_parser.py`
  - `PYTHONPATH=src .venv/bin/python -m core.peg.compiler tools/grammars/graph_query.peg -o src/web/site/js/frameworks/cti-query-parser.js --target js --ast-only --no-runtime --class-name CTIQuery`
  - 検証: `tests/search/test_query_parser_peg.py`, `tests/graph/test_graph_query_peg.py`

#### Phase 3: データフォーマット・PDF 文法群のマイグレーション
- [tools/grammars/yaml_frontmatter.peg](../../tools/grammars/yaml_frontmatter.peg)
- [tools/grammars/bibtex.peg](../../tools/grammars/bibtex.peg)
- [tools/grammars/pdf_cmap.peg](../../tools/grammars/pdf_cmap.peg)
- [tools/grammars/turtle.peg](../../tools/grammars/turtle.peg)
- パーサー再生成と検証:
  - `PYTHONPATH=src .venv/bin/python tools/peg/compile_peg.py tools/grammars/yaml_frontmatter.peg -o src/pipeline/transformer/generated_yaml_frontmatter_parser.py`
  - `PYTHONPATH=src .venv/bin/python tools/peg/compile_peg.py tools/grammars/bibtex.peg -o src/pdf_engine/bibtex/generated_parser.py`
  - `PYTHONPATH=src .venv/bin/python tools/peg/compile_peg.py tools/grammars/pdf_cmap.peg -o src/pdf_engine/cmap/generated_parser.py`
  - `PYTHONPATH=src .venv/bin/python tools/peg/compile_peg.py tools/grammars/turtle.peg -o src/ontology/turtle/generated_parser.py`
  - 検証: `tests/pipeline/test_okf_peg_frontmatter.py`, `tests/pdf_engine/`, `tests/ontology/`

#### Phase 4: SQL エンジン文法群のマイグレーション
- [tools/grammars/sql_expr.peg](../../tools/grammars/sql_expr.peg)
- [tools/grammars/sql_dql.peg](../../tools/grammars/sql_dql.peg)
- [tools/grammars/sql_dml.peg](../../tools/grammars/sql_dml.peg)
- [tools/grammars/sql_ddl.peg](../../tools/grammars/sql_ddl.peg)
- [tools/grammars/sql_admin.peg](../../tools/grammars/sql_admin.peg)
- パーサー再生成と検証:
  - `make compile_grammars` の SQL 対象ターゲットを順次ビルド。
  - 検証: `tests/database/test_sql_*_peg.py` 全テスト実行。

#### Phase 5: 全面ビルド・自己ホスト不動点および品質検証
- `make compile_grammars` を一括実行し、全生成コードの再フォーマット（`black`, `isort`）を実行。
- `make verify_peg_bootstrap` による自己ホスト完全一致の検証。
- リポジトリ全体回帰テストの実行。
- `make check_format` および `make static_analysis`（xenon Rank A, mypy --strict）の 100% PASS 検証。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `tools/grammars/` 配下の全 13 文法ファイルが CPython PEG 構文（`rule:`, `|`, `name=expr`, `[expr]`, `sep.rule+`）に統一移行されていること。
- [x] 各文法ファイルから旧構文の `<-` および `/`（Choice 用）が完全に排除されていること（文字クラス内スラッシュを除く）。
- [x] `make compile_grammars` がエラーなく実行され、全生成パーサー（Python 8ファイル、JS 1ファイル）が更新されること。
- [x] `make verify_peg_bootstrap`（`test_bootstrap.py`）が 100% PASS し、自己ホスト AOT パーサーが全 13 文法を正しく解析できること。
- [x] 既存のドメイン回帰テストスイート（SQL, BibTeX, PDF CMap, Turtle, YAML Frontmatter, Search Query）がすべて 100% PASS すること。
- [x] `make format && make static_analysis` がエラー 0 件で PASS すること（xenon Rank A, mypy --strict 617 files）。
- [x] すべてのファイル参照およびリンクにおいて相対パス規則が厳格に守られていること。
