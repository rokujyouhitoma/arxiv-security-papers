# Issue #678: Synapse 並行処理基盤改修に伴う客観的性能再測定およびベンチマーク評価レポートの更新

## 1. 概要 (Overview)
Synapse 並行処理基盤（[DSN-37](../../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md)）において、Phase 6〜Phase 7（Issue #666〜#670, #671〜#677）の大規模改修（ネイティブマルチスレッドワーカープール、Linux `SYS_futex` によるワーカーパーク・アンパーク、Linux `io_uring` 非同期イベントループ、スーパービジョンツリー、プロセスレジストリ、クラッシュロガー等）が完了した。
これに伴い、ベンチマークターゲット（`bench_microtasks`, `bench_latency_under_gc`）のビルド依存（`thread.scm`, `build/thread.o`, `build/futex.o`）を最新化し、実機環境（Linux x86-64 SMP）上で 10 万並行マイクロタスク耐久性能および STW-GC 誘発下での決定論的レイテンシを再測定した。
得られた客観的実測値に基づき、[`docs/benchmarks/concurrency_evaluation.md`](../../benchmarks/concurrency_evaluation.md) を最新の実測メトリクスと考察に更新した。

---

## 2. 背景・動機 (Background & Motivation)
- **改修によるアーキテクチャ進化**:
  - Issue #675 でネイティブスレッド生成 (`sys_clone`) と CPU アフィニティ制御 (`set-thread-affinity!`) が `scheduler.scm` に統合された。
  - Issue #676 で `SYS_futex` プリミティブ、Issue #677 で `io_uring` イベントループが追加された。
  - これにより、従来のベンチマーク単体実行時に `set-thread-affinity!` 等の未束縛シンボル参照やリンク不足が発生するため、ベンチマーク入力ファイルおよび Makefile のビルドルールを最新ランタイム構成に整合させる必要があった。
- **性能メトリクスの再検証の必要性**:
  - コアランタイムに各種同期・監視機構が組み込まれた状態で、Synapse が標榜する「10万並行マイクロタスク高スループット」および「ホスト STW-GC ゼロ実時間決定論性（P99 < 100 μs）」が依然として超過達成されているかを客観的に実測し、ドキュメントにエビデンスを残す必要があった。

---

## 3. 実装要件・タスク分解 (Requirements & Task Breakdown)
- [x] **Task 1: ベンチマークソースおよびビルドルールの更新**:
  - `benchmarks/concurrency/bench_microtasks.scm` に `(load "ulisp/runtime/concurrency/thread.scm")` を追加。
  - `benchmarks/concurrency/bench_latency_under_gc.scm` に `(load "ulisp/runtime/concurrency/thread.scm")` を追加し、標準ライブラリ `vector-sort!` との衝突を `bench-vector-sort!` への改名により解消。
  - `ulisp/Makefile` の `bench_microtasks` および `bench_latency_under_gc` ターゲットの依存・リンクオブジェクトに `build/thread.o` と `build/futex.o` を追加。
- [x] **Task 2: ベンチマークスイートの実機再実行・実測値収集**:
  - `make -C ulisp bench_concurrency`（`bench_microtasks` および `bench_latency_under_gc`）を実行。
  - 10 万マイクロタスク実行時間（24 ms）、スループット（4,095,856 tasks/sec）、平均遅延（244 ns/task）、線形チャネルスループット（828,457 msgs/sec）、エフェメラルアリーナ即時回収性能（3,096,862 cycles/sec）、STW-GC 100回誘発下でのレイテンシ（P50: 299 ns, P90: 426 ns, P99: 1,638 ns, Max: 30.9 μs）の実測値を収集。
- [x] **Task 3: 客観的性能評価レポート (`docs/benchmarks/concurrency_evaluation.md`) の更新**:
  - セクション 1（総合評価サマリー）の測定値を最新実測値に更新。
  - セクション 2（実機実測比較表）の Synapse 実測値を最新化。
  - セクション 4（STW-GC ゼロ実証実験のレイテンシ分布 / Mermaid チャート）の数値を最新実測値に更新。
  - 改修後の最新アーキテクチャ（Futex / io_uring / Worker Pool）を踏まえた工学的考察およびセキュリティ評価表を補強。
- [x] **Task 4: 品質ゲート検証 & Issue クローズ**:
  - S式構文バランス検査（`make -C ulisp lint_sexpr`）、Python 静的解析（`make static_analysis`）、相対パス整合性の 100% 合格を確認。
  - Issue を `docs/issues/closed/` へ移動し、`docs/issues/README.md` を更新。

---

## 4. 完了基準 (Definition of Done: DoD) 検証結果
1. `make -C ulisp bench_concurrency` がビルドエラー・未束縛変数エラーなく正常完了し、実測結果が出力されること。 ➔ **PASS**
2. 10 万マイクロタスク耐久スループットが目標値（> 1,000,000 tasks/sec）を達成し、タスク完了率 100% であること。 ➔ **PASS (4,095,856 tasks/sec, 完了率 100%)**
3. STW-GC 100 回誘発下の Layer 2 P99 レイテンシが目標値（< 100 μs）を大幅にクリアしていること。 ➔ **PASS (1.64 μs, 61倍マージン達成)**
4. `docs/benchmarks/concurrency_evaluation.md` が最新実測値および Mermaid 図表とともに正確に更新されていること。 ➔ **PASS**
5. 全内部リンクが相対パス（`../...`）で記述され、絶対パスが 0 件であること。 ➔ **PASS (0 件検出)**
6. 全品質ゲート（S式構文、静的解析）が 100% PASS すること。 ➔ **PASS**

