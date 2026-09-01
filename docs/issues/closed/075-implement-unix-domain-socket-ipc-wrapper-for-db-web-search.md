---
ID: 075
種別: Feature / Architecture Refactor
優先度: High
ステータス: Closed
---

# [FEAT] Unix Domain Socket による DB・Web・Search の完全プロセス分離と IPC ラッパー基盤の実装 (ID: 075)

## 1. 概要 / Summary

Web ゲートウェイ、Database（LSM/BTree/SQL エンジン）、Search（VectorEngine/FMRaptor）の 3 つの主要サブシステムを、Unix Domain Socket（UDS）による高信頼・低レイテンシな IPC ラッパーを介して明確にプロセス分離・相互通信できるようにする。

同時に、テスト環境や単体起動時（`make run_web`、CLI 実行など）において Web プロセス内に DB や Search を直接組み込んで動作させる「埋め込みモード（Embedded / In-process Fallback）」を完全に維持・保証する。

### 主な要件・目標
1. **Unix Domain Socket IPC ラッパーの統一・提供**:
   - 共通の IPC クライアント/サーバー通信ラッパー（フレーミング、リクエスト/レスポンス、タイムアウト、エラーハンドリング）の整備。
   - `SearchService` / `SearchClient`（`search.sock`）の洗練。
   - `DatabaseService` / `DatabaseClient`（`db.sock`）の新規実装および SQL / ベクトル操作の IPC 化。
2. **Web / DB / Search の明確なプロセス分離**:
   - Web ゲートウェイプロセスは DB や Search の重厚なデータ構造やインデックスを直接起動時ロードせず、IPC 経由でクエリを要求。
   - DB サービス（`DatabaseService` / `DatabaseLifecycleHook`）が `db.sock` をホスト。
   - Search サービス（`SearchService` / `SearchLifecycleHook`）が `search.sock` をホスト。
3. **埋め込みモード（In-Process Fallback）の完全互換維持**:
   - UDS ソケットが存在しない場合（スタンドアロン起動、個別テスト実行時など）、クライアント側が透過的にインプロセス実行へフォールバックし、既存の埋め込み機能を一切損なわない。

---

## 2. トレーサビリティ / Traceability

- 関連 Issue:
  - [Issue 072: Web/DB プール分離管理](closed/072-fix-scale-command-kills-db-worker.md)
  - [Issue 073: Web と Search Engine のプロセス分離](closed/073-fix-worker-rss-memory-bloat-on-startup.md)
  - [Issue 074: アイドル状態継続後のワーカー誤判定・ゾンビプロセス回収不備の根絶](closed/074-fix-idle-worker-death-and-zombie-reaping.md)
  - [Issue 076: Supervisor のドメイン非依存・汎用プロセスエンジン化](closed/076-decouple-domain-workers-from-supervisor-generic-engine.md)
- アーキテクチャ原則:
  - ゼロコピー / 低レイテンシ Unix Domain Socket 通信
  - 障害分離（Fault Isolation）: DB / Search のクラッシュが Web プロセスを巻き込まない
  - Dual-Mode 透過性（Socket IPC モード ⇄ In-Process 埋め込みモードの自動切替）
  - クリーンアーキテクチャ: Supervisor は純粋な汎用プロセスオーケストレータとして機能し、DB/Search サービスは `LifecycleHook` 経由でプラグイン注入される。

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [`src/database/client.py`](../../src/database/client.py) — `DatabaseClient` IPC クライアントおよびインプロセスフォールバックの実装
- [ ] [`src/database/service.py`](../../src/database/service.py) — `DatabaseService` IPC サーバーデーモンおよびライフサイクルフックの実装
- [ ] [`src/search/client.py`](../../src/search/client.py) — `SearchClient` の堅牢化・共通プロトコル対応・インプロセスフォールバック
- [ ] [`src/search/server/service.py`](../../src/search/server/service.py) — `SearchService` の堅牢化およびライフサイクルフックの実装
- [ ] [`src/web/gateway/handlers.py`](../../src/web/gateway/handlers.py) — `DatabaseClient` / `SearchClient` を介した統合ルーティング
- [ ] [`tests/database/test_db_ipc.py`](../../tests/database/test_db_ipc.py) — DB IPC 通信および埋め込みフォールバックの単体テスト
- [ ] [`tests/search/test_search_ipc.py`](../../tests/search/test_search_ipc.py) — Search IPC 通信および埋め込みフォールバックの単体テスト

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/075-uds-ipc-wrapper-db-web-search-separation`

1. **UDS IPC プロトコルとクライアント/サーバー抽象の共通化・標準化**:
   - リクエスト形式: `{"action": "<cmd>", "params": {...}}`
   - レスポンス形式: `{"status": "ok"|"error", "data": ..., "error": ...}`
   - 4バイトビッグエンディアン長プレフィックス付き JSON メッセージフレーミング（または改行デリミタ JSON）による安定通信。
2. **`DatabaseService` & `DatabaseClient` の実装**:
   - `DatabaseService`: `src/database/sqlite_engine.py` や `src/database/engine/` をラップし、`query`, `execute`, `get_stats`, `ping` 等を UDS 経由で提供。
   - `DatabaseClient`: `db.sock` へ接続を試み、接続できない場合はインプロセスで SQLite/LSM エンジンをインスタンス化して直接実行（Dual-Mode）。
   - `DatabaseLifecycleHook`: `src/supervisor/contracts.py` の `LifecycleHook` を実装し、サービスワーカー内で `DatabaseService` をホスト。
3. **`SearchService` & `SearchClient` の強化**:
   - `SearchService` / `SearchClient`: 既存のソケット通信を共通 IPC プロトコルに準拠させ、ソケット非存在時は `VectorEngine` / `FMRaptor` へのインプロセスフォールバックを保証。
   - `SearchLifecycleHook`: `LifecycleHook` を実装し、サービスワーカー内で `SearchService` をホスト。
4. **Web ゲートウェイとの結合**:
   - Web ハンドラから `DatabaseClient` / `SearchClient` を利用し、Web プロセスを DB / Search 実体から完全に分離。
5. **テストと検証**:
   - ソケット通信モードでのクエリ実行テスト
   - ソケット未起動時の埋め込みインプロセスフォールバックテスト
   - 既存の全テスト（Web, Search, Database, Supervisor）との後方互換性検証

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] Web、DB、Search がそれぞれ Unix Domain Socket 経由で独立プロセス間通信できる
- [ ] DB や Search サービスが停止・ソケット不在の場合でも、Web プロセス内で自動的にインプロセス実行にフォールバック（埋め込み動作）できる
- [ ] `DatabaseClient` および `SearchClient` が統一された IPC プロトコル・エラーハンドリングを備えている
- [ ] `tests/database/test_db_ipc.py` および `tests/search/test_search_ipc.py` が新規作成され、PASS する
- [ ] `make check` (format + static_analysis + test) が 100% PASS

