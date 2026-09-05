---
ID: 152
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT] MITRE ATT&CK 緩和策（Mitigations）自動マッピングと動的防衛シグネチャ生成（Semgrep/Sigma/YARA）連携強化 (ID: 152)

## 1. 概要 / Summary
Issue 150 で構築された MITRE ATT&CK CTI カタログ（`cti_catalog.db`）には、697 件のテクニックだけでなく、44 件の緩和策（Mitigations: M1049, M1042 等）および 1,923 件の関連性（`mitigates` リレーション）が蓄積されている。
本 Issue では、攻撃手法（テクニック ID）に対応する MITRE 推奨緩和策を即座にリレーション結合・検索する機能を `CTIStorage` / `MITRECTIRegistry` に追加し、`threat_defense_server` MCP ツール群（`generate_sigma_rule`, `synthesize_detection_signature` 等）や新規ツール `get_mitigations_for_threat` を通じて、脅威検知シグネチャと具体的な防衛策を統合提示できるようにする。

---

## 2. トレーサビリティ / Traceability
- 関連仕様: [docs/designs/DSN-20-external_security_knowledge_ingestion_and_catalog_architecture.md](../designs/DSN-20-external_security_knowledge_ingestion_and_catalog_architecture.md)
- 関連Issue:
  - [Issue 150: MITRE ATT&CK CTI 定義取り込み・SQLiteカタログ基盤](closed/150-implement-mitre-cti-stix-ingestion-and-catalog-pipeline.md)
  - [Issue 151: ドメイン層（src/domain/security/）へのCTI・Taxonomy知識体系の再配置](closed/151-reorganize-domain-security-cti-taxonomy-boundaries.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [src/domain/security/cti/storage.py](../../src/domain/security/cti/storage.py)
- [src/domain/security/cti/registry.py](../../src/domain/security/cti/registry.py)
- [src/security/cti/registry.py](../../src/security/cti/registry.py)
- [src/security/cti/storage.py](../../src/security/cti/storage.py)
- [src/mcp/threat_defense_server.py](../../src/mcp/threat_defense_server.py)
- [tests/security/test_mitigation_defense_integration.py](../../tests/security/test_mitigation_defense_integration.py)

---

## 4. セキュリティ考慮事項 / Security Analysis
- **入力サニタイズ**: テクニック ID 入力に対して正規化と安全なプレースホルダーバインド（SQLite Parameterized Query）を強制し、SQL インジェクションを根絶。
- **純粋 Python / ゼロ外部依存**: 外部ネットワーク通信を行わず、ローカル SQLite `cti_catalog.db` およびフォールバック定義のみで完結。

---

## 5. 実装方針 / Implementation Plan
1. `CTIStorage.get_mitigations_for_technique(tech_id)`:
   - `cti_relationships` テーブルから `target_id = tech_id` かつ `relationship_type = 'mitigates'` となる `source_id` を取得。
   - `cti_mitigations` テーブルと結合し、該当緩和策（ID, 名称, 概要）のリストを返却。
2. `MITRECTIRegistry.get_mitigations_for_technique(tech_id)`:
   - ストレージから該当緩和策を取得し、キャッシュまたはフォールバック緩和策とマージ。
3. `threat_defense_server.py`:
   - ツール `get_mitigations_for_threat` を追加。
   - `generate_sigma_rule` および `synthesize_detection_signature` の結果に、推奨される MITRE 緩和策情報を包含。
4. 単体・結合テストの追加（Xenon Rank A, Mypy strict 準拠）。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `CTIStorage` および `MITRECTIRegistry` からテクニックに対応する緩和策リストが正しく取得できること。
- [x] `threat_defense_server` に `get_mitigations_for_threat` ツールが追加され、正常に応答すること。
- [x] `generate_sigma_rule` のレスポンスに緩和策推奨情報が含まれること。
- [x] Xenon 循環的複雑度 Grade A（CC <= 5）を 100% 維持すること。
- [x] `mypy --strict src` で型エラー 0 件であること。
- [x] 単体・結合テストが 100% PASS すること。
