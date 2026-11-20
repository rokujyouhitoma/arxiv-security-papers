---
ID: 874
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT] 4値束縛時間束（Lattice）モデルに基づく BTA 型推論パスの実装 (ID: 874)

## 1. 概要 / Summary
DSN-33-03 §4.1 および §2.5 に基づき、$\bot \sqsubset \mathbf{Static} \sqsubset \mathbf{PSDS} \sqsubset \mathbf{Dynamic} \sqsubset \top$ の束モデルに従ってプログラム中の全式の束縛時間を推論するオフライン BTA（Binding-Time Analysis）パスを実装する。

---

## 2. トレーサビリティ / Traceability
- 関連資料: [DSN-33-03 §2.5, §4.1](docs/designs/DSN-33-03-ulisp_stage_polymorphic_metacompiler_and_futamura_projection_architecture.md#41-4値束縛時間束latticeモデル)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/compiler/dataflow.scm](ulisp/compiler/dataflow.scm)
- [ ] [ulisp/compiler/nanopass.scm](ulisp/compiler/nanopass.scm)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/874-implement-4-valued-bta-lattice-type-inference-pass`

1. 4値束（Static, PSDS, Dynamic, Bot/Top）の合流（Join: $\sqcup$）演算子を定義。
2. 変数環境 $\Gamma$ における束縛時間伝播と不動点反復ソルバーを実装。
3. 各 AST ノードに束縛時間アノテーションを付与。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 定数式が Static、ペア骨格が PSDS、実行時変数が Dynamic に正しく分類されること。
- [ ] `make py_compile` が PASS すること。
