---
ID: 078
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT/ENH] Implement DSN-12 DAG Boot Ordering, ONESHOT_TASK Management, and QueueWorker (ID: 078)

## 1. 概要 / Summary
`docs/designs/DSN-12-process_supervisor_and_arbiter.md` 設計仕様書の完全準拠に向けて、以下の未実装機能を実装した：
1. **多段有向グラフ（DAG）汎用トポロジカル依存関係ソート (`resolve_boot_order`)**: サービス・プール間の `dependencies` を自動解析し、トポロジカル順序で起動および逆順でドレイン停止する機能（循環依存の検知と安全なエラー通知）。
2. **`ONESHOT_TASK` バッチタスク実行管理 (`ServiceRole.ONESHOT_TASK`)**: 正常終了（Exit Code 0）したタスクをクラッシュ判定せず「COMPLETED」として再起動をスキップし、異常終了時は設定された再試行回数（`max_retries`）に従ってハンドリングする機能。
3. **汎用メッセージキュー・コンシューマワーカー (`QueueWorker`)**: HTTP ソケットを持たず、メッセージキュー／イベントストリーム（Callable / Queue）から安全にデキュー・処理するステートレスワーカークラス（`SIGQUIT` 受信時の Graceful Drain 処理）。

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- `src/supervisor/contracts.py`: `ServiceRole.ONESHOT_TASK`, `WorkerSpec.dependencies`, `WorkerSpec.max_retries`, `ServiceState.COMPLETED`
- `src/supervisor/arbiter.py`: `resolve_boot_order()`, `_build_dependency_graph()`, `_handle_child_exit()`
- `src/supervisor/workers/queue_worker.py`: 汎用キューコンシューマワーカーの実装
- `src/supervisor/workers/__init__.py`: `QueueWorker` のエクスポート
- `tests/supervisor/test_dag_and_oneshot.py`: DAG トポロジカル起動、ONESHOT タスク、QueueWorker の単体・結合テスト

---

## 3. 脅威モデルとセキュリティ要件 (Threat Model & Security)
- **循環依存によるデッドロック（DoS）**: 不正な設定ファイルや悪意ある依存定義（`A -> B -> A`）による無限ループ・ハングアップの防止。Kahn のトポロジカルソートで循環を検出し `ValueError` で安全に拒否する。
- **ゾンビプロセスのリソース枯渇**: `ONESHOT_TASK` が終了した際、`waitpid` で確実にプロセスを刈り取り（Reap）、PID リークを根絶する。
- **キューメッセージ喪失防止**: `QueueWorker` が `SIGQUIT` や `SIGTERM` を受信した際、現在処理中のメッセージを完了してから終了する（Graceful Drain）。

---

## 4. 実装方針 / Implementation Plan
- **Target Branch**: `feat/078-implement-dsn12-dag-boot-oneshot-and-queue-workers`

### Step 1: `src/supervisor/contracts.py` の拡張
- `ServiceState.COMPLETED` を追加。
- `WorkerSpec` に `dependencies: List[str]`, `max_retries: int = 0`, `retry_count: int = 0` を追加。

### Step 2: `src/supervisor/workers/queue_worker.py` の新規実装
- `BaseWorker` を継承した `QueueWorker` クラスを実装。
- `Callable[[], Optional[Any]]` または `queue.Queue` からアイテムを pop し、`handler(item)` を実行。
- `alive` フラグと `init_signals()` による `SIGQUIT` 安全ドレイン。

### Step 3: `src/supervisor/arbiter.py` の DAG 起動・停止制御 & ONESHOT 管理
- `resolve_boot_order()`: プールおよびサービス間の `dependencies` を元に Kahn のトポロジカルソートを実行。
- `start()`: トポロジカルソート順（Phase 1: DB/Search 等の先行サービス $\to$ Phase 2: Web 等の依存プール）で起動。
- `shutdown()`: トポロジカル逆順でグレースフル停止。
- `_handle_child_exit(pid, exit_code)`: `ServiceRole.ONESHOT_TASK` の場合、正常終了（exit_code == 0）なら再起動せず `ServiceState.COMPLETED` に遷移。異常終了時は `retry_count < max_retries` なら再フォーク。

### Step 4: 単体テストと品質ゲート検証
- `tests/supervisor/test_dag_and_oneshot.py` を作成し、DAG ソート、循環依存検知、ONESHOT 正常完了、異常再試行、QueueWorker ドレインを検証。
- `make check_format`, `make static_analysis`, `pytest tests/supervisor/` をパスさせる。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] 依存関係グラフ（DAG）に基づくトポロジカル順序起動と逆順停止が機能すること
- [x] 循環依存が指定された場合に即座に検知され、エラーが通知されること
- [x] `ONESHOT_TASK` が正常終了時に再起動されず、`COMPLETED` として安全に記録されること
- [x] `QueueWorker` がメッセージを処理し、`SIGQUIT` で処理中タスクを完了して安全終了すること
- [x] すべての品質ゲート（`make check_format`, `make static_analysis`, 全テスト PASS）が 100% 成功すること
