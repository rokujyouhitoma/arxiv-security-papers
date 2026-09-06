# [REQ-ONT-01] オントロジー駆動知識アーキテクチャ要求仕様書 (Ontology-Driven Knowledge Architecture Specification)

本ドキュメントは、「`arxiv-security-papers`」システム全体が **オントロジー駆動（Ontology-Driven Architecture / ODA）** に基づいて構築・拡張・自律運用されることを規定する最上位の要求仕様書です。

---

## 1. 背景と基本思想 (Philosophy & Background - WHY)

### 1.1 オントロジーとは何か
オントロジー（Ontology）とは、特定領域における概念（Classes）、実体（Entities）、それらの間に成立する関係性（Properties / Relations）、およびドメイン固有の論理的公理（Axioms / Rules）を、**人間とコンピュータの双方が曖昧さなく処理・推論できるように形式化した知識体系**です。

### 1.2 なぜオントロジー駆動（Ontology-Driven）なのか
従来のシステム開発やデータパイプラインでは、データベースの物理スキーマ、APIのJSON構造、プログラミング言語のクラス定義、およびUI表現が個別に定義され、ドメイン概念の変更や拡張が発生するたびに各層へ手動で整合性を合わせる「スキーマの乖離・陳腐化」が多発していました。

また、近年のLLMや自律型AIエージェントの台頭において、単なる文字列ベクトルの類似度検索（Vector RAG）だけでは、因果関係の誤認、エンティティ関係のハルシネーション（幻覚）、および論理的矛盾を伴う出力が深刻な課題となっています。

本プロジェクトでは、**オントロジーを最上位の「唯一の真実（Single Source of Truth / SOT）」**として位置づけ、以下の3大原則に基づく「オントロジー駆動アーキテクチャ」をシステム全域に適用します。

1. **オントロジー第一原則 (Ontology-First Principle)**:
   すべてのデータモデル、抽出ロジック、グラフ推論、検索インデックス、およびAPIスキーマは、オントロジー定義（TBox: 概念・公理）から演繹的に導出されること。
2. **意味論的相互運用性 (Semantic Interoperability)**:
   W3C RDF 1.1 Turtle (.ttl) / OWL 2 仕様に完全準拠し、外部のナレッジグラフ、TripleStore、STIX 2.1、MITRE ATT&CK、および推論エンジンと標準プロトコルで相互接続可能であること。
3. **論理推論と説明責任 (Logical Inference & Explainability)**:
   論文知見から導出される攻撃手法、脆弱性、防御策の因果関係は、オントロジー公理（推移律、逆関係、排他制約）および推論ルール（EIROM）に基づいて客観的エビデンス・確信度とともに導出されること。

---

## 2. 機能要求事項 (Functional Requirements - WHAT)

### REQ-ONT-FR-01: W3C Turtle / OWL 標準オントロジー記述要求
- **要求**: システムは、セキュリティ論文知見および関連概念を W3C RDF 1.1 Turtle (.ttl) および OWL 2 形式で定義・シリアライズできる専用エンジン（`src/ontology/turtle_engine.py`）を内製・保持しなければならない。
- **目的**: 外部依存（重量級フレームワーク）を排した軽量・高速な知識エクスポートと標準化を実現するため。

### REQ-ONT-FR-02: TBox（概念・関係・公理）の厳密定義要求
- **要求**: システムは、セキュリティドメインにおける 7 大コア概念（Paper, ThreatActor, AttackTechnique, Vulnerability, TargetAsset, DefenseMechanism, BenchmarkMetric）およびそれらを結ぶ関係性述語を、ドメイン・レンジ制約、逆関係、推移関係とともにオントロジーとして形式化しなければならない。
- **目的**: 不正なエッジ接続や論理矛盾の混入をスキーマレベルで根絶するため。

### REQ-ONT-FR-03: ABox（実体データ）の動的抽出とオントロジー適合性検証要求
- **要求**: システムは、収集した論文原本（PDF/Abstract/Metadata）からエンティティおよび関係性を抽出する際、オントロジーの TBox 定義に照合して妥当性を検証（Conformance Checking）し、実体インスタンス（ABox）としてナレッジグラフに登録しなければならない。
- **目的**: 抽出データの信頼性とグラフ全体のトポロジ的一貫性を担保するため。

### REQ-ONT-FR-04: 多言語・教育的メタデータ付与要求
- **要求**: すべてのクラスおよびプロパティには、日本語による正確なラベル（`rdfs:label "@ja"`）および教育的解説（`rdfs:comment "@ja"`）を付与し、人間にとっても直感的に理解可能なメタデータを維持しなければならない。
- **目的**: AI エージェントだけでなく、セキュリティアナリストや初学者に対する知識伝達を最大化するため。

### REQ-ONT-FR-05: GraphRAG および因果探索連携要求
- **要求**: 検索エンジンおよび GraphRAG パイプラインは、オントロジーで定義された関係性（`sec:exploits`, `sec:mitigates`, `sec:discloses` 等）と推移関係を利用して、マルチホップの因果連鎖（例: 論文 -> 攻撃手法 -> 標的資産 -> 防御策）を論理的に探索・提示できなければならない。
- **目的**: 単なるキーワード一致を超えた、深いセキュリティインサイトの自動導出を実現するため。

---

## 3. 非機能要求事項 (Non-Functional Requirements)

### REQ-ONT-NFR-01: ゼロ外部依存性 (Pure Python Execution)
- システムのオントロジーエンジンおよびシリアライザは、`rdflib` 等の巨大な外部ライブラリを一切導入せず、標準ライブラリのみで完結する Pure Python 実装でなければならない。

### REQ-ONT-NFR-02: 厳格な型安全性と静的解析適合性
- オントロジー関連の全コードは、`mypy --strict` の完全通過、および Xenon 循環的複雑度（CC）最高評価 Grade A（絶対複雑度 A、モジュール平均 A）を維持しなければならない。

### REQ-ONT-NFR-03: 永続化とフォーマット相互運用性
- 生成されたオントロジー定義およびインスタンスデータは、標準的な拡張子 `.ttl` のテキストファイルとしてファイルシステム上に永続化可能であり、Protégé や Apache Jena、Neo4j などの標準ツールでエラーなく取り込み可能でなければならない。

---

## 4. トレーサビリティマトリクス (Traceability)

| 要求 ID | 実装コンポーネント | 設計仕様書 | プロセス規範 |
| :--- | :--- | :--- | :--- |
| **REQ-ONT-FR-01** | [src/ontology/turtle_engine.py](../../src/ontology/turtle_engine.py) | [DSN-22](../designs/DSN-22-security_and_threat_ontology_w3c_specification.md) | [ODD プロセス](../processes/ontology_driven_development_process.md) |
| **REQ-ONT-FR-02** | [src/ontology/schema.py](../../src/ontology/schema.py) | [DSN-14](../designs/DSN-14-database_and_knowledge_graph_engine.md) | [MNG-02](../processes/MNG-02-mitre_attack_cwe_ledger.md) |
| **REQ-ONT-FR-03** | [src/ontology/extractor.py](../../src/ontology/extractor.py) | [DSN-03](../designs/DSN-03-paper_collector_and_okf_converter.md) | [ODD プロセス](../processes/ontology_driven_development_process.md) |
| **REQ-ONT-FR-04** | [src/ontology/turtle_engine.py](../../src/ontology/turtle_engine.py) | [DSN-22](../designs/DSN-22-security_and_threat_ontology_w3c_specification.md) | [MNG-01](../processes/MNG-01-document_ledger.md) |
| **REQ-ONT-FR-05** | [src/graph/](../../src/graph/) / [src/database/](../../src/database/) | [DSN-05](../designs/DSN-05-multi_engine_hybrid_search.md) | [ODD プロセス](../processes/ontology_driven_development_process.md) |
