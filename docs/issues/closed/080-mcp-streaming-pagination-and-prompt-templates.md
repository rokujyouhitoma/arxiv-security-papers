# [FEAT] 4 大 MCP サーバーの動的ページネーション・ストリーミングおよび学術推論プロンプトテンプレートの高度化 (ID: 080)

| 項目 | 内容 |
| :--- | :--- |
| **ID** | 080 |
| **種別** | Feature |
| **優先度** | High |
| **ステータス** | Closed (Resolved) |
| **起票日** | 2026-08-27 |
| **完了日** | 2026-08-27 |
| **担当ロール** | Systems Architect (SA) / AI Coding Specialist (AI) |
| **対象ブランチ** | `feat/080-mcp-streaming-pagination-and-prompt-templates` |

---

## 1. 概要 / Summary
LLM のコンテキストウィンドウ圧迫を防ぎつつ、大量の検索結果やプロファイルデータを安全に取得できるよう、4 大 MCP サーバー（`papers`, `observability`, `threat-defense`, `tech-radar`）にカーソルベースの動的ページネーション（`offset`, `limit`, `has_more`, `next_cursor`）を標準導入する。また、セキュリティ監査用プロンプトテンプレート（`audit_code_with_papers`, `generate_exploit_poc_tests`）を最新の学術論文知見と連携させ、高精度な PoC テスト生成能力を付与する。

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- `src/mcp/base.py` (共通ページネーション・ストリーミングラッパー)
- `src/mcp/papers_server.py` (検索結果ページネーション & プロンプト強化)
- `src/mcp/observability_server.py` (プロファイル・メモリ追跡のチャンク化)
- `src/mcp/threat_defense_server.py` (ルール/パッチ生成)
- `src/mcp/tech_radar_server.py` (レーダー一覧ページネーション)
- `tests/mcp/test_mcp_server.py` (単体テスト)
- `tests/test_all_mcp_servers.py` (E2E 検証スイート)

---

## 3. 要件定義と脅威モデル / Requirements & Threat Model
- **機能要件**:
  - `search_security_papers`, `search_papers_hybrid`, `get_technology_radar` 等のリスト返却ツールで `limit` (デフォルト 5, 最大 20) および `offset` をサポートし、レスポンスに `pagination: { total, offset, limit, has_more }` メタデータを付与。
  - プロンプト `audit_code_with_papers` において、入力コードスニペットの AST 構文解析と VectorEngine を連動させ、関連論文の Mitigations セクションを動的にインジェクション。
- **セキュリティ・脅威モデル**:
  - `limit` の過大指定による DoS を防止するため、上限ガード（`min(limit, 50)`）を徹底。
  - プロンプト生成時のプロンプトインジェクション防御（ユーザーコード内の特殊トークンエスケープ）。

---

## 4. 実装方針 / Implementation Plan
1. **`src/mcp/base.py`**:
   - 共通ページネーションヘルパー `paginate_results(items, offset, limit)` を実装。
2. **`src/mcp/papers_server.py`**:
   - `handle_search_security_papers`, `handle_search_papers_hybrid` に `offset`, `limit` パラメータを追加。
   - `handle_get_prompt` の `audit_code_with_papers` で関連論文の日本語要約を構造化プロンプトへ注入。
3. **`tests/`**:
   - ページネーション境界値テストおよびプロンプト生成テストを追加。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] 全 4 大 MCP サーバーで `offset`/`limit` ページネーションが動作し、レスポンス文字数が安全閾値（5,000文字以内）に収まること。
- [x] プロンプト `audit_code_with_papers` が関連論文の具体的対策を含む高品質な指示文を生成すること。
- [x] `tests/test_all_mcp_servers.py` および `tests/mcp/` が 100% PASS すること。
- [x] `make check` (mypy strict 0エラー, xenon Grade A/B) をクリアすること。
