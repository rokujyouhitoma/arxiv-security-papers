---
ID: 247
種別: Feature
優先度: Medium
ステータス: Open (New)
担当エージェント: Software Development (SWD) / Information Security Specialist / Systems Architect
---

# [FEAT/CORE] Disjoint Set (Union-Find / 素集合データ構造) の共通コア実装と CTI 脅威グラフ連結成分・クラスタ検出の高速化 (ID: 247)

## 1. 概要 / Summary

本リポジトリのナレッジグラフおよび CTI（脅威インテリジェンス）解析層 [`src/graph/`](../../src/graph/) では、Dijkstra 最短経路や PageRank による重要度算出が実装されているが、共通の脅威アクター、攻撃キャンペーン、マルウェアファミリ、脆弱性（CVE/CWE）群が相互に形成する「連結成分（Connected Components）」の検出やクラスタリングの標準データ構造が未整備であった。

本タスクでは、経路圧縮（Path Compression）およびランク結合（Union by Rank）を備え、アッカーマン関数の逆関数 $\alpha(N)$ に比例するほぼ定数時間 $O(\alpha(N))$ で動作する **Disjoint Set (Union-Find)** を共通コア基盤 [`src/core/structures/disjoint_set.py`](../../src/core/structures/disjoint_set.py) に実装する。
これにより、CTI 脅威グラフのクラスタ抽出や、LSM-Tree SSTable のキー重複グループ判定などを高速かつ簡潔に実現する。

---

## 2. トレーサビリティ / Traceability

- **設計書**:
  - [`docs/designs/DSN-01-cyber_security_ontology_and_graph_engine.md`](../designs/DSN-01-cyber_security_ontology_and_graph_engine.md) (CTI Graph & Ontology)
- **学術・技術参照**:
  - Tarjan, R. E. (1975). "Efficiency of a Good But Not Linear Set Union Algorithm", *Journal of the ACM*.
- **規約**:
  - ゼロ外部依存（Standard Library Only）
  - Xenon Rank A (CC <= 4), `mypy --strict` 準拠

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [`src/core/structures/disjoint_set.py`](../../src/core/structures/disjoint_set.py) (新規):
  - `DisjointSet[T]`: 汎用型パラメータ対応、`find(x)` (経路圧縮), `union(x, y)` (ランク結合), `connected(x, y)`, `component_count()`, `get_components()`
- [ ] [`src/core/structures/__init__.py`](../../src/core/structures/__init__.py):
  - `DisjointSet` のエクスポート
- [ ] [`src/graph/structures.py`](../../src/graph/structures.py):
  - グラフ構造への連結成分抽出ヘルパーの追加
- [ ] [`src/graph/traversal.py`](../../src/graph/traversal.py):
  - `find_connected_threat_clusters(graph)` の実装
- [ ] [`tests/core/test_disjoint_set.py`](../../tests/core/test_disjoint_set.py) (新規):
  - 単体テスト（初期化、結合、循環結合、連結判定、全グループ辞書抽出）
- [ ] [`tests/graph/test_graph_engine.py`](../../tests/graph/test_graph_engine.py):
  - 脅威クラスタ検出の結合テスト

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/247-implement-disjoint-set-union-find-for-graph-clustering`

1. `src/core/structures/disjoint_set.py` にジェネリック `DisjointSet[T]` を実装。
2. 経路圧縮（Path Compression）による再帰・平坦化と、ランクまたはサイズによるツリー結合。
3. 全連結グループを取得する `get_components() -> Dict[T, Set[T]]` の提供。
4. `src/graph/` での CTI 脅威ノードクラスタリングへのバインド。
5. 単体テストおよび品質ゲート（Xenon, mypy）の検証。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `src/core/structures/disjoint_set.py` に `DisjointSet` が実装されていること。
- [ ] 経路圧縮とランク結合が正しく動作し、要素数 10 万件以上の結合・判定がミリ秒単位で完了すること。
- [ ] `tests/core/test_disjoint_set.py` が新規作成され、100% PASS すること。
- [ ] Xenon Rank A (CC <= 4)、`mypy --strict` 0 エラー、フォーマッタ 100% 合格であること。
