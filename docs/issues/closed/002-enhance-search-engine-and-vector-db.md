---
ID: 002
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT] セキュリティ同義語拡張・マルチフィールドハイブリッドスコアリング・段落チャンク化による検索エンジンおよび VectorDB の高度化 (ID: 002)

## 1. 概要 / Summary
`registered-information-security-specialist-examination` の高品質な検索モジュール設計（同義語シノニム拡張、マルチフィールドスコアリング、意味段落チャンク化）を参考に、`arxiv-security-papers` の `VectorEngine` および `MCPServer` を刷新し、日本語・英語を跨ぐセキュリティ検索精度と適合率を向上させます。

---

## 2. トレーサビリティ / Traceability
- **参考リポジトリ**: `registered-information-security-specialist-examination` (`tokenizer.js`, `synonym_expander.js`, `semantic_scorer.js`)
- **仕様書**: `docs/mcp/MCP-01-mcp_server_specification.md`, `docs/requirements/REQ-01-system_requirements.md`
- **設計書**: `docs/designs/DSN-01-high_level_design.md`, `docs/designs/DSN-02-low_level_design.md`

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [`src/synonym_expander.py`](../../src/synonym_expander.py): セキュリティ専門用語・日英同義語展開辞書
- [x] [`src/vector_engine.py`](../../src/vector_engine.py): 同義語拡張＋段落チャンク化＋マルチフィールド重み付きハイブリッド検索エンジン
- [x] [`src/mcp_server.py`](../../src/mcp_server.py): MCP サーバの拡張検索ハンドラ
- [x] [`tests/test_vector_engine.py`](../../tests/test_vector_engine.py): 新検索エンジン・シノニム展開の単体テスト
- [x] [`Makefile`](../../Makefile): `build_vector_db`, `rag_query`, `py_compile` ターゲット更新

---

## 4. 実装方針 / Implementation Plan (ST / SA / IR 指導)
Target Branch: `feat/002-enhance-search-engine-and-vector-db`

1. **`src/synonym_expander.py` の新規開発**:
   - `ペンテスト` ⇄ `ペネトレーションテスト` ⇄ `penetration testing` ⇄ `exploit` などのセキュリティ専門用語シノニム辞書の定義。
   - クエリ文字列に対する自動双方向トークン拡張ロジックの実装。
2. **`src/vector_engine.py` の高度化**:
   - 論文全体のテキストを意味セクション（Abstract, Intro, Threat Model 等）に段落チャンク分割。
   - スコアリング計算の多重化: Title(3.0), Tags(2.5), Description(2.0), Abstract(1.5), Body(1.0) のフィールド重み付けと時間経過減衰（Recency Decay）の統合。
3. **`src/mcp_server.py` およびテストの対応**:
   - MCP ツール `search_security_papers` および `query_attack_technique` に拡張検索エンジンを適用。
   - `tests/test_vector_engine.py` を追加し `make test` で全緑化。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `src/synonym_expander.py` が「ペンテスト」「自動運転」「暗号」等の用語を適切に日英相互拡張すること。
- [x] `make build_vector_db` により段落チャンク付きインデックスが正常作成されること。
- [x] `make rag_query Q="ペンテスト自動化"` で高精度なスコアリング結果が返却されること。
- [x] `make py_compile` および `make test` が 100% PASS すること。
