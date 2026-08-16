---
ID: 024
種別: Refactor / Architecture
優先度: High
ステータス: Closed (Completed)
---

# [REFACTOR] MCPサーバー群の `src/mcp/` パッケージ集約と共通JSON-RPC基盤の確立 (ID: 024)

## 1. 概要 / Summary
機能設計書 [DSN-12](../../designs/DSN-12-mcp-strategic-ecosystem-expansion.md) および **Systems Architect (SA) / IT Strategist (ST)** の方針に基づき、`src/` 直下に散在していた 4 大 MCP サーバー群を **`src/mcp/` パッケージ** に集約し、共通の JSON-RPC トランスポート基盤（`src/mcp/base.py`）を導入してリポジトリの凝集度と保守性を飛躍的に向上させました。

---

## 2. トレーサビリティ / Traceability
- **設計規約**: [AGENTS.md](../../../.agents/AGENTS.md) (Systems Architect / PM)
- **設計書**: [DSN-12-mcp-strategic-ecosystem-expansion.md](../../designs/DSN-12-mcp-strategic-ecosystem-expansion.md), [DSN-11-repository-security-and-threat-defense.md](../../designs/DSN-11-repository-security-and-threat-defense.md)
- **関連Issue**: [023-mcp-strategic-ecosystem-expansion.md](closed/023-mcp-strategic-ecosystem-expansion.md), [022-ast-security-guard-hardening-and-traversal-defense.md](closed/022-ast-security-guard-hardening-and-traversal-defense.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [src/mcp/__init__.py](../../../src/mcp/__init__.py)
- [x] [src/mcp/base.py](../../../src/mcp/base.py) (共通 JSON-RPC トランスポートループ `run_mcp_server`)
- [x] [src/mcp/papers_server.py](../../../src/mcp/papers_server.py) (旧 `src/mcp_server.py`)
- [x] [src/mcp/observability_server.py](../../../src/mcp/observability_server.py) (旧 `src/observability_mcp_server.py`)
- [x] [src/mcp/threat_defense_server.py](../../../src/mcp/threat_defense_server.py) (旧 `src/threat_defense_mcp_server.py`)
- [x] [src/mcp/tech_radar_server.py](../../../src/mcp/tech_radar_server.py) (旧 `src/tech_radar_mcp_server.py`)
- [x] [src/web_server.py](../../../src/web_server.py) (インポートパス更新)
- [x] [.agents/mcp_config.json](../../../.agents/mcp_config.json) (4大サーバーの実行パス更新)
- [x] [Makefile](../../../Makefile) (PYTHON_SRCS および実行ターゲット更新)
- [x] [tests/test_mcp_strategic_ecosystem.py](../../../tests/test_mcp_strategic_ecosystem.py)
- [x] [tests/test_security_hardening.py](../../../tests/test_security_hardening.py)
- [x] [tests/test_search_evaluation.py](../../../tests/test_search_evaluation.py)
- [x] [docs/issues/README.md](../README.md)

---

## 4. 実装成果 / Implementation Results
Target Branch: `refactor/024-consolidate-mcp-package`

1. **`src/mcp/` パッケージの創設**:
   - `base.py`: 共通の JSON-RPC stdio メッセージディスパッチループを共通化し、DRY 原則を確立。
   - `papers_server.py`: 論文検索、GraphRAG、CWE 照合、2段階コンパクト検索。
   - `observability_server.py`: cProfile, tracemalloc, timeit, dis, IR 評価ベンチマーク。
   - `threat_defense_server.py`: Semgrep ルール合成、セキュアパッチ生成、脅威カバレッジ。
   - `tech_radar_server.py`: Adopt/Trial/Assess/Hold 技術レーダー、急上昇脅威予測。
2. **クリーンなリポジトリ構造**:
   - `src/` 直下のノイズを排除し、`src/search/` と `src/mcp/` の 2 大サブシステム構成に統一。
3. **設定・ビルド・テストの完全整合**:
   - `.agents/mcp_config.json`, `Makefile`, `tests/` 内の全参照パスを `src/mcp/*.py` に同期。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] 全 61 ソースファイルの `mypy` 静的型解析 0 エラー
- [x] コアテストスイート全 23 件 100% PASS (0.36s)
- [x] `.agents/mcp_config.json` の動作確認
