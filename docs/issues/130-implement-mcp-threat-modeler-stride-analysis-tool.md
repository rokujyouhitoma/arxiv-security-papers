---
ID: 130
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] IaC・OpenAPIスキーマ解析と論文知見照合によるSTRIDE脅威モデリング自動化MCPツール（mcp-threat-modeler）の実装 (ID: 130)

## 1. 概要 / Summary
開発者が作成したインフラ定義ファイル（IaC: Terraform や AWS CloudFormation）や OpenAPI スキーマをエージェントが読み込んだ際、最新の学術論文知見と照合して STRIDE 脅威分析を半自動実行する専用ツール `mcp-threat-modeler` を実装する。
システム構成内のコンポーネント特性から、リポジトリ内の最新論文から関連する攻撃シナリオや設定不備の事例を引き出し、構造化された緩和策（Course of Action）を提案する。

---

## 2. トレーサビリティ / Traceability
- [DSN-08: Model Context Protocol 戦略的エコシステム](../../docs/designs/DSN-08-mcp_strategic_ecosystem.md)
- [src/mcp/threat_defense_server.py](../../src/mcp/threat_defense_server.py)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] `src/mcp/tools/threat_modeler.py`
- [ ] `src/mcp/threat_defense_server.py`
- [ ] `tests/mcp/test_threat_modeler.py`

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/130-implement-mcp-threat-modeler-stride-analysis-tool`
1. IaC (JSON/YAML) および OpenAPI スキーマからのアーキテクチャコンポーネント抽出。
2. STRIDE 6大カテゴリ（Spoofing, Tampering, Repudiation, Information Disclosure, DoS, Elevation of Privilege）の脅威マッピング。
3. 論文ナレッジベースからの緩和論文（Mitigations）紐付け。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] IaC / OpenAPI スキーマを渡して STRIDE 分析結果と論文ベースの緩和策が返却されること
- [ ] MCP JSON-RPC 2.0 準拠のツール仕様を満たすこと
- [ ] 全品質ゲート（Xenon Rank A, Flake8, Mypy Strict, pytest）を 100% パスすること
