---
ID: 179
種別: Feature / Architecture
優先度: High
ステータス: Closed
---

# [FEAT/ARCH] 全領域統合セキュリティ知識オントロジー（Full-Spectrum SKO: 実脅威・防御コード・前提条件・研究ギャップ・信頼性来歴）の実装 (ID: 179)

## 1. 概要 / Summary

本 Issue では、ODA（オントロジー駆動アーキテクチャ）の中核である「論文（Paper）と因果関係」をさらに進化させ、学術知見を実務の防御・意思決定・AIエージェント自律行動へ直結させるための **5大領域統合セキュリティ知識オントロジー（Full-Spectrum Security Knowledge Ontology）** を構築・実装します。

1. **実世界脅威世界との接続**: `ThreatActor`, `Incident`, `verifiesCVE`
2. **防御の実装・即応成果物**: `DetectionRule` (Semgrep/Sigma/YARA), `PoCArtifact`, `blocks`, `generatesRule`
3. **成立前提・制約条件と評価指標**: `Precondition` (Threat Model/Access Level), `EvaluationMetric`, `requiresPrecondition`
4. **研究の限界・未解決課題**: `ResearchGap`, `ResidualRisk`, `leavesUnaddressed`, `identifiesGap`
5. **信頼性・査読来歴・再現性**: `PublicationVenue` (IEEE S&P, USENIX, CCS, NDSS), `reproducibilityTier`, `presentedAt`

---

## 2. トレーサビリティ / Traceability

- 関連プロセス:
  - [processes/MNG-01-document_ledger.md](../processes/MNG-01-document_ledger.md)
  - [processes/MNG-03-ontology_driven_development_process.md](../processes/MNG-03-ontology_driven_development_process.md)
- 関連要件:
  - [requirements/REQ-01-system_requirements.md](../requirements/REQ-01-system_requirements.md)
  - [requirements/REQ-ONT-01_ontology_driven_knowledge_architecture.md](../requirements/REQ-ONT-01_ontology_driven_knowledge_architecture.md)
- 関連設計:
  - [designs/DSN-14-graph_engineering_dashboard.md](../designs/DSN-14-graph_engineering_dashboard.md)
  - [designs/DSN-22-security_and_threat_ontology_w3c_specification.md](../designs/DSN-22-security_and_threat_ontology_w3c_specification.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [src/ontology/schema.py](../../src/ontology/schema.py) (新規エンティティ型・関係述語・データ構造追加)
- [x] [src/ontology/turtle_engine.py](../../src/ontology/turtle_engine.py) (全領域統合オントロジービルダー `build_full_spectrum_security_ontology`)
- [x] [src/ontology/extractor.py](../../src/ontology/extractor.py) (前提条件・研究ギャップ・防御ルール・来歴抽出器)
- [x] [src/ontology/extended_extractor.py](../../src/ontology/extended_extractor.py) (拡張エンティティ抽出エンジン)
- [x] [src/ontology/rule_registry.py](../../src/ontology/rule_registry.py) (新規関係性推論ルール)
- [x] [site/dashboard.html](../../site/dashboard.html) (新ノードカラー・凡例・フィルタリングUI)
- [x] [outputs/ontology/security_ontology_v2.ttl](../../outputs/ontology/security_ontology_v2.ttl) (生成される Turtle オントロジー)
- [x] [docs/requirements/REQ-ONT-01_ontology_driven_knowledge_architecture.md](../requirements/REQ-ONT-01_ontology_driven_knowledge_architecture.md) (要求事項 REQ-ONT-FR-06〜10 追記)
- [x] [docs/designs/DSN-22-security_and_threat_ontology_w3c_specification.md](../designs/DSN-22-security_and_threat_ontology_w3c_specification.md) (仕様拡充)
- [x] [tests/ontology/test_full_spectrum_ontology.py](../../tests/ontology/test_full_spectrum_ontology.py) (網羅的テストスイート)
- [x] [docs/issues/README.md](README.md) (Issue 台帳更新)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/179-implement-full-spectrum-security-knowledge-ontology`

1. **パッケージ 1: オントロジー層のスキーマ拡張と W3C Turtle 生成エンジン**:
   - `src/ontology/schema.py` に `DETECTION_RULE`, `PRECONDITION`, `RESEARCH_GAP`, `RESIDUAL_RISK`, `PUBLICATION_VENUE`, `POC_ARTIFACT` などを追加。
   - `src/ontology/turtle_engine.py` に `build_full_spectrum_security_ontology()` を実装し、`outputs/ontology/security_ontology_v2.ttl` を出力。
2. **パッケージ 2: 抽出・アノテーション層の拡張**:
   - `src/ontology/extractor.py` に前提条件（Threat Model）、研究ギャップ（Limitations）、防御コード（GitHub / Semgrep）、採択先（Venue）の抽出ロジックを追加。
3. **パッケージ 3: 知識グラフ＆推論層の拡張**:
   - 推論ルール（EIROM）に `blocks`, `requiresPrecondition`, `leavesUnaddressed`, `identifiesGap` を追加。
4. **パッケージ 4: Web ポータル＆可視化層の対応**:
   - `site/dashboard.html` / `site/app.js` に新ノードカラー・凡例・フィルタリングを追加。
5. **パッケージ 5: ドキュメント＆テスト整備**:
   - `REQ-ONT-01`, `DSN-22` を更新し、`tests/ontology/test_full_spectrum_ontology.py` で品質検証。

---

## 5. 完了条件 / Success Criteria (DoD)

- [x] 5 大領域（実脅威、防御コード、前提条件、研究ギャップ、信頼性来歴）のクラス・述語が `src/ontology/schema.py` および `src/ontology/turtle_engine.py` で定義されていること。
- [x] `outputs/ontology/security_ontology_v2.ttl` が有効な W3C Turtle 形式で出力されること。
- [x] `src/ontology/extractor.py` が論文テキストから前提条件、ギャップ、ルール、来歴を抽出できること。
- [x] `site/dashboard.html` で新ノード種別の色分けと凡例が表示可能であること。
- [x] `make check_format`、`make static_analysis` (xenon Grade A, mypy --strict)、単体テストが 100% PASS すること。
- [x] 相対パスリンク規則を完全に遵守していること。

