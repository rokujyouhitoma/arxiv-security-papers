---
ID: 793
種別: Bug
優先度: Low
ステータス: Closed (Resolved)
---

# [BUG/SEC] スケジューラの最大タスク上限 (scheduler-max-tasks) 判定における累積値から生存タスク数への修正 (ID: 793)

## 1. 概要 / Summary

Synapse 並行ランタイムのスケジューラ（`ulisp/runtime/concurrency/scheduler.scm`）において、タスク生成（`scheduler-spawn!`）時の同時実行数上限判定が、「現在生存・実行中のタスク数（live tasks）」ではなく「累積タスク生成数（`scheduler-tasks-spawned`）」と比較されている重大な設計不備を修正する。

`*scheduler-max-tasks*`（デフォルト: 10,000,000）は本来、DoS 攻撃やリソース枯渇（CWE-400: Uncontrolled Resource Consumption）を防ぐために「同時にアクティブに存在できる最大並行タスク数」を制限する目的で導入されたガードである。しかし、現行の実装では単調増加する累積生成カウンター `scheduler-tasks-spawned` と比較されているため、タスクが正常終了（`task-exit!` / `'completed`）または異常終了（`panic` / `'failed`）してもカウンターが減算されない。

この結果、正常に短時間のタスク生成・完了を繰り返す長寿命サービスや高頻度バッチ処理、Supervisor 管理下のアクターシステムであっても、累積稼働回数が上限に到達した瞬間に全 `scheduler-spawn!` が恒久的に拒絶（`scheduler-spawn!: maximum spawned tasks limit exceeded (CWE-400)`）され、Supervisor による子プロセスの再起動も不能となってシステム全体が完全停止（Denial of Service）に陥る。

### 脅威モデル分析 (STRIDE / CWE)
- **STRIDE 分類**: Denial of Service (DoS)
- **CWE 分類**: CWE-400 (Uncontrolled Resource Consumption / Improper Resource Exhaustion Handling)
- **脅威シナリオ**:
  - 攻撃者が多数の正当な短命リクエスト（HTTP リクエストハンドラ、バッチクエリ、軽量マイクロタスク等）を反復送出し、スケジューラの累積タスク生成数を増加させる。
  - 同時アクティブタスク数が 0〜1 個のアイドル状態であっても累積上限に達した時点でスケジューラがロックし、以降の全タスク投入および Supervisor 子タスク自動復旧が拒絶され、サービス停止に至る。
- **セキュリティ要件**:
  - `*scheduler-max-tasks*` は「現在並行に生存しているアクティブタスク数（Concurrent Live Tasks）」に対して適用されなければならない。
  - 累積タスク生成数（`tasks-spawned`）は可観測性・監査ログ・メトリクス用途としてそのまま単調増加で保持し、新たにアトミックな生存タスクカウンター（`live-tasks`）を導入して分離・管理する。

### 再現手順 / Steps to Reproduce
1. スケジューラを生成し、`*scheduler-max-tasks*` に小さな上限値（例: 3）を設定する。
2. 短時間のタスクを順次生成・実行・完了させる（例: 3 回連続で `scheduler-spawn!` $\to$ `scheduler-run!`）。
3. 3 個のタスクがすべて完了して生存タスク数が 0 に戻っている状態において、4 個目のタスクを `scheduler-spawn!` する。
4. **現行挙動**: 累積タスク数 3 が上限 3 に達しているため、エラー `scheduler-spawn!: maximum spawned tasks limit exceeded (CWE-400)` が発生し拒絶される。
5. **期待挙動**: 生存タスク数は 0 であるため、4 個目のタスクが正常に投入・実行できること。

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [ulisp/runtime/concurrency/scheduler.scm](../../ulisp/runtime/concurrency/scheduler.scm) - スケジューラ統計ベクタ拡張（3要素 $\to$ 4要素）、`scheduler-live-tasks` / `%scheduler-live-tasks-inc!` / `%scheduler-live-tasks-dec!` 実装、`scheduler-spawn!` 判定の変更、タスク完了・異常終了時のデクリメント接続
- [x] [ulisp/lib/ulisp/concurrency/scheduler.sld](../../ulisp/lib/ulisp/concurrency/scheduler.sld) - `scheduler-live-tasks` および `scheduler-total-live` のエクスポート宣言
- [x] [tests/concurrency/test_scheduler.scm](../../tests/concurrency/test_scheduler.scm) - Group 3b 統計検証および Group 6/8 における生存タスク数に基づく CWE-400 境界検証単体テスト追加
- [x] [docs/issues/README.md](README.md) - Issue 台帳のステータス更新 (`Closed`)

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis

`ulisp/runtime/concurrency/scheduler.scm` の該当実装箇所において以下の構造的欠陥が存在する：

1. **統計ベクタの要素不足**:
   ```scheme
   (define (%make-scheduler-stats)
     (let ((s (make-vector 3)))
       (vector-set! s 0 (make-atomic-box 0)) ;; tasks-spawned (累積)
       (vector-set! s 1 (make-atomic-box 0)) ;; tasks-completed (累積)
       (vector-set! s 2 (make-atomic-box 0)) ;; tasks-failed (累積)
       s))
   ```
   現在並行して生存・実行中のタスク数を表すスロットが存在しない。

2. **`scheduler-spawn!` における誤った累積値判定**:
   ```scheme
   (let ((sp-cnt (scheduler-tasks-spawned sched)))
     (if (>= sp-cnt *scheduler-max-tasks*)
         (error "scheduler-spawn!: maximum spawned tasks limit exceeded (CWE-400)" sp-cnt)
         (let ((normalized (%normalize-task-context task)))
           (%scheduler-tasks-spawned-inc! sched)
           ...)))
   ```
   `scheduler-tasks-spawned` は単調増加する累積値であるため、終了タスクの解放が反映されない。

3. **タスク終了処理における生存タスク減算の欠落**:
   `%scheduler-run-and-record!` において、タスクの正常完了時（`tasks-completed` 加算）およびパニック・例外発生時（`tasks-failed` 加算）のいずれの経路においても、生存タスク数を減算する処理が呼び出されていない。

---

## 4. 恒久対策 / Permanent Fix

1. **スケジューラ統計ベクタの 4 スロット化**:
   - スロット 0: `tasks-spawned`（累積投入タスク数、単調増加）
   - スロット 1: `tasks-completed`（累積正常完了タスク数、単調増加）
   - スロット 2: `tasks-failed`（累積異常終了タスク数、単調増加）
   - スロット 3: `live-tasks`（現在アクティブな生存タスク数、並行アトミック加減算）

2. **生存タスク操作 API の新設**:
   - `(scheduler-live-tasks sched)`: 現在の生存タスク数をアトミックに取得。
   - `(scheduler-total-live sched)`: `scheduler-live-tasks` の別名（エイリアス）。
   - `(%scheduler-live-tasks-inc! sched)`: `atomic-fetch-add!` による +1 アトミック加算。
   - `(%scheduler-live-tasks-dec! sched)`: `atomic-fetch-add!` による -1 アトミック減算。

3. **`scheduler-spawn!` のガード修正**:
   - `(let ((live-cnt (scheduler-live-tasks sched))) (if (>= live-cnt *scheduler-max-tasks*) ...))` に変更。
   - スポーン成功時に `(%scheduler-tasks-spawned-inc! sched)` と `(%scheduler-live-tasks-inc! sched)` の双方を実行。

4. **タスク終了時の減算フック接続**:
   - `%scheduler-run-and-record!` の完了・失敗分岐双方において、`(%scheduler-live-tasks-dec! sched)` を即座に実行。
   - `%scheduler-stats-reset!` においてスロット 3 も 0 に初期化。
   - `scheduler-stats` の戻り値 alist に `(cons 'live-tasks (scheduler-live-tasks sched))` を追加。

5. **ライブラリ公開と型・安全性ガード**:
   - `(ulisp concurrency scheduler)` のエクスポートリストに `scheduler-live-tasks` と `scheduler-total-live` を追加。
   - 非スケジューラオブジェクトが渡された場合の CWE-843 型検査を厳格に保持。

---

## 5. 実装方針 / Implementation Plan

Target Branch: `fix/793-scheduler-live-tasks-limit`

### Step 1: ブランチ作成
- Git ブランチ `fix/793-scheduler-live-tasks-limit` を `main` より分岐作成。

### Step 2: スケジューラ本体 (`scheduler.scm`) の修正
- `ulisp/runtime/concurrency/scheduler.scm`:
  - `%make-scheduler-stats`: ベクタ長を 4 に拡張し、インデックス 3 に `(make-atomic-box 0)` を設定。
  - `(scheduler-live-tasks sched)` および `(scheduler-total-live sched)` を定義（CWE-843 ガード付き）。
  - `(%scheduler-live-tasks-inc! sched)` および `(%scheduler-live-tasks-dec! sched)` を定義。
  - `%scheduler-stats-reset!`: インデックス 3 も 0 にリセット。
  - `scheduler-spawn!`:
    - 上限比較を `(scheduler-live-tasks sched)` に変更。
    - 成功時に `(%scheduler-tasks-spawned-inc! sched)` と `(%scheduler-live-tasks-inc! sched)` を呼び出し。
  - `%scheduler-run-and-record!`:
    - 正常完了・パニック終了の双方で `(%scheduler-live-tasks-dec! sched)` を実行。
  - `scheduler-stats`: `(cons 'live-tasks (scheduler-live-tasks sched))` を alist に追加。

### Step 3: R7RS ライブラリ仕様 (`scheduler.sld`) の更新
- `ulisp/lib/ulisp/concurrency/scheduler.sld`:
  - `export` に `scheduler-live-tasks` と `scheduler-total-live` を追加。

### Step 4: 単体テストスイート (`test_scheduler.scm`) の拡充
- `tests/concurrency/test_scheduler.scm`:
  - Group 3b（統計カウンタ検証）に `scheduler-live-tasks` の初期値 0、タスク投入時の 1、実行完了後の 0 復帰、リセット動作の検証アサーションを追加。
  - Group 6（セキュリティ・境界ガード）に Issue 793 専用テストケースを追加：
    - 一時的に `*scheduler-max-tasks*` を 3 に設定。
    - 3 個のタスクを投入し、4 個目の投入が CWE-400 で正しく拒絶されることを検証。
    - スケジューラを実行して 3 個のタスクを完了させ、`live-tasks` が 0 に戻ることを確認。
    - `tasks-spawned` が 3（上限値と同一）のまま、4 個目のタスク投入が今度は正常に成功することを検証。
    - `*scheduler-max-tasks*` を元の 10,000,000 に復元。

### Step 5: 品質ゲート検証とコミット
- `make -C ulisp lint_sexpr`
- `make -C ulisp test_scheduler`
- `make -C ulisp test_multithread_scheduler`
- `make verify_quality`
- すべて 100% PASS を確認後、Conventional Commits 形式でコミットし、PR / マージを実施。

---

## 6. 完了条件 / Success Criteria (DoD)

- [x] **生存タスク数の正確な追跡**:
  - `scheduler-live-tasks` がタスク投入時に正確に +1 され、実行終了時（正常完了およびパニック異常終了の双方）に確実に -1 されること。
- [x] **累積値と生存値の明確な分離**:
  - `scheduler-tasks-spawned` は単調増加を維持し、`scheduler-live-tasks` は現在のアクティブタスク数を正確に反映すること。
- [x] **長寿命システムにおける DoS (CWE-400) 回避実証**:
  - 累積タスク生成数が上限値に達した状態であっても、現在の生存タスク数が上限未満であれば後続タスクの spawn が拒絶されず正常に動作すること。
- [x] **同時実行タスク数超過時の適正な拒絶**:
  - 現在アクティブな生存タスク数が上限値に達している瞬間には、新規 spawn が適切に CWE-400 エラーで拒絶されること。
- [x] **R7RS ライブラリ整合性**:
  - `ulisp/lib/ulisp/concurrency/scheduler.sld` から `scheduler-live-tasks` および `scheduler-total-live` が正常にエクスポートされていること。
- [x] **全品質ゲートの完全通過**:
  - `make -C ulisp lint_sexpr` が全ファイルで括弧完全一致（100% balanced）であること。
  - `make -C ulisp test_scheduler` が全アサーション合格（201 passed, 0 failed）すること。
  - `make -C ulisp test_multithread_scheduler` が全アサーション合格（72 passed, 0 failed）すること。
  - `make verify_quality` が 100% PASS すること（2,766 passed, 83.15% coverage）。
