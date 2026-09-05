---
ID: 153
種別: Feature / Ops
優先度: High
ステータス: Closed
---

# [FEAT] Supervisor 4x daily 自律バッチ運用と過去OKF論文アーカイブの全量CTI再アノテーション・エンリッチメント (ID: 153)

## 1. 概要 / Summary
Issue 150 で構築した 697 件の MITRE ATT&CK テクニックおよび 44 件の緩和策カタログ、さらに Issue 152 で実現した攻撃-緩和策リレーションを活用し、過去に収集・変換された全 OKF 論文アーカイブ（`outputs/okf_papers/YYYY-MM-DD/*.md`）を一括再スキャンして最新 CTI 定義で再アノテーション（Backfill Enrichment）を行う基盤を実装する。
また、Supervisor プロセス管理基盤と連携し、1 日 4 回（00:00, 06:00, 12:00, 18:00）のパイプライン自動実行および CTI 整合性ヘルスチェックを完全自律化する。

---

## 2. トレーサビリティ / Traceability
- 関連仕様: [docs/designs/DSN-20-external_security_knowledge_ingestion_and_catalog_architecture.md](../designs/DSN-20-external_security_knowledge_ingestion_and_catalog_architecture.md)
- 関連Issue:
  - [Issue 150: MITRE ATT&CK CTI 定義取り込み・SQLiteカタログ基盤](closed/150-implement-mitre-cti-stix-ingestion-and-catalog-pipeline.md)
  - [Issue 151: ドメイン層（src/domain/security/）へのCTI・Taxonomy知識体系の再配置](closed/151-reorganize-domain-security-cti-taxonomy-boundaries.md)
  - [Issue 152: MITRE ATT&CK 緩和策自動マッピングと動的防衛シグネチャ生成連携](closed/152-integrate-cti-mitigations-with-defense-signatures.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [src/pipeline/cti_backfill.py](../../src/pipeline/cti_backfill.py)
- [Makefile](../../Makefile)
- [tests/pipeline/test_cti_backfill.py](../../tests/pipeline/test_cti_backfill.py)
- [docs/issues/153-implement-supervisor-4xdaily-cron-and-cti-backfill-reannotation.md](153-implement-supervisor-4xdaily-cron-and-cti-backfill-reannotation.md)

---

## 4. セキュリティ考慮事項 / Security Analysis
- **非破壊的アノテーション**: 既存 OKF Markdown の本文・構造を一切破壊せず、YAML フロントマターの特定メタデータ（`tags`, `cti_techniques`, `mitigations`）のみをアトミックに追記・更新。
- **パストラバーサル防御**: `security.validation.is_safe_workspace_path` により、ワークスペース外ファイルへの誤アクセスを厳格遮断。

---

## 5. 実装方針 / Implementation Plan
1. `src/pipeline/cti_backfill.py`:
   - `CTIBackfillEnricher` クラスを実装。
   - `outputs/okf_papers/` 配下の全 `.md` ファイルを安全に検索。
   - 論文本文およびタイトル・アブストラクトから、`MITRECTIRegistry` を用いて最新 ATT&CK テクニックを抽出。
   - 各テクニックに対応する MITRE 緩和策（`get_mitigations_for_technique`）を自動マッピング。
   - YAML フロントマターを安全に再構築してファイルを更新。
   - 処理件数、新規付与テクニック数、緩和策数の統計レポートを返却。
2. `Makefile`:
   - `make reannotate_cti` ターゲットを追加。
3. `tests/pipeline/test_cti_backfill.py`:
   - 一時ディレクトリに OKF Markdown を配置し、エンリッチメント前後の YAML フロントマター更新、冪等性、タグ保持をテスト。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `src/pipeline/cti_backfill.py` が実装され、OKF 論文への CTI 再アノテーションが正常動作すること。
- [x] テクニックのみならず、対応する MITRE 緩和策（Mitigations）も YAML に安全に付与されること。
- [x] `make reannotate_cti` ターゲットが Makefile に定義されていること。
- [x] 2 回連続実行してもデータが重複・破壊されないこと（冪等性保証）。
- [x] Xenon CC <= 5 (Rank A 100%) および `mypy --strict src` (0 errors) を完全達成すること。
- [x] 単体・結合テストが 100% PASS すること。
