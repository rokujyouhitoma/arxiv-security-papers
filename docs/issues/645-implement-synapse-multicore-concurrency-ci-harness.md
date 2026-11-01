---
ID: 645
種別: Feature
優先度: High
ステータス: In Progress
---

# [FEAT] CI 向けマルチコア並行競合テストハーネス (concurrency_harness.scm) の実装 (ID: 645)

## 1. 概要 / Summary

[DSN-37](../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md) Phase 5 Task 5.4 および全 16 専門エージェント審査決議（第 15 章 QA 所見）に基づき、CI パイプライン（GitHub Actions / Linux x86-64）上でデータ競合（CWE-362）、デッドロック（CWE-833）、ABA 問題、ライブロック、およびメモリリーク／リソース枯渇（CWE-400）の再発を恒久的に防止する**マルチコア並行競合テストハーネス（`tests/concurrency/concurrency_harness.scm`）**を実装する。

Synapse 並行ランタイム基盤（Phase 0〜5）では、プロセスローカル・エフェメラルアリーナ（Issue 630）、低レベルアトミック命令（Issue 631）、境界付き P2P チャネル（Issue 633）、分散 M:N ワークスティーリングスケジューラ（Issue 635）、境界ディープコピーサニタイザ（Issue 641）、エポックフェンシング＆投機ロールバック（Issue 642）、および Dual-Mode 評価アダプタ（Issue 644）を順次開発・統合してきた。
しかし、並行処理ランタイムにおける競合状態（Race Conditions）やタイミング依存の不具合は、単一コア環境や負荷の低い決定論的単体テストでは潜在化したまま見逃されやすい。

本 Issue では、擬似乱数ジェネレータ（PRNG）に基づく**カオス的ジッター（Jitter）注入機構**を導入し、スレッド・タスク間のスケジューリング順序や CAS ループの衝突タイミングを動的に激しく攪乱する。これにより、極限の競合条件下におけるチャネル送受信の完全性、Chase-Lev Deque における ABA 耐性、エポック世代境界での投機タスク遮断性、およびアリーナメモリのリークゼロ性を検証する。
CI 自動実行ターゲットとして **100 反復連続実行で 100% PASS**（Flakiness ゼロ）を保証する包括的ハーネスを確立する。

---

## 2. ガバナンス・専門エージェント多角レビュー / Governance & Reviews

本 Issue は、リポジトリ統治規約（[`../../.agents/AGENTS.md`](../../.agents/AGENTS.md)）に従い、PM 主導のもと全 16 専門エージェントによる多角的設計レビューを統合して策定された。

- **Project Manager (PM) (Chair / Governance)**:
  - DSN-37 Phase 5 の最終マイルストーン（Task 5.4）として、これまでの全成果物（Phase 0〜5）に対する品質証明の役割を果たす。CI パイプラインで日常的に実行可能な軽快さ（100 反復を 10 秒〜30 秒以内で完了）と、高負荷カオス注入による極限レース検出力を両立させる。
- **Software Quality Assurance Specialist (SQA)**:
  - 並行テストの最大の敵は Flaky テスト（非決定論的偽陽性・偽陰性）である。100 反復連続で 100% PASS を必須の DoD とし、万が一の失敗時にはイテレーション番号、シード値、発生タスク ID、期待値と実測値の不一致理由を詳細に出力する診断ログ機構を組み込む。
- **IT Specialist (Programming Languages & Compilers / PLC)**:
  - uLisp Native AOT コンパイラ（`bin/ulisp-boot`）によるネイティブバイナリ生成環境において、全コンポーネントがメモリバリア、レジスタ退避、アライメント、型安全性を維持して動作することを検証する。Pass 070 (ANF) の `(begin ...)` 制約および Pass 040 の `case-lambda` 制約を遵守した高信頼な Scheme コードとして構成する。
- **Information Security Specialist (SEC)**:
  - 並行処理特有のセキュリティ脅威である CWE-362（競合状態）、CWE-833（デッドロック）、CWE-400（リソース枯渇）、および CWE-190（整数オーバーフロー）に対する自動検知ガードを配備。カオス注入下でもセキュリティ不変条件（不変領域への書き込み遮断、アリーナ境界の保護）が破られないことを実証する。
- **Systems Architect (SA)**:
  - Layer 1（ホスト並行インフラ）と Layer 2（ASC 計算プレーン）の境界分離がマルチコア負荷下でも完全に保たれるかを検証。ディープコピーサニタイザ（Issue 641）とエポックフェンシング（Issue 642）が連動し、分離違反やゴーストタスクの残留が発生しないアーキテクチャ的一貫性を保証する。
- **Software Development (SWD)**:
  - Xorshift32 等の極小かつ決定論的シード指定可能な Pure Scheme PRNG をテストハーネス内部に内装し、再現可能なカオス Jitter 注入を実現する。不必要なシステムコールを排し、CPU ビジーループや CAS 衝突リトライによる純粋なスレッドインターリーブ攪乱を生成する。
- **Network Specialist (NET)**:
  - P2P / MPSC チャネルの有界バッファ（有界バックプレッシャー）が極限の競合下でもメッセージ脱落、バッファオーバーフロー、または永久ブロックを引き起こさないことを検証する。
- **Database Specialist (DB)**:
  - エポックフェンシングに基づく MVCC 的トランザクション破棄が、並行書き込み競合下でも古いエポックのコミットを 100% 遮断することを確認する。
- **IT Service Manager (SM)**:
  - GitHub Actions やローカル CI でのワンコマンド実行性（`make test_concurrency_ci`）を提供し、ハングアップ防止のためのタイムアウト機構（あるいは反復上限）を明確に設ける。
- **Systems Auditor (AU)**:
  - 100 反復の実行結果、各フェーズ（チャネル、ABA、エポック、アリーナ）の実行時間、通過アサーション数の監査サマリーを標準出力へ整形表示し、トレーサビリティを確保する。
- **Embedded Systems Specialist (EMB)** / **IT Specialist (NLP & IR)** / **IT Strategist (ST)** / **UI/UX Designer** / **Education Specialist (EDU)** / **Application Specialist (APS)**:
  - リソース制約環境でも動作する軽量設計、教育的で可読性の高いテストケース記述、および業務バッチパイプラインへの高い適用可能性を承認。

---

## 3. 脅威分析とセキュリティ要件 / Threat Modeling & Security Requirements

| 脅威分類 (STRIDE) | 脆弱性タイプ (CWE) | 潜在リスク・攻撃シナリオ | 防護策・緩和設計 (Mitigation) |
| :--- | :--- | :--- | :--- |
| **Tampering / Information Disclosure** | CWE-362 (Race Condition / Concurrent Execution using Shared Resource) | 複数コアからチャネル送受信やスケジューラキューの操作が極小タイミングで同時に行われた際、CAS アトミック性やメモリ可視性（Memory Visibility）の欠落によりメッセージ順序破損や二重受領が発生する。 | カオス Jitter を CAS ループおよびチャネル送受信の合間に挿入し、全インターリーブ下でメッセージ連番（Seq No）の完全性と一意性をアサートする。 |
| **Denial of Service** | CWE-833 (Deadlock) / CWE-835 (Infinite Loop / Livelock) | ワークスティーリングや有界チャネルの送受信ブロック時、スレッド間の依存循環や CAS リトライの永久ループによりシステム全体がハングアップする。 | 最大リトライ回数の境界検証、ノンブロッキング試行による巡回、および反復ごとのステップ上限設定によりライブロック／デッドロックを早期検知・遮断する。 |
| **Integrity Violation** | ABA Problem (Lock-free Pointer Invalidation) | スレッド A がノード P を読み取った直後、スレッド B が P を解放し、さらにスレッド C が同じメモリアドレス P に新たなノードを割り当てた場合、スレッド A の CAS がアドレス一致のみで成功してキューを破損させる。 | Chase-Lev Deque における世代カウンタ（Epoch / Version Tag）の整合性、およびアリーナ O(1) 破棄後のポインタ再利用時の検証を行い、ABA 誤更新を排除する。 |
| **Denial of Service** | CWE-400 (Uncontrolled Resource Consumption / Memory Leak) | 並行タスクの起動・完了・アボートを数千回繰り返す中で、アリーナの拡張チャンクやキャンセルされたタスクコンテキストが回収されずに累積し、OOM クラッシュを引き起こす。 | ハーネス実行前後でのアリーナ使用量および未解放タスク数をトラッキングし、反復終了時に残存オブジェクト数が厳密にゼロであることをアサートする。 |
| **Integrity Violation** | CWE-190 (Integer Overflow) | Jitter 計算用の PRNG カウンタやエポック番号、チャネル送受信シーケンス番号が長時間の高負荷実行でオーバーフローし、不正なインデックス参照を引き起こす。 | 60 ビット Fixnum 範囲内での安全なビットマスク（`bitwise-and`）演算により、符号付きラップアラウンドを防止する。 |

---

## 4. トレーサビリティ / Traceability

- **正典設計仕様書**:
  - [DSN-37: ホスト・カーネル分離型 階層 CSP/アクター・ハイブリッド並行処理基盤 ＆ AOT コンパイルパイプライン包括的アーキテクチャ設計書](../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md#task-54-ci-向けマルチコア並行競合テストハーネス-testsconcurrencyconcurrency_harnessscm) (第 14.7 節 Task 5.4、第 15 章 QA 所見)
- **関連 Issue**:
  - [Issue 630: プロセスローカル・エフェメラルアリーナの実装 (Task 0.1)](closed/630-implement-synapse-task-independent-bump-arena.md)
  - [Issue 631: 低レベルアトミック命令の実装 (Task 0.2)](closed/631-implement-synapse-low-level-atomic-primitives.md)
  - [Issue 633: 線形所有権移譲チャネルの実装 (Task 1.1)](closed/633-implement-synapse-first-class-p2p-channel.md)
  - [Issue 635: 分散 M:N ワークスティーリングスケジューラの実装 (Task 1.2)](closed/635-implement-synapse-work-stealing-scheduler.md)
  - [Issue 638: アフィン線形所有権静的検査パスの実装 (Task 2.1)](closed/638-implement-nanopass-check-affine-types-and-raii-drop.md)
  - [Issue 641: 境界サニタイザおよびディープコピー機構の実装 (Task 4.1)](closed/641-implement-synapse-boundary-sanitizer-and-deep-copy.md)
  - [Issue 642: 世代管理型エポックフェンシングの実装 (Task 5.1)](closed/642-implement-synapse-epoch-fencing-distributed-rollback.md)
  - [Issue 643: 10 万マイクロタスク耐久ベンチマークの実装 (Task 5.2)](closed/643-implement-synapse-benchmark-suite-and-stw-gc-verification.md)
  - [Issue 644: インタプリタ向け Dual-Mode 評価アダプタの実装 (Task 5.3)](closed/644-implement-synapse-interpreter-dual-mode-eval-adapter.md)

---

## 5. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [tests/concurrency/concurrency_harness.scm](../../tests/concurrency/concurrency_harness.scm) (新規作成)
  - Xorshift32 Pure Scheme 擬似乱数ジェネレータ（PRNG）およびカオス Jitter 注入ヘルパー
  - **Scenario 1**: カオス Jitter 注入下での P2P / MPSC チャネル送受信競合テスト（連番整合性・脱落ゼロ・重複ゼロ検証）
  - **Scenario 2**: Chase-Lev ワークスティーリング Dequeue における ABA パターン＆ポインタ再利用検証
  - **Scenario 3**: エポック昇格競合下での投機タスク書き込み遮断＆ロールバック整合性検証
  - **Scenario 4**: マルチタスク並列アリーナ高速生成・O(1) 破棄耐久テスト（メモリリーク 0 検証）
  - **Scenario 5**: 100 反復連続実行コントローラおよび監査サマリー整形レポーティング
- [ ] [ulisp/Makefile](../../ulisp/Makefile) (変更)
  - `test_concurrency_harness` ターゲットの追加（単発実行および標準 `make test` への統合検討）
  - `test_concurrency_ci` ターゲットの追加（CI 向け 100 反復連続実行ターゲット）
- [ ] [Makefile](../../Makefile) (変更)
  - ルートの `test_concurrency_ci` ターゲット追加（`ulisp/` へのディスパッチ）

---

## 6. 実装方針 / Implementation Plan

Target Branch: `feat/645-concurrency-ci-harness`

### Step 1: テストハーネス基盤および決定論的カオス Jitter 生成器の設計 (`tests/concurrency/concurrency_harness.scm`)
1. **依存モジュールの包含ロード**:
   - `arena.scm`, `atomic.scm`, `queue.scm`, `channel.scm`, `boundary.scm`, `epoch.scm`, `context.scm`, `deque.scm`, `scheduler.scm`, `preempt.scm`, `eval_adapter.scm` の順次ロード。
2. **決定論的 PRNG (Xorshift32)**:
   - 外部ライブラリ非依存の 32-bit Xorshift PRNG を実装（シード指定可能）。
   - 指定された反復シードに基づき、再現可能な乱数列を生成。
3. **カオス Jitter 注入機構**:
   - `(inject-jitter! prng max-spins)`: 0〜`max-spins` 回の微小 CPU ビジーループを実行し、スレッド・タスク間の実行インターリーブを激しく揺さぶる。

### Step 2: 4 大コア並行競合シナリオの実装
1. **Scenario 1: カオス Jitter 注入チャネル競合テスト**:
   - 複数プロデューサーが連番メッセージをチャネルへ送信し、コンシューマーが受信。
   - 送受信の直前・直後に `inject-jitter!` を挿入し、バッファ満杯・空の境界競合を人為的に多発させる。
   - 受信メッセージの欠落ゼロ、重複ゼロ、各プロデューサーごとの順序性を検証。
2. **Scenario 2: Chase-Lev ワークスティーリング Dequeue ABA 競合テスト**:
   - オーナーが Push/Pop を繰り返す裏で、スティーラーが Steal を連続実行。
   - Dequeue されたインデックスやタスク参照が再利用された際、古いスナップショットによる誤 Steal が発生しないことを検証。
3. **Scenario 3: エポック昇格競合下での投機タスク遮断検証**:
   - 複数の並行タスクがアトミック状態変更を試みる中、ランダムなタイミングでエポックを昇格（`epoch-advance!`）。
   - 旧エポックタスクのコミットが 100% 失敗し、新エポックのタスクのみが成功することを検証。
4. **Scenario 4: 高速アリーナ O(1) 破棄＆メモリ整合性テスト**:
   - 多数のタスクが同時にアリーナを確保し、一時オブジェクトをバンプ割り当て後、`arena-reset!` または `arena-secure-reset!` を実施。
   - メモリリークが一切生じず、アリーナ統計が期待値通りにリセットされることを検証。

### Step 3: 100 反復 CI 実行コントローラと診断レポーティング
1. **反復実行ループ**:
   - 100 回の反復テストを連続実行（イテレーションごとにシードを更新）。
   - 万が一いずれかのイテレーションでアサーションが失敗した場合は即座にシード番号、シナリオ名、詳細エラーを出力して中断。
2. **サマリー整形出力**:
   - 全 100 反復完走後、総実行時間、総アサーション成功数、検証シナリオ内訳を美しくフォーマットして出力。

### Step 4: Makefile ターゲット統合と CI 品質検証
1. **`ulisp/Makefile`**:
   - `test_concurrency_harness`: 単発（1 反復）検証ターゲット。
   - `test_concurrency_ci`: 100 反復連続実行ターゲット。
2. **`scripts/lint_sexpr.py`**:
   - `concurrency_harness.scm` を構文リンターの対象に追加し、Pass 070 制約、S 式括弧整合性を担保。
3. **品質ゲート実行**:
   - `make lint_sexpr` PASS
   - `make test_concurrency_ci` 100 反復 100% PASS
   - 相対パスリンク規約（0 件絶対パス）の検証。

---

## 7. 完了条件 / Definition of Done (DoD)

- [ ] `tests/concurrency/concurrency_harness.scm` が実装され、Xorshift PRNG による再現可能なカオス Jitter 注入機構を備えていること
- [ ] 以下の 4 大並行競合シナリオが実装され、すべて検証されていること:
  - Scenario 1: カオス Jitter 注入チャネル送受信（欠落・重複ゼロ）
  - Scenario 2: Chase-Lev ワークスティーリング Dequeue ABA 検証
  - Scenario 3: エポック昇格競合下での投機タスク遮断検証
  - Scenario 4: 並行アリーナ O(1) 破棄＆メモリリーク 0 バイト検証
- [ ] `ulisp/Makefile` に `test_concurrency_harness` および `test_concurrency_ci` が追加されていること
- [ ] `make test_concurrency_ci` が 100 反復連続実行で 100% PASS すること（Flakiness ゼロ）
- [ ] `make lint_sexpr` がエラー 0 件で PASS すること
- [ ] すべてのファイルリンクが相対パスリンク規約に準拠していること（絶対パス 0 件）
