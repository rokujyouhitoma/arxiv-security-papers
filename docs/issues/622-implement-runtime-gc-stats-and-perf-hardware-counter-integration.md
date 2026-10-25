---
ID: 622
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] 実行時 GC 統計プロファイル（ULISP_GC_STATS）および Linux perf ハードウェアカウンタ連携基盤の実装 (ID: 622)

## 1. 概要 / Summary
ULisp でコンパイルされたバイナリの実行時ボトルネックを特定するためには、単に「全体の実行時間（Wall-clock time）」を見るだけでは不十分であり、「時間が GC で消費されているのか」「間接呼び出しによる CPU 分岐予測ミスなのか」「メモリアクセスのキャッシュミスなのか」を定量的に切り分ける必要がある。

本 Issue では、ネイティブランタイムに GC 停止時間・総回収回数・割り当て総バイト数を記録・表示する `ULISP_GC_STATS=1` 機能を実装する。さらに、ベンチマークスイートから Linux のハードウェア性能カウンタ（`perf stat`）を自動呼び出し、CPU サイクル数、命令数（IPC: Instructions Per Cycle）、ブランチミス予測率、および L1 キャッシュミス率を自動集計・分析できるプロファイリング基盤を構築する。

---

## 2. トレーサビリティ / Traceability
- **正典仕様書**:
  - [DSN-33 (ULisp 包括設計仕様書)](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md) (第 2 章 Cheney GC、第 10 章 品質ゲート)
  - Linux `perf` Performance Analysis Tools Specification
- **関連 Issue**:
  - Issue 501: Cheney's 2-Space コピーガベージコレクタの導入
  - Issue 577: C バックエンドおよびネイティブ後端共通 GC ストレステストモードの実装
  - Issue 620: ベンチマークスイートの修復および make bench 自動計測ハーネスの確立
  - Issue 623: ULisp 正典性能ベースライン測定レポート（BASELINE.md）の策定

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/runtime/gc.scm](../../ulisp/runtime/gc.scm) / [ulisp/backend/141_backend_x86_gc.scm](../../ulisp/backend/141_backend_x86_gc.scm) (`ULISP_GC_STATS` による統計収集・出力ロジックの実装)
- [ ] [ulisp/benchmarks/benchmark_c_vs_x86.py](../../ulisp/benchmarks/benchmark_c_vs_x86.py) (`perf stat` 連携オプション `--perf` の追加)
- [ ] [ulisp/tests/test_gc_stats.sh](../../ulisp/tests/test_gc_stats.sh) (新規: GC 統計出力テスト)
- [ ] [ulisp/Makefile](../../ulisp/Makefile) (`bench_perf` ターゲットの追加)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/622-implement-runtime-gc-stats-and-perf-hardware-counter-integration`

1. **GC 統計収集機能（Pass 141 & runtime/gc.scm）の実装**:
   - ランタイムのデータセグメントに以下の統計カウンタ変数を配置：
     - `ulisp_gc_count`: 総 GC 回数
     - `ulisp_gc_bytes_allocated`: 総割り当てバイト数
     - `ulisp_gc_bytes_survived`: 総生存コピーバイト数
     - `ulisp_gc_total_time_ns`: 総 GC 停止時間（ナノ秒）
   - プログラム終了時（`sys_exit` 直前）、環境変数 `ULISP_GC_STATS=1` が設定されていれば、標準エラー出力に統計サマリーを直接出力：
     ```text
     [ULISP GC STATS] Collections: 14, Alloc: 45.2 MB, Copied: 1.2 MB, GC Time: 1.42 ms (1.8% of total)
     ```
2. **`benchmark_c_vs_x86.py` への Linux `perf stat` 連携**:
   - `python3 benchmark_c_vs_x86.py --perf` 実行時、各バイナリを以下のようにラップして実行：
     ```bash
     perf stat -e cycles,instructions,branches,branch-misses,cache-references,cache-misses ./bin
     ```
   - 出力から **IPC（instructions / cycles）**、**Branch Miss Rate (%)**、**Cache Miss Rate (%)** をパースし、Markdown 表にカラムを追加。
3. **性能改善の判定基準化**:
   - 間接呼び出し最適化（Devirtualization）時は `branch-misses` の減少を確認。
   - スタック割り当て最適化時は `Allocated Bytes` および `cache-misses` の減少を確認。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `ULISP_GC_STATS=1 ./binary` を実行した際、GC 回数・メモリ割り当て量・停止時間が標準エラー出力に正しく出力されること。
- [ ] `benchmark_c_vs_x86.py --perf` により、各ワークロードの IPC、分岐予測ミス率、キャッシュミス率が集計されること。
- [ ] 統計採取を有効化しない通常実行時において、性能低下が 0.1% 未満であること。
