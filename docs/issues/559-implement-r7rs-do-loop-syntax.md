---
ID: 559
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT] R7RS 反復構文 (do) のマクロ脱糖実装 (ID: 559)

## 1. 概要 / Summary
R7RS 4.2.4 (Iteration) に規定されている汎用反復構文 `do` を ULisp コンパイラ脱糖パス (`ulisp/passes/030_desugar.scm`) において名前付き `let` (named let) に脱糖する機能を実装する。
`do` ループ構文は Scheme における古典的かつ強力なループ構文であり、新規の中間表現やランタイム関数を追加することなく、名前付き `let` と条件分岐 `if` / `begin` への純粋な構文変換としてエレガントに実現可能である。

---

## 2. トレーサビリティ / Traceability
- 関連仕様: R7RS-small Section 4.2.4 (Iteration)
  - 構文: `(do ((<variable1> <init1> <step1>) ...) (<test> <expression> ...) <command> ...)`
  - 意味論:
    各 `<variable>` を `<init>` に初期化してループ開始。各反復で `<test>` を評価し、真であれば `<expression> ...` を順に評価して最後の値を返す（なければ未定義値）。
    偽であれば `<command> ...` を副作用評価し、各変数を `<step>`（省略時は元の変数自身）で更新して次反復を実行。
- 関連ドキュメント: [r7rs_specification_compliance.md](../../ulisp/docs/r7rs_specification_compliance.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/passes/030_desugar.scm](../../ulisp/passes/030_desugar.scm) (構文脱糖ハンドラに `do` 追加)
- [ ] [ulisp/tests/](../../ulisp/tests/) (反復ループの単体テスト追加)
- [ ] [ulisp/docs/r7rs_specification_compliance.md](../../ulisp/docs/r7rs_specification_compliance.md) (適合状況更新)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/559-implement-r7rs-do-loop-syntax`

1. 構文脱糖パターンの設計:
   - `(do ((var init step ...) ...) (test res ...) body ...)` を以下のように展開:
     ```scheme
     (let loop ((var init) ...)
       (if test
           (begin #f res ...)
           (begin
             body ...
             (loop (if step-present step var) ...))))
     ```
   - step が省略された変数（`init` のみ指定）の場合は、更新値として変数自身 `var` を渡す。
2. `ulisp/passes/030_desugar.scm` への組込み:
   - `desugar` 関数に `(eq? (car form) 'do)` のケースを追加し、補助関数 `expand-do` で上記 AST に変換。
3. テストの作成:
   - 単純カウンタループ（1 から 10 までの加算）。
   - 複数変数の同時並行更新（フィボナッチ数列計算など）。
   - step 省略変数が混在するループ。
   - ループ本体（command）が空の場合、返却式（res）が複数ある場合の挙動検証。
4. 全体ビルド・テスト (`./test.sh`, `./test_c.sh`) の実行。
5. `ulisp/docs/r7rs_specification_compliance.md` の更新。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] コンパイラが `do` 構文を解釈し、名前付き `let` に正常脱糖してコンパイルできること。
- [ ] カウンタ、フィボナッチ、step 省略等の各種テストケースが PASS すること。
- [ ] `./test.sh` および `./test_c.sh` がエラーなく 100% PASS すること。
- [ ] `ulisp/docs/r7rs_specification_compliance.md` の該当項目が更新されていること。
