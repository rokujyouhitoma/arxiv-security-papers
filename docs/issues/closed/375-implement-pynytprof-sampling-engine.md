---
ID: 375
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT/ENH] PyNYTProf 統計的サンプリングエンジン (SamplingEngine / SamplingProfiler) の実装 (Phase 7) (ID: 375)

## 1. 概要 / Summary

DSN-28（Python版NYTProf統合スイート設計仕様書）の Phase 7 として、本番稼働パイプラインの常時監視に対応する **+2% 未満** の超低オーバーヘッドを実現する統計的サンプリングエンジン（`src/core/profiler/sampling.py`）を実装する。

トレーシング方式（`sys.settrace` / `sys.monitoring`）はピンポイント計測に優れるが、本番の 4x daily バックグラウンド実行では +80〜200% のオーバーヘッドは許容できない。`SamplingEngine` は SIGPROF シグナル駆動サンプリングにより Perl 版 NYTProf の `mode=sampling` 相当の低インパクト常時監視を純粋 Python で実現する。

Triple-Engine 選択戦略:
| エンジン | オーバーヘッド目標 | 適用場面 |
|---------|-----------------|--------|
| PEP 669 (`sys.monitoring`) | +15〜80% | 開発時精密解析 (Python 3.12+) |
| `sys.settrace` | +50〜200% | 開発時精密解析 (Python 3.8〜3.11) |
| **SIGPROF サンプリング** | **+2% 未満** | **本番常時監視 (POSIX)** |
| **threading.Timer サンプリング** | **+5% 未満** | **本番常時監視 (Windows)** |

---

## 2. トレーサビリティ / Traceability

- 設計仕様書: [DSN-28-python_nytprof_profiler_and_visualization_suite.md](../designs/DSN-28-python_nytprof_profiler_and_visualization_suite.md) Section 4.5 (統計的サンプリングエンジン仕様)
- 関連 Issue: [369](closed/369-implement-pynytprof-core-profiling-engine-and-storage.md) (Phase 1), [373](closed/373-implement-pynytprof-cli-and-e2e.md) (Phase 5)
- 関連規格: DSN-10 Section 8 (Service Level Objectives — 5% SLA)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [src/core/profiler/sampling.py](../../src/core/profiler/sampling.py) (新規: サンプリングエンジン)
  - `SamplingEngine` — SIGPROF / threading.Timer 駆動コアエンジン
  - `SamplingProfiler` — コンテキストマネージャ API
- [x] [src/core/profiler/__init__.py](../../src/core/profiler/__init__.py) (更新: `SamplingEngine`, `SamplingProfiler` を `__all__` に追加)
- [x] [docs/issues/README.md](README.md) (Issue 台帳の同期)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/375-pynytprof-sampling-engine`

1. **`SamplingEngine` クラス (sampling.py)**:
   - `start()` — サンプリング開始（SIGPROF または threading.Timer を起動）
   - `stop()` → `ProfileData` — サンプリング停止・集計データ返却
   - `sample_count` プロパティ — 採取済みサンプル数

2. **SIGPROF モード (POSIX)**:
   - `signal.setitimer(ITIMER_PROF, interval, interval)` で定期発火
   - `_sigprof_handler` → `_capture_stack` → `_frame_to_parts` でスタック採取
   - スタックは `ProfileData.record_stack_trace(stack_str, time_ns)` に直接集計

3. **threading.Timer フォールバック (Windows / 全環境対応)**:
   - `threading.Timer(interval, _timer_callback)` でデーモンスレッド駆動
   - `sys._current_frames()` で全スレッドのフレームを一括採取
   - `_build_thread_stack(frame)` → セミコロン区切りスタック文字列を生成

4. **`SamplingProfiler` コンテキストマネージャ**:
   - `__enter__` → `engine.start()`
   - `__exit__` → `engine.stop()` + 任意の `output_file` への保存

5. **Xenon rank A 準拠**:
   - `stop()` → `_stop_engine()` / `_finalize_metadata()` に分割
   - `_capture_stack` → `_frame_to_parts()` を staticmethod に分離
   - `_capture_all_thread_stacks` → `_build_thread_stack()` を staticmethod に分離

---

## 5. 完了条件 / Success Criteria (DoD)

- [x] `src/core/profiler/sampling.py` が作成され、`SamplingEngine`, `SamplingProfiler` が使用可能であること
- [x] POSIX 環境で SIGPROF サンプリングが正常に動作し、`sample_count > 0` を返すこと
- [x] Windows / シグナル非対応環境で threading.Timer フォールバックが自動選択されること
- [x] 採取されたスタックが `ProfileData.stack_traces` に正しく集計され、Flame Graph 生成と互換であること
- [x] コンテキストマネージャ形式 (`with SamplingProfiler(...) as sp:`) が動作すること
- [x] `make py_compile` PASS（構文エラー 0 件）
- [x] `make static_analysis` PASS（xenon rank A + mypy strict 544 files 全件 PASS）
- [x] `docs/issues/README.md` の Closed 一覧に Issue 375 が登録済みであること
