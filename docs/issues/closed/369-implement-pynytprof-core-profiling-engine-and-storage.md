---
ID: 369
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT/ENH] PyNYTProf コア計測エンジンおよび整数ナノ秒Tickストリーミングストレージの実装 (ID: 369)

## 1. 概要 / Summary
DSN-28（Python版NYTProf統合スイート設計仕様書）の Phase 1 として、Python 3.12+ の PEP 669 (`sys.monitoring`) およびレガシー互換の `sys.settrace` を抽象化・統合したデュアル計測エンジン（`ProfilerEngine`）と、整数ナノ秒精度（`time.perf_counter_ns`）で Exclusive / Inclusive 時間を加算・蓄積し、zlib 圧縮で高速ストリーミング永続化するストレージ層（`ProfileStorage`）をゼロ外部依存の Pure Python で実装する。

---

## 2. トレーサビリティ / Traceability
- 設計仕様書: [DSN-28-python_nytprof_profiler_and_visualization_suite.md](../designs/DSN-28-python_nytprof_profiler_and_visualization_suite.md) Section 4 (コア計測エンジン仕様)
- 関連仕様: PEP 669 (Low Impact Monitoring for CPython)
- 関連設計: `DSN-02` (Low-Level Architecture), `DSN-10` (Observability & Evaluation Framework)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [src/core/profiler/__init__.py](../../src/core/profiler/__init__.py) (新規: 公開インターフェース)
- [x] [src/core/profiler/engine.py](../../src/core/profiler/engine.py) (新規: PEP 669 / sys.settrace デュアル計測エンジン)
- [x] [src/core/profiler/storage.py](../../src/core/profiler/storage.py) (新規: 整数ナノ秒集計・コールストリーム・zlib バイナリストレージ)
- [x] [tests/core/test_pynytprof_engine.py](../../tests/core/test_pynytprof_engine.py) (新規: 決定論的検証テストスイート)
- [x] [docs/issues/README.md](README.md) (Issue台帳の同期)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/369-pynytprof-core-engine`

1. **データ構造の定義 (`storage.py`)**:
   - `CallArcKey`: `(caller: str, callee: str)`
   - `ArcMetric`: `call_count: int`, `inclusive_time_ns: int`, `exclusive_time_ns: int`
   - `LineMetric`: `exec_count: int`, `exclusive_time_ns: int`
   - `ProfileData`: メタデータ（日時、ホスト、Pythonバージョン、コマンド等）、ファイル別行メトリクス、Arc メトリクス、コールイベントリスト。
   - `ProfileStorage`: コンパクトバイナリ/JSON+zlib シリアライザ、`all_stacks_by_time.calls` ストリーム生成。

2. **デュアル計測エンジンの実装 (`engine.py`)**:
   - `ProfilerEngine`:
     - Python 3.12+ の判定および `sys.monitoring` API の登録（`PY_START`, `PY_RETURN`, `PY_UNWIND`, `LINE`, `C_START`, `C_RETURN`）。
     - Python 3.8〜3.11 環境における `sys.settrace()` 互換トレーサ。
     - コールスタックフレーム管理: `[CallFrame(sub_name, entry_time_ns, children_time_ns)]`。
     - 整数ナノ秒精度での Exclusive / Inclusive 時間の計算:
       $$\text{inclusive} = \text{exit\_time} - \text{entry\_time}$$
       $$\text{exclusive} = \text{inclusive} - \text{children\_time}$$
     - 組み込み関数・C拡張の `CORE:<name>` プレフィックス付与。
     - 呼出・復帰時の `calls_mode`（0: off, 1: returns, 2: calls+returns）制御。

3. **コンテキストマネージャ・デコレータ API (`__init__.py`)**:
   - `Profiler`: `with Profiler(...) as p:` コンテキストマネージャ。
   - `@profile`: 関数デコレータ。
   - `pynytprof_enable()`, `pynytprof_disable()`, `pynytprof_finish()` API。

4. **テストスイートの構築 (`test_pynytprof_engine.py`)**:
   - 再帰関数（Fibonacci 等）でのスタック深度・時間計算の整合性。
   - 例外送出時（`try/except`）のスタックアンワインド検証。
   - 行単位計測（`lines=True`）の正確性。
   - 浮動小数点丸め誤差 0% の検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `src/core/profiler/` ディレクトリ配下にコアエンジンおよびストレージモジュールが配置され、ゼロ外部依存（標準ライブラリのみ）で動作すること。
- [ ] 整数ナノ秒（`perf_counter_ns`）により、サブルーチンの Inclusive/Exclusive 時間が計算逆転せず加算集計されること。
- [ ] 再帰呼び出しおよび例外発生時のスタックトラッキングが壊れないこと。
- [ ] `tests/core/test_pynytprof_engine.py` の全テストが 100% パスすること。
- [ ] `make py_compile` およびリポジトリ品質ゲートを完全パスすること。
