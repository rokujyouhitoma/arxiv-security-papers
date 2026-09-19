---
ID: 350
種別: Refactor
優先度: High
ステータス: Closed (Completed)
完了日: 2026-09-19
---

# [FEAT/ENH] `DisjointSet`: `site/dashboard.html` の LCC 計算 (`computeLargestConnectedComponent`) および孤立ノード判定の高速化 (ID: 350)

## 1. 概要 / Summary
`site/dashboard.html` (L2200〜L2239) における最大連結成分 (Largest Connected Component, LCC) 探索関数 `computeLargestConnectedComponent(nodes, edges)` は、現在手動の BFS キュー探索で実装されている。
これを `site/js/frameworks/disjoint-set.js` の `DisjointSet` (Union-Find) に委譲する形式にリファクタリングし、計算量を $O((V+E)\alpha(V))$ に高速化するとともに、孤立ノード判定 (`getIsolates()`) などのトポロジー分析基盤を統一する。

---

## 2. トレーサビリティ / Traceability
- 関連 Issue:
  - [344-port-disjoint-set-to-frontend-lcc-clustering.md](closed/344-port-disjoint-set-to-frontend-lcc-clustering.md)
  - [348-extract-graph-canvas-engine-from-dashboard.md](closed/348-extract-graph-canvas-engine-from-dashboard.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [site/dashboard.html](../site/dashboard.html) (L2200 `computeLargestConnectedComponent`, グラフフィルタリングロジック)
- [ ] [tests/web/test_dashboard_topology.py](../tests/web/test_dashboard_topology.py) (LCC 判定テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `refactor/350-delegate-dashboard-lcc-to-disjoint-set`

1. `site/dashboard.html` の `computeLargestConnectedComponent(nodes, edges)` を更新:
   - `window.DisjointSet` が存在する場合、`const ds = new window.DisjointSet();` を用いて全ノードを `add` し、エッジごとに `union(e.source, e.target)` を実行。
   - `new Set(ds.getLargestComponent())` を返却（呼び出し元の戻り値シグネチャである `Set<string|number>` を厳密に維持）。
   - 万一 `DisjointSet` 未初期化環境の安全策として、従来の BFS をフォールバックとして保持。
2. 孤立ノード判定やクラスター分割への `ds.getIsolates()`, `ds.getComponents()` の活用。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `computeLargestConnectedComponent` が `DisjointSet` を利用して同一の正しい最大連結成分を返却すること。
- [ ] 戻り値の型 (`Set`) およびシグネチャが後方互換を完全に維持していること。
- [ ] `tests/web/test_dashboard_topology.py` を含むダッシュボード全テストが PASS すること。
- [ ] Closure Compiler によるコンパイルがエラー 0 件であること。
