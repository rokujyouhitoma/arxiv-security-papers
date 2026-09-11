---
ID: 253
種別: Bug
優先度: Medium
ステータス: Open (In Progress)
---

# [BUG] Fix Context Mesh Paper Cluster Mapping to Sources Instead of Entities (ID: 253)

## 1. 概要 / Summary
`site/dashboard.html` の Context Mesh（コンテキストメッシュ可視化グラフ）において、原本・情報源である学術論文（`Paper`）ノードが、本来属すべき `SOURCE`（Sources: 情報源、赤系色）ではなく `ENTITY`（Entities: 実体・客体、濃灰系色）として分類・表示されてしまう不具合を解消する。

オントロジーおよびナレッジグラフの設計上、`Paper`（および `PublicationVenue`）はエビデンス（Provenance）の起点・原本としての「Source」であるべきであり、攻撃手法（`AttackTechnique`）や脆弱性（`Vulnerability`）などのセキュリティ対象実体である「Entity」と混同されてはならない。

### 再現手順 / Steps to Reproduce
1. Web ゲートウェイを起動し、ブラウザで `http://localhost:8000/site/dashboard.html` を開く。
2. Context Mesh 表示モードまたは Graph タブで、論文頂点（例: `iacr-2026-783` 等の `Paper` ノード）をクリックまたはインスペクトする。
3. ノード上部のクラスタバッジおよび色判定が、`SOURCE`（赤系: `#e0533c`）ではなく `ENTITY`（濃灰系: `#2b2b2b`）と表示される。

### 再現環境 / Environment
- OS / Env: Linux / All Browsers
- Target Files:
  - [site/dashboard.html](../../site/dashboard.html)
  - [src/web/gateway/handlers.py](../../src/web/gateway/handlers.py)
  - [tests/test_web_gateway.py](../../tests/test_web_gateway.py)

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [src/web/gateway/handlers.py](../../src/web/gateway/handlers.py) (`_extract_real_nodes`, `_build_dynamic_paper_mesh`)
- [x] [site/dashboard.html](../../site/dashboard.html) (`CLUSTERS`, `applyContextMesh`, ノード描画・インスペクト詳細)
- [x] [tests/web/gateway/test_gateway.py](../../tests/web/gateway/test_gateway.py) (メッシュ抽出クラスタの単体テスト)
- [x] [tests/web/test_dashboard_html.py](../../tests/web/test_dashboard_html.py) (フロントエンドクラスタ正規化の単体テスト)

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
1. **ABox 頂点抽出時のクラスタ名不一致**:
   - `src/web/gateway/handlers.py` の `_extract_real_nodes()` において、PropertyGraph 頂点ラベルをそのまま `v.label.lower()` でセットしているため、`Paper` 頂点は `"cluster": "paper"`、`PublicationVenue` は `"cluster": "publicationvenue"` となる。
2. **動的メッシュ生成時の複数形不一致**:
   - `_build_dynamic_paper_mesh()` では `"cluster": "sources"`, `"entities"`, `"claims"`, `"decisions"` と複数形文字列で指定されている。
3. **フロントエンド側のクラスタ定義とフォールバックの乖離**:
   - `site/dashboard.html` の `CLUSTERS` 定義には `{ source, entity, claim, decision, schema }` の 5 つの単数形キーしか存在しない。
   - `CLUSTERS[node.cluster] || CLUSTERS.entity` というフォールバック判定を行っているため、`"paper"`, `"sources"`, `"publicationvenue"` 等のキーが存在せず、すべてデフォルトの `CLUSTERS.entity`（バッジ: `ENTITY`、色: `#2b2b2b`）にフォールバックしてしまっていた。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**: なし
* **恒久対策 (Permanent Fix)**:
  1. **バックエンド (`src/web/gateway/handlers.py`) の統一クラスタマッピング**:
     - `_map_vertex_to_cluster(label: str) -> str` ヘルパー関数を導入。
     - `Paper`, `PublicationVenue` ➔ `"source"`
     - `Claim`, `Proposition`, `Finding` ➔ `"claim"`
     - `Decision`, `MitigationPolicy` ➔ `"decision"`
     - `Schema`, `OntologyClass` ➔ `"schema"`
     - それ以外（`AttackTechnique`, `Vulnerability`, `ThreatActor` 等） ➔ `"entity"`
     - `_build_dynamic_paper_mesh()` での出力キーも単数形（`"source"`, `"entity"`, `"claim"`, `"decision"`）に統一。
  2. **フロントエンド (`site/dashboard.html`) のエイリアス吸収と堅牢化**:
     - `resolveCluster(clusterKey: string)` 関数を導入し、`'paper'`, `'papers'`, `'sources'`, `'source'`, `'publicationvenue'` を確実に `source` に正規化。
     - `applyContextMesh()` およびノード描画・インスペクト詳細表示で正規化関数を経由させる。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `fix/253-fix-context-mesh-paper-cluster-classification`

### Step 1: バックエンドのマッピング統一
- `src/web/gateway/handlers.py`:
  - `_map_vertex_to_cluster(label: str) -> str` を定義。
  - `_extract_real_nodes()` で `v.label.lower()` の代わりに `_map_vertex_to_cluster(v.label)` を使用。
  - `_build_dynamic_paper_mesh()` で `"sources"` ➔ `"source"`, `"entities"` ➔ `"entity"`, `"claims"` ➔ `"claim"`, `"decisions"` ➔ `"decision"` に更新。

### Step 2: フロントエンドの正規化・エイリアス対応
- `site/dashboard.html`:
  - `resolveClusterKey(cluster)` 関数を定義（`paper` / `sources` / `publicationvenue` ➔ `'source'`, `entities` ➔ `'entity'`, `claims` ➔ `'claim'`, `decisions` ➔ `'decision'`）。
  - `applyContextMesh()` のクラスタ変換部を `resolveClusterKey` 準拠に更新。
  - キャンバス描画（`CLUSTERS[n.cluster]`）およびインスペクト表示（`CLUSTERS[node.cluster]`）で、未知クラスタでも `resolveClusterKey` を通すことで安全に `CLUSTERS.source` 等に解決。

### Step 3: テストと品質ゲート
- `tests/test_web_gateway.py`:
  - `Paper` ラベルの頂点が `_extract_real_nodes()` で `"cluster": "source"` となることを検証するテストケースを追加。
  - `_build_dynamic_paper_mesh()` のノードクラスタが正規化されていることを検証。
- `make check` (`make format`, `make static_analysis`, `make test`) を実行し 100% PASS を確認。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `Paper` および `PublicationVenue` 頂点が、Context Mesh において確実に `cluster: "source"`（バッジ: `SOURCE`、色: `#e0533c`）として分類・表示されること。
- [x] バックエンド（`handlers.py`）から返却されるメッシュノードのクラスタ名が、5大クラスタ（`sources`, `entities`, `claims`, `decisions`, `schema`）に正規化されていること。
- [x] フロントエンド（`dashboard.html`）側でも複数形・個別クラス名（`paper`, `sources` 等）のエイリアスが吸収され、破綻なく `SOURCE` として描画されること。
- [x] 新規・既存テストがすべて PASS すること。
- [x] `make check`（フォーマット、静的解析、単体テスト）が 100% PASS すること。
