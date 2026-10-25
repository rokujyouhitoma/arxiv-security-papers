---
ID: 621
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] コンパイラ Nanopass 実行時間・メモリ消費プロファイラ（--time-passes）の実装 (ID: 621)

## 1. 概要 / Summary
ULisp はフロントエンド（マクロ展開・脱糖・解析）、LIR（最適化・SSA・ピープホール）、バックエンド（コード生成）にわたり 30 以上の独立した Nanopass で構成されている。現在、全体のコンパイル所要時間は計測できるものの、各 Nanopass がどれだけの時間（ミリ秒）とメモリ（ヒープ cons アロケーション）を消費しているかの詳細な内訳を観測する機能が存在しない。

本 Issue では、コンパイラドライバおよび Pass Manager に `--time-passes`（または環境変数 `ULISP_BENCH_PASSES=1`）オプションを実装する。これにより、各パスの実行時間、割合（%）、累積時間、およびメモリ消費量をテーブル形式で標準エラー出力へ表示可能にし、コンパイル速度のボトルネック特定と Pass 融合（Pass Fusion）の定量的指針を提供する。

---

## 2. トレーサビリティ / Traceability
- **正典仕様書**:
  - [DSN-33 (ULisp 包括設計仕様書)](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md) (第 2 章、第 8 章)
  - [ULisp パイプライン・Nanopass 詳細仕様書](../../ulisp/docs/spec_pipeline.md)
- **関連 Issue**:
  - Issue 586: Nanopass Framework DSL Phase 4: パイプライン統御・AST Diff トレーサの実装
  - Issue 598: 統一 Pass Manager の導入によるパイプライン制御・最適化レベルスケジューリングの一元化
  - Issue 620: ベンチマークスイートの修復および make bench 自動計測ハーネスの確立
  - Issue 623: ULisp 正典性能ベースライン測定レポート（BASELINE.md）の策定

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/compiler/pass_manager.scm](../../ulisp/compiler/pass_manager.scm) (各パス前後の高精度タイマー計測および統計収集ロジックの追加)
- [ ] [ulisp/compiler/driver.scm](../../ulisp/compiler/driver.scm) (`--time-passes` CLI フラグおよび環境変数のパース・レポート出力)
- [ ] [ulisp/tests/test_pass_profiler.sh](../../ulisp/tests/test_pass_profiler.sh) (新規: プロファイラ出力の整合性検証テスト)
- [ ] [ulisp/Makefile](../../ulisp/Makefile) (`test_profiler` ターゲットの追加)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/621-implement-compiler-pass-timing-and-memory-profiler`

1. **高精度タイマー・プロファイリング状態管理の導入**:
   - `pass_manager.scm` に `*pass-profiling-enabled*` フラグおよび各パス名ごとの `(name, start-time, elapsed-time, alloc-count)` 記録用テーブルを整備。
   - 時刻取得には R7RS `(current-second)` または POSIX 高精度時刻（ナノ秒/マイクロ秒）を利用。
2. **Pass ディスパッチャのフック拡張**:
   - `run-pass` 実行ラッパーにおいて、プロファイリング有効時に前後の時刻を取得し、累積実行時間を記録。
3. **集計レポートのフォーマット出力**:
   - コンパイル完了時、標準エラー出力に以下のような整形テーブルを出力：
     ```text
     === Nanopass Execution Profile (Total: 4.82 ms) ===
     Pass Name                      Time (ms)    Share (%)   Cumulative
     ------------------------------------------------------------------
     Pass 020 Macro Expander           1.25 ms       25.9%      1.25 ms
     Pass 040 Analysis                 0.31 ms        6.4%      1.56 ms
     Pass 090 S-RTyper                 0.45 ms        9.3%      2.01 ms
     Pass 132 Braun SSA                0.88 ms       18.3%      2.89 ms
     Pass 140 Backend x86-64           0.72 ms       14.9%      3.61 ms
     ...
     ```
4. **テストおよび自動化**:
   - 通常のコンパイル実行時にはプロファイラが無効化され、オーバーヘッドがゼロであることを保証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `--time-passes` フラグまたは `ULISP_BENCH_PASSES=1` 付与時に、全実行 Nanopass の個別所要時間テーブルが表示されること。
- [ ] 各パスの所要時間の合計が全体のコンパイル所要時間と概ね一致（計測誤差 5% 以内）すること。
- [ ] 通常コンパイル（フラグなし）時にプロファイリングオーバーヘッドが発生しないこと。
