# DSN-12: 汎用プロセススーパーバイザー & 調停基盤 (Universal Process Arbiter & Supervisor Tree)

## 1. エグゼクティブサマリー (Executive Summary)

本ドキュメント（DSN-12）は、**Gunicorn** の Pre-fork ワーカーモデル、Erlang/OTP の Supervisor ツリー、および Systemd のサービス調停・監視機構を統合し、**Web ゲートウェイ、分散検索エンジン、データベース、常駐サービスなど、異種プロセスを統一的に統括管理・動的スケーリング・自己回復させる汎用プロセス調停基盤（`src/supervisor/`）** の具象設計・実装仕様書です。

---

## 2. コア設計思想とアーキテクチャ (Core Architecture & Topology)

本システムは、メモリ肥大化の防止と障害分離を実現するため、**「Web ゲートウェイ（ステートレス並行プール）」**、**「Search Engine（常駐ベクトルインデックス）」**、**「Database（ストレージ＆SQL実行エンジン）」** の 3 層完全プロセス分離アーキテクチャを採用しています。

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          ProcessArbiter (Master)                            │
│  - Pre-binds HTTP Listening Socket (0.0.0.0:8000)                           │
│  - POSIX Double-Fork Daemonization (-D / --daemon)                          │
│  - Millisecond Heartbeat Watchdog & Hang Recovery                           │
│  - IPC Control Server: outputs/supervisor/control.sock                      │
│  - Log Redirection: outputs/supervisor/supervisor.log                       │
│  - PID Guard: outputs/supervisor/arbiter.pid                                │
└───────────────────────┬─────────────────────────────┬───────────────────────┘
                        │                             │
       (Ordered Phase 1)│                             │(Ordered Phase 2)
                        ▼                             ▼
┌──────────────────────────────────────────┐ ┌────────────────────────────────┐
│      Stateful Managed Services           │ │    Stateless Worker Pools      │
│  (ManagedServiceWorker / LifecycleHook)  │ │      (Pre-fork Web Workers)    │
│                                          │ │                                │
│ ┌──────────────────────────────────────┐ │ │ ┌────────────────────────────┐ │
│ │ SearchService (PID: 123846)          │ │ │ │ Web Worker 1 (Sync / Gthr) │ │
│ │ - 14,349件 論文ベクトル・全文検索    │ │ │ │ - Shared HTTP socket accept│ │
│ │ - IPC: outputs/supervisor/search.sock│ │ │ └────────────────────────────┘ │
│ └──────────────────────────────────────┘ │ │ ┌────────────────────────────┐ │
│ ┌──────────────────────────────────────┐ │ │ │ Web Worker 2 (Sync / Gthr) │ │
│ │ DatabaseService (PID: 123847..123849)│ │ │ │ - Shared HTTP socket accept│ │
│ │ - VectorStorage / ARIES WAL / SQL    │ │ │ └────────────────────────────┘ │
│ │ - IPC: outputs/supervisor/db.sock    │ │ └────────────────────────────────┘
│ └──────────────────────────────────────┘ │
└──────────────────────────────────────────┘
```

---

## 3. 主要コンポーネント詳細仕様 (Component Specifications)

### 3.1 Process Arbiter (`src/supervisor/arbiter.py`)
Arbiter（マスタープロセス）はクライアントリクエストを直接処理せず、クラスタ全体のライフサイクル、シグナルハンドリング、死活監視、およびデーモン化を統括します。

1. **POSIX Double-Fork デーモン化 (`daemonize`)**:
   - `-D` / `--daemon` オプション指定時、2段階の `os.fork()`、`os.setsid()`（新規セッションリーダー化）、`os.umask(0)` を実行し、制御端末（TTY）から完全にデタッチ。
   - 標準入力（FD 0）を `/dev/null` に、標準出力・標準エラー出力（FD 1, 2）を `config.log_file`（`outputs/supervisor/supervisor.log`）へ安全にリダイレクト。
   - 二重起動を防止するため `outputs/supervisor/arbiter.pid` を管理し、既存プロセスの生存確認（`os.kill(pid, 0)`）を実施。
2. **Pre-fork リスニングソケット共有**:
   - 親プロセスで `0.0.0.0:8000` を事前バインドし、子ワーカーへファイルディスクリプタを継承。OS カーネルによる自然な負荷分散を実現。
3. **二段階順序起動 (Two-Phase Ordered Boot)**:
   - **Phase 1 (Stateful Services)**: 依存元となる `SearchService`, `DatabaseService` などの常駐サービスを先行起動し、`LifecycleHook.setup()` が完了するまで待機。
   - **Phase 2 (Stateless Pools)**: サービス準備完了後、Web ワーカー群を Pre-fork 起動。

---

### 3.2 汎用ライフサイクルフック & サービス契約 (`src/supervisor/contracts.py`)

あらゆる常駐型ステートフルサービス（DB, Search, Queue, Batch）は `LifecycleHook` 抽象インターフェースに準拠します。

```python
class ServiceRole(enum.Enum):
    STATELESS_POOL = "STATELESS_POOL"      # 水平スケール可能なワーカー群 (Web)
    STATEFUL_SERVICE = "STATEFUL_SERVICE"  # 単一性・整合性を要する常駐サービス (DB, Search)
    ONESHOT_TASK = "ONESHOT_TASK"          # 完了後に終了するバッチタスク (拡張予定)

class LifecycleHook(abc.ABC):
    @abc.abstractmethod
    def setup(self) -> bool:
        """ストレージ初期化、インデックスロード、UDS ソケット起動等。成功時 True。"""
        raise NotImplementedError

    @abc.abstractmethod
    def health_check(self) -> bool:
        """ミリ秒精度の死活・応答性判定 (Ping/Health)。合格時 True。"""
        raise NotImplementedError

    def on_flush(self) -> None:
        """定期的 (sync_interval) またはシャットダウン直前に実行するディスク同期。"""
        pass

    @abc.abstractmethod
    def teardown(self) -> None:
        """安全停止処理 (接続切断, ロック解放, ソケットアンリンク)。"""
        raise NotImplementedError
```

---

### 3.3 ハートビート＆ミリ秒精度 Watchdog (`src/supervisor/heartbeat.py`)

従来の Gunicorn ではアイドル状態のワーカーがタイムアウト誤判定される問題がありましたが、本設計では **「リクエスト処理中フラグ（`is_handling_request`）」** を導入して誤判定を根絶しています。

- **健全性判定**: 各ワーカーはリクエスト開始時に `watchdog.pulse(handling=True)`、完了時に `watchdog.pulse(handling=False)` を通知。
- **ハング検出**: `is_handling_request=True` のまま `request_timeout`（デフォルト30秒）を超過したワーカーのみを「真のハングプロセス」として検知。
- **自動回復**: ハングしたワーカーを `SIGKILL` で強制終了し、Arbiter が `SIGCHLD` をトラップして即座に代替ワーカーをフォーク。

---

### 3.4 リアルタイム Top モニター (`src/supervisor/top.py`)

外部 C 拡張（`psutil` や `curses` 等）に依存せず、Linux の `/proc` ファイルシステムから高精度なメモリテレメトリを収集・可視化します。

- **PSS (Proportional Set Size) 計測**:
  - `/proc/<pid>/smaps_rollup` から PSS（共有メモリの重複を除外した実質固有メモリ）と RSS をリアルタイム算出。
  - プロセス全体の正確なメモリフットプリントを可視化（例: Search: 1.3 GB, Web: 30 MB, DB: 25 MB）。
- **非破壊 ANSI 描画**:
  - `outputs/supervisor/control.sock` 経由で定期ポーリング（デフォルト 1.0秒間隔）。
  - CI・スクリプト連携用の `--once`（ワンショット出力）および `--interval <sec>` に対応。

---

### 3.5 多段有向グラフ (DAG) トポロジカル順序起動 & 逆順ドレイン停止

サービス・プール間の `dependencies` を元に、Kahn のアルゴリズムを用いた有向グラフのトポロジカルソートを実行し、依存関係を厳格に満たす順序で起動および停止します。

1. **トポロジカル順序解決 (`resolve_boot_order`)**:
   - `WorkerSpec.dependencies` から入次数（in-degree）マップと隣接リストを生成。
   - 入次数 0 の独立ノードから順に起動キューへ追加し、依存先がすべて起動完了した後に依存元（Web 等）を起動。
   - 同一次数ノード間ではステートフルサービス（DB/Search）を優先。
2. **循環依存の安全な遮断**:
   - 循環依存（`A -> B -> A` 等）が存在する場合、即座に `ValueError` を送出し、クラスタのデッドロック・起動ハングを未然に防止。
3. **逆順トポロジカルグレースフル停止**:
   - シャットダウン時（`shutdown()`）はトポロジカル順序を反転させ、上位の Web ワーカー群を先にドレイン・停止させた後、下位の DB/Search サービスを安全に終了。

---

### 3.6 `ONESHOT_TASK` バッチタスク実行 & 再試行管理

一括インデックス構築やマイグレーションなど、タスク完了後に自動終了するプロセスを管理します。

1. **正常終了時の再起動スキップ**:
   - ワーカーが終了コード 0（Exit Code 0）で終了した際、Arbiter はクラッシュと判定せず、状態を `ServiceState.COMPLETED` に遷移させて再起動を抑止。
2. **異常終了時の自動再試行 (`max_retries`)**:
   - 終了コードが 0 以外の場合、`retry_count < max_retries` であれば自動で再フォークしてタスクを再試行。
   - リトライ上限到達時は `ServiceState.FAILED` として恒久停止し、ログにエラーを記録。

---

### 3.7 汎用メッセージキュー・コンシューマワーカー (`QueueWorker`)

HTTP リスニングソケットをバインドせず、メモリキュー（`queue.Queue`）やイベントストリームからメッセージを安全にデキューして処理するステートレスワーカーです。

1. **ノンブロッキング・ポーリングループ**:
   - デキュー関数またはキューからアイテムを取得し、定義されたハンドラを実行。
   - アイドル時・処理完了時に `pulse(handling=False)`、タスク実行中に `pulse(handling=True)` を送信して Watchdog と連携。
2. **`SIGQUIT` グレースフルドレイン**:
   - `SIGQUIT` または `SIGTERM` 受信時、現在処理中のメッセージを最後まで完遂してから安全にプロセスを終了（メッセージの喪失を防止）。

---

## 4. IPC コントロールプロトコル仕様 (Unix Domain Socket)

Arbiter および各サブシステムは、専用の Unix Domain Socket 上で JSON ベースの高速 IPC プロトコルを提供します。

### 4.1 エンドポイント一覧

| ソケットパス | 担当サービス | 主なコマンド / オペレーション |
| :--- | :--- | :--- |
| **`outputs/supervisor/control.sock`** | **Arbiter Control** | `ping`, `status`, `scale`, `reload`, `stop` |
| **`outputs/supervisor/search.sock`** | **Search Service** | `ping`, `search`, `get_paper`, `get_related`, `get_stats` |
| **`outputs/supervisor/db.sock`** | **Database Service** | `ping`, `info`, `execute_sql`, `insert`, `search_knn`, `get_by_id` |

---

### 4.2 Control IPC メッセージ仕様

#### 1. `status` (クラスタ状態テレメトリ)
- **Request**: `{"cmd": "status"}`
- **Response**:
```json
{
  "status": "ok",
  "arbiter_pid": 123844,
  "uptime": 120.5,
  "pools": {
    "web": { "target": 2, "active": 2, "pids": [123850, 123851], "role": "STATELESS_POOL" },
    "search": { "target": 1, "active": 1, "pids": [123846], "role": "STATEFUL_SERVICE" },
    "database": { "target": 3, "active": 3, "pids": [123847, 123848, 123849], "role": "STATEFUL_SERVICE" }
  },
  "workers": {
    "123846": { "pid": 123846, "type": "search", "status": "ALIVE", "is_healthy": true, "idle_seconds": 2.1 }
  }
}
```

#### 2. `scale` (動的プール伸縮)
- **Request**: `{"cmd": "scale", "pool": "web", "workers": 4}`
- **Response**: `{"status": "ok", "pool": "web", "target_workers": 4}`

#### 3. `reload` (ローリングリスタート)
- **Request**: `{"cmd": "reload"}`
- **Response**: `{"status": "ok", "message": "Reload sequence initiated"}`

#### 4. `stop` (グレースフル停止)
- **Request**: `{"cmd": "stop"}`
- **Response**: `{"status": "ok", "message": "Shutdown sequence initiated"}`

---

## 5. 設定ファイル仕様 (`config/supervisor.json`)

```json
{
  "bind_host": "0.0.0.0",
  "bind_port": 8000,
  "daemon": false,
  "log_file": "outputs/supervisor/supervisor.log",
  "pid_file": "outputs/supervisor/arbiter.pid",
  "control_socket": "outputs/supervisor/control.sock",
  "request_timeout": 30.0,
  "pools": [
    {
      "name": "web",
      "workers": 2,
      "worker_class": "sync",
      "dependencies": ["search", "database"]
    }
  ],
  "services": [
    {
      "name": "search",
      "workers": 1,
      "hook_uri": "search.server.service:SearchLifecycleHook",
      "sync_interval": 2.0
    },
    {
      "name": "database",
      "workers": 3,
      "hook_uri": "database.service:DatabaseLifecycleHook",
      "sync_interval": 2.0
    }
  ]
}
```

---

## 6. CLI 運用コマンド・リファレンス (CLI Operations Reference)

### 6.1 起動 (Start)
```bash
# 1. デーモンモードでバックグラウンド起動 (即座にシェル解放)
PYTHONPATH=src .venv/bin/python -m supervisor.cli -c config/supervisor.json start -D

# または Makefile ターゲット
make start_supervisor

# 2. フォアグラウンド起動 (ログをコンソール出力)
PYTHONPATH=src .venv/bin/python -m supervisor.cli -c config/supervisor.json start
```

### 6.2 状態確認 & モニタリング (Status & Top)
```bash
# 1. JSON 形式でのクラスター状態取得
PYTHONPATH=src .venv/bin/python -m supervisor.cli status
# または make status_supervisor

# 2. リアルタイム ANSI プロセス監視 TUI
PYTHONPATH=src .venv/bin/python -m supervisor.cli top
# または make top_supervisor

# 3. Top ダッシュボードのワンショット表示
PYTHONPATH=src .venv/bin/python -m supervisor.cli top --once

# 4. ログのリアルタイム追跡
tail -f outputs/supervisor/supervisor.log
```

### 6.3 ライフサイクル制御 (Scale / Reload / Stop)
```bash
# 1. Web ワーカー数を 4 プロセスにスケール
PYTHONPATH=src .venv/bin/python -m supervisor.cli scale -p web -w 4

# 2. 設定再読み込みとワーカー再起動 (ゼロダウンタイム)
PYTHONPATH=src .venv/bin/python -m supervisor.cli reload
# または make reload_supervisor

# 3. Supervisor 親プロセスおよび全子ワーカーの安全停止
PYTHONPATH=src .venv/bin/python -m supervisor.cli stop
# または make stop_supervisor
```

---

## 7. 結論と品質保証 (Conclusion & Verification)

本調停基盤（`src/supervisor/`）は、DAG トポロジカル順序起動、デーモン化（`-D`）、UDS プロセス分離 IPC、PSS メモリ監視、`ONESHOT_TASK`、および `QueueWorker` の全仕様を完全実装し、厳格な品質ゲート（Xenon 複雑度 A/B、Mypy strict 0エラー、全単体/結合テスト PASS）により堅牢性が保証されています。
