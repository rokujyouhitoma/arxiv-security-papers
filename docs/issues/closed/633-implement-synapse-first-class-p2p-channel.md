---
title: "[FEAT] 線形所有権移譲チャネルおよび有界バックプレッシャー機構の実装 (ID: 633)"
ステータス: Closed (Completed 2026-10-31)
優先度: High (P1)
担当エージェント:
  -Project Manager (PM) (Chair / Governance)
  -IT Specialist (Programming Languages & Compilers / PLC)
  -Software Development (SWD)
  -Systems Architect
  -Network Specialist
  -Information Security Specialist
  -Software Quality Assurance Specialist
作成日: 2026-10-31
更新日: 2026-10-31
---

# Issue #633: [FEAT] 線形所有権移譲チャネルおよび有界バックプレッシャー機構の実装

## 1. 概要 (Summary)

[DSN-37: Synapse Dual-Plane Concurrent Runtime Architecture](../../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md)（第 4 章「並行通信モデルと所有権の数理的整合性」、第 4.3.1 節「有界チャネルとバックプレッシャー」、第 6.1 節「Scheme レコード構造体」、および第 14.3 節 Phase 1 Task 1.2）に基づき、[Issue #632](632-implement-synapse-michael-scott-lockfree-queue.md) で実装した Michael-Scott ノンブロッキングキュー（`<lock-free-queue>`）と [Issue #631](631-implement-synapse-low-level-atomic-primitives.md) のハードウェア CAS プリミティブ（`<atomic-box>`）を基盤として、**1 対 1 のゼロコピー所有権移譲（Move Semantics）を保証する線形チャネル (`<channel>`)** および **決定論的バックプレッシャー機構** を Pure uLisp Scheme で実装する。

本モジュールは、容量 `0` のランデブー同期チャネル（Rendezvous Synchronous Channel）と容量 `> 0` の有界バッファチャネル（Bounded Buffered Channel）の双方を単一の一貫したレコード構造でサポートし、バッファ満杯時の送信タスク自動サスペンド（`'waiting-channel` 遷移 & `send-wait-queue` 登録）および下流の `channel-recv!` による待機タスク即時起床（Wakeup & 昇格）を実現する。

先行する [Issue #630](630-implement-synapse-task-independent-bump-arena.md)・[Issue #631](631-implement-synapse-low-level-atomic-primitives.md)・[Issue #632](632-implement-synapse-michael-scott-lockfree-queue.md) と同様、**uLisp 専用スコープ**（`ilisp/` への組み込みや `tests/ilisp/` でのテストは行わない）および [DSN-37 セクション 13.4](../../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md) の**オンデマンド・モジュールロード設計**（コアランタイムにはバンドルせず、`include` / `load` / `import` の 3 方式で利用可能）を厳格に遵守する。

---

## 2. ガバナンス・専門エージェント多角レビュー (Governance & Multi-Agent Reviews)

1. **Project Manager (PM) [Chair]**:
   - DSN-37 Phase 1（通信 & ロックフリー同期）の最終タスク（Task 1.2）。完了済みの [Issue #631](631-implement-synapse-low-level-atomic-primitives.md)・[Issue #632](632-implement-synapse-michael-scott-lockfree-queue.md) を統合し、Phase 2 の [Issue #635: 分散 M:N ワークスティーリングスケジューラ (`scheduler.scm`)](../635-implement-synapse-work-stealing-scheduler.md) や Phase 3 の [Issue #638: アフィン線形所有権静的検査パス](../638-implement-nanopass-check-affine-types-and-raii-drop.md) へ接続する。スコープは uLisp（`ulisp/`）と `tests/concurrency/` に限定する。
2. **IT Specialist (Programming Languages & Compilers / PLC)**:
   - チャネル送受信で受け渡される Scheme オブジェクト（ペア、ベクタ、レコード、ボックス等）がコピーを一切伴わず同一ポインタ（`eq?` 同一性維持）のまま送信側から受信側へ Move されることを保証する。また DSN-37 Section 6.1 の `<task-context>`（TCB）レコード構造体を定義し、後続の `scheduler.scm` とシームレスに共有可能とする。
3. **Software Development (SWD)**:
   - `<channel>` 内部の 3 本の `<lock-free-queue>`（`message-queue`, `recv-wait-queue`, `send-wait-queue`）と `current-count`（`<atomic-box>`）の更新順序を厳密に設計し、ランデブー直接ハンドオフ（`capacity = 0`）と有界バッファ昇格（`capacity > 0` で `channel-recv!` 時に `send-wait-queue` 先頭要素を `message-queue` へ補充しつつ送信タスクを `'ready` に復帰させる処理）をロックフリーで実装する。
4. **Systems Architect**:
   - スケジューラ（Phase 2）導入前でも単体でサスペンド／起床遷移を検証でき、かつ Phase 2 の `scheduler.scm` からは起床コールバックフック（`*channel-wake-hook*` または引数指定フック）を介してワーカのランキューへ直接再投入できる疎結合設計とする。
5. **Network Specialist**:
   - DSN-37 Section 4.3.1 の CSP バックプレッシャー制御を実装し、無制限キューによる OOM（CWE-400）を防止する。また Section 4.2 に基づき、複数チャネルへの Fan-out 配信用にディープコピーを強制する `broadcast-send!` を分離提供する。
6. **Information Security Specialist**:
   - クローズ済みチャネルへの送信による不整合や、負の容量・非整数容量指定によるバッファ境界破壊（CWE-20 / CWE-190）、`<channel>` や `<task-context>` 以外の不正オブジェクト渡しによる型混同（CWE-843）、および起床済み待機ノードにペイロード参照が残存することによるメモリ保持リーク（CWE-401）への対策を必須化する。
7. **Software Quality Assurance Specialist**:
   - ① ランデブー同期（`capacity = 0`）での送信先行・受信先行双方のゼロコピー直接ハンドオフ、② 有界バッファ（`capacity > 0`）での満杯時サスペンドと受信に伴う順次起床（バックプレッシャー解消）、③ `eq?` ポインタ同一性検証、④ `#f` ペイロード送受信の正確な識別、⑤ `broadcast-send!` によるディープコピー分離、⑥ 10,000 メッセージ連続送受信耐久テストを網羅する `tests/concurrency/test_channel.scm` を策定する。
8. **Database / Data Infrastructure Specialist**:
   - 非同期クエリ実行パイプラインのステージ間チャネルとして、FIFO 順序性とメッセージ欠損ゼロが保証されることを確認する。
9. **IT Specialist (NLP & Info Retrieval)**:
   - 文書チャンク解析ストリームにおいて、チャンクベクタのポインタをゼロコピー Move で下流ステージへ引き渡せることを確認する。
10. **IT Strategist**:
    - Go 言語の有界チャネルや Erlang/BEAM のプロセス間通信に匹敵する表現力を、STW-GC 停止や OS ミューテックスなしの Pure Scheme レコード＋CAS で実現する。
11. **IT Service Manager**:
    - 運用監視のため、現在のバッファ内メッセージ数・送信待機タスク数・受信待機タスク数・累計送信数・累計受信数・バックプレッシャー発動回数を取得する `channel-stats` API を提供する。
12. **Embedded Systems Specialist**:
    - `<channel>` の内部キューに [Issue #632](632-implement-synapse-michael-scott-lockfree-queue.md) の `<queue-node-pool>` を選択的に適用可能とし、組込み環境での動的アロケーション抑制に対応する。
13. **Systems Auditor**:
    - DSN-37 Section 8.3（Generation Gate）との連携を見据え、`<task-context>` に `epoch` フィールドを保持し、待機タスク起床時に世代一致を検証可能なフック構造を備えるとともに、ドキュメントの相対パス規約（絶対パス 0 件）を監査する。
14. **UI/UX & Documentation Designer**:
    - `(import (ulisp concurrency channel))`、`(load "ulisp/runtime/concurrency/channel.scm")`、`(include "ulisp/runtime/concurrency/channel.scm")` の 3 層インターフェースを整える。
15. **Education Specialist**:
    - 容量 0（Rendezvous）と容量 $>0$（Bounded Buffer）の状態遷移図および Move セマンティクスの不変条件をコメント・ドキュメントに明記する。
16. **Application Specialist (APS)**:
    - ブロッキング／サスペンド前提の `channel-send!` / `channel-recv!` に加え、即時ポーリング用の `channel-try-send!` / `channel-try-recv!` / `channel-close!` を提供し、制御プレーンと計算プレーンの双方から扱いやすい API とする。

---

## 3. 脅威分析とセキュリティ要件 (Threat Modeling & Security Requirements)

| 脅威 ID | STRIDE 分類 | 対象 CWE | 脅威シナリオ | 緩和策・セキュリティ設計 |
| :--- | :--- | :--- | :--- | :--- |
| **TM-633-01** | Tampering / Elevation of Privilege | CWE-843 (Type Confusion) | `channel-send!`, `channel-recv!`, `channel-close!` 等に `<channel>` 以外の値を渡す、またはタスク引数に `<task-context>` 以外を渡すことで内部スロットを誤参照・破壊する。 | 全公開手続きの入口で `(channel? ch)` および `(task-context? task)` 検査を強制し、型違反時は即座に `error` を送出する。 |
| **TM-633-02** | Denial of Service | CWE-400 (Uncontrolled Resource Consumption) | 高速なプロデューサが無制限にメッセージを投入してヒープメモリを枯渇させる、または不正な負の `capacity` 指定により容量判定が破綻する。 | `make-channel` で `capacity` が 0 以上の整数であることを厳密に検証し（上限 `*channel-max-capacity*` も規定）、`current-count >= capacity` 到達時は送信タスクを必ず `'waiting-channel` にサスペンドさせて決定論的バックプレッシャーを強制する。 |
| **TM-633-03** | Tampering / Information Disclosure | CWE-416 / CWE-662 (Shared Mutable Aliasing in Broadcast) | 1 対多の同報配信で同一可変オブジェクトのポインタをそのまま共有すると、複数タスクからの競合アクセスや Use-After-Move が発生する。 | `channel-send!` は厳密に 1 対 1 の所有権 Move とし、複数チャネルへの配信は構造的ディープコピーを行う `broadcast-send!` として明示的に分離する（DSN-37 Section 4.2）。 |
| **TM-633-04** | Denial of Service | CWE-401 (Memory Leak via Waiter Payload Retention) | 送受信待機エントリ（`<channel-waiter>`）や `<task-context>` のハンドオフスロットに起床後もメッセージ参照が残り続け、GC 回収を妨げる。 | ハンドオフ完了およびメッセージ取り出し直後に `<channel-waiter>` や `<task-context>` の一時受け渡しスロットを `#f` でクリアし、不要参照を即座に切断する。 |

---

## 4. トレーサビリティ (Traceability)

- **親設計ドキュメント**:
  - [DSN-37: Synapse Dual-Plane Concurrent Runtime Architecture](../../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md)（第 4 章「並行通信モデルと所有権の数理的整合性」、第 4.3.1 節「有界チャネルとバックプレッシャー」、第 6.1 節「Scheme レコード構造体」、第 13.4 節「並行ランタイムモジュールのロード設計」、第 14.3 節「Phase 1 Task 1.2: 線形所有権移譲チャネルの実装」）
- **先行 Issue (完了済)**:
  - [Issue #630: プロセスローカル・エフェメラルアリーナおよび O(1) 瞬時全破棄機構の実装](630-implement-synapse-task-independent-bump-arena.md)
  - [Issue #631: Scheme 低レベルアトミック命令 (atomic-cas! / atomic-box) の提供](631-implement-synapse-low-level-atomic-primitives.md)
  - [Issue #632: Michael-Scott ノンブロッキング・ロックフリーキューの実装](632-implement-synapse-michael-scott-lockfree-queue.md)
- **後続・依存先 Issue**:
  - [Issue #635: 分散 M:N ワークスティーリングスケジューラおよび Chase-Lev Deque の実装](../635-implement-synapse-work-stealing-scheduler.md)
  - [Issue #638: アフィン線形所有権静的検査パス (check-affine-types) および自動 RAII Drop の実装](../638-implement-nanopass-check-affine-types-and-raii-drop.md)
  - [Issue #642: 世代管理型投機タスク破棄および待機タスク世代ゲート検証の実装](../642-implement-synapse-epoch-fencing-distributed-rollback.md)
  - [Issue #643: 10 万並行マイクロタスク耐久ベンチマークおよび STW-GC ゼロ検証スイートの実装](../643-implement-synapse-benchmark-suite-and-stw-gc-verification.md)

---

## 5. 影響範囲と関連ファイル (Scope and Affected Files)

> [!IMPORTANT]
> ユーザー指示および DSN-37 の方針に基づき、実装およびテストの対象は **uLisp のみ**（`ulisp/` および `tests/concurrency/`）とする。`ilisp/` への組み込みや `tests/ilisp/` でのテスト追加は一切行わない。また、`ulisp/stdlib_entry.scm` や `ULISP_RUNTIME_LIBS` にはバンドルせず、オンデマンドロード方式とする。

### 新規作成ファイル
- [`ulisp/runtime/concurrency/channel.scm`](../../../ulisp/runtime/concurrency/channel.scm):
  - `<task-context>`（DSN-37 Section 6.1 準拠 TCB レコード＋ハンドオフスロット）、`<channel-waiter>`、`<channel>` レコード定義、および `make-channel`, `channel-send!`, `channel-try-send!`, `channel-recv!`, `channel-try-recv!`, `channel-try-recv-with-status!`, `channel-close!`, `channel-closed?`, `channel-empty?`, `channel-full?`, `channel-stats`, `broadcast-send!` の実装。
- [`ulisp/lib/ulisp/concurrency/channel.sld`](../../../ulisp/lib/ulisp/concurrency/channel.sld):
  - R7RS `(import (ulisp concurrency channel))` 用のライブラリ定義ファイル。
- [`tests/concurrency/test_channel.scm`](../../../tests/concurrency/test_channel.scm):
  - ランデブー同期（`capacity = 0`）、有界バッファ（`capacity > 0`）とバックプレッシャー・サスペンド／起床、ゼロコピー Move（`eq?` ポインタ同一性）、`#f` ペイロード送受信、`broadcast-send!` ディープコピー、10,000 メッセージ耐久テスト、および型安全性ガードの単体テストスイート。

### 変更対象ファイル
- [`ulisp/Makefile`](../../../ulisp/Makefile):
  - `lint_sexpr` 対象ファイルに `runtime/concurrency/channel.scm`, `lib/ulisp/concurrency/channel.sld`, `$(ROOT_DIR)/tests/concurrency/test_channel.scm` を追加。
  - `test_channel` ターゲットを追加し、`test` ターゲットへ統合。

---

## 6. 実装方針 (Implementation Plan)

- **ターゲットブランチ**: `feat/633-linear-channel`

### Step 1: `<task-context>` (TCB) および `<channel-waiter>` の定義 (DSN-37 Section 6.1)
1. **`<task-context>` レコード定義**:
   - DSN-37 Section 6.1 に準拠し、`tid`, `state` (`'ready` | `'running` | `'waiting-channel` | `'terminated`), `reductions`, `continuation-pc`, `stack-pointer`, `arena-base`, `arena-offset`, `arena-capacity`, `blocked-on`, `epoch`, `next-run`, `reduction-exhaustions`, `steals-count` に加え、チャネル直接ハンドオフ受領用の内部ボックス `handoff-box`（`<atomic-box>`）を備える。
   - `make-task-context` は `case-lambda` により、テストや軽量タスク生成で使いやすい 1〜2 引数 `(make-task-context tid [epoch])` と、DSN-37 Section 6.1 の 13 引数フルコンストラクタの双方をサポートする。
   - 状態定数およびヘルパー：`*task-default-reductions*` (`4096`), `task-take-handoff!`（ハンドオフ値を取り出しスロットを `#f` にクリアして CWE-401 を防ぐ）。
2. **`<channel-waiter>` レコード定義**:
   - 送受信待機キュー（`recv-wait-queue` / `send-wait-queue`）に格納する待機ノード `(define-record-type <channel-waiter> (%make-channel-waiter task payload-box active-box) channel-waiter? ...)` を定義する。

### Step 2: `<channel>` 構造体と起床フック機構の実装 (DSN-37 Section 4 & 6.1)
1. **`<channel>` レコード定義**:
   - `message-queue`: `<lock-free-queue>`（バッファされた Move 済みメッセージ）
   - `recv-wait-queue`: `<lock-free-queue>`（受信待機中 `<channel-waiter>`）
   - `send-wait-queue`: `<lock-free-queue>`（バックプレッシャー／ランデブー送信待機中 `<channel-waiter>`）
   - `capacity`: 整数（`0`: ランデブー同期、`> 0`: 有界バッファ、上限 `*channel-max-capacity* = 1048576`）
   - `current-count`: `<atomic-box>`（現在のバッファ内メッセージ数）
   - `closed-box`: `<atomic-box>`（クローズ状態フラグ `#f` / `#t`）
   - 統計カウンタ（`sent-count-box`, `received-count-box`, `backpressure-count-box`, `handoff-count-box`）。
2. **`make-channel` コンストラクタ**:
   - `case-lambda` により `()`（デフォルト `capacity = 0` ランデブー）および `(capacity)`（`0 <= capacity <= *channel-max-capacity*`）、さらに DSN-37 Section 6.1 の 5 引数 `make-channel-internal` をサポートする。
3. **スケジューラ連携用起床フック (`set-channel-wake-hook!`)**:
   - チャネル操作により待機タスクが `'waiting-channel` から `'ready` に遷移した際、登録されたコールバック `(wake-hook task)` を呼び出す（Phase 2 の `scheduler.scm` がランキュー投入フックを登録可能）。

### Step 3: `channel-send!` / `channel-recv!` と決定論的バックプレッシャーの実装
1. **`channel-send!`**:
   - `(channel-send! ch val [sender-task [wake-hook]])`:
   - クローズ済みチャネル（`channel-closed?`）への送信は即座に `error` を送出する。
   - **Fast Path 1 (Direct Rendezvous Handoff to Waiting Receiver)**:
     - `recv-wait-queue` から有効な待機レシーバ `waiter` をデキューできた場合、`val` をゼロコピー（ポインタそのまま）でレシーバタスクの `handoff-box`（および `waiter` の `payload-box`）へ格納し、レシーバタスクの `blocked-on` を `#f`、`state` を `'ready` に更新して `wake-hook` を呼び出し、`#t`（ステータス `'handoff`）を返す。
   - **Fast Path 2 (Bounded Buffer Enqueue)**:
     - `capacity > 0` かつ `(atomic-ref current-count) < capacity` の場合、CAS で `current-count` を `+1` し、`message-queue` に `val` を `enqueue-lockfree!` で格納して `#t`（ステータス `'buffered`）を返す。
   - **Slow Path (Backpressure / Rendezvous Suspension)**:
     - バッファ満杯（`current-count >= capacity`）または `capacity == 0` で待機レシーバ不在の場合、`sender-task` が指定されていれば `(task-state-set! sender-task 'waiting-channel)` および `(task-blocked-on-set! sender-task ch)` に遷移させ、`(make-channel-waiter sender-task val)` を `send-wait-queue` にエンキューし、バックプレッシャー発動カウンタを `+1` して `'suspended` を返す。
2. **`channel-recv!`**:
   - `(channel-recv! ch [receiver-task [wake-hook]])`:
   - **Fast Path 1 (Buffered Message Available, `capacity > 0`)**:
     - `message-queue` から `dequeue-lockfree-with-status!` でメッセージ `(ok . msg)` を取得できた場合：
       - `send-wait-queue` を確認し、バックプレッシャーで待機中の送信タスク `sender-waiter` が存在すれば、その保留ペイロード `promoted-val` を取り出して `message-queue` にエンキューし（バッファ数は `capacity` のまま維持）、送信タスクの `blocked-on` を `#f`、`state` を `'ready` に遷移させて `wake-hook` で起床させる。
       - 待機中の送信タスクがいなければ `current-count` を `-1` する。
       - 取得した `msg` を返す。
   - **Fast Path 2 (Direct Handoff from Waiting Sender)**:
     - `message-queue` が空で、`send-wait-queue` に待機中の送信タスク `sender-waiter` が存在する場合（`capacity == 0` のランデブー、またはレース直後）、`sender-waiter` から `val` を直接 Move 取得し（`sender-waiter` 内の参照は `#f` クリア）、送信タスクの `blocked-on` を `#f`、`state` を `'ready` に遷移させて `wake-hook` で起床させ、`val` を返す。
   - **Slow Path (Receiver Suspension)**:
     - バッファも送信待機キューも空の場合（クローズ済みなら `'closed` またはデフォルト値を返却）、`receiver-task` を `'waiting-channel`（`blocked-on = ch`）に遷移させて `recv-wait-queue` に登録し、`'suspended` を返す。
3. **`broadcast-send!` (DSN-37 Section 4.2)**:
   - `(broadcast-send! channels val [deep-copy-proc])`: チャネルリストの各チャネルに対し、構造的ディープコピー（ペア・ベクタ・文字列・バイトベクタを再帰複製）を生成して送信し、タスク間で可変ポインタが共有されないことを保証する。

### Step 4: 単体・耐久テストスイート (`tests/concurrency/test_channel.scm`) の作成
1. `tests/concurrency/test_channel.scm` を作成し、以下の 6 グループを検証する：
   - **Group 1**: チャネルおよび `<task-context>` の初期化・述語検証・境界条件（`capacity = 0`, `capacity > 0`、`channel-empty?`, `channel-full?`, `channel-close!`）。
   - **Group 2**: ランデブー同期（`capacity = 0`）における「受信先行 → 送信起床」および「送信先行 → 受信起床」双方の待ち合わせと状態遷移検証。
   - **Group 3**: 有界バッファ（`capacity > 0`）における満杯時バックプレッシャー（送信タスクの `'waiting-channel` サスペンド）と、`channel-recv!` による待機送信タスクの自動起床・ペイロード昇格検証。
   - **Group 4**: ゼロコピー所有権移譲（Move Semantics: 送受信前後での `eq?` ポインタ同一性）と、`broadcast-send!` におけるディープコピー分離（`equal?` かつ `(not (eq? ...))`）および `#f` ペイロード送受信の検証。
   - **Group 5**: 10,000 メッセージ連続送受信・バックプレッシャー往復耐久ストレステストおよび `channel-stats` / CWE-401 参照クリア検証。
   - **Group 6**: 型混同・不正容量・クローズ済み送信に対するセキュリティガード（CWE-843 / CWE-20）検証。

---

## 7. 完了条件 (Success Criteria / Definition of Done)

- [x] `ulisp/runtime/concurrency/channel.scm` および `ulisp/lib/ulisp/concurrency/channel.sld` が実装され、`include` / `load` / `import` の 3 方式すべてでオンデマンドロード可能であること（コアランタイムにはバンドルしないこと）。
- [x] `<task-context>`, `<channel>`, `make-channel`, `channel-send!`, `channel-try-send!`, `channel-recv!`, `channel-try-recv!`, `channel-close!`, `broadcast-send!`, `channel-stats` が実装されていること。
- [x] ランデブー同期（`capacity = 0`）で送信側と受信側が互いに待ち合わせて同期し、待機側タスクが `'waiting-channel` から `'ready` へ起床すること。
- [x] 有界バッファ（`capacity > 0`）で満杯時に送信タスクが確実に `'waiting-channel` へサスペンドし、下流の `channel-recv!` に伴い送信待機タスクが起床・昇格すること（バックプレッシャー解消）。
- [x] 送受信で渡されるオブジェクトポインタの同一性（`eq?` によるゼロコピー Move）および `broadcast-send!` のディープコピー分離が検証されること。
- [x] ILisp (`ilisp/` および `tests/ilisp/`) には一切の変更を加えていないこと。
- [x] `tests/concurrency/test_channel.scm` の全テストケースがネイティブコンパイル実行 (`make -C ulisp test_channel`) で 100% PASS すること（107/107 assertions PASS）。
- [x] S 式構文・括弧バランス検査 (`make -C ulisp lint_sexpr`) および品質ゲート (`make format`, `make static_analysis`) がエラー 0 件で PASS すること。
- [x] ドキュメント内のすべてのリンクが相対パスで記述されており、絶対パス指定が 0 件であること。
