# Issue #101: 論文パイプラインとグラフDB・GraphRAGの完全統合および因果チェーンAPIの実装

## 1. 概要 (Overview)
本インテリジェンス基盤（`arxiv-security-papers`）において、論文の収集・変換パイプラインからナレッジグラフへの自動インジェスト、GraphRAG（知識グラフ拡張型 LLM 推論）、および多ホップ因果関係推論（Attack-Defense Causal Chain）をエンドツーエンドで統合・実用化する。

### 実現する機能
1. **パイプライン自動インジェスト**: 論文フェッチ・OKF変換時に `OntologyExtractor` を連動させ、`PropertyGraphEngine` (Dual CSR) および `src/database/` (SQL vertices/edges) に自動格納
2. **GraphRAG 統合パイプライン**: ベクトル検索（ANN）+ 2ホップ因果サブグラフ展開による根拠（Grounding Context）の自動生成
3. **因果チェーン & 防御策逆引き API**: 新着攻撃・脆弱性に対する過去論文の有効防御アルゴリズム自動探索
4. **MCP サーバー連携**: Claude / Cursor 等の LLM エージェントからグラフ走査・GraphRAG を呼び出す MCP ツールの追加

- **ステータス**: 完了 (Closed)
- **完了日**: 2026-08-28
- **担当**: IT Specialist (NLP & IR) & Systems Architect Agent
- **優先度**: 高

---

## 2. 影響範囲 (Scope & Target Files)
- `src/pipeline/arxiv_okf_fetcher.py`: グラフ自動インジェスト連携
- `src/pipeline/transformer/`: オントロジー・グラフ変換ステージ
- `src/graph/graphrag.py`: GraphRAG パイプラインの強化（ベクトル検索 $\times$ サブグラフ結合）
- `src/mcp/threat_defense_server.py` / `src/mcp/papers_server.py`: グラフ走査・GraphRAG MCP ツール追加
- `tests/pipeline/test_pipeline.py` & `tests/graph/test_graphrag.py`: 単体・統合テスト

---

## 3. 完了条件 (Definition of Done)
- [ ] 論文フェッチ・OKF 生成時にグラフデータベース（`graph.db`）および SQL 頂点・辺テーブルが自動更新される
- [ ] GraphRAG による起点論文からの 2 ホップ因果関係（CVE, MITRE, Defense）サブグラフ展開が正常動作する
- [ ] MCP サーバー経由でグラフ走査および因果チェーン探索が実行できる
- [ ] `make check`（フォーマット、静的解析、単体テスト）が 100% PASS する
