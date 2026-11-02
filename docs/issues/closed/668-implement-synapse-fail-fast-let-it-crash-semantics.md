---
ID: 668
種別: Feature
優先度: Medium
ステータス: Closed (Resolved)
---

# [FEAT/ENH] エフェメラルアリーナ O(1) 即時破棄と融合した Fail-Fast "Let It Crash" セマンティクスおよびパニック機構の確立 (ID: 668)

## 1. 概要 / Summary
Erlang の "Let It Crash" 哲学（不正な入力や不変条件違反に直面した際、中途半端な防御的コードで例外を握りつぶさず即座に死ぬ）を、Synapse のプロセスローカル・エフェメラルアリーナ（Shared-Nothing）および AOT/並行ランタイムと統合する。
タスクローカルなパニック機構（`synapse-panic!`）および表明ガード構文（`synapse-assert`）を整備し、タスク異常終了時にメモリを $O(1)$ でバンプリセットし、保有チャネルを安全に毒化・解放して新品状態でスーパーバイザ（Issue #667）に委ねることで、コードの簡潔化・高スループット化と状態汚染の完全遮断（Zero-State Contamination）を両立する。

---

## 2. 背景と根本課題 / Background & Problem Statement
1. **中途半端なエラー回復による状態汚染とバグの潜在化**:
   - 従来のプログラミング手法では、エラー発生時に呼び出しスタックの途中で catch して不完全な状態のまま処理を続行しがちであり、データ構造の不整合やメモリ破壊、潜在的な脆弱性を招く。
   - Erlang/OTP では「プロセスを即座にクラッシュさせ、新品のクリーンな状態でスーパーバイザに再起動させる」ことで、99.999% 以上の可用性と自己修復性を実現している。
2. **GC 走査コストおよびメモリリークの排除**:
   - タスククラッシュ時に汎用トレース GC を実行すると、全ヒープの走査遅延（Stop-The-World やマークフェーズ）が発生し、計算層（Layer 2）の決定論的リアルタイム性が破壊される。
   - Synapse はタスクごとに独立したエフェメラルバンプアリーナ（Shared-Nothing）を持つため、タスク死亡時にバンプポインタを 0 にリセットするだけで $O(1)$ でメモリ全量を回収できる。
3. **対向チャネル待機タスクのデッドロック防止（CWE-833）**:
   - 単にパニックで終了するだけでは、チャネルの待機キューにタスクが取り残され、送受信相手が永久にブロックされる。
   - Issue #666 で確立したタスクリンク・モニタおよびチャネル毒化（`task-poison-owned-channels!`）と融合し、パニック発生時にアトミックかつ即時に全待機相手をアンブロック脱出させる必要がある。

---

## 3. トレーサビリティ / Traceability
- **関連設計書**: [DSN-37 ホスト・カーネル分離型 階層 CSP/アクター並行処理基盤 (Section 8.4.4, 14.8 Task 6.3)](../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md)
- **関連 Issue**:
  - [Issue #630 (独立バンプアリーナ)](closed/630-implement-synapse-task-independent-bump-arena.md)
  - [Issue #633 (線形所有権移譲チャネル)](closed/633-implement-synapse-first-class-p2p-channel.md)
  - [Issue #638 (アフィン型検査とRAII Drop)](closed/638-implement-nanopass-check-affine-types-and-raii-drop.md)
  - [Issue #642 (世代管理型投機タスク破棄・アリーナ即時リセット)](closed/642-implement-synapse-epoch-fencing-distributed-rollback.md)
  - [Issue #666 (タスク間リンク・モニタ・チャネル毒化)](closed/666-implement-synapse-task-links-and-monitors.md)
  - [Issue #667 (Supervision Tree & 再起動戦略)](667-implement-synapse-supervision-tree-and-restart-strategies.md)（本 Issue と協調）

---

## 4. セキュリティ・脅威分析 (Threat Modeling & CWE Mitigations)

| 脅威 / 脆弱性 | リスク詳細 | 緩和・防御策 |
| :--- | :--- | :--- |
| **CWE-212: Exposure of Sensitive Information Through Data Left in Memory** | パニック発生時にアリーナ内に機密情報（認証トークン、暗号鍵等）が残留し、後続の再利用タスクから読み取られる | `synapse-panic!` 時にセキュアリセットモード（`arena-secure-reset!` によるゼロクリアスクラビング）を選択・適用可能とする |
| **CWE-400: Uncontrolled Resource Consumption** | クラッシュループやパニック連鎖によってアリーナやチャネルがリークし、ホストメモリを枯渇させる | バンプアリーナの $O(1)$ 即時破棄と保有チャネルの自動解放・RAII ドロップにより、メモリ・リソースリークを 0 に抑え込む |
| **CWE-833: Deadlock** | パニックしたタスクがチャネル待機中に死亡し、対向タスクが永久に起床されない | `task-poison-owned-channels!` をパニックハンドラ内で不可逆実行し、送受信両待機キューの全タスクを即座に `'poisoned` エラーで起床・脱出させる |
| **CWE-843: Type Confusion** | パニック理由コードや表明ガードに不正なオブジェクトが渡された際の型混同 | 全パニック・アサーション API のエントリポイントにおいて述語検査を厳格に実施 |

---

## 5. アーキテクチャと詳細設計 / Architectural & Technical Design

### 5.1 パニック機構の構造 (`panic.scm`)
```scheme
;; 1. パニック例外オブジェクト定義
(define-record-type <synapse-panic-record>
  (%make-synapse-panic-record reason details source-loc timestamp)
  synapse-panic-record?
  (reason      synapse-panic-reason)
  (details     synapse-panic-details)
  (source-loc  synapse-panic-source-loc)
  (timestamp   synapse-panic-timestamp))

;; 2. パニック脱出プリミティブ
(define (synapse-panic! reason . details)
  ;; カレントタスク境界の脱出ハンドラを呼び出し、スタック巻き戻しを開始
  (%invoke-task-panic-handler! reason details))
```

### 5.2 タスク保護実行境界 (`with-synapse-task-boundary`)
- タスク実行時（スケジューラまたはスレッド内）に `with-synapse-task-boundary` で保護。
- 通常終了時は戻り値を返却。
- パニック発生時：
  1. タスクの保有アリーナを $O(1)$ でリセット（通常は `arena-reset!`、セキュア時は `arena-secure-reset!`）。
  2. タスクが保有する全チャネルを毒化（`task-poison-owned-channels!`）。
  3. タスク状態を `'terminated` に更新。
  4. リンク先タスクおよび監視タスクへ `task-handle-termination!` で終了通知を配送（リンク先はカスケード道連れ終了または trap-exit 受信、監視者は DOWN 通知受信）。
  5. スケジューラ側へ `(cons 'panic <synapse-panic-record>)` を返却し、上位スーパーバイザに委ねる。

### 5.3 表明ガード構文 (`synapse-assert`)
- `(synapse-assert cond message [details...])`
- `cond` が `#f` の場合、即座に `(synapse-panic! 'assertion-violation message details...)` を発行。
- ASC (Affine Stream Core) における不変条件検査を最小コストで実現。

---

## 6. 実装計画 / Implementation Plan

Target Branch: `feat/668-synapse-fail-fast-let-it-crash`

### Step 1: パニックコアエンジン (`panic.scm` & `panic.sld`) の新設
- 対象ファイル: `ulisp/runtime/concurrency/panic.scm`, `ulisp/lib/ulisp/concurrency/panic.sld`
- 実装内容:
  1. `<synapse-panic-record>` のレコード定義と述語・アクセサ。
  2. `*current-task-panic-handler-box*` によるタスクローカルパニックハンドラ設定。
  3. `synapse-panic!` および `synapse-panic-record?` の実装。
  4. `synapse-assert` 表明構文・手続きの実装。

### Step 2: エフェメラルアリーナ・チャネル後処理の統合
- 対象ファイル: `ulisp/runtime/concurrency/panic.scm`, `ulisp/runtime/concurrency/arena.scm`
- 実装内容:
  1. `synapse-cleanup-task-resources! task [secure?]` の実装。
  2. バンプアリーナの $O(1)$ リセット（`arena-reset!`）呼び出し。
  3. 保有チャネルの自動毒化（`task-poison-owned-channels!`）呼び出し。
  4. リンク先・モニタ通知（`task-handle-termination!`）の安全な連動。

### Step 3: タスク保護境界ラッパー (`with-synapse-task-boundary`) の実装
- 対象ファイル: `ulisp/runtime/concurrency/panic.scm`
- 実装内容:
  1. 脱出継続（`call/cc` または例外ハンドラ）を用いたタスク実行境界の保護。
  2. パニック発生時における他タスク・親スレッドへの影響遮断（Zero-State Contamination）。
  3. 戻り値およびパニック結果の構造化。

### Step 4: スケジューラおよび評価器アダプタへの統合
- 対象ファイル: `ulisp/runtime/concurrency/eval_adapter.scm`, `ulisp/runtime/concurrency/scheduler.scm`
- 実装内容:
  1. `eval_adapter.scm` の環境に `synapse-panic!`, `synapse-assert` をエクスポート・バインド。
  2. スケジューラワーカーがタスクを実行する際、パニックを捕捉してタスクを安全に終了・クリーンアップする連携。

### Step 5: テストスイートの作成と品質ゲート検証
- 対象ファイル: `tests/concurrency/test_let_it_crash.scm`, `ulisp/Makefile`
- 実装内容:
  1. Group 1: 基本パニック動作と脱出境界の検証（他タスクへ影響しないこと）。
  2. Group 2: パニック時のアリーナ $O(1)$ 即時リセット検証（メモリリーク 0）。
  3. Group 3: パニック時の保有チャネル自動毒化と待機タスク脱出検証（CWE-833 排除）。
  4. Group 4: `synapse-assert` 表明違反時の Fail-Fast パニック検証。
  5. Group 5: リンク/モニタとの統合（パニックがスーパーバイザ・リンク先に正確に伝播すること）。
  6. Group 6: セキュリティ境界・CWE-843/CWE-212 ゼロスクラビング検証。

---

## 7. 完了条件 / Success Criteria (DoD)
- [x] `synapse-panic!` 呼び出し時に、他タスクのヒープやスタックを汚染することなく単一タスクのみがクリーンに停止・脱出すること。
- [x] パニック発生時にタスクのアリーナが $O(1)$ で即座にリセットされ、GC や走査コストを一切発生させないこと。
- [x] セキュアリセット指定時に、アリーナ内のメモリ領域がゼロクリア（ゼロスクラビング）されること（CWE-212 排除）。
- [x] パニック時にタスクが保有するチャネルが即座に毒化され、送受信待機中の対向タスクがデッドロックせずに脱出できること（CWE-833 排除）。
- [x] `synapse-assert` により事前条件違反が即座に検知され、詳細なエラーコンテキストを伴ってパニックすること。
- [x] リンク先タスクやモニタタスクへ、パニック理由が正確に通知されること（Issue #666 連携）。
- [x] `make -C ulisp test_let_it_crash`（全テスト PASS）および既存の並行性テスト群が 100% PASS すること。
- [x] 相対パス規則（Gate 3）の完全適合（絶対パス 0 件）。


