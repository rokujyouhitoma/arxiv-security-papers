---
ID: 160
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] Pure-Python STIX 2.1 CTI 推論 & ATT&CK Navigator レイヤー自動生成基盤の実装 (ID: 160)

## 1. 概要 / Summary
外部ライブラリ（`python-stix2` 等）や外部クラウド/サービス（GitHub API, GitHub Issues/Discussions, alphaXiv 等）を一切使用せず、Python 標準ライブラリのみで論文テキスト（Abstract/本文）から MITRE ATT&CK Technique を自動推論し、STIX 2.1 準拠の SDO/SRO JSON および MITRE ATT&CK Navigator 仕様（v4.5）準拠のレイヤー JSON を自動出力する基盤を実装する。

これにより、arXiv セキュリティ論文の攻撃手法・防御策を業界標準の CTI（Cyber Threat Intelligence）形式へとローカル環境完結で形式化し、研究集中領域や防衛空白地帯（Research & Defense Gaps）の可視化を可能にする。

---

## 2. トレーサビリティ / Traceability
- 関連資料:
  - 先端知見統合と自律型分析プラットフォームのアーキテクチャ設計 (テーラーリング版 Phase 1)
  - `docs/designs/DSN-07-security_guard_and_rbac.md`
  - MITRE ATT&CK Navigator Layer Spec v4.5
  - OASIS STIX 2.1 Specification (Attack Pattern, Course of Action, Relationship)
  - Issue 150: `docs/issues/closed/150-implement-mitre-cti-stix-ingestion-and-catalog-pipeline.md`
  - Issue 152: `docs/issues/closed/152-integrate-cti-mitigations-with-defense-signatures.md`

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] `src/domain/security/cti/stix_model.py`: Pure-Python STIX 2.1 SDO/SRO モデル定義
- [ ] `src/domain/security/cti/inference.py`: 論文テキストからの Technique / TTP 推論エンジン
- [ ] `src/domain/security/cti/navigator.py`: ATT&CK Navigator Layer v4.5 JSON エクスポーター
- [ ] `src/domain/security/cti/__init__.py`: パッケージエクスポートの更新
- [ ] `tests/domain/test_stix_navigator.py`: 単体テスト新規作成
- [ ] `outputs/navigator/`: 生成された Navigator レイヤー格納ディレクトリ

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/160-pure-python-stix-navigator`

1. **Pure-Python STIX 2.1 モデル (`stix_model.py`)**:
   - `python-stix2` を使用せず、`AttackPattern`, `CourseOfAction`, `VulnerabilityRef`, `StixRelationship` を dataclass と canonical JSON 辞書出力で実装。
   - `spec_version = "2.1"`, deterministic ID 生成 (`attack-pattern--<uuid5>`, `relationship--<uuid5>`)。
2. **Technique 推論エンジン (`inference.py`)**:
   - 論文のタイトル・アブストラクトから、MITRE ATT&CK の手法名、ID（`Txxxx` / `Txxxx.xxx`）、および特徴キーワード（n-gram/文脈トークン照合）に基づき、確信度スコア付きで Technique を推論。
3. **ATT&CK Navigator レイヤー生成器 (`navigator.py`)**:
   - Navigator v4.5 仕様準拠の JSON 構造（`name`, `version`, `domain: "enterprise-attack"`, `techniques: [{"techniqueID": ..., "score": ..., "color": ..., "comment": ...}]`）を出力。
   - 論文言及数や攻撃/防御種別に応じたスコアリングとカラーグラデーション自動計算。
4. **制約と品質要件**:
   - 外部ライブラリ依存ゼロ（Python 標準ライブラリのみ）。
   - GitHub API や GitHub Issues / Discussions などの外部通信・連携は含めず、すべてローカルファイルシステム・内製ストアで完結。
   - Xenon 循環的複雑度 $\le 5$ (Rank A), Mypy `--strict` 準拠。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 外部ライブラリ `python-stix2` を一切含まずに STIX 2.1 SDO/SRO JSON が生成できること
- [ ] 論文テキストから ATT&CK Technique が推論され、確信度付きで抽出できること
- [ ] ATT&CK Navigator v4.5 準拠のレイヤー JSON が `outputs/navigator/` 配下に正しく出力されること
- [ ] 単体テスト `tests/domain/test_stix_navigator.py` が 100% PASS すること
- [ ] `make check_format` および `make static_analysis` (radon, xenon, flake8, mypy --strict) が 100% PASS すること
