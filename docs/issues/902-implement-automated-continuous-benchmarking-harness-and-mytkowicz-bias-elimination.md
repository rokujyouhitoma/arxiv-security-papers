---
ID: 902
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] Implement Automated Continuous Benchmarking Harness and Mytkowicz Bias Elimination (ID: 902)

## 1. 概要 / Summary
[[DSN-33-06]](../designs/DSN-33-06-ulisp_ilisp_aot_jit_continuous_benchmarking_framework.md) 第 2 章・第 6 章に基づき、ILisp、ULisp AOT、および ULisp JIT の 3 種実行系を同一環境で評価する自動ベンチマークハーネス、環境変数・スタック配置による測定バイアス排除（Mytkowicz 手法）、および `outputs/benchmarks/` への JSON 履歴自動蓄積パイプラインを実装する。

---

## 2. トレーサビリティ / Traceability
- 関連設計書:
  - [[DSN-33-06] ILisp・ULisp AOT・ULisp JIT 3種実行系 継続的性能評価基盤 設計仕様書 (第2章・第6章)](../designs/DSN-33-06-ulisp_ilisp_aot_jit_continuous_benchmarking_framework.md)
  - [[DSN-33] ULISP 包括設計仕様書](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [tools/benchmark_ilisp_ulisp.py](../../tools/benchmark_ilisp_ulisp.py)
- [ ] [ulisp/benchmarks/run_benchmarks.scm](../../ulisp/benchmarks/run_benchmarks.scm)
- [ ] [outputs/benchmarks/latest.json](../../outputs/benchmarks/latest.json)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/902-implement-automated-continuous-benchmarking-harness-and-mytkowicz-bias-elimination`

1. 5 つの標準ワークロード（`fib_loop`, `fact_loop`, `sum_loop`, `poly_loop`, `tri_loop`）に対する反復実行ハーネスを構築。
2. 環境変数パディングおよびスタックオフセットのランダムシフトを導入し、メモリアライメントによる測定ノイズを排除。
3. 実行結果（Wall Clock Time, CPU Time, Max RSS, GC 発生回数）を構造化 JSON として `outputs/benchmarks/history/` に自動保存。
4. 単体・実行テストを作成し、3 種実行系のメトリクスが再現性高く収集されることを検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 3 種実行系のベンチマークが単一コマンド `make benchmark` で自動実行されること。
- [ ] Mytkowicz 補正により、測定結果の分散（Variance）が許容閾値内に収まること。
- [ ] `outputs/benchmarks/latest.json` が正常に出力・更新されること。
- [ ] `make py_compile && make static_analysis` が PASS すること。
