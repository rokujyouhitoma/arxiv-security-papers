---
ID: 620
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] ベンチマークスイート（benchmark_c_vs_x86）の修復・Freestanding対応および make bench 自動計測ハーネスの確立 (ID: 620)

## 1. 概要 / Summary
現在 ULisp の性能測定スクリプト [ulisp/benchmarks/benchmark_c_vs_x86.py](../../ulisp/benchmarks/benchmark_c_vs_x86.py) は、以前のアーキテクチャで存在した `runtime.c` を参照しているため、実行時に `cc1: fatal error: runtime.c: No such file or directory` で異常終了する状態となっている。また、測定環境や試行回数、ウォームアップ、統計値（平均・標準偏差・最小値）の集計・レポート出力機能が統一されていない。

本 Issue では、最適化施策を着手する前の大前提として、現在の Freestanding ネイティブバックエンド（Pass 142）に対応したベンチマークスイートの修復を行い、純粋なスタンドアロン x86-64 バイナリと GCC（-O2）同等 C コードを公平かつ再現可能に比較できる自動計測ハーネス（`make bench`）を確立する。

---

## 2. トレーサビリティ / Traceability
- **正典仕様書**:
  - [DSN-33 (ULisp 包括設計仕様書)](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md) (第 3 章、第 10 章)
  - [ULisp ベンチマークレポート](../../ulisp/benchmarks/README.md)
- **関連 Issue**:
  - Issue 512: AOT vs JIT ベンチマーク評価基盤の導入
  - Issue 615: ビルドパイプラインからの GCC 呼出し排除と GNU as / ld 直接駆動への移行
  - Issue 618: S-RTyper（Pass 090）および LIR / バックエンドにおける関数間アンボックス特化とタグオーバーヘッド撲滅
  - Issue 621: コンパイラ Nanopass 実行時間・メモリ消費プロファイラ（--time-passes）の実装
  - Issue 622: 実行時 GC 統計プロファイルおよび Linux perf ハードウェアカウンタ連携基盤の実装
  - Issue 623: ULisp 正典性能ベースライン測定レポート（BASELINE.md）の策定

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/benchmarks/benchmark_c_vs_x86.py](../../ulisp/benchmarks/benchmark_c_vs_x86.py) (存在しない `runtime.c` 依存の除去、C バックエンド比較コードの更新)
- [ ] [ulisp/benchmarks/run_bench_multi_scheme.py](../../ulisp/benchmarks/run_bench_multi_scheme.py) (Chez / Guile / Gosh / ULisp 多重比較スクリプトの修復)
- [ ] [ulisp/Makefile](../../ulisp/Makefile) (`bench` ターゲットの更新および自動集計ワークフロー統合)
- [ ] [ulisp/benchmarks/README.md](../../ulisp/benchmarks/README.md) (ベンチマーク実行手順の最新化)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/620-repair-benchmark-suite-and-establish-automated-bench-harness`

1. **`benchmark_c_vs_x86.py` の修正**:
   - 存在しない `runtime.c` 依存を除去。C 言語との比較は、同等のアルゴリズムを持つ純粋な C ソースコードをオンザフライ生成し、`gcc -O2` でコンパイルして計測。
   - ネイティブ x86-64 側は、`compiler.scm` 経由で生成されたスタンドアロンバイナリ（libc 依存ゼロ）を実行。
2. **代表的 6 大ワークロードの標準化**:
   - Fibonacci (fib 35): 再帰・スタック・整数演算
   - Tail-Recursive Loop (10M): ループ内レジスタ割り当て・ジャンプ
   - Ackermann (ack 3 8): 深い再帰・関数呼出しオーバーヘッド
   - Higher-Order Iter (1M): クロージャ・間接呼出し
   - List Alloc & Sum (100k): ヒープ確保・GC 負荷
   - Vector / String Traverse (1M): 配列走査・アドレッシング
3. **統計値集計と Markdown レポート出力**:
   - ウォームアップ 3 回 + 本試行 10 回の平均・最小・最大・標準偏差を算出。
   - 実行結果を Markdown 表形式および JSON で `build/bench_results.md` / `json` に出力。
4. **Makefile ターゲットの整備**:
   - `make bench` で一発実行可能にする。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `make bench` がエラーなく 100% 完遂し、コンソールおよび `build/bench_results.md` に集計結果が出力されること。
- [ ] 6 大ワークロードすべてにおいて、x86-64 ネイティブと C (-O2) の双方の実行時間・バイナリサイズが正常に測定できること。
- [ ] 存在しないファイルへの参照エラーが完全に解消されていること。
