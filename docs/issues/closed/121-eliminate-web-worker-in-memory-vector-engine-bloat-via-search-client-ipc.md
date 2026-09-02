---
ID: 121
種別: Bug
優先度: High
ステータス: Closed (Completed)
---

# [BUG/SEC] WebワーカーにおけるVectorEngineオンメモリ展開の完全排除とSearchClient IPC移行 (ID: 121)

## 1. 概要 / Summary
Supervisor 上で Web ワーカー (`PID 17201`) のメモリ使用量 (PSS) が **1207.4 (1197.8) MB** まで急増するメモリ肥大化事象が発生。
アクセスログ及びコード解析の結果、Web ワーカーが `/api/mcp` エンドポイント経由で `mcp.papers_server.dispatch_tool` を呼び出した際、`mcp.papers_server.get_vector_engine()` が直接 `VectorEngine` を初期化し、全ベクトル・BM25 インデックス・近傍グラフを Web ワーカープロセス内のオンメモリに展開してしまっていたことが判明した。

### 再現手順 / Steps to Reproduce
1. Supervisor プロセスを起動 (`make start` または `supervisor` 経由)。
2. Web UI (`site/index.html`) の「⚡ MCP ツールサンドボックス」から `search_security_papers` や `verify_code_security` 等のツール実行リクエスト (`POST /api/mcp`) を送信する。
3. `supervisorctl top` または Top モニタを確認すると、リクエストを処理した Web ワーカーのメモリ使用量が 70MB 前後から **~1.2GB** に肥大化する。

### 再現環境 / Environment
- OS / Env: Linux / Supervisor Worker Pools (`web: 2/2`, `search: 1/1`)
- File: [src/web/gateway/handlers.py](../../src/web/gateway/handlers.py), [src/mcp/papers_server.py](../../src/mcp/papers_server.py), [src/search/client.py](../../src/search/client.py)

---

## 2. トレーサビリティ / Traceability
- [src/mcp/papers_server.py](../../src/mcp/papers_server.py): MCP Papers Server & Tool Handlers
- [src/web/gateway/handlers.py](../../src/web/gateway/handlers.py): Gateway MCP POST Handler
- [src/search/client.py](../../src/search/client.py): Search Engine Unix Socket IPC Client
- [tests/web/test_web_server.py](../../tests/web/test_web_server.py): Web Gateway & MCP Tests
- [tests/mcp/test_mcp_server.py](../../tests/mcp/test_mcp_server.py): MCP Server Unit & Integration Tests

---

## 3. 脅威分析・制約事項 / Threat Analysis & Operational Constraints
1. **ワーカー OOM (Out of Memory) による可用性毀損**:
   - *脅威*: Web ワーカーが複数起動し各ワーカーが 1.2GB のメモリを消費すると、コンテナやホストサーバーのメモリ枯渇（OOM Killer）により全サービスが停止する。
   - *緩和策*: すべての検索・取得処理を `SearchClient` 経由の IPC に委譲し、Web ワーカーは一切のベクトルインデックスをロードしない（常に < 80MB）。
2. **IPC 通信障害時のグレースフルフォールバック**:
   - *脅威*: `SearchService` ソケットが一時的に利用不能な場合、`SearchClient` がエラーを安全に返却し、クラッシュを防止する。

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [src/mcp/papers_server.py](../../src/mcp/papers_server.py)
- [x] [src/web/gateway/handlers.py](../../src/web/gateway/handlers.py)
- [x] [src/search/client.py](../../src/search/client.py)
- [x] [tests/mcp/test_mcp_server.py](../../tests/mcp/test_mcp_server.py)
- [x] [tests/web/test_web_server.py](../../tests/web/test_web_server.py)

---

## 5. 根本原因分析 (RCA) / Root Cause Analysis
1. **なぜ Web ワーカーのメモリが 1.2GB に急増したのか？**
   - Web ワーカープロセス内で `VectorEngine` の全ドキュメント・ベクトルストレージ (4,000+ 件の埋め込みベクトル・BM25・Proximity Graph) がインメモリにロードされたため。
2. **なぜ VectorEngine が Web プロセス内でロードされたのか？**
   - `POST /api/mcp` のハンドラ (`_execute_mcp_legacy_or_rpc` in `src/web/gateway/handlers.py`) が `mcp.papers_server.dispatch_tool()` を直接呼び出していたため。
3. **なぜ dispatch_tool が VectorEngine を生成したのか？**
   - `src/mcp/papers_server.py` 内の `get_vector_engine()` が、IPC サービス (`SearchClient`) 経由の問い合わせを行わず、常にプロセス内シングルトン `VectorEngine(workspace_dir=WORKSPACE_DIR)` を直接インスタンス化していたため。
4. **設計上の分離不備**:
   - Issue #111 で Web 検索 (`/api/search`) は `SearchClient` IPC への切り離しが行われたが、`/api/mcp` 経由の MCP ツール呼び出し群 (`search_security_papers`, `verify_code_security`, `get_related_papers_graph` 等) では `get_vector_engine()` が残存していた。

---

## 6. 実装方針 / Implementation Plan
Target Branch: `fix/121-eliminate-web-worker-in-memory-vector-engine-bloat-via-search-client-ipc`

1. **`src/mcp/papers_server.py` の `SearchClient` 統合**:
   - `get_search_client()` / `set_search_client(client)` を追加。
   - `get_vector_engine()` は `_VECTOR_ENGINE` が明示的に注入された場合のみ使用し、それ以外は `get_search_client()` を利用。
   - `handle_search_security_papers`: `get_search_client().search(...)` を使用。
   - `handle_search_papers_hybrid`: `get_search_client().search(...)` を使用。
   - `handle_query_knowledge_graph`: `get_search_client().get_related(...)` を使用。
   - `handle_query_attack_technique`: `get_search_client().search(...)` を使用。
   - `handle_get_related_papers_graph`: `get_search_client().get_related(...)` を使用。
   - `handle_verify_code_security`: `get_search_client().search(...)` を使用。
   - `handle_get_cwe_mitigation_recipe`: `get_search_client().search(...)` を使用。
2. **`src/web/gateway/handlers.py` との連携**:
   - `GatewayHandlers` の初期化時または `handle_mcp_post` 呼び出し時に `papers_server.set_search_client(self.search_client)` を共有し、同一ソケットクライアントで IPC 通信を行う。
3. **自動テストの追加と検証**:
   - `tests/web/test_web_server.py` に、`POST /api/mcp` 実行時に `application.handlers._search_client._fallback_engine` が `None` のままであり、インプロセス展開が発生しないことを検証するテストを追加。
   - `tests/mcp/test_mcp_server.py` の全テストがパスすることを確認。
4. **品質ゲート検証**:
   - `make format`, `make static_analysis`, `pytest` を実行し、100% パスを確認。

---

## 7. 完了条件 / Success Criteria (DoD)
- [x] `/api/mcp` 経由で `search_security_papers` や `verify_code_security` 等を呼び出した際に、Web プロセス内で `VectorEngine` が初期化されないこと（`SearchClient` IPC 経由で正常応答すること）
- [x] `src/mcp/papers_server.py` の全ツールが `SearchClient` IPC 経由で動作すること
- [x] Web ワーカーのメモリ使用量が 100MB 未満を維持すること
- [x] 全ユニットテスト・統合テスト（`make test`）および品質ゲート（`make format`, `make static_analysis`）が 100% PASS すること

