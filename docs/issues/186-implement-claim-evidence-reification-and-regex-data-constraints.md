---
ID: 186
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] 主張（Claim）と実証（Evidence）の分離・エッジ属性具現化およびデータ型正規表現制約の実装 (ID: 186)

## 1. 概要 / Summary
学術論文の「著者による主張（Claim）」と第三者・実環境による「検証事実（Evidence）」を峻別し、グラフエッジに文脈情報（成功率、対象OS/アーキテクチャ、再現性等）を付与可能な具現化（Reification）アーキテクチャを確立する。また、識別子（CVE, CWE, ATT&CK）に対するデータ型制約をスキーマ層で導入する。
1. **主張・実証分離モデルの導入**: `sec:Claim`（論文の主張）および `sec:EvaluationResult`（実測・評価結果）クラスの追加。
2. **関係性の具現化（Reification）プロパティ**: 防御緩和や攻撃実証におけるエッジ属性（測定成功率、環境条件）を `sec:EvaluationResult` を介して表現。
3. **データ型正規表現制約（`xsd:pattern`）の適用**:
   - `CVE-YYYY-NNNN+`
   - `CWE-[0-9]+`
   - `T[0-9]{4}(\.[0-9]{3})?`
   これらのフォーマット違反を検知可能なカスタム Datatype 定義。

---

## 2. トレーサビリティ / Traceability
- 関連要求: [REQ-ONT-01](../../docs/requirements/REQ-ONT-01-security-paper-ontology.md)
- 設計仕様: [DSN-22](../../docs/designs/DSN-22-security_and_threat_ontology_w3c_specification.md)
- 関連Issue: [Issue 184](184-enhance-owl-logic-incident-coupling-and-standards-alignment.md), [Issue 185](185-implement-threat-model-causality-impact-and-precondition-neutralization.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [src/ontology/turtle_engine.py](../../src/ontology/turtle_engine.py) (オントロジー定義・データ型ビルダー)
- [ ] [outputs/ontology/security_ontology_v2.ttl](../../outputs/ontology/security_ontology_v2.ttl)
- [ ] [tests/ontology/test_full_spectrum_ontology.py](../../tests/ontology/test_full_spectrum_ontology.py)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/186-implement-claim-evidence-reification`

1. **具現化クラス定義**:
   - `sec:Claim` (論文が主張する緩和・検出等の命題)
   - `sec:EvaluationResult` (ベンチマーク・実験・実環境での検証結果イベント)
2. **具現化プロパティ定義**:
   - `sec:evaluatesClaim` (EvaluationResult $\rightarrow$ Claim)
   - `sec:evaluatesTechnique` (EvaluationResult $\rightarrow$ AttackTechnique)
   - `sec:successRate` (EvaluationResult $\rightarrow$ xsd:decimal)
   - `sec:targetEnvironment` (EvaluationResult $\rightarrow$ xsd:string)
   - `sec:empiricalEvidenceLevel` (EvaluationResult $\rightarrow$ xsd:string)
3. **識別子パターン制約（rdfs:Datatype）の導入**:
   - `sec:CVEIdentifier` (`xsd:pattern "[cC][vV][eE]-[0-9]{4}-[0-9]{4,}"`)
   - `sec:CWEIdentifier` (`xsd:pattern "[cC][wW][eE]-[0-9]+"`)
   - `sec:AttackTechniqueIdentifier` (`xsd:pattern "T[0-9]{4}(\\.[0-9]{3})?"`)
4. **テスト作成 & 検証**:
   - 具現化モデルのグラフ整合性および正規表現制約の出力テスト。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `sec:Claim`, `sec:EvaluationResult` クラスが定義され、エッジ属性（成功率・動作環境等）を保持できること。
- [ ] 論文の主張と第三者実証結果が分離して表現できること。
- [ ] CVE/CWE/ATT&CK 用の `rdfs:Datatype` パターン制約が定義されていること。
- [ ] テストが全件 PASS すること。
