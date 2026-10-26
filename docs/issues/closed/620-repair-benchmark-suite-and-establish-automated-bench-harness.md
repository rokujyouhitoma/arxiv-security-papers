---
ID: 620
種別: Feature
優先度: High
ステータス: Closed (Completed)
完了日: 2026-10-26
---

# [FEAT/ENH] ベンチマークスイート（benchmark_c_vs_x86）の修復・Freestanding対応および make bench 自動計測ハーネスの確立 (ID: 620)

## 1. 概要 / Summary
現在 ULisp の性能測定スクリプト [ulisp/benchmarks/benchmark_c_vs_x86.py](../../ulisp/benchmarks/benchmark_c_vs_x86.py) は、Issue #580（Pre-Scheme 思想に基づく Scheme 自給自足ランタイム化）で完全廃止された `runtime.c` を未だに参照しているため、実行時に `cc1: fatal error: runtime.c: No such file or directory` で異常終了する状態となっている。同様に、関連スクリプト（[run_bench_c_vs_x86.sh](../../ulisp/benchmarks/run_bench_c_vs_x86.sh), [run_bench_multi_scheme.py](../../ulisp/benchmarks/run_bench_multi_scheme.py), [benchmark_stage2_vs_ulisp_jit.py](../../ulisp/benchmarks/benchmark_stage2_vs_ulisp_jit.py)）にも `runtime.c` への参照が残存している。

また、測定環境や試行回数、ウォームアップ、統計値（平均・標準偏差・最小値・最大値）の集計・レポート出力機能が統一されておらず、結果を客観的に比較・追跡するための Markdown / JSON レポート出力が整備されていない。

本 Issue では、最適化施策（Issue #618 S-RTyper アンボックス特化や Issue #621 プロファイラ等）に着手する前の絶対的前提条件として、以下の改修を実施する：
1. **Freestanding ネイティブ対応**: 現在の Freestanding x86-64 バックエンド（Pass 142、`gcc -nostdlib -static`）および完全自己完結型 C バックエンド（Pass 160、`gcc -O2`）に適合するようベンチマーク群を全面修復する。
2. **三位一体性能比較（ULisp x86-64 vs ULisp C vs Pure C）**:
   - `ULisp x86-64 Native`: Freestanding AOT コンパイル（libc 依存ゼロ）
   - `ULisp C Backend`: `(!target c)` 出力 C コード（`gcc -O2`）
   - `Pure C Baseline`: 同一アルゴリズムの純粋な手書き C99 実装（`gcc -O2`）
3. **代表的 6 大ワークロードの標準化**: 整数演算・再帰・末尾再帰・クロージャ・ヒープ割当/走査・ベクタアクセスを網羅。
4. **自動計測ハーネスの確立**: `make bench` で一発実行可能とし、ウォームアップ 3 回 + 本試行 10 回の精密統計値を算出し、コンソール、`build/bench_results.md`、および `build/bench_results.json` に自動出力する。

---

## 2. トレーサビリティ / Traceability
- **正典仕様書**:
  - [DSN-33 (ULisp 包括設計仕様書)](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md) (第 3 章、第 10 章)
  - [ULisp ベンチマークレポート](../../ulisp/benchmarks/README.md)
- **関連 Issue**:
  - [580-deprecate-runtime-c-and-implement-pure-scheme-runtime.md](closed/580-deprecate-runtime-c-and-implement-pure-scheme-runtime.md) (`runtime.c` の完全廃止と低水準 Scheme ランタイム化)
  - [512-aot-vs-jit-performance-evaluation.md](closed/512-aot-vs-jit-performance-evaluation.md) (AOT vs JIT ベンチマーク評価基盤の導入)
  - [515-differential-and-benchmark-suite.md](closed/515-differential-and-benchmark-suite.md) (Trio ベンチマーク基盤)
  - [615-decouple-gcc-driver-and-migrate-to-direct-as-ld-invocation.md](615-decouple-gcc-driver-and-migrate-to-direct-as-ld-invocation.md) (脱 GCC ドライバと as/ld 直接駆動)
  - [618-eliminate-tagging-overhead-with-interprocedural-unboxing.md](618-eliminate-tagging-overhead-with-interprocedural-unboxing.md) (関数間アンボックス特化)
  - [621-implement-compiler-pass-timing-and-memory-profiler.md](621-implement-compiler-pass-timing-and-memory-profiler.md) (コンパイラ Nanopass 実行時間・メモリ消費プロファイラ)
  - [623-establish-canonical-performance-baseline-and-continuous-monitoring.md](623-establish-canonical-performance-baseline-and-continuous-monitoring.md) (正典性能ベースライン測定レポート策定)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/benchmarks/benchmark_c_vs_x86.py](../../ulisp/benchmarks/benchmark_c_vs_x86.py)
  - `runtime.c` 依存の完全除去
  - `compile_x86()`: `gcc -nostdlib -static` による Freestanding リンク維持
  - `compile_c()`: `runtime.c` 引数を削除し、Pass 160 の自己完結 C 出力を `gcc -Wall -Wextra -Werror -Wno-unused-label -O2` で直接コンパイル
  - `compile_pure_c()`: 同等アルゴリズムの純粋 C99 コードをオンザフライ生成・コンパイル
  - 6 大ワークロード定義（Fibonacci, Tail-Loop, Ackermann, Closure, List Alloc, Vector Traverse）
  - ウォームアップ 3 回 + 本試行 10 回、統計値（平均、最小、最大、標準偏差）計算
  - `build/bench_results.md` および `build/bench_results.json` への出力機能追加
- [ ] [ulisp/benchmarks/run_bench_c_vs_x86.sh](../../ulisp/benchmarks/run_bench_c_vs_x86.sh)
  - `gcc ... runtime.c ...` を `gcc ... -Wno-unused-label -O2 "$c_file" ...` に修正
- [ ] [ulisp/benchmarks/run_bench_multi_scheme.py](../../ulisp/benchmarks/run_bench_multi_scheme.py)
  - `RUNTIME_C` 依存の除去
  - `compile_ulisp_c()` の修正
- [ ] [ulisp/benchmarks/benchmark_stage2_vs_ulisp_jit.py](../../ulisp/benchmarks/benchmark_stage2_vs_ulisp_jit.py)
  - `RUNTIME_C` 依存の除去
  - `gcc -no-pie -O2 runtime.c s_path` から `gcc -nostdlib -static s_path` への移行
- [ ] [ulisp/Makefile](../../ulisp/Makefile)
  - `bench` ターゲットを更新し、`compiler` 依存および修復された `benchmark_c_vs_x86.py` の自動実行へ統合
- [ ] [ulisp/benchmarks/README.md](../../ulisp/benchmarks/README.md)
  - `runtime.c` 記載を全面撤廃し、Freestanding x86-64 および Standalone C のコンパイルコマンドと実行手順を最新化

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/620-repair-benchmark-suite-and-establish-automated-bench-harness`

### Step 1: `benchmark_c_vs_x86.py` のアーキテクチャ刷新
1. **`runtime.c` 参照の撤廃**:
   - `RUNTIME_C = os.path.join(ULISP_DIR, "runtime.c")` を削除。
   - `compile_c()` を以下のように更新:
     ```python
     run_cmd(["gcc", "-Wall", "-Wextra", "-Werror", "-Wno-unused-label", "-O2", c_path, "-o", bin_path])
     ```
2. **Pure C Baseline (`compile_pure_c`) の追加**:
   - Scheme の各ワークロードに対応する純粋な C99 コード（GCC -O2 最適化）をオンザフライ生成・コンパイル。
   - ULisp x86-64 Native、ULisp C Backend、Pure C Baseline の 3 者比較を可能にする。
3. **代表的 6 大ワークロードの定義**:
   - **W1: Fibonacci (`fib 30`)**: 再帰分岐・コールフレームオーバーヘッド・整数演算
     - Scheme: `(letrec ((fib (lambda (n) (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2))))))) (fib 30))`
     - Expected: `832040`
   - **W2: Tail-Recursive Loop (`loop 10M`)**: TCO（末尾呼出最適化）、レジスタピン留め・ループ分岐速度
     - Scheme: `(letrec ((loop (lambda (i acc) (if (= i 10000000) acc (loop (+ i 1) (+ acc i)))))) (loop 0 0))`
     - Expected: `49999995000000`
   - **W3: Ackermann (`ack 3 7`)**: 深いスタックネスト・多重再帰関数呼出し
     - Scheme: `(letrec ((ack (lambda (m n) (if (= m 0) (+ n 1) (if (= n 0) (ack (- m 1) 1) (ack (- m 1) (ack m (- n 1)))))))) (ack 3 7))`
     - Expected: `1021`
   - **W4: Higher-Order Closure (`closure 1M`)**: ファーストクラスクロージャ呼出し・環境参照
     - Scheme: `(letrec ((iter (lambda (n f acc) (if (= n 0) acc (iter (- n 1) f (f acc)))))) (iter 1000000 (lambda (x) (+ x 1)) 0))`
     - Expected: `1000000`
   - **W5: List Allocation & Traverse (`list 100k`)**: バンプアロケータ・ヒープ走査・ペアリスト走査
     - Scheme: `(letrec ((iota (lambda (n acc) (if (= n 0) acc (iota (- n 1) (cons n acc))))) (sum (lambda (lst acc) (if (pair? lst) (sum (cdr lst) (+ acc (car lst))) acc)))) (sum (iota 100000 '()) 0))`
     - Expected: `5000050000`
   - **W6: Vector Indexing & Traverse (`vector 100k`)**: ベクタインデックス参照・メモリ走査
     - Scheme: `(letrec ((v (make-vector 100000 42)) (loop (lambda (i acc) (if (= i 100000) acc (loop (+ i 1) (+ acc (vector-ref v i))))))) (loop 0 0))`
     - Expected: `4200000`
4. **精密計測と統計処理**:
   - `measure_execution(bin_path, iterations, warmup=3)`:
     - 計測前にウォームアップを 3 回実行し、CPU キャッシュミスや CPU クロック周波数の変動を抑制。
     - 本試行 10 回で `mean`, `min`, `max`, `stdev` をナノ秒精度（`time.perf_counter_ns`）で算出。
   - 出力の一致検証（`assert x86_out == c_out == pure_c_out`）により、アルゴリズムの等価性を機械的に保証。
5. **レポート出力**:
   - コンソールへのリッチな ANSI/Markdown サマリーテーブル表示。
   - `build/bench_results.md`: GitHub GFM 表形式（Workload, x86-64, ULisp C, Pure C, 比率, バイナリサイズ）。
   - `build/bench_results.json`: CI 連携・トレンド解析用の構造化データ。

### Step 2: 関連ベンチマークスクリプトの修正
1. `run_bench_c_vs_x86.sh`:
   - `runtime.c` をコンパイルコマンドから削除し、スタンドアロンビルドに変更。
2. `run_bench_multi_scheme.py`:
   - `RUNTIME_C` の参照を削除し、ULisp C のコンパイルコマンドを更新。
3. `benchmark_stage2_vs_ulisp_jit.py`:
   - `RUNTIME_C` の参照を削除し、`gcc -nostdlib -static` で AOT 実行可能バイナリを生成するよう修正。

### Step 3: Makefile ターゲット `make bench` の統合
1. `ulisp/Makefile` の `bench` ターゲットを整備:
   ```makefile
   bench: compiler
   	@mkdir -p build
   	$(PYTHON) benchmarks/benchmark_c_vs_x86.py
   ```
2. 既存の `bench_stage2_vs_jit` ターゲットを新設または `benchmark_stage2_vs_ulisp_jit.py` も正常動作するよう修復。

### Step 4: ドキュメント（README.md）の最新化
1. `ulisp/benchmarks/README.md` の AOT コンパイル手順・C バックエンドコンパイル手順から `runtime.c` を削除。
2. `gcc -nostdlib -static` による Freestanding x86-64 コンパイル、および `gcc -O2` による Standalone C コンパイルの手順を明記。
3. `make bench` の実行方法と出力アーティファクトの説明を追加。

---

## 5. セキュリティ・品質保証観点 / Security & QA Considerations
- **サブプロセスの安全性**:
  - `subprocess.run(..., shell=False)` を徹底し、シェルインジェクションの脆弱性を排除。
  - 出力パース時のバッファオーバーランやハング防止のため、適切なタイムアウトを設定。
- **再現性と公平性**:
  - `ULISP_QUIET=1` を指定し、ランタイムのデバッグ出力オーバーヘッドを排除。
  - プロセス起動時間ではなく実実行時間を比較可能にするため、各ワークロードの計算量を十分な実行時間（5ms〜100ms）に設定。
- **環境差異の吸収**:
  - Python 仮想環境（`.venv/bin/python`）の有無を自動判定し、システム Python との互換性を確保。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `python3 ulisp/benchmarks/benchmark_c_vs_x86.py` がエラーなく 100% 完遂すること。
- [x] `ulisp/benchmarks/run_bench_c_vs_x86.sh`, `run_bench_multi_scheme.py`, `benchmark_stage2_vs_ulisp_jit.py` の全スクリプトで `runtime.c: No such file or directory` エラーが 0 件であること。
- [x] 6 大ワークロード（Fibonacci, Loop 10M, Ackermann, Closure, List Alloc, Vector Traverse）すべてにおいて、x86-64 ネイティブ、ULisp C、Pure C の実行結果（標準出力）が完全一致すること。
- [x] `make -C ulisp bench` が単一コマンドで正常実行され、コンソール表示および `ulisp/build/bench_results.md` / `build/bench_results.json` に集計結果が出力されること。
- [x] `ulisp/benchmarks/README.md` の記述が Freestanding / Standalone C アーキテクチャに更新されていること。
- [x] リポジトリ全体の品質ゲート（`make py_compile`, `make static_analysis`）が PASS すること。

