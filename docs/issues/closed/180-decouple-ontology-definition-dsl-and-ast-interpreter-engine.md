---
ID: 180
種別: Architecture / Refactor
優先度: High
ステータス: Closed
---

# [ARCH/REFACTOR] オントロジー宣言DSL（Pure Python Class定義）とASTインタプリタ処理エンジンの完全分離アーキテクチャの実装 (ID: 180)

## 1. 概要 / Summary

現在のオントロジー実装では、スキーマ定義・シリアライズ・抽出・グラフインジェストが相互に密結合しており、セキュリティドメイン知識とオントロジーの汎用処理機構が同一モジュール内に混在しています。

本 Issue では、**「オントロジー定義そのものを Pure Python Class（宣言的 DSL）で記述できること」** と **「それを解析・検証・実行するエンジン」** を完全に分離する次世代オントロジー基盤を構築します。
エンジン側はコンパイラ・インタプリタの概念（AST: Abstract Syntax Tree、構文チェック、セマンティック検証、Visitor/評価器）に基づいて設計し、セキュリティドメイン知識を一切含まない純粋なオントロジーコアエンジンとして独立させます。

### コアコンセプト
1. **宣言的 Pure Python Class DSL (Frontend)**:
   - メタクラスまたはデコレータを活用し、通常の Python クラスとしてオントロジー（クラス、プロパティ、公理、制約）を宣言。
   - ドメインエキスパートが直感的に定義可能。
2. **AST (Abstract Syntax Tree) & 中間表現 (IR)**:
   - 定義されたクラス群から、構文木（`OntologyASTNode`, `ClassNode`, `PropertyNode`, `AxiomNode`）を構築。
3. **構文・意味論チェック (Semantic Linter / Type Checker)**:
   - ドメイン・レンジ不一致、未定義参照、多重定義、循環継承、排他公理違反（Disjointness Violation）などを静的検証。
4. **インタプリタ / コード生成 (Backends)**:
   - AST をトラバースし、W3C Turtle (.ttl) 生成、プロパティグラフスキーマ生成、推論実行などを Visitor パターンで分離実行。
5. **厳格なドメイン分離**:
   - `src/ontology/core/`: ドメイン非依存の汎用オントロジー DSL & AST インタプリタエンジン。
   - `src/ontology/security/`: セキュリティドメイン固有のオントロジー定義（Paper, AttackTechnique, Precondition, etc.）。

---

## 2. トレーサビリティ / Traceability

- 関連プロセス:
  - [processes/MNG-01-document_ledger.md](../processes/MNG-01-document_ledger.md)
  - [processes/MNG-03-ontology_driven_development_process.md](../processes/MNG-03-ontology_driven_development_process.md)
- 関連要件:
  - [requirements/REQ-01-system_requirements.md](../requirements/REQ-01-system_requirements.md)
  - [requirements/REQ-ONT-01_ontology_driven_knowledge_architecture.md](../requirements/REQ-ONT-01_ontology_driven_knowledge_architecture.md)
- 関連設計:
  - [designs/DSN-22-security_and_threat_ontology_w3c_specification.md](../designs/DSN-22-security_and_threat_ontology_w3c_specification.md)
  - [designs/DSN-14-graph_engineering_dashboard.md](../designs/DSN-14-graph_engineering_dashboard.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] `src/ontology/core/` (新規ディレクトリ: 汎用オントロジーエンジン)
  - [x] `src/ontology/core/__init__.py`
  - [x] `src/ontology/core/ast.py` (AST ノード定義: ClassNode, PropertyNode, AxiomNode 等)
  - [x] `src/ontology/core/dsl.py` (Pure Python 宣言的 DSL: @ontology_class, ObjectPropertyField, DatatypePropertyField)
  - [x] `src/ontology/core/parser.py` (Python クラスから AST への構文解析器)
  - [x] `src/ontology/core/validator.py` (静的意味論・公理・制約チェッカー)
  - [x] `src/ontology/core/interpreter.py` (AST 評価・Visitor インタプリタ基盤)
  - [x] `src/ontology/core/codegen_turtle.py` (AST から W3C Turtle へのコード生成器)
- [x] `src/ontology/security/` (新規ディレクトリ: セキュリティドメインオントロジー定義)
  - [x] `src/ontology/security/__init__.py`
  - [x] `src/ontology/security/classes.py` (Pure Python DSL で書かれたセキュリティ概念群)
  - [x] `src/ontology/security/properties.py` (セキュリティ関係性述語群)
  - [x] `src/ontology/security/axioms.py` (セキュリティ公理・推論規則群)
  - [x] `src/ontology/security/model.py` (セキュリティ知識オントロジーモデル統合定義)
- [x] `src/ontology/__init__.py` (Core & Security エクスポート)
- [x] `tests/ontology/test_core_ast.py` (コア AST & インタプリタの単体テスト)
- [x] `tests/ontology/test_core_parser_validator.py` (DSL パーサー & セマンティック検証の単体テスト)
- [x] `tests/ontology/test_security_dsl.py` (セキュリティ DSL & モデル統合の単体テスト)
- [x] `docs/designs/DSN-22-security_and_threat_ontology_w3c_specification.md` (AST & Interpreter アーキテクチャ設計追記)
- [x] `docs/issues/README.md` (Issue 台帳更新)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/180-decouple-ontology-definition-dsl-and-ast-interpreter-engine`

1. **フェーズ 1: コア AST および宣言的 DSL の設計・実装 (`src/ontology/core/`)**:
   - `ASTNode` 基底クラスおよび `ClassNode`, `ObjectPropertyNode`, `DatatypePropertyNode`, `AxiomNode`, `OntologyDocumentNode` を定義。
   - `@ontology_class` デコレータ、`ObjectPropertyField`, `DatatypePropertyField` などの宣言的プロパティ記述子を実装。
   - Xenon CC <= 5, mypy --strict を厳格遵守。
2. **フェーズ 2: 構文解析・静的制約検証エンジンの実装 (`parser.py`, `validator.py`)**:
   - DSL で書かれた Python クラス定義群をリフレクション走査し、`OntologyDocumentNode` (AST) を構築する `OntologyParser` を実装。
   - `SemanticValidator`: 未定義クラス/プロパティ参照、ドメイン・レンジ型不一致、多重定義、循環継承関係、排他公理違反を静的検査し、診断エラー/警告リストを返却。
3. **フェーズ 3: AST インタプリタ & Turtle コード生成器 (`interpreter.py`, `codegen_turtle.py`)**:
   - Visitor パターンに基づく `ASTVisitor` 基底クラスを実装。
   - `TurtleCodeGenerator`: AST を走査し、W3C RDF 1.1 Turtle (.ttl) 形式のプレフィックス、クラス定義、プロパティ定義、公理定義を生成。
4. **フェーズ 4: セキュリティドメイン知識の分離・移行 (`src/ontology/security/`)**:
   - 既存の 14 大エンティティ（`Paper`, `ThreatActor`, `AttackTechnique`, `Vulnerability`, `TargetAsset`, `DefenseMechanism`, `BenchmarkMetric`, `Incident`, `DetectionRule`, `PoCArtifact`, `Precondition`, `ResearchGap`, `ResidualRisk`, `PublicationVenue`）を、Pure Python DSL で宣言。
   - コアエンジン側からセキュリティ知識のハードコードを完全に除去。
5. **フェーズ 5: 互換性担保・ドキュメント更新・品質検証**:
   - `src/ontology/turtle_engine.py` にファサードを配置し、既存テストおよび `build_full_spectrum_security_ontology()` との 100% 互換性を保証。
   - `make check_format`, `make static_analysis` (xenon Grade A, mypy --strict), `pytest` 100% PASS を達成。

---

## 5. 完了条件 / Success Criteria (DoD)

- [x] オントロジーコア（`src/ontology/core/`）にセキュリティドメイン特有の用語や知識が一切含まれていないこと。
- [x] セキュリティオントロジーが Pure Python Class DSL を用いて宣言的に記述可能であること。
- [x] Python クラスから AST が正しく構築され、構文エラーや制約違反が適切にエラー検出されること。
- [x] AST インタプリタによって、W3C Turtle (.ttl) が正確に出力されること。
- [x] 既存の `outputs/ontology/security_ontology_v2.ttl` と同等以上のオントロジー定義が生成されること。
- [x] `make check_format` および `make static_analysis` (xenon Grade A, mypy --strict) が 100% PASS すること。
- [x] ドキュメント相対パスリンク規則を完全に遵守していること。
