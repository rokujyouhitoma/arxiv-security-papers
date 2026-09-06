---
ID: 184
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT/ENH] OWL論理整合性向上・Incident孤立解消および既存標準語彙アライメント (ID: 184)

## 1. 概要 / Summary
オントロジー構築エンジン（`src/ontology/turtle_engine.py`）および出力オントロジー（`security_ontology_v2.ttl`）における論理構文上の不備を解消し、CTIおよび学術ドメインとしての表現力とGraphRAG/推論探索性を大幅に向上させる。
1. **孤立クラス `sec:Incident` の結合**: インシデントと攻撃手法、脆弱性、標的資産、脅威アクターを繋ぐ関係述語の定義。
2. **双方向関係 (`owl:inverseOf`) の体系的補完**: 防御策 $\leftrightarrow$ 攻撃手法、論文 $\leftrightarrow$ 提唱技術、脆弱性 $\leftrightarrow$ PoC 等の逆関係を定義し、SPARQLクエリやグラフ探索の利便性を最大化。
3. **プロパティ特性の付与**: 論文引用（`sec:cites`）や同盟関係等の対称性・推移性等の論理特性を明示。
4. **既存標準（Dublin Core, CiTO, STIX）とのアライメント**: `dcterms:`, `cito:` 等の外部語彙プレフィックス導入と `rdfs:subPropertyOf` マッピング。

---

## 2. トレーサビリティ / Traceability
- 関連要求: [REQ-ONT-01](../../docs/requirements/REQ-ONT-01-security-paper-ontology.md)
- 設計仕様: [DSN-22](../../docs/designs/DSN-22-security_and_threat_ontology_w3c_specification.md)
- 関連Issue: [Issue 179](closed/179-implement-full-spectrum-security-knowledge-ontology.md), [Issue 180](closed/180-decouple-ontology-definition-dsl-and-ast-interpreter-engine.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [src/ontology/turtle_engine.py](../../src/ontology/turtle_engine.py) (オントロジー定義ビルダー)
- [x] [src/ontology/schema.py](../../src/ontology/schema.py) (述語定義 Predicate の拡張)
- [x] [outputs/ontology/security_ontology_v2.ttl](../../outputs/ontology/security_ontology_v2.ttl) (W3C Turtle出力)
- [x] [tests/ontology/test_full_spectrum_ontology.py](../../tests/ontology/test_full_spectrum_ontology.py) (単体・統合テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/184-enhance-owl-logic-and-standards-alignment`

1. **外部標準プレフィックスの追加**:
   - `dcterms`: `http://purl.org/dc/terms/`
   - `cito`: `http://purl.org/spar/cito/`
   - `stix`: `http://docs.oasis-open.org/cti/ns/stix#`
2. **`sec:Incident` 結合述語の追加**:
   - `sec:observedInIncident` (AttackTechnique $\rightarrow$ Incident, inverse: `sec:incidentObservedTechnique`)
   - `sec:leveragedVulnerability` (Incident $\rightarrow$ Vulnerability, inverse: `sec:vulnerabilityLeveragedIn`)
   - `sec:attributedToActor` (Incident $\rightarrow$ ThreatActor, inverse: `sec:actorAttributedIncident`)
   - `sec:targetsAsset` (Incident $\rightarrow$ TargetAsset, inverse: `sec:assetTargetedInIncident`)
3. **`owl:inverseOf` 逆関係の網羅**:
   - `sec:mitigates` $\leftrightarrow$ `sec:mitigatedBy`
   - `sec:exploits` $\leftrightarrow$ `sec:exploitedBy`
   - `sec:proposes` $\leftrightarrow$ `sec:proposedIn`
   - `sec:discloses` $\leftrightarrow$ `sec:disclosedIn`
   - `sec:analyzes` $\leftrightarrow$ `sec:analyzedIn`
   - `sec:blocks` $\leftrightarrow$ `sec:blockedBy`
   - `sec:generatesRule` $\leftrightarrow$ `sec:ruleGeneratedBy`
   - `sec:requiresPrecondition` $\leftrightarrow$ `sec:preconditionRequiredBy`
   - `sec:leavesUnaddressed` $\leftrightarrow$ `sec:unaddressedBy`
   - `sec:identifiesGap` $\leftrightarrow$ `sec:gapIdentifiedBy`
   - `sec:presentedAt` $\leftrightarrow$ `sec:venuePresentedPaper`
   - `sec:hasPoC` $\leftrightarrow$ `sec:pocOfPaper`
   - `sec:verifiesCVE` $\leftrightarrow$ `sec:cveVerifiedBy`
4. **標準語彙マッピング (`rdfs:subPropertyOf`) の適用**:
   - `sec:title rdfs:subPropertyOf dcterms:title`
   - `sec:publishedDate rdfs:subPropertyOf dcterms:date`
   - `sec:cites rdfs:subPropertyOf cito:cites`
5. **テスト拡充 & .ttl 生成**:
   - `tests/ontology/test_full_spectrum_ontology.py` に逆関係・孤立クラス解消・語彙マッピングのテストを追加。
   - `outputs/ontology/security_ontology_v2.ttl` を再生成。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `sec:Incident` が孤立しておらず、4種以上の関係述語で攻撃手法・脆弱性・アクター・標的資産と結合されていること。
- [x] コアおよび拡張述語のすべてに `owl:inverseOf` が定義され、双方向推論が可能であること。
- [x] Dublin Core (`dcterms:`) および CiTO (`cito:`) への `rdfs:subPropertyOf` マッピングが `.ttl` に出力されていること。
- [x] 単体・統合テストが全件 PASS すること。
- [x] `outputs/ontology/security_ontology_v2.ttl` が W3C RDF/Turtle 構文として正当であること。
