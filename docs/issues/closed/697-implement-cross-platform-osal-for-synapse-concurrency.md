---
ID: 697
種別: Feature
優先度: Medium
ステータス: Closed
---

# [FEAT] Synapse 並行性ランタイム向けクロスプラットフォーム OSAL (OS Abstraction Layer) の設計と kqueue/IOCP 統合 (ID: 697)

## 1. 概要 / Summary
Synapse 並行性ランタイム（DSN-37）において現在 Linux 専用のシステムコール（`sys_clone`, `sys_futex`, `io_uring`）に直結している低レイヤ並行・同期・非同期 I/O 機構を疎結合化し、クロスプラットフォームで動作可能な **OSAL (OS Abstraction Layer)** を設計・実装する。

Linux における既存の最高速ゼロコピーパス（`sys_clone` 1:1 コアピニング、`sys_futex` 低レイテンシ休止/起床、`io_uring` ゼロシステムコール SQPOLL）のゼロオーバーヘッド性能を 100% 維持したまま、macOS（Darwin: `pthread` / `pthread_cond` / `kqueue`）および Windows（Win32: `CreateThread` / `WaitOnAddress` / `IOCP`）、さらに C バックエンド（Pass 160）環境に向けた統一的な OS 抽象化レイヤーを構築する。
これにより、Issue #695 (Windows MinGW/Wine) および Issue #696 (macOS Clang) で確立したマルチプラットフォーム基盤上で、Synapse デュアルプレーン並行モデル（M:N 軽量タスク、Shared-Nothing チャネル通信、プリエンプティブスケジューラ）を完全可搬（Portable）にする。

---

## 2. トレーサビリティ / Traceability
- **DSN-37**: §7.4 (物理マルチコア並列化と CPU 飽和アーキテクチャ), §7.4.1 (`sys_clone`), §7.4.2 (`sys_futex`), §7.4.3 (`io_uring`), §8.1 (Shared-Nothing 境界)
- **DSN-33-02**: §2.1 (Pass 160 Portable C Backend), §7.2 (クロスプラットフォーム検証)
- **関連 Issue**:
  - #675: Native Worker Pool & Threading Subsystem
  - #676: Linux Futex Primitives for Low-Latency Park/Unpark
  - #677: Linux io_uring Event Loop Integration
  - #692: AArch64 Context Switch & Mechanical Sympathy
  - #695: ULisp Portable C99 Backend Windows (MinGW/MSVC) 移植と Wine 実行検証
  - #696: ULisp Portable C99 Backend macOS (Clang) 対応および GitHub Actions CI マトリクス検証の確立

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/runtime/concurrency/osal.scm](../../ulisp/runtime/concurrency/osal.scm):
  - 新設：OSAL 統一インターフェース定義、プラットフォーム動的プローブ、および抽象ディスパッチテーブル
- [x] [ulisp/runtime/concurrency/thread.scm](../../ulisp/runtime/concurrency/thread.scm):
  - スレッド生成・終了・親和性設定（Affinity）の OSAL 経由へのリファクタリング（Linux `clone` / POSIX `pthread` / Win32 `CreateThread`）
- [x] [ulisp/runtime/concurrency/futex.scm](../../ulisp/runtime/concurrency/futex.scm):
  - 同期セルの抽象化と非 Linux 向けフォールバック（Linux `sys_futex` / POSIX `pthread_cond` / Win32 `WaitOnAddress`）
- [x] [ulisp/runtime/concurrency/io_uring.scm](../../ulisp/runtime/concurrency/io_uring.scm):
  - Linux `io_uring` を OSAL 非同期イベントループバックエンドとして登録・適応
- [x] [ulisp/runtime/concurrency/io_kqueue.scm](../../ulisp/runtime/concurrency/io_kqueue.scm):
  - 新設：macOS / BSD 向け `kqueue` / `kevent` 非同期 I/O イベントループバックエンド
- [x] [ulisp/backend/160_backend_c.scm](../../ulisp/backend/160_backend_c.scm):
  - C99 バックエンドにおける OSAL スレッド・条件変数・ポーリングランタイムプリミティブの生成
- [x] [ulisp/tests/test_concurrency_osal.scm](../../ulisp/tests/test_concurrency_osal.scm):
  - 新設：OSAL スレッド生成、Futex Park/Unpark、およびイベントループ通知のクロスプラットフォーム統合テストスイート
- [x] [ulisp/Makefile](../../ulisp/Makefile) & [Makefile](../../Makefile):
  - `make test_concurrency_osal` ターゲットの追加

---

## 4. 脅威モデルとセキュリティ検証 (Threat Model & Security Mitigation)

| 脅威項目 (Threat Vector) | 影響度 | 脆弱性メカニズム | 対策・緩和策 (Mitigation) |
| :--- | :---: | :--- | :--- |
| **CWE-833: Lost Wakeup によるデッドロック** | High | 休止直前と起床通知が競合した際、通知が消失してワーカーが永久休止状態に陥る。 | 3状態 CAS ステートマシン（`EMPTY=0`, `PARKED=1`, `NOTIFIED=2`）を OSAL 共通層で厳密に管理。休止システムコール突入直前に未処理通知の有無を不可分に再検査。 |
| **CWE-400: スレッドスピンによる CPU 資源過剰消費** | Medium | OS 間で待機実装が異なる場合にビジーウェイトを継続し、CPU 使用率 100% とキャッシュバス競合を誘発。 | Adaptive Backoff（適応型スピン休止: Pause 命令 $\to$ Yield $\to$ OSAL カーネル休止）を全 OS で統一適用。 |
| **CWE-119: イベント通知バッファの境界外アクセス** | High | イベントループの完了通知キュー（CQ / kevent 配列）のサイズ制限を超過した結果、隣接メモリ領域を破壊。 | イベントループ初期化時に最大エントリ数（`*osal-max-events*`）を上限固定し、リングバッファ境界のインデックスビットマスク走査を強制。 |
| **CWE-843: OSAL ハンドルの型混乱** | Medium | 不正な整数ポインタを `<osal-cell>` や `<osal-thread>` として扱い無効メモリアクセスが発生。 | レコード型検査（`osal-cell?`, `osal-thread?`）およびアラインメントチェック（64バイト境界）を事前検証。 |

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/697-implement-concurrency-osal`

### 5.1 OSAL 3大インターフェース仕様策定 (`ulisp/runtime/concurrency/osal.scm`)
1. **スレッド管理サブシステム (OSAL Threading)**:
   - `(%osal-thread-supported?)` $\to$ `#t` / `#f`
   - `(%osal-thread-spawn thunk name)` $\to$ `<osal-thread>`
   - `(%osal-thread-exit! code)` $\to$ 現在のスレッドを即時終了
   - `(%osal-thread-yield)` $\to$ CPU 譲渡
   - `(%osal-cpu-count)` $\to$ 有効 CPU コア数
   - `(%osal-set-affinity! thread-id core-id)` $\to$ コア固定（Linux / Windows 対応、macOS はアドバイザリ）

2. **軽量同期・待機サブシステム (OSAL Futex / Synchronization)**:
   - `(%osal-futex-supported?)` $\to$ `#t` / `#f`
   - `(%osal-futex-alloc-cell [init-val])` $\to$ `<osal-cell>` (64バイトアラインメント確保)
   - `(%osal-futex-free-cell! cell)` $\to$ メモリ解放
   - `(%osal-futex-get cell)` $\to$ 現在値の取得
   - `(%osal-futex-set! cell val)` $\to$ 値の格納
   - `(%osal-futex-cas! cell expected desired)` $\to$ 不可分比較置換
   - `(%osal-futex-wait! cell expected timeout-ms)` $\to$ 待機（Linux `sys_futex`, Windows `WaitOnAddress`, macOS/POSIX `pthread_cond`）
   - `(%osal-futex-wake! cell count)` $\to$ 起床通知

3. **非同期イベント通知サブシステム (OSAL Event Loop)**:
   - `(%osal-event-loop-create capacity)` $\to$ `<osal-event-loop>`
   - `(%osal-event-register-read loop fd user-data)` $\to$ 読込監視登録
   - `(%osal-event-register-write loop fd user-data)` $\to$ 書込監視登録
   - `(%osal-event-poll loop max-events timeout-ms)` $\to$ 完了イベントリスト `((user-data . result) ...)`
   - `(%osal-event-loop-close! loop)` $\to$ ループ終了

### 5.2 各 OS バックエンドの実装と接続
1. **Linux バックエンド**:
   - `sys_clone` (syscall 56), `sys_futex` (syscall 202), `io_uring` (syscall 425+) の既存ネイティブパスをそのまま OSAL プロバイダとして登録。ゼロオーバーヘッドを担保。
2. **macOS (Darwin) バックエンド (`io_kqueue.scm`)**:
   - `kqueue` / `kevent` による高機能イベント監視。
   - `pthread_create` / `pthread_cond_wait` によるスレッド待機。
3. **Windows バックエンド**:
   - `CreateThread` / `ExitThread` / `SetThreadAffinityMask`。
   - `WaitOnAddress` / `WakeByAddressSingle`（Win8+）による Futex 等価動作。
   - `IOCP` / `WSAPoll` イベントループ。
4. **C バックエンド (Pass 160) 共通ランタイム**:
   - C レベルでの POSIX `pthread` / Win32 API 抽象化ラッパーを自動出力。

### 5.3 テストスイートの構築 (`ulisp/tests/test_concurrency_osal.scm`)
- **スレッドライフサイクル検証**: スレッド起動、引数受渡し、戻り値、正常終了の検証。
- **Futex CAS & Park/Unpark 検証**: 複数ワーカー間での排他ロックおよび起床通知（Lost Wakeup 0件）。
- **非同期イベントループ検証**: パイプ（またはソケットペア）に対する非同期書込・読込通知の正確性検証。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] **OSAL 抽象レイヤー新設**:
  - `ulisp/runtime/concurrency/osal.scm` が整備され、スレッド・同期・イベントループの 3 大インターフェースが定義されていること。
- [x] **プラットフォーム適合性**:
  - Linux では既存の `io_uring` / `futex` / `clone` パスが速度劣化なく動作すること。
  - macOS (Darwin) 環境で `kqueue` / `pthread` 経路による非同期通知および待機が機能すること。
  - Windows 環境で `WaitOnAddress` / `CreateThread` 経路が機能すること。
- [x] **デッドロック耐性 (CWE-833)**:
  - 10,000 回の連続 Park/Unpark ストレステストにおいて Lost Wakeup による停止が発生しないこと。
- [x] **単体・統合テスト 100% PASS**:
  - `make test_concurrency_osal` が追加され、全テストケースが無エラーで通過すること。
- [x] **相対パス完全準拠**:
  - 本ファイルおよび関連ファイルにおいて絶対パスリンクが 0 件であること。
