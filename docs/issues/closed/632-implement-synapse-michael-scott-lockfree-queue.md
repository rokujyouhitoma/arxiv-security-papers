---
title: "[FEAT] Michael-Scott ノンブロッキング・ロックフリーキューの実装 (ID: 632)"
ステータス: Closed (Completed 2026-10-31)
優先度: High (P1)
担当エージェント:
  -Project Manager (PM) (Chair / Governance)
  -IT Specialist (Programming Languages & Compilers / PLC)
  -Software Development (SWD)
  -Systems Architect
  -Information Security Specialist
  -Software Quality Assurance Specialist
作成日: 2026-10-31
更新日: 2026-10-31
---

# Issue #632: [FEAT] Michael-Scott ノンブロッキング・ロックフリーキューの実装

## 1. 概要 (Summary)

[DSN-37: Synapse Dual-Plane Concurrent Runtime Architecture](../../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md)（第 6 章「排他制御の現実解：Michael-Scott ロックフリーキュー」および第 14.3 節 Phase 1 Task 1.1）に基づき、スピンロックや OS ミューテックスを一切使用せず、[Issue #631](631-implement-synapse-low-level-atomic-primitives.md) で実装したハードウェア CAS プリミティブ（`atomic-cas!` / `<atomic-box>` / `<atomic-stamped-box>`）のみを用いて動作する **Michael-Scott ノンブロッキング FIFO キュー (`<lock-free-queue>`)** を Pure uLisp Scheme で実装する。

本モジュールは、後続の [Issue #633: 線形所有権移譲チャネル (`channel.scm`)](../633-implement-synapse-first-class-p2p-channel.md) におけるメッセージバッファキュー（`message-queue`）および送受信待機タスクキュー（`recv-wait-queue` / `send-wait-queue`）、さらに [Issue #635: 分散 M:N ワークスティーリングスケジューラ (`scheduler.scm`)](../635-implement-synapse-work-stealing-scheduler.md) のグローバルインジェクションキューの中核データ構造として機能する。

先行する [Issue #630](630-implement-synapse-task-independent-bump-arena.md)・[Issue #631](631-implement-synapse-low-level-atomic-primitives.md) と同様、**uLisp 専用スコープ**（`ilisp/` への組み込みや `tests/ilisp/` でのテストは行わない）および [DSN-37 セクション 13.4](../../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md) の**オンデマンド・モジュールロード設計**（コアランタイムにはバンドルせず、`include` / `load` / `import` の 3 方式で利用可能）を厳格に遵守する。

---

## 2. ガバナンス・専門エージェント多角レビュー (Governance & Multi-Agent Reviews)

1. **Project Manager (PM) [Chair]**:
   - DSN-37 Phase 1（通信 & ロックフリー同期）の最初のマイルストーン（Task 1.1）。完了済みの [Issue #631](631-implement-synapse-low-level-atomic-primitives.md) を基盤とし、後続の [Issue #633](../633-implement-synapse-first-class-p2p-channel.md)（チャネル）および [Issue #635](../635-implement-synapse-work-stealing-scheduler.md)（スケジューラ）の直接の前提条件となる。スコープは uLisp ランタイム（`ulisp/`）および `tests/concurrency/` に限定する。
2. **IT Specialist (Programming Languages & Compilers / PLC)**:
   - `ulisp/runtime/concurrency/queue.scm` が `atomic.scm` のインラインハードウェア命令 `atomic-cas!`（x86-64 `lock cmpxchg qword ptr [rdx + 11], rcx`）および `<atomic-stamped-box>` を直接活用し、関数呼び出しやボクシングのオーバーヘッドを最小化した S 式レコード構造でコンパイルされることを保証する。
3. **Software Development (SWD)**:
   - Michael & Scott (PODC 1996) の正規アルゴリズムに従い、センチネル（ダミー）ヘッドノード方式を採用する。特に `tail` ポインタの更新が 1 ステップ遅れている状態（Lagging Tail: `head == tail` かつ `head.next != #f`、または `tail.next != #f`）を他スレッドが検知した際、`atomic-cas!` で `tail` の前進を協調支援（Helping）するノンブロッキング不変条件を厳密に実装する。
4. **Systems Architect**:
   - DSN-37 セクション 6.3 の「ABA 問題の完全抑止（世代タグ付きポインタまたは事前確保済み固定長フリーリスト）」を満たすため、`<atomic-stamped-box>` による 64-bit 世代スタンプ付きロックフリー・ノードフリーリスト（`<queue-node-pool>`）を統合し、定常状態でのヒープアロケーション削減と ABA 問題の構造的排除を両立する。
5. **Information Security Specialist**:
   - デキュー完了後の旧ダミーノード（または次のダミーへ昇格した `next` ノード）にペイロード参照が残存すると、長寿命キューにおいて不要オブジェクトが GC 回収されないメモリリーク（CWE-401 / Memory Retention DoS）を引き起こす。デキュー CAS 成功直後に昇格ノードの `value` スロットを `#f` でゼロクリア（参照切断）する緩和策を必須化する。また CWE-843（Type Confusion）対策として全公開 API で `lock-free-queue?` / `queue-node?` の型検証を強制する。
6. **Software Quality Assurance Specialist**:
   - 空キューからのデキュー（`#f` 返却）、単一要素の Enqueue/Dequeue 境界条件（`head == tail` 遷移）、Lagging Tail 状態からの自動 Helping 回復、10,000 要素の連続 FIFO 順序保証、ノードプール再利用時の ABA 防止検証、および不正引数ガードを網羅するテストスイート `tests/concurrency/test_queue.scm` を整備する。
7. **Database / Data Infrastructure Specialist**:
   - WAL ログフラッシュキューや非同期クエリバッチキューとして利用した際にも、FIFO 順序性（Linearizability）が 100% 維持される設計とする。
8. **Network Specialist**:
   - 高負荷パケット・イベントディスパッチ時に、`#f` 自体を正当なメッセージ値として送受信したいケースにも対応できるよう、`dequeue-lockfree!` にデフォルト値指定（`(dequeue-lockfree! q [empty-default])`）およびステータス付き取得（`dequeue-lockfree-with-status!`）を提供する。
9. **IT Specialist (NLP & Info Retrieval)**:
   - ストリーミング文書トークナイザの Producer-Consumer パイプラインでゼロロック受け渡しが可能となることを確認する。
10. **IT Strategist**:
    - OS カーネルロック（`futex` 等）へのフォールバックを一切持たない Wait-Free / Lock-Free 協調 Helping 構造により、コンテキストスイッチ遅延ゼロの通信基盤を確立する。
11. **IT Service Manager**:
    - 運用可観測性（Observability）のため、キューごとの累計エンキュー数・累計デキュー数・CAS リトライ回数を取得できる `queue-stats` テレメトリ API を提供する。
12. **Embedded Systems Specialist**:
    - 事前確保済み固定長ノードプール（`make-queue-node-pool`）を用いることで、組込み・省メモリ環境でも動的ヒープ拡張なしに決定論的メモリフットプリントで稼働可能とする。
13. **Systems Auditor**:
    - DSN-37、完了済み Issue #630・#631、および後続 Issue #633〜#645 との双方向トレーサビリティと相対パスリンク規約（絶対パス 0 件）を監査する。
14. **UI/UX & Documentation Designer**:
    - R7RS `(import (ulisp concurrency queue))` と `(load ...)` / `(include ...)` の利用方法を明快に整理し、後続モジュール（`channel.scm` 等）からの依存関係を一貫させる。
15. **Education Specialist**:
    - Michael-Scott キューにおけるセンチネルノードの役割と 2 段階 CAS（`tail.next` 接続 → `tail` 前進）の協調 Helping メカニズムをコード内コメントで明快に解説する。
16. **Application Specialist (APS)**:
    - `queue-empty?`, `queue-size`, `queue-peek`, `queue->list` などの高水準インスペクション API を揃え、チャネル層やスケジューラ層から直感的に操作できるようにする。

---

## 3. 脅威分析とセキュリティ要件 (Threat Modeling & Security Requirements)

| 脅威 ID | STRIDE 分類 | 対象 CWE | 脅威シナリオ | 緩和策・セキュリティ設計 |
| :--- | :--- | :--- | :--- | :--- |
| **TM-632-01** | Tampering / Elevation of Privilege | CWE-843 (Type Confusion) | `enqueue-lockfree!` や `dequeue-lockfree!` に `<lock-free-queue>` 以外のオブジェクトを渡すことで、内部レコードスロットを誤参照・破壊する。 | 全公開手続き（`enqueue-lockfree!`, `dequeue-lockfree!`, `queue-empty?`, `queue-size`, `queue-peek`, `queue-stats` 等）の入口で `(lock-free-queue? q)` 検査を強制し、型違反時は即座に `error` を送出する。 |
| **TM-632-02** | Denial of Service | CWE-833 (Deadlock / Livelock via Lagging Tail) | エンキュー中のタスクが `tail.next` の CAS に成功した直後、`tail` 自体の更新前にプリエンプトされると、他タスクが永遠に `tail.next != #f` を見て進行不能（ライブロック）に陥る。 | Michael-Scott の Helping 機構を厳密に実装し、`enqueue-lockfree!` および `dequeue-lockfree!` の双方で `tail.next != #f` を検知したスレッドが `(atomic-cas! (lock-free-queue-tail q) tail next)` を代行実行してシステム全体の進行（Lock-Freedom）を保証する。 |
| **TM-632-03** | Tampering | CWE-416 (ABA Problem on Recycled Queue Nodes) | フリーリストから再利用された `<queue-node>` が偶然同一アドレスに再配置され、古い `head` または `tail` を観測していたスレッドの CAS が誤って成功しキュー構造が破損する。 | ノードプール（`<queue-node-pool>`）のフリーリストヘッドに [Issue #631](631-implement-synapse-low-level-atomic-primitives.md) の `<atomic-stamped-box>`（世代スタンプ付き CAS）を採用し、またプール返却時にノードの `next` ボックスを新規初期化／世代管理することで ABA 問題を構造的に抑止する。 |
| **TM-632-04** | Denial of Service | CWE-401 (Memory Leak via Sentinel Payload Retention) | `dequeue-lockfree!` で `head` が `next` ノードへ前進した際、`next` ノードが新しいセンチネル（ダミー）ノードとなるが、`next` の `value` フィールドにデキュー済みオブジェクトへの参照が残ると GC で回収されずリークする。 | `dequeue-lockfree!` において `(atomic-cas! (lock-free-queue-head q) head next)` が成功した直後、新しいセンチネルとなった `next` の値スロットを `(queue-node-value-set! next #f)` で即座にクリアし、旧 `head` の `next` ポインタも切断して GC 回収可能性を保証する。 |

---

## 4. トレーサビリティ (Traceability)

- **親設計ドキュメント**:
  - [DSN-37: Synapse Dual-Plane Concurrent Runtime Architecture](../../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md)（第 6 章「排他制御の現実解：Michael-Scott ロックフリーキュー」、第 13.4 節「並行ランタイムモジュールのロード設計」、第 14.3 節「Phase 1 Task 1.1: Michael-Scott ロックフリーキューの実装」）
- **先行 Issue (完了済)**:
  - [Issue #630: プロセスローカル・エフェメラルアリーナおよび O(1) 瞬時全破棄機構の実装](630-implement-synapse-task-independent-bump-arena.md)
  - [Issue #631: Scheme 低レベルアトミック命令 (atomic-cas! / atomic-box) の提供](631-implement-synapse-low-level-atomic-primitives.md)
- **後続・依存先 Issue**:
  - [Issue #633: 線形所有権移譲チャネルおよび有界バックプレッシャー機構の実装](../633-implement-synapse-first-class-p2p-channel.md)
  - [Issue #635: 分散 M:N ワークスティーリングスケジューラおよび Chase-Lev Deque の実装](../635-implement-synapse-work-stealing-scheduler.md)
  - [Issue #643: 10 万並行マイクロタスク耐久ベンチマークおよび STW-GC ゼロ検証スイートの実装](../643-implement-synapse-benchmark-suite-and-stw-gc-verification.md)
  - [Issue #645: CI 向けマルチコア並行競合テストハーネス (concurrency_harness.scm) の実装](../645-implement-synapse-multicore-concurrency-ci-harness.md)

---

## 5. 影響範囲と関連ファイル (Scope and Affected Files)

> [!IMPORTANT]
> ユーザー指示および DSN-37 の方針に基づき、実装およびテストの対象は **uLisp のみ**（`ulisp/` および `tests/concurrency/`）とする。`ilisp/` への組み込みや `tests/ilisp/` でのテスト追加は一切行わない。また、`ulisp/stdlib_entry.scm` や `ULISP_RUNTIME_LIBS` にはバンドルせず、オンデマンドロード方式とする。

### 新規作成ファイル
- [`ulisp/runtime/concurrency/queue.scm`](../../../ulisp/runtime/concurrency/queue.scm):
  - `<queue-node>`, `<lock-free-queue>`, `<queue-node-pool>` のレコード定義、および `enqueue-lockfree!`, `dequeue-lockfree!`, `dequeue-lockfree-with-status!`, `queue-empty?`, `queue-size`, `queue-peek`, `queue->list`, `queue-stats`, ABA 安全な事前確保済み固定長フリーリスト操作一式の実装。
- [`ulisp/lib/ulisp/concurrency/queue.sld`](../../../ulisp/lib/ulisp/concurrency/queue.sld):
  - R7RS `(import (ulisp concurrency queue))` 用のライブラリ定義ファイル（内部で `ulisp/runtime/concurrency/queue.scm` をインクルード）。
- [`tests/concurrency/test_queue.scm`](../../../tests/concurrency/test_queue.scm):
  - Michael-Scott キューの FIFO 整合性、Lagging Tail Helping 回復、空キュー境界条件、固定長フリーリストによる ABA 防止、10,000 要素耐久ストレス、および型安全性ガードの単体テストスイート。

### 変更対象ファイル
- [`ulisp/Makefile`](../../../ulisp/Makefile):
  - `lint_sexpr` 対象ファイルに `runtime/concurrency/queue.scm`, `lib/ulisp/concurrency/queue.sld`, `$(ROOT_DIR)/tests/concurrency/test_queue.scm` を追加。
  - `test_queue` ターゲットを追加し、`test` ターゲットへ統合。

---

## 6. 実装方針 (Implementation Plan)

- **ターゲットブランチ**: `feat/632-michael-scott-queue`

### Step 1: `<queue-node>` および ABA 安全な固定長フリーリスト (`<queue-node-pool>`) の実装
1. **`<queue-node>` レコード定義 (DSN-37 Section 6.1)**:
   - `(define-record-type <queue-node> (%make-queue-node value next) queue-node? (value %queue-node-value %queue-node-value-set!) (next %queue-node-next %queue-node-next-set!))`
   - `make-queue-node`: `case-lambda` により 1 引数 `(make-queue-node val)`（`next` を `(make-atomic-box #f)` で自動初期化）および DSN-37 互換の 2 引数 `(make-queue-node val next-box)` の双方をサポートする。
2. **事前確保済み固定長フリーリスト (`<queue-node-pool>`, DSN-37 Section 6.3)**:
   - `(define-record-type <queue-node-pool> (%make-queue-node-pool top-stamped capacity available-box) queue-node-pool? ...)`
   - `(make-queue-node-pool [capacity])`: 指定個数 `capacity` の `<queue-node>` を事前確保して単方向リストに連結し、`<atomic-stamped-box>`（世代スタンプ初期値 `0`）で管理する。
   - `(queue-pool-acquire! pool val)` / `(pool-alloc-node! pool val)`: `<atomic-stamped-box>` の世代スタンプを `+1` しながらヘッドノードを CAS ポップして初期値 `val` を設定する（プール枯渇時は安全に動的ノード確保へフォールバック）。
   - `(queue-pool-release! pool node)` / `(pool-free-node! pool node)`: ノードの `value` と `next` をクリアした上で、`<atomic-stamped-box>` の世代スタンプを `+1` しながら CAS プッシュで返却する。これにより `A -> B -> A` のポインタ再利用が起きても世代スタンプが異なるため ABA 問題を 100% 阻止できる。

### Step 2: `<lock-free-queue>` 本体と Michael-Scott Enqueue / Dequeue アルゴリズムの実装
1. **`<lock-free-queue>` レコード定義**:
   - `(define-record-type <lock-free-queue> (%make-lock-free-queue head tail count-box pool enqueue-count-box dequeue-count-box) lock-free-queue? ...)`
   - `make-lock-free-queue`: `case-lambda` により：
     - `()` (0 引数): ダミー（センチネル）ノード `(make-queue-node #f (make-atomic-box #f))` を 1 つ生成し、`head` と `tail` の `<atomic-box>` が共にそのダミーノードを指す状態で初期化する。
     - `(pool-or-cap)` (1 引数): 整数 `cap` または `<queue-node-pool>` を受け取り、事前確保済みノードプールを紐付けたロックフリーキューを生成する。
     - `(head-box tail-box)` (2 引数): DSN-37 セクション 6.1 の 2 引数コンストラクタ互換。
2. **`enqueue-lockfree!` (および別名 `queue-enqueue!`)**:
   - DSN-37 セクション 6.2 のアルゴリズムに準拠：
     1. 新規ノード `node` を（プールがあれば `pool-alloc-node!`、なければ `make-queue-node` で）用意する。
     2. `tail = (atomic-ref (lock-free-queue-tail queue))`、`next = (atomic-ref (queue-node-next tail))` を読み取る。
     3. `tail` が変わっていないか再確認し、`next` が `#f` であれば `(atomic-cas! (queue-node-next tail) #f node)` を試行する。
     4. 成功したら `(atomic-cas! (lock-free-queue-tail queue) tail node)` で `tail` を前進させ、要素数カウンタと累計エンキュー数を `atomic-fetch-add!` で `+1` して `#t` を返す。
     5. もし `next` が `#f` でなければ（他スレッドの Enqueue 途中 = Lagging Tail）、`(atomic-cas! (lock-free-queue-tail queue) tail next)` で `tail` の前進を支援（Helping）してからリトライする。
3. **`dequeue-lockfree!` (および別名 `queue-dequeue!`, `dequeue-lockfree-with-status!`)**:
   - DSN-37 セクション 6.2 のアルゴリズムに準拠：
     1. `head = (atomic-ref (lock-free-queue-head queue))`、`tail = (atomic-ref (lock-free-queue-tail queue))`、`next = (atomic-ref (queue-node-next head))` を読み取る。
     2. `head` が変わっていないか再確認する。
     3. `(eq? head tail)` の場合：
        - `(not next)` ならキューは空であり、デフォルト値（省略時 `#f`）を即座に返す。
        - `next` が存在する場合は `tail` が遅れている（Lagging Tail）ため、`(atomic-cas! (lock-free-queue-tail queue) tail next)` で `tail` を前進させてからリトライする。
     4. `(not (eq? head tail))` の場合：
        - `val = (queue-node-value next)` を読み取る。
        - `(atomic-cas! (lock-free-queue-head queue) head next)` を試行する。
        - 成功したら、新しくセンチネルとなった `next` の値スロットを `(queue-node-value-set! next #f)` でクリア（CWE-401 緩和）し、要素数カウンタを `-1`、累計デキュー数を `+1`（プール使用時は旧 `head` をプールへ返却）して `val` を返す。
4. **インスペクション・ユーティリティ手続き**:
   - `(queue-empty? queue)`: キューが空なら `#t`、要素があれば `#f`（Lagging Tail 時は Helping を行う）。
   - `(queue-size queue)`: 現在のキュー内要素数を返す。
   - `(queue-peek queue [default])`: 先頭要素を削除せずに返す（空なら `default` または `#f`）。
   - `(queue->list queue)`: 現在のキュー内要素を FIFO 順のリストとして非破壊的に取得する。
   - `(queue-stats queue)`: `((size . N) (enqueued . E) (dequeued . D) (has-pool? . B))` の連想リストを返す。

### Step 3: 単体・耐久テストスイート (`tests/concurrency/test_queue.scm`) の作成
1. `tests/concurrency/test_queue.scm` を作成し、以下のテストグループを実装する：
   - **Group 1**: キュー初期化・述語検証・空キューからの `dequeue-lockfree!` / `queue-peek` / `queue-empty?` 境界条件。
   - **Group 2**: 単一および複数要素の FIFO 順序整合性検証（数値・シンボル・リスト・`#f` 値を含むエンキュー／デキュー）。
   - **Group 3**: Lagging Tail（`tail` ポインタが `head` に遅れた中間状態）を意図的に構築し、`enqueue-lockfree!` / `dequeue-lockfree!` / `queue-peek` が CAS Helping によって自動回復することのホワイトボックス検証。
   - **Group 4**: センチネル昇格時のペイロード参照クリア（CWE-401 緩和）検証。
   - **Group 5**: 事前確保済み固定長フリーリスト（`<queue-node-pool>`）を用いたノードリサイクル・世代スタンプによる ABA 問題抑止検証、および 10,000 回のインターリーブ Enqueue/Dequeue 耐久ストレステスト。
   - **Group 6**: 型混同ガード（CWE-843）および R7RS `(import (ulisp concurrency queue))` ロード検証。

---

## 7. 完了条件 (Success Criteria / Definition of Done)

- [x] `ulisp/runtime/concurrency/queue.scm` および `ulisp/lib/ulisp/concurrency/queue.sld` が実装され、`include` / `load` / `import` の 3 方式すべてでオンデマンドロード可能であること（コアランタイムにはバンドルしないこと）。
- [x] `<queue-node>`, `<lock-free-queue>`, `<queue-node-pool>`, `enqueue-lockfree!`, `dequeue-lockfree!`, `dequeue-lockfree-with-status!`, `queue-empty?`, `queue-size`, `queue-peek`, `queue->list`, `queue-stats` が実装されていること。
- [x] 空キューからの `dequeue-lockfree!` が即座に `#f`（または指定デフォルト値）を返すこと。
- [x] Lagging Tail 状態からの CAS Helping 推進、デキュー後のセンチネルノード値クリア（CWE-401 対策）、および `<atomic-stamped-box>` フリーリストによる ABA 抑止が機能すること。
- [x] ILisp (`ilisp/` および `tests/ilisp/`) には一切の変更を加えていないこと。
- [x] `tests/concurrency/test_queue.scm` の全テストケースがネイティブコンパイル実行 (`make -C ulisp test_queue`) で 100% PASS すること（102/102 アサーション PASS）。
- [x] S 式構文・括弧バランス検査 (`make -C ulisp lint_sexpr`) および品質ゲート (`make format`, `make static_analysis`) がエラー 0 件で PASS すること。
- [x] ドキュメント内のすべてのリンクが相対パスで記述されており、絶対パス指定が 0 件であること。

