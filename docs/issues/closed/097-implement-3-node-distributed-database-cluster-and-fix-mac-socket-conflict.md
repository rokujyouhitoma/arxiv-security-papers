---
ID: 097
種別: Bug / Feature
優先度: High
ステータス: Closed (Done)
---

# [BUG/FEAT] 3ノード分散データベース同期クラスタ基盤の実装および macOS ソケット競合 ([Errno 17] File exists) の修正 (ID: 097)

## 1. 概要 / Summary
`config/supervisor.json` で `database.workers: 3` を指定して起動した際、3つのワーカープロセスが単一の固定ソケットパス（`outputs/supervisor/db.sock`）に同時に `bind()` を試みることで、macOS（BSD ソケット）環境において **`Failed to start DatabaseService: [Errno 17] File exists`** が発生し、ワーカーが `sys.exit(0)` で即時終了する不具合を修正した。

あわせて、単なるソケット分離にとどまらず、3つのワーカープロセスが **[`src/database/distributed/`](../../src/database/distributed/)（Raft, Quorum レプリケーション $N=3$, Gossip 障害検知, ベクトルクロック）** に基づき、相互にリアルタイム同期を取りながら稼働する **3ノード分散データベースクラスタ（Distributed Database Cluster）** を構築・統合した。

---

## 2. トレーサビリティ & 脅威モデル / Traceability & Threat Model
- **関連資料**:
  - [docs/designs/DSN-05-database_engine_architecture.md](../../designs/DSN-05-database_engine_architecture.md)
  - [docs/designs/DSN-12-process_supervisor_and_arbiter.md](../../designs/DSN-12-process_supervisor_and_arbiter.md)
- **脅威モデル & セキュリティ要件 (Sec / DB / AU 監査)**:
  - **T1: スプリットブレイン（Split-Brain）防止**: Quorum レプリケーション（$W=2, R=2, N=3$）により、過半数の合意が取れない状態での不整合書き込みを防止。
  - **T2: ソケット競合・不正バインド排除**: ワーカーインデックスに基づく決定論的ソケット命名（`db_0.sock`, `db_1.sock`, `db_2.sock`）により、OS レベルのファイル競合を 100% 排除。
  - **T3: ノード間認証 & 不正パケット遮断**: Unix ドメインソケットのパーミッション（0600）管理と内部プロトコル署名検証。

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [src/database/service.py](../../../src/database/service.py): ノード別ソケットパス（`db_<node_id>.sock`）の動的バインドおよび分散クラスタ初期化
- [x] [src/database/client.py](../../../src/database/client.py): 3ノードクラスタ認識、Quorum 読み書き、自動フェイルオーバー
- [x] [src/supervisor/workers/service_worker.py](../../../src/supervisor/workers/service_worker.py): ワーカーインデックスの伝達とフック初期化
- [x] [src/supervisor/contracts.py](../../../src/supervisor/contracts.py): `LifecycleHook.bind_worker()` インターフェース追加
- [x] [tests/database/distributed/test_cluster_service.py](../../../tests/database/distributed/test_cluster_service.py): 3ノード分散同期クラスタの統合テスト
- [x] [config/supervisor.json](../../../config/supervisor.json): `database.workers: 3` 構成の完全稼働

---

## 4. 実装方針 / Implementation Plan
Target Branch: `fix/097-3-node-distributed-db-and-mac-socket-conflict`

### Step 1: Supervisor サービスワーカーへのワーカーインデックス・ノードID伝達
1. `src/supervisor/contracts.py`: `LifecycleHook` に `bind_worker(worker_id: str)` を追加。
2. `src/supervisor/workers/service_worker.py`: `ManagedServiceWorker` は `setup()` 前に `self.hook.bind_worker(self.worker_id)` を呼び出す。

### Step 2: `DatabaseService` & `DatabaseLifecycleHook` の動的ノード別ソケットバインド
1. `src/database/service.py`:
   - `DatabaseLifecycleHook` は与えられた `worker_id`（例: `database_1`）から `node_id`（`1`）を抽出し、`outputs/supervisor/db_1.sock` を対象とする `DatabaseService` を生成・起動。
   - `node_id == 0`（プライマリ）の場合は `outputs/supervisor/db.sock` へのシンボリックリンクを提供し、既存クライアントとの完全後方互換性を保証。
   - ソケット作成前に不要な古い残存ファイルを安全に unlink。

### Step 3: 分散同期メッシュ（Quorum / Gossip）の統合
1. `src/database/service.py`:
   - 3ノード（`db_0.sock`, `db_1.sock`, `db_2.sock`）のクラスタイニシャライザとプロトコル連携。

### Step 4: `DatabaseClient` のクラスタ認識 & フェイルオーバー
1. `src/database/client.py`:
   - クラスタ内の利用可能な候補ソケット（`db_0.sock`, `db_1.sock`, `db_2.sock`）を検出し、プライマリダウン時の自動フェイルオーバーをサポート。

### Step 5: テスト & 品質ゲート検証
1. `tests/database/distributed/test_cluster_service.py` を新規作成し、3 ノード同時起動、ソケット競合 0 件、データレプリケーションを検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `config/supervisor.json`（`database.workers: 3`）で起動した際、macOS / Linux 環境で `[Errno 17] File exists` が発生せず 3 ワーカーがすべて `ALIVE / HEALTHY` で常駐すること。
- [x] `outputs/supervisor/` 配下に `db_0.sock`, `db_1.sock`, `db_2.sock` が独立して生成され、3 プロセスが並列稼働すること。
- [x] 3 ノード間で Quorum レプリケーションおよびデータ同期プロトコルが正常に機能すること。
- [x] `pytest tests/database/` および `pytest tests/supervisor/` が 100% PASS すること。
