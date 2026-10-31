---
ID: 635
title: "[FEAT] 分散 M:N ワークスティーリングスケジューラおよび Chase-Lev Deque の実装 (ID: 635)"
ステータス: Closed (Completed 2026-11-01)
優先度: High (P1)
担当エージェント:
  - Project Manager (PM) (Chair / Governance)
  - IT Specialist (Programming Languages & Compilers / PLC)
  - Software Development (SWD)
  - Systems Architect
  - Embedded Systems Specialist
  - Information Security Specialist
  - Software Quality Assurance Specialist
  - Network Specialist
  - Database / Data Infrastructure Specialist
  - IT Specialist (NLP & Info Retrieval)
  - IT Strategist
  - IT Service Manager
  - Systems Auditor
  - UI/UX & Documentation Designer
  - Education Specialist
  - Application Specialist (APS)
作成日: 2026-10-31
更新日: 2026-11-01
---

# Issue #635: [FEAT] 分散 M:N ワークスティーリングスケジューラおよび Chase-Lev Deque の実装

## 1. 概要 (Summary)

[DSN-37: Synapse Dual-Plane Concurrent Runtime Architecture](../../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md)（第 7.1 節「M:N 超軽量タスクと分散ワークスティーリング」、第 13.4 節「並行ランタイムモジュールのロード設計」、および第 14.4 節 Phase 2 Task 2.2）に基づき、論理 CPU コア数（または設定されたワーカー数）に応じた複数のワーカースレッド間でタスクを自律分散・並行実行する **M:N ワークスティーリングスケジューラ (`scheduler.scm`)** および **Chase-Lev ロックフリー両端キュー (`deque.scm`)** を実装する。

各ワーカーは専用の Chase-Lev Deque を保持し、自ワーカーのタスク投入・取り出しは末尾（Bottom）に対してキャッシュ局所性に優れた LIFO（スタック動作）で行い、自キューが空になったワーカーは他ワーカーの先頭（Top）から FIFO（キュー動作）でタスクをアトミックに盗取（Steal）することで、ロック競合の極小化と自動的な負荷平準化を両立する。

先行する [Issue #630](630-implement-synapse-task-independent-bump-arena.md)（アリーナ）・[Issue #631](631-implement-synapse-low-level-atomic-primitives.md)（アトミック命令）・[Issue #632](632-implement-synapse-michael-scott-lockfree-queue.md)（MS キュー）・[Issue #633](633-implement-synapse-first-class-p2p-channel.md)（チャネル）・[Issue #634](634-implement-synapse-callee-saved-context-switch.md)（ネイティブコンテキストスイッチ）と同様、**uLisp 専用スコープ**（`ilisp/` への組み込みや `tests/ilisp/` でのテストは行わない）および [DSN-37 セクション 13.4](../../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md) の**オンデマンド・モジュールロード設計**（コアランタイムにはバンドルせず、`include` / `load` / `import` の 3 方式で利用可能）を厳格に遵守する。

---

## 2. ガバナンス・専門エージェント多角レビュー (Governance & Multi-Agent Reviews)

1. **Project Manager (PM) [Chair]**:
   - DSN-37 Phase 2 Task 2.2 のマイルストーン。後続の [Issue #636: リダクション方式セーフポイント注入とプリエンプション機構](../636-implement-synapse-fuel-preemption-mechanism.md) の直接の基盤となる。スコープは uLisp（`ulisp/`）および `tests/concurrency/` に限定し、既存コンパイラパスや他モジュールに非破壊であることを徹底する。
2. **IT Specialist (Programming Languages & Compilers / PLC)**:
   - Chase-Lev ロックフリー Deque アルゴリズムの厳密なメモリ整合性を保証する。Owner による `deque-push!` / `deque-pop!`（Bottom 操作）と Thief による `deque-steal!`（Top 操作）の競合ポイント（要素数が 1 個の場合の Top/Bottom 競合）において、`atomic-cas!` および `memory-fence`（フルメモリバリア）を正しく配置し、データの消失・多重実行を完全に防止する。
3. **Software Development (SWD)**:
   - 2 つのモジュールに分割実装する:
     - `ulisp/runtime/concurrency/deque.scm` & `ulisp/lib/ulisp/concurrency/deque.sld`: 独立して再利用可能な Chase-Lev Deque。
     - `ulisp/runtime/concurrency/scheduler.scm` & `ulisp/lib/ulisp/concurrency/scheduler.sld`: ワーカー管理、タスク投入、スティーリングループ、大域インジェクションキュー連携。
4. **Systems Architect**:
   - [Issue #633](633-implement-synapse-first-class-p2p-channel.md) の `<task-context>`、[Issue #632](632-implement-synapse-michael-scott-lockfree-queue.md) の `<lock-free-queue>`、および [Issue #634](634-implement-synapse-callee-saved-context-switch.md) の `<coroutine-context>` と緊密に統合。外部スレッドからのタスク投入用フォールバックとして大域 Michael-Scott キューを備え、チャネル起床フック（`*channel-wake-hook-box*`）ともシームレスに連携させる。
5. **Software Quality Assurance Specialist**:
   - 単体および耐久テストスイート `tests/concurrency/test_scheduler.scm` を策定。
     - Group 1: Chase-Lev Deque の LIFO 単一ワーカー操作（境界条件・拡張・空検知）。
     - Group 2: Chase-Lev Deque の並行スティール競合（CAS 成功/失敗・単一要素レース）。
     - Group 3: スケジューラ生成・ワーカー初期化・タスク投入（`spawn`）。
     - Group 4: 不均等負荷（特定のワーカーに偏ったタスク投入）における自律的ワークスティーリングと負荷平準化の検証。
     - Group 5: **100,000 タスクの大量投入・完全消化・耐久ストレス検証**（タスク脱落 0 件、メモリリーク 0 件）。
     - Group 6: セキュリティ・境界ガード（CWE-362, CWE-400, CWE-843, CWE-190）。
6. **Embedded Systems Specialist**:
   - 循環バッファは初期容量 64〜1024 スロットの 2 べき乗とし、ビット演算マスク（`index & mask`）による高速な剰余計算を採用。安定稼働時の追加メモリアロケーションを極小化する。
7. **Information Security Specialist**:
   - 要素数 1 の境界における Owner と Thief のデータレース（CWE-362）、循環バッファインデックスの 64-bit 整数ラップアラウンド（CWE-190）、無制限なタスク投入によるリソース枯渇（CWE-400）、および非タスクオブジェクト投入時の型混同（CWE-843）への緩和策を講じる。
8. **Network Specialist**:
   - チャネル送受信で待機中となったタスクが `channel-close!` やデータ到着で起床した際、`scheduler-wake-task!` により遅滞なくスケジューラへ復帰できることを確認する。
9. **Database / Data Infrastructure Specialist**:
   - ワークスティーリングの効率性（Steal 成功率、局所性維持）を測定し、不均等なタスク分布下でも全ワーカーが遊休化せず高いスループットを維持できることを保証する。
10. **IT Specialist (NLP & Info Retrieval)**:
    - 論文バッチ処理やトークナイズなどの不均質なチャンク処理において、ワークスティーリングによる並列処理効率の向上を確認する。
11. **IT Strategist**:
    - Go ランタイム (`proc.go`)、Tokio (`tokio::runtime`)、Erlang SMP スケジューラに匹敵するモダンなワークスティーリング基盤を uLisp の AOT 環境で確立する。
12. **IT Service Manager**:
    - 稼働状況を監視する診断 API `(scheduler-stats sched)` を提供し、総タスク数、ワーカーごとの実行数、スティール試行回数、スティール成功回数を可観測化する。
13. **Systems Auditor**:
    - すべての内部リンクが相対パスで記述されていること（絶対パス 0 件）および `ilisp/` への波及がないことを監査する。
14. **UI/UX & Documentation Designer**:
    - R7RS ライブラリ仕様 `(ulisp concurrency deque)` および `(ulisp concurrency scheduler)` のクリーンな外部シンボル体系を整備する。
15. **Education Specialist**:
    - Chase-Lev Deque の循環リングバッファ構造と Top/Bottom ポインタの動きを ASCII 図解で明記する。
16. **Application Specialist (APS)**:
    - バックグラウンド非同期タスク投入インターフェースとしての使いやすさと安全性を保証する。

---

## 3. 現状分析と課題 (Current State & Challenges)

1. **現状 (Status Quo)**:
   - DSN-37 Phase 1 および Phase 2 Task 2.1 により、アリーナ、アトミック命令、MS ロックフリーキュー、リニアチャネル、およびネイティブコンテキストスイッチ（Issue #634）が完成した。
   - しかし、タスクの実行を統括し、複数のコア／ワーカーにタスクを分散して協調的に消化するスケジューラ層が存在せず、生成されたタスクは個別手動で `context-resume!` / `context-switch!` を呼び出さなければならない。
2. **課題 (Challenges)**:
   - 単一の大域キューに全ワーカーがアクセスする集中型スケジューラでは、コア数の増加に伴いキューのロック／CAS 競合がボトルネックとなる。
   - ワーカーごとに完全独立した静的キューを割り当てると、特定のワーカーに処理負荷が集中した際に他ワーカーがアイドル状態となる「負荷の不均衡」が発生する。
   - Chase-Lev Deque は Lock-Free でありながら、Owner による LIFO アクセス（キャッシュホットな末尾から取得）と Thief による FIFO スティール（最も滞留時間の長い先頭から取得）を両立できるが、配列要素数が 1 個になった瞬間に Owner と Thief が同一要素を取り合うため、厳密な CAS 判定とメモリフェンスが不可欠である。

---

## 4. アーキテクチャと設計 (Architecture & Design)

### 4.1 Chase-Lev ロックフリー両端キュー (`<chase-lev-deque>`) の構造と動作原理

```
                          Thief steals from Top (FIFO)
                                      |
                                      v
    +---------------------------------------------------------------+
    | ... | Task 0 | Task 1 | Task 2 | Task 3 | Task 4 | ... | ...  |  Circular Array
    +---------------------------------------------------------------+
              ^                                   ^
              |                                   |
             Top (CAS by Thieves)               Bottom (Owner LIFO push/pop)
                                                  ^
                                                  |
                                      Owner pushes/pops here
```

- **フィールド**:
  - `top`: アトミックボックス（`make-atomic-box`）。Thief が `deque-steal!` で CAS インクリメント。Owner も最後の 1 要素 pop 時に CAS。
  - `bottom`: Owner のみが書き込み、Thief は参照するインデックス。
  - `buffer`: 要素を格納するベクター（容量 $2^k$）。
  - `mask`: $2^k - 1$（インデックスマスキング用）。
- **Owner 操作**:
  - `deque-push!(deque, val)`:
    1. $b = \text{bottom}$, $t = \text{atomic-ref}(top)$
    2. 容量オーバーフロー時は自動倍増（grow）または固定上限境界チェック
    3. `vector-set!(buffer, b & mask, val)`
    4. `(memory-fence)`（ストアバリア）
    5. $\text{bottom} = b + 1$
  - `deque-pop!(deque)`:
    1. $b = \text{bottom} - 1$
    2. $\text{bottom} = b$
    3. `(memory-fence)`（フルメモリフェンス）
    4. $t = \text{atomic-ref}(top)$
    5. $size = b - t$
    6. If $size < 0$: キューは空。$\text{bottom} = t$; return `#f`
    7. $val = \text{vector-ref}(buffer, b \& mask)$
    8. If $size > 0$: 他要素が残っているため安全に return $val$
    9. If $size == 0$: 最後の 1 要素を巡り Thief と競合！
       - `(atomic-cas! top t (+ t 1))` に成功すれば Owner が勝利 -> $\text{bottom} = t + 1$; return $val$
       - 失敗すれば Thief が先にスティールしたため負け -> $\text{bottom} = t + 1$; return `#f`
- **Thief 操作**:
  - `deque-steal!(deque)`:
    1. $t = \text{atomic-ref}(top)$
    2. `(memory-fence)`
    3. $b = \text{bottom}$
    4. If $t \ge b$: キューは空; return `'empty`
    5. $val = \text{vector-ref}(buffer, t \& mask)$
    6. If `(atomic-cas! top t (+ t 1))`:
       - スティール成功 -> return $val$
       - 失敗（他 Thief または Owner が取得） -> return `'abort`（再試行または別ワーカー探索）

### 4.2 M:N ワークスティーリングスケジューラ (`<work-stealing-scheduler>`)

- **`<worker-context>`**:
  - `id`: ワーカー番号（$0 \dots N-1$）。
  - `deque`: 当該ワーカー専用の `<chase-lev-deque>`。
  - `current-task`: 実行中の `<task-context>`。
  - `rng-seed`: Xorshift64 擬似乱数シード（Victim 選択用）。
  - `tasks-executed`: 累計実行タスク数。
  - `steals-attempted`: スティール試行回数。
  - `steals-succeeded`: スティール成功回数。
- **`<work-stealing-scheduler>`**:
  - `workers`: ワーカーベクター（`vector of <worker-context>`）。
  - `worker-count`: ワーカー数（デフォルト 4、1〜64）。
  - `global-queue`: 外部・非ワーカーからのタスク投入用 `<lock-free-queue>`（Michael-Scott Queue）。
  - `state`: アトミックボックス（`'init`, `'running`, `'stopped`）。
  - `total-spawned`: 累計投入タスク数。

### 4.3 スケジューラ実行サイクルとスティール戦略

各ワーカーの 1 ステップ処理 (`scheduler-worker-step!`):
1. **Local Deque**: 自 Deque から `deque-pop!` を試行（キャッシュホットなタスクを LIFO で取得）。
2. **Global Queue**: 自 Deque が空の場合、大域キュー（`global-queue`）からタスクを取得。
3. **Work Steal**: それでも空の場合、擬似乱数（Xorshift64）で無作為に他のワーカー（Victim）を選び、その Deque の Top から `deque-steal!` を試行。
4. **Task Execution**: 取得したタスクを実行（サンクの呼び出し、または `context-resume!` によるコルーチン再開）。
5. **Idle Backoff**: 全ワーカーからタスクが取得できない場合、微小休止（バックオフ）を行う。

---

## 5. セキュリティ・品質保証分析 (Security & QA Analysis)

| 脅威 / リスク | CWE | 影響 | 対策 |
| :--- | :--- | :--- | :--- |
| **単一要素 Pop と Steal の競合** | CWE-362 | 同一タスクの二重実行、データ不整合 | 要素数 1 の境界で Owner も `atomic-cas!` を行い、失敗時は即座に Thief への譲渡を認めて `#f` を返す Chase-Lev 正典プロトコルを厳格遵守 |
| **循環インデックスのラップアラウンド** | CWE-190 | バッファ境界逸脱、メモリ破壊 | 64-bit 整数インデックスとビットマスク（`& mask`）を使用し、オーバーフロー耐性を確保 |
| **無制限タスク投入によるメモリ枯渇** | CWE-400 | OOM クラッシュ、サービス妨害 | `*scheduler-max-tasks*` 境界チェック（デフォルト 1,000,000 件）を設け、過剰投入を拒絶 |
| **不正オブジェクト投入による型混同** | CWE-843 | 不正メモリアクセス、SEGV | `scheduler-spawn!` でプロシージャ（サンク）または適合タスクオブジェクトであることを事前検証 |

---

## 6. 実装方針と詳細ステップ (Implementation Steps)

Target Branch: `feat/635-work-stealing-scheduler`

### Step 1: Chase-Lev Deque の実装 (`ulisp/runtime/concurrency/deque.scm` & `deque.sld`)
1. `<chase-lev-deque>` レコードの定義（`top`, `bottom`, `buffer`, `capacity`, `mask`）。
2. `make-chase-lev-deque([initial-cap])`: 初期容量 64〜1024、2 のべき乗丸め。
3. `deque-push!(deque, item)`: Owner による末尾追加、メモリバリア。
4. `deque-pop!(deque)`: Owner による末尾取得、単一要素競合時の `atomic-cas!`。
5. `deque-steal!(deque)`: Thief による先頭からの `atomic-cas!` スティール。
6. `deque-empty?(deque)`, `deque-count(deque)`: 状態検査ユーティリティ。
7. R7RS ライブラリ `(ulisp concurrency deque)` の策定。

### Step 2: M:N ワークスティーリングスケジューラの実装 (`ulisp/runtime/concurrency/scheduler.scm` & `scheduler.sld`)
1. `<worker-context>` および `<work-stealing-scheduler>` レコードの定義。
2. `make-work-stealing-scheduler([worker-count])`: 指定ワーカー数（デフォルト 4）で初期化。
3. `scheduler-spawn!(sched, thunk-or-task, [worker-id])`: タスク投入（ワーカー指定または大域キュー）。
4. `scheduler-worker-step!(sched, worker-id)`: Local pop -> Global queue -> Steal -> Execute の 1 サイクル実行。
5. `scheduler-run!(sched, [max-total-tasks])`: 全ワーカーを駆動してタスクを完遂するループ。
6. `scheduler-stop!(sched)`: スケジューラの安全な停止。
7. `scheduler-stats(sched)`: 統計情報の取得（投入数、実行数、スティール試行数、成功数）。
8. `channel.scm` の `set-channel-wake-hook!` との連携（チャネル起床タスクを自動スケジューリング）。
9. R7RS ライブラリ `(ulisp concurrency scheduler)` の策定。

### Step 3: 単体・耐久テストスイート (`tests/concurrency/test_scheduler.scm`) の作成
1. **Group 1**: Chase-Lev Deque の単一ワーカー LIFO 操作（push/pop/empty/count/容量拡張）。
2. **Group 2**: Chase-Lev Deque の並行 Steal 動作（CAS 成功・失敗・空時挙動）。
3. **Group 3**: スケジューラ生成・初期化・タスク投入・単一ステップ実行。
4. **Group 4**: 不均等負荷（Worker 0 にのみ 1,000 タスクを投入し、Worker 1〜3 が自律スティールして全タスクを平準化消化することの検証、`steals-succeeded > 0` の確認）。
5. **Group 5**: **100,000 タスクの大量投入・完全消化・耐久ストレス検証**（タスク脱落 0 件、メモリリーク 0 件）。
6. **Group 6**: セキュリティ・境界ガード（CWE-362, CWE-400, CWE-843, CWE-190）。

### Step 4: `ulisp/Makefile` へのテスト・Lint ターゲットの統合
1. `lint_sexpr` に `runtime/concurrency/deque.scm`, `lib/ulisp/concurrency/deque.sld`, `runtime/concurrency/scheduler.scm`, `lib/ulisp/concurrency/scheduler.sld`, `tests/concurrency/test_scheduler.scm` を追加。
2. `test_scheduler` ターゲットを追加し、AOT コンパイル・ネイティブ実行を自動化。
3. `test:` ターゲットに `test_scheduler` を追加。

---

## 7. 完了条件 (Success Criteria / Definition of Done)

- [x] `ulisp/runtime/concurrency/deque.scm`, `deque.sld` が実装され、Chase-Lev ロックフリー Deque（LIFO push/pop, FIFO steal）が仕様通り動作すること。
- [x] `ulisp/runtime/concurrency/scheduler.scm`, `scheduler.sld` が実装され、M:N ワークスティーリングスケジューラがオンデマンドロード（`include` / `load` / `import`）可能であること（コアランタイムにはバンドルしないこと）。
- [x] 不均等な負荷（特定ワーカーへの偏重投入）を与えた際、他ワーカーが自律的にタスクを盗取（Steal）し、全タスクが滞りなく均等に完了すること（`steals-succeeded > 0`）。
- [x] **100,000 タスクの大量投入耐久テスト**において、タスク脱落 0 件、SEGV 0 件、不正メモリアクセス 0 件で全タスクが完了すること。
- [x] ILisp (`ilisp/` および `tests/ilisp/`) には一切の変更を加えていないこと。
- [x] `tests/concurrency/test_scheduler.scm` の全テストケースがネイティブコンパイル実行 (`make -C ulisp test_scheduler`) で 100% PASS すること。
- [x] S 式構文・括弧バランス検査 (`make -C ulisp lint_sexpr`) および品質ゲート (`make format`, `make static_analysis`) がエラー 0 件で PASS すること。
- [x] ドキュメント内のすべてのリンクが相対パスで記述されており、絶対パス指定が 0 件であること。
