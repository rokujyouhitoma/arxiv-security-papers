---
ID: 073
種別: Bug / Architecture Refactor
優先度: High
ステータス: Closed
---

# [BUG] Web と Search Engine のプロセス分離・独立ワーカー化によるメモリ肥大化（15 GB → 1.6 GB）の根絶 (ID: 073)

## 1. 概要 / Summary

`make run_supervisor` 起動直後から、Arbiter および全ワーカープロセス（Web ワーカー、Database ワーカー）が
それぞれ **約 1,372〜1,404 MB の RSS**（物理メモリ使用量）を消費し、クラスタ全体で 15 GB 前後の物理メモリを占有していた。

### 根本原因
従来のモノリシックなワーカーモデルでは、Web ワーカーが `src/search/vector_engine.py`（6.3 GB の index.json、HNSW、FM-Index、共起グラフ等を含む 1.4 GB の重厚な検索エンジン）を各プロセス内で直接ロード・保持していた。
さらに、Arbiter 親プロセスでの import 伝播や、検索を行わない DB ワーカーまでインデックスを抱え込んでいたため、Web ワーカーをスケールするたびに `ワーカー数 × 1.4 GB` のメモリが消費される設計的欠陥が存在していた。

### 解決策: Web / Search / Database の 3層プロセス完全分離
1. **`web` プール (Web Gateway Workers, 2+ プロセス)**:
   - I/O バウンドの HTTP リクエスト受付、ルーティング、HTML/静的配信、CORS 制御に特化。
   - インデックスは保持せず、超軽量（各 ~30 MB）を維持。
   - 検索リクエストは Unix Domain Socket 経由で `search` サービスへ高速 IPC 委譲。
2. **`search` サービス (Dedicated Search Worker, 1 プロセス固定)**:
   - メモリバウンド & CPU バウンドの `VectorEngine` を 1 プロセスのみで集中保持（1.4 GB）。
   - Unix Domain Socket (`outputs/supervisor/search.sock`) でクエリ（ANN検索、RRFハイブリッド、グラフ探索、統計）を受信し高速応答。
3. **`database` サービス (Database Workers, 3 プロセス)**:
   - SQLite 互換ストレージ、ARIES WAL、Raft レプリケーションに特化（各 ~40 MB）。
   - Web や Search のコードは一切ロードしない。

### メモリ消費削減目標
| プロセス種別 | 修正前 (1プロセスあたり) | 修正後 (1プロセスあたり) | プロセス数 | 修正後 合計メモリ |
|---|---|---|---|---|
| **Arbiter (Master)** | 1,382 MB | **~35 MB** | 1 | ~35 MB |
| **`database` サービス** | 1,373 MB | **~40 MB** | 3 | ~120 MB |
| **`web` ワーカー** | 1,404 MB | **~35 MB** | 2 | ~70 MB |
| **`search` サービス** | (Webに同梱) | **~1,400 MB** | 1 | ~1,400 MB |
| **クラスタ合計** | **約 15,200 MB (~15.2 GB)** | **約 1,625 MB (~1.6 GB)** | 7 | **約 1.6 GB (約 90% 削減)** |

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [`src/search/client.py`](../../src/search/client.py) [NEW] / [`src/search/ipc.py`](../../src/search/ipc.py)
  - `SearchClient`: Unix Domain Socket 経由で `SearchServer` と通信する軽量クライアント
  - ソケット非接続時（スタンドアロン起動時）はインプロセス `VectorEngine` へ遅延フォールバック
- [x] [`src/search/server/service.py`](../../src/search/server/service.py) [NEW]
  - `SearchService`: Unix Domain Socket で IPC リクエストを受信し `VectorEngine` を実行・返却
- [x] [`src/supervisor/workers/search_worker.py`](../../src/supervisor/workers/search_worker.py) [NEW]
  - `SearchWorker`: Supervisor 管理下で `SearchService` のライフサイクル（起動・ヘルスチェック・停止）を実行
- [x] [`src/supervisor/contracts.py`](../../src/supervisor/contracts.py)
  - `WorkerLabel.SEARCH = "search"` 追加
- [x] [`src/supervisor/config.py`](../../src/supervisor/config.py)
  - `manage_search: bool = True`, `search_worker_count: int = 1`, `search_socket: str` の追加
- [x] [`src/supervisor/arbiter.py`](../../src/supervisor/arbiter.py)
  - `search_workers` プロセスプールの追加・管理、および起動順序の整理（Phase 1: DB & Search 起動 -> Phase 2: Web 起動）
  - DB/Search ワーカー起動時の不要な `load_wsgi_app()` 排除
- [x] [`src/web/gateway/handlers.py`](../../src/web/gateway/handlers.py) & [`src/web/gateway/__init__.py`](../../src/web/gateway/__init__.py)
  - `GatewayHandlers`: `SearchClient` 経由での検索・統計・論文取得
  - モジュールトップレベルでの `VECTOR_ENGINE` 即時ロードの撤廃
- [x] [`src/supervisor/top.py`](../../src/supervisor/top.py)
  - `search` ワーカーのステータス表示および `PSS / RSS` メトリクス表示
- [x] [`tests/search/test_search_ipc.py`](../../tests/search/test_search_ipc.py) [NEW]
  - Search IPC クライアント/サーバー間通信のテスト
- [x] [`tests/supervisor/test_search_worker.py`](../../tests/supervisor/test_search_worker.py) [NEW]
  - `SearchWorker` ライフサイクル管理のテスト

---

## 3. 完了条件 / Success Criteria (DoD)

- [x] `PYTHONPATH=src python3 -c "import web.server"` 実行後の RSS が 60 MB 以下
- [x] `make run_supervisor` 起動時、`search` サービスが独立起動し、Web ワーカー各プロセスの RSS が 60 MB 以下
- [x] Web ワーカー数を 10 にスケールしても、クラスタ全体のメモリ増加が `10 × 35 MB ≈ 350 MB` に抑制される
- [x] `/api/search`, `/api/paper/<id>`, `/api/trends`, `/api/stats` が `SearchClient` 経由で正常動作（検索結果・プロファイルが完全一致）
- [x] `supervisor.cli top --once` に `web`, `database`, `search` の全ワーカーと PSS/RSS が正常表示される
- [x] `make check` (format + static_analysis + test) が 100% PASS
