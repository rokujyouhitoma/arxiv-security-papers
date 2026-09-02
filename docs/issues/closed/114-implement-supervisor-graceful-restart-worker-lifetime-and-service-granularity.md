---
ID: 114
種別: Feature / Improvement
優先度: High
ステータス: Closed (Completed)
---

# [FEAT/ENH] Supervisorのサービス単位Graceful Restart・稼働時間(TTL)制限・リクエスト数制限による自律ローテーション機能の実装 (ID: 114)

## 1. 概要 / Summary
長期間にわたる高負荷運用や継続的デプロイにおいて、Supervisor 配下の各種ワーカープロセス（Web、Search、Database 等）を安全かつ自律的に管理・ローテーションするための以下の機能を実装する。

1. **サービス単位の個別 Graceful Restart**:
   - `supervisor restart [target]` コマンドおよび UDS IPC コマンド（`{"cmd": "restart", "target": "search"}`）により、指定したサービス（`search`, `database`）またはプール（`web`）のみを選択的かつ安全に再起動。
   - ステートレスプール（Web等）は新旧プロセスの先行起動・ドレイン置換による完全ゼロダウンタイム再起動。
   - ステートフルサービス（Search, Database等）は `hook.on_flush()` / `hook.teardown()` による永続化クリーンアップを経由した安全なプロセス置換。
2. **稼働時間制限（Max Worker Lifetime / TTL）と Jitter 機構**:
   - 起動からの経過時間（TTL）に応じた自動ローテーション（`max_worker_lifetime`）。
   - 全ワーカーの一斉再起動を防ぐランダムゆらぎ（`max_worker_lifetime_jitter`）の導入。
3. **リクエスト数制限（Max Requests）と Jitter 機構**:
   - 処理リクエスト累積件数が上限に達した際の自律 Graceful Drain（`max_requests`）。
   - サンダリングハードを防止するランダムゆらぎ（`max_requests_jitter`）の導入。
4. **サービス・プール単位の階層的設定モデル**:
   - `SupervisorConfig`（全体デフォルト）に加え、`PoolConfig` / `ServiceConfig` において個別の上限・タイムアウト値をオーバーライド可能にする。

---

## 2. トレーサビリティ / Traceability
- **関連設計書**: [DSN-12: 汎用プロセススーパーバイザー & 調停基盤包括的アーキテクチャ設計書](../../designs/DSN-12-process_supervisor_and_arbiter.md) (Section 8, Section 11, Section 12)
- **関連 Issue**:
  - Issue 113 (サービスワーカーIPCメトリクス連携・RPSモニタ)
  - Issue 112 (TopモニタリアルタイムREQ表示)
  - Issue 099 (Supervisor多重起動完全防止)
  - Issue 076 (Supervisor汎用プロセスエンジン化)

---

## 3. 脅威モデル分析とセキュリティ要件 / Threat Analysis & Security Requirements

| 脅威 / リスク | 影響度 | 対策・緩和策 |
| :--- | :---: | :--- |
| **Thundering Herd DoS（一斉再起動による過負荷）** | High | ワーカーの TTL / Max Requests 到達時に $\pm\text{jitter}$ の一様乱数を加算・減算し、ワーカーの退役タイミングを時間的に分散させる。 |
| **不正な IPC 引数による任意コマンドインジェクション** | Medium | UDS IPC の `restart` 引数 `target` を厳格にバリデーション（英数字・アンダースコア限定、未登録サービス名は即座に拒絶）。 |
| **Jitter 設定値の境界値異常（負数・過大値）** | Low | 設定読み込み時に `max_requests_jitter >= 0` かつ `max_requests_jitter < max_requests` を検証・正規化。 |
| **ステートフルサービス再起動時のデータ欠損** | High | `hook.on_flush()` を確実に呼び出し、WAL やインデックスの未書き込みバッファを同期した上で安全にプロセスを終了・置換する。 |

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files

### 設定・契約層
- [x] [src/supervisor/config.py](../../../src/supervisor/config.py):
  - `PoolConfig`, `ServiceConfig`, `SupervisorConfig` に `max_requests`, `max_requests_jitter`, `max_worker_lifetime`, `max_worker_lifetime_jitter`, `graceful_timeout` を追加。
  - `build_worker_specs()` で各設定を `WorkerSpec` へ伝播。
- [x] [src/supervisor/contracts.py](../../../src/supervisor/contracts.py):
  - `WorkerSpec` にライフタイムおよびリクエスト制限メタデータを統合。

### ワーカー層（自律ローテーション）
- [x] [src/supervisor/workers/base.py](../../../src/supervisor/workers/base.py):
  - `_init_retirement_criteria()` および `_should_retire()` メソッドを追加し、Jitter を加味した自律 Graceful 判定を実装。
- [x] [src/supervisor/workers/sync_worker.py](../../../src/supervisor/workers/sync_worker.py):
  - リクエスト処理後およびループ周回時に退役判定を実行し、正常終了。
- [x] [src/supervisor/workers/service_worker.py](../../../src/supervisor/workers/service_worker.py):
  - `_sync_hook_metrics` 後およびメインループ周回時に退役判定を実行。
- [x] [src/supervisor/workers/async_worker.py](../../../src/supervisor/workers/async_worker.py):
  - 非同期ストリーム処理後の退役判定。
- [x] [src/supervisor/workers/gthread_worker.py](../../../src/supervisor/workers/gthread_worker.py):
  - スレッドプール実行環境での退役判定。
- [x] [src/supervisor/workers/queue_worker.py](../../../src/supervisor/workers/queue_worker.py):
  - キューメッセージ消費後の退役判定。

### 調停・制御・CLI層
- [x] [src/supervisor/arbiter.py](../../../src/supervisor/arbiter.py):
  - サービス単位の再起動メソッド `restart(target: Optional[str] = None, mode: Optional[str] = None)` を実装。
  - `STATELESS_POOL` と `STATEFUL_SERVICE` で最適な再起動フロー（ローリング vs フラッシュ＆再起動）を分岐。
- [x] [src/supervisor/control.py](../../../src/supervisor/control.py):
  - `ControlClient.restart(target: str = "", all: bool = False, mode: str = "")` メソッドを追加。
- [x] [src/supervisor/cli.py](../../../src/supervisor/cli.py):
  - `restart` サブコマンドを拡張（`python -m supervisor.cli restart [target] [--all] [--rolling]`）。

### テスト
- [x] [tests/supervisor/test_config.py](../../../tests/supervisor/test_config.py):
  - 新設設定フィールドのパース・バリデーションテスト。
- [x] [tests/supervisor/test_workers.py](../../../tests/supervisor/test_workers.py):
  - `max_requests` および `max_worker_lifetime` 到達時の自律退役テスト。
- [x] [tests/supervisor/test_arbiter.py](../../../tests/supervisor/test_arbiter.py):
  - サービス単位の再起動およびローリング置換の検証テスト。
- [x] [tests/supervisor/test_cli.py](../../../tests/supervisor/test_cli.py):
  - `restart` CLI コマンドのテスト。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/114-implement-supervisor-graceful-restart-worker-lifetime-and-service-granularity`

1. **設定モデル・契約の拡張 (`config.py`, `contracts.py`)**:
   - `PoolConfig` / `ServiceConfig` / `SupervisorConfig` にフィールドを追加し、`to_dict()` および `WorkerSpec` への伝播を実装。
2. **ワーカー自律ローテーション (`base.py` & 各ワーカー)**:
   - `BaseWorker` に `effective_max_requests` と `effective_max_lifetime` を計算するロジックを実装。
   - 各ワーカーがリクエスト処理後およびループ周回時に `_should_retire()` をチェックし、到達時に `self.alive = False` で Graceful Drain して終了。
3. **Arbiter サービス単位 Restart (`arbiter.py`)**:
   - `restart(target, mode)` を実装し、ステートレスプールはローリング、ステートフルサービスはフラッシュ後再起動を実施。
   - 全体再起動時は依存関係を考慮した順序で実行。
4. **Control Client & CLI 統合 (`control.py`, `cli.py`)**:
   - IPC コマンドパーサーに `restart` を追加。
   - CLI 引数 `target`, `--all`, `--rolling` をサポート。
5. **品質ゲート検証**:
   - Xenon Grade A (CC $\le 5$)、Black, Isort, Flake8, MyPy, Pytest を全パス確認。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `max_requests` 到達時にワーカーが自律的に Graceful 退役し、Arbiter により新品ワーカーが自動補充されること。
- [x] `max_worker_lifetime` 到達時にワーカーが安全に終了し、Jitter により一斉再起動（サンダリングハード）が回避されること。
- [x] `supervisor restart <service>` により、指定したサービス（`search` や `database` 等）またはプール（`web`）のみが個別再起動できること。
- [x] `supervisor restart --all` により、全サービスがトポロジカル依存順序に沿って安全に再起動できること。
- [x] 全テストスイートが 100% PASS すること。
- [x] Xenon 循環的複雑度が全モジュールで **100% Rank A (CC $\le 5$)** を維持していること。

