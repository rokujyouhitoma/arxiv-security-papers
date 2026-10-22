---
ID: 560
種別: Feature
優先度: Medium
ステータス: Closed
---

# [FEAT] R7RS 多値定義構文 (define-values) のマクロ脱糖実装 (ID: 560)

## 1. 概要 / Summary
R7RS 5.3.3 (Multiple-value definitions) に規定されている `define-values` 構文を ULisp コンパイラ脱糖パス (`ulisp/passes/030_desugar.scm`) およびトップレベル解析器 (`ulisp/passes/025_top_level.scm`) に実装した。
ULisp の既存の `call-with-values`, `values`, `let-values` によるゼロヒープ複数値返却機構と結合し、トップレベル定義および局所内部定義の両方において多値返却関数の結果を一括して束縛・定義可能にした。

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
- [x] [ulisp/passes/010_library.scm](../../ulisp/passes/010_library.scm) (モジュール名前空間・エクスポート対応)
- [x] [ulisp/passes/020_macro_expander.scm](../../ulisp/passes/020_macro_expander.scm) (コア予約語登録)
- [x] [ulisp/passes/025_top_level.scm](../../ulisp/passes/025_top_level.scm) (トップレベル多値定義展開)
- [x] [ulisp/passes/028_desugar_bindings.scm](../../ulisp/passes/028_desugar_bindings.scm) (複数本体式正規化)
- [x] [ulisp/passes/029_desugar_dynamic.scm](../../ulisp/passes/029_desugar_dynamic.scm) (局所内部多値定義脱糖)
- [x] [ulisp/passes/030_desugar.scm](../../ulisp/passes/030_desugar.scm) (脱糖パス統合)
- [x] [ulisp/compiler.scm](../../ulisp/compiler.scm) (自己ホストコンパイラ結合)
- [x] [ulisp/tests/passes/](../../ulisp/tests/passes/) (Pass 025/029/030 単体テスト追加)
- [x] [ulisp/tests/test_values.scm](../../ulisp/tests/test_values.scm) (多値定義E2Eテスト)
- [x] [ulisp/tests/test_stdlib_r7rs.scm](../../ulisp/tests/test_stdlib_r7rs.scm) (R7RS仕様適合テスト)
- [x] [ulisp/docs/r7rs_specification_compliance.md](../../ulisp/docs/r7rs_specification_compliance.md) (適合状況更新)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/560-implement-r7rs-define-values-syntax`

1. 構文脱糖の設計:
   - トップレベルでの `(define-values formals expr)` の展開:
     Pass 025 (`expand-define-values`) にて、テンポラリ変数 `tmp` に `call-with-values` でベクタ集約を行い、各変数 `v_i` を `vector-ref` で順次 `define` するフラットな定義群へ展開。
   - 内部定義での展開:
     Pass 029/030 にて、`(begin (define-values formals expr) . rest)` を `(let-values ((formals expr)) . rest)` へ脱糖。本体が単一式の場合は `call-with-values` へ変換。
2. ライブラリ名前空間およびマクロ展開器の対応:
   - Pass 010 において `extract-defined-names-in-body` および `alpha-rename-expr` で `define-values` の定義変数群を追跡・修飾。
   - Pass 020 において `core-form-or-primitive?` に `define-values` を登録。
3. テストの作成・実行:
   - 0値、1値、2値、3値のトップレベル定義テスト。
   - 手続き内、let内、および連続内部定義テスト。
4. 全体テストの実行・パス確認 (`./test.sh`, `./test_c.sh`)。
5. 3段階セルフホスティングブートストラップによる固定点収束とシードバイナリ更新。
6. `ulisp/docs/r7rs_specification_compliance.md` の更新。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `define-values` 構文が正常に脱糖・コンパイルされ、指定変数に多値が束縛されること。
- [x] 単体テストにおいて多値定義と値の整合性が確認されること。
- [x] `./test.sh` および `./test_c.sh` がエラーなく 100% PASS すること。
- [x] `ulisp/docs/r7rs_specification_compliance.md` の該当項目が更新されていること。
