---
ID: 076
種別: Feature / Architecture Refactor
優先度: High
ステータス: Open (New)
---

# [FEAT] Supervisor のドメイン非依存・汎用プロセスエンジン化と宣言的 Worker/Service 抽象化 (ID: 076)

## 1. 概要 / Summary

現在の `src/supervisor/`（Arbiter, Config, Workers）には、`web`, `search`, `database` といった特定のアプリケーションコンポーネントに特化した具象実装や分岐ロジック（`db_workers`, `search_workers`, `spawn_worker("search")`, `manage_db`, `manage_search` 等）がハードコードされている。

スーパーバイザー（プロセス調停基盤）の本来の責務は、任意のワーカースペック（Pre-fork Web ワーカー、バックグラウンド常駐サービス、IPC ソケットデーモンなど）を汎用的に管理・監視・スケール・再起動・ローリング更新する「ドメイン非依存のプロセススーパーバイザー基盤」であるべきである。

Web / DB / Search などの具象構成要素やサービス定義は、アプリケーションオーケストレーション層（`src/orchestrator/` やアプリケーションアセンブリ）で宣言的に定義・注入できるように責務を分離する。

### 主な課題と改善目標
1. **Arbiter のドメイン具象分岐の排除**:
   - `Arbiter` から `web_workers`, `db_workers`, `search_workers` のハードコードを撤廃し、汎用的な `ServicePool` / `WorkerPool`（`dict[str, WorkerPool]`）管理へ移行。
2. **宣言的 `WorkerSpec` / `ServiceSpec` 契約の導入**:
   - ワーカーの起動方式（Pre-fork HTTP, UDS サービス, バックグラウンドタスク）、プール数、再起動ポリシー、ライフサイクルフックなどを宣言的に定義可能なインターフェースを導入。
3. **Supervisor Config の汎用化**:
   - `SupervisorConfig` から `manage_search`, `manage_db` 等の具象フィールドを排除し、`services: dict[str, ServiceSpec]` またはプラグイン可能なワーカーレジストリで管理。
4. **具象ワーカーの適切な配置とオーケストレーション**:
   - `SearchWorker` / `DatabaseWorker` 等の具象実装は各ドメインパッケージ（`src/search/`、`src/database/`、`src/orchestrator/`）または拡張アダプタへ配置し、オーケストレーター側から Supervisor に登録・アセンブルする。

---

## 2. トレーサビリティ / Traceability

- 関連 Issue:
  - [Issue 069: Gunicorn スタイル Pre-fork プロセススーパーバイザーの実装](closed/069-implement-gunicorn-style-process-supervisor-and-arbiter.md)
  - [Issue 072: Web/DB プール分離管理](closed/072-fix-scale-command-kills-db-worker.md)
  - [Issue 073: Web と Search Engine のプロセス分離](closed/073-fix-worker-rss-memory-bloat-on-startup.md)
  - [Issue 075: Unix Domain Socket IPC ラッパー基盤の実装](075-implement-unix-domain-socket-ipc-wrapper-for-db-web-search.md)
- 設計原則:
  - 単一責任の原則 (SRP): Supervisor は汎用プロセス管理のみを担当
  - 開放閉鎖の原則 (OCP): 新しいサービス（Spider, MCP Server等）を追加する際に Supervisor 本体のコード変更が不要
  - 依存性逆転の原則 (DIP): Supervisor は具象ではなく `WorkerSpec` / `LifecycleHook` 抽象に依存

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [`src/supervisor/arbiter.py`](../../src/supervisor/arbiter.py) — 具象分岐（`db`/`search`/`web`）を汎用プール管理（`ServicePool`）へリファクタリング
- [ ] [`src/supervisor/config.py`](../../src/supervisor/config.py) — 宣言的サービス設定（`services` / `worker_pools`）への汎用化
- [ ] [`src/supervisor/contracts.py`](../../src/supervisor/contracts.py) — `WorkerSpec`, `ServiceSpec`, `WorkerFactory` 等の抽象プロトコル定義
- [ ] [`src/supervisor/workers/`](../../src/supervisor/workers/) — 汎用ワーカーベース（`SyncWorker`, `GthreadWorker`, `AsyncWorker`, `ManagedServiceWorker`）のみを保持
- [ ] [`src/orchestrator/`](../../src/orchestrator/) / アプリケーション層 — Web, Search, DB の具象サービス構成および Supervisor への登録・アセンブリ
- [ ] [`src/supervisor/cli.py`](../../src/supervisor/cli.py) & [`src/supervisor/top.py`](../../src/supervisor/top.py) — 動的なサービス名表示対応
- [ ] [`tests/supervisor/`](../../tests/supervisor/) — 汎用プロセスマネージャーとしての単体テスト刷新

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/076-generic-supervisor-decouple-domain-workers`

1. **抽象インターフェースの設計 (`src/supervisor/contracts.py`)**:
   - `WorkerSpec`: サービス名、ワーカークラス/ファクトリ、ターゲット Callable、初期プロセス数、UDS/TCP ソケット要件、ライフサイクルフック等をカプセル化。
2. **`Arbiter` の汎用化 (`src/supervisor/arbiter.py`)**:
   - `self.pools: Dict[str, WorkerPool]` による統一プール管理。
   - `scale(service_name, count)`、`reload(service_name=None)`、`spawn(service_name)` を完全に一般化。
   - 具象ドメイン名への依存（`if type == "db"` や `if self.config.manage_search`）を完全に削除。
3. **アプリケーションオーケストレーションへの具象アセンブリ移譲**:
   - `arxiv-security-papers` 全体としての実行構成（Web Gateway + Search Engine + Database Daemon）をオーケストレーターまたはアプリ設定から定義し、`Arbiter` に `WorkerSpec` のリストとして引き渡す。
4. **既存テストおよび CLI/Top との後方互換性担保**:
   - 任意のサービス名（`web`, `db`, `search`, `spider`, `mcp` 等）を `top` コマンドや `scale` コマンドで動的に表示・操作可能にする。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `src/supervisor/` 内のコードから `search`, `db`, `sqlite` 等の具象ドメイン固有ロジックや分岐が完全に排除されている
- [ ] Supervisor が任意の `WorkerSpec` を受け取り、複数プロセスプールを独立してスケール・再起動・死活監視できる
- [ ] Web / Search / DB の具象サービス定義がオーケストレーション層または設定から宣言的に注入される
- [ ] `supervisor.cli` および `top` が任意の登録サービス名を動的にモニタリング・操作できる
- [ ] `make check` (format + static_analysis + test) が 100% PASS
