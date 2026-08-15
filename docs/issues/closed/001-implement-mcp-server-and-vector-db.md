---
ID: 001
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT] MCP サーバおよびベクトル DB セマンティック検索エンジンの導入 (ID: 001)

## 1. 概要 / Summary
`arxiv-security-papers` リポジトリの蓄積論文群（原本JSON/PDF/TXT、OKF v0.2 Markdown、5層日本語サマリー）を AI エージェントや外部クライアントから高度にセマンティック検索・参照可能にするため、標準 Model Context Protocol (MCP) サーバおよびベクトル DB 検索エンジンを導入します。

---

## 2. トレーサビリティ / Traceability
- **アーキテクチャ定義**: `docs/hld.md`, `docs/lld.md`
- **MCP 規格**: Anthropic / Google Model Context Protocol JSON-RPC 2.0 Specification
- **プロジェクトルール**: `.agents/AGENTS.md` (Antigravity IDE & 2.0 Integration Rules)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [`src/vector_engine.py`](../../src/vector_engine.py): ハイブリッドベクトル＆BM25検索エンジン
- [x] [`src/mcp_server.py`](../../src/mcp_server.py): MCP JSON-RPC 標準サーバー
- [x] [`.agents/mcp_config.json`](../../.agents/mcp_config.json): MCP サーバ登録設定
- [x] [`tests/test_mcp_server.py`](../../tests/test_mcp_server.py): MCP & VectorEngine 単体テスト
- [x] [`Makefile`](../../Makefile): `build_vector_db`, `run_mcp_server`, `rag_query` ターゲット追加
- [x] [`pyproject.toml`](../../pyproject.toml): ビルドおよび依存定義
- [x] [`requirements.txt`](../../requirements.txt): ツール依存性定義

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/001-mcp-server-and-vector-db`

1. **`src/vector_engine.py` の構築**:
   - `outputs/okf_papers/` 配下の全 OKF ドキュメントをスキャンし、Title, Description (1文要約), Tags, Content をトークナイズ・ベクトル化。
   - `outputs/vector_db/index.json` に永続化インデックスを出力。
2. **`src/mcp_server.py` の構築**:
   - `search_security_papers`, `get_paper_summary`, `get_latest_trends`, `query_attack_technique` の 4 大 MCP ツールを実装。
   - stdio 経由での標準 MCP JSON-RPC 2.0 リクエスト処理。
3. **ワークスペース設定と Makefile 統合**:
   - `.agents/mcp_config.json` を作成し、エージェント環境へ接続。
   - `Makefile` に `build_vector_db`, `run_mcp_server`, `rag_query` ターゲットを追加。
4. **単体テストと動作検証**:
   - `tests/test_mcp_server.py` にテストケースを追加し、`make test` を実行。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `make py_compile` が構文エラー 0 件で成功すること。
- [x] `make build_vector_db` により `outputs/vector_db/index.json` が正常構築されること。
- [x] `make rag_query Q="malware"` で上位関連論文が検索取得できること。
- [x] `make test` により全単体テストが 100% PASS すること。
- [x] `.agents/mcp_config.json` が正しく設定されていること。
