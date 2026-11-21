---
ID: 908
種別: Feature
優先度: High
ステータス: Open (In Progress)
---

# [REFACTOR/ENH] Migrate tools/grammars/*.peg to CPython PEG Grammar Syntax (ID: 908)

## 1. 概要 / Summary
[[DSN-25]](../designs/DSN-25-pure_python_packrat_peg_parser_engine.md) および [[Issue #907]](907-support-cpython-peg-grammar-specification-in-core-peg.md) の成果に基づき、リポジトリ内の `tools/grammars/` 配下に存在する全 PEG 文法ファイル（全13ファイル）を、CPython 公式の PEG 文法仕様（PEP 617 / [Grammar/python.gram](https://github.com/python/cpython/tree/main/Grammar)）の構文（`rule: choice1 | choice2`、`name=expr`、`[expr]`、`sep.rule+`、`~` 等）へ統一マイグレーション（Migrate）する。

これにより、プロジェクト内のすべての構文定義が業界標準の CPython PEG 仕様に一元化され、Python 側の `src/core/peg` と Pure Scheme 側の `ulisp/workbench/peg.scm`（[[Issue #894]](894-implement-pure-scheme-compile-time-peg-parser-generator.md)）の両方から共通の文法ソースとして直接コンパイル可能になる。

---

## 2. トレーサビリティ / Traceability
- 関連設計書:
  - [[DSN-25] Pure Python Packrat PEG Parser Engine Specification](../designs/DSN-25-pure_python_packrat_peg_parser_engine.md)
  - [[DSN-33-04] ULisp 言語ワークベンチ・インタプリタ自動生成 ＆ ゲスト言語ランタイムアーキテクチャ設計書 (第3章 PEG/Packrat 構文解析フロントエンド)](../designs/DSN-33-04-ulisp_language_workbench_interpreter_generator_and_guest_runtime_architecture.md)
- 依存 Issue:
  - [[Issue #907] Support CPython PEG Grammar Specification in src/core/peg](907-support-cpython-peg-grammar-specification-in-core-peg.md) (**前提タスク: 完了必須**)
- 後続 Issue:
  - [[Issue #894] Implement Pure Scheme Compile-Time PEG Parser Generator](894-implement-pure-scheme-compile-time-peg-parser-generator.md) (Pure Scheme 上でのビルド検証)

---

## 3. 影響範囲と対象文法ファイル / Scope and Affected Files

### 対象文法ファイル (`tools/grammars/*.peg` 全13ファイル)
- [x] [tools/grammars/calc.peg](../../tools/grammars/calc.peg) (四則演算・括弧計算文法)
- [x] [tools/grammars/search_query.peg](../../tools/grammars/search_query.peg) (論文・CTI検索クエリ文法)
- [x] [tools/grammars/graph_query.peg](../../tools/grammars/graph_query.peg) (ナレッジグラフクエリ文法)
- [x] [tools/grammars/bibtex.peg](../../tools/grammars/bibtex.peg) (BibTeX / LaTeX 引用文法)
- [x] [tools/grammars/pdf_cmap.peg](../../tools/grammars/pdf_cmap.peg) (PDF ToUnicode CMap マッピング文法)
- [x] [tools/grammars/turtle.peg](../../tools/grammars/turtle.peg) (W3C RDF 1.1 Turtle オントロジー文法)
- [x] [tools/grammars/yaml_frontmatter.peg](../../tools/grammars/yaml_frontmatter.peg) (OKF v0.2 YAML フロントマター文法)
- [x] [tools/grammars/sql_expr.peg](../../tools/grammars/sql_expr.peg) (SQL 式評価文法)
- [x] [tools/grammars/sql_dql.peg](../../tools/grammars/sql_dql.peg) (SQL SELECT/CTE/JOIN 構文)
- [x] [tools/grammars/sql_dml.peg](../../tools/grammars/sql_dml.peg) (SQL INSERT/UPDATE/DELETE/UPSERT 構文)
- [x] [tools/grammars/sql_ddl.peg](../../tools/grammars/sql_ddl.peg) (SQL CREATE/ALTER/DROP 構文)
- [x] [tools/grammars/sql_admin.peg](../../tools/grammars/sql_admin.peg) (SQL PRAGMA/VACUUM/INDEX 管理構文)
- [x] [tools/grammars/peg_meta.peg](../../tools/grammars/peg_meta.peg) (PEG 自己ホスティング・メタ文法)

### 生成パーサーと検証テストスイート
- `make compile_grammars` により更新される AOT 生成パーサー群:
  - `src/core/peg/compiler/generated_meta_parser.py`
  - `src/database/sql/generated_sql_*_parser.py` (5ファイル)
  - `src/pdf_engine/bibtex/generated_parser.py`
  - `src/pdf_engine/cmap/generated_parser.py`
  - `src/ontology/turtle/generated_parser.py`
  - `src/pipeline/transformer/generated_yaml_frontmatter_parser.py`
  - `src/search/query/generated_search_query_parser.py`
  - `src/graph/generated_graph_query_parser.py`
- ドメイン回帰テストスイート:
  - `tests/core/peg/compiler/test_bootstrap.py`
  - `tests/database/test_sql_*.py`
  - `tests/pdf_engine/test_bibtex_peg.py`, `test_cmap_peg.py`
  - `tests/pipeline/test_okf_peg_frontmatter.py`
  - `tests/search/test_query_parser_peg.py`
- [docs/issues/README.md](README.md) (Issue 台帳更新)

---

## 4. セキュリティ・堅牢性設計 / Security and Robustness
1. **構文解析の等価性（Semantic Equivalence）**:
   - Ford 記法から CPython 記法への変換において、演算子の結合性（左結合・右結合）や優先順位、セマンティックアクション内の変数スコープが 100% 保持されること。
2. **バックトラック爆発・無限ループの防止**:
   - 複数行オルタナティブ化に伴う意図しない選択枝順序の変化がないこと。
   - セパレータ付きリスト（`sep.rule+`）への置換時、空セパレータや空要素による無限ループガードが動作すること。
3. **データ完全性の保証**:
   - YAML フロントマター、BibTeX、SQL クエリ等、外部からの信頼できない入力を受けるパーサーにおいて、悪意あるペイロードに対する堅牢性が損なわれないこと。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/908-migrate-tools-grammars-to-cpython-peg-grammar-syntax`

### 構文変換ルール標準表
| 構文要素 | 旧構文 (Ford POPL '04) | 新構文 (CPython PEP 617 / python.gram) | 備考 |
|---|---|---|---|
| **ルール定義** | `rule <- expr` | `rule: expr` または 複数行 `\|` | インデント整形 |
| **選択 (Choice)** | `e1 / e2` | `e1 \| e2` または 行頭 `\| alt` | 先行パイプ許容 |
| **変数束縛** | `name:expr` | `name=expr` | アクション引数連携 |
| **オプショナル** | `expr?` または `(?:...)?` | `[expr]` または `expr?` | 角括弧推奨 |
| **セパレータリスト** | `first:e rest:(sep e)*` | `sep.e+` | 簡潔な記述 |
| **カット演算子** | `^` (手動バックトラック遮断) | `~` | コミットポイント |
| **アクション** | `{ action_code }` | `{ action_code }` | 既存コード完全維持 |

### 段階的移行ステップ (Staged Migration)

#### Phase 1: 基本文法のマイグレーション
- `tools/grammars/calc.peg`
- `tools/grammars/search_query.peg`
- `tools/grammars/graph_query.peg`
- `tools/grammars/peg_meta.peg` (自己ホスティング検証)
- 検証: `tests/core/peg/compiler/test_bootstrap.py` の実行

#### Phase 2: データフォーマット文法のマイグレーション
- `tools/grammars/bibtex.peg`
- `tools/grammars/pdf_cmap.peg`
- `tools/grammars/turtle.peg`
- `tools/grammars/yaml_frontmatter.peg`
- 検証: `tests/pdf_engine/`, `tests/ontology/`, `tests/pipeline/` の回帰テスト実行

#### Phase 3: SQL エンジン文法群のマイグレーション
- `tools/grammars/sql_expr.peg`
- `tools/grammars/sql_dql.peg`
- `tools/grammars/sql_dml.peg`
- `tools/grammars/sql_ddl.peg`
- `tools/grammars/sql_admin.peg`
- 検証: `tests/database/test_sql_*.py` の全テスト実行

#### Phase 4: パーサー一括再生成と全系統合検証
- `make compile_grammars` の実行
- `make verify_peg_bootstrap` の実行
- 全 PEG 関連テストの 100% PASS 検証

---

## 6. 完了条件 / Success Criteria (DoD)
- [ ] `tools/grammars/` 配下の全 13 文法ファイルが CPython PEG 構文に統一移行されていること。
- [ ] `make compile_grammars` がエラーなく実行され、全生成パーサーが最新の文法ファイルから正常に出力されること。
- [ ] `tests/core/peg/compiler/test_bootstrap.py`（AOT 自己ホスト等価性テスト）が 100% PASS すること。
- [ ] ドメイン回帰テスト（SQL、BibTeX、PDF CMap、Turtle、YAML Frontmatter、Search Query）が全件 PASS すること。
- [ ] `make py_compile && make static_analysis` がエラー 0 件で PASS すること。
- [ ] 相対パス規則が厳格に守られていること。
