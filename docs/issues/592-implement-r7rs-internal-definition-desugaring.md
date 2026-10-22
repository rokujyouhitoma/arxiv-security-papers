---
ID: 592
種別: Bug
優先度: High
ステータス: Open (New)
---

# [BUG] 手続き本体および内部定義 (Internal Definitions) の脱糖未実装による未束縛変数例外 (ID: 592)

## 1. 概要 / Summary
R7RS §5.3.2 (Internal definitions) において規定されている、手続き本体（`lambda` や `define (<var> . <formals>)`）および局所構文（`let` 等）の `<body>` 先頭に配置される内部定義 `(define <var> <expr>)` や `(define (<name> . <params>) <body>)` が、ULisp コンパイラの脱糖パス（Pass 028/029/030）において `letrec*` / `let` 構造へ脱糖されず素通りするため、後続の式から参照された際に未束縛変数例外（`Unbound variable in LIR: <var>`）が発生する。

Issue #560 にて多値定義構文 `define-values` の内部定義脱糖（`(begin (define-values ...) . rest)` -> `let-values`）は実装されたが、通常の `(define ...)` 形式の内部定義脱糖ルールが未実装であるため、これを改修・整合化する。

### 再現手順 / Steps to Reproduce
1. 以下の内部定義を含む Scheme コードを ULisp コンパイラに入力・実行する:
   ```bash
   ./bin/ulisp-boot <<< "(define (foo) (define x 10) (define y 20) (+ x y)) (foo)"
   ```
2. 以下の実行時エラー（未束縛例外）が発生してコンパイルに失敗する:
   ```
   *** ERROR: unhandled exception: (#<symbol> "Unbound variable in LIR: x" #<symbol>)
   ```

### 再現環境 / Environment
- OS / Env: Linux (Ubuntu 24.04 x86_64)
- Compiler: ULisp AOT Compiler (`compiler.scm` / `bin/ulisp-boot`)
- Related Specification: R7RS-small Section 5.3.2 (Internal definitions)

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/passes/028_desugar_bindings.scm](../../ulisp/passes/028_desugar_bindings.scm) (局所束縛脱糖ルール)
- [ ] [ulisp/passes/029_desugar_dynamic.scm](../../ulisp/passes/029_desugar_dynamic.scm) (内部定義・複数本体式の正規化)
- [ ] [ulisp/passes/030_desugar.scm](../../ulisp/passes/030_desugar.scm) (全体脱糖パスへの統合)
- [ ] [ulisp/compiler.scm](../../ulisp/compiler.scm) (自己ホストコンパイラ)
- [ ] [ulisp/tests/passes/test_028_desugar_bindings.scm](../../ulisp/tests/passes/test_028_desugar_bindings.scm) (単体テスト)
- [ ] [ulisp/tests/passes/test_030_desugar.scm](../../ulisp/tests/passes/test_030_desugar.scm) (単体テスト)
- [ ] [ulisp/tests/test_stdlib_r7rs.scm](../../ulisp/tests/test_stdlib_r7rs.scm) (R7RS E2Eテスト)
- [ ] [ulisp/docs/r7rs_specification_compliance.md](../../ulisp/docs/r7rs_specification_compliance.md) (仕様適合状況更新)

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
- **原因 1 (Pass 025 のスコープ)**:
  Pass 025 (`rewrite-top-level`) は最上位の式リストのみを巡回し、トップレベルの `(define ...)` のみを `%program` の `unique-defs`（グローバルシンボル領域）へ巻き上げている。
- **原因 2 (内部定義脱糖の欠如)**:
  `lambda` の本体式などに現れる内部 `(define ...)` は Pass 025 の対象外であり、そのまま `(begin (define x 10) ...)` または連続した本体式として Pass 028/030 に渡される。
- **原因 3 (Pass 028/030 の脱糖漏れ)**:
  Pass 028/030 には内部 `define-values` に対する脱糖ルールはあるものの、通常の `(define <var> <expr>)` や `(define (<name> . <params>) ...)` を `let` や `letrec` へ巻き直すルールが存在しなかったため、ローカル変数環境へ登録されずに LIR 生成へ到達し未束縛例外となっていた。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**:
  内部定義の代わりに `let`、`let*`、または `define-values`（例: `(define-values (x) 10)`）を明示的に使用する。
* **恒久対策 (Permanent Fix)**:
  Pass 029 / 030 の脱糖規則に内部 `define`（変数定義および短縮手続き定義）の検出ルールを追加し、`(begin (define ...) . rest)` を `let` / `letrec` 構造へ再帰的に展開する。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `fix/592-internal-definition-desugaring`

1. 内部定義脱糖関数の定義 (`desugar-internal-define`):
   - `(define (<name> . <params>) . <body>)` の場合: `(letrec ((<name> (lambda <params> (make-body-expr <body>)))) (make-body-expr rest))`
   - `(define <name> <val>)` の場合: `(let ((<name> <val>)) (make-body-expr rest))`
2. Pass 029 (`029_desugar_dynamic.scm`) および Pass 030 (`030_desugar.scm`) へのルール組み込み:
   - `((begin (define ,spec . ,rest-def) . ,rest) (Expr (desugar-internal-define (cons 'define (cons spec rest-def)) rest)))`
3. テストの作成・実行:
   - 手続き内の内部変数定義 `(define (foo) (define x 10) (define y 20) (+ x y))`
   - 手続き内の内部関数定義 `(define (outer) (define (inner n) (* n 2)) (inner 21))`
   - 内部定義と式が混在するケースの検証。
4. 3段階セルフホスティングブートストラップによる固定点収束とシードバイナリ更新。
5. `ulisp/docs/r7rs_specification_compliance.md` §5.3.2 を更新。

---

## 6. 完了条件 / Success Criteria (DoD)
- [ ] `./bin/ulisp-boot <<< "(define (foo) (define x 10) (define y 20) (+ x y)) (foo)"` がエラーなく 30 を出力すること。
- [ ] 内部手続き定義 `(define (<name> ...) ...)` が `letrec` 経由で正常にコンパイル・実行できること。
- [ ] `./test.sh` および `./test_c.sh` がエラーなく 100% PASS すること。
- [ ] `ulisp/docs/r7rs_specification_compliance.md` の §5.3.2 が更新されること。
