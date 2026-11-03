---
ID: 697
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT] Synapse 並行性ランタイム向けクロスプラットフォーム OSAL (OS Abstraction Layer) の設計と kqueue/IOCP 統合 (ID: 697)

## 1. 概要 / Summary
現在 Linux 専用となっている Synapse 並行性ランタイムの低レベル機能（`io_uring` による非同期 I/O、`futex` によるスレッド待機/起床、`sys_clone` による物理スレッド生成）を抽象化する **OSAL (OS Abstraction Layer)** を設計・実装する。
macOS / BSD 向けの `kqueue` / `pthread`、および Windows 向けの `IOCP` / `WaitOnAddress` へのフォールバック経路を整備し、全 OS 上で Synapse の並行タスクモデルがポータブルに機能する土台を確立する。

---

## 2. トレーサビリティ / Traceability
- **DSN-37**: §7.4 (Low-Level Concurrency Architecture)
- **関連 Issue**: #675 (Native Worker Pool), #676 (Futex Primitives), #677 (io_uring Event Loop), #692 (AArch64 Context Switch)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/runtime/concurrency/boundary.scm](../../ulisp/runtime/concurrency/boundary.scm): OSAL インターフェース定義と OS 判別ディスパッチ
- [ ] [ulisp/runtime/concurrency/io_kqueue.scm](../../ulisp/runtime/concurrency/io_kqueue.scm): macOS / BSD 向け kqueue イベントループ
- [ ] [ulisp/runtime/concurrency/futex.scm](../../ulisp/runtime/concurrency/futex.scm): 非 Linux 環境向け POSIX / Win32 同期フォールバック

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/697-implement-concurrency-osal`

1. OS 抽象化境界（OSAL）のインターフェース策定：
   - 非同期イベント通知: `%osal-event-init`, `%osal-event-poll`, `%osal-event-submit`
   - スレッド待機・起床: `%osal-park-wait`, `%osal-unpark-wake`
   - スレッド生成: `%osal-thread-spawn`, `%osal-thread-exit`
2. 各 OS 実装モジュールの整備：
   - Linux: `io_uring` + `futex`（最高速ゼロコピーパス）
   - macOS / BSD: `kqueue` + `pthread_cond`
   - Windows: `IOCP` + `WaitOnAddress`
3. C バックエンドおよび POSIX 共通テストハーネスによる複数 OS 上での動作検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 非 Linux 環境（macOS / Windows）でも Synapse 並行性ランタイムがビルドおよび初期化できること。
- [ ] タスクの非同期 I/O 待機および起床が `kqueue` / `IOCP` またはフォールバック機構を介して正常に完了すること。

