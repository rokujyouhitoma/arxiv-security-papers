---
ID: 669
種別: Feature
優先度: Medium
ステータス: Closed
---

# [FEAT] 動的タスク再起動を透過化する Synapse プロセス名レジストリ (Registry) と透過的チャネル再バインド機構の実装 (ID: 669)

## 1. 概要 / Summary
Erlang/OTP のプロセス名登録機構（Process Registry: `register/2`, `whereis/1`, `unregister/1`）を参考に、Synapse 並行ランタイムにタスクおよび通信チャネルの論理名レジストリ（`registry.scm` & `(ulisp concurrency registry)`）を導入する。

Synapse ではスーパービジョンツリー（Issue #667）および Fail-Fast "Let It Crash" セマンティクス（Issue #668）により、異常を検知したタスクはエフェメラルアリーナごと即座に破棄・再起動される。その際、タスクの物理 ID（TID）やローカルアリーナ上のチャネルアドレスは新しく割り当て直される。
プロセス名レジストリを導入することにより、クライアントタスクは相手の物理ポインタや可変な TID ではなく論理名（Symbol）を参照して通信を行い、スーパーバイザによる再起動時にも透過的なチャネル再バインド（`synapse-rebind!`）と自動ルーティング（`synapse-send-named!`）によって障害復旧をクライアント側から完全に透過化する。

---

## 2. トレーサビリティ / Traceability
- **関連設計書**:
  - [DSN-37 ホスト・カーネル分離型 階層 CSP/アクター並行処理基盤](../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md) (Section 8.4.5 & Section 14.8 Task 6.4)
- **関連 Issue**:
  - [Issue #633: 線形所有権移譲チャネルの実装](closed/633-implement-synapse-first-class-p2p-channel.md)
  - [Issue #635: ワークスティーリングスケジューラの実装](closed/635-implement-synapse-work-stealing-scheduler.md)
  - [Issue #666: タスク間双方向リンクと単方向モニタの実装](closed/666-implement-synapse-task-links-and-monitors.md)
  - [Issue #667: Erlang/OTP スーパービジョンツリーと再起動戦略の実装](closed/667-implement-synapse-supervision-tree-and-restart-strategies.md)
  - [Issue #668: エフェメラルアリーナ即時破棄と Fail-Fast セマンティクスの確立](closed/668-implement-synapse-fail-fast-let-it-crash-semantics.md)
  - [Issue #675: Linux ネイティブスレッドプールと CPU コアピニングの実装](closed/675-implement-synapse-native-multithread-worker-pool.md)
  - [Issue #676: Linux SYS_futex による省電力ワーカー待機・起床機構の実装](closed/676-implement-synapse-futex-park-unpark-primitives.md)

---

## 3. セキュリティ・脅威分析 (STRIDE & CWE Mitigations)

| 脅威分類 (STRIDE) | 脆弱性 (CWE) | 想定される脅威シナリオ | 本実装での防御・緩和策 |
| :--- | :--- | :--- | :--- |
| **Tampering / Information Disclosure** | **CWE-416** (Use-After-Free) | タスクがクラッシュしてアリーナが回収された後、旧チャネルアドレスへのメッセージ送信により解放済みメモリを破壊・読み出し | タスク終了・クラッシュ時にレジストリエントリを即時破棄（Unregister）またはアトミックに新チャネルへ差し替え（Rebind）。無効な宛先への送信は `'dead_process` または `'not_found` で安全に拒絶。 |
| **Denial of Service** | **CWE-362** (Race Condition / Concurrent Registration) | 複数ネイティブワーカースレッドが同一論理名を同時に登録・更新しようとしてレジストリ内部構造が破損 | アトミック CAS（`atomic-cas!`）またはアトミックボックスによる線形化可能（Linearizable）なエントリ更新。二重登録時は安全に失敗（`#f` または例外）。 |
| **Denial of Service** | **CWE-400** (Uncontrolled Resource Consumption) | 無制限なシンボル名登録によるレジストリ肥大化、メモリ枯渇、ハッシュ衝突 DoS | `*registry-max-entries*`（上限 65,536 件）を強制し、上限超過時は登録を拒絶。エントリごとの固定アリーナ確保。 |
| **Denial of Service** | **CWE-833** (Deadlock) | 宛先タスクが終了・クラッシュ中に `synapse-send-named!` を呼び出し、無限待機やロック競合でワーカースレッドが停止 | ロックフリーな名前解決とノンブロッキング送信。名前が存在しないか無効な場合は即座にステータスシンボル（`'not_found` / `'dead_process`）を返却。 |
| **Type Confusion** | **CWE-843** (Type Confusion) | 非シンボル型（文字列、整数、リスト等）を名前として登録、または不正なオブジェクトを通信先として設定 | `symbol?` 述語による登録名チェック、および `channel?` / `budgeted-task?` / 手続き型述語による通信対象の事前型バリデーション。 |

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files

### 新規作成ファイル
- [ulisp/runtime/concurrency/registry.scm](../../ulisp/runtime/concurrency/registry.scm)
  - Synapse プロセス名レジストリの中核ランタイム実装。
  - レコード型 `<process-registry>`, `<registry-entry>`。
  - ロックフリー・スレッドセーフな `synapse-register!`, `synapse-unregister!`, `synapse-whereis`, `synapse-rebind!`, `synapse-send-named!` API。
- [ulisp/lib/ulisp/concurrency/registry.sld](../../ulisp/lib/ulisp/concurrency/registry.sld)
  - R7RS ライブラリ定義 `(ulisp concurrency registry)`。
- [tests/concurrency/test_registry.scm](../../tests/concurrency/test_registry.scm)
  - プロセス名レジストリ専用の包括的単体・並行・耐障害性テストスイート。

### 変更対象ファイル
- [ulisp/runtime/concurrency/supervisor.scm](../../ulisp/runtime/concurrency/supervisor.scm)
  - スーパーバイザ再起動ルーチンにおける論理名自動再バインド（`synapse-rebind!`）連携。
- [ulisp/runtime/concurrency/eval_adapter.scm](../../ulisp/runtime/concurrency/eval_adapter.scm)
  - レジストリ関連プリミティブのフォールバックスタブおよび評価環境バインド。
- [ulisp/runtime/concurrency/channel.scm](../../ulisp/runtime/concurrency/channel.scm)
  - チャネルクローズ時・毒化（Poisoning）時のレジストリ通知連携（オプションフック）。
- [ulisp/Makefile](../../ulisp/Makefile)
  - `test_registry` ターゲットの追加および `test` / `lint_sexpr` 依存関係への統合。

---

## 5. 実装計画 / Implementation Plan

Target Branch: `feat/669-synapse-process-registry`

### Step 1: プロセス名レジストリ中核データ構造 (`registry.scm`)
1. **レコード定義**:
   - `<registry-entry>`: `name` (Symbol), `target-box` (Atomic Box holding `<channel>`, `<budgeted-task>`, or TID), `mon-ref` (Monitor Ref or `#f`), `epoch` (Generation Counter).
   - `<process-registry>`: `table-box` (Atomic Box holding vector of buckets / association list), `count-box` (Atomic Box of current size), `max-capacity` (Fixnum, default 65536).
2. **グローバルデフォルトレジストリ**:
   - `*default-synapse-registry*`: プロセス全体で共有されるデフォルトレジストリインスタンス。
   - `(current-synapse-registry)` / `(with-synapse-registry reg thunk)`: 動的スコープ切り替え対応。

### Step 2: レジストリ基本操作 API の実装
1. **`synapse-register!`**:
   - シグネチャ: `(synapse-register! [reg] name target)`
   - 二重登録検査: 既に `name` が登録されている場合は `#f` を返す（またはオプションでエラー）。
   - 型検査 (CWE-843): `name` は `symbol?`、`target` は `channel?` または `budgeted-task?`。
   - 容量検査 (CWE-400): `count >= max-capacity` の場合は登録拒絶。
2. **`synapse-unregister!`**:
   - シグネチャ: `(synapse-unregister! [reg] name)`
   - 登録済みエントリをアトミックに削除。成功時は `#t`、未登録時は `#f`。
3. **`synapse-whereis`**:
   - シグネチャ: `(synapse-whereis [reg] name)`
   - 高速 O(1) ルックアップ。登録先ターゲット（チャネルまたはタスク）を返却。未登録の場合は `#f`。
4. **`synapse-registered-names`**:
   - シグネチャ: `(synapse-registered-names [reg])`
   - 現在登録されている全シンボルのリストを返却。

### Step 3: 動的チャネル再バインドと透過的ルーティング
1. **`synapse-rebind!`**:
   - シグネチャ: `(synapse-rebind! [reg] name new-target)`
   - 指定された `name` のターゲットをアトミックに `new-target` に更新（CAS 更新）。未登録の場合は新規登録。
   - スーパーバイザ再起動時に古いタスクの参照をアトミックに切り替える。
2. **`synapse-send-named!`**:
   - シグネチャ: `(synapse-send-named! [reg] name msg)`
   - `synapse-whereis` で名前解決を行い、ターゲットがチャネルであれば `channel-send!`、タスクであればタスクの受信チャネルへ送信。
   - 送信成功時は `#t`、未登録時は `'not_found`、ターゲットがクローズ・クラッシュ済みの場合は `'dead_process` を返却（ノンブロッキング、デッドロック完全排除）。

### Step 4: スーパービジョンツリー (`supervisor.scm`) との統合
1. スーパーバイザの `<child-spec>` に論理名（`id` シンボル）が定義されている場合、子タスク起動時に自動的に `(synapse-rebind! child-id child-task-or-channel)` を実行。
2. 子タスクがクラッシュして再起動された際、新しく生成された子タスクのチャネルを同名で即座に `synapse-rebind!`。
3. クライアント側は `(synapse-send-named! 'worker_service msg)` を呼び出すだけで、再起動前後を問わず同一コードで最新タスクへメッセージ到達。

### Step 5: テストスイート拡充と品質ゲート検証
1. **`tests/concurrency/test_registry.scm` の作成**:
   - **Group 1**: 基本 API 検証（`register!`, `whereis`, `unregister!`, `registered-names`）。
   - **Group 2**: 二重登録拒絶および境界値・型検査（CWE-843, CWE-400）。
   - **Group 3**: アトミックな動的再バインド（`synapse-rebind!`）と `synapse-send-named!` ルーティング。
   - **Group 4**: スーパーバイザ障害復旧統合（タスクパニック $\to$ 再起動 $\to$ 名前解決による透過的通信継続）。
   - **Group 5**: マルチコア並列高スループット競合テスト（複数ワーカーによる並行登録・検索・送信、10,000 操作）。
   - **Group 6**: クラッシュ時・クローズ時エラーハンドリングとデッドロックフリー検証（CWE-833, CWE-416）。
2. **`ulisp/Makefile` への `test_registry` 統合**:
   - `build/test_registry` ビルドターゲットおよび `test:` への追加。
   - `make -C ulisp test` の 100% PASS 保証。

---

## 6. 完了条件 / Success Criteria (DoD)

- [x] `registry.scm` および `(ulisp concurrency registry)` が実装され、`synapse-register!`, `synapse-unregister!`, `synapse-whereis`, `synapse-rebind!`, `synapse-send-named!` が提供されること。
- [x] スーパーバイザ配下のタスクがパニック・クラッシュして再起動した際、`synapse-whereis` および `synapse-send-named!` 経由で新タスクのチャネルへ透過的にメッセージが配送されること。
- [x] 複数ネイティブワーカースレッドからの並行登録・検索・再バインドにおいてデータ競合（CWE-362）が発生せず、線形化可能性が保たれること。
- [x] 未登録または終了済みタスクへの送信時にハングやデッドロック（CWE-833）を起こさず、適切なステータスコードを即座に返却すること。
- [x] `make -C ulisp test_registry`（全テスト PASS）および全体の `make -C ulisp test` が 100% エラーなく完走すること。
- [x] Python 品質ゲート（`make py_compile` および `make static_analysis`）が 100% PASS すること。
- [x] 相対パス規則（Gate 3）の完全適合（絶対パス 0 件）。

---

## 7. レビューア・担当エージェント
- **主幹**: IT Specialist (Programming Languages & Compilers / PLC)
- **並行基盤設計**: Systems Architect
- **耐障害性・セキュリティ監査**: Information Security Specialist & Systems Auditor
- **品質保証**: Software Quality Assurance Specialist
