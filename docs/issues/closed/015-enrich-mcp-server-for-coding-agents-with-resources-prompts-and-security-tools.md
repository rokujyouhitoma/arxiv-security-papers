---
ID: 015
種別: Feature / Architecture / MCP
優先度: High
ステータス: Closed (Completed)
完了日: 2026-08-16
---

# [FEAT/MCP] コーディングエージェント向け MCP サーバー超高度化（Resources / Prompts / セキュアコーディング支援ツール・Graph-RAG 統合） (ID: 015)

## 1. 概要 / Summary
Antigravity、Claude Code、Cursor、GitHub Copilot 等の自律型コーディングエージェントが、本リポジトリに蓄積された 14,000 件超のセキュリティ学術ナレッジをコード生成・脆弱性監査・PoC テスト作成時に最大限活用できるよう、**Model Context Protocol (MCP 2024-11-05 仕様準拠) サーバー（`src/mcp_server.py`）を包括的にリッチ化・高度化** しました。

MCP 仕様の 3 大柱である **`Tools`（動的関数呼出）** に加え、**`Resources`（論文・脅威マップの直接コンテキスト参照）** および **`Prompts`（学術根拠に基づくコード監査・PoC 生成プロンプト）** を完全実装し、AI エージェントと本セキュリティナレッジベースのシームレスな統合を完了しました。

---

## 2. 実装成果と提供機能 / Delivered Components & Capabilities

### 2.1 新規 MCP Tools（拡張関数群）
1. **`verify_code_security`**:
   - コード片から脆弱性パターン（SQLi, OS Command, Path Traversal, XSS, Broken Crypto, Deserialization 等）を解析し、リスクレベル・警告・学術根拠論文（arXiv ID/タイトル）・安全な修正コードパターンを返却。
2. **`get_cwe_mitigation_recipe`**:
   - 指定 CWE ID に対し、学術論文で実証された根本防御ロジック・アルゴリズムおよび関連論文一覧を返却。
3. **`get_related_papers_graph`**:
   - 論文間近傍トポロジー（Graph-RAG）のノード・エッジ・Mermaid 構成図を返却。

### 2.2 MCP Resources（直接コンテキスト参照）
- `arxiv://paper/{arxiv_id}`: 論文の OKF v0.2 Markdown を直接注入。
- `arxiv://trends/latest`: 最新の脅威動向レポートを直接注入。
- `arxiv://cwe-taxonomy`: CWE / MITRE ATT&CK マッピング辞書 JSON。

### 2.3 MCP Prompts（自律セキュリティワークフロー）
- `audit_code_with_papers`: コード差分の学術的脅威監査プロンプト。
- `generate_exploit_poc_tests`: 論文の攻撃手法に基づく pytest 用の防御テスト自動生成プロンプト。
- `recommend_cwe_mitigation`: CWE 根本防御コードパターンの生成プロンプト。

### 2.4 Web UI MCP サンドボックス統合
- ブラウザ上の MCP サンドボックス（`site/index.html`, `site/app.js`）で全ツールのテスト実行が可能。
- Google Closure Compiler で再コンパイル完了（`site/app-min.js`）。

---

## 3. 完了条件 (DoD) 検証結果
- [x] `verify_code_security` ツールでコード片から関連セキュリティ論文とリスク警告が返却されること。
- [x] `get_cwe_mitigation_recipe` ツールで CWE に応じた防御レシピが返却されること。
- [x] `get_related_papers_graph` ツールで近傍トポロジーが返却されること。
- [x] `resources/list`, `resources/read`, `prompts/list`, `prompts/get` が MCP 仕様に準拠して動作すること。
- [x] `make build_js`、`mypy`、`flake8`、`pytest` が 100% オールグリーンで通過すること。
