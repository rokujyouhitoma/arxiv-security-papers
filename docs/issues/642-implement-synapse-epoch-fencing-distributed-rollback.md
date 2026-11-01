---
ID: 642
種別: Feature
優先度: High
ステータス: Open (In Progress)
---

# [FEAT] 世代管理型投機タスク破棄および待機タスク世代ゲート検証の実装 (ID: 642)

## 1. 概要 / Summary

[DSN-37](../../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md) Phase 4 Task 4.2 に基づき、コントロールプレーン（Layer 1: R7RS）の継続（`call/cc`）に基づくバックトラック探索・ロールバックと連動し、無効化された世代（Epoch）に属する並列計算タスク群を即座に特定・強制アボートさせる **世代管理型投機タスク破棄（Generation-Based Speculative Cancellation：`epoch.scm`）** 機構を Pure Scheme で実装する。

従来の並列処理系（CSP / アクターモデル）では、投機的に並列起動された探索タスクが不要（枝刈り・探索失敗）となった場合でも、バックグラウンドで無益に CPU サイクルを消費し続けたり（ゾンビタスク問題）、外側スレッドが過去の状態に巻き戻った後に古いタスクがチャネルへ不要なメッセージを書き込んで状態を汚染する競合状態（Stale State Pollution / CWE-362）が深刻な課題であった。

本 Issue では、各並列タスク（`<task-context>`）に発行世代番号（Epoch ID）を不変バインドし、コントロールプレーンの探索チェックポイント復帰と同期して、無効化された世代のタスク群の命令バジェット（Reduction カウンタ）をアトミックにゼロ化して安全に強制停止させる。
さらに、チャネル待機（`TASK_WAITING_CHANNEL`）でスリープ中のタスクが不整合なメッセージを受信してゾンビ化することを防止するため、起床時に自身の世代と現在有効な世代をアトミック検証する **世代ゲート検証（Generation Gate：DSN-37 第 8.3 節）** 機構を確立する。アボートされたタスクは直ちにプロセスローカル・エフェメラルアリーナ（`<task-arena>`）を $O(1)$ 瞬時解放し、メモリリークゼロでの分散ロールバックを保証する。

---

## 2. ガバナンス・専門エージェント多角レビュー / Governance & Reviews

本 Issue は、リポジトリ統治規約（[`.agents/AGENTS.md`](../../../.agents/AGENTS.md)）に従い、PM 主導のもと全 16 専門エージェントによる多角的設計レビューを統合して策定された。

- **Project Manager (PM) (Chair / Governance)**:
  - Phase 4（ホスト・カーネル境界 ＆ 世代管理型投機タスク破棄）の最終マイルストーン（Task 4.2）として、Phase 5（10 万並行ベンチマーク #643）へ進むための不可欠な前提要件となる。Pure Scheme で実装し、外部 C 依存ゼロ、全並行テスト回帰合格を厳格に管理する。
- **IT Specialist (Programming Languages & Compilers / PLC)**:
  - `call/cc` の継続オブジェクトと Epoch 状態の連動を設計。Scheme の第 1 級継続による巻き戻し発生時、動的環境（Dynamic Wind / Parameterize）または明示的チェックポイント境界（`speculative-checkpoint`）により、過去の Epoch への回帰を決定論的に捕捉する。
  - AOT ネイティブコンパイル環境（`bin/ulisp-boot`）およびインタプリタ環境（ILisp / Gauche Dual-Mode）の双方で同一コードベースが動作するよう、アトミックボックス（`atomic-box`）を用いた不可分な世代更新・検証ロジックを構成する。
- **Systems Architect (SA)**:
  - DSN-37 第 8.2 節および第 8.3 節に基づき、Layer 1（R7RS コントロールプレーン）の非決定的探索・バックトラックと、Layer 2（ASC 計算プレーン）の決定論的 M:N 並行実行を疎結合に橋渡しする。タスク側にロックを一切持たせず、命令バジェットゼロ化（セーフポイント強制停止）と Generation Gate（チャネル起床時検証）の 2 重防壁で完全な非同期停止を実現する。
- **Information Security Specialist (SEC)**:
  - 不要となった投機タスクがリソースを浪費し続ける DoS（CWE-400）、旧世代タスクによる不正な共有リソース書き換え競合（CWE-362）、およびアボート後のメモリ解放漏れ（CWE-401）に対する防御を設計。
  - Generation Gate により、無効化されたタスクがチャネルからメッセージを不正取得・詐取することを防ぎ、強制アボート時にアリーナの安全なスクラビング（`arena-secure-reset!`）を行う。
- **Software Quality Assurance Specialist (SQA)**:
  - 単体・統合テストスイート `tests/concurrency/test_epoch.scm` において、世代カウンタの単調増加・アトミック更新、投機タスク起動と Epoch バインド、`call/cc` ロールバック連動アボート、チャネル待機タスクの Generation Gate 遮断検証、および 10,000 タスク一括ロールバック耐久テストを設計し、DoD を策定。
- **Software Development (SWD)**:
  - `ulisp/runtime/concurrency/epoch.scm`、ライブラリ定義 `ulisp/lib/ulisp/concurrency/epoch.sld` を実装。
  - `ulisp/runtime/concurrency/channel.scm` の `*channel-epoch-validator-box*` と正式に統合し、`ulisp/Makefile` に `test_epoch` ターゲットを追加。
- **Database Specialist (DB)** / **Network Specialist (NET)** / **IT Specialist (NLP & IR)**:
  - 分散クエリや投機的インデックス走査、外部 RSS/PDF 並行フェッチにおいて、先着 1 件の成功による他タスクのキャンセル（Happy Eyeballs / 投機的並行フェッチ）に本機構が理想的に適合することを確認。
- **Embedded Systems Specialist (EMB)** / **IT Service Manager (SM)** / **Systems Auditor (AU)**:
  - 極小メモリ環境でのゾンビタスク堆積を完全に抑止し、`epoch-stats` により現在世代番号、アクティブ世代数、アボート累計数、回収アリーナ容量等の可観測性（Observability）を提供する。

---

## 3. 脅威分析とセキュリティ要件 / Threat Modeling & Security Requirements

| 脅威分類 (STRIDE) | 脆弱性タイプ (CWE) | 潜在リスク・攻撃シナリオ | 防護策・緩和設計 (Mitigation) |
| :--- | :--- | :--- | :--- |
| **Denial of Service** | CWE-400 (Uncontrolled Resource Consumption) | 投機的探索タスクが破棄されずにバックグラウンドで永久に稼働し続け、CPU コア、アリーナメモリ、スタック空間を占有してシステムをハングアップさせる（ゾンビタスク DoS）。 | 世代ロールバック時、無効化された Epoch に属するタスクの命令バジェット（Reduction）をアトミックに 0 化し、次回のセーフポイント（最大 4,000 命令以内）で確実に強制終了させる。 |
| **Tampering / Race Condition** | CWE-362 (Concurrent Execution using Shared Resource with Improper Synchronization) | コントロールプレーンが過去のチェックポイントに巻き戻った後、旧世代のタスクが遅延してチャネルへ結果メッセージを送信し、新世代の計算状態を不正に上書き・汚染する。 | チャネル送受信のハンドシェイク時に Generation Gate を適用。旧世代タスクによる `channel-send!` / `channel-recv!` を無効化し、旧メッセージの流入を遮断する。 |
| **Information Disclosure / Integrity Violation** | CWE-843 (Type Confusion) / CWE-200 | チャネル待機（`TASK_WAITING_CHANNEL`）でスリープしていた旧タスクが、新世代のために用意された機密メッセージや型が異なるペイロードを誤って起床・受領してしまう。 | `channel.scm` の `%pop-live-waiter!` において `(%task-epoch-valid? task)` をアトミック検証。世代不一致の待機タスクはメッセージを一切消費することなく `'aborted` へ遷移させ、キューから即座に排除する。 |
| **Resource Leak** | CWE-401 (Improper Release of Memory Before Removing Last Reference) | タスク強制アボート時に、タスク専用アリーナ（`<task-arena>`）が適切に回収されず、未解放メモリが累積して OOM に至る。 | タスクアボートハンドラにおいて、タスク状態を `'terminated` に遷移させると同時に `arena-reset!`（または `arena-secure-reset!`）を直ちに実行し、$O(1)$ 瞬時回収を保証する。 |

---

## 4. トレーサビリティ / Traceability

- **正典設計仕様書**:
  - [DSN-37: ホスト・カーネル分離型 階層 CSP/アクター・ハイブリッド並行処理基盤 ＆ AOT コンパイルパイプライン包括的アーキテクチャ設計書](../../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md)
    - 第 8.2 節: 外側 call/cc と並列タスクの世代管理型投機タスク破棄 (Generation-Based Speculative Cancellation)
    - 第 8.3 節: 待機中タスクのアボート保証 (Generation Gate)
    - 第 14.6 節: Phase 4 ホスト・カーネル境界 ＆ 世代管理型投機タスク破棄 (Task 4.2)
  - [DSN-36: Zero-libc Pure Scheme ベアメタルランタイム包括設計仕様書](../../designs/DSN-36-zero_libc_pure_scheme_bare_metal_runtime.md)
  - [DSN-33: uLisp x86-64 ネイティブ AOT コンパイラ包括設計仕様書](../../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
- **関連・先行 Issue**:
  - [Issue 630: プロセスローカル・エフェメラルアリーナおよび O(1) 瞬時全破棄機構の実装](../closed/630-implement-synapse-task-independent-bump-arena.md)
  - [Issue 631: Scheme 低レベルアトミック命令 (atomic-cas! / atomic-box) の提供](../closed/631-implement-synapse-low-level-atomic-primitives.md)
  - [Issue 633: 線形所有権移譲チャネルおよび有界バックプレッシャー機構の実装](../closed/633-implement-synapse-first-class-p2p-channel.md)
  - [Issue 636: リダクション方式セーフポイント注入と協調的・強制的プリエンプション機構の実装](../closed/636-implement-synapse-fuel-preemption-mechanism.md)
  - [Issue 640: Nanopass ループバックエッジ・プロローグ セーフポイント判定自動注入パスの実装](../closed/640-implement-nanopass-inject-fuel-checks-pass.md)
  - [Issue 641: ホスト・カーネル境界サニタイザおよびディープコピー機構の実装](../closed/641-implement-synapse-boundary-sanitizer-and-deep-copy.md)

---

## 5. 影響範囲と関連ファイル / Scope and Affected Files

### 新規作成
- `ulisp/runtime/concurrency/epoch.scm`: 世代管理型投機タスク破棄および世代ゲート機構本体
  - グローバル世代管理（`*current-epoch-box*`, `epoch-current`, `epoch-advance!`）
  - タスク世代バインドおよび追跡レジストリ（`epoch-bind-task!`, `register-epoch-task!`, `unregister-epoch-task!`）
  - バックトラック投機破棄（`epoch-checkpoint`, `epoch-rollback-to!`, `speculative-checkpoint`）
  - 待機タスク世代ゲート検証（`epoch-task-valid?`, `install-epoch-channel-gate!`）
  - テレメトリおよび統計（`epoch-stats`, `epoch-reset-stats!`）
- `ulisp/lib/ulisp/concurrency/epoch.sld`: R7RS ライブラリ定義
  - `(ulisp concurrency epoch)`
- `tests/concurrency/test_epoch.scm`: 単体・統合・耐久テストスイート
  - 世代カウンタ操作、タスクバインド、バックトラックアボート、Generation Gate 遮断、メモリリークゼロ検証

### 既存更新
- `ulisp/runtime/concurrency/channel.scm`:
  - `*channel-epoch-validator-box*` への `epoch-task-valid?` デフォルト結合対応
- `ulisp/Makefile`:
  - `test_epoch` ターゲットの追加
  - `lint_sexpr` への新規ファイル登録
  - 並行性包括テストハーネスへの統合
- `docs/issues/README.md`: Issue #642 ステータス管理

---

## 6. 実装方針 / Implementation Plan

Target Branch: `feat/642-speculative-cancellation`

### Step 1: グローバル世代管理とアトミック基盤の定義 (`epoch.scm`)
1. **世代定数とアトミックボックス**:
   - `*epoch-global-counter*`: 初期値 `1` の `atomic-box`。
   - `*epoch-active-floor*`: 現在有効な最小世代番号の `atomic-box`（初期値 `1`）。
   - `*epoch-task-registry*`: 各世代に属するタスクの追跡リスト（またはアトミックリストボックス）。
2. **基本操作 API**:
   - `(epoch-current)`: 現在の世代番号をアトミックに取得。
   - `(epoch-advance!)`: 世代番号を不可分に `+1` し、新しい世代番号を返却。
   - `(epoch-floor)`: 有効下限世代番号を取得。

### Step 2: タスク世代バインドとレジストリ機構
1. **タスク生成時バインド**:
   - `(epoch-bind-task! task [epoch])`:
     - 指定がない場合は `(epoch-current)` をタスクの `task-epoch` フィールドに設定。
     - タスクを世代別追跡レジストリへ登録。
2. **タスク完了時クリーンアップ**:
   - `(epoch-unbind-task! task)`:
     - 正常終了またはアボートしたタスクを追跡レジストリから除去。

### Step 3: 分散ロールバックと投機タスクアボート機構
1. **アボートシグナル発行 (`epoch-rollback-to! target-epoch`)**:
   - `target-epoch` より大きい（または無効化された）世代に属する全タスクを特定。
   - 各タスクに対して：
     1. 命令バジェット `task-reductions-set!` を `0`（または負数）にアトミック設定。
     2. タスク状態 `task-state-set!` を `'terminated` へ遷移。
     3. 関連付けられたアリーナを `arena-reset!` で $O(1)$ 瞬時解放。
2. **`call/cc` 連動チェックポイント構文 (`epoch-checkpoint`)**:
   - `(epoch-checkpoint proc)`:
     - 現在の世代 $E$ を記録し、`(call/cc (lambda (rollback-k) ...))` を実行。
     - 探索失敗時に `(rollback-k 'abort)` が呼ばれた場合、自動的に `(epoch-rollback-to! E)` を実行して新世代 $E+1$ を再開。

### Step 4: 待機タスク世代ゲート検証（Generation Gate）
1. **検証述語 (`epoch-task-valid? task`)**:
   - `task` が `#f` の場合は `#f`。
   - `(task-state task)` が `'terminated` の場合は `#f`。
   - `(task-epoch task)` が現在有効な世代範囲（$\ge \text{floor}$ かつ $\le \text{current}$）に収まっているかを検証。
2. **チャネルランタイム統合 (`install-epoch-channel-gate!`)**:
   - `channel.scm` の `(set-channel-epoch-validator! epoch-task-valid?)` を設定。
   - `channel-send!` / `channel-recv!` / `%pop-live-waiter!` で起床したタスクが旧世代の場合、メッセージを消費せずに直ちに安全破棄。

### Step 5: テストスイートの作成と Makefile 統合
1. `tests/concurrency/test_epoch.scm` の実装：
   - Group 1: 世代カウンタ・アトミック更新検証
   - Group 2: タスクへの Epoch バインドとレジストリ検証
   - Group 3: ロールバック時の命令バジェットゼロ化とセーフポイント強制停止検証
   - Group 4: チャネル待機タスクの Generation Gate 遮断検証
   - Group 5: `call/cc` バックトラック連携エンドツーエンド検証
   - Group 6: 10,000 タスク一括ロールバック耐久ストレス＆ $O(1)$ メモリ回収検証
2. `ulisp/Makefile` への `test_epoch` 統合および回帰テスト実行。

---

## 7. 完了条件 / Success Criteria (DoD)

### 定量的検証項目
1. **世代カウンタの不可分整合性**:
   - 並行タスク生成時でも世代番号が重複・逆行せず単調増加すること。
2. **投機タスクの確実なアボート**:
   - `epoch-rollback-to!` 実行時、対象世代の全タスクの Reduction が即時に 0 化され、次回のセーフポイント（または次回実行時）に確実に停止すること。
3. **Generation Gate による汚染防止**:
   - チャネル待機中の旧世代タスクが起床しても、メッセージを消費することなく直ちに `'terminated` へ遷移し、新世代のチャネルデータが 1 件も失われないこと。
4. **$O(1)$ アリーナメモリの完全回収**:
   - 10,000 件のタスクを投機生成後に一括ロールバックした際、全アリーナが即時にリセットされ、残存リークメモリが 0 バイトであること。
5. **全テストハーネスの合格**:
   - `make -C ulisp test_epoch`: 全グループ 100% PASS。
   - `make -C ulisp lint_sexpr`: 括弧整合性 PASS。
   - 全並行性ランタイム（`test_arena`, `test_atomic`, `test_queue`, `test_channel`, `test_boundary`, `test_context_switch`, `test_scheduler`, `test_preemption`, 全パス）との一括回帰テスト PASS。
   - 相対パスリンク 100% 準拠（絶対パス 0 件）。
