---
ID: 011
種別: Feature
優先度: High
ステータス: Closed (Completed)
完了日: 2026-08-16
---

# [FEAT/ENH] 論文間トポロジカル近傍グラフ（k-NN Proximity Graph）の事前計算 ＆ 関連論文ネットワーク可視化 (ID: 011)

## 1. 概要 / Summary
従来のキーワード検索やクエリベースのセマンティック検索に加え、論文同士の多次元距離（TF-IDF 疎ベクトルコサイン類似度、セキュリティ注釈特徴語の一致度、被引用・共起関係）を事前バッチ計算し、トポロジカルな $k$-NN 近傍グラフ（Proximity Graph）としてインデックス（`outputs/vector_db/index.json`）に保持しました。

本機能により、以下の 2 大価値を実現しました：
1. **引用関係のない潜在的関連論文の即時レコメンド（Citation Blind Spot の解消）**:
   - 同時期・異コミュニティで発表された同一攻撃手法・脆弱性防御モデルを扱う論文を $O(1)$ で特定。
2. **Web ポータル全画面ビューア内での「Connected Papers 型」トポロジー可視化**:
   - 閲覧中の論文を中心とする近傍ノード（類似論文）およびエッジ（類似度・共通ドメイン）を Mermaid / インタラクティブグラフで動的描画し、クリックによるシームレスな芋づる式探索を実現。

---

## 2. トレーサビリティ / Traceability
- **要求仕様**:
  - [REQ-01: System Requirements](../../requirements/REQ-01-system_requirements.md) (REQ-FR-04: 高度検索 ＆ グラフナビゲーション)
  - [REQ-02: Feature List](../../requirements/REQ-02-feature_list.md) (F-04: ハイブリッド検索 ＆ トポロジー解析)
- **設計仕様**:
  - [DSN-01: High-Level Design](../../designs/DSN-01-high_level_design.md) (マルチエンジン ＆ グラフ結合)
  - [DSN-02: Low-Level Design](../../designs/DSN-02-low_level_design.md) (インデックススキーマ v2.1.0)
  - [DSN-05: Multi-Engine Hybrid Search](../../designs/DSN-05-multi_engine_hybrid_search.md) (トポロジカル近傍グラフ仕様)
  - [MCP-01: MCP Server Specification](../../mcp/MCP-01-mcp_server_specification.md)

---

## 3. 実装成果物 / Delivered Components
1. **コア近傍グラフモジュール (`src/search/proximity_graph.py`)**:
   - `ProximityGraphIndex` クラス（類似度計算、高速プルーニング近傍探索、Mermaid グラフ生成）
2. **検索エンジン統合 (`src/search/vector_engine.py`)**:
   - 14,169 件 OKF に対する `proximity_graph` の事前計算と `index.json` への永続化
   - `get_related_papers(doc_id)` メソッドの提供
3. **API ＆ MCP ツール (`src/web_server.py`, `src/mcp_server.py`)**:
   - REST エンドポイント `GET /api/paper/<id>/related`
   - MCP ツール `get_related_papers_graph`
4. **Web ポータル全画面ビューア統合 (`site/app.js`, `site/style.css`, `site/app-min.js`)**:
   - 関連論文トポロジーネットワーク（Mermaid ダイアグラムおよび近傍カード一覧）の動的描画
   - Google Closure Compiler による再コンパイル完了
5. **テストスイート (`tests/test_vector_engine.py`, `tests/test_mcp_server.py`, `tests/test_web_server.py`)**:
   - 単体・結合テストの追加および型チェック（MyPy/Flake8）100% PASS

---

## 4. 完了条件 (DoD) 検証結果
- [x] `ProximityGraphIndex` が各論文の上位近傍論文を $O(1)$ で即時返却できること。
- [x] `GET /api/paper/{arxiv_id}/related` および MCP ツールが正常にレスポンスを返すこと。
- [x] 全画面モーダル内に Mermaid による関連論文トポロジー図が美しく描画され、相互遷移できること。
- [x] `make build_js`（Google Closure Compiler）が 0 error, 0 warning で通過すること。
- [x] ドキュメント内に絶対パスリンクが存在しないこと（0 件検出）。
