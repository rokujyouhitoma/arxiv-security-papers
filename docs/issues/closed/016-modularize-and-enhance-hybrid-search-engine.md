---
ID: 016
種別: Feature
優先度: High
ステータス: Closed (Completed)
完了日: 2026-08-16
---

# [FEAT/ENH] 検索エンジン機能モジュール別再設計・ハイブリッド検索パイプライン高度化 (ID: 016)

## 1. 概要 / Summary
検索エンジンの6大コア機能（①データ収集・クローリング、②解析・インデクシング、③クエリ理解・意図解析、④ハイブリッド・リトリーバル、⑤マルチステージ・ランキング、⑥プレゼンテーション・AI統合）の再設計方針に基づき、`src/search/` および周辺サービスのモジュール責務を明確化・強化しました。

クエリ理解層（正規化・同義語展開・クエリパーサー）からハイブリッド・リトリーバル層（BM25 疎検索 ＋ Vector 密検索）、マルチステージ・ランキング層（特徴量・多様性・ナレッジグラフ照合）、プレゼンテーション層（スニペット・ハイライト生成）へのデータフローを `QueryContext` およびモジュール別メソッドとして整理し、検索品質・拡張性・保守性を向上させました。

---

## 2. トレーサビリティ / Traceability
- **設計規約**: [AGENTS.md](../../.agents/AGENTS.md) (PM主導 13大専門エージェント協調・品質ゲート準拠)
- **関連Issue**:
  - [012-rearchitect-to-enterprise-multifield-search-engine.md](012-rearchitect-to-enterprise-multifield-search-engine.md) (多層フィールド別転置インデックス・高度クエリパーサー)
  - [010-integrate-advanced-index-types-and-multi-stage-rag-pipeline.md](010-integrate-advanced-index-types-and-multi-stage-rag-pipeline.md) (高度インデックス体系・多段階RAGパイプライン)
  - [015-enrich-mcp-server-for-coding-agents-with-resources-prompts-and-security-tools.md](015-enrich-mcp-server-for-coding-agents-with-resources-prompts-and-security-tools.md) (MCPサーバー高度化)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [src/search/query_parser.py](../../src/search/query_parser.py) (クエリ構文解析・意図抽出・QueryContext導入)
- [x] [src/search/synonym_expander.py](../../src/search/synonym_expander.py) (セキュリティドメイン同義語・類義語展開)
- [x] [src/search/vector_engine.py](../../src/search/vector_engine.py) (モジュール別パイプラインメソッド整備)
- [x] [src/search/highlighter.py](../../src/search/highlighter.py) (スニペット抽出・highlight_document追加)
- [x] [src/search/__init__.py](../../src/search/__init__.py) (QueryContextエクスポート)
- [x] [tests/test_vector_engine.py](../../tests/test_vector_engine.py) (QueryContextおよびパイプライン単体テスト)
- [x] [docs/issues/README.md](../README.md) (Issue台帳)

---

## 4. 実装結果 / Implementation Results
Target Branch: `feat/016-modularize-and-enhance-hybrid-search-engine`

1. **`QueryContext` クラスの実装**:
   - `raw_query`, `normalized_query`, `clauses`, `expanded_tokens`, `target_fields`, `intent` を一元管理するデータコンテナを導入。
   - `EnterpriseQueryParser.create_context()` により同義語展開とインテント分類を自動実行。
2. **`VectorEngine` のモジュール別パイプライン化**:
   - `prepare_query_context`: クエリ理解・コンテキスト生成
   - `retrieve_candidates`: 疎密ハイブリッド・候補プルーニング
   - `rerank_candidates`: 多段スコアリング・リランキング
   - `format_presentation`: ハイライト・スニペット生成
   - 既存の `search()`, `search_with_profile()`, `search_hybrid_pipeline()` をこれらに基づき再構成。
3. **プレゼンテーション層の強化**:
   - `DynamicHighlighter.highlight_document()` を追加し、複数フィールドのスニペット抽出を共通化。
4. **単体テストと静的解析の完了**:
   - `test_query_context_and_intent` および `test_modular_search_pipeline` を追加し、100% PASS を確認。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `QueryContext` およびハイブリッド検索パイプラインの各機能モジュール（クエリ理解、リトリーバル、ランキング、ハイライト）が明確に構造化されていること
- [x] 既存の Web 検索 (`src/web_server.py`) および MCP サーバー (`src/mcp_server.py`) との後方互換性が完全に維持されていること
- [x] `py_compile`, `mypy`, `pytest` がエラーゼロ（100% PASS）で通過すること
- [x] 相対リンクおよび OKF v0.2 規約に準拠していること
