---
ID: 592
種別: Bug
優先度: High
ステータス: Closed (2026-10-24)
---

# [BUG] 手続き本体および内部定義 (Internal Definitions) の脱糖未実装による未束縛変数例外 (ID: 592)

## 1. 概要 / Summary
R7RS §5.3.2 (Internal definitions) において規定されている、手続き本体（`lambda` や `define (<var> . <formals>)`）および局所構文（`let` 等）の `<body>` 先頭に配置される内部定義 `(define <var> <expr>)` や `(define (<name> . <params>) <body>)` が、ULisp コンパイラの脱糖パス（Pass 028/029/030）において `letrec*` / `let` 構造へ脱糖されず素通りするため、後続の式から参照された際に未束縛変数例外（`Unbound variable in LIR: <var>`）が発生する。

Issue #560 にて多値定義構文 `define-values` の内部定義脱糖（`(begin (define-values ...) . rest)` -> `let-values`）は実装されたが、通常の `(define ...)` 形式の内部変数定義および手続き定義脱糖ルールが脱糖パス（Pass 028/030）に未実装であるため、これを改修・整合化する。

### 再現手順 / Steps to Reproduce
1. 以下の内部定義を含む Scheme コードを ULisp コンパイラに入力・実行する:
   ```bash
   ./bin/ulisp-boot <<< "(define (foo) (define x 10) (define y 20) (+ x y)) (foo)"
   ```
2. 以下の実行時例外（未束縛変数エラー）が発生してコンパイルに失敗する:
   ```
   *** ERROR: unhandled exception: (#<symbol> "Unbound variable in LIR: x" #<symbol>)
   ```

### 再現環境 / Environment
- OS / Env: Linux (Ubuntu 24.04 x86_64)
- Compiler: ULisp AOT Compiler (`compiler.scm` / `bin/ulisp-boot`)
- Related Specification: R7RS-small Section 5.3.2 (Internal definitions) / Section 5.3.1 (Top-level definitions)

---

## 2. トレーサビリティ / Traceability

- **言語仕様基準**:
  - R7RS-small Section 5.3.2 (Internal definitions):
    - `<body>` の先頭（`<definition>* <expression>+`）に置かれる定義は、その `<body>` に閉じた局所定義として機能する。
    - 単一定義、複数連続定義、手続き定義短縮構文、およびスプライシング `begin` 内部の定義が含まれる。
    - 意味論として `letrec*` 構造と等価（手続き群は相互再帰可能、変数は左から右へ逐次束縛）。
  - R7RS-small Section 5.3.1 (Top-level definitions)
  - R7RS-small Section 4.2.2 (Binding constructs: `let`, `letrec`, `letrec*`)
- **アーキテクチャ仕様**:
  - [DSN-33 コンパイラアーキテクチャ仕様書](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
  - [ulisp/docs/pipeline_architecture.md](../../ulisp/docs/pipeline_architecture.md) (Frontend 脱糖パス構成)
  - [ulisp/docs/r7rs_specification_compliance.md](../../ulisp/docs/r7rs_specification_compliance.md) (§5.3.2 適合状況)
- **関連 Issue**:
  - [560-implement-r7rs-define-values-syntax.md](closed/560-implement-r7rs-define-values-syntax.md) (多値定義構文 `define-values` の内部定義脱糖)
  - [548-implement-r7rs-define-library-and-import-syntax.md](closed/548-implement-r7rs-define-library-and-import-syntax.md) (ライブラリ内定義の抽出・名前解決)
  - [570-top-level-definition-lifting.md](closed/570-top-level-definition-lifting.md) (Pass 025: トップレベル定義のホイスティング)
  - [581-nanopass-framework-phase1-core-syntax-desugaring.md](closed/581-nanopass-framework-phase1-core-syntax-desugaring.md) (Pass 030 Nanopass DSL 化)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [ulisp/frontend/028_desugar_bindings.scm](../../ulisp/frontend/028_desugar_bindings.scm) (局所束縛・内部定義脱糖ルール実装: `desugar-internal-define`, `normalize-define-spec`)
- [x] [ulisp/frontend/029_desugar_dynamic.scm](../../ulisp/frontend/029_desugar_dynamic.scm) (動的・多値内部定義脱糖ルール整合化)
- [x] [ulisp/frontend/030_desugar.scm](../../ulisp/frontend/030_desugar.scm) (統合脱糖パス `desugar-all` への内部定義・スプライシング `begin` 展開ルール組み込み)
- [x] [ulisp/compiler.scm](../../ulisp/compiler.scm) (自己ホスト結合・シードバイナリ更新)
- [x] [ulisp/tests/passes/test_028_desugar_bindings.scm](../../ulisp/tests/passes/test_028_desugar_bindings.scm) (Pass 028 単体テスト)
- [x] [ulisp/tests/passes/test_030_desugar.scm](../../ulisp/tests/passes/test_030_desugar.scm) (Pass 030 単体テスト)
- [x] [ulisp/tests/test_stdlib_r7rs.scm](../../ulisp/tests/test_stdlib_r7rs.scm) (R7RS 内部定義 E2E テスト)
- [x] [ulisp/docs/r7rs_specification_compliance.md](../../ulisp/docs/r7rs_specification_compliance.md) (§5.3.2 適合状況を △ から ◎ へ更新)

---

## 4. 根本原因分析 (RCA) / Root Cause Analysis

1. **Pass 025 (トップレベル巻き上げ) の局所性限界**:
   Pass 025 (`rewrite-top-level`) は最上位の式リストのみを走査し、トップレベルの `(define ...)` のみを `%program` の `unique-defs`（グローバルシンボル領域）へ巻き上げる。
   手続き本体（`lambda` 式等）の内部にある式は通常の式本体として扱われ、局所的な `(define ...)` は巻き上げの対象外となる。
2. **Pass 028 (局所束縛) における複数本体式の begin 正規化**:
   Pass 028 は `(lambda params b1 b2 . rest)` を `(lambda params (begin b1 b2 . rest))` へ正規化する。
   この結果、内部定義は `(begin (define x 10) (define y 20) (+ x y))` のような `begin` ブロックの先頭式として現れる。
3. **Pass 028 / 029 / 030 の脱糖規則の漏れ**:
   Pass 029 および Pass 030 には `define-values` に対する `(begin (define-values ...) . rest)` の脱糖ルールが存在する一方、通常の `(define <var> <val>)` や `(define (<name> . <params>) . <body>)` に対する脱糖ルールが存在しない。
   そのため、局所内部定義がそのまま素通りして Pass 040（解析）以降・Pass 130（LIR 生成）へ渡される。
4. **LIR 変数解決時の未束縛例外の誘発**:
   LIR 生成層（`130_lir.scm`）ではグローバルシンボル（`unique-defs`）またはレキシカル環境（`let` / `lambda` / `letrec`）に登録された変数のみを解決可能であるため、未脱糖のまま残った内部定義の対象変数が未解決となり、`Unbound variable in LIR: <var>` 例外が送出される。

---

## 5. セキュリティ・品質脅威分析 (Security & Threat Analysis)

1. **変数捕捉およびハイジーン破壊の脅威**:
   - 内部定義を展開する際、テンポラリ変数を無秩序に導入すると、ユーザー定義変数との衝突（変数の意図しないシャドーイングやスコープ汚染）を引き起こす恐れがある。
   - **対策**: `unique-symbol` を使用し、直接 `let` / `letrec` 束縛を構築することで不要な一時変数導入を極小化する。
2. **相互再帰・前方参照の未解決（参照時エラー）の脅威**:
   - 手続き定義を個別に順次 `letrec` にネストすると、後続の手続きが先行手続きのスコープ外となり、相互再帰呼び出し時に未束縛変数例外や不正なクロージャ生成が発生する。
   - **対策**: 連続する内部手続き定義を検出し、単一の `letrec` 複数束縛節へ統合（Grouped Letrec）することで、R7RS §5.3.2 準拠の相互再帰を保証する。
3. **カリー化・ネスト短縮構文の再帰爆発 / 不正構文の脅威**:
   - `(define ((f x) y) ...)` などのネストした構文定義に対し、構文解析が不完全であると無限再帰や不整合な AST を生成する危険がある。
   - **対策**: `normalize-define-spec` を再帰的に定義し、任意の深さのカリー化手続き定義を正規の `lambda` 階層へ脱糖する。
4. **末尾式欠落（定義のみの body）における未定義動作**:
   - R7RS では `<definition>* <expression>+` が要求されるが、万が一 `(define x 10)` のみで末尾式が存在しない場合でも、コンパイラがクラッシュせず `#f`（unspecified value）を補完して安全に完了すること。

---

## 6. 実装方針 / Implementation Plan

Target Branch: `fix/592-internal-definition-desugaring`

### 6.1 定義仕様の正規化ヘルパー (`normalize-define-spec`)
変数定義および短縮手続き定義（ネストしたカリー化定義を含む）を `(name . value-expr)` の標準ペアへ変換する:
```scheme
(define (normalize-define-spec spec bodies)
  (if (pair? spec)
      (if (pair? (car spec))
          ;; カリー化短縮構文: (define ((f x) y) ...) -> (define (f x) (lambda (y) ...))
          (normalize-define-spec (car spec) (list (cons 'lambda (cons (cdr spec) bodies))))
          ;; 通常短縮構文: (define (f x ...) ...) -> (define f (lambda (x ...) ...))
          (cons (car spec) (cons 'lambda (cons (cdr spec) bodies))))
      ;; 変数定義: (define x val)
      (cons spec (if (pair? bodies) (car bodies) #f))))
```

### 6.2 内部定義脱糖ロジック (`desugar-internal-define`)
1. **相互再帰手続き定義の集約 (Grouped Letrec)**:
   - 先頭が手続き定義（値が `lambda`）の場合、後続する連続手続き定義を収集し、単一の `(letrec ((name1 (lambda ...)) (name2 (lambda ...))) <body>)` へ脱糖。
2. **変数定義の逐次束縛 (Sequential Let)**:
   - 変数定義の場合、`(let ((name val)) <body>)` へ脱糖し、後続の定義は再帰的に内側の `let` / `letrec` へ展開（左から右への逐次評価順序を保証）。
3. **空本体式の安全補完**:
   - `rest` が空の場合は `#f` を返す。

```scheme
(define (desugar-internal-define spec rest-def rest)
  (let* ((norm (normalize-define-spec spec rest-def))
         (name (car norm))
         (val (cdr norm))
         (is-proc? (and (pair? val) (eq? (car val) 'lambda))))
    (if is-proc?
        ;; 連続する手続き定義を単一の letrec 節へ集約（相互再帰対応）
        (let loop ((cur-rest rest)
                   (proc-bindings (list (list name val))))
          (if (and (pair? cur-rest)
                   (pair? (car cur-rest))
                   (eq? (caar cur-rest) 'define)
                   (pair? (cdar cur-rest)))
              (let* ((next-def (car cur-rest))
                     (next-norm (normalize-define-spec (cadr next-def) (cddr next-def)))
                     (next-name (car next-norm))
                     (next-val (cdr next-norm)))
                (if (and (pair? next-val) (eq? (car next-val) 'lambda))
                    (loop (cdr cur-rest) (cons (list next-name next-val) proc-bindings))
                    (list 'letrec (reverse proc-bindings) (make-body-expr cur-rest))))
              (list 'letrec (reverse proc-bindings) (make-body-expr cur-rest))))
        ;; 通常の変数定義: let で包み、後続の定義・式を body に配置
        (list 'let (list (list name val)) (make-body-expr rest)))))
```

### 6.3 スプライシング `begin` の平坦化
Pass 030 (`desugar-all`) および Pass 028 にて、`begin` 直下のネストした `begin` を平坦化するルールを追加:
```scheme
((begin (begin ,inner ...) . ,rest)
 (Expr (cons 'begin (append inner rest))))
```

### 6.4 脱糖パスへのルール組み込み
`ulisp/frontend/028_desugar_bindings.scm` および `ulisp/frontend/030_desugar.scm` に以下のマッチングルールを追加:
```scheme
((begin (define ,spec . ,rest-def) . ,rest)
 (Expr (desugar-internal-define spec rest-def rest)))
((define ,spec . ,rest-def)
 (Expr (desugar-internal-define spec rest-def '())))
```

### 6.5 テストスイートの作成・拡張
1. **Pass 028 単体テスト (`tests/passes/test_028_desugar_bindings.scm`)**:
   - `desugar-internal-define` による内部変数定義脱糖の検証。
   - `desugar-internal-define` による内部手続き定義（短縮形）の `letrec` 展開の検証。
   - 複数連続定義・相互再帰定義の `letrec` 集約検証。
2. **Pass 030 単体テスト (`tests/passes/test_030_desugar.scm`)**:
   - `(desugar-all '(begin (define x 10) (define y 20) (+ x y)))` の検証。
   - スプライシング `begin` 併用時の内部定義脱糖検証。
3. **E2E 仕様テスト (`tests/test_stdlib_r7rs.scm`)**:
   - 手続き内の内部変数定義 `(define (foo) (define x 10) (define y 20) (+ x y))`
   - 手続き内の内部関数定義 `(define (outer) (define (inner n) (* n 2)) (inner 21))`
   - 相互再帰内部関数 `(define (foo) (define (even? n) ...) (define (odd? n) ...) (even? 10))`
   - カリー化内部関数 `(define (foo) (define ((add a) b) (+ a b)) ((add 10) 20))`
   - `let` や `let*` ブロック先頭での内部定義。

### 6.6 セルフホスティングブートストラップとドキュメント更新
- `make compiler` による `compiler.scm` の再生成。
- 3-Stage セルフホスティングブートストラップ（`make stage1 && make stage2 && cmp build/scheme-stage1 build/scheme-stage2`）による固定点収束確認とシードバイナリ（`bin/ulisp-boot`）更新。
- `ulisp/docs/r7rs_specification_compliance.md` の §5.3.2 適合ステータスを **△** から **◎** へ更新。

---

## 7. 完了条件 / Success Criteria (DoD)

- [x] `./bin/ulisp-boot <<< "(define (foo) (define x 10) (define y 20) (+ x y)) (foo)"` がエラーなく正常終了し、`30` を出力すること。
- [x] 内部手続き定義 `(define (<name> ...) ...)` が `letrec` 経由で正常にコンパイル・実行できること。
- [x] 相互再帰内部手続き（`even?` / `odd?` 等）が同一 `letrec` 内で未束縛例外なく正常に動作すること。
- [x] カリー化短縮定義 `(define ((f x) y) ...)` が正常に脱糖され実行できること。
- [x] `make test_nanopass` および `make test_passes` が 100% PASS すること。
- [x] `./test.sh` および `./test_c.sh` がエラーなく 100% PASS すること。
- [x] 3段階セルフホスティングブートストラップにおいて固定点収束（`cmp` 一致）が確認され、シードバイナリが更新されること。
- [x] `ulisp/docs/r7rs_specification_compliance.md` の §5.3.2 が **◎** に更新されること。
