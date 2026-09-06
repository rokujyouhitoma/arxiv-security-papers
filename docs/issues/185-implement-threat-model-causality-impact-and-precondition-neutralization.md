---
ID: 185
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] 脅威モデル因果連鎖（STRIDE・Impact / Consequence）および前提条件無力化モデルの実装 (ID: 185)

## 1. 概要 / Summary
攻撃手法がもたらす結果・被害影響（Impact / Consequence）および、防御策が攻撃の前提条件（Precondition）を打破・無力化する因果関係をオントロジーモデルとして形式化する。
1. **影響実体 `sec:Impact` の導入**: STRIDE分類（Spoofing, Tampering, Repudiation, Information Disclosure, Denial of Service, Elevation of Privilege）およびCIA（機密性・完全性・可用性）侵害レベルを表現するクラス。
2. **攻撃被害述語 `sec:hasImpact`**: `AttackTechnique` が成立した際に派生する `Impact` を表現（逆関係: `sec:impactCausedBy`）。
3. **前提条件無力化述語 `sec:neutralizesPrecondition`**: 論文が提案する `DefenseMechanism` が攻撃手法のどの `Precondition` を無力化・成立不能にするかの因果連鎖を表現（逆関係: `sec:preconditionNeutralizedBy`）。
4. **因果推論チェーンの確立**: 「防御策 $\rightarrow$ 前提条件無力化 $\rightarrow$ 攻撃手法阻害 $\rightarrow$ 被害影響の抑止」という一連の推論パスをオントロジー上で導出可能にする。

---

## 2. トレーサビリティ / Traceability
- 関連要求: [REQ-ONT-01](../../docs/requirements/REQ-ONT-01-security-paper-ontology.md)
- 設計仕様: [DSN-22](../../docs/designs/DSN-22-security_and_threat_ontology_w3c_specification.md)
- 関連Issue: [Issue 184](184-enhance-owl-logic-incident-coupling-and-standards-alignment.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [src/ontology/turtle_engine.py](../../src/ontology/turtle_engine.py) (オントロジー定義)
- [ ] [src/ontology/schema.py](../../src/ontology/schema.py) (スキーマ定義)
- [ ] [outputs/ontology/security_ontology_v2.ttl](../../outputs/ontology/security_ontology_v2.ttl)
- [ ] [tests/ontology/test_full_spectrum_ontology.py](../../tests/ontology/test_full_spectrum_ontology.py)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/185-implement-threat-model-causality-impact`

1. **クラス定義**:
   - `sec:Impact` (ラベル: "被害影響・影響度", コメント: "攻撃成立により発生する機密性/完全性/可用性の侵害または権限昇格等の結果事象")
2. **オブジェクトプロパティ定義**:
   - `sec:hasImpact` (Domain: `sec:AttackTechnique`, Range: `sec:Impact`, Inverse: `sec:impactCausedBy`)
   - `sec:neutralizesPrecondition` (Domain: `sec:DefenseMechanism`, Range: `sec:Precondition`, Inverse: `sec:preconditionNeutralizedBy`)
3. **データ型プロパティ定義**:
   - `sec:strideCategory` (Domain: `sec:Impact`, Range: `xsd:string`, 例: "Elevation of Privilege")
   - `sec:severityLevel` (Domain: `sec:Impact`, Range: `xsd:string`, 例: "Critical", "High")
4. **テスト作成 & 検証**:
   - 防御策から攻撃被害抑止への因果連鎖を検証するテストを追加。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `sec:Impact` クラスおよび `sec:hasImpact`, `sec:neutralizesPrecondition` 述語が定義されていること。
- [ ] すべてのプロパティに適切な逆関係 (`owl:inverseOf`) が設定されていること。
- [ ] STRIDE 分類用データ型プロパティが定義されていること。
- [ ] テストが全件 PASS すること。
