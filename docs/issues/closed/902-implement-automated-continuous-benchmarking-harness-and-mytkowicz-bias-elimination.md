---
ID: 902
種別: Feature
優先度: Medium
ステータス: Closed (Completed)
---

# [FEAT/ENH] Implement Automated Continuous Benchmarking Harness and Mytkowicz Bias Elimination (ID: 902)

## 1. 概要 / Summary

[[DSN-33-06]](../designs/DSN-33-06-ulisp_ilisp_aot_jit_continuous_benchmarking_framework.md) 第 2 章・第 6 章に基づき、プロジェクト内の 3 つの Scheme 実行系（**ILisp** / **ULisp AOT** / **ULisp JIT**）を同一の計算負荷ワークロードで多角的に測定・比較評価する自動ベンチマークハーネス、環境変数・スタック・コード配置による測定バイアス排除（Mytkowicz 手法）、および `outputs/benchmarks/` への JSON 履歴自動蓄積パイプラインを実装する。

本基盤により、機能拡張や最適化パス追加による予期せぬ性能退行（パフォーマンスリグレッション）を客観的・統計的かつ決定論的に検知・ブロックできる強固な CI/CD 品質ゲートを確立する。

---

## 2. トレーサビリティ / Traceability

- 関連設計書:
  - [[DSN-33-06] ILisp・ULisp AOT・ULisp JIT 3種実行系 継続的性能評価基盤 設計仕様書 (第2章・第6章)](../designs/DSN-33-06-ulisp_ilisp_aot_jit_continuous_benchmarking_framework.md)
  - [[DSN-33-05] ULisp 内因的メタトレーシング JIT アーキテクチャ包括設計書](../designs/DSN-33-05-ulisp_endogenous_meta_tracing_jit_architecture.md)
  - [[DSN-33-02] ULisp 多言語フロントエンド ＆ 型付き機械語 LIR 設計書](../designs/DSN-33-02-ulisp_multilingual_frontend_and_typed_machine_lir_architecture.md)
  - [[DSN-33] ULISP 包括設計仕様書](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
- 先行 Issue:
  - [Issue #901: 最適化済み LIR トレースからインメモリ W^X 実行可能バッファへのネイティブ機械語直接アセンブル配線](closed/901-integrate-jit-trace-buffer-with-in-memory-native-x86-emitter.md)
  - [Issue #900: JIT トレース最適化（ガード除去・仮想化）および脱出 Deopt トランポリンの実装](closed/900-implement-jit-trace-optimizer-and-guard-failure-deopt-trampoline.md)
  - [Issue #899: ホットループ検出プロファイラおよび限定継続（shift/reset）線形トレースレコーダの実装](closed/899-implement-hot-loop-profiler-and-linear-trace-recorder.md)
  - [Issue #898: 評価器ループに対する JIT マージポイントおよび型ガード注釈基盤の実装](closed/898-implement-jit-loop-merge-point-and-guard-annotations.md)
- 後続 Issue:
  - [Issue #903: 統計的性能退行（Regression Detector）自動検知器および日本語ベンチマークレポート自動生成](903-implement-performance-regression-detector-and-automated-markdown-reporting.md)

---

## 3. 脅威モデルとセキュリティ要件 (Threat Model & Security Requirements)

| 脅威 ID | 分類 (STRIDE) | 脆弱性・リスク事象 | 対策方針・緩和策 |
| :--- | :--- | :--- | :--- |
| **TM-902-01** | Denial of Service (DoS) | 悪意あるループ式や過大ループによる CPU/メモリリソース枯渇（CWE-400） | 各ワークロード実行プロセスに対して一律 60 秒のサブプロセス・タイムアウト（`subprocess.run(timeout=60)`）を強制適用。 |
| **TM-902-02** | Tampering / Information Disclosure | 環境変数パディング処理における予期せぬバッファオーバーランや不正文字混入（CWE-119 / CWE-20） | `BENCHMARK_ENV_PAD` にASCII英字 `'X'` のみを充填し、合計長を安全に 4,096 バイト固定（4KB アライン）に正規化。 |
| **TM-902-03** | Tampering | ベンチマーク結果の出力先パス指定におけるパストラバーサル（CWE-22 / CWE-73） | 出力先パス（`--json-out`, `--markdown-out`）を `Path.resolve()` で検証し、リポジトリルート外への不正書き込みを遮断。 |
| **TM-902-04** | Elevation of Privilege | Linux `perf stat` 実行時の権限不足エラーによるクラッシュ | `perf_event_paranoid` 制限を検知した場合、例外を握りつぶさず安全に Wall-clock / CPU time 計測のみへグレースフル・フォールバック。 |

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files

### 対象ソースコード
- [`tools/benchmark_ilisp_ulisp.py`](../../tools/benchmark_ilisp_ulisp.py)
  - 3 種実行系測定ループ、Mytkowicz 4KB 環境変数パディング、`perf stat` 連携、結果 JSON / Markdown 生成。
- [`ulisp/workbench/frame.scm`](../../ulisp/workbench/frame.scm)
  - `gfd-add-slot!` の可変長引数（`. maybe-type`）を Stage 2 コンパイラ適合形式（固定引数／アリティ固定）へリファクタリング。
- [`ulisp/Makefile`](../../ulisp/Makefile)
  - `bin/ulisp-jit` ビルドターゲットの安定化、`bench_trio`, `bench_ci`, `bench_perf` ルール確認。
- [`Makefile`](../../Makefile)
  - ルート Makefile における `benchmark_trio`, `bench_ci`, `bench_perf` ターゲットの統合。
- [`outputs/benchmarks/latest.json`](../../outputs/benchmarks/latest.json)
  - 最新の 3 種実行系測定結果スナップショット（ベースライン）。
- [`outputs/benchmarks/history/`](../../outputs/benchmarks/history/)
  - タイムスタンプ付き実行履歴保存ディレクトリ。

---

## 5. 実装方針 / Implementation Plan

Target Branch: `feat/902-implement-automated-continuous-benchmarking-harness-and-mytkowicz-bias-elimination`

### Step 1: Stage 2 コンパイラでの `bin/ulisp-jit` ビルド修正
1. `ulisp/workbench/frame.scm` の `gfd-add-slot!` における可変長引数（`. maybe-type`）を、AOT コンパイラ（Stage 2）で正しく解決できるよう修正：
   ```scheme
   (define (gfd-add-slot! gfd name . maybe-type) ...)
   ;; -> 内部実装を 3 引数 (gfd-add-slot-typed! gfd name type-hint) と
   ;;    2 引数 (gfd-add-slot! gfd name) に整理、または case-lambda 適合化
   ```
2. `make -C ulisp jit` を実行し、スタンドアロンネイティブバイナリ `ulisp/bin/ulisp-jit` が正常にコンパイル・リンクされることを検証。
3. `make -C ulisp run_jit` により、JIT ループ実行および AOT コンパイル機能が単体で動作することを確認。

### Step 2: 5 つの標準ワークロードの 3 種実行系完全一致検証
1. 以下の 5 ワークロードの計算結果が、ILisp、ULisp AOT、ULisp JIT のすべてで 100% 同一であることを保証：
   - `fib_loop`: `(fib 20)` $\to$ `6765`
   - `fact_loop`: `(fact 12)` $\to$ `479001600`
   - `sum_loop`: `(sum 5000)` $\to$ `12497500`
   - `poly_loop`: `(poly 1000)` $\to$ `1001005000`
   - `tri_loop`: `(tri 500)` $\to$ `125250`
2. `tools/benchmark_ilisp_ulisp.py` の `extract_result` を堅牢化し、バナーやデバッグ出力が混入しても正確に戻り値を抽出できることを確認。

### Step 3: Mytkowicz 測定バイアス排除プロトコルの高度化
1. **スタック配置バイアス排除 (Stack Alignment Bias)**:
   - `make_padded_env()` による環境変数文字列長 4,096 バイト固定化（`BENCHMARK_ENV_PAD`）の確実な適用。
2. **ハードウェア性能カウンタの同時取得**:
   - Linux `perf stat` 連携 (`--perf` オプション) で `instructions`, `branch-misses`, `cycles`, `page-faults` を取得し、最適化による動的命令数削減を客観的に評価。
   - 実行権限がない環境では警告を表示し、Wall-clock 時間計測へ自動フォールバック。
3. **ウォームアップと統計値算出**:
   - 各ワークロードで初回実行（JIT ウォームアップ／ページフォルト）を考慮し、平均値、中央値、最小値、最大値、標準偏差（Variance）を算出。

### Step 4: 継続的ストレージ蓄積と Makefile ターゲット整備
1. ベンチマーク実行結果を `outputs/benchmarks/latest.json` へ出力。
2. 同時に `outputs/benchmarks/history/benchmark_YYYYMMDD_HHMMSS.json` へ履歴スナップショットを自動保存。
3. `outputs/benchmarks/benchmark_report.md` を更新。
4. ルート Makefile および `ulisp/Makefile` の `benchmark_trio` / `bench_ci` が 1 コマンドで確実に動作することを確認。

---

## 6. 完了条件 / Success Criteria (DoD)

- [x] `ulisp/workbench/frame.scm` の修正により `make -C ulisp jit` がエラーなく完走し、`ulisp/bin/ulisp-jit` が生成されること。
- [x] `make -C ulisp run_jit` が PASS すること。
- [x] 5 つの標準ワークロード（`fib_loop`, `fact_loop`, `sum_loop`, `poly_loop`, `tri_loop`）すべてで、ILisp、ULisp AOT、ULisp JIT の実行結果が期待値と 100% 一致すること。
- [x] `python3 tools/benchmark_ilisp_ulisp.py --iterations 3` が単一コマンドで完走し、`outputs/benchmarks/latest.json` および `history/` スナップショットが生成されること。
- [x] `make benchmark_trio` および `make bench_ci` が正常終了すること。
- [x] `make py_compile` および `make static_analysis` がエラー 0 件で PASS すること。
- [x] 相対パス規則（絶対パス 0 件）が完全に遵守されていること。
