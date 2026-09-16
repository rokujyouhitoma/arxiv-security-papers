---
ID: 307
種別: Feature
優先度: High
ステータス: Open (In Progress)
---

# [FEAT] PEG ファサード LRU キャッシュ可観測性統合 (Observability MCP) および文法境界値 ReDoS ファジングテスト基盤の実装 (ID: 307)

## 1. 概要 / Summary
DSN-25 仕様に基づき本番稼働する全 PEG パーサーファサード（SQL および検索クエリ）の LRU キャッシュ状態（Hits, Misses, MaxSize, CurrSize, Hit Rate）を、Model Context Protocol (MCP) の可観測性サーバー (`src/mcp/observability_server.py`) から動的に取得・監視できるメトリクスツール `get_parser_cache_metrics` を実装する。
併せて、極度の括弧ネスト（1,000 段超）、巨大入力境界値（65,536 文字制限）、およびランダムトークン列に対する ReDoS / DoS 耐性を継続検証する自動ファジングテストスイートを構築する。

---

## 2. トレーサビリティ / Traceability
- 関連設計書: [`DSN-25`](../designs/DSN-25-pure_python_packrat_peg_parser_engine.md), [`DSN-12`](../designs/DSN-12-mcp_server_architecture.md)
- 関連 Issue: [#303](closed/303-optimize-packrat-peg-parser-engine.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [`src/mcp/observability_server.py`](../../src/mcp/observability_server.py)
- [ ] [`tests/mcp/test_observability_mcp_server.py`](../../tests/mcp/test_observability_mcp_server.py)
- [ ] [`tests/core/test_peg_fuzzing.py`](../../tests/core/test_peg_fuzzing.py)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/307-peg-observability-and-fuzzing`

1. **LRU キャッシュ可観測性 MCP ツール (`src/mcp/observability_server.py`)**:
   - `get_parser_cache_metrics` ツールを登録。
   - `parse_sql`, `parse_sql_expr`, `parse_dql`, `parse_dml`, `parse_ddl`, `_cached_aot_search_parse` の `cache_info()` を安全に取得・集計。
   - 各パーサーの hits, misses, maxsize, currsize, hit_rate_pct を含む構造化メトリクス辞書を返却。
2. **ReDoS / 境界値ファジングテストスイート (`tests/core/test_peg_fuzzing.py`)**:
   - 1,000 段の括弧ネストに対するスタック安全停止テスト（`PEGSyntaxError` による安全遮断）。
   - 70,000 文字の巨大入力に対する DoS ガード検証（`ValueError` 即時送出）。
   - ランダム文字列生成器による ReDoS 耐性検証（線形時間 $O(N)$ 完了の定量的検証）。
3. **MCP サーバー統合テストの追加 (`tests/mcp/test_observability_mcp_server.py`)**:
   - `get_parser_cache_metrics` ツールのレスポンス構造と集計値の単体テスト。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `src/mcp/observability_server.py` に `get_parser_cache_metrics` ツールが追加され、全パーサーのキャッシュ状態を取得できること。
- [x] `tests/mcp/test_observability_mcp_server.py` でメトリクスツールの動作が検証されていること。
- [x] `tests/core/test_peg_fuzzing.py` が作成され、1,000段ネストやReDoS攻撃文字列が安全に処理されること。
- [x] 循環的複雑度 $CC \le 4$ (Xenon Grade A) および型安全性が 100% PASS すること。
