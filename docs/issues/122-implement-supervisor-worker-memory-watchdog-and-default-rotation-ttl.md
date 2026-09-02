---
ID: 122
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/OPS] Supervisorにおけるワーカー自動ローテーションTTLデフォルト設定とメモリ上限監視（Memory Watchdog）の実装 (ID: 122)

## 1. 概要 / Summary
Supervisor 上で Web ワーカープロセスが一定時間ごと、あるいはメモリ肥大化時に自動で再生成・リフレッシュされる機構についての挙動仕様の明確化と改善。
現状の Supervisor 設計では、ワーカーの自律的退役機構 (`max_requests`, `max_worker_lifetime`) は実装されているものの、デフォルト値が `0.0` (無効化) となっており、またプロセスごとのメモリ使用量上限 (Memory Ceiling) に基づく自動退役・再生成機構（Memory Watchdog）が存在しなかった。
そのため、万が一ワーカー内で一時的なメモリ展開やキャッシュ肥大化（例: Issue #121）が発生した場合、手動リロードまたは再起動を行わない限りメモリが永続的に確保され続けてしまう課題がある。

### 目的 / Objectives
1. **ワーカー自動ローテーションのデフォルト化**:
   - Web プール等のステートレスワーカーに対して、デフォルトで安全な TTL (`max_worker_lifetime = 3600s` + Jitter `300s`) およびリクエスト数上限 (`max_requests = 2000` + Jitter `200`) を適用し、長時間稼働によるメモリ蓄積を自律的に解消する。
2. **メモリ上限監視（Memory Watchdog / RSS・PSS Ceiling）の導入**:
   - Arbiter の Watchdog ループにおいて各ワーカーの PSS/RSS メモリ使用量を定期サンプリングし、設定された閾値（例: Web ワーカー `max_worker_memory_mb = 250MB`）を超過した場合に自律的に Graceful 退役 (`SIGQUIT`) と新規ワーカーの即時フォークを実行する。

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [src/supervisor/config.py](../../src/supervisor/config.py)
- [ ] [src/supervisor/heartbeat.py](../../src/supervisor/heartbeat.py)
- [ ] [src/supervisor/arbiter.py](../../src/supervisor/arbiter.py)
- [ ] [src/supervisor/workers/base.py](../../src/supervisor/workers/base.py)
- [ ] [tests/supervisor/test_arbiter.py](../../tests/supervisor/test_arbiter.py)
- [ ] [tests/supervisor/test_watchdog.py](../../tests/supervisor/test_watchdog.py)
- [ ] [tests/supervisor/test_config.py](../../tests/supervisor/test_config.py)

---

## 3. 根本原因と現状仕様の整理 / Current Behavior vs Expected
1. **現状 (Current Behavior)**:
   - `SupervisorConfig` / `PoolConfig` の `max_worker_lifetime` (TTL) はデフォルト `0.0` (無制限)。
   - `max_requests` はデフォルト `0` (無制限)。
   - メモリ上限に基づく自動退役機能は未実装。
   - そのため、Web ワーカーが一度肥大化すると、プロセスが自律的に終了・再生成されず常駐し続ける。
2. **期待動作 (Expected Behavior)**:
   - ステートレスワーカープール（Web 等）は一定時間（例: 1時間）または一定リクエスト数ごとに自動的かつ Jitter 付きで順次ローテーション再生成される。
   - ワーカーのメモリ使用量が規定値を超えた場合、Arbiter Watchdog がそれを検知して Graceful にローテーションし、システムの健全性を自動維持する。

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/122-implement-supervisor-worker-memory-watchdog-and-default-rotation-ttl`

1. **`src/supervisor/config.py` の拡張**:
   - `PoolConfig`, `ServiceConfig`, `SupervisorConfig` に `max_worker_memory_mb: float` (デフォルト: Webプールは 250.0MB, グローバルは 0.0) を追加。
   - デフォルトの Web プール設定において `max_worker_lifetime` (3600.0s) と `max_worker_lifetime_jitter` (300.0s) を標準有効化。
2. **`src/supervisor/heartbeat.py` & `src/supervisor/arbiter.py` のメモリ監視**:
   - Watchdog に `check_memory_exceeded_workers(threshold_mb)` を実装（`/proc/<pid>/smaps_rollup` または `status` から PSS/RSS を取得）。
   - Arbiter の定期ヘルスチェックループ (`murder_workers` / `check_worker_health`) でメモリ超過ワーカーを検知し、`SIGQUIT` (Graceful Retirement) を送信後、即座に新規ワーカーを補充する。
3. **自動テストの追加**:
   - `tests/supervisor/test_arbiter.py` に、ワーカーがメモリ上限超過時に自動で Graceful 再生成されることを検証するユニットテストを追加。
   - `tests/supervisor/test_config.py` に新規設定フィールドのバリデーションテストを追加。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] Web プール等のワーカーがデフォルトで 1 時間周期 (+ Jitter) で自律的・順次ローテーション再生成されること
- [ ] ワーカーのメモリ使用量が `max_worker_memory_mb` を超えた際に、Arbiter が検知してゼロダウンタイムで新規ワーカーへ交代させること
- [ ] 全テスト（`make test`）および品質ゲート（`make format`, `make static_analysis`）が 100% PASS すること
