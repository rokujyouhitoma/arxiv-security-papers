---
ID: 850
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] R7RS case 構文におけるパイプライン句 ((<datum> ...) => <proc>) の脱糖サポート (ID: 850)

## 1. 概要 / Summary
R7RS §4.2.1 仕様において、`case` 条件分岐は標準の `((<datum> ...) <expression> ...)` に加え、パイプライン構文 `((<datum> ...) => <expression>)` をサポートすることが義務付けられている。マッチしたキー評価結果が `<expression>`（1引数手続き）に渡されて評価される。
しかし現状の `ulisp/frontend/027_desugar_conditionals.scm` の `desugar-case` は `else` 句と通常式句しか認識しておらず、`=>` パイプライン句を正しく脱糖できない（リファレンス記載と実コードの乖離）。
本 Issue では、Pass 027 における `case` 脱糖器を拡張し、`=>` パイプライン句を完全サポートする。

---

## 2. トレーサビリティ / Traceability
- 関連仕様:
  - R7RS-small Section 4.2.1 (Conditionals: `case`)
  - [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) §1.1 (4.2.1)
  - [DSN-33 (ULisp 包括設計仕様書)](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/frontend/027_desugar_conditionals.scm](../../ulisp/frontend/027_desugar_conditionals.scm)
- [ ] [ulisp/tests/passes/test_027_desugar_conditionals.scm](../../ulisp/tests/passes/test_027_desugar_conditionals.scm) (新規または拡充)
- [ ] [ulisp/tests/test_stdlib_r7rs.scm](../../ulisp/tests/test_stdlib_r7rs.scm)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/850-implement-r7rs-case-syntax-pipeline-arrow-clause`

1. **`desugar-case` 節解析の拡張 (`ulisp/frontend/027_desugar_conditionals.scm`)**:
   - 各 clause `c` を検査し、`(and (pair? (cdr c)) (eq? (cadr c) '=>))` である場合を識別。
   - 通常のマッチ時: `(list 'if (desugar-case-test k-var (car c)) (list (caddr c) k-var) (loop (cdr cls)))` への脱糖。
   - `(else => <expression>)` が指定された場合: `(list (caddr c) k-var)` への脱糖。
2. **ユニットテストの拡充**:
   - 数値・シンボル・文字のマッチング時に key 値が receiver に渡されることを確認するテストを追加。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `(case 10 ((10 20) => (lambda (x) (* x 2))) (else #f))` が `20` を評価すること。
- [ ] `(case 'foo ((bar) 1) (else => (lambda (x) x)))` が `'foo` を評価すること。
- [ ] 既存の `case` 式脱糖が壊れず後方互換性が保たれていること。
- [ ] テストスイートがすべて PASS すること。
