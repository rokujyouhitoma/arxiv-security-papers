---
ID: 160
種別: Feature
優先度: High
ステータス: Open (In Progress)
---

# [FEAT/ENH] Pure-Python STIX 2.1 CTI 推論 & ATT&CK Navigator レイヤー自動生成基盤の実装 (ID: 160)

## 1. 概要 / Summary
外部ライブラリ（`python-stix2` 等）や外部サービス（GitHub API、GitHub Issues/Discussions、alphaXiv）を一切使用せず、Python 標準ライブラリのみで論文テキスト（Abstract/本文）から MITRE ATT&CK Technique を自動推論し、OASIS STIX 2.1 準拠の SDO/SRO JSON および MITRE ATT&CK Navigator 仕様（v4.5）準拠のレイヤー JSON を自動出力する基盤を実装する。

これにより、arXiv セキュリティ論文群の攻撃手法・防御策を業界標準の CTI（Cyber Threat Intelligence）形式へとローカル環境完結で形式化し、研究集中領域や防衛空白地帯（Security Coverage Gaps）の視覚的ヒートマップ分析を可能にする。

---

## 2. トレーサビリティ / Traceability
- 関連資料:
  - 先端知見統合と自律型分析プラットフォームのアーキテクチャ設計 (テーラーリング版 Phase 1)
  - `docs/designs/DSN-07-security_guard_and_rbac.md` (Rev 2.2)
  - MITRE ATT&CK Navigator Layer Spec v4.5
  - OASIS STIX 2.1 Specification (Attack Pattern, Course of Action, Relationship, Bundle)
  - Issue 150: `docs/issues/closed/150-implement-mitre-cti-stix-ingestion-and-catalog-pipeline.md` (STIX CTI Ingestion)
  - Issue 152: `docs/issues/closed/152-integrate-cti-mitigations-with-defense-signatures.md` (Mitigations & Signatures)

---

## 3. 脅威モデリングとセキュリティ要件 (Threat Model & Security Requirements)
1. **信頼できない外部入力の無害化**:
   - arXiv から取得した論文テキストやアブストラクトには特殊文字や制御文字、JSON インジェクション文字が含まれる可能性がある。
   - すべての STIX 2.1 SDO プロパティおよび Navigator JSON 出力において、厳格な型変換と標準 `json.dumps` エスケープを徹底する。
2. **決定論的かつ衝突耐性のある ID 生成**:
   - STIX 2.1 仕様に準拠し、ランダム UUID4 ではなく RFC 4122 / STIX 2.1 準拠の UUIDv5（名前空間ベースの決定論的ハッシュ）を採用し、同一手法・論文に対して再現性のある一意 ID を生成する。
3. **ローカル主権性とゼロ外部通信**:
   - 外部サービス（GitHub API / alphaXiv / 外部 CTI サーバー）との通信を一切行わず、オフラインローカル環境下で 100% 決定論的に動作することを保証する。

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] `src/domain/security/cti/stix_model.py`: Pure-Python STIX 2.1 SDO/SRO モデルクラス・決定論的ID生成器
- [ ] `src/domain/security/cti/inference.py`: 語彙・文脈照合駆動の Technique 推論エンジン
- [ ] `src/domain/security/cti/navigator.py`: ATT&CK Navigator Layer v4.5 JSON エクスポーター
- [ ] `src/domain/security/cti/__init__.py`: 新規モジュールのエクスポート追加
- [ ] `outputs/navigator/`: 生成レイヤー JSON の出力先ディレクトリ
- [ ] `tests/domain/test_stix_navigator.py`: STIX 2.1 出力、推論エンジン、および Navigator 生成の単体テスト

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/160-pure-python-stix-navigator`

### 5.1 Pure-Python STIX 2.1 SDO/SRO データモデル (`src/domain/security/cti/stix_model.py`)
- `python-stix2` への依存を排除し、Python 標準の `@dataclass(frozen=True)` および `typing` で形式定義：
  - **`AttackPattern`**: `id` (`attack-pattern--<uuid5>`), `name`, `description`, `external_references` (MITRE ID: `Txxxx`), `kill_chain_phases` (Tactic), `spec_version = "2.1"`
  - **`CourseOfAction`**: `id` (`course-of-action--<uuid5>`), `name`, `description`, `external_references`
  - **`StixRelationship`**: `id` (`relationship--<uuid5>`), `relationship_type` (`"mitigates"`, `"targets"`, `"subtechnique-of"`), `source_ref`, `target_ref`, `spec_version = "2.1"`
  - **`StixBundle`**: `type = "bundle"`, `id` (`bundle--<uuid5>`), `objects: List[Dict[str, Any]]`
- **決定論的 ID 生成**:
  - `generate_stix_id(type_name: str, identifier: str, namespace: uuid.UUID = STIX_NAMESPACE) -> str`:
    `f"{type_name}--{uuid.uuid5(namespace, f'{type_name}:{identifier}')}"`
- **シリアライズ**:
  - `to_dict()` および `to_json()` メソッドにより、STIX 2.1 準拠の canonical JSON を出力。

### 5.2 語彙・文脈ベースの Technique 推論エンジン (`src/domain/security/cti/inference.py`)
- **`InferredTechnique`**:
  - `technique_id: str` (e.g. `T1190`)
  - `technique_name: str`
  - `tactic: str`
  - `confidence: float` (0.0 〜 1.0)
  - `matched_keywords: List[str]`
  - `research_focus: str` (`"offensive"`, `"defensive"`, `"analysis"`)
- **`TechniqueInferenceEngine`**:
  - `infer(title: str, text: str, paper_id: Optional[str] = None) -> List[InferredTechnique]`
  - 判定ロジック:
    - ① 直接 ID マッチ（`T1059` 等の正規表現検知）: 確信度 1.0
    - ② タイトル語彙一致（Technique 名または特徴キーフレーズ）: 重み 0.8
    - ③ 本文・アブストラクト語彙一致（`keywords` および専門用語照合）: 重み 0.3 〜 0.7
    - ④ 攻撃系（PoC, attack, bypass）vs 防御系（mitigate, defense, detection）の文脈判定
  - 確信度閾値（デフォルト `0.4`）以上の Technique をスコア降順で返却。

### 5.3 MITRE ATT&CK Navigator Layer v4.5 生成器 (`src/domain/security/cti/navigator.py`)
- **`NavigatorLayerConfig`**:
  - `name: str` (e.g. `"arXiv Security Papers - Coverage Layer"`)
  - `domain: str = "enterprise-attack"`
  - `version: str = "4.5"`
  - `description: str`
- **`generate_navigator_layer(inferences_by_paper: Dict[str, List[InferredTechnique]], config: Optional[NavigatorLayerConfig] = None) -> Dict[str, Any]`**:
  - 各 Technique の言及論文数を集計し `score` を算出。
  - カラーグラデーション算出（言及数 1 件: 黄色 `#ffd966`, 3 件: 橙色 `#f6b26b`, 5 件以上: 赤色 `#e06666`）。
  - `comment` フィールドに言及論文 ID リスト（`2401.xxxxx` 等）を自動集約。
  - `export_navigator_file(layer_dict: Dict[str, Any], output_path: str) -> str`: `outputs/navigator/` 配下へ整形 JSON ファイルを出力。

### 5.4 制約・品質保証
- **外部依存ゼロ**: Python 標準ライブラリ (`uuid`, `json`, `re`, `typing`, `dataclasses`, `datetime`, `math`, `os`, `pathlib`) のみ使用。
- **Xenon 循環的複雑度**: 全関数・メソッド $\le 5$ (Rank A 必須)。
- **Mypy `--strict` 適合**: 100% 型安全。
- **外部通信完全遮断**: GitHub API, Discussions, alphaXiv への外部 HTTP 通信は一切行わない。

---

## 6. 完了条件 / Success Criteria (DoD)
- [ ] `stix_model.py` が `python-stix2` なしで STIX 2.1 準拠の SDO/SRO/Bundle JSON を決定論的 ID で生成できること
- [ ] `inference.py` が論文タイトルおよびアブストラクトから ATT&CK Technique を推論し、確信度・マッチ語彙を返却できること
- [ ] `navigator.py` が ATT&CK Navigator Spec v4.5 準拠のレイヤー JSON を正しく出力し、ヒートマップ色とコメントが正しく構成されること
- [ ] `outputs/navigator/` ディレクトリにレイヤーファイルが書き出し可能であること
- [ ] 単体テスト `tests/domain/test_stix_navigator.py` が 100% PASS すること
- [ ] `make check_format` および `make static_analysis` (radon, xenon Rank A, flake8, mypy --strict) が 100% PASS すること
