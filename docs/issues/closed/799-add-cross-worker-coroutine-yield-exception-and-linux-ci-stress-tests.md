---
ID: 799
種別: Feature
優先度: Medium
ステータス: Closed
---

# [FEAT/TEST] クロスワーカー環境におけるコルーチン yield 後例外テスト拡充および Linux 実機 CI 検証環境の確立 (ID: 799)

## 1. 概要 / Summary
Issue #787（コルーチン yield 後の例外ハンドラ連鎖復元）および Issue #791（並行スケジューラ上での Supervisor・コルーチン結合テスト Group 11）において、マルチ OS スレッド環境での基本結合テストが導入された。
しかし、現存するテストは以下の 2 つのパターンに限定されており、実運用上最も過酷なシナリオが未網羅のまま残されている：
1. **Group 9 (`test_multithread_scheduler.scm`)**: ワーカー 0 で yield したコルーチンを、別ワーカーへ手動で再ディスパッチし、再開側の thunk 内で明示的 `guard` でキャッチする（スケジューラ・Supervisor の自動障害復旧パスを介さない）。
2. **Group 11 (`test_multithread_scheduler.scm`)**: Supervisor 配下のコルーチン子タスクが yield 中断している最中に、外部から `task-exit!` を直接発行して停止させる（コルーチン内部からの未処理例外発生ではない）。

そのため、「ワーカー A で実行開始・`yield` したコルーチン子タスクが、ワークスチールによりワーカー B へ移動（Migration）して再開（`context-resume!`）され、その実行コンテキスト内部で直接未処理例外（例: `(car '())`）を発生させたケース」において、ワーカー B のスタック上の境界ハンドラ（`with-synapse-task-boundary`）が正しくスタックを巻き戻し、Supervisor へ `DOWN` シグナルを配送して新規コルーチンとして再起動・完走させるという、真のエンドツーエンド耐障害性実機テストが未網羅である。

また、開発環境が macOS arm64 に偏ると Linux x86-64 固有のアセンブリ・スタックフレーム挙動（Thread / TLS / Futex）の回帰検知が遅れるリスクがある。
本 Issue では、クロスワーカーでの再開・例外発生・Supervisor 自動復旧テストスイート（Group 12）を追加するとともに、Linux CI / コンテナ上で自動実行される高負荷並行ストレステスト（`make test_concurrency_stress`）を確立する。

---

## 2. トレーサビリティ / Traceability
- 関連 Issue:
  - [787-fix-coroutine-exception-handler-chain-restore-after-yield.md](closed/787-fix-coroutine-exception-handler-chain-restore-after-yield.md) (TCB ヘッダ境界ハンドラスロットおよびアセンブリ復元)
  - [791-add-parallel-integration-tests-for-supervisor-and-coroutines.md](closed/791-add-parallel-integration-tests-for-supervisor-and-coroutines.md) (マルチスレッド Supervisor & コルーチン結合テスト Group 10/11)
  - [798-fix-supervisor-idle-state-transition-race-condition.md](closed/798-fix-supervisor-idle-state-transition-race-condition.md) (Supervisor post-boundary hook による多重複入防止)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [tests/concurrency/test_multithread_scheduler.scm](../../tests/concurrency/test_multithread_scheduler.scm)
  - Group 12 を新設: 4 ワーカー並行スケジューラ上で Supervisor が管理するコルーチン子タスクが、ワーカー 0 で yield $\to$ 別ワーカーでワークスチール再開 $\to$ コルーチン内例外（`(car '())`）発生 $\to$ 境界ハンドラ捕捉 $\to$ Supervisor 自動復旧 $\to$ 正常完走を検証。
- [ ] [ulisp/Makefile](../../ulisp/Makefile)
  - `test_concurrency_stress` ターゲットを新設: `test_concurrency`（全並行テスト）および高負荷並行テストを連続反復実行するストレスターゲットを整備。
- [ ] [Makefile](../../Makefile)
  - ルート Makefile に `test_concurrency_stress` ターゲットを追加し、CI / ローカルから一発実行可能にする。
- [ ] [.github/workflows/ci.yml](../../.github/workflows/ci.yml)
  - Quality Gate 6 に並行ストレステスト実行を追加、または専用ステップとして統合し、Linux x86-64 実機での完全自動回帰検証を保証。

---

## 4. 根本原因分析と技術的課題 / RCA & Technical Challenges
1. **ワーカー間マイグレーション時の境界ハンドラ再接続の検証不足**:
   - コルーチンがワーカー 0 で作成・yield された際、ワーカースタック 0 の境界ハンドラが TCB に記録される。
   - ワーカー 1 にスチールされて再開された際、Issue #787 のアセンブリ修正によりワーカー 1 の境界ハンドラが末尾に再接続される仕様となっているが、再開直後に例外が発生した際に、ワーカー 1 のスタックフレーム上で正しく `%raise` が発火し、ワーカー 1 の境界ハンドラへ巻き戻される実機動作が、Supervisor 自動復旧とセットで検証されていない。
2. **クラッシュ後の Supervisor 再起動クリーンネス**:
   - コルーチンが例外で panic 終了した後、Supervisor が新規タスクコンテキストおよび新規コルーチンスタックを割り当てて再起動し、2回目の実行で正常終了するまでの状態遷移（`running` $\to$ `waiting`）が確実に機能することを実証する必要がある。

---

## 5. 脅威モデリングと安全性検証 / Threat Modeling & Safety Analysis
- **CWE-825 (Expired Pointer Dereference) / CWE-588 (Attempt to Access Child of Non-structure Type)**:
  - ワークスチールにより他ワーカーへ移行したコルーチンが例外を送出した際、旧ワーカーのスタックポインタ（無効フレーム）へジャンプすると、スタック破壊およびメモリ不正アクセスを引き起こす。
  - **検証目標**: ワーカー移行後の例外発生時でも、新ワーカーのスタック上で境界ハンドラが確定的に捕捉し、旧ワーカーのスタックを一切参照しないことを実機検証。
- **CWE-362 (Race Condition) / CWE-662 (Improper Synchronization)**:
  - 並行実行中のワークスチール・例外発生・Supervisor への DOWN 送信が同時に発生した場合のロックフリーキューおよび状態マシンの整合性。
- **CWE-835 / CWE-400 (Infinite Loop / Resource Exhaustion / Deadlock)**:
  - マルチスレッド並行ストレステストにおいて、フュテックス待機やワーカースチールループがハングアップしないことの検証。

---

## 6. 実装方針 / Implementation Plan
Target Branch: `feat/799-add-cross-worker-coroutine-yield-exception-and-linux-ci-stress-tests`

### 1. `test_multithread_scheduler.scm` への Group 12 追加
- **Group 12: Cross-Worker Coroutine Yield, Migration & Unhandled Exception Recovery**:
  - 4 ワーカーの並行スケジューラ `(make-work-stealing-scheduler 4 256)` を作成。
  - Supervisor（`one_for_one`）配下にコルーチン子タスク `coro_migrating_child` を登録。
  - 子タスクの動作:
    - 1回目のブート時: ワーカー 0 上で実行開始し、初期値を出力して `(context-yield! 'yielded_step1)` でサスペンド。
    - サスペンド後、別ワーカー（ワーカー 1〜3）がスチールして再開（`context-resume!`）。
    - 再開されたコルーチン内部で、意図的に未処理例外 `(car '())` を発生させる。
    - ワーカー B の境界ハンドラが panic を捕捉し、Supervisor に `DOWN` を送出。
    - Supervisor が子タスクを再起動（2回目のブート）。
    - 2回目のブート時: コルーチンが正常に最後まで完走（`'coro_completed_ok`）。
  - **アサーション**:
    - ブート回数が正確に 2 回（初期起動 + 1 回の再起動）。
    - 1 回目の yield が確実に記録されていること。
    - 2 回目のブートで正常完了フラグが設定されること。
    - Supervisor の状態が `'idle`、タスク状態が `'waiting` に復帰すること。
    - メモリ破壊やセグメンテーションフォールトが皆無であること。

### 2. `ulisp/Makefile` およびルート `Makefile` へのストレステスト整備
- `ulisp/Makefile`:
  - `test_concurrency_stress`:
    - `test_concurrency`（全並行テスト）に加えて、`test_multithread_scheduler` および `test_supervisor` を 10 サイクル連続実行するストレスターゲットを定義。
- `Makefile`:
  - `test_concurrency_stress` ターゲットを追加し、`$(MAKE) -C ulisp test_concurrency_stress` を呼び出す。

### 3. CI ワークフローへの統合 (`.github/workflows/ci.yml`)
- `Quality Gate 6` において、`make test_concurrency` に加えて `make test_concurrency_stress` を実行するように更新。
- Linux x86-64 環境での高負荷耐障害性を完全自動保証。

---

## 7. 完了条件 / Success Criteria (DoD)
- [x] `tests/concurrency/test_multithread_scheduler.scm` に Group 12 が追加され、4 ワーカー環境でのコルーチン yield $\to$ ワークスチール再開 $\to$ 未処理例外 $\to$ Supervisor 自動復旧 $\to$ 完走が 100% PASS すること。
- [x] `ulisp/Makefile` およびルート `Makefile` に `test_concurrency_stress` ターゲットが実装され、反復実行でエラーが 0 件であること。
- [x] `.github/workflows/ci.yml` に `make test_concurrency_stress` が組み込まれ、CI パイプライン定義が更新されていること。
- [x] `make -C ulisp test_multithread_scheduler` が全件 PASS すること。
- [x] `make -C ulisp test_supervisor`, `make -C ulisp test_preemption`, `make -C ulisp bench_concurrency_gate` がリグレッションなく PASS すること。
- [x] 相対パス規約が 100% 遵守されていること（絶対パス 0 件）。
