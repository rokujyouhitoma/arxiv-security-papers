# Issue 台帳 (Issue Ledger)

本ドキュメントは、`arxiv-security-papers` プロジェクトにおけるタスク、新機能開発、リファクタリング、および障害修正の全 Issue 台帳です。

---

## 1. アクティブ Issue 一覧 (Active Issues)

| Issue ID | タイトル | 種別 | 優先度 | ステータス | 担当ブランチ / ファイル |
| :---: | --- | :---: | :---: | :---: | --- |
| **037** | [Makefile およびパイプラインにおける品質・テスト・ビルド基準の極限厳格化](037-enforce-strict-code-quality-and-test-standards.md) | Feature / Quality | High | New | `feat/037-enforce-strict-code-quality-and-test-standards` |
| **033** | [`src/database/` の内部エンジン進化（B+Tree インデックスおよび Cost-Based Query Planner の分離・実装）](033-enhance-database-with-btree-index-and-cost-based-planner.md) | Feature | Medium | New | `feat/033-database-btree-and-query-planner` |
| **034** | [Web サーバーの API Gateway 化と UI プレゼンテーション層の完全分離（`src/gateway/` / `src/presentation/`）](034-split-web-server-into-api-gateway-and-ui-presentation.md) | Feature / Arch | Low | New | `feat/034-split-gateway-and-presentation` |

---

## 2. 完了・アーカイブ済み Issue 一覧 (Closed Issues)

| Issue ID | タイトル | 種別 | 完了日 | アーカイブリンク |
| :---: | --- | :---: | :---: | --- |
| **036** | [Makefile 品質チェックにおけるエラー握りつぶし（`|| true`）の完全撤廃と厳格な品質ゲート適合](closed/036-enforce-strict-quality-gates-and-remove-error-suppression.md) | Feature / Refactor | 2026-08-19 | [036-enforce-strict-quality-gates-and-remove-error-suppression.md](closed/036-enforce-strict-quality-gates-and-remove-error-suppression.md) |
| **032** | [共通セキュリティ＆コンプライアンス基盤（`src/security/`）の独立集約](closed/032-consolidate-unified-security-guard-and-rbac.md) | Feature / Security | 2026-08-19 | [032-consolidate-unified-security-guard-and-rbac.md](closed/032-consolidate-unified-security-guard-and-rbac.md) |
| **035** | [VectorEngine テスト `test_vector_engine_indexing_and_search` が 312MB index.json の同期ロードによりブロック](closed/035-fix-vector-engine-test-blocking-on-312mb-index-load.md) | Bug | 2026-08-18 | [035-fix-vector-engine-test-blocking-on-312mb-index-load.md](closed/035-fix-vector-engine-test-blocking-on-312mb-index-load.md) |
| **031** | [`src/fetcher/` の ETL 3層（`ingestion` / `transformer` / `reporter`）アーキテクチャ分離](closed/031-refactor-fetcher-into-etl-pipeline-architecture.md) | Feature / Refactor | 2026-08-17 | [031-refactor-fetcher-into-etl-pipeline-architecture.md](closed/031-refactor-fetcher-into-etl-pipeline-architecture.md) |
| **030** | [4層ベクトルDBの重厚な性能・メモリプロファイリング評価およびSQL互換性テスト拡充](closed/030-database-performance-memory-profiling-and-sql-test-expansion.md) | Performance / Test | 2026-08-17 | [030-database-performance-memory-profiling-and-sql-test-expansion.md](closed/030-database-performance-memory-profiling-and-sql-test-expansion.md) |
| **029** | [`tests/` および `src/` ディレクトリのパッケージ階層（`database/`, `fetcher/`, `mcp/`, `search/`, `web/`）1:1完全対応化](closed/029-reorganize-tests-by-package-hierarchy.md) | Refactor | 2026-08-17 | [029-reorganize-tests-by-package-hierarchy.md](closed/029-reorganize-tests-by-package-hierarchy.md) |
| **028** | [SQLite型4層アーキテクチャ（VFS / Pager / VDBE / Compiler）に基づくゼロ依存ベクトルDB再設計・実装](closed/028-sqlite-inspired-vdbe-vfs-vector-architecture.md) | Feature | 2026-08-17 | [028-sqlite-inspired-vdbe-vfs-vector-architecture.md](closed/028-sqlite-inspired-vdbe-vfs-vector-architecture.md) |
| **027** | [ゼロ依存 / 純Python製 5大SQLコマンド体系（DDL / DQL / DML / DCL / TCL）エンジンおよび Python 標準 SQLite / PEP 249 DB-API 2.0 接続インターフェースの実装](closed/027-pure-python-sql-engine-support.md) | Feature | 2026-08-17 | [027-pure-python-sql-engine-support.md](closed/027-pure-python-sql-engine-support.md) |
| **026** | [ゼロ依存 / 純Python製ベクトルストレージ・近似近傍探索 (ANN/HNSW) エンジンおよび プロトコル駆動型疎結合基盤の実装](closed/026-pure-python-vector-storage-and-ann-engine.md) | Feature | 2026-08-17 | [026-pure-python-vector-storage-and-ann-engine.md](closed/026-pure-python-vector-storage-and-ann-engine.md) |
| **025** | [MCP および検索エンジンにおける処理速度・メモリ可観測性の統合とログダンプ・計測基盤の実装](closed/025-unified-performance-and-memory-observability.md) | Feature | 2026-08-17 | [025-unified-performance-and-memory-observability.md](closed/025-unified-performance-and-memory-observability.md) |
| **024** | [MCPサーバー群の `src/mcp/` パッケージ集約と共通JSON-RPC基盤の確立](closed/024-consolidate-mcp-servers-into-src-mcp.md) | Refactor | 2026-08-16 | [024-consolidate-mcp-servers-into-src-mcp.md](closed/024-consolidate-mcp-servers-into-src-mcp.md) |
| **023** | [DSN-12準拠: MCP 戦略的エコシステム拡張（Phase 1〜Phase 3）の実装](closed/023-mcp-strategic-ecosystem-expansion.md) | Feature | 2026-08-16 | [023-mcp-strategic-ecosystem-expansion.md](closed/023-mcp-strategic-ecosystem-expansion.md) |
| **022** | [DSN-11準拠: ASTセキュリティガードの多層堅牢化とパストラバーサル防御の実装](closed/022-ast-security-guard-hardening-and-traversal-defense.md) | Security | 2026-08-16 | [022-ast-security-guard-hardening-and-traversal-defense.md](closed/022-ast-security-guard-hardening-and-traversal-defense.md) |
| **021** | [情報検索評価フレームワーク（Precision@K / Recall@K / F1 / MAP / MRR / NDCG）の実装](closed/021-search-engine-evaluation-framework.md) | Feature | 2026-08-16 | [021-search-engine-evaluation-framework.md](closed/021-search-engine-evaluation-framework.md) |
| **020** | [ホットパスにおける多重ループ解消・アルゴリズム最適化と可観測性ベンチマーク実証](closed/020-hotpath-loop-optimization-and-benchmarking.md) | Performance | 2026-08-16 | [020-hotpath-loop-optimization-and-benchmarking.md](closed/020-hotpath-loop-optimization-and-benchmarking.md) |
| **019** | [AIコーディングエージェント向け可観測性（Observability）特化型 MCP サーバーの実装](closed/019-observability-mcp-server-for-ai-coding-agents.md) | Feature | 2026-08-16 | [019-observability-mcp-server-for-ai-coding-agents.md](closed/019-observability-mcp-server-for-ai-coding-agents.md) |
| **018** | [Python標準ライブラリを活用した計測可能性（可観測性・プロファイリング）基盤の構築](closed/018-standard-library-observability-and-profiling-framework.md) | Feature | 2026-08-16 | [018-standard-library-observability-and-profiling-framework.md](closed/018-standard-library-observability-and-profiling-framework.md) |
| **017** | [Apache Lucene / Solr パラダイムに基づく検索エンジン2層分離リアーキテクチャ](closed/017-rearchitect-search-engine-to-lucene-solr-paradigm.md) | Feature | 2026-08-16 | [017-rearchitect-search-engine-to-lucene-solr-paradigm.md](closed/017-rearchitect-search-engine-to-lucene-solr-paradigm.md) |
| **016** | [検索エンジン機能モジュール別再設計・ハイブリッド検索パイプライン高度化](closed/016-modularize-and-enhance-hybrid-search-engine.md) | Feature | 2026-08-16 | [016-modularize-and-enhance-hybrid-search-engine.md](closed/016-modularize-and-enhance-hybrid-search-engine.md) |
| **015** | [コーディングエージェント向け MCP サーバー超高度化（Resources / Prompts / セキュアコーディング支援ツール・Graph-RAG 統合）](closed/015-enrich-mcp-server-for-coding-agents-with-resources-prompts-and-security-tools.md) | Feature | 2026-08-16 | [015-enrich-mcp-server-for-coding-agents-with-resources-prompts-and-security-tools.md](closed/015-enrich-mcp-server-for-coding-agents-with-resources-prompts-and-security-tools.md) |
| **014** | [OKF .md プレーンテキスト配信 ＆ 独立 HTML プレビュー画面の実装と検索結果リンク配置](closed/014-support-okf-markdown-link-and-rich-html-preview.md) | Feature | 2026-08-16 | [014-support-okf-markdown-link-and-rich-html-preview.md](closed/014-support-okf-markdown-link-and-rich-html-preview.md) |
| **013** | [Raw データ（.txt / .pdf / .json）の直接静的配信とプレーンテキスト表示の最適化](closed/013-support-raw-data-static-serving-and-plain-text-delivery.md) | Fix | 2026-08-16 | [013-support-raw-data-static-serving-and-plain-text-delivery.md](closed/013-support-raw-data-static-serving-and-plain-text-delivery.md) |
| **012** | [多層フィールド別転置インデックス・高度クエリパーサー・動的ハイライトによるエンタープライズ検索エンジンへの全面リアーキテクチャ](closed/012-rearchitect-to-enterprise-multifield-search-engine.md) | Refactor | 2026-08-16 | [012-rearchitect-to-enterprise-multifield-search-engine.md](closed/012-rearchitect-to-enterprise-multifield-search-engine.md) |
| **011** | [論文間トポロジカル近傍グラフ（k-NN Proximity Graph）の事前計算 ＆ 関連論文ネットワーク可視化](closed/011-implement-paper-proximity-graph-and-topology-visualization.md) | Feature | 2026-08-16 | [011-implement-paper-proximity-graph-and-topology-visualization.md](closed/011-implement-paper-proximity-graph-and-topology-visualization.md) |
| **010** | [高度インデックス体系（密ベクトルANN・ナレッジグラフ・RAPTOR・ファセット・引用網・セマンティックキャッシュ）および多段階検索パイプラインの統合](closed/010-integrate-advanced-index-types-and-multi-stage-rag-pipeline.md) | Feature | 2026-08-16 | [010-integrate-advanced-index-types-and-multi-stage-rag-pipeline.md](closed/010-integrate-advanced-index-types-and-multi-stage-rag-pipeline.md) |
| **009** | [Python 3.14.7 へのアップグレード ＆ venv 仮想環境の再構築](closed/009-rebuild-venv-and-upgrade-to-python-3-14.md) | Enhancement | 2026-08-16 | [009-rebuild-venv-and-upgrade-to-python-3-14.md](closed/009-rebuild-venv-and-upgrade-to-python-3-14.md) |
| **008** | [アブストラクト全文の重み付けインデックス拡張 ＆ VectorEngine 検索再現率の向上](closed/008-expand-vector-engine-with-fulltext-abstract-indexing.md) | Feature | 2026-08-16 | [008-expand-vector-engine-with-fulltext-abstract-indexing.md](closed/008-expand-vector-engine-with-fulltext-abstract-indexing.md) |
| **007** | [Web サーバーの PEP 3333 WSGI インターフェース対応](closed/007-support-wsgi-interface-for-web-server.md) | Feature | 2026-08-16 | [007-support-wsgi-interface-for-web-server.md](closed/007-support-wsgi-interface-for-web-server.md) |
| **006** | [日本語 IR 検索エンジンの高度化 ＆ 自動特徴語抽出・事前注釈・FM-Index/BM25/転置統合](closed/006-enhance-japanese-ir-and-pre-annotations.md) | Feature | 2026-08-15 | [006-enhance-japanese-ir-and-pre-annotations.md](closed/006-enhance-japanese-ir-and-pre-annotations.md) |
| **005** | [yuzora 準拠の Google Closure Compiler ツール配置およびビルド設定統合](closed/005-integrate-closure-compiler-tooling.md) | Feature | 2026-08-15 | [005-integrate-closure-compiler-tooling.md](closed/005-integrate-closure-compiler-tooling.md) |
| **004** | [Lexer, Parser, AST, Evaluator, Renderer による Markdown Compiler Engine の構築](closed/004-implement-markdown-compiler-engine.md) | Feature | 2026-08-15 | [004-implement-markdown-compiler-engine.md](closed/004-implement-markdown-compiler-engine.md) |
| **003** | [MCP サーバおよび VectorDB をバックエンドとしたモダン Web 検索 UI の構築](closed/003-implement-web-search-ui-and-mcp-backend.md) | Feature | 2026-08-15 | [003-implement-web-search-ui-and-mcp-backend.md](closed/003-implement-web-search-ui-and-mcp-backend.md) |
| **002** | [セキュリティ同義語拡張・マルチフィールドハイブリッドスコアリング・段落チャンク化による検索エンジンおよび VectorDB の高度化](closed/002-enhance-search-engine-and-vector-db.md) | Feature | 2026-08-15 | [002-enhance-search-engine-and-vector-db.md](closed/002-enhance-search-engine-and-vector-db.md) |
| **001** | [MCP サーバおよびベクトル DB セマンティック検索エンジンの導入](closed/001-implement-mcp-server-and-vector-db.md) | Feature | 2026-08-15 | [001-implement-mcp-server-and-vector-db.md](closed/001-implement-mcp-server-and-vector-db.md) |
