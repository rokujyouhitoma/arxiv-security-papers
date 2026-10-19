---
ID: 574
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] 構文脱糖パス (030_desugar.scm) の構文別ナノパス分割（条件分岐・束縛・多値・動的環境） (ID: 574)

## 1. 概要 / Summary
現在 `ulisp/passes/030_desugar.scm` は 250 行 (23KB) の中で、条件分岐（`cond`, `case`, `and`, `or`）、局所束縛（`let*`, `named-let`）、多値受取（`let-values`, `let*-values`）、動的パラメータ（`parameterize`）、例外保護（`guard`）、および各種複合リテラル生成子（`list`, `vector`, `bytevector`）の脱糖を単一の走査関数 `desugar-all` で一括して行っている。
本 Issue では、各構文糖衣ごとに独立した正規化ステップ（Nanopass）として分割し、AST 文法の中間不変条件を厳密化するとともに、各構文脱糖処理の単体テストを独立して実施可能にする。

---

## 2. トレーサビリティ / Traceability
- Nanopass Framework 原則
- DSN-33 コンパイラアーキテクチャ仕様
- R7RS-small (Section 4.2 Derived expression types)
- 関連資料: [ulisp/passes/030_desugar.scm](../../ulisp/passes/030_desugar.scm)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/passes/030_desugar.scm](../../ulisp/passes/030_desugar.scm) (分割・リファクタリング)
- [ ] [ulisp/passes/031_desugar_conditionals.scm](../../ulisp/passes/031_desugar_conditionals.scm) (`cond`, `case`, `and`, `or`)
- [ ] [ulisp/passes/032_desugar_bindings.scm](../../ulisp/passes/032_desugar_bindings.scm) (`let*`, `named-let`)
- [ ] [ulisp/passes/033_desugar_values.scm](../../ulisp/passes/033_desugar_values.scm) (`let-values`, `let*-values`)
- [ ] [ulisp/passes/034_desugar_dynamic.scm](../../ulisp/passes/034_desugar_dynamic.scm) (`parameterize`, `guard`)
- [ ] [ulisp/passes/035_desugar_constructors.scm](../../ulisp/passes/035_desugar_constructors.scm) (`list`, `vector`, `bytevector` 等)
- [ ] [ulisp/tests/passes/](../../ulisp/tests/passes/) (各構文脱糖パス単体テスト)
- [ ] [ulisp/Makefile](../../ulisp/Makefile) (`PASSES_LIB` リスト更新)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/574-nanopass-decomposition-of-desugar-pass-030`

1. 構文脱糖の順序関係（例: `case` は `cond` に落ち、`cond` は `if` に落ちる、など）の依存関係を整理
2. 各構文脱糖パスを個別の Nanopass として独立モジュール化
3. 各モジュールに対応するテストを `ulisp/tests/passes/` に追加
4. パイプライン全体での結合テストおよび既存テストスイートの全件パスを確認

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `030_desugar.scm` の各構文脱糖処理が独立したパスに分割されていること
- [ ] 各パスに対して単体テストが整備され、構文変換の不変条件が検証されていること
- [ ] `make test` および全言語機能テストが完全に成功すること
