---
ID: 903
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] Implement Performance Regression Detector and Automated Markdown Reporting (ID: 903)

## 1. 概要 / Summary
[[DSN-33-06]](../designs/DSN-33-06-ulisp_ilisp_aot_jit_continuous_benchmarking_framework.md) 第 4 章に基づき、過去のベースライン測定値と新規測定値を統計的に比較して 5% 以上の性能退行（Regression）を自動検知する判定器、およびトレンド可視化表を含む日本語エグゼクティブサマリー `outputs/benchmarks/benchmark_report.md` を自動生成するパイプラインを実装する。

---

## 2. トレーサビリティ / Traceability
- 関連設計書:
  - [[DSN-33-06] ILisp・ULisp AOT・ULisp JIT 3種実行系 継続的性能評価基盤 設計仕様書 (第4章)](../designs/DSN-33-06-ulisp_ilisp_aot_jit_continuous_benchmarking_framework.md)
  - [[DSN-10] 統合オブザーバビリティ ＆ 品質評価フレームワーク設計書](../designs/DSN-10-observability_and_eval_framework.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [tools/regression_detector.py](../../tools/regression_detector.py)
- [ ] [tools/report_benchmarks.py](../../tools/report_benchmarks.py)
- [ ] [outputs/benchmarks/benchmark_report.md](../../outputs/benchmarks/benchmark_report.md)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/903-implement-performance-regression-detector-and-automated-markdown-reporting`

1. `tools/regression_detector.py` において、ウェルチの t 検定（Welch's t-test）を用いた統計的有意差判定および 5% 性能悪化閾値チェックを実装。
2. `tools/report_benchmarks.py` を作成し、3 種実行系のスループット比率（Speedup vs ILisp）やメモリ消費量を構造化 Markdown 表形式でレンダリング。
3. CI/CD パイプライン連携用の終了コード（退行検知時に非ゼロ終了）および GitHub Actions 用サマリー連携を実装。
4. 単体テスト `tests/test_benchmark_reporter.py` を作成し、レポート生成および退行検知ロジックを検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 性能退行検知時に適切なアラートが出力されること。
- [ ] `outputs/benchmarks/benchmark_report.md` が完全な日本語マークダウン表形式で自動出力されること。
- [ ] `pytest tests/test_benchmark_reporter.py` が PASS すること。
- [ ] `make py_compile && make static_analysis` が PASS すること。
