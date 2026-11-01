---
ID: 650
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] R7RS §4.2.2 厳密な左から右への評価順序を保証する letrec* 構文の実装 (ID: 650)

## 1. 概要 / Summary
R7RS-small §4.2.2 で規定されている `(letrec* (<binding> ...) <body>)` 構文の評価セマンティクスを完全準拠させる。
現状の ULisp では `letrec*` は [Pass 030: `030_desugar.scm`](../../ulisp/frontend/030_desugar.scm) において通常の `letrec` と同等として処理されているが、R7RS 仕様では各束縛の初期化式が厳密に左から右（先頭から末尾）へ逐次評価されることが義務付けられている。内部定義（internal definitions）の標準脱糖先としても不可欠な規約を満たすよう脱糖ルールを修正・強化する。

---

## 2. トレーサビリティ / Traceability
- R7RS-small: Section 4.2.2 (Binding constructs - letrec*)
- 仕様リファレンス: [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) §1.1
- 関連コンパイラパス: [028_desugar_bindings.scm](../../ulisp/frontend/028_desugar_bindings.scm), [030_desugar.scm](../../ulisp/frontend/030_desugar.scm)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/frontend/028_desugar_bindings.scm](../../ulisp/frontend/028_desugar_bindings.scm)
- [ ] [ulisp/frontend/030_desugar.scm](../../ulisp/frontend/030_desugar.scm)
- [ ] [ulisp/docs/ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md)
- [ ] [ulisp/tests/test_letrec_star.scm](../../ulisp/tests/test_letrec_star.scm) (新規テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/650-implement-r7rs-letrec-star-evaluation-order`

1. R7RS 標準マクロ展開規約に沿い、`letrec*` を未初期化変数群の定義と、左から右への逐次代入（`set!`）の列に脱糖する：
   ```scheme
   (let ((var1 <unassigned>) (var2 <unassigned>) ...)
     (set! var1 init1)
     (set! var2 init2)
     ...
     body1 body2 ...)
   ```
2. もしくは、先行する束縛を参照可能な局所環境チェインを構築する。
3. 逐次代入時の副作用や先行参照が意図通り動作することを検証するテストを作成。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `letrec*` において先行する変数の値を後続の初期化式で直接評価・参照できること。
- [ ] 既存の `letrec` テストおよび内部定義（Issue #592）の挙動に退行がないこと。
- [ ] `ref_r7rs_compliance.md` の §4.2.2 `letrec*` のステータスを `◎` に更新すること。

