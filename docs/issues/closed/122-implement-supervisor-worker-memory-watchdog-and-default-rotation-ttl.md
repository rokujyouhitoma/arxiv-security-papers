---
ID: 122
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT/OPS] Supervisorにおけるワーカー自動ローテーションTTLデフォルト設定とメモリ上限監視（Memory Watchdog）の実装 (ID: 122)

## 1. 概要 / Summary
Supervisor 上で Web ワーカープロセスが一定時間ごと、あるいはメモリ肥大化時に自動で再生成・リフレッシュされる機構についての挙動仕様の明確化と恒久改善。
現状の Supervisor 設計では、ワーカーの自律的退役機構 (`max_requests`, `max_worker_lifetime`) のロジックは実装されているものの、デフォルト値が `0.0` (無効化) となっており、またプロセスごとのメモリ使用量上限 (Memory Ceiling) に基づく自動退役・再生成機構（Memory Watchdog）が存在しなかった。
そのため、万が一ワーカー内で一時的なメモリ展開やキャッシュ肥大化（例: Issue #121）が発生した場合、手動リロードまたは再起動を行わない限りメモリが永続的に確保され続けてしまう課題がある。

### 目的 / Objectives
1. **ワーカー自動ローテーションのデフォルト化**:
   - Web プール等のステートレスワーカーに対して、デフォルトで安全な TTL (`max_worker_lifetime = 3600.0s` + Jitter `300.0s`) およびリクエスト数上限 (`max_requests = 2000` + Jitter `200`) を標準適用し、長時間稼働によるメモリ蓄積を自律的・順次世代交代で解消する。
2. **メモリ上限監視（Memory Watchdog / RSS・PSS Ceiling）の導入**:
   - Arbiter の Watchdog ループにおいて各ワーカーの PSS/RSS メモリ使用量を定期サンプリングし、設定された閾値（例: Web ワーカー `max_worker_memory_mb = 250.0MB`）を超過した場合に、Arbiter が自律的に新規ワーカーを先行補充（Pre-spawn）した上で肥大化ワーカーへ Graceful 退役シグナル (`SIGQUIT`) を送信する。

---

## 2. トレーサビリティ / Traceability
- [src/supervisor/config.py](../../src/supervisor/config.py): `PoolConfig`, `ServiceConfig`, `SupervisorConfig` メモリ上限・デフォルトTTL設定
- [src/supervisor/contracts.py](../../src/supervisor/contracts.py): `WorkerSpec` への `max_worker_memory_mb` 定義追加
- [src/supervisor/heartbeat.py](../../src/supervisor/heartbeat.py): ワーカーメモリ使用量サンプリングと上限超過判定
- [src/supervisor/arbiter.py](../../src/supervisor/arbiter.py): メモリ上限超過ワーカーのゼロダウンタイム自動ローテーションループ
- [src/supervisor/workers/base.py](../../src/supervisor/workers/base.py): ワーカー自律退役条件の評価
- [tests/supervisor/test_config.py](../../tests/supervisor/test_config.py): メモリ上限設定バリデーションテスト
- [tests/supervisor/test_heartbeat.py](../../tests/supervisor/test_heartbeat.py): メモリ監視メソッドのユニットテスト
- [tests/supervisor/test_arbiter.py](../../tests/supervisor/test_arbiter.py): メモリ上限超過時の自律ローテーション統合テスト

---

## 3. 脅威分析・制約事項 / Threat Analysis & Operational Constraints
1. **OOM Killer によるサービス全断 (CWE-400 / Availability Loss)**:
   - *脅威*: ワーカーがメモリリークや過大ペイロード処理により肥大化し、OS の OOM Killer が Arbiter や他重要プロセスを巻き込んで強制終了させる。
   - *緩和策*: Memory Watchdog により各ワーカーが安全閾値 (250MB) に達した時点で事前検知し、安全にローテーションする。
2. **ローテーション時の一斉再起動（サンダリングハード）**:
   - *脅威*: 全ワーカーが同一の TTL やリクエスト数で同時に終了し、リクエストの取りこぼしやレイテンシスパイクが発生する。
   - *緩和策*: `max_worker_lifetime_jitter` (±300s) および `max_requests_jitter` (±200) により、各ワーカーの退役タイミングを分散。
3. **ゼロダウンタイムの維持**:
   - *脅威*: 肥大化ワーカーを先に終了させてから新規ワーカーを起動すると、一時的なキャパシティ低下が発生する。
   - *緩和策*: Arbiter は先に新規ワーカーを `spawn_worker()` してプールに補充した上で、旧ワーカーへ `SIGQUIT` を送信する（Rolling Rotation パターン）。

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [src/supervisor/config.py](../../src/supervisor/config.py)
- [x] [src/supervisor/contracts.py](../../src/supervisor/contracts.py)
- [x] [src/supervisor/heartbeat.py](../../src/supervisor/heartbeat.py)
- [x] [src/supervisor/arbiter.py](../../src/supervisor/arbiter.py)
- [x] [src/supervisor/workers/base.py](../../src/supervisor/workers/base.py)
- [x] [tests/supervisor/test_config.py](../../tests/supervisor/test_config.py)
- [x] [tests/supervisor/test_heartbeat.py](../../tests/supervisor/test_heartbeat.py)
- [x] [tests/supervisor/test_arbiter.py](../../tests/supervisor/test_arbiter.py)

---

## 5. 根本原因と現状仕様の整理 / Current Behavior vs Expected
1. **現状 (Current Behavior)**:
   - `SupervisorConfig` / `PoolConfig` の `max_worker_lifetime` (TTL) はデフォルト `0.0` (無制限)。
   - `max_requests` はデフォルト `0` (無制限)。
   - メモリ上限に基づく自動退役機能（Memory Watchdog）は未実装。
   - そのため、Web ワーカーが一度肥大化すると、プロセスが自律的に終了・再生成されず常駐し続ける。
2. **期待動作 (Expected Behavior)**:
   - ステートレスワーカープール（Web 等）はデフォルトで 1 時間周期 (+ Jitter) または 2,000 リクエストごとに自動的かつ順次ローテーション再生成される。
   - ワーカーのメモリ使用量が規定値（250MB）を超えた場合、Arbiter Watchdog がそれを検知して先行補充 + Graceful ローテーションを実行し、常時健全なメモリフットプリント（< 100MB）を維持する。

---

## 6. 実装方針 / Implementation Plan
Target Branch: `feat/122-implement-supervisor-worker-memory-watchdog-and-default-rotation-ttl`

1. **`src/supervisor/config.py` & `contracts.py` の拡張**:
   - `PoolConfig`, `ServiceConfig`, `SupervisorConfig`, `WorkerSpec` に `max_worker_memory_mb: float` (デフォルト: Webプールは `250.0`, グローバルデフォルトは `0.0`) を追加。
   - デフォルトの Web プール設定において `max_worker_lifetime = 3600.0`, `max_worker_lifetime_jitter = 300.0`, `max_requests = 2000`, `max_requests_jitter = 200` を標準有効化。
2. **`src/supervisor/heartbeat.py` のメモリ監視メソッド実装**:
   - `get_worker_memory_mb(pid: int) -> float`: `/proc/<pid>/smaps_rollup` (PSS) または `/proc/<pid>/status` (VmRSS) からメモリ使用量 (MB) を高精度・低オーバーヘッドで取得。
   - `get_memory_exceeded_workers(spec_map: Dict[str, WorkerSpec]) -> List[int]`: 登録ワーカーのうち、対応する `WorkerSpec.max_worker_memory_mb > 0` かつ上限を超過している PID のリストを返却。
3. **`src/supervisor/arbiter.py` の自律ローテーション統合**:
   - Arbiter の定期監視ループ（`check_worker_memory()`）を追加。
   - メモリ超過ワーカーを検知した場合、該当プールに新規ワーカーを先行フォーク (`spawn_worker`) して `reloading_old_pids` に旧 PID を追加し、旧ワーカーへ `SIGQUIT` (または `SIGTERM`) を送信。
4. **自動テストの追加と品質ゲート検証**:
   - `tests/supervisor/test_config.py`: `max_worker_memory_mb` のバリデーションおよびデフォルト値テスト。
   - `tests/supervisor/test_heartbeat.py`: `get_worker_memory_mb` および `get_memory_exceeded_workers` の動作テスト。
   - `tests/supervisor/test_arbiter.py`: メモリ超過検知時にワーカーが先行補充されて安全にローテーションされる統合テスト。
   - 全体品質ゲート: `make format`, `make static_analysis` (Xenon Rank A, Mypy Strict), `pytest` 100% PASS。

---

## 7. 完了条件 / Success Criteria (DoD)
- [x] Web プール等のステートレスワーカーがデフォルトで 1 時間周期 (+ Jitter) および 2000 req (+ Jitter) で自律的・順次ローテーション再生成されること
- [x] ワーカーのメモリ使用量が `max_worker_memory_mb` (250MB) を超えた際に、Arbiter が検知してゼロダウンタイム（先行補充 + SIGQUIT）で新規ワーカーへ交代させること
- [x] `tests/supervisor/` にメモリ監視・自動ローテーションのユニットおよび統合テストが追加され、全テストが 100% PASS すること
- [x] 品質ゲート（`make format`, `make static_analysis` / Xenon Rank A, Mypy Strict）が 100% PASS すること


