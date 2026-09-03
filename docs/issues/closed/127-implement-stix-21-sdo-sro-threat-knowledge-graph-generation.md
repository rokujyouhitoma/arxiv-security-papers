---
ID: 127
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT/ENH] OASIS STIX 2.1仕様準拠 SDO/SRO 脅威インテリジェンス・ナレッジグラフ自動構築パイプラインの実装 (ID: 127)

## 1. 概要 / Summary
学術論文の要約およびメタデータから抽出された知見を国際標準サイバー脅威インテリジェンス（CTI）へと昇華させるため、OASIS 標準の STIX 2.1（Structured Threat Information Expression）仕様に厳格準拠した SDO（STIX Domain Objects: `attack-pattern`, `vulnerability`, `course-of-action`, `threat-actor`, `identity`, `indicator`）および SRO（STIX Relationship Objects: `mitigates`, `targets`, `indicates`, `exploits`）の自動構築パイプラインを Pure Python（ゼロ外部依存）で実装する。

本パイプラインにより、OKF v0.2 ドキュメントおよび内製プロパティグラフから標準 STIX 2.1 JSON Bundle（`bundle--<UUIDv4>`）を生成し、OpenCTI や MISP 等の商用・オープンソース脅威インテリジェンスプラットフォームと直接相互運用可能なナレッジエクスポートを実現する。

---

## 2. トレーサビリティ / Traceability
- [DSN-17: セキュリティ知識オントロジー](../../docs/designs/DSN-17-security_knowledge_ontology.md)
- [REQ-03: プロジェクトユースケース台帳 (UC-RES-02, UC-NCO-04, UC-NCO-13)](../requirements/REQ-03-use_case_ledger.md)
- [Issue 135: arXivセキュリティ論文・MITRE ATT&CK・CWEナレッジグラフデータ基盤](closed/135-implement-paper-attck-cwe-knowledge-graph-and-dashboard-visualization.md)
- [Issue 128: PRIMUS知見に基づくCWE/CVSS/ATT&CK精密マッピングエンジン](128-implement-primus-cti-rcm-vsp-ate-precision-mapping-engine.md)
- [src/ontology/schema.py](../../src/ontology/schema.py)
- [src/ontology/extractor.py](../../src/ontology/extractor.py)
- [src/graph/structures.py](../../src/graph/structures.py)

---

## 3. 脅威モデリングとセキュリティ要件 (Threat Modeling & Mitigations)
- **T-127-01: STIX 識別子偽装および UUIDv4 衝突 (Identifier Spoofing)**
  - *脅威*: 外部から取り込まれた論文データにより、既存の正規な攻撃パターン ID（例: `attack-pattern--...`）と衝突する偽の SDO が生成され、脅威インテリジェンスが上書き改ざんされる。
  - *対策*: RFC 4122 準拠の暗号論的 UUIDv4 生成（`uuid.uuid4()`）または決定論的名前空間付き UUIDv5（論文 ID とエンティティ名のハッシュ結合）を用い、外部入力からの ID 直接指定を拒絶。
- **T-127-02: 巨大 STIX バンドルの一括シリアライズによるメモリ枯渇 (Bundle DoS)**
  - *脅威*: 数万件のエンティティとリレーションを一括して単一の巨大 JSON 文字列にダンプしようとし、Search / Web ワーカーのメモリを圧迫・クラッシュさせる。
  - *対策*: ジェネレータ形式（ストリーミング直列化）を採用し、最大バンドルサイズ制限（デフォルト 10,000 オブジェクト）およびチャンク分割書き出しを導入。
- **T-127-03: 不正リレーションによる CTI ナレッジグラフ循環・毒入れ (Graph Poisoning)**
  - *脅威*: 論文本文の誤読や悪意ある記述により、防御策が攻撃手法として誤分類（またはその逆）され、誤った自動防御ルールが下流に配信される。
  - *対策*: SRO 作成時に定義済みオントロジースキーマ（`allowed_relationships`）と突き合わせ、未承認の主語・目的語タイプの組み合わせ（例: `vulnerability` が `course-of-action` を `mitigates` する等）を厳格に拒否。

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files
- [x] `src/ontology/stix/__init__.py` (STIX サブパッケージのエクスポート)
- [x] `src/ontology/stix/sdo.py` (STIX ドメインオブジェクト dataclass 定義)
- [x] `src/ontology/stix/sro.py` (STIX リレーションシップオブジェクト dataclass 定義)
- [x] `src/ontology/stix/bundle.py` (STIX 2.1 Bundle コンテナおよび JSON エンコーダー)
- [x] `src/ontology/stix/generator.py` (OKF / SKO から STIX 2.1 への変換パイプライン)
- [x] `tests/ontology/test_stix_generator.py` (STIX 2.1 準拠性、必須フィールド、リレーション検証テスト)

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/127-implement-stix-21-sdo-sro-threat-knowledge-graph-generation`

1. **ステップ 1: STIX 2.1 オブジェクト定義 (`src/ontology/stix/sdo.py`, `src/ontology/stix/sro.py`)**:
   - `spec_version = "2.1"` を固定値とする基底データクラス `STIXObject` を定義（`id`, `created`, `modified`, `spec_version`, `labels`, `confidence`）。
   - SDO 定義:
     - `AttackPatternSDO`: MITRE ATT&CK 手法名、ID、外部参照（`external_references`）。
     - `VulnerabilitySDO`: CVE ID、CWE ID、CVSS スコア。
     - `CourseOfActionSDO`: 論文が提唱する防御手法、パッチ、緩和策。
     - `IdentitySDO`: 著者、研究機関、採択学会情報。
   - SRO 定義:
     - `RelationshipSRO`: `relationship_type` (`mitigates`, `targets`, `exploits`, `attributed-to`)、`source_ref`、`target_ref`。
2. **ステップ 2: STIX Bundle コンテナ (`src/ontology/stix/bundle.py`)**:
   - `STIXBundle` クラスを作成（`type="bundle"`, `id=f"bundle--{uuid4()}"`, `objects=[...]`）。
   - RFC 3339 / ISO 8601 準拠の UTC タイムスタンプ（ミリ秒精度 `YYYY-MM-DDTHH:MM:SS.sssZ`）シリアライザーを実装。
   - `to_json()`, `to_file(path)` をサポート。
3. **ステップ 3: OKF / SKO からの自動変換パイプライン (`src/ontology/stix/generator.py`)**:
   - `STIXGenerator` クラスを実装。OKF Markdown のフロントマター（`tags`, `provenance`, `trust`）および本文から抽出されたオントロジーエンティティ・トリプルを入力とする。
   - 抽出結果から SDO を生成し、対応する因果トリプルから SRO を生成して自動的に 1 つの Bundle へ集約。
   - 信頼度スコア（`confidence`: Gold=90, Silver=60）を付与。
4. **ステップ 4: テストスイートと品質ゲート検証**:
   - `tests/ontology/test_stix_generator.py` で OASIS STIX 2.1 仕様に基づく必須プロパティ（`spec_version`, `id` 命名規則, `source_ref`/`target_ref` の存在保証）を 100% テスト。
   - `make format`, `make static_analysis` (Xenon Rank A, Mypy Strict), `pytest` 100% PASS を達成。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] 外部依存ゼロ（標準ライブラリのみ）で STIX 2.1 準拠の JSON Bundle が正常に出力されること
- [x] 生成される全 SDO / SRO が STIX 2.1 の必須フィールド（`spec_version="2.1"`, `id`, `created`, `modified`）を具備すること
- [x] `source_ref` および `target_ref` が指し示す実体オブジェクトが Bundle 内に存在すること（ダングリングリレーションの根絶）
- [x] 不正なエンティティ間のリレーション試行時にスキーマバリデーションエラーが送出されること
- [x] 全品質ゲート（Xenon Rank A, Flake8 0 errors, Mypy Strict 0 errors, pytest 100% PASS）を満たすこと
