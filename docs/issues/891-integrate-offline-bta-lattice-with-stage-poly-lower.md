---
ID: 891
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT] オフライン BTA 4値束注釈とオンライン部分評価のハイブリッド推論フィードバック統合 (ID: 891)

## 1. 概要 / Summary
DSN-33-03 §2.5（ハイブリッド部分評価モデル）および §8.1 (Phase P5) に基づき、Issue #874 で実装された 4値束縛時間束（Static, PSDS, Dynamic, Bot）の型推論パス（`bta-infer`）が生成した束縛時間アノテーションを、オンライン部分評価器 `stage-poly-lower` が先回り参照して投機的簡約・動的ディスパッチ消去・ループアンローリングをより強力にドライブするフィードバック統合を実装する。

---

## 2. トレーサビリティ / Traceability
- 関連個別仕様書:
  - [DSN-33-03 §2.5, §4.1](../designs/DSN-33-03-ulisp_stage_polymorphic_metacompiler_and_futamura_projection_architecture.md#25-ハイブリッド部分評価offline-bta--online-psds-簡約の数理モデル)
- 関連 Issue: #874 (4-Valued BTA Lattice), #876 (CSP Boundary Validator), #879 (Stage-Poly-Lower)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/compiler/dataflow.scm](../../ulisp/compiler/dataflow.scm)
- [ ] [ulisp/compiler/eval_in_language.scm](../../ulisp/compiler/eval_in_language.scm)
- [ ] [ulisp/tests/test_bta_lattice.scm](../../ulisp/tests/test_bta_lattice.scm)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/891-integrate-offline-bta-lattice-with-stage-poly-lower`

1. `bta-infer` の出力アノテーション木を `stage-poly-lower` の初期静的環境（`static-env`）へ自動変換・インポートするブリッジ関数を実装。
2. `@Static` または `@PSDS` と判定された変数を `Now` 辞書評価で優先的にインライン展開。
3. 3重差分テストオラクル（#881）を用いて、ハイブリッド最適化後の意味論が完全一致することを検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] BTA の 4値束推論結果が `stage-poly-lower` の部分評価コアループに正しく反映されること。
- [ ] BTA 注釈による投機的展開を行っても意味論が崩れず、3重差分オラクル検証が 100% PASS すること。
- [ ] `make test_bta_lattice` および `make test_stage_oracle` が 100% PASS すること。
