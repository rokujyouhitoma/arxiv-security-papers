---
ID: 622
種別: Feature
優先度: Medium
ステータス: Open (In Progress)
---

# [FEAT/ENH] 実行時 GC 統計プロファイル（ULISP_GC_STATS）および Linux perf ハードウェアカウンタ連携基盤の実装 (ID: 622)

## 1. 概要 / Summary
ULisp でコンパイルされたバイナリの実行時ボトルネックを客観的・定量的に特定するためには、単に「全体の実行時間（Wall-clock time）」を見るだけでは不十分である。「時間が GC で消費されているのか」「間接呼び出しによる CPU 分岐予測ミスなのか」「メモリアクセスのキャッシュミスなのか」を多角的に切り分けられなければ、Issue #618（関数間アンボックス最適化）や Issue #578（スタック配置最適化）等の最適化施策の効果測定を正確に行うことができない。

本 Issue では、ネイティブランタイムおよび C バックエンドに GC 停止時間・総回収回数・総割り当てバイト数・総生存コピーバイト数を記録・表示する `ULISP_GC_STATS=1` 機能を実装する。さらに、ベンチマークスイート（`benchmark_c_vs_x86.py`）から Linux のハードウェア性能カウンタ（`perf stat`）を自動呼び出し、CPU サイクル数、命令数（IPC: Instructions Per Cycle）、ブランチミス予測率、および L1/LLC キャッシュミス率を自動集計・分析できるプロファイリング基盤を構築する。

---

## 2. トレーサビリティ / Traceability
- **正典仕様書**:
  - [DSN-33 (ULisp 包括設計仕様書)](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md) (第 2 章 Cheney GC、第 10 章 品質ゲート)
  - Linux `perf` Performance Analysis Tools Specification (`perf_event_open` / `perf stat`)
- **関連 Issue**:
  - [501-cheney-2space-gc.md](closed/501-cheney-2space-gc.md) (Cheney's 2-Space コピーガベージコレクタの導入)
  - [569-separate-x86-gc-collector-and-freestanding-runtime-passes.md](closed/569-separate-x86-gc-collector-and-freestanding-runtime-passes.md) (x86-64 GC コレクタの物理パス分離)
  - [577-implement-gc-stress-testing-mode-for-c-and-native-backends.md](closed/577-implement-gc-stress-testing-mode-for-c-and-native-backends.md) (C バックエンドおよびネイティブ後端共通 GC ストレステストモード)
  - [580-deprecate-runtime-c-and-implement-pure-scheme-runtime.md](closed/580-deprecate-runtime-c-and-implement-pure-scheme-runtime.md) (Pre-Scheme 思想に基づく自己完結 Scheme ランタイム)
  - [620-repair-benchmark-suite-and-establish-automated-bench-harness.md](closed/620-repair-benchmark-suite-and-establish-automated-bench-harness.md) (ベンチマークスイートの修復および make bench 自動計測ハーネスの確立)
  - [618-eliminate-tagging-overhead-with-interprocedural-unboxing.md](618-eliminate-tagging-overhead-with-interprocedural-unboxing.md) (S-RTyper 関数間アンボックス特化)
  - [621-implement-compiler-pass-timing-and-memory-profiler.md](closed/621-implement-compiler-pass-timing-and-memory-profiler.md) (コンパイラ Nanopass 実行時間・メモリ消費プロファイラ)
  - [623-establish-canonical-performance-baseline-and-continuous-monitoring.md](623-establish-canonical-performance-baseline-and-continuous-monitoring.md) (ULisp 正典性能ベースライン測定レポート策定)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/backend/140_backend_x86_64.scm](../../ulisp/backend/140_backend_x86_64.scm)
  - `ulisp_gc_state` バッファのスロット拡張（累積割り当て量、生存コピー量、GC時間、開始時間、統計フラグ）
  - `.L_flags_scan_loop`: 環境変数 `ULISP_GC_STATS=` のパースと `ulisp_gc_stats_mode` の有効化
  - プログラム開始時（`clock_gettime`）および終了時（`.L_start_exit`）の統計出力トリガー
  - `ulisp_print_gc_stats` / `ulisp_print_u64_stderr`: libc 非依存の標準エラー出力ルーチン生成
- [ ] [ulisp/backend/141_backend_x86_gc.scm](../../ulisp/backend/141_backend_x86_gc.scm)
  - `ulisp_gc_collect`: GC 開始前後のタイムスタンプ計測（`sys_clock_gettime(CLOCK_MONOTONIC=1)` syscall 228）
  - Cheney デュアルスペースおよび世代別マイナー GC 完了時における累積生存コピーバイト数の加算
  - バンプポインタ `r12` の変移に基づく累積割り当てバイト数の追跡
- [ ] [ulisp/backend/160_backend_c.scm](../../ulisp/backend/160_backend_c.scm)
  - C バックエンドにおける `ULISP_GC_STATS` 環境変数の解釈と GC 統計（割り当て量、GC回数、コピー量、GC時間）の標準エラー出力対応
- [ ] [ulisp/runtime/gc.scm](../../ulisp/runtime/gc.scm)
  - `ulisp_gc_state` のスロット定義更新（スロット 17: alloc_bytes, 18: survived_bytes, 19: gc_time_ns, 20: stats_mode, 21: start_time_ns）
  - アクセサ手続き群（`runtime-gc-alloc-bytes`, `runtime-gc-survived-bytes`, `runtime-gc-total-time-ns`）の追加
- [ ] [ulisp/benchmarks/benchmark_c_vs_x86.py](../../ulisp/benchmarks/benchmark_c_vs_x86.py)
  - CLI 引数 `--perf` の追加
  - `perf stat -x, -e cycles,instructions,branches,branch-misses,cache-references,cache-misses` による自動計測ハーネス
  - CSV 出力のパース処理（IPC, Branch Miss Rate %, Cache Miss Rate % の算出）
  - コンソール出力、Markdown 表（`build/bench_c_x86/bench_results.md`）、JSON（`outputs/benchmarks/latest.json`）のカラム拡張
  - `perf` コマンド未導入時および `kernel.perf_event_paranoid` 権限不足時の安全なフォールバック
- [ ] [ulisp/tests/test_gc_stats.sh](../../ulisp/tests/test_gc_stats.sh) (新規テストスイート)
  - `ULISP_GC_STATS=1` 指定時における x86-64 および C バイナリの統計出力フォーマット検証
  - 通常実行（`ULISP_GC_STATS` 未指定）時に標準エラー出力が沈黙（Quiet-by-Default）を維持することの検証
- [ ] [ulisp/Makefile](../../ulisp/Makefile)
  - `bench_perf`: `$(PYTHON) benchmarks/benchmark_c_vs_x86.py --perf` への更新
  - `test_gc_stats`: テストスイートの追加と `test` ターゲットへの統合

---

## 4. 脅威モデルとセキュリティ・堅牢性要件 / Threat Model & Security Requirements

1. **環境変数パースのバウンダリ検証**:
   - `ULISP_GC_STATS=` のパース処理は、ELF プロセス起動時に渡される `envp` 配列を直接走査する。ヌル終端の検証、未知の値に対するデフォルト沈黙化（`ULISP_GC_STATS=0` または空文字列の場合は無効化）を徹底し、スタック破壊や未初期化ポインタ参照を防止する。
2. **Freestanding 環境での安全な I/O 出力**:
   - `sys_write` (syscall 1) をファイルディスクリプタ 2 (stderr) に対して直接実行する。一時バッファはスタック上の固定サイズ（64バイト）を用い、バッファオーバーランを原理的に排除する。
3. **ハードウェアカウンタの権限・環境互換性**:
   - コンテナや VM 環境では `perf_event_paranoid > 2` によりハードウェアカウンタへのアクセスが遮断される場合がある。`benchmark_c_vs_x86.py` は `perf` の失敗・未検出をトラップし、例外終了させずに `N/A` 表記でフォールバックする。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/622-implement-runtime-gc-stats-and-perf-hardware-counter-integration`

### Phase 1: ランタイム GC 統計収集アーキテクチャの確立 (`gc.scm` & `140_backend_x86_64.scm`)
1. **`ulisp_gc_state` メモリレイアウトの拡張**:
   - 現在の 256 バイト（32 クアッドワード）領域内に新規スロットを割当：
     - Slot 17 (Offset 136): `total_alloc_bytes` (累積割り当てバイト数)
     - Slot 18 (Offset 144): `total_survived_bytes` (累積生存コピーバイト数)
     - Slot 19 (Offset 152): `total_gc_time_ns` (累積 GC 停止時間 ナノ秒)
     - Slot 20 (Offset 160): `stats_mode` (0: 無効, 1: 有効)
     - Slot 21 (Offset 168): `start_time_sec` (プロセス開始時刻 秒)
     - Slot 22 (Offset 176): `start_time_nsec` (プロセス開始時刻 ナノ秒)
2. **環境変数 `ULISP_GC_STATS` のスキャン (`140_backend_x86_64.scm`)**:
   - `.L_flags_scan_loop` にて、接頭辞 `ULISP_GC_STATS=` (15 文字) を比較。
   - 値が `'1'` または非ゼロ文字列の場合、`ulisp_gc_state[20]` を 1 に設定。
   - 同時に `sys_clock_gettime(CLOCK_MONOTONIC=1, &timespec)` (syscall 228) を発行し、開始時刻を Slot 21/22 に保存。

### Phase 2: GC コレクタでの時間・コピー量追跡 (`141_backend_x86_gc.scm`)
1. **割り当てバイト数の非侵襲追跡**:
   - `%alloc` のホットパス（bump pointer `add r12, bytes`）には一切追加命令を挿入せず、ゼロオーバーヘッドを維持。
   - `ulisp_gc_collect` の突入時、直前の空間開始点から `r12` までの消費量（`r12 - from` または `r12 - nursery_base`）を `total_alloc_bytes` に加算。
   - プログラム終了時（`.L_start_exit`）にも同様に最終サイクル分の消費量を `total_alloc_bytes` に加算。
2. **GC 停止時間の計測**:
   - `stats_mode == 1` の場合のみ、`ulisp_gc_collect` の開始直前および復帰直前に `sys_clock_gettime` を発行。
   - 差分ナノ秒（`(end_sec - start_sec) * 1e9 + (end_nsec - start_nsec)`）を `total_gc_time_ns` にアトミック加算。
3. **生存コピー量の集計**:
   - Cheney デュアルスペース完了時: `free_ptr - to_space` を `total_survived_bytes` に加算。
   - 世代別マイナー GC 完了時: プロモートされた Mature 空間の増加量（`mature_free_end - mature_free_start`）を加算。

### Phase 3: 標準エラー出力フォーマッタと C バックエンド同期 (`140_backend_x86_64.scm` & `160_backend_c.scm`)
1. **`ulisp_print_gc_stats` の実装 (Freestanding x86-64)**:
   - スタック上に数値を ASCII 文字列化する `ulisp_print_u64_stderr` を配置。
   - `.L_start_exit` にて `stats_mode == 1` を検知した場合、標準エラー出力に整形サマリーを出力：
     ```text
     [ULISP GC STATS] Collections: 14 (Minor: 14, Major: 0), Alloc: 45.2 MB, Copied: 1.2 MB, GC Time: 1.42 ms (1.8% of total)
     ```
2. **C バックエンド (`160_backend_c.scm`) の同期**:
   - `getenv("ULISP_GC_STATS")` を検出し、`main()` 終了時および `ulisp_gc_collect()` にて同様の統計を出力。

### Phase 4: `benchmark_c_vs_x86.py` への `perf stat` 連携とレポート拡充
1. **CLI オプション `--perf` の追加**:
   - `argparse` または引数解析にて `--perf` を受付。
2. **`measure_perf(bin_path, iters)` ハーネス**:
   - 以下のコマンドでバイナリをラップ実行：
     ```bash
     perf stat -x, -e cycles,instructions,branches,branch-misses,cache-references,cache-misses ./bin
     ```
   - 標準エラー出力の CSV 形式から各カウンタを抽出：
     - `IPC = instructions / cycles`
     - `Branch Miss Rate (%) = (branch-misses / branches) * 100.0`
     - `Cache Miss Rate (%) = (cache-misses / cache-references) * 100.0`
3. **Markdown / JSON レポートの更新**:
   - `bench_results.md` の表に `IPC`, `Branch Miss %`, `Cache Miss %` カラムを追加。
   - `outputs/benchmarks/latest.json` の各ワークロード結果に `perf` オブジェクトを格納。
4. **Makefile ターゲットの整備**:
   - `make bench_perf` で本機能が一発実行できるようにターゲットを最新化。

---

## 6. 完了条件 / Success Criteria (DoD)
- [ ] `ULISP_GC_STATS=1 ./binary` を実行した際、GC 回数・総割り当て量・生存コピー量・停止時間が標準エラー出力に規定フォーマットで出力されること。
- [ ] 通常実行時（`ULISP_GC_STATS` 未指定時）において、標準エラー出力が沈黙を保ち、オーバーヘッドが 0.1% 未満（ホットパス無変更）であること。
- [ ] `140_backend_x86_64.scm`（ネイティブ）および `160_backend_c.scm`（C バックエンド）の双角で同一の `ULISP_GC_STATS` 仕様が動作すること。
- [ ] `python3 benchmarks/benchmark_c_vs_x86.py --perf`（または `make bench_perf`）が正常に完走し、IPC、分岐予測ミス率、キャッシュミス率が集計・出力されること。
- [ ] `perf` 権限がない環境または未インストール環境でも、エラーで異常終了せず警告とともに安全にフォールバックすること。
- [ ] 新規テストスイート `ulisp/tests/test_gc_stats.sh` が作成され、全項目 PASS すること。
- [ ] `make test` および `make py_compile` / `make static_analysis` が 100% エラー 0 件で通過すること。

