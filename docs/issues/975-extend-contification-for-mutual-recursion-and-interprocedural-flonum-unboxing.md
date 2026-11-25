---
ID: 975
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] 継続化（Contification）の相互再帰・複数束縛 letrec 拡張および Flonum 関数間アンボックス化強化 (ID: 975)

## 1. 概要 / Summary

単一束縛 `letrec`（`(= (length x*) 1)`）に限定されている `100_contify.scm` を Dominator ベースの一般継続化へ拡張し、相互再帰や複数ローカル関数のクロージャ確保・スタックフレーム生成を削減する。
あわせて `080_annotator.scm` / `090_rtyper.scm` の型格子を拡張し、Fixnum だけでなく Flonum（`f64`）の関数間アンボックス化と XMM レジスタ直結演算を強化する。

---

## 2. トレーサビリティ / Traceability

- 関連資料:
  - [BASELINE.md](../../ulisp/benchmarks/BASELINE.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [080_annotator.scm](../../ulisp/frontend/080_annotator.scm)
- [ ] [090_rtyper.scm](../../ulisp/frontend/090_rtyper.scm)
- [ ] [100_contify.scm](../../ulisp/frontend/100_contify.scm)
- [ ] [125_lir_continuation.scm](../../ulisp/lir/125_lir_continuation.scm)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/975-general-contification-and-flonum-unboxing`

1. 共通復帰継続（Dominator）に基づく複数束縛・相互再帰 `letrec` の継続化判定と `%cont-fun` 変換を実装する。
2. `080_annotator.scm` / `090_rtyper.scm` に `flonum` 型および `f64` 関数間アンボックス化呼出規約サポートを追加する。
3. 詳細手順は `polish-issue` にて精緻化する。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] 相互再帰を含む複数束縛 `letrec` が `%cont-fun` へ変換され、クロージャ確保が削減されること
- [ ] 純粋 Flonum 演算ループでボクシングが排除され XMM レジスタ演算が生成されること
- [ ] `make format` / `make static_analysis` / `make test` および `verify-quality-gates` が全 PASS すること
