---
ID: 129
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] 論文引用ネットワークとCTIナレッジグラフを統合したマルチホップGraphRAGパイプラインの実装 (ID: 129)

## 1. 概要 / Summary
抽出された STIX 知識グラフを論文間の引用関係（Citation Network）と同一のインメモリ有向グラフとして結合し、PageRank や幅優先探索（BFS）による近傍走査アルゴリズムを適用する。
特定の攻撃手法（例: ATT&CK T1059）を起点として、その派生攻撃を検証した論文群や、それに対抗する形式検証ツール・パッチ生成技術を提示した最新論文群をマルチホップ走査で特定する GraphRAG 機能を実装する。

---

## 2. トレーサビリティ / Traceability
- [DSN-18: Property Graph Database Engine](../../docs/designs/DSN-18-property_graph_database_engine.md)
- [src/graph/](../../src/graph/)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] `src/graph/graphrag_pipeline.py`
- [ ] `src/graph/citation_linker.py`
- [ ] `src/graph/traversal.py`
- [ ] `tests/graph/test_graphrag_pipeline.py`

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/129-implement-citation-network-cti-graphrag-pipeline`
1. 引用有向エッジ（`cites`）と CTI オントロジーエッジ（`mitigates`, `targets`）の統合グラフインデックス。
2. マルチホップ幅優先展開と PageRank 重要度スコアリング。
3. GraphRAG によるサブグラフトリプル合成とグラウンディング。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 攻撃起点からのマルチホップ走査（深さ 3〜5）で派生論文・防御論文が高速特定できること
- [ ] 引用ネットワークと CTI グラフが破綻なくインメモリ走査できること
- [ ] 全品質ゲート（Xenon Rank A, Flake8, Mypy Strict, pytest）を 100% パスすること
