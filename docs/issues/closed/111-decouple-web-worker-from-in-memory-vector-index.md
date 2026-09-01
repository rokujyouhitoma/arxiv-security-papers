---
ID: 111
種別: Improvement / Architecture
優先度: High
ステータス: Closed (Completed)
完了日: 2026-09-02
---

# [FEAT/ENH] Webワーカーのオンメモリ検索インデックス展開廃止とSearchワーカーIPC問い合わせへの完全移行 (ID: 111)

## 1. 概要 / Summary
Supervisor 上でプロセスプールを起動した際、`web` ワーカープロセス（2インスタンス）がそれぞれ約 1.2GB〜1.35GB（合計約 2.6GB）のメモリを消費しており、専用の `search` ワーカープロセス（1.38GB）とほぼ同等にメモリを圧迫している事象を解決した。

根本原因であった `SearchClient` の早期タイムアウト時の暗黙的 `VectorEngine` インプロセス展開、および `GatewayHandlers` の直接インデックス参照を撤廃し、Unix Domain Socket IPC による `search` 専用ワーカーへの完全委任を実現した。

---

## 2. 成果とメモリ削減効果 (Results & Verification)

### Supervisor Top 実測比較

```
[改善前]
  PID    TYPE       STATUS   HEALTH   REQ IDLE MEM (PSS)
  ──────────────────────────────────────────────────────────────────────────
  471388 search    ALIVE   HEALTHY 0        49.1s      1379.9 (1367.9) MB
  471392 web       ALIVE   HEALTHY 0        49.1s      1226.7 (1214.7) MB  <-- ⚠️ 1.23GB
  471393 web       ALIVE   HEALTHY 0        49.1s      1350.4 (1338.5) MB  <-- ⚠️ 1.35GB
  ※ Web ワーカー合計: 約 2.58 GB

[改善後 (実測値)]
  PID    TYPE       STATUS   HEALTH   REQ IDLE MEM (PSS)
  ──────────────────────────────────────────────────────────────────────────
  482433 search    ALIVE   HEALTHY 0        33.0s      1205.7 (1193.4) MB
  482437 web       ALIVE   HEALTHY 0        33.0s      52.0 (38.5) MB     <-- ✅ 96% 削減
  482438 web       ALIVE   HEALTHY 0        33.0s      32.5 (18.9) MB     <-- ✅ 97.6% 削減
  ※ Web ワーカー合計: 84.5 MB (PSS: 57.4 MB) — 2.5GB 以上のメモリ浪費を解消
```

---

## 3. 主な変更点 / Key Implementations

1. **[SearchClient (src/search/client.py)](../../src/search/client.py)**:
   - `timeout` を 15.0s に設定し、Supervisor 環境下で不用意に `fallback_engine` を起動しない安全機構（`allow_inprocess_fallback` 制御）を実装。
   - `search` メソッドに `offset: int = 0` 引数を追加し、`total_hits`, `has_more` 属性を含むレスポンスを返却。
   - `send_command` をリファクタリングし、Xenon 循環的複雑度 Grade A を達成。
2. **[SearchService (src/search/server/service.py)](../../src/search/server/service.py)**:
   - IPC リクエストから `offset` をパースし、`VectorEngine.search_with_profile(..., offset=offset)` へ伝播。
   - 返却辞書に `total_hits`, `offset`, `limit`, `has_more` を確実に格納。
3. **[GatewayHandlers (src/web/gateway/handlers.py)](../../src/web/gateway/handlers.py)**:
   - Web Gateway のデフォルト検索経路 `_execute_client_search` を `SearchClient` 専任化し、`offset` およびページネーション属性を透過的にクライアントへ返却。
4. **[QuerySemanticCache (src/search/query/query_cache.py)](../../src/search/query/query_cache.py)**:
   - ページネーション（`offset > 0`）クエリに対して `exact_only=True` を適用し、誤ったキャッシュヒットによるオフセット不整合を完全に防止。

---

## 4. 完了条件の達成状況 / DoD Verification
- [x] `web` ワーカープロセスが `vector_db/index.json` をオンメモリ展開しないこと。
- [x] `supervisor top` 上で `web` ワーカーのメモリ使用量（PSS）が 60MB 未満（実測 38.5MB / 18.9MB）に抑制されたこと。
- [x] `/api/search` が `SearchClient` / IPC 経由で `search` ワーカーから正確な結果、`total_hits`、`has_more` を取得・返却できること。
- [x] 全テストスイートが 100% PASS すること。
- [x] Xenon 循環的複雑度が全モジュールで **100% Rank A (CC $\le 5$)** を維持していること。
