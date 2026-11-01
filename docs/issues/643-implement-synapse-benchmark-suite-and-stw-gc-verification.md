---
ID: 643
種別: Feature
優先度: High
ステータス: Open (In Progress)
---

# [FEAT] 10 万並行マイクロタスク耐久ベンチマークおよび STW-GC ゼロ検証スイートの実装 (ID: 643)

## 1. 概要 / Summary

[DSN-37](../../docs/designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md) Phase 5 Task 5.1 & Task 5.2 に基づき、ホスト・カーネル分離型 階層 CSP/アクター並行処理基盤（Synapse Architecture）の極限耐久性能と実時間決定論性を実証する **並行性能ベンチマークスイート（Concurrency Benchmark Suite）** を構築する。

本基盤（Phase 0〜4 で構築したプロセスローカル・エフェメラルアリーナ、ロックフリーキュー、線形チャネル、Chase-Lev ワークスティーリング、リダクション式プリエンプション、ホスト境界サニタイザ、世代管理ロールバック）は、Erlang BEAM の Shared-Nothing 思想と Rust のアフィン型ゼロコピー移譲、Perceus/FBIP インプレース更新を融合した次世代アーキテクチャである。

本 Issue では、このアーキテクチャが標榜する以下の 2 大中核性能要件を、実ハードウェア（Linux x86-64 / uLisp AOT ネイティブバイナリ）上で一切のモックなしに実測・定量検証する：

1. **10 万並行マイクロタスク耐久性能 (Task 5.1 / `bench_microtasks.scm`)**:
   - 100,000 個の軽量アフィンタスクを一括生成し、線形所有権移譲チャネル（P2P / リングリレー）を介してメッセージを確実に伝播・完了。
   - スループット（マイクロタスク/秒）、平均コンテキストスイッチ遅延（ナノ秒単位）、ピーク RSS メモリ、アリーナ $O(1)$ 即時回収によるメモリリーク 0 バイトを計測。
2. **STW-GC ゼロ実証＆レイテンシジッター検証 (Task 5.2 / `bench_latency_under_gc.scm`)**:
   - コントロールプレーン（Layer 1: R7RS）側で大量の動的オブジェクト生成を連続実行し、意図的にホスト Stop-The-World (STW) GC（マイナーおよびメジャー GC）を頻発させる。
   - 同一プロセス内で並行稼働するアフィン計算プレーン（Layer 2: ASC）側のタスクレイテンシ（P50, P90, P99, Max）を高精度モノトニックタイマー（`sys-clock-gettime-monotonic`）で計測し、ホスト GC 停止時間が計算タスクに一切伝播しない「レイテンシスパイクゼロ（STW-GC ゼロ）」を実証。

---

## 2. ガバナンス・専門エージェント多角レビュー / Governance & Reviews

本 Issue は、リポジトリ統治規約（[`.agents/AGENTS.md`](../../../.agents/AGENTS.md)）に従い、PM 主導のもと全 16 専門エージェントによる多角的設計レビューを統合して策定された。

- **Project Manager (PM) (Chair / Governance)**:
  - Phase 5（統合検証 ＆ 性能ベンチマーク）の中核マイルストーン（Task 5.1 & 5.2）として、DSN-37 の最終性能検証を担当する。外部 C ライブラリや OS 依存ツールに頼らず、uLisp AOT コンパイルされたスタンドアロン ELF バイナリとして動作可能にし、CI および自動テスト環境で決定論的に再現可能な測定メトリクスを確立する。
- **IT Specialist (Programming Languages & Compilers / PLC)**:
  - ナノ秒単位の計測精度を担保するため、`ulisp/lib/posix.scm` の `sys-clock-gettime-monotonic`（Linux `sys_clock_gettime(CLOCK_MONOTONIC=1)`) を直接活用する。
  - AOT コンパイラ（`bin/ulisp-boot`）が生成するネイティブコードにおいて、不要なボックス化やクロージャ再割り当てによる測定ノイズを排除し、純粋なランタイム並行性能を抽出する。
- **Systems Architect (SA)**:
  - DSN-37 第 1.2 節（ホスト・カーネル分離）および第 5 章（プロセスローカル・エフェメラルアリーナ）の設計仮説「Layer 2 はホスト GC ヒープを触らないため、Layer 1 が GC で停止しても Layer 2 タスクは一切影響を受けない」を実験的に完全検証する。
  - 10 万並行タスク生成時のメモリレイアウト（1 タスクあたり 4KB アリーナ＋TCB で約 400MB 〜 500MB に収まり、物理 RAM 上でスワップなしにスケールすること）を確認。
- **Software Development (SWD)**:
  - `bench_microtasks.scm` におけるタスク生成・メッセージリレーアルゴリズムを設計。数珠繋ぎリング（Ring Relay）またはバケツリレー（Pipeline Relay）を採用し、全 100,000 タスクが順次メッセージを受信・検証・転送して正常終了するフローを実装。
- **Information Security Specialist (SEC)**:
  - 10 万並行時のリソース枯渇型 DoS（CWE-400 / CWE-770）、レイテンシ計測値の算術オーバーフロー（CWE-190）、および GC 誘発時の競合状態（CWE-362）に対する防御・アサーションを設計。ベンチマーク実行中もアリーナ境界・チャネル有界制限を遵守する。
- **Software Quality Assurance Specialist (SQA)**:
  - ベンチマークスイートを単なる表示スクリプトに留めず、厳格なアサーション（DoD 判定）を組み込んだ自動検証ハーネスとする。P99 レイテンシ許容閾値、完了タスク数一致、メモリリーク 0 バイトの判定ロジックを実装。
- **Database Specialist (DB)**:
  - 将来の大規模 CTI グラフ探索やトランザクション処理（WAL/MVCC）における並行クエリ実行エンジンとしての適用性を評価し、10 万並行時のスループット指標がデータベース並列スキャン要件を満たすか確認。
- **Network Specialist (NET)**:
  - 高頻度パケット処理タスクのシミュレーションにおいて、チャネルを介したゼロコピー線形所有権移譲がボトルネックなく毎秒数十万〜数百万メッセージを処理できるかを検証。
- **IT Specialist (NLP & IR)**:
  - セキュリティ論文の並列トークナイズ・TF-IDF 抽出タスクにおけるマイクロタスク分散の適用可能性を評価。
- **IT Strategist (STR)**:
  - Erlang/Elixir (BEAM)、Go (Goroutine)、Rust (Tokio) との定量的比較資料となる性能評価レポート（`docs/benchmarks/concurrency_evaluation.md`）の章立てを監修。
- **IT Service Manager (SM)** / **Systems Auditor (AU)**:
  - 本番運用環境での可観測性（Observability）を担保するため、`epoch-stats`, `channel-stats`, `runtime-gc-alloc-bytes`, `runtime-gc-minor-count` などのランタイム内部統計レジスタの整合性を測定前後に監査・ログ出力。
- **Embedded Systems Specialist (EMB)**:
  - メモリ制約環境（エッジノード・IoT）への移植性を考慮し、タスクあたり最小メモリフットプリント（RSS 増分 / タスク数）を定量算出。
- **UI/UX & Documentation Designer (UI/UX)**:
  - `docs/benchmarks/concurrency_evaluation.md` にレイテンシジッター分布表、スループット推移 Mermaid XY チャート、およびアーキテクチャ比較表を美麗にレイアウト。
- **Education Specialist (EDU)**:
  - ベンチマーク結果の技術的意義（なぜ STW-GC がゼロになるのか、なぜ 10 万並行が軽量なのか）を読者が平易に理解できる解説セクションを配置。
- **Application Specialist (APS)**:
  - Web ゲートウェイおよびストリーミング API サーバでの耐障害性・レスポンス安定化に直結することを検証。

---

## 3. 脅威分析とセキュリティ要件 / Threat Modeling & Security Requirements

| 脅威分類 (STRIDE) | 脆弱性タイプ (CWE) | 潜在リスク・攻撃シナリオ | 防護策・緩和設計 (Mitigation) |
| :--- | :--- | :--- | :--- |
| **Denial of Service** | CWE-400 / CWE-770 (Uncontrolled Resource Consumption) | 100,000 個のタスクを一斉生成した際、スタック領域やヒープが枯渇して OOM Killer によりプロセスがクラッシュする。 | タスク毎の TCB は軽量 Pure Scheme レコードとして確保し、エフェメラルアリーナはオンデマンド確保または有界割り当てを行い、ピーク RSS を監視・制限する。 |
| **Tampering / Arithmetic Error** | CWE-190 (Integer Overflow or Wraparound) | ナノ秒単位の累積時間計算や 100,000 タスクのスループット算出時に 64-bit 整数がオーバーフローし、誤った性能値やゼロ除算例外を引き起こす。 | ナノ秒計算は 128-bit 相当または秒とナノ秒を独立処理する安全な時間差分演算ロジックを適用し、負数・ゼロ除算を事前検証。 |
| **Race Condition** | CWE-362 (Concurrent Execution using Shared Resource with Improper Synchronization) | ホスト側で連続 GC が走っている最中に、並列計算タスクがチャネルやアリーナを操作して内部ポインタの不整合やメモリ破損を起こす。 | Layer 1（ホスト GC 管理下）と Layer 2（プロセス独立アリーナ）のポインタ非共有原則を厳格に保持し、チャネル通信はアトミック CAS による線形所有権移譲のみを使用。 |
| **Information Disclosure / State Leak** | CWE-212 / CWE-401 (Improper Removal of Sensitive Data / Memory Leak) | 10 万タスク終了後にアリーナやタスク構造体が回収されず、後続のベンチマーク実行時にメモリが肥大化・残存する。 | 全タスク完了後に `epoch-rollback-to!` または個別 `arena-reset!` を実行し、残存登録タスク数 0、アリーナ使用バイト数 0 を厳格アサート。 |

---

## 4. トレーサビリティ / Traceability

- **正典設計仕様書**:
  - [DSN-37: ホスト・カーネル分離型 階層 CSP/アクター・ハイブリッド並行処理基盤 ＆ AOT コンパイルパイプライン包括的アーキテクチャ設計書](../../docs/designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md#147-phase-5-統合検証--性能ベンチマーク) (第 14.7 節 Phase 5: Task 5.1 & Task 5.2)
  - [DSN-35: ILISP/ULISP AOT/JIT 継続的性能ベンチマークフレームワーク設計書](../../docs/designs/DSN-35-ilisp_ulisp_aot_jit_continuous_benchmarking_framework.md)
  - [DSN-33: uLisp x86-64 ネイティブ AOT コンパイラ包括設計仕様書](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
- **関連・先行 Issue**:
  - [Issue 630: プロセスローカル・エフェメラルアリーナおよび O(1) 瞬時全破棄機構の実装 (Closed)](closed/630-implement-synapse-task-independent-bump-arena.md)
  - [Issue 631: Scheme 低レベルアトミック命令 (atomic-cas! / atomic-box) の提供 (Closed)](closed/631-implement-synapse-low-level-atomic-primitives.md)
  - [Issue 632: Michael-Scott ロックフリーキューの実装 (Closed)](closed/632-implement-synapse-lock-free-queue.md)
  - [Issue 633: 線形所有権移譲チャネルおよび有界バックプレッシャー機構の実装 (Closed)](closed/633-implement-synapse-first-class-p2p-channel.md)
  - [Issue 634: 超軽量コンテキストスイッチおよびスタック境界防御の実装 (Closed)](closed/634-implement-synapse-ultralight-context-switch.md)
  - [Issue 635: 分散 M:N ワークスティーリングスケジューラおよび Chase-Lev Deque の実装 (Closed)](closed/635-implement-synapse-work-stealing-scheduler.md)
  - [Issue 636: リダクション方式セーフポイント注入と協調的・強制的プリエンプション機構の実装 (Closed)](closed/636-implement-synapse-fuel-preemption-mechanism.md)
  - [Issue 637: Nanopass コンパイラへの動的パス注入機構と Synapse プレーン分離パスの実装 (Closed)](closed/637-implement-nanopass-split-planes-pass.md)
  - [Issue 638: アフィン線形所有権静的検査パスおよび自動 RAII Drop の実装 (Closed)](closed/638-implement-nanopass-check-affine-types-and-raii-drop.md)
  - [Issue 639: FBIP (Perceus) インプレース再利用最適化パスの実装 (Closed)](closed/639-implement-nanopass-fbip-inplace-optimization.md)
  - [Issue 640: Nanopass ループバックエッジ・プロローグ セーフポイント自動注入パスの実装 (Closed)](closed/640-implement-nanopass-inject-fuel-checks-pass.md)
  - [Issue 641: ホスト・カーネル境界サニタイザおよびディープコピー機構の実装 (Closed)](closed/641-implement-synapse-boundary-sanitizer-and-deep-copy.md)
  - [Issue 642: 世代管理型投機タスク破棄および待機タスク世代ゲート検証の実装 (Closed)](closed/642-implement-synapse-epoch-fencing-distributed-rollback.md)
- **後続 Issue**:
  - [Issue 644: インタプリタ向け Dual-Mode 評価アダプタ (eval_adapter.scm) の実装](../644-implement-synapse-interpreter-dual-mode-eval-adapter.md)
  - [Issue 645: CI 向けマルチコア並行競合テストハーネス (concurrency_harness.scm) の実装](../645-implement-synapse-multicore-concurrency-ci-harness.md)

---

## 5. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [benchmarks/concurrency/bench_microtasks.scm](../../benchmarks/concurrency/bench_microtasks.scm) (新規作成)
  - 100,000 並行マイクロタスク生成および線形チャネルメッセージリレーベンチマーク
  - 高精度モノトニックタイマー計測、スループット算出、アリーナ $O(1)$ リセット検証
- [ ] [benchmarks/concurrency/bench_latency_under_gc.scm](../../benchmarks/concurrency/bench_latency_under_gc.scm) (新規作成)
  - コントロールプレーン（Layer 1: R7RS）における大規模連続ヒープ割り当て（ホスト GC 誘発）
  - アフィン計算プレーン（Layer 2: ASC）における定期パケット処理タスクのレイテンシ分布（P50, P90, P99, Max）計測
  - ホスト GC 停止（STW）非干渉性の実証アサーション
- [ ] [docs/benchmarks/concurrency_evaluation.md](../../docs/benchmarks/concurrency_evaluation.md) (新規作成)
  - 10 万並行マイクロタスク耐久ベンチマークおよび STW-GC ゼロ検証の総合性能評価レポート
  - Mermaid チャート、統計メトリクス表、BEAM / Go / Rust との比較考察
- [ ] [ulisp/Makefile](../../ulisp/Makefile) (変更)
  - `bench_microtasks`, `bench_latency_under_gc`, `bench_concurrency` ターゲットの追加
  - `lint_sexpr` への新規ベンチマークファイルの追加

---

## 6. 実装方針 / Implementation Plan

Target Branch: `feat/643-concurrency-benchmark-suite`

### Step 1: 10 万並行マイクロタスク耐久ベンチマーク (`bench_microtasks.scm`)
1. **ランタイム環境の読み込み**:
   - `ulisp/runtime/concurrency/arena.scm`
   - `ulisp/runtime/concurrency/atomic.scm`
   - `ulisp/runtime/concurrency/channel.scm`
   - `ulisp/runtime/concurrency/epoch.scm`
2. **高精度時間計測ヘルパー**:
   - `sys-clock-gettime-monotonic` を用いた経過時間（秒およびナノ秒）計算関数 `(time-diff-ns start end)`。
3. **ベンチマークワークロード設計**:
   - **Phase A (Spawn Throughput)**: 100,000 個の `<task-context>` を連続生成し、各タスクに 4KB アリーナを割り当てて世代バインド。生成速度（tasks/sec）を計測。
   - **Phase B (Channel Relay Throughput)**: 100,000 個のタスク間で有界チャネルを介してトークンをリレー伝達。各段でアリーナからのバンプ確保・即時リセットを実行。
   - **Phase C (Reclamation)**: `epoch-rollback-to!` または一括アリーナ解放による $O(1)$ メモリ回収とリーク 0 バイトのアサーション。

### Step 2: STW-GC ゼロ ＆ レイテンシジッター検証 (`bench_latency_under_gc.scm`)
1. **ホスト GC 誘発ワークロード (Layer 1 Background Pressure)**:
   - 大量のペア・ベクタ（1,000,000 個の cons セル連鎖）を継続的に確保し、ホストコピー GC（Nursery $\to$ Mature）を連続的にトリガー。
   - `(runtime-gc-minor-count)` および `(runtime-gc-major-count)` を監視し、測定期間中に数十回〜数百回の GC サイクルが確実に発生していることを確認。
2. **アフィン計算タスク (Layer 2 Latency Probe)**:
   - ホスト GC が激しく発生している最中に、プロセスローカル・エフェメラルアリーナ上で短命なデータ変換タスク（例: 256 バイトのパケットサニタイズ処理）を 10,000 回反復実行。
   - 各反復の開始・終了タイムスタンプをナノ秒単位で記録し、レイテンシサンプル配列へ格納。
3. **統計解析および STW-GC ゼロ判定**:
   - サンプル配列から P50（中央値）、P90、P99、Max レイテンシを算出。
   - ホスト GC 停止（通常数十ミリ秒）の影響が Layer 2 タスクに伝播した場合、Max や P99 に明確なミリ秒級スパイクが現れる。Layer 2 がホスト GC から完全に隔離されていれば、P99 は数マイクロ秒〜数十マイクロ秒の一定値を維持することをアサート。

### Step 3: Makefile 統合とビルド自動化 (`ulisp/Makefile`)
1. `bench_microtasks` ターゲットの定義:
   - `ULISP_STD_LIBS` と `bench_microtasks.scm` を結合し、`env ULISP_GC_PROFILE=compiler ./bin/ulisp-boot` によりネイティブバイナリへ AOT コンパイル。
   - `./build/bench_microtasks` を実行し、結果を標準出力へフォーマット表示。
2. `bench_latency_under_gc` ターゲットの定義:
   - 同様にネイティブコンパイルし、実行・レイテンシ統計を出力。
3. `bench_concurrency` ターゲットの定義:
   - 両ベンチマークを連続実行する統合ターゲット。
4. `lint_sexpr` ターゲットへのファイル登録。

### Step 4: 性能評価レポートの執筆 (`docs/benchmarks/concurrency_evaluation.md`)
1. **実測メトリクスの記録**:
   - 10 万並行マイクロタスクの総実行時間、スループット（tasks/sec）、タスクあたりメモリフットプリント。
   - GC 圧迫下における Layer 2 タスクのレイテンシパーセンタイル（P50, P90, P99, Max）と GC 停止時間との対比。
2. **アーキテクチャ考察と図解**:
   - なぜ Layer 2 は STW-GC の影響を全く受けないのか（物理的分離と共有ゼロ原則）。
   - 他言語ランタイム（Go, Erlang, Rust）との設計トレードオフ比較。
   - Mermaid 図表による可視化。

---

## 7. 完了条件 / Success Criteria (DoD)

### 定量的検証項目
1. **10 万並行マイクロタスク完遂 (Task 5.1)**:
   - 100,000 個のタスクがクラッシュ（SIGSEGV, OOM, Stack Overflow）なしに 100% 完了すること。
   - スループット $\ge 100,000 \text{ tasks/sec}$（またはハードウェア性能に応じた規定水準）を達成すること。
   - 完了後の残存登録タスク数 0、アリーナ使用バイト数 0（メモリリーク 0 バイト）であること。
2. **STW-GC ゼロ実証 (Task 5.2)**:
   - ホスト GC が 10 回以上発生する高負荷条件下でも、Layer 2 計算タスクの P99 レイテンシが $100 \ \mu\text{s}$ 未満（ホスト GC のミリ秒級停止が一切伝播しないこと）を維持すること。
3. **ビルドおよび回帰テスト 100% PASS**:
   - `make -C ulisp bench_microtasks`: 正常終了（Exit Code 0）。
   - `make -C ulisp bench_latency_under_gc`: 正常終了（Exit Code 0）。
   - `make -C ulisp lint_sexpr`: 括弧整合性 PASS。
   - 既存の全並行性回帰テスト（`test_arena`, `test_atomic`, `test_queue`, `test_channel`, `test_boundary`, `test_epoch`, `test_context_switch`, `test_scheduler`, `test_preemption`, 全 Nanopass パス）が 100% PASS を維持すること。
4. **リポジトリ統治基準の遵守**:
   - `make py_compile` および `make static_analysis` 100% PASS。
   - 全新規ドキュメント・コードにおける相対パス 100% 準拠（絶対パス 0 件検出）。
   - `docs/issues/README.md` の台帳更新。
