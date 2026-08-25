---
ID: 076
種別: Feature / Architecture Refactor
優先度: High
ステータス: Closed
---

# [FEAT] Supervisor のドメイン非依存・汎用プロセスエンジン化と宣言的 Worker/Service 抽象化 (ID: 076)

## 1. 概要 / Summary

現在の `src/supervisor/`（Arbiter, Config, Workers）には、`web`, `search`, `database` といった特定のアプリケーションコンポーネントに特化した具象実装や分岐ロジック（`db_workers`, `search_workers`, `spawn_worker("search")`, `manage_db`, `manage_search` 等）がハードコードされている。

スーパーバイザー（プロセス調停基盤）の本来の責務は、任意のワーカースペック（Pre-fork Web ワーカー、バックグラウンド常駐サービス、IPC ソケットデーモンなど）を汎用的に管理・監視・スケール・再起動・ローリング更新する「ドメイン非依存のプロセススーパーバイザー基盤」であるべきである。

Web / DB / Search などの具象構成要素やサービス定義は、アプリケーションオーケストレーション層（`src/orchestrator/` やアプリケーションアセンブリ）で宣言的に定義・注入できるように責務を分離する。

---

## 2. トレーサビリティと設計原則 / Traceability & Architecture Principles

- **関連 Issue**:
  - [Issue 069: Gunicorn スタイル Pre-fork プロセススーパーバイザーの実装](closed/069-implement-gunicorn-style-process-supervisor-and-arbiter.md)
  - [Issue 072: Web/DB プール分離管理](closed/072-fix-scale-command-kills-db-worker.md)
  - [Issue 073: Web と Search Engine のプロセス分離](closed/073-fix-worker-rss-memory-bloat-on-startup.md)
  - [Issue 074: アイドル状態継続後のワーカー誤判定・ゾンビプロセス回収不備の根絶](closed/074-fix-idle-worker-death-and-zombie-reaping.md)
  - [Issue 075: Unix Domain Socket IPC ラッパー基盤の実装](075-implement-unix-domain-socket-ipc-wrapper-for-db-web-search.md)
- **SOLID / クリーンアーキテクチャ原則**:
  - **単一責任の原則 (SRP)**: Supervisor はプロセス管理（Pre-fork, Watchdog, Signal, Scaling）のみを担当し、特定ドメインの業務知識を持たない。
  - **開放閉鎖の原則 (OCP)**: 新たなワーカー（例: `spider`, `mcp`, `worker_queue` 等）を追加する際、Supervisor 本体のコード変更が一切不要。
  - **依存性逆転の原則 (DIP)**: `Arbiter` は具象クラス（`DatabaseWorker`, `SearchWorker`）に直接依存せず、`WorkerSpec` / `LifecycleHook` 抽象プロトコルに依存する。

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [`src/supervisor/contracts.py`](../../src/supervisor/contracts.py)
  - `WorkerSpec` / `ServiceSpec` / `WorkerFactory` 宣言的契約の定義
- [ ] [`src/supervisor/config.py`](../../src/supervisor/config.py)
  - 具象フィールド（`manage_db`, `manage_search` 等）の非推奨・汎用 `pools` / `services` への移行
- [ ] [`src/supervisor/arbiter.py`](../../src/supervisor/arbiter.py)
  - `web_workers` / `db_workers` / `search_workers` の個別辞書を汎用 `pools: Dict[str, ManagedPool]` に一元化
  - `spawn_worker()`, `adjust_pool()`, `scale()`, `reload()`, `check_hung_workers()` の完全ドメイン非依存化
- [ ] [`src/supervisor/workers/`](../../src/supervisor/workers/)
  - `ManagedServiceWorker`, `SyncWorker`, `GthreadWorker`, `AsyncWorker` を汎用コアワーカーとして洗練
  - 具象ワーカーの切り出しまたはファクトリ化
- [ ] [`src/supervisor/cli.py`](../../src/supervisor/cli.py) & [`src/supervisor/top.py`](../../src/supervisor/top.py)
  - 登録された任意のサービスプール（動的なサービス名）を柔軟に一覧・操作可能に改善
- [ ] [`tests/supervisor/`](../../tests/supervisor/)
  - 汎用スーパーバイザーとしての網羅的単体テスト（カスタムサービス定義、動的プールスケール、ライフサイクル）の拡充

---

## 4. 根本原因分析とリファクタリング設計 / RCA & Refactoring Architecture

### 課題の構造
```
【現状の結合度 (Tight Coupling)】
 Supervisor (Arbiter)
    ├── import DatabaseWorker ---> src/database/ (具象依存)
    ├── import SearchWorker   ---> src/search/   (具象依存)
    ├── if worker_type == "db": ...
    ├── elif worker_type == "search": ...
    └── config.manage_search, config.db_worker_count ... (具象設定が混入)

【目指す分離アーキテクチャ (Clean Architecture)】
 ┌──────────────────────────────────────────────────────────┐
 │ Application / Orchestrator Layer (src/orchestrator/)     │
 │  - Defines Web WorkerSpec (HTTP Sync/Async)              │
 │  - Defines Search ServiceSpec (UDS Hook / SearchService) │
 │  - Defines Database ServiceSpec (UDS Hook / DBService)   │
 └────────────────────────────┬─────────────────────────────┘
                              │ registers WorkerSpec[]
                              ▼
 ┌──────────────────────────────────────────────────────────┐
 │ Generic Process Supervisor Engine (src/supervisor/)      │
 │  - Arbiter (Generic Process Arbiter & Signal Router)     │
 │  - Watchdog & Health Monitoring                          │
 │  - Generic Pools: Dict[str, ManagedPool]                 │
 │  - Worker Types: Sync, Gthread, Async, ManagedService    │
 └──────────────────────────────────────────────────────────┘
```

---

## 5. 詳細実装計画 / Implementation Plan

Target Branch: `feat/076-generic-supervisor-decouple-domain-workers`

### Step 1: 宣言的ワーカースペック契約の設計 (`src/supervisor/contracts.py`)
- `WorkerSpec` クラスの定義:
  ```python
  @dataclasses.dataclass
  class WorkerSpec:
      name: str
      worker_class: Type[BaseWorker] = SyncWorker
      target_count: int = 1
      app_target: Optional[Callable[..., Any]] = None
      hook: Optional[LifecycleHook] = None
      server_socket: Optional[socket.socket] = None
      role: ServiceRole = ServiceRole.STATELESS_POOL
      sync_interval: float = 2.0
      metadata: Dict[str, Any] = dataclasses.field(default_factory=dict)
  ```

### Step 2: 汎用プロセスプール管理の実装 (`src/supervisor/arbiter.py`)
- `ManagedPool` 構造体の導入:
  - `name: str`
  - `spec: WorkerSpec`
  - `workers: Dict[int, BaseWorker]`
  - `target_count: int`
- `Arbiter` のリファクタリング:
  - `self.pools: Dict[str, ManagedPool]` で一元管理。
  - `spawn_worker(service_name: str)`: 該当プールの `spec` に基づいてプロセスを fork しワーカーを起動。
  - `adjust_pool(service_name: str, target: Optional[int] = None)`: 任意のサービスを増減。
  - `scale(service_name: str, count: int)`: 汎用スケールコマンド。
  - `reload(service_name: Optional[str] = None)`: 汎用ローリングリロード。
  - `check_hung_workers()`: 全プールを走査し、ハングプロセスを安全に再起動。

### Step 3: SupervisorConfig の汎用化 (`src/supervisor/config.py`)
- `pools` / `services` から動的に `WorkerSpec` を生成するファクトリメソッドを提供。
- 既存の `workers`, `db_worker_count`, `search_worker_count` は後方互換のためのプロパティとして維持しつつ、内部的には汎用スペックリストへマッピング。

### Step 4: CLI および Top モニターの動的サービス対応 (`src/supervisor/top.py`)
- ハードコードされた `database`, `search` カラム/表示を、`workers` の `type` / サービスプール情報から動的に集計・レンダリングする構造へ刷新。

### Step 5: テストスイートの拡充と検証
- 具象ドメインに依存しない汎用カスタムサービス（例: `custom_worker`, `queue_worker`）を定義して Supervisor が正常に起動・スケール・死活監視できることをテスト。
- 既存のすべてのテスト（`test_arbiter.py`, `test_top.py`, `test_workers.py`）が PASS することを確認。

---

## 6. 完了条件 / Success Criteria (DoD)

- [ ] `src/supervisor/arbiter.py` から `db_workers`, `search_workers` のハードコードおよび具象ドメイン分岐（`if worker_type == "db"` 等）が完全に排除されている
- [ ] `Arbiter` が任意の `WorkerSpec` リストを受け取り、複数サービスプールを動的に管理・スケールできる
- [ ] `supervisor.cli scale <service> <n>` で任意のサービスプールをスケールできる
- [ ] `supervisor.cli top` が任意の登録サービス名を動的にモニタリング・表示できる
- [ ] `make check` (format + static_analysis + test) が 100% PASS
- [ ] `tests/supervisor/` に汎用 WorkerSpec / ManagedPool の単体テストが追加され、全テストが PASS

