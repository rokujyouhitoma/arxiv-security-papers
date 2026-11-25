---
ID: 971
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] 汎用インライン展開 ＆ β-簡約パスの導入およびフロントエンド最適化（CP0/LVN/DCE）の Fixpoint 反復化 (ID: 971)

## 1. 概要 / Summary

現在 `050_cp0.scm` の `map`/`for-each`/`call-with-values` と Synapse 専用パスに限られているインライン展開を拡張し、ノード数コストモデル・単一呼出強制インライン・再帰 1 段展開を備えた汎用インライナ ＆ β-簡約パスを導入する。
さらに `pass_manager.scm` の `run-pass-fixpoint` を活用し、`(inline -> cp0 -> lvn/dce)` を有界固定点反復することで後続の定数伝播・アンボックス・エスケープ解析の機会を最大化する。

---

## 2. トレーサビリティ / Traceability

- 関連資料:
  - [Issue #958](958-eliminate-unused-prologue-spills-and-inline-small-accessors.md)
  - [Issue #840](closed/840-automate-analysis-cache-invalidation-and-recomputation-in-nanopass.md)
  - [BASELINE.md](../../ulisp/benchmarks/BASELINE.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [050_cp0.scm](../../ulisp/frontend/050_cp0.scm)
- [ ] [060_lvn.scm](../../ulisp/frontend/060_lvn.scm)
- [ ] [frontend_lang.scm](../../ulisp/frontend/frontend_lang.scm)
- [ ] [pass_manager.scm](../../ulisp/compiler/pass_manager.scm)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/971-general-inliner-and-frontend-fixpoint`

1. 呼び出し回数（use-count）と AST サイズに基づくコストモデルを備えた汎用インライナ ＆ α リネーム付き β-簡約パスを実装する。
2. `*aot-native-pipeline-passes*` に `run-pass-fixpoint` ベースの `(inline -> cp0 -> lvn)` 有界固定点ループを組み込む。
3. 詳細手順は `polish-issue` にて精緻化する。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] 小規模関数および単一呼出ローカル関数が安全にインライン展開・β-簡約され、コード膨張が閾値内に抑えられること
- [ ] 固定点反復後も自己コンパイル不動点および全回帰テストが PASS すること
- [ ] `make format` / `make static_analysis` / `make test` および `verify-quality-gates` が全 PASS すること
