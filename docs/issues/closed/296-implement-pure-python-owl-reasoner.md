---
ID: 296
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT] Pure Python 完全自作 OWL DL / RL 推論エンジン (Tableau / Hypertableau & Datalog) の実装と HermiT / Pellet 参考実装トラッキング (ID: 296)

## 1. 概要 / Summary
セマンティック Web およびオントロジー工学の核心である OWL 2 DL（記述論理: $\mathcal{SROIQ}^{\mathcal{D}}$）および OWL 2 RL（多項式時間ルール推論）に基づき、外部ライブラリ（Java / owlready2 等）に一切依存しない **完全自作の Pure Python OWL 推論エンジン（Reasoner）** を実装する。

先行する代表的 DL 推論器である **HermiT**（オックスフォード大学, Hypertableau法）および **Pellet**（Clark & Parsia, Tableau法）のアルゴリズム、DL-Clause 正規化、ブロッキング手法、および SWRL ルール連携を「参考実装（Reference Tracking Specification）」として体系的にトラッキング・ドキュメント化しつつ、本リポジトリの設計哲学である「Pure Python 100%」を貫徹した推論基盤を提供する。

### 主な提供機能
1. **論理整合性検証（Consistency Checking & Clash Detection）**:
   - 排他クラス（`owl:disjointWith`）、存在・全称量化制約（`someValuesFrom`, `allValuesFrom`）、否定（`owl:complementOf`）における論理矛盾をバックトラッキング付き Tableau 展開で厳密検知。
2. **クラス階層の自動再構築（Classification / Subsumption）**:
   - クラス定義の論理包含関係（$C \sqsubseteq D \iff C \sqcap \neg D$ が充足不能）を判定し、暗黙的な上位・下位タクソノミーを自動再構成。
3. **大規模 ABox 向け高速推論（OWL 2 RL / Datalog Forward Chaining）**:
   - 14,000件超の論文インスタンス（ABox）に対し、多項式時間（PTime）で動作する前向き推論エンジンにより、推移律（`owl:TransitiveProperty`）、逆関係（`owl:inverseOf`）、ドメイン・レンジ制約を高速に演繹展開。
4. **矛盾原因の監査・説明責任（Inconsistency Explanation / Justification）**:
   - 矛盾検知時に Minimal Unsatisfiable Sub-ontology（MUS）を抽出し、どの公理とどのトリプルが論理衝突を起こしているかを人間および AI に監査可能な自然言語/構造化データで説明。
5. **HermiT / Pellet リファレンストラッキング**:
   - `docs/designs/DSN-26-pure-python-owl-dl-reasoner.md` および `src/ontology/reasoner/hermit_pellet_tracker.py` において、HermiT / Pellet の推論規則・最適化手法との対比・トラッキングを明文化。

---

## 2. トレーサビリティ / Traceability
- 発端: 監査所見に基づくオントロジー推論器実装要求（Issue #295 是正完了に続く論理推論エンジン自作要求）
- 参考標準・先行実装:
  - W3C OWL 2 Web Ontology Language Direct Semantics (2012)
  - HermiT Reasoner: *Hypertableau End-User and Algorithmic Documentation* (Motik, Shearer, Horrocks)
  - Pellet Reasoner: *The Design and Implementation of an OWL DL Reasoner* (Sirin, Parsia, Grau, Kalyanpur, Katz)
- 関連設計書:
  - `docs/designs/DSN-22-security_and_threat_ontology_w3c_specification.md`
  - `docs/designs/DSN-18-knowledge_graph_and_semantic_search.md`
  - `docs/designs/DSN-26-pure-python-owl-dl-reasoner.md` (新規策定・APPROVED)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [NEW] `docs/designs/DSN-26-pure-python-owl-dl-reasoner.md` (推論エンジンアーキテクチャ ＆ HermiT/Pellet トラッキング仕様)
- [x] [NEW] `src/ontology/reasoner/__init__.py`
- [x] [NEW] `src/ontology/reasoner/base.py` (抽象インターフェース、ConsistencyReport、Clash 型)
- [x] [NEW] `src/ontology/reasoner/ast_nodes.py` (DL 概念・公理表現 AST)
- [x] [NEW] `src/ontology/reasoner/tableaux.py` (Pure Python Tableau / Hypertableau 矛盾検知 ＆ ブロッキングエンジン)
- [x] [NEW] `src/ontology/reasoner/forward_rule_engine.py` (OWL 2 RL / Datalog 前向き演繹エンジン)
- [x] [NEW] `src/ontology/reasoner/explanation.py` (MUS 矛盾説明 ＆ 監査トレーサー)
- [x] [NEW] `src/ontology/reasoner/hermit_pellet_tracker.py` (HermiT / Pellet 仕様対比・追跡モジュール)
- [x] [NEW] `src/ontology/reasoner/facade.py` (統合推論ファサード)
- [x] [MODIFY] `src/mcp/threat_defense_server.py` (推論ツールハンドラー登録 `check_ontology_consistency`)
- [x] [NEW] `tests/ontology/reasoner/test_pure_owl_reasoner.py` (推論エンジン単体・統合テスト 12件全件PASS)
- [x] [MODIFY] `docs/issues/README.md`
- [x] [MODIFY] `docs/README.md`
- [x] [MODIFY] `README.md`

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/296-pure-python-owl-reasoner`

1. **設計書の策定 (`DSN-26`)**:
   - Tableau 法（Pellet）と Hypertableau 法（HermiT）のアルゴリズム的相違点（分岐数の削減、Individual Reuse、コアブロッキング）を整理。
   - Pure Python 実装におけるデータ構造、計算量抑制戦略、および ABox/TBox 分離モデルの明文化。
2. **DL AST およびインターフェース定義 (`ast_nodes.py`, `base.py`)**:
   - `Concept` (Atomic, Conjunction, Disjunction, Negation, Existential, Universal)
   - `Axiom` (SubClassOf, DisjointClasses, SubPropertyOf, InverseProperties, TransitiveProperty)
   - `ConsistencyReport`, `ClashExplanation`
3. **Tableau / Clash 探索エンジンの実装 (`tableaux.py`)**:
   - ノードラベル展開（$\sqcap, \sqcup, \exists, \forall$ 規則）
   - Clash 検出（$A \sqcap \neg A$、DisjointClasses 衝突）
   - Equality / Subset によるブロッキング機構（無限モデル防止）
4. **OWL 2 RL 前向き連鎖エンジンの実装 (`forward_rule_engine.py`)**:
   - 多項式時間で推移律・逆関係・型継承を展開し、ナレッジグラフトリプルを演繹的にマテリアライズ。
5. **矛盾説明生成 (`explanation.py`)**:
   - 矛盾を引き起こした最小公理集合を抽出し、自然言語および構造化データで説明文を生成。
6. **MCP 連携と品質ゲートの検証**:
   - `check_ontology_consistency` MCP ツール公開。
   - `make format`, `make static_analysis` (xenon Grade A, mypy --strict), `make test` の完全通過。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] 外部 Java や外部推論ライブラリに一切依存しない Pure Python 実装であること。
- [x] Tableau / Hypertableau エンジンが排他クラス、否定、量化制約の矛盾を正しく検知し、充足可能な場合はモデルを生成すること。
- [x] クラス階層の包含関係（Subsumption）の自動判定が正しく機能すること。
- [x] OWL 2 RL 前向き推論エンジンが多項式時間で推移律・逆関係トリプルを演繹展開すること。
- [x] 矛盾発生時に「どの公理とどのトリプルが矛盾したか」を説明する監査レポートが出力されること。
- [x] HermiT / Pellet の参考実装トラッキングドキュメントおよびコードが整備されていること。
- [x] `tests/ontology/reasoner/` テストスイートが 100% PASS すること。
- [x] `make check_format` および `make static_analysis` (xenon Grade A, mypy --strict, flake8 0 errors, `# flake8: noqa` 追加なし) に完全合格すること。
