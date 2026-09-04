---
ID: 142
種別: Bug
優先度: High
ステータス: Closed (Completed)
---

# [BUG] グラフクエリ探索結果が5秒ごとのLive Mesh同期でリセット・分裂する不具合の修正 (ID: 142)

## 1. 概要 / Summary
`http://localhost:8000/dashboard?tab=graph` において、`match: side-channel` などの CTI グラフクエリを実行すると、初動では対象サブグラフ（`Relations (97):` を持つ大きな Vertex を中心とする密結合ネットワーク）が正しく描画されるが、数秒後（最大 5 秒後）に突如として大きな Vertex が消失し、グラフ全体が初期メッシュクラスタへ分裂・リセットされてしまう問題が発生している。

### 再現手順 / Steps to Reproduce
1. ブラウザで `http://localhost:8000/dashboard?tab=graph` にアクセスする。
2. グラフクエリコンソールにて `match: side-channel` を入力（またはプリセットボタン「⚡ Side-Channel Leakage」をクリック）して探索を実行する。
3. 画面上に degree 97（半径 28px の最大 Vertex）を中心とするサブグラフが表示され、Relations (97) が確認できる。
4. 約 5 秒待機すると、画面上の大きな Vertex が突然消失し、ノード群が初期の多クラスタ状態へと散らばり（分裂）、デフォルトの CTI メッシュ（未検索の全域ノード群）に上書きされる。

### 再現環境 / Environment
- OS / Env: Linux / Google Antigravity Web Dashboard
- File: `site/dashboard.html`

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [site/dashboard.html](file:///workspace/arxiv-security-papers/site/dashboard.html)
- [x] [tests/web/test_dashboard_graph_tab.py](file:///workspace/arxiv-security-papers/tests/web/test_dashboard_graph_tab.py)

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
1. **無条件なデフォルトメッシュ同期**:
   - `site/dashboard.html` 内の `initSseLiveStream()` で `setInterval(syncLiveMesh, 5000)` が登録されている。
   - `syncLiveMesh()` では `currentGraphMode === 'cti'` の場合に無条件で `await fetchCtiMesh()` を実行している。
2. **クエリ状態（Active Query）の無視**:
   - `fetchCtiMesh()` は常に全体メッシュ API `/api/graph/cti-mesh?limit=150` を呼び出し、取得した全体ノード（平均 degree 1〜2）で `ctiRawNodes` および `ctiRawEdges` を上書きし、`applyCtiFilter()` を発火している。
   - ユーザーがクエリ探索中（`activeGraphQuery` 保持時）であってもこれを検知するガードが存在せず、探索結果が 5 秒ごとにデフォルト全体メッシュに強制上書きリセットされていた。
3. **ノード再配置と分裂（Dispersal）の誘発**:
   - `applyCtiFilter()` が呼ばれると、全体メッシュの 150 ノードが円形初期位置から物理演算（Force-directed repulsion）を開始するため、ユーザーの目には「大きな Vertex が消えてグラフが分裂した」ように見える。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**: 
  - なし（リロードしても 5 秒後に再発するためコード修正が必要）。
* **恒久対策 (Permanent Fix)**: 
  - `activeGraphQuery` 状態変数を導入し、クエリ探索中は `syncLiveMesh()` / `fetchCtiMesh()` によるデフォルトメッシュの上書きを完全に遮断（ガード）する。
  - クエリ実行中は必要に応じて同一クエリでの再同期を行うか、またはクエリ結果の安定表示を保証する。
  - ユーザーが「✕ リセット」または `clearGraphQuery()` を明示的に実行した場合にのみ `activeGraphQuery = null` とし、デフォルト全体メッシュへの復帰を許可する。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `fix/142-fix-graph-query-subgraph-reset-by-background-sync`

1. **状態管理の強化 (`site/dashboard.html`)**:
   - `let activeGraphQuery = null;` を導入。
   - `window.executeGraphQuery` 実行成功時に `activeGraphQuery = query;` を保持。
   - `window.clearGraphQuery` 実行時に `activeGraphQuery = null;` に初期化。
2. **バックグラウンド同期のガード (`syncLiveMesh`, `fetchCtiMesh`)**:
   - `syncLiveMesh()` 内において、`currentGraphMode === 'cti'` かつ `activeGraphQuery` が設定されている場合は `fetchCtiMesh()` をスキップする。
   - `fetchCtiMesh(force = false)` にガードを設け、クエリ実行中の不用意な呼び出しによる `ctiRawNodes` の破壊を防止。
3. **単体・結合テストの追加 / 拡張**:
   - `dashboard.html` 内の JavaScript ロジック整合性および、クエリ実行状態におけるバックグラウンド同期間隔ガードのテストを整備。
4. **品質ゲート検証**:
   - `make format`, `make static_analysis`, `pytest tests/web/` を実行し、100% PASS を確認。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `activeGraphQuery` 保持中に `syncLiveMesh` (5秒ごと) が実行されても、探索結果ノード・エッジがデフォルト全体メッシュで上書きされないこと。
- [x] `match: side-channel` 実行後、5秒以上経過しても degree 97 の大きな Vertex とサブグラフ構造が安定して維持され続けること。
- [x] 「✕ リセット」を押すと `activeGraphQuery` がクリアされ、正常にデフォルト CTI メッシュ（または Context メッシュ）に戻ること。
- [x] 全テスト・静的解析（Xenon Rank A, Mypy Strict, リンクリント）に合格すること。
