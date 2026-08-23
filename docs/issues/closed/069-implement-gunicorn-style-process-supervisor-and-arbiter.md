# Issue 069: Gunicorn スタイル Pre-fork プロセススーパーバイザー & 調停基盤 (src/supervisor/) の実装

## 1. 概要 (Overview)
Gunicorn の Pre-fork ワーカーモデルおよびプロセス調停（Arbiter）アーキテクチャを踏襲・発展させ、ステートレスな Web サーバ群（WSGI / Gthread / Async）とステートフルな 組み込み／分散データベース（Vector DB / SQL / LSM / CoW-BTree）を一元管理・動的スケーリング・順序制御する統合プロセススーパーバイザーパッケージ（`src/supervisor/`）を実装した。

## 2. 背景と目的 (Context & Motivation)
- 現在の Web サーバおよびデータベースは、個別のプロセスまたは組み込み形式で起動・運用されていたが、高トラフィック環境や障害発生時の自己回復・自動スケーリング・グレースフル再起動を行うプロセス管理基盤が必要であった。
- Gunicorn と同様のシグナルセマンティクス（`SIGTTIN`/`SIGTTOU` でワーカー増減、`SIGHUP` でローリングリロード、`SIGCHLD` で死活監視・自動再起動）を提供し、さらにステートフルなデータベースの整合性を守る順序付きライフサイクル（起動時は DB 先行 $\to$ Web 追従、停止時は Web ドレイン $\to$ DB ディスクフラッシュ）を実現した。

## 3. 実装内容 (Implementation Summary)
1. `src/supervisor/contracts.py`: 汎用サービス役割（`ServiceRole`）、状態（`ServiceState`）、ライフサイクルフック（`LifecycleHook`）の抽象定義。
2. `src/supervisor/config.py`: 汎用プール（`PoolConfig`）、サービス（`ServiceConfig`）、ルート（`SupervisorConfig`）設定モデル。
3. `src/supervisor/heartbeat.py`: ミリ秒精度のワーカー死活監視 & タイムアウト検出（`HeartbeatWatchdog`）。
4. `src/supervisor/control.py`: Unix ドメインソケット JSON-RPC IPC コントロールサーバ & クライアント（`ControlServer`, `ControlClient`）。
5. `src/supervisor/workers/`:
   - `base.py`: ワーカー基底クラス（`BaseWorker`）。
   - `sync_worker.py`: 同期 PEP 3333 WSGI ワーカー（`SyncWorker`）。
   - `gthread_worker.py`: スレッドプール並行ワーカー（`GthreadWorker`）。
   - `async_worker.py`: AsyncIO イベントループワーカー（`AsyncWorker`）。
   - `service_worker.py`: 汎用ステートフルサービスワーカー（`ManagedServiceWorker`, `DatabaseWorker`）。
6. `src/supervisor/arbiter.py`: Arbiter コアループ、シグナルディスパッチャ、Pre-fork ソケット管理、順序制御（`ProcessArbiter`, `Arbiter`）。
7. `src/supervisor/cli.py`: CLI エントリポイント (`supervisor start/stop/reload/status/scale/ping`)。
8. `src/supervisor/__init__.py`: パッケージ公開インターフェース。
9. `Makefile`: `run_supervisor`, `status_supervisor` ターゲット追加。
10. `tests/supervisor/`: 包括的テストスイート（全22件 PASS）。
11. `docs/designs/DSN-12-process_supervisor_and_arbiter.md`: Gunicorn 機能整理、比較表、具象アダプタ設計を含む包括的設計ドキュメント。

## 4. 完了基準 (Definition of Done)
- [x] `src/supervisor/` パッケージが実装され、すべての主要ワーカータイプおよび Arbiter が動作すること
- [x] `make check_format` および `make static_analysis` がエラー 0 件で PASS すること
- [x] `tests/supervisor/` の単体・統合テストがすべて PASS すること
- [x] DSN-12 設計ドキュメントと整合していること
