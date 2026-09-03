---
ID: 128
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] PRIMUS知見に基づくCWE/CVSS/ATT&CK精密マッピングエンジン（CTI-RCM, CTI-VSP, CTI-ATE）と来歴階層化の実装 (ID: 128)

## 1. 概要 / Summary
自然言語で記された論文のアブストラクトや本文から標準セキュリティ識別子を割り出す処理に、最新のサイバーセキュリティ専門評価体系（PRIMUS / CTI-Bench）の知見を取り入れたマッピングエンジンを組み込む。
根本原因（CTI-RCM $\rightarrow$ CWE）、深刻度予測（CTI-VSP $\rightarrow$ CVSS v3.1/v4.0）、攻撃技術抽出（CTI-ATE $\rightarrow$ MITRE ATT&CK）を推論し、確証度に応じたゴールドラベル／シルバーラベルの来歴階層化（Provenance-tiered）バリデーションを導入して展開ノイズと擬陽性を根絶する。

---

## 2. トレーサビリティ / Traceability
- [DSN-17: セキュリティ知識オントロジー](../../docs/designs/DSN-17-security_knowledge_ontology.md)
- [src/ontology/taxonomy.py](../../src/ontology/taxonomy.py)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] `src/ontology/primus/rcm.py`
- [ ] `src/ontology/primus/vsp.py`
- [ ] `src/ontology/primus/ate.py`
- [ ] `src/ontology/primus/provenance.py`
- [ ] `tests/ontology/test_primus_mapping.py`

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/128-implement-primus-cti-rcm-vsp-ate-precision-mapping-engine`
1. CTI-RCM (Root Cause Mapping): 脆弱性機序から 900+ CWE 分類への推論。
2. CTI-VSP (Vulnerability Severity Prediction): 攻撃前提条件・影響範囲から CVSS ベクトル文字列推定。
3. CTI-ATE (Attack Technique Extraction): TTPs 分解と ATT&CK Technique ID マッピング。
4. Provenance Tier（Gold / Silver）のメタデータ付与。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 論文テキストから CWE, CVSS, ATT&CK ID が高い精度で導出されること
- [ ] ラベルの確証度（Gold/Silver）がメタデータに分離保持されること
- [ ] 全品質ゲート（Xenon Rank A, Flake8, Mypy Strict, pytest）を 100% パスすること
