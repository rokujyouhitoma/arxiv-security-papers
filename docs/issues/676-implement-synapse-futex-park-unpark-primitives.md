---
ID: 676
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] Linux SYS_futex に基づくワーカー待機 (Park) およびチャネル起床 (Unpark) による省電力・低遅延同期機構の実装 (ID: 676)

## 1. 概要 / Summary
現在の Synapse スケジューラにおけるタスク枯渇時のバックオフ処理（`%scheduler-idle-backoff!`）は 64 回のビジースピンループを行っている。
マルチコア並行環境下で仕事のないワーカーがスピンを続けると、CPU コアの無駄な電力消費とメモリバスのキャッシュコヒーレンシ帯域（Cache Invalidation / Snoop Traffic）を激しく圧迫し、実行中ワーカーのメモリアクセス性能を著しく低下させる。
Linux カーネルの `SYS_futex`（`FUTEX_WAIT` / `FUTEX_WAKE`）を活用した OS レベルの待機（Park）および起床（Unpark）プリミティブを実装し、タスク枯渇ワーカーを即座に省電力スリープさせ、チャネルメッセージ送信や新規タスク生成時にマイクロ秒未満で即時起床させる極限の同期制御基盤を確立する。

---

## 2. トレーサビリティ / Traceability
- 関連設計書: [DSN-37 ホスト・カーネル分離型 階層 CSP/アクター並行処理基盤](../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md)
- 関連 Issue:
  - [Issue #633 (第一級 P2P チャネル)](closed/633-implement-synapse-first-class-p2p-channel.md)
  - [Issue #635 (M:N ワークスティーリングスケジューラ)](closed/635-implement-synapse-work-stealing-scheduler.md)
  - [Issue #675 (物理マルチコア並列実行エンジン)](675-implement-synapse-native-multithread-worker-pool.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/runtime/concurrency/futex.scm](../../ulisp/runtime/concurrency/futex.scm)
- [ ] [ulisp/runtime/concurrency/futex.s](../../ulisp/runtime/concurrency/futex.s)
- [ ] [ulisp/lib/ulisp/concurrency/futex.sld](../../ulisp/lib/ulisp/concurrency/futex.sld)
- [ ] [ulisp/runtime/concurrency/scheduler.scm](../../ulisp/runtime/concurrency/scheduler.scm)
- [ ] [ulisp/runtime/concurrency/channel.scm](../../ulisp/runtime/concurrency/channel.scm)
- [ ] [tests/concurrency/test_futex.scm](../../tests/concurrency/test_futex.scm)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/676-futex-park-unpark-primitives`

1. **Futex システムコールラッパー (`futex.s`, `futex.scm`)**:
   - AMD64 Linux システムコール番号 202 (`SYS_futex`) を直接発行するネイティブ手続きの実装。
   - `(futex-wait u32-addr val timeout)`: `FUTEX_WAIT_PRIVATE` 操作によるスレッド待機。
   - `(futex-wake u32-addr count)`: `FUTEX_WAKE_PRIVATE` 操作による指定スレッド数の起床。
2. **ワーカー Park / Unpark 制御 (`scheduler.scm`)**:
   - 各ワーカーに 32bit futex 単語スロット（状態: `RUNNING` / `PARKED` / `NOTIFIED`）を配置。
   - スティール試行が全て失敗しタスクが見つからない場合、ワーカーは `FUTEX_WAIT` でスリープ。
   - チャネルへのメッセージ投入（`channel-send!`）や `scheduler-spawn!` 時に、待機中のワーカーに対して `FUTEX_WAKE` を発行して起床。
3. **テスト検証**:
   - 待機状態のスレッドがビジーループせず CPU 使用率 0% で休止することを確認。
   - 起床通知が届いた瞬間に遅延なく再開し、タスクを消化することを検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `SYS_futex` による `futex-wait` および `futex-wake` が正常に機能すること。
- [ ] タスク不在時にワーカーが休止し、無駄な CPU スピンおよびバス帯域消費が停止すること。
- [ ] チャネル送信およびタスク投入時に休止中ワーカーが即座に起床すること。
- [ ] `make -C ulisp test_futex` および既存並行テストが 100% PASS すること。
- [ ] 相対パス規則（Gate 3）の完全適合（絶対パス 0 件）。
