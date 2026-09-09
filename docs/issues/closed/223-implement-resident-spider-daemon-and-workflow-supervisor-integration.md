---
ID: 223
種別: Feature / Architecture
優先度: High
ステータス: Closed
完了日: 2026-09-09
担当エージェント: Systems Architect / Network Specialist / Software Development / IT Service Manager
---

# [FEAT/ARCH] src/spider の常駐型デーモン化および src/workflow・src/supervisor 統合アーキテクチャの実装 (ID: 223)

## 1. 概要 / Summary

現在、`src/spider/` クローラー基盤は、CLI やバッチから呼び出されるたびにプロセスが起動し、フェッチ完了後に破棄される「一回限り実行（One-shot CLI/Script）」の動作モデルとなっている。
しかし、大規模かつ継続的なセキュリティ論文・脅威インテリジェンス収集（arXiv, IACR, CISA KEV, NVD CVE, MITRE CWE 等）においては、以下の課題が顕在化している：

1. **接続オーバーヘッド**: 起動ごとの TCP 3-way ハンドシェイクおよび TLS ネゴシエーション。
2. **Politeness（礼儀正しさ）状態・キャッシュの喪失**: プロセス終了に伴い、ドメインごとの最終アクセス時刻や連続 429 バックオフ係数、ETag / If-Modified-Since テーブルがメモリから失われ、再起動時にリセットされる。
3. **イベント駆動の即時性欠如**: Web コンソールからのオンデマンド即時更新や外部アラート検知に対して、コールドスタート遅延が発生する。

本 Issue では、`src/spider` を常駐型アプリケーション（`SpiderWorker` / `SpiderDaemon`）へと刷新し、`src/workflow`（汎用ワークフロー基盤）および `src/supervisor`（プロセス調停基盤）、さらに DSN-23 の `src/core/hsm`（階層型ステートマシン）と以下の 4 大設計方針に基づいて統合する。

### 4 大統合方針
1. **制御プレーンと実行プレーンの明確な分離**:
   - **Control Plane（制御プレーン）: `src/workflow` (`WorkflowScheduler`)**: 「いつ・何を・どの順序で実行するか（What & When）」を一元統制（Cron/Interval、全体 DAG、障害時の Circuit/Saga/WAL）。
   - **Execution Plane（実行プレーン）: `src/spider` (`SpiderWorker`)**: 「外部通信をどう安全・確実に実行するか（How）」に専念（SSRF 防護、429 バックオフ、ETag キャッシュ、Politeness 制御）。
2. **`src/supervisor` による堅牢な常駐ライフサイクル管理**:
   - Arbiter の管理下で `SpiderWorker`（`BaseWorker` / `QueueWorker` 拡張）として稼働。
   - 通信例外やクラッシュ時の「自動リカバリ（Self-Healing）」、`max_requests` や TTL による「自律世代交代（Graceful Retirement）」、停止時の「安全ドレイン（Graceful Drain）」を完備。
3. **`src/core/hsm` によるセッション状態統制 (DSN-23 Phase 2)**:
   - `OPERATIONAL.ACTIVE` 内を `IDLE` (待機) $\leftrightarrow$ `FETCHING` (クロール中) $\leftrightarrow$ `BACKOFF` (429 待機) で厳格にモデル化。
   - `DRAINING` 時に `FLUSH_ETAG_CACHE` を実行し、永続化を保証。
4. **透過的アダプター（`SpiderTaskOperator` / `SpiderDaemonClient`）**:
   - 常駐モード時は IPC キュー / UDS 経由で非同期ディスパッチ。
   - スタンドアロン・ローカル CLI 実行時は直接 `SpiderRunner().run_sync()` を同期実行する完全な後方互換性を担保。

```mermaid
graph TD
    subgraph SupervisorArbiter ["src/supervisor (Arbiter Master Process)"]
        Master["Supervisor Arbiter (Master Process)<br/>• 死活監視 (Heartbeat)<br/>• シグナル統制 (TERM/QUIT/HUP)"]
        SpiderWorker["SpiderWorker (PID: 1040)<br/>• 常駐待機ループ (HSM統制)<br/>• コネクションプール維持<br/>• max_requests=500 / TTL=86400s"]
        WorkflowWorker["WorkflowWorker (PID: 1030)<br/>• WorkflowScheduler 常駐ループ"]
        Master -->|fork / 監視| SpiderWorker
        Master -->|fork / 監視| WorkflowWorker
    end

    WorkflowWorker -->|CrawlJob 投入 (IPC Queue / UDS)| SpiderWorker
    SpiderWorker -->|HTTP/HTTPS クロール| ExternalWeb["外部ターゲット (arXiv / CWE / NVD)"]
```

---

## 2. トレーサビリティ / Traceability

- **リポジトリ内設計仕様書 (DSN)**:
  - `docs/designs/DSN-06-distributed_spider_and_crawler.md` (Section 9: 常駐型 Spider Daemon / Spider Worker アーキテクチャ)
  - `docs/designs/DSN-11-universal_workflow_engine.md` (Section 9.4: SpiderTaskOperator による常駐スパイダー連携)
  - `docs/designs/DSN-12-process_supervisor_and_arbiter.md` (Section 4.7, 4.8, 5.2: SpiderWorker ワーカーモデルおよび DAG 起動)
  - `docs/designs/DSN-23-hierarchical_state_machine_and_lifecycle_governance.md` (Section 4.1, 8.3: SpiderWorker セッション HSM 統合)
- **関連 Issue**:
  - Issue 205 (CISA KEV / NVD CVE Spiders)
  - Issue 207 (Retry / Offsite Middleware)
  - Issue 209 (Conditional GET & ETag Caching)
  - Issue 222 (MITRE CWE Spider & Catalog Ingestion)
  - Issue 224 (Hierarchical State Machine Engine & Supervisor HSM)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

### 1. スパイダー常駐基盤・クライアント
- [ ] [NEW] `src/spider/daemon/contracts.py`: `CrawlJob` / `CrawlResult` データモデル
- [ ] [NEW] `src/spider/daemon/worker.py`: 常駐型 `SpiderDaemonWorker`（HSM 駆動、ETag / Politeness 永続化）
- [ ] [NEW] `src/spider/daemon/client.py`: `SpiderDaemonClient`（UDS/IPC 通信＆同期フォールバック）
- [ ] [NEW] `src/spider/daemon/__init__.py`: パッケージエクスポート
- [ ] [MODIFY] `src/spider/runner.py`: 常駐モードおよびクライアント連携ヘルパー

### 2. スーパーバイザー統合
- [ ] [NEW] `src/supervisor/workers/spider_worker.py`: Supervisor 用 `SpiderWorker`
- [ ] [MODIFY] `src/supervisor/workers/__init__.py`: `SpiderWorker` エクスポートおよび `WORKER_CLASSES` 登録
- [ ] [MODIFY] `src/supervisor/contracts.py`: `WorkerSpec` における `spider` クラスサポート
- [ ] [MODIFY] `src/supervisor/arbiter.py`: `SpiderWorker` の初期化引数バインドと Graceful Drain

### 3. ワークフロー統合
- [ ] [NEW] `src/workflow/operators/spider_operator.py`: `SpiderTaskOperator`（透過的ディスパッチアダプター）
- [ ] [NEW] `src/workflow/operators/__init__.py`: パッケージエクスポート
- [ ] [MODIFY] `src/workflow/__init__.py`: `SpiderTaskOperator` 公開

### 4. 台帳・テスト
- [ ] [MODIFY] `docs/issues/README.md`: Issue 223 のステータスを `Open (In Progress)` に更新
- [ ] [NEW] `tests/spider/test_spider_daemon.py`: 常駐ディスパッチ・フォールバック・Graceful Drain 単体テスト
- [ ] [NEW] `tests/supervisor/test_spider_worker.py`: Supervisor 上での `SpiderWorker` 起動・死活・停止テスト
- [ ] [NEW] `tests/workflow/test_spider_operator.py`: DAG ワークフロー内での `SpiderTaskOperator` テスト

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/223-implement-resident-spider-daemon-and-workflow-supervisor-integration`

### Step 1: `SpiderDaemon` コア契約とワーカーの実装 (`src/spider/daemon/`)
1. `CrawlJob`（スパイダー名、パラメータ、優先度、ジョブID）および `CrawlResult`（ステータス、件数、統計、エラー）を定義。
2. `src/core/hsm` を活用した `SpiderSessionHSM`（`IDLE`, `FETCHING`, `BACKOFF`, `DRAINING`）を組み込んだ `SpiderDaemonWorker` を実装。
3. `SpiderDaemonClient` を実装し、常駐ワーカーが稼働している場合はキュー/UDS経由で高速実行し、非稼働時は `SpiderRunner` / `run_spider` を同期実行する完全透過フォールバックを提供。

### Step 2: Supervisor への `SpiderWorker` 統合 (`src/supervisor/`)
1. `SpiderWorker`（`QueueWorker` / `BaseWorker` 派生）を実装し、Supervisor の Arbiter からの死活監視パルス、`SIGQUIT` による Graceful Drain、`max_requests` と TTL による自律ローテーションをサポート。
2. `LifecycleHook` により、シャットダウン時に ETag キャッシュのディスク書き出し（`on_flush` / `teardown`）を確実に行う。

### Step 3: Workflow への `SpiderTaskOperator` 統合 (`src/workflow/`)
1. `SpiderTaskOperator` を実装し、DAG ワークフローのタスクノードハンドラとして登録可能にする。
2. 実行時コンテキストからパラメータを受け取り、`SpiderDaemonClient` 経由で実行して結果をワークフローの次ノードへ受け渡す。

### Step 4: 総合検証と品質ゲート
1. 全新規テストスイート（`tests/spider/test_spider_daemon.py`, `tests/supervisor/test_spider_worker.py`, `tests/workflow/test_spider_operator.py`）の PASS。
2. Xenon Grade A（CC $\le 4$ on all blocks）および `mypy --strict` の 100% 適合。

---

## 5. 完了条件 / Success Criteria (DoD)

- [x] `SpiderWorker` が `src/supervisor` の管理下で常駐プロセスとして起動・死活監視・自動再起動されること。
- [x] `src/workflow`（`DAGWorkflowEngine` / `WorkflowScheduler`）から `SpiderTaskOperator` を介して常駐スパイダーへ非同期ディスパッチできること。
- [x] 常駐プロセス非稼働時にも、透過的フォールバックにより CLI / スクリプトから同期実行できること。
- [x] 通信接続プール、ドメイン別 Politeness 状態、ETag キャッシュが常駐プロセス内で永続保持されること。
- [x] `make static_analysis` (`xenon` Grade A CC<=4, `mypy --strict`) に 100% 適合すること。
- [x] `docs/issues/README.md` で Issue 223 が `Open (In Progress)` として管理されていること。

