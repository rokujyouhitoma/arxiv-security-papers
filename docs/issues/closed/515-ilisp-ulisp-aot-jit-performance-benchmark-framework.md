---
ID: 515
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT/ENH] ILisp・ULisp AOT・ULisp JIT 3種実行系性能評価および継続的ベンチマーク基盤の構築 (ID: 515)

## 1. 概要 / Summary

ILisp (Python基盤インタプリタ)、ULisp AOT (x86-64ネイティブAOTコンパイルバイナリ)、ULisp JIT (メタトレーシングJIT動的評価) の3種類の実行系について、多角的な計算負荷ワークロード（再帰、ホットループ、算術演算等）における実行速度・スループット・メモリ消費量を厳密に性能評価する。
さらに、今後のコンパイラ最適化や機能追加に伴う性能退行（パフォーマンスリグレッション）を自動検知し、定期・継続的に性能評価結果を蓄積・可視化できる「継続的ベンチマーク基盤（Continuous Benchmarking Suite）」を構築・統合した。

---

## 2. トレーサビリティ / Traceability

- 関連設計文書:
  - [DSN-31 (ILisp 包括設計仕様書)](../designs/DSN-31-ilisp_kernel_r7rs_infrastructure_lisp_architecture_specification.md)
  - [DSN-33 (ULisp 包括設計仕様書)](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
  - [DSN-35 (3種実行系 継続的性能評価基盤 設計仕様書)](../designs/DSN-35-ilisp_ulisp_aot_jit_continuous_benchmarking_framework.md)
- 関連Issue:
  - [Issue #512 (ULisp AOT and JIT One Binary Integration)](closed/512-integrate-ulisp-aot-and-mlisp-jit-one-binary.md)
  - [Issue #514 (Consolidate ULisp & MLisp into Unified RPython Framework)](closed/514-consolidate-ulisp-and-mlisp-into-unified-rpython-framework.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [tools/benchmark_ilisp_ulisp.py](file:///workspace/arxiv-security-papers/tools/benchmark_ilisp_ulisp.py) (新規: 3種実行系一括ベンチマーク測定エンジン)
- [x] [ulisp/Makefile](file:///workspace/arxiv-security-papers/ulisp/Makefile) (`bench_trio`, `bench_ci` ターゲット追加)
- [x] [Makefile](file:///workspace/arxiv-security-papers/Makefile) (`benchmark_trio`, `bench_ci` 統合)
- [x] [tests/test_benchmark_suite.py](file:///workspace/arxiv-security-papers/tests/test_benchmark_suite.py) (新規: ベンチマークハーネス自体の自動テスト)
- [x] [outputs/benchmarks/benchmark_report.md](file:///workspace/arxiv-security-papers/outputs/benchmarks/benchmark_report.md) (新規: 構造化性能評価レポート & Mermaidグラフ)
- [x] [docs/designs/DSN-35-ilisp_ulisp_aot_jit_continuous_benchmarking_framework.md](file:///workspace/arxiv-security-papers/docs/designs/DSN-35-ilisp_ulisp_aot_jit_continuous_benchmarking_framework.md) (新規: 設計仕様書)
- [x] [docs/issues/README.md](file:///workspace/arxiv-security-papers/docs/issues/README.md) (Issue台帳更新)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/515-ilisp-ulisp-aot-jit-benchmark-framework`

1. **ワークロード選定と標準化**:
   - Scheme/Lisp 共通コードとして ILisp, ULisp AOT, ULisp JIT の全ランタイムで構文解析・実行可能な 5 種の代表的ワークロードを定義:
     1. `fib_loop`: 反復フィボナッチ数計算 `(fib 20)`
     2. `fact_loop`: 反復階乗計算 `(fact 12)`
     3. `sum_loop`: ホットループ加算 `(let loop ((i 0) (sum 0)) ... 5,000回)`
     4. `poly_loop`: 多項式計算ループ `(3x^2 + 5x + 7, 1,000回)`
     5. `tri_loop`: 三角数累積和 `(tri 500)`
2. **測定ハーネス (`tools/benchmark_ilisp_ulisp.py`)**:
   - `ILisp`: `python3 -m ilisp -p <file>` によるインタープリタ実行レイテンシ
   - `ULisp AOT`: `ulisp-jit` (`(!compile)`) 経由で生成した ELF ネイティブバイナリの実行レイテンシ
   - `ULisp JIT`: `ulisp-jit` による JIT ループ追跡・動的コンパイル実行レイテンシ
   - 統計指標（Mean, StdDev, Min, Max, Speedup Ratio）を算出
   - JSON 形式（`outputs/benchmarks/latest.json` & `history/`）および Markdown レポート出力
   - リグレッション検知モード（`--compare <base_json> --threshold 2.5`）を実装
3. **継続的評価の統合 (CI & Makefile)**:
   - `make benchmark_trio` / `make -C ulisp bench_trio` で一括実行
   - `make bench_ci` / `make -C ulisp bench_ci` でベースライン比較・回帰検知
   - `tests/test_benchmark_suite.py` で CI テストスイートに組み込み
4. **品質ゲート検証**:
   - `make py_compile`, `flake8`, `pytest` 適合確認

---

## 5. 完了条件 / Success Criteria (DoD)

- [x] ILisp、ULisp AOT、ULisp JIT の3者間で共通 5 ワークロードの実行性能（ms）が正常に測定できること
- [x] 各ワークロードの実行結果（戻り値）が 3 種類の実行系すべてで完全に一致すること（健全性保証: 🟢 100% PASS）
- [x] 性能評価結果が構造化 JSON (`outputs/benchmarks/latest.json`) および Markdown レポート (`outputs/benchmarks/benchmark_report.md`) に出力されること
- [x] 過去結果との比較およびリグレッション検知機能が動作すること (`make bench_ci`)
- [x] `make benchmark_trio` / `pytest tests/test_benchmark_suite.py` が PASS すること
- [x] すべての品質ゲートを通過すること

