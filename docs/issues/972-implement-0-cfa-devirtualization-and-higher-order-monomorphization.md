---
ID: 972
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] 全プログラム 0-CFA（制御フロー解析）による間接呼び出し脱仮想化と高階関数単相化・特化パスの導入 (ID: 972)

## 1. 概要 / Summary

`BASELINE.md` で Pure C 比 6.39x と最大ボトルネックとなっている `Higher-Order Closure` ワークロードを解消するため、全プログラム 0-CFA（クロージャフロー解析）により各呼出サイトで取り得る関数集合を静的推論し、単一ターゲットを `%direct-call` へ脱仮想化する。
さらに高階関数や既知型引数に対して専用クローン関数を合成する単相化・特化パスを導入し、クロージャ確保と動的ディスパッチを削減する。

---

## 2. トレーサビリティ / Traceability

- 関連資料:
  - [Issue #971](971-implement-general-inliner-and-frontend-fixpoint-optimization.md)
  - [BASELINE.md](../../ulisp/benchmarks/BASELINE.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [080_annotator.scm](../../ulisp/frontend/080_annotator.scm)
- [ ] [090_rtyper.scm](../../ulisp/frontend/090_rtyper.scm)
- [ ] [110_closure_convert.scm](../../ulisp/frontend/110_closure_convert.scm)
- [ ] [pass_manager.scm](../../ulisp/compiler/pass_manager.scm)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/972-0-cfa-and-monomorphization`

1. `L_anf` 上で制約グラフに基づく全プログラム 0-CFA を実装し、単一関数集合に収束した間接呼出を `%direct-call` へ変換する。
2. 関数引数・定数型を受け取る高階手続きに対して特殊化クローンを生成する単相化パスを実装する（コード膨張ガード付き）。
3. 詳細手順は `polish-issue` にて精緻化する。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] 静的推論可能な高階呼び出しが `%direct-call` へ脱仮想化・特化されること
- [ ] `Higher-Order Closure` 系ベンチマークの実行速度およびヒープ割当量が大幅に改善すること
- [ ] `make format` / `make static_analysis` / `make test` および `verify-quality-gates` が全 PASS すること
