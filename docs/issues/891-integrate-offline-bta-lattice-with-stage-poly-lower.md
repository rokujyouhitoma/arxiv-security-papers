---
ID: 891
種別: Feature
優先度: Medium
ステータス: Open (In Progress)
---

# [FEAT] オフライン BTA 4値束注釈とオンライン部分評価のハイブリッド推論フィードバック統合 (ID: 891)

## 1. 概要 / Summary
DSN-33-03 §2.5（ハイブリッド部分評価モデル）および §8.1 (Phase P5) に基づき、Issue #874 で実装された 4値束縛時間束（Static, PSDS, Dynamic, Bot）の型推論パス（`bta-infer`）が生成した束縛時間アノテーションを、オンライン部分評価器 `stage-poly-lower` が先回り参照して投機的簡約・動的ディスパッチ消去・ループアンローリングをより強力にドライブするフィードバック統合を実装する。

---

## 2. トレーサビリティ / Traceability
- 関連個別仕様書:
  - [DSN-33-03 §2.5, §4.1](../designs/DSN-33-03-ulisp_stage_polymorphic_metacompiler_and_futamura_projection_architecture.md#25-ハイブリッド部分評価offline-bta--online-psds-簡約の数理モデル)
- 関連 Issue: #874 (4-Valued BTA Lattice), #876 (CSP Boundary Validator), #879 (Stage-Poly-Lower), #881 (Stage Oracle)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/compiler/dataflow.scm](../../ulisp/compiler/dataflow.scm)
- [x] [ulisp/compiler/eval_in_language.scm](../../ulisp/compiler/eval_in_language.scm)
- [x] [ulisp/tests/test_bta_lattice.scm](../../ulisp/tests/test_bta_lattice.scm)
- [x] [ulisp/tests/test_stage_oracle.scm](../../ulisp/tests/test_stage_oracle.scm)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/891-integrate-offline-bta-lattice-with-stage-poly-lower`

1. **BTA 束縛時間環境からステージ多相初期環境への変換**:
   - `ulisp/compiler/eval_in_language.scm` に、`bta-infer-expr` の解析結果から静的変数の組 `((var . static) ...)` を抽出し、`stage-poly-lower` の第 2 引数 `static-env` へ供給するヘルパー `bta-extract-static-env` を実装。
2. **PSDS 投機的アンローリングと動的分岐ガード**:
   - `@PSDS` と判定されたコンテナ（リストや環境ペア）について、不変部分を `Now` 側で展開し、可変または動的要素のみを `Later` 側へ残余化するハイブリッド簡約ルールを `eval-in-stage` 内に接続。
3. **3重差分オラクルによる等価性検証**:
   - `test_stage_oracle.scm` にて、BTA フィードバック有効時と無効時で意味論的実行結果（Now 評価 vs Residual ANF 評価）が 100% 一致することをメタモルフィックテストでアサート。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] BTA の 4値束推論結果が `stage-poly-lower` の部分評価コアループに正しく反映され、静的分岐消去が行われること。
- [ ] BTA 注釈による投機的展開を行っても意味論が崩れず、3重差分オラクル検証が 100% PASS すること。
- [ ] `make test_bta_lattice` および `make test_stage_oracle` が 100% PASS すること。
