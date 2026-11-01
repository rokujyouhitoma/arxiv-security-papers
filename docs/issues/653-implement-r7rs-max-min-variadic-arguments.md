---
ID: 653
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] R7RS §6.2.6 max および min 手続きの可変長引数対応 (ID: 653)

## 1. 概要 / Summary
R7RS-small §6.2.6 で規定されている `(max x1 x2 ...)` および `(min x1 x2 ...)` 手続きを、1引数以上（任意個数）の可変長引数で呼び出し可能にする。
現状の ULisp では [compiler/primitives.scm](../../ulisp/compiler/primitives.scm) 等において 2 引数固定プリミティブとして定義されており、3 引数以上の比較呼び出し（例: `(max 1 5 3 9 2)`）や 1 引数呼び出し（例: `(max 42)`）で arity エラーが発生する制限を解消する。

---

## 2. トレーサビリティ / Traceability
- R7RS-small: Section 6.2.6 (Numerical operations - max, min)
- 仕様リファレンス: [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) §1.3 (6.2.6)
- 関連コンパイラパス: [030_desugar.scm](../../ulisp/frontend/030_desugar.scm), [compiler/primitives.scm](../../ulisp/compiler/primitives.scm), [ulisp/lib/math.scm](../../ulisp/lib/math.scm)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/compiler/primitives.scm](../../ulisp/compiler/primitives.scm)
- [ ] [ulisp/frontend/030_desugar.scm](../../ulisp/frontend/030_desugar.scm)
- [ ] [ulisp/lib/math.scm](../../ulisp/lib/math.scm)
- [ ] [ulisp/docs/ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md)
- [ ] [ulisp/tests/test_math.scm](../../ulisp/tests/test_math.scm) (追加テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/653-implement-r7rs-max-min-variadic-arguments`

1. 2引数コアプリミティブ（`%max-2`, `%min-2` または既存の `max`, `min`）を保持しつつ、脱糖パス（Pass 030）またはランタイムライブラリ（`ulisp/lib/math.scm`）において可変長引数をサポートする。
2. 既知の引数列に対してはコンパイル時畳み込みおよび二項比較連鎖へ展開（アロケーションゼロ）。
3. 動的可変引数呼び出し（`(apply max args)` 等）に対しては、`fold` 相当の左畳み込みループで実行する手続きを定義。
4. 0引数呼び出し時の例外（arity error）を適切にハンドリング。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `(max 10)` => `10`、`(max 1 9 4 2 8)` => `9`、`(min 5 2 8 1 9)` => `1` 等がすべて期待通り動作すること。
- [ ] `apply` 経由の可変長呼び出しが正常に動作すること。
- [ ] `ref_r7rs_compliance.md` の §6.2.6 `max`, `min` のステータスを `◎` に更新すること。

