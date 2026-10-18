---
ID: 560
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT] R7RS 多値定義構文 (define-values) のマクロ脱糖実装 (ID: 560)

## 1. 概要 / Summary
R7RS 5.3.3 (Multiple-value definitions) に規定されている `define-values` 構文を ULisp コンパイラ脱糖パス (`ulisp/passes/030_desugar.scm`) またはマクロ展開器 (`ulisp/passes/020_macro_expander.scm`) に実装する。
ULisp では既に Issue 538 において `call-with-values`, `values`, `let-values` によるゼロヒープ複数値返却機構が完全実装されているため、`define-values` をこれらの中間表現・脱糖へと結合することで、多値返却関数の結果を一括して束縛・定義可能にする。

---

## 2. トレーサビリティ / Traceability
- 関連仕様: R7RS-small Section 5.3.3 (Multiple-value definitions)
  - 構文: `(define-values (<formals>) <expression>)`
  - 意味論:
    `<expression>` を評価して複数の値を受け取り、`<formals>` の各変数に束縛・定義する。
    トップレベル定義および局所内部定義の両方で使用される。
- 関連ドキュメント: [r7rs_specification_compliance.md](../../ulisp/docs/r7rs_specification_compliance.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/passes/030_desugar.scm](../../ulisp/passes/030_desugar.scm) (または `020_macro_expander.scm`)
- [ ] [ulisp/tests/](../../ulisp/tests/) (多値定義テスト追加)
- [ ] [ulisp/docs/r7rs_specification_compliance.md](../../ulisp/docs/r7rs_specification_compliance.md) (適合状況更新)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/560-implement-r7rs-define-values-syntax`

1. 構文脱糖の設計:
   - トップレベルでの `(define-values (x y z) expr)` の展開:
     テンポラリ変数 `t` を定義し、`call-with-values` でリスト等に集約、あるいは多値結果を保持した上で各変数を `define`。
     例:
     ```scheme
     (define dummy
       (call-with-values (lambda () expr)
         (lambda (vx vy vz)
           (set! x vx)
           (set! y vy)
           (set! z vz))))
     ```
     または各変数を宣言 (`define x #f` ...) してから初期化ブロックを実行。
   - 内部定義での展開:
     内部定義環境においては `let-values` または局所 `call-with-values` への置き換え。
2. コンパイラ脱糖パスへの組込み:
   - `030_desugar.scm` における定義リスト解析処理に `define-values` の処理を追加。
3. テストの作成・実行:
   - 2値・3値返却関数（`values`）からの多値定義。
   - 変数束縛後の計算利用テスト。
4. 全体テストの実行・パス確認 (`./test.sh`, `./test_c.sh`)。
5. `ulisp/docs/r7rs_specification_compliance.md` の更新。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `define-values` 構文が正常に脱糖・コンパイルされ、指定変数に多値が束縛されること。
- [ ] 単体テストにおいて多値定義と値の整合性が確認されること。
- [ ] `./test.sh` および `./test_c.sh` がエラーなく 100% PASS すること。
- [ ] `ulisp/docs/r7rs_specification_compliance.md` の該当項目が更新されていること。
