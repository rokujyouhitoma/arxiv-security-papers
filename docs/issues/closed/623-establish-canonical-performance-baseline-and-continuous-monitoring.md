---
ID: 623
種別: Feature
優先度: Medium
ステータス: Closed (Completed)
---

# [FEAT/ENH] ULisp 正典性能ベースライン測定レポート（BASELINE.md）の策定と継続的性能監視基盤の構築 (ID: 623)

## 1. 概要 / Summary
Issue #620（ベンチマークハーネス修復）、Issue #621（Pass 所要時間・メモリプロファイラ）、および Issue #622（GC 統計プロファイル・Linux perf ハードウェアカウンタ連携）の成果を統合し、今後の本格的最適化施策（Issue #618 S-RTyper 関数間アンボックス特化、Issue #578 スタック配置最適化、Pass 132/133 SSA・ピープホール等）に着手する前の**「公式正典ベースライン数値（Canonical Baseline Metrics）」**を確定・記録する。

主要 6 大ワークロードについて、ULisp（x86-64 Freestanding ネイティブ）、ULisp C バックエンド（-O2）、Pure C 最適化ベースライン（-O2）、および外部主要 Scheme 処理系（Chez Scheme、Gauche、Chibi-Scheme、Guile 3.0）の実測値を多角的に収集し、`ulisp/benchmarks/BASELINE.md` および `outputs/benchmarks/canonical_baseline.json` に正式記録する。

さらに、今後の言語機能追加やリファクタリング、最適化パス導入に伴い、予期せぬ性能低下（Performance Regression）やバイナリサイズの急激な肥大化（Footprint Bloat）が発生していないかを、CI や日常開発（`make bench_verify`）で自動検知できる継続的性能監視基盤（`verify_regression.py`）を構築する。

---

## 2. トレーサビリティ / Traceability
- **正典仕様書**:
  - [DSN-33 (ULisp 包括設計仕様書)](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md) (第 2 章 Cheney GC、第 10 章 品質ゲート・テスト自動化)
  - [DSN-31 (Trio 実行階層アーキテクチャ統合仕様書)](../../docs/designs/DSN-31-trio_execution_tier_architecture.md)
  - [ULisp ベンチマークレポート](../../ulisp/benchmarks/README.md)
- **関連 Issue**:
  - [620-repair-benchmark-suite-and-establish-automated-bench-harness.md](closed/620-repair-benchmark-suite-and-establish-automated-bench-harness.md) (ベンチマークスイートの修復および make bench 自動計測ハーネスの確立)
  - [621-implement-compiler-pass-timing-and-memory-profiler.md](closed/621-implement-compiler-pass-timing-and-memory-profiler.md) (コンパイラ Nanopass 実行時間・メモリ消費プロファイラ（--time-passes）の実装)
  - [622-implement-runtime-gc-stats-and-perf-hardware-counter-integration.md](closed/622-implement-runtime-gc-stats-and-perf-hardware-counter-integration.md) (実行時 GC 統計プロファイルおよび Linux perf ハードウェアカウンタ連携基盤の実装)
  - [618-eliminate-tagging-overhead-with-interprocedural-unboxing.md](618-eliminate-tagging-overhead-with-interprocedural-unboxing.md) (S-RTyper Pass 090 および LIR / バックエンドにおける関数間アンボックス特化とタグオーバーヘッド撲滅)
  - [578-coordinate-closure-escape-and-lir-stack-allocation-pipeline.md](closed/578-coordinate-closure-escape-and-lir-stack-allocation-pipeline.md) (Pass 110/120/130 連携による非エスケープオブジェクトのスタック配置最適化)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/benchmarks/BASELINE.md](../../ulisp/benchmarks/BASELINE.md) (新規: 正典ベースライン測定レポート、実行環境スペック、Mermaid可視化図、多角分析)
- [x] [outputs/benchmarks/canonical_baseline.json](../../outputs/benchmarks/canonical_baseline.json) (新規: 機械可読正典ベースラインデータセット)
- [x] [ulisp/benchmarks/verify_regression.py](../../ulisp/benchmarks/verify_regression.py) (新規: 最新測定値 vs ベースライン回帰自動検知スクリプト)
- [x] [ulisp/benchmarks/benchmark_c_vs_x86.py](../../ulisp/benchmarks/benchmark_c_vs_x86.py) (ベースライン出力フラグ `--baseline`、試行回数制御 `--iterations`、Nanopass 時間収集連携)
- [x] [ulisp/Makefile](../../ulisp/Makefile) (`bench_baseline`, `bench_verify` ターゲットの追加と既存ベンチマークターゲット群の整理)
- [x] [ulisp/benchmarks/README.md](../../ulisp/benchmarks/README.md) (正典ベースラインへのリンク追加、回帰検知プロトコルおよび運用のドキュメント化)
- [x] [docs/issues/README.md](../../docs/issues/README.md) (Issue 台帳のステータス更新)

---

## 4. 脅威モデルと堅牢性要件 / Threat Model & Robustness Requirements

1. **測定環境ノイズ・CPU 動的周波数変動（Jitter）への耐性**:
   - WSL2 / 仮想化環境やバックグラウンドタスクによるクロック変動・コンテキストスイッチ遅延の影響を最小化するため、ベースライン採取は十分なウォームアップ（最低 5 回）と安定反復試行（30 回）を実施する。
   - 統計指標として平均値（Mean）だけでなく、中央値（Median）、最小値（Min）、最大値（Max）、標準偏差（StdDev）を併記し、外れ値の影響を可視化・制御する。
2. **回帰判定における誤検知（False Positives）の抑止**:
   - マイクロ秒単位の短時間ワークロードでは数%の自然揺らぎが発生する。回帰検知スクリプト（`verify_regression.py`）は許容閾値（Tolerance Threshold: デフォルト 10%〜15%）を設定可能とし、軽微なジッターによるビルドパイプライン停止を防止する。
   - 実行レイテンシだけでなく、環境要因を受けにくい確定的な指標（バイナリサイズ、命令数 `instructions`）を第一級の回帰監視対象として位置付ける。
3. **安全なデータ解析と入力バリデーション**:
   - `verify_regression.py` は JSON ファイルを読み込む際、破損ファイルや予期せぬ欠落キー（Missing Keys）に対して安全に例外処理を行い、明確なエラーメッセージを出力して終了する（CWE-20 対策）。
   - シェルインジェクションを回避するため、外部プロセスの起動には安全な引数リスト形式を使用する。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/623-establish-canonical-performance-baseline-and-continuous-monitoring`

### Phase 1: ベンチマークスイートのベースライン採取・測定強化 (`benchmark_c_vs_x86.py`)
1. **CLI オプションの拡充**:
   - `--iterations N` (デフォルト 10、ベースライン採取時は 30 回)
   - `--warmup N` (デフォルト 3、ベースライン採取時は 5 回)
   - `--baseline` (ベースラインモード: `outputs/benchmarks/canonical_baseline.json` を生成・更新)
   - `--include-nanopass` (コンパイラ Nanopass 実行時間 `--time-passes` を採取しプロファイルに組み込み)
2. **システム詳細スペックの自動取得**:
   - `/proc/cpuinfo` から CPU モデル名、コア数、周波数を抽出
   - `platform.platform()`, Linux カーネルバージョン、GCC バージョン、メモリ容量（MemTotal）を取得し JSON メタデータに記録
3. **多実装 Scheme データの取り込み**:
   - `run_bench_multi_scheme.py` の測定結果（Chez Scheme、Gauche、Chibi-Scheme、Guile 3.0）を統合するヘルパールーチンを整理

### Phase 2: 正典ベースラインドキュメント (`BASELINE.md`) & JSON の策定
1. **`outputs/benchmarks/canonical_baseline.json` の生成**:
   - 6 大ワークロード（`fib_30`, `loop_10m`, `ack_3_7`, `closure_1m`, `list_100k`, `vector_100k`）の 30 回試行実測データを記録。
   - 記録項目:
     - 実行時間: `mean_ms`, `median_ms`, `min_ms`, `max_ms`, `std_ms`
     - バイナリフットプリント: `size_bytes`, `text_bytes`, `data_bytes`, `bss_bytes`
     - ハードウェアカウンタ: `cycles`, `instructions`, `ipc`, `branch_miss_pct`, `cache_miss_pct`
     - GC 統計: `alloc_bytes`, `survived_bytes`, `gc_time_ms`, `gc_count`
     - 他系比較: `ratio_vs_pure_c`, `ratio_vs_ulisp_c`, `ratio_vs_chez`, `ratio_vs_gauche`
2. **`ulisp/benchmarks/BASELINE.md` の執筆**:
   - 正典ドキュメントとして、完全な測定結果、ハードウェア環境、分析考察、および Mermaid チャートを記述。
   - Mermaid チャート内容:
     - ワークロード別 Pure C に対する相対性能倍率バーチャート
     - x86-64 Native vs Pure C の IPC 比較
     - コンパイル時における各 Nanopass（Frontend, LIR, Backend）の処理時間割合

### Phase 3: 性能回帰自動検知スクリプト (`verify_regression.py`) の実装
1. **比較ロジックの構築**:
   - `outputs/benchmarks/latest.json`（最新測定結果）と `outputs/benchmarks/canonical_baseline.json`（正典ベースライン）をロード。
   - 各ワークロードについて以下の項目を比較検証：
     - 実行レイテンシ: `mean_ms` の悪化率が閾値（`--threshold-latency`, デフォルト 15%）を超えていないか
     - バイナリサイズ: `size_bytes` の増加率が閾値（`--threshold-size`, デフォルト 5%）を超えていないか
     - 命令数 / 分岐ミス: `instructions` が想定外に急増していないか
2. **出力とリターンコード制御**:
   - 回帰なし（PASS）: 差分サマリー表をコンソール出力し、Exit Code 0 で終了。
   - 回帰検出（FAIL）: 悪化したワークロード、測定値、ベースライン値、悪化率（+X%）を強調表示し、Exit Code 1 で終了。
   - Markdown 形式の回帰レポート（`build/regression_report.md`）の自動出力。

### Phase 4: `ulisp/Makefile` およびテストスイートの統合
1. **新規 Makefile ターゲットの追加**:
   - `bench_baseline`:
     ```makefile
     bench_baseline: compiler
     	$(PYTHON) benchmarks/benchmark_c_vs_x86.py --perf --iterations 30 --warmup 5 --baseline
     ```
   - `bench_verify`:
     ```makefile
     bench_verify: compiler
     	$(PYTHON) benchmarks/benchmark_c_vs_x86.py --perf --iterations 5
     	$(PYTHON) benchmarks/verify_regression.py --threshold-latency 15.0 --threshold-size 5.0
     ```
2. **ドキュメントの更新**:
   - `ulisp/benchmarks/README.md` に正典ベースラインの参照、ベースライン更新プロトコル、`make bench_verify` の活用法を追記。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `ulisp/benchmarks/BASELINE.md` が完全な実測値（レイテンシ、サイズ、perf カウンタ、GC 統計、他系比較）および Mermaid グラフとともに策定されていること。
- [x] `outputs/benchmarks/canonical_baseline.json` が生成され、Git 管理下にコミットされていること。
- [x] `ulisp/benchmarks/verify_regression.py` が実装され、正常時（Pass）および人工的な閾値超過時（Fail）の双方が正確にテスト・検証されていること。
- [x] `make -C ulisp bench_baseline` で正典ベースラインの再測定・更新が正常動作すること。
- [x] `make -C ulisp bench_verify` で最新測定値と正典ベースラインの回帰検証が自動実行され、正常終了すること。
- [x] `ulisp/benchmarks/README.md` にベースライン参照リンクと回帰検証プロトコルが明記されていること。
- [x] `make py_compile` および `make static_analysis` がエラー 0 件で通過すること。
