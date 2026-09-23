---
ID: 377
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT/ENH] PyNYTProf asyncio コルーチン対応・Await待機時間分離・マルチタスク追跡 (Phase 9) (ID: 377)

## 1. 概要 / Summary

DSN-28（Python版NYTProf高精度プロファイラ統合スイート設計仕様書）の Phase 9 として、`asyncio` コルーチンのライフサイクル（呼び出し、中断・再開、Await待機時間）を高精度に識別・追跡し、**CPU 実行時間と I/O 待機時間（`suspend_time_ns`）を完全分離**する計測エンジン拡張を実装する。

従来のトレーサでは、コルーチンが `await` で中断している間の時間が親フレームやコルーチンの Exclusive/Inclusive 時間に混入し、CPU ボトルネックと I/O 待機時間の判別が不可能であった。
本実装により、`asyncio.current_task()` やタスク識別子に基づき、タスク別のスタック追跡と `suspend_time_ns` の独立計上を実現する。

---

## 2. トレーサビリティ / Traceability

- 設計仕様書: [DSN-28-python_nytprof_profiler_and_visualization_suite.md](../designs/DSN-28-python_nytprof_profiler_and_visualization_suite.md)
  - Section 4.1 (PEP 669 / sys.settrace ハイブリッド追跡層・asyncio コルーチン対応)
  - Section 9.2 (フェーズ一覧 Phase 9: asyncio コルーチン対応、SUSPEND_TIME_NS 計上)
- 関連 Issue:
  - [369](369-implement-pynytprof-core-profiling-engine-and-storage.md) (Phase 1: コア計測エンジン)
  - [375](375-implement-pynytprof-sampling-engine.md) (Phase 7: サンプリングエンジン)
  - [376](376-implement-pynytprof-diff-sampling-cli-and-test-suite.md) (Phase 8: CLI 差分統合 ＆ 品質ゲート)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [src/core/profiler/storage.py](../../src/core/profiler/storage.py) (`SubroutineMetric` に `suspend_time_ns` フィールド追加、シリアライズ対応)
- [x] [src/core/profiler/engine.py](../../src/core/profiler/engine.py) (`CallFrame` に `task_id`, `is_coroutine` 追加、コルーチンの中断・再開検知と `suspend_time_ns` 計上、タスク別スタック分離)
- [x] [tests/core/test_pynytprof_asyncio.py](../../tests/core/test_pynytprof_asyncio.py) (新規: asyncio コルーチン計測テスト)
- [x] [docs/issues/README.md](../issues/README.md) (Issue 台帳の同期)
- [x] [docs/designs/DSN-28-python_nytprof_profiler_and_visualization_suite.md](../designs/DSN-28-python_nytprof_profiler_and_visualization_suite.md) (フェーズ表更新)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/377-pynytprof-asyncio-coroutine-profiling`

1. **`SubroutineMetric` および `storage.py` 拡張**:
   - `SubroutineMetric` に `suspend_time_ns: int = 0` を追加。
   - `record_subroutine_exit` に `suspend_ns: int = 0` 引数を追加し累積加算。
   - JSON シリアライズ/デシリアライズ時の下位互換性を 100% 保持（デフォルト値 0）。

2. **`CallFrame` 拡張 (`engine.py`)**:
   - `task_id: Optional[int] = None`（`id(asyncio.current_task())` または 0）
   - `is_coroutine: bool = False`（`inspect.iscoroutinefunction` またはコードフラグ `CO_COROUTINE`）
   - `suspend_start_ns: int = 0`
   - `accumulated_suspend_ns: int = 0`

3. **コルーチン中断・再開ライフサイクル追跡 (`engine.py`)**:
   - `_get_current_task_id()` ヘルパー: `asyncio._get_running_loop()` が存在する場合に `asyncio.current_task()` の ID を取得。
   - 複数タスクが並行して実行される場合でも、タスク識別子に基づきスタックを整流。
   - コルーチンが一時中断される際（Await 待機突入時）、中断開始時刻 `suspend_start_ns` を記録。
   - 再開時に `suspend_delta = now_ns - suspend_start_ns` を算出し、`accumulated_suspend_ns` に加算。
   - コルーチン完全終了時に `suspend_time_ns` として `profile_data` に記録。

4. **単体テスト (`tests/core/test_pynytprof_asyncio.py`)**:
   - `asyncio.sleep(0.05)` を伴う非同期関数のプロファイル検証。
   - CPU 処理時間（Exclusive Time）は小さく、`suspend_time_ns` に sleep 待機時間（~50ms）が計上されることをアサート。
   - `asyncio.gather()` による複数コルーチンの並行実行時のスタック整合性・リーク 0 件検証。

---

## 5. 完了条件 / Success Criteria (DoD)

- [x] `SubroutineMetric` に `suspend_time_ns` が追加され、互換性を維持して保存・読み込み可能であること
- [x] 非同期コルーチン (`async def`) のプロファイリング時にスタックリークが発生しないこと
- [x] `asyncio.sleep` 等の待機時間が `suspend_time_ns` として記録されること
- [x] `tests/core/test_pynytprof_asyncio.py` が PASS すること
- [x] `make py_compile` PASS
- [x] `make static_analysis` PASS (xenon rank A, mypy strict)
- [x] `docs/issues/README.md` に反映されていること
