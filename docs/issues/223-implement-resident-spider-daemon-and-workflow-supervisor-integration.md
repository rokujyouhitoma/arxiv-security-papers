---
ID: 223
種別: Feature / Architecture
優先度: High
ステータス: Open (New)
担当エージェント: Systems Architect / Network Specialist / Software Development / IT Service Manager
---

# [FEAT/ARCH] src/spider の常駐型デーモン化および src/workflow・src/supervisor 統合アーキテクチャの実装 (ID: 223)

## 1. 概要 / Summary

現在、`src/spider/` クローラー基盤は、CLI やバッチから呼び出されるたびにプロセスが起動し、フェッチ完了後に破棄される「一回限り実行（One-shot CLI/Script）」の動作モデルとなっている。
しかし、大規模かつ継続的なセキュリティ論文・脅威インテリジェンス収集（arXiv, IACR, CISA KEV, NVD CVE, MITRE CWE 等）においては、以下の課題が顕在化している：

1. **接続オーバーヘッド**: 起動ごとの TCP 3-way ハンドシェイクおよび TLS ネゴシエーション。
2. **Politeness（礼儀正しさ）状態・キャッシュの喪失**: プロセス終了に伴い、ドメインごとの最終アクセス時刻や連続 429 バックオフ係数、ETag / If-Modified-Since テーブルがメモリから失われ、再起動時にリセットされる。
3. **イベント駆動の即時性欠如**: Web コンソールからのオンデマンド即時更新や外部アラート検知に対して、コールドスタート遅延が発生する。

本 Issue では、`src/spider` を常駐型アプリケーション（`SpiderWorker` / `SpiderDaemon`）へと刷新し、`src/workflow`（汎用ワークフロー基盤）および `src/supervisor`（プロセス調停基盤）と以下の 3 大設計方針に基づいて統合する。

### 3 大統合方針
1. **制御プレーンと実行プレーンの明確な分離**:
   - **Control Plane（制御プレーン）: `src/workflow` (`WorkflowScheduler`)**: 「いつ・何を・どの順序で実行するか（What & When）」を一元統制（Cron/Interval、全体 DAG、障害時の Circuit/Saga/WAL）。
   - **Execution Plane（実行プレーン）: `src/spider` (`SpiderWorker`)**: 「外部通信をどう安全・確実に実行するか（How）」に専念（SSRF 防護、429 バックオフ、ETag キャッシュ、Politeness 制御）。
2. **`src/supervisor` による堅牢な常駐ライフサイクル管理**:
   - Arbiter の管理下で `SpiderWorker`（`QueueWorker` 拡張）として稼働。
   - 通信例外やクラッシュ時の「自動リカバリ（Self-Healing）」、`max_requests` や TTL による「自律世代交代（Graceful Retirement）」、停止時の「安全ドレイン（Graceful Drain）」を完備。
3. **透過的アダプター（`SpiderTaskOperator` / `SpiderDaemonClient`）**:
   - 常駐モード時は IPC キュー経由で非同期ディスパッチ。
   - スタンドアロン・ローカル CLI 実行時は直接 `SpiderRunner().run_sync()` を同期実行する完全な後方互換性を担保。

```mermaid
graph TD
    subgraph SupervisorArbiter ["src/supervisor (Arbiter Master Process)"]
        Master["Supervisor Arbiter (Master Process)<br/>• 死活監視 (Heartbeat)<br/>• シグナル統制 (TERM/QUIT/HUP)"]
        SpiderWorker["SpiderWorker (PID: 1040)<br/>• 常駐待機ループ<br/>• コネクションプール維持<br/>• max_requests=500 / TTL=86400s"]
        WorkflowWorker["WorkflowWorker (PID: 1030)<br/>• WorkflowScheduler 常駐ループ"]
        Master -->|fork / 監視| SpiderWorker
        Master -->|fork / 監視| WorkflowWorker
    end

    WorkflowWorker -->|CrawlJob 投入 (IPC Queue)| SpiderWorker
    SpiderWorker -->|HTTP/HTTPS クロール| ExternalWeb["外部ターゲット (arXiv / CWE / NVD)"]
```

---

## 2. トレーサビリティ / Traceability

- **リポジトリ内設計仕様書 (DSN)**:
  - `docs/designs/DSN-06-distributed_spider_and_crawler.md` (Section 9: 常駐型 Spider Daemon / Spider Worker アーキテクチャ)
  - `docs/designs/DSN-11-universal_workflow_engine.md` (Section 9.4: SpiderTaskOperator による常駐スパイダー連携)
  - `docs/designs/DSN-12-process_supervisor_and_arbiter.md` (Section 4.7, 4.8, 5.2: SpiderWorker ワーカーモデルおよび DAG 起動)
- **関連 Issue**:
  - Issue 205 (CISA KEV / NVD CVE Spiders)
  - Issue 207 (Retry / Offsite Middleware)
  - Issue 209 (Conditional GET & ETag Caching)
  - Issue 222 (MITRE CWE Spider & Catalog Ingestion)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

### 1. スパイダー常駐基盤・クライアント
- [ ] [NEW] `src/spider/daemon/worker.py`: 常駐型クローラー待機ループおよび IPC ハンドラー
- [ ] [NEW] `src/spider/daemon/client.py`: `SpiderDaemonClient`（常駐ワーカーとの UDS/IPC 通信＆フォールバック）
- [ ] [MODIFY] `src/spider/runner.py`: 常駐モード起動（`--daemon` / `--worker`）サポート

### 2. スーパーバイザー統合
- [ ] [NEW] `src/supervisor/workers/spider_worker.py`: Supervisor 用 `SpiderWorker`（`QueueWorker` / `ServiceWorker` 継承）
- [ ] [MODIFY] `src/supervisor/contracts.py`: `WorkerSpec` における `spider` クラスおよび依存 DAG 定義
- [ ] [MODIFY] `src/supervisor/arbiter.py`: `SpiderWorker` の起動・監視・Graceful Drain

### 3. ワークフロー統合
- [ ] [NEW] `src/workflow/operators/spider_operator.py`: `SpiderTaskOperator`（透過的ディスパッチアダプター）
- [ ] [MODIFY] `src/workflow/scheduler.py`: 各種スパイダー定期タスクの登録

### 4. 台帳・テスト
- [ ] [MODIFY] `docs/issues/README.md`: Issue 223 の登録
- [ ] [NEW] `tests/spider/test_spider_daemon.py`: 常駐ディスパッチ・フォールバック・Graceful Drain 単体テスト

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/223-implement-resident-spider-daemon-and-workflow-supervisor-integration`

### Step 1: `SpiderDaemonClient` および常駐ワーカーのコア実装
1. ゼロ外部依存（Pure Python）で UDS（Unix Domain Socket）またはインメモリ IPC キューを介したメッセージプロトコル（`CrawlJob` ➔ `CrawlResult`）を設計。
2. `SpiderDaemonClient` を実装し、常駐デーモンが存在する場合は IPC 送信、非存在時は直接 `SpiderRunner` を同期実行するフォールバックを完備。

### Step 2: Supervisor への `SpiderWorker` 統合
1. `src/supervisor/workers/spider_worker.py` を作成し、`LifecycleHook`（`health_check`, `setup`, `teardown`）を実装。
2. `max_requests`（処理回数制限）および `max_worker_lifetime`（TTL）による自律世代交代と、`SIGQUIT` 受信時の通信ドレイン（Graceful Drain）を保証。

### Step 3: Workflow への `SpiderTaskOperator` 統合
1. `SpiderTaskOperator` を実装し、`WorkflowScheduler` から宣言的に `ScheduledTask` としてスパイダーを登録可能にする。
2. arXiv、CISA KEV、NVD CVE、MITRE CWE の定期タスクを `SpiderTaskOperator` 経由で実行可能にする。

### Step 4: 総合検証と品質ゲート
1. `make test` による常駐通信・フォールバック単体テストの全件通過。
2. `make static_analysis` (Black, isort, Flake8, Xenon Grade A CC<=4, `mypy --strict`) 100% 適合。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `SpiderWorker` が `src/supervisor` の管理下で常駐プロセスとして起動・死活監視・自動再起動されること。
- [ ] `src/workflow`（`WorkflowScheduler`）から `SpiderTaskOperator` を介して常駐スパイダーへ非同期ディスパッチできること。
- [ ] 常駐プロセス非稼働時にも、透過的フォールバックにより CLI / スクリプトから同期実行できること。
- [ ] 通信接続プール、ドメイン別 Politeness 状態、ETag キャッシュが常駐プロセス内で永続保持されること。
- [ ] `make static_analysis` (`xenon` Grade A CC<=4, `mypy --strict`) に 100% 適合すること。
- [ ] `docs/issues/README.md` に Issue 223 が登録されていること。
