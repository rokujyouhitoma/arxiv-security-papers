---
ID: 127
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] OASIS STIX 2.1仕様準拠 SDO/SRO 脅威インテリジェンス・ナレッジグラフ自動構築パイプラインの実装 (ID: 127)

## 1. 概要 / Summary
学術論文の要約データをサイバー脅威インテリジェンス（CTI）へと昇華させるため、OASIS 標準の STIX 2.1（Structured Threat Information Expression）仕様に準拠した SDO（STIX Domain Objects: attack-pattern, vulnerability, course-of-action, threat-actor, identity）および SRO（STIX Relationship Objects: mitigates, targets, indicates）を自動抽出し、ナレッジグラフとして構造化するパイプラインを実装する。

---

## 2. トレーサビリティ / Traceability
- [DSN-17: セキュリティ知識オントロジー](../../docs/designs/DSN-17-security_knowledge_ontology.md)
- [src/ontology/](../../src/ontology/)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] `src/ontology/stix/sdo.py`
- [ ] `src/ontology/stix/sro.py`
- [ ] `src/ontology/stix/generator.py`
- [ ] `tests/ontology/test_stix_generator.py`

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/127-implement-stix-21-sdo-sro-threat-knowledge-graph-generation`
1. STIX 2.1 データクラス定義（UUIDv4 ID、タイプ、タイムスタンプ、必須フィールド）。
2. OKF 要約 Markdown からの SDO エンティティ・SRO リレーションシップ自動抽出。
3. MISP / OpenCTI 等と連携可能な JSON Bundle 形式のエクスポート。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 論文から STIX 2.1 準拠の JSON Bundle が正常に生成されること
- [ ] SDO/SRO の必須プロパティおよびリレーションシップの整合性バリデーションが通ること
- [ ] 全品質ゲート（Xenon Rank A, Flake8, Mypy Strict, pytest）を 100% パスすること
