# [MCP-01] MCP サーバ ＆ ベクトル DB 仕様書 (MCP Server Specification) - arxiv-security-papers

本ドキュメントは、「`arxiv-security-papers`」プロジェクトにおいて提供される **Model Context Protocol (MCP) JSON-RPC 2.0 サーバ** および **セマンティックベクトル DB 検索エンジン** の詳細仕様、ツールの入力/出力スキーマ、およびセキュリティサンドボックス検証規則を定義する仕様書です。

---

## 1. 概要

本 MCP サーバ ([`src/mcp_server.py`](../../src/mcp_server.py)) は、Antigravity IDE、Antigravity 2.0、および外部 AI エージェントに対して `arxiv-security-papers` リポジトリの蓄積論文ナレッジ（14,000件以上の OKF ドキュメントおよび5層の日本語サマリー）を即時セマンティック検索・参照可能なインタフェースを提供するコンポーネントです。

---

## 2. 提供ツール (MCP Tools Manifest)

### 2.1 `search_security_papers`
- **目的**: 自然言語（日本語または英語）での論文ハイブリッド検索（ベクトル類似度＋BM25スコアリング）。
- **Input Schema**:
  ```json
  {
    "type": "object",
    "properties": {
      "query": { "type": "string", "description": "検索クエリ (日本語/英語)" },
      "top_k": { "type": "integer", "default": 5, "description": "取得件数" },
      "category": { "type": "string", "description": "カテゴリタグ絞り込み (例: cs.CR, cryptography)" }
    },
    "required": ["query"]
  }
  ```

### 2.2 `get_paper_summary`
- **目的**: 指定 `arxiv_id` の 100% 日本語構造化要約および OKF v0.2 ドキュメント内容を取得。
- **Input Schema**:
  ```json
  {
    "type": "object",
    "properties": {
      "arxiv_id": { "type": "string", "description": "arXiv論文ID (例: 2510.18232)" }
    },
    "required": ["arxiv_id"]
  }
  ```

### 2.3 `get_latest_trends`
- **目的**: 月次・四半期・通期の最新セキュリティトレンド、急上昇キーワード、および Mermaid マインドマップを取得。
- **Input Schema**:
  ```json
  {
    "type": "object",
    "properties": {
      "period": { "type": "string", "enum": ["monthly", "quarterly", "annual"], "default": "monthly" }
    }
  }
  ```

### 2.4 `query_attack_technique`
- **目的**: MITRE ATT&CK テクニック ID（例: `T1059`）や STRIDE カテゴリに関連する論文を逆引き取得。
- **Input Schema**:
  ```json
  {
    "type": "object",
    "properties": {
      "technique_id": { "type": "string", "description": "MITRE ATT&CK ID またはセキュリティ用語" }
    },
    "required": ["technique_id"]
  }
  ```

---

## 3. セキュリティ ガードレール (Security Sandboxing)

すべてのファイルオープン処理において、`is_safe_workspace_path()` 関数による二重検証が実行されます：
1. `os.path.realpath()` によるシンボリックリンクおよび相対パス脱出 (`../`) の絶対パス解決。
2. ターゲットパスが `WORKSPACE_DIR` の配下にあることの確認 (`startswith`)。
3. 敏感ファイル・ディレクトリ (`.ssh`, `.aws`, `.env`, `etc/passwd`) へのアクセスの拒絶。
