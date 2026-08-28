---
ID: 097
種別: Bug / Feature
優先度: High
ステータス: Open (New)
---

# [BUG/FEAT] 3ノード分散データベース同期クラスタ基盤の実装および macOS ソケット競合 ([Errno 17] File exists) の修正 (ID: 097)

## 1. 概要 / Summary
`config/supervisor.json` で `database.workers: 3` を指定して起動した際、3つのワーカープロセスが単一の固定ソケットパス（`outputs/supervisor/db.sock`）に同時に `bind()` を試みることで、macOS（BSD ソケット）環境において **`Failed to start DatabaseService: [Errno 17] File exists`** が発生し、ワーカーが `sys.exit(0)` で即時終了する不具合を修正する。

あわせて、単なるソケット分離にとどまらず、3つのワーカープロセスが **[src/database/distributed/](file:///workspace/arxiv-security-papers/src/database/distributed/)（Raft, Quorum レプリケーション $N=3$, Gossip 障害検知, ベクトルクロック）** に基づき、相互にリアルタイム同期を取りながら稼働する **3ノード分散データベースクラスタ（Distributed Database Cluster）** を構築・統合する。

---

## 2. トレーサビリティ & 脅威モデル / Traceability & Threat Model
- **関連資料**:
  - [docs/designs/DSN-05-database_engine_architecture.md](../designs/DSN-05-database_engine_architecture.md)
  - [docs/designs/DSN-12-process_supervisor_and_arbiter.md](../designs/DSN-12-process_supervisor_and_arbiter.md)
- **脅威モデル & セキュリティ要件 (Sec / DB / AU 監査)**:
  - **T1: スプリットブレイン（Split-Brain）防止**: Quorum レプリケーション（$W=2, R=2, N=3$）により、過半数の合意が取れない状態での不整合書き込みを防止。
  - **T2: ソケット競合・不正バインド排除**: ワーカーインデックスに基づく決定論的ソケット命名（`db_0.sock`, `db_1.sock`, `db_2.sock`）により、OS レベルのファイル競合を 100% 排除。
  - **T3: ノード間認証 & 不正パケット遮断**: Unix ドメインソケットのパーミッション（0600）管理と内部プロトコル署名検証。

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [src/database/service.py](../../src/database/service.py): ノード別ソケットパス（`db_<node_id>.sock`）の動的バインドおよび分散クラスタ初期化
- [ ] [src/database/client.py](../../src/database/client.py): 3ノードクラスタ認識、Quorum 読み書き、自動フェイルオーバー
- [ ] [src/supervisor/workers/service_worker.py](../../src/supervisor/workers/service_worker.py): ワーカーインデックスの伝達
- [ ] [src/supervisor/arbiter.py](../../src/supervisor/arbiter.py): サービスワーカー起動時のノード識別子付与
- [ ] [tests/database/distributed/test_cluster_service.py](../../tests/database/distributed/test_cluster_service.py) [NEW]: 3ノード分散同期クラスタの統合テスト
- [ ] [tests/supervisor/test_service_worker.py](../../tests/supervisor/test_service_worker.py): 複数サービスワーカーの並列起動検証

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/097-implement-3-node-distributed-database-cluster`

1. **ノード別ソケット割り当てと macOS ソケット競合根絶**:
   - `DatabaseService` の初期化時に `node_id`（`0`, `1`, `2`）を受け取り、`outputs/supervisor/db_{node_id}.sock` にバインド。
   - `node_id == 0` はプライマリとして `outputs/supervisor/db.sock` へシンボリックリンクまたはエイリアスを提供。
2. **3ノード分散同期メッシュの統合**:
   - `DatabaseLifecycleHook` 内で、`src/database/distributed/quorum.py`（クオラム $N=3$）および `gossip.py` のクラスタノードを起動。
   - ノード間での書き込みレプリケーションとベクトルクロック同期を自動実行。
3. **`DatabaseClient` のマルチノード対応**:
   - クライアントが 3 つのノードソケットを保持し、Quorum 読み取り（$R=2$）およびプライマリへの書き込み（$W=2$）を実行。
4. **テスト & 品質ゲート検証**:
   - `pytest tests/database/`, `pytest tests/supervisor/`, `make check` を全パス。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `database.workers: 3` 構成で Supervisor を起動した際、macOS / Linux 環境で `[Errno 17] File exists` が発生せず 3 ワーカーがすべて `ALIVE / HEALTHY` で常駐すること。
- [ ] 3つのワーカー（`db_0.sock`, `db_1.sock`, `db_2.sock`）がそれぞれ独立プロセスとして起動し、分散同期プロトコルが稼働すること。
- [ ] `DatabaseClient` 経由で 3 ノードに対するクエリ・書き込みが正常に分散同期されること。
- [ ] `make check` / `make verify_quality` が 100% PASS すること。
