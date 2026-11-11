---
ID: 762
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT/ENH] フロントエンド脱糖パス (026〜029) の全規則 define-picopass 化と 1行S式ユニットテストの整備 (DSN-33-01 T4.1) (ID: 762)

## 1. 概要 / Summary

[[DSN-33-01] ULisp 階層型パス融合 ＆ DAG 最適化基盤設計書](../../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md) の第 1.1 節（Nanopass の粒度ジレンマ）、第 2.3 節（4階層の責務と入出力契約）、第 6.2 節（中間言語階層とパス配置マップ）、第 7.1 節（1行ユニットテスト）、および第 9.2 節タスク **T4.1** に基づき、フロントエンド脱糖サブモジュール群：
- Pass 026: `026_desugar_constructors.scm` (複合リテラル・コンストラクタ脱糖)
- Pass 027: `027_desugar_conditionals.scm` (条件分岐・比較連鎖脱糖)
- Pass 028: `028_desugar_bindings.scm` (局所束縛・内部定義・多値本体脱糖)
- Pass 029: `029_desugar_dynamic.scm` (動的環境・多値・継続・例外脱糖)

のすべての構文変換規則を第一級オブジェクトである **`define-picopass`**（および構文不変条件を守る **`define-attopass`**）として再定義した。

さらに、各サブモジュールの Nanopass 定義（`desugar-constructors`, `desugar-conditionals`, `desugar-bindings`, `desugar-dynamic`）を、手書きの個別節パターン記述から **`(fuse-rules ...)` による宣言的自動融合** へと再構築した。
これにより、各変換規則が AST 全体のボイラープレートなしに単体 S 式入力で直接呼び出し可能となり、1行 S 式ユニットテストの整備を通じてテスタビリティと保守性を飛躍的に高めた。これは、後続の Pass 030 重複コード約 190 行撤去（[Issue #763](../763-replace-desugar-030-duplicate-rules-with-fuse-rules.md) / Task T4.2）に向けた決定的な基盤整備となる。

---

## 2. トレーサビリティ / Traceability

- **関連設計書**:
  - [[DSN-33-01] ULisp 階層型パス融合 ＆ DAG 最適化基盤設計書](../../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md)
    - 第 1.1 節（Nanopass の粒度ジレンマ）
    - 第 2.3 節（各階層の厳密な責務と入出力契約: Picopass, Nanopass, Pass）
    - 第 3.1 節（3つの直交バリアント: `pico` / `femto` / `atto`）
    - 第 4.1〜4.3 節（Pass Fusion エンジン、先頭タグ $O(1)$ ディスパッチ、局所再適用）
    - 第 6.2 節（エンドツーエンド中間言語階層と全パス配置マップ）
    - 第 7.1 節（1行ユニットテストと REPL マイクロパイプライン）
    - 第 8.2 節（課題①: HIR 8構文ハードコードの撤去と明示的脱糖ルール）
    - 第 9.2 節（Phase 4 タスク **T4.1**）
- **依存関係**:
  - **先行 Issue**:
    - [Issue #756](756-implement-rule-descriptor-and-picopass-femtopass-attopass-dsl.md) (T2.1: 第一級 Rule Descriptor と Picopass DSL 実装) (Closed)
    - [Issue #757](757-implement-picopass-strategy-combinators.md) (T2.2: Picopass 関数合成コンビネータ群の実装) (Closed)
    - [Issue #758](758-integrate-picopass-dsl-into-pass-015-expander.md) (T2.3: Pass 015 先行 DSL 展開器への pico/femto/atto 構文統合) (Closed)
    - [Issue #759](759-implement-fuse-rules-and-head-tag-o1-dispatch.md) (T3.1: `fuse-rules` 構文と Head-Tag $O(1)$ ディスパッチ生成エンジンの実装) (Closed)
    - [Issue #760](760-implement-local-redispatch-and-extends-eliminates-validation.md) (T3.2: 5ステップ融合サイクルの局所再適用と `extends (-)` 対 `eliminates` 自動整合性検証) (Closed)
    - [Issue #761](761-implement-fuse-window-rules-for-lir-sliding-window.md) (T3.3: LIR スライディングウィンドウ走査ドライバ `fuse-window-rules` の実装) (Closed)
  - **後続 Issue**:
    - [Issue #763](../763-replace-desugar-030-duplicate-rules-with-fuse-rules.md) (T4.2: 030_desugar.scm の重複190行撤去と `fuse-rules` 完全置換)
    - [Issue #764](../764-migrate-verifier-to-attopass-and-eliminate-triple-traversal.md) (T4.3: verifier.scm の `define-attopass` 化と三重走査の解消)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [ulisp/frontend/026_desugar_constructors.scm](../../../ulisp/frontend/026_desugar_constructors.scm)
  - Pass 026 脱糖ヘルパー関数の統合配置（`desugar-string-copy`, `desugar-gcd`, `desugar-format` 等を含む）。
  - 名前付き `define-picopass` 規則群の定義：
    - `rule-desugar-list`
    - `rule-desugar-vector`
    - `rule-desugar-bytevector`
    - `rule-desugar-string-ops`
    - `rule-desugar-vector-ops`
    - `rule-desugar-bytevector-ops`
    - `rule-desugar-math-variadic`
    - `rule-desugar-format`
    - `rule-desugar-cxr`
  - `desugar-constructors` を `(fuse-rules ...)` による宣言的 Nanopass へ再定義。
- [x] [ulisp/frontend/027_desugar_conditionals.scm](../../../ulisp/frontend/027_desugar_conditionals.scm)
  - 名前付き `define-picopass` 規則群の定義：
    - `rule-desugar-cond-expand`
    - `rule-desugar-cond`
    - `rule-desugar-case`
    - `rule-desugar-and`
    - `rule-desugar-or`
    - `rule-desugar-chain-cmp`
  - `desugar-conditionals` を `(fuse-rules ...)` による宣言的 Nanopass へ再定義。
- [x] [ulisp/frontend/028_desugar_bindings.scm](../../../ulisp/frontend/028_desugar_bindings.scm)
  - 名前付き `define-picopass` 規則群の定義：
    - `rule-desugar-case-lambda`
    - `rule-desugar-let*`
    - `rule-desugar-letrec*`
    - `rule-desugar-named-let`
    - `rule-desugar-multi-body` (`let`, `letrec`, `lambda` の 0式/複数式正規化)
    - `rule-desugar-do`
    - `rule-desugar-internal-define`
  - `desugar-bindings` を `(fuse-rules ...)` による宣言的 Nanopass へ再定義。
- [x] [ulisp/frontend/029_desugar_dynamic.scm](../../../ulisp/frontend/029_desugar_dynamic.scm)
  - Pass 029 動的環境ヘルパー関数の統合配置（`desugar-delay`, `desugar-values`, `desugar-error`, `desugar-assume` 等）。
  - 名前付き `define-picopass` / `define-attopass` 規則群の定義：
    - `rule-desugar-let-values`
    - `rule-desugar-define-values`
    - `rule-desugar-guard`
    - `rule-desugar-parameterize`
    - `rule-desugar-delay`
    - `rule-desugar-parameter-ops`
    - `rule-desugar-values`
    - `rule-desugar-error-assume`
    - `atto-no-unexpanded-let-syntax`
  - `desugar-dynamic` を `(fuse-rules ...)` による宣言的 Nanopass へ再定義。
- [x] [ulisp/frontend/030_desugar.scm](../../../ulisp/frontend/030_desugar.scm)
  - `026` および `029` へのヘルパー移動に伴う重複 272 行を撤去し定義を一元化。
- [x] [ulisp/compiler.scm](../../../ulisp/compiler.scm)
  - `make -C ulisp compiler` による結合ソース再生成と 3-Stage セルフホスト固定点検証の通過。
- [x] [ulisp/tests/passes/test_026_desugar_constructors.scm](../../../ulisp/tests/passes/test_026_desugar_constructors.scm)
- [x] [ulisp/tests/passes/test_027_desugar_conditionals.scm](../../../ulisp/tests/passes/test_027_desugar_conditionals.scm)
- [x] [ulisp/tests/passes/test_028_desugar_bindings.scm](../../../ulisp/tests/passes/test_028_desugar_bindings.scm)
- [x] [ulisp/tests/passes/test_029_desugar_dynamic.scm](../../../ulisp/tests/passes/test_029_desugar_dynamic.scm)
  - 各 Picopass を直接呼び出す 1 行 S 式単体テスト群の追加・拡充。

---

## 4. 詳細設計 / Detailed Design

### 4.1 各脱糖サブモジュールにおける Picopass 規則群の設計

#### (1) Pass 026: Constructors (`026_desugar_constructors.scm`)
`L_src` における複合データ構造のリテラル構築構文および可変長操作をプリミティブ呼び出しへ変換する。

```scheme
;; 1. リスト構築
(define-picopass rule-desugar-list
  (Expr
    (((list . ,args) (desugar-list args)))))

;; 2. ベクタ構築
(define-picopass rule-desugar-vector
  (Expr
    (((vector . ,args) (desugar-vector args))
     ((vector-append . ,args) (desugar-vector-append args))
     ((make-vector . ,args) (desugar-make-vector args)))))

;; 3. バイトベクタ構築
(define-picopass rule-desugar-bytevector
  (Expr
    (((bytevector . ,args) (desugar-bytevector args))
     ((bytevector-append . ,args) (desugar-bytevector-append args))
     ((make-bytevector . ,args) (desugar-make-bytevector args)))))

;; 4. 文字列関連操作
(define-picopass rule-desugar-string-ops
  (Expr
    (((string . ,args) (desugar-string args))
     ((string-append . ,args) (desugar-string-append args))
     ((string-copy . ,args) (desugar-string-copy args))
     ((string-copy! . ,args) (desugar-string-copy! args))
     ((string-fill! . ,args) (desugar-string-fill! args))
     ((string->utf8 . ,args) (desugar-string->utf8 args))
     ((utf8->string . ,args) (desugar-utf8->string args))
     ((string->list . ,args) (desugar-string->list args))
     ((string->vector . ,args) (desugar-string->vector args)))))

;; 5. ベクタ関連操作
(define-picopass rule-desugar-vector-ops
  (Expr
    (((vector-copy . ,args) (desugar-vector-copy args))
     ((vector-copy! . ,args) (desugar-vector-copy! args))
     ((vector-fill! . ,args) (desugar-vector-fill! args))
     ((vector->list . ,args) (desugar-vector->list args))
     ((vector->string . ,args) (desugar-vector->string args))
     ((make-list . ,args) (desugar-make-list args)))))

;; 6. バイトベクタ関連操作
(define-picopass rule-desugar-bytevector-ops
  (Expr
    (((bytevector-copy . ,args) (desugar-bytevector-copy args))
     ((bytevector-copy! . ,args) (desugar-bytevector-copy! args)))))

;; 7. 可変長算術関数
(define-picopass rule-desugar-math-variadic
  (Expr
    (((gcd . ,args) (desugar-gcd args))
     ((lcm . ,args) (desugar-lcm args))
     ((max . ,args) (desugar-max args))
     ((min . ,args) (desugar-min args)))))

;; 8. 書式化出力
(define-picopass rule-desugar-format
  (Expr
    (((format . ,args) (desugar-format args)))))

;; 9. CxR 合成アクセサ (caar 〜 cadddr)
(define-picopass rule-desugar-cxr
  (Expr
    (((caar ,x) (list 'car (list 'car x)))
     ((cadr ,x) (list 'car (list 'cdr x)))
     ((cdar ,x) (list 'cdr (list 'car x)))
     ((cddr ,x) (list 'cdr (list 'cdr x)))
     ((caddr ,x) (list 'car (list 'cdr (list 'cdr x))))
     ((cdddr ,x) (list 'cdr (list 'cdr (list 'cdr x))))
     ((cadddr ,x) (list 'car (list 'cdr (list 'cdr (list 'cdr x))))))))
```

#### (2) Pass 027: Conditionals (`027_desugar_conditionals.scm`)
条件分岐構文（`cond`, `case`, `and`, `or`, 比較連鎖）をコアの `if` 式へ脱糖する。

```scheme
(define-picopass rule-desugar-cond-expand
  (Expr
    (((cond-expand ,clauses ...) (desugar-cond-expand clauses))
     ((cond-expand . ,clauses) (desugar-cond-expand clauses)))))

(define-picopass rule-desugar-cond
  (Expr
    (((cond ,clauses ...) (desugar-cond clauses))
     ((cond . ,clauses) (desugar-cond clauses)))))

(define-picopass rule-desugar-case
  (Expr
    (((case ,key ,clauses ...) (desugar-case key clauses))
     ((case ,key . ,clauses) (desugar-case key clauses)))))

(define-picopass rule-desugar-and
  (Expr
    (((and ,args ...) (desugar-and args))
     ((and . ,args) (desugar-and args)))))

(define-picopass rule-desugar-or
  (Expr
    (((or ,args ...) (desugar-or args))
     ((or . ,args) (desugar-or args)))))

(define-picopass rule-desugar-chain-cmp
  (Expr
    ;; 3引数以上の多項比較演算子を 2項比較の and 式へと展開
    (((char<? ,a1 ,a2 ,a3 . ,rest) (desugar-chain-cmp 'char<? (cons* a1 a2 a3 rest)))
     ((char<=? ,a1 ,a2 ,a3 . ,rest) (desugar-chain-cmp 'char<=? (cons* a1 a2 a3 rest)))
     ((char>? ,a1 ,a2 ,a3 . ,rest) (desugar-chain-cmp 'char>? (cons* a1 a2 a3 rest)))
     ((char>=? ,a1 ,a2 ,a3 . ,rest) (desugar-chain-cmp 'char>=? (cons* a1 a2 a3 rest)))
     ((char=? ,a1 ,a2 ,a3 . ,rest) (desugar-chain-cmp 'char=? (cons* a1 a2 a3 rest)))
     ((char-ci<? ,a1 ,a2 ,a3 . ,rest) (desugar-chain-cmp 'char-ci<? (cons* a1 a2 a3 rest)))
     ((char-ci<=? ,a1 ,a2 ,a3 . ,rest) (desugar-chain-cmp 'char-ci<=? (cons* a1 a2 a3 rest)))
     ((char-ci>? ,a1 ,a2 ,a3 . ,rest) (desugar-chain-cmp 'char-ci>? (cons* a1 a2 a3 rest)))
     ((char-ci>=? ,a1 ,a2 ,a3 . ,rest) (desugar-chain-cmp 'char-ci>=? (cons* a1 a2 a3 rest)))
     ((char-ci=? ,a1 ,a2 ,a3 . ,rest) (desugar-chain-cmp 'char-ci=? (cons* a1 a2 a3 rest)))
     ((string<? ,a1 ,a2 ,a3 . ,rest) (desugar-chain-cmp 'string<? (cons* a1 a2 a3 rest)))
     ((string<=? ,a1 ,a2 ,a3 . ,rest) (desugar-chain-cmp 'string<=? (cons* a1 a2 a3 rest)))
     ((string>? ,a1 ,a2 ,a3 . ,rest) (desugar-chain-cmp 'string>? (cons* a1 a2 a3 rest)))
     ((string>=? ,a1 ,a2 ,a3 . ,rest) (desugar-chain-cmp 'string>=? (cons* a1 a2 a3 rest)))
     ((string=? ,a1 ,a2 ,a3 . ,rest) (desugar-chain-cmp 'string=? (cons* a1 a2 a3 rest)))
     ((string-ci<? ,a1 ,a2 ,a3 . ,rest) (desugar-chain-cmp 'string-ci<? (cons* a1 a2 a3 rest)))
     ((string-ci<=? ,a1 ,a2 ,a3 . ,rest) (desugar-chain-cmp 'string-ci<=? (cons* a1 a2 a3 rest)))
     ((string-ci>? ,a1 ,a2 ,a3 . ,rest) (desugar-chain-cmp 'string-ci>? (cons* a1 a2 a3 rest)))
     ((string-ci>=? ,a1 ,a2 ,a3 . ,rest) (desugar-chain-cmp 'string-ci>=? (cons* a1 a2 a3 rest)))
     ((string-ci=? ,a1 ,a2 ,a3 . ,rest) (desugar-chain-cmp 'string-ci=? (cons* a1 a2 a3 rest))))))
```

#### (3) Pass 028: Bindings (`028_desugar_bindings.scm`)
局所束縛構文（`let*`, `letrec*`, `named-let`, `case-lambda`, `do`, 内部 `define`）および複数式本体の正規化を行う。

```scheme
(define-picopass rule-desugar-case-lambda
  (Expr
    (((case-lambda . ,clauses) (desugar-case-lambda clauses)))))

(define-picopass rule-desugar-let*
  (Expr
    (((let* ,bindings . ,bodies) (desugar-let* bindings bodies)))))

(define-picopass rule-desugar-letrec*
  (Expr
    (((letrec* ,bindings . ,bodies) (guard (list? bindings))
      (desugar-letrec* bindings bodies)))))

(define-picopass rule-desugar-named-let
  (Expr
    (((let ,name ,bindings . ,bodies) (guard (symbol? name))
      (desugar-named-let (cons 'let (cons name (cons bindings bodies))))))))

(define-picopass rule-desugar-multi-body
  (Expr
    (((let ,bindings) (guard (list? bindings))
      (list 'let bindings '(begin)))
     ((let ,bindings ,b1 ,b2 . ,rest) (guard (list? bindings))
      (list 'let bindings (cons 'begin (cons b1 (cons b2 rest)))))
     ((letrec ,bindings) (guard (list? bindings))
      (list 'letrec bindings '(begin)))
     ((letrec ,bindings ,b1 ,b2 . ,rest) (guard (list? bindings))
      (list 'letrec bindings (cons 'begin (cons b1 (cons b2 rest)))))
     ((lambda ,params)
      (list 'lambda params '(begin)))
     ((lambda ,params ,b1 ,b2 . ,rest)
      (list 'lambda params (cons 'begin (cons b1 (cons b2 rest))))))))

(define-picopass rule-desugar-do
  (Expr
    (((do ,bindings ,exit-clause . ,commands)
      (desugar-do bindings exit-clause commands)))))

(define-picopass rule-desugar-internal-define
  (Expr
    (((begin (begin . ,inner) . ,rest)
      (cons 'begin (append inner rest)))
     ((begin (define ,spec . ,rest-def) . ,rest)
      (desugar-internal-define spec rest-def rest))
     ((define ,spec . ,rest-def)
      (desugar-internal-define spec rest-def '())))))
```

#### (4) Pass 029: Dynamic Environment & Multiple Values (`029_desugar_dynamic.scm`)
動的巻き戻し・多値・遅延評価・例外ハンドラをコア形式へ脱糖する。

```scheme
(define-picopass rule-desugar-let-values
  (Expr
    (((let-values ,bindings . ,bodies) (desugar-let-values bindings bodies))
     ((let*-values ,bindings . ,bodies) (desugar-let*-values bindings bodies)))))

(define-picopass rule-desugar-define-values
  (Expr
    (((begin (define-values ,formals ,expr) . ,rest)
      (desugar-define-values formals expr rest))
     ((define-values ,formals ,expr)
      (desugar-define-values formals expr '())))))

(define-picopass rule-desugar-guard
  (Expr
    (((guard ,spec . ,bodies) (desugar-guard spec bodies)))))

(define-picopass rule-desugar-parameterize
  (Expr
    (((parameterize ,bindings . ,bodies) (desugar-parameterize bindings bodies)))))

(define-picopass rule-desugar-delay
  (Expr
    (((delay . ,args) (desugar-delay (cons 'delay args)))
     ((delay-force . ,args) (desugar-delay-force (cons 'delay-force args))))))

(define-picopass rule-desugar-parameter-ops
  (Expr
    (((make-parameter . ,args) (desugar-make-parameter args)))))

(define-picopass rule-desugar-values
  (Expr
    (((values . ,args) (desugar-values args)))))

(define-picopass rule-desugar-error-assume
  (Expr
    (((error . ,args) (desugar-error (cons 'error args)))
     ((assume . ,args) (desugar-assume (cons 'assume args)))
     ((assert . ,args) (desugar-assume (cons 'assert args)))
     ((syntax-error . ,args) (desugar-syntax-error (cons 'syntax-error args))))))

;; 未展開の let-syntax / letrec-syntax を拒絶する不変条件 Attopass
(define-attopass atto-no-unexpanded-let-syntax
  (Expr
    (((let-syntax . ,args)
      (error "syntax-error [R7RS §4.3.1]: unexpanded let-syntax encountered in desugar" args))
     ((letrec-syntax . ,args)
      (error "syntax-error [R7RS §4.3.1]: unexpanded let-syntax encountered in desugar" args)))))
```

---

### 4.2 `define-pass` の `fuse-rules` 宣言化

各サブモジュールの `define-pass` は、上記の Picopass 群を `(fuse-rules ...)` で束ねる極めて宣言的な構成へと刷新される：

```scheme
;; 026_desugar_constructors.scm
(define-pass desugar-constructors : L_src (ir) -> L_core ()
  (fuse-rules
    rule-desugar-list
    rule-desugar-vector
    rule-desugar-bytevector
    rule-desugar-string-ops
    rule-desugar-vector-ops
    rule-desugar-bytevector-ops
    rule-desugar-math-variadic
    rule-desugar-format
    rule-desugar-cxr))

;; 027_desugar_conditionals.scm
(define-pass desugar-conditionals : L_src (ir) -> L_core ()
  (fuse-rules
    rule-desugar-cond-expand
    rule-desugar-cond
    rule-desugar-case
    rule-desugar-and
    rule-desugar-or
    rule-desugar-chain-cmp))

;; 028_desugar_bindings.scm
(define-pass desugar-bindings : L_src (ir) -> L_core ()
  (fuse-rules
    rule-desugar-case-lambda
    rule-desugar-let*
    rule-desugar-letrec*
    rule-desugar-named-let
    rule-desugar-multi-body
    rule-desugar-do
    rule-desugar-internal-define))

;; 029_desugar_dynamic.scm
(define-pass desugar-dynamic : L_src (ir) -> L_core ()
  (fuse-rules
    rule-desugar-let-values
    rule-desugar-define-values
    rule-desugar-guard
    rule-desugar-parameterize
    rule-desugar-delay
    rule-desugar-parameter-ops
    rule-desugar-values
    rule-desugar-error-assume
    atto-no-unexpanded-let-syntax))
```

---

### 4.3 1行S式単体テスト仕様

各 Picopass が一級手続きとして呼び出し可能であることを活用し、各テストファイルに以下の直接呼出しテストを追加する：

```scheme
;; test_026_desugar_constructors.scm
(assert-equal "rule-desugar-list single" '(cons 1 (cons 2 '())) (rule-desugar-list '(list 1 2)))
(assert-equal "rule-desugar-math-variadic gcd" '(gcd-2 6 9) (rule-desugar-math-variadic '(gcd 6 9)))
(assert-equal "rule-desugar-cxr cadr" '(car (cdr x)) (rule-desugar-cxr '(cadr x)))

;; test_027_desugar_conditionals.scm
(assert-equal "rule-desugar-and single" '(if a (and b) #f) (rule-desugar-and '(and a b)))
(assert-equal "rule-desugar-cond single" '(if (= x 1) (begin 10) (begin 20)) (rule-desugar-cond '(cond ((= x 1) 10) (else 20))))

;; test_028_desugar_bindings.scm
(assert-equal "rule-desugar-let* single" '(let ((x 1)) (let ((y 2)) (+ x y))) (rule-desugar-let* '(let* ((x 1) (y 2)) (+ x y))))
(assert-equal "rule-desugar-multi-body lambda" '(lambda (x) (begin 1 2)) (rule-desugar-multi-body '(lambda (x) 1 2)))

;; test_029_desugar_dynamic.scm
(let ((res (rule-desugar-let-values '(let-values (((a b) (values 1 2))) (+ a b)))))
  (assert-equal "rule-desugar-let-values root" 'call-with-values (car res)))
```

---

### 4.4 セキュリティ考慮事項 / Security Considerations

- **CWE-400 (Uncontrolled Resource Consumption / CPU 枯渇防止)**:
  - 局所再適用（Local Re-dispatch）による無限ループを抑止するため、Nanopass エンジンの Fuel Guard（最大再ディスパッチ制限 16 回）が確実に適用されることを保証する。
- **CWE-674 (Uncontrolled Recursion)**:
  - `desugar-string-append`, `desugar-vector-append`, `desugar-bytevector-append` は分割統治法（Divide and Conquer）により AST の再帰深さを $O(\log N)$ に制限し、スタックオーバーフローを防止する。
- **CWE-704 / CWE-843 (型・構造の誤認防止)**:
  - 不完全な形式の S 式（アトム、非ペア引数等）が渡された場合でも、ガード式（`guard (list? bindings)` 等）によりクラッシュせず安全にフォールスルーまたは構文エラーを発生させる。
- **CWE-1188 (不変条件の強制)**:
  - `atto-no-unexpanded-let-syntax` により、Pass 020 マクロ展開器をすり抜けた未展開構文が下流パスへ漏洩することを決定的に遮断する。

---

## 5. 実装手順 / Implementation Steps

Target Branch: `refactor/762-migrate-desugar-026-029-to-picopass`

- [x] **Step 1: Feature ブランチ作成と作業環境準備**
  - `refactor/762-migrate-desugar-026-029-to-picopass` ブランチを作成し、現在の `main` から分岐。
- [x] **Step 2: Pass 026 Constructors の Picopass 化とヘルパー集約 (`026_desugar_constructors.scm`)**
  - `desugar-string-copy` 等のコンストラクタ関連ヘルパーを統合配置。
  - `rule-desugar-list`, `rule-desugar-vector`, `rule-desugar-bytevector`, `rule-desugar-string-ops`, `rule-desugar-vector-ops`, `rule-desugar-bytevector-ops`, `rule-desugar-math-variadic`, `rule-desugar-format`, `rule-desugar-cxr` を `define-picopass` で定義。
  - `desugar-constructors` を `(fuse-rules ...)` で宣言的に再構成。
- [x] **Step 3: Pass 027 Conditionals の Picopass 化 (`027_desugar_conditionals.scm`)**
  - `rule-desugar-cond-expand`, `rule-desugar-cond`, `rule-desugar-case`, `rule-desugar-and`, `rule-desugar-or`, `rule-desugar-chain-cmp` を `define-picopass` で定義。
  - `desugar-conditionals` を `(fuse-rules ...)` で宣言的に再構成。
- [x] **Step 4: Pass 028 Bindings の Picopass 化 (`028_desugar_bindings.scm`)**
  - `rule-desugar-case-lambda`, `rule-desugar-let*`, `rule-desugar-letrec*`, `rule-desugar-named-let`, `rule-desugar-multi-body`, `rule-desugar-do`, `rule-desugar-internal-define` を `define-picopass` で定義。
  - `desugar-bindings` を `(fuse-rules ...)` で宣言的に再構成。
- [x] **Step 5: Pass 029 Dynamic & Values の Picopass 化 (`029_desugar_dynamic.scm`)**
  - `desugar-delay`, `desugar-values`, `desugar-error`, `desugar-assume`, `desugar-syntax-error` 等のヘルパーを統合配置。
  - `rule-desugar-let-values`, `rule-desugar-define-values`, `rule-desugar-guard`, `rule-desugar-parameterize`, `rule-desugar-delay`, `rule-desugar-parameter-ops`, `rule-desugar-values`, `rule-desugar-error-assume` を `define-picopass` で定義。
  - `atto-no-unexpanded-let-syntax` を `define-attopass` で定義。
  - `desugar-dynamic` を `(fuse-rules ...)` で宣言的に再構成。
- [x] **Step 6: Pass 030 とのヘルパー整合性確保 (`030_desugar.scm`)**
  - `026` および `029` に移動したヘルパー定義との重複 272 行を解消し、`030_desugar.scm` の定義を一元化。
- [x] **Step 7: 1行S式単体テストの拡充 (`test_026`〜`test_029`)**
  - `test_026_desugar_constructors.scm`、`test_027_desugar_conditionals.scm`、`test_028_desugar_bindings.scm`、`test_029_desugar_dynamic.scm` に各 Picopass を直接呼び出す単体テストを追加。
- [x] **Step 8: コンパイラ再生成と 3-Stage セルフホスト固定点検証**
  - `make -C ulisp compiler` を実行し、結合ソースを再生成。
  - `make -C ulisp bootstrap` を実行し、Stage 2 と Stage 3 の bit-for-bit IDENTICAL 一致およびスモークテスト（42）PASS を確認。
- [x] **Step 9: 品質ゲート検証**
  - `make -C ulisp test_passes` および `make -C ulisp test_nanopass` を実行し全件 PASS を確認。
  - `make py_compile` および `make static_analysis` のエラー 0 件を確認。
- [x] **Step 10: 台帳更新とコミット (`git-workflow`)**
  - `docs/issues/762-migrate-desugar-passes-026-to-029-to-picopass.md` をクローズし、`docs/issues/closed/` へ移動。
  - `docs/issues/README.md` を更新。
  - Conventional Commit 形式でコミット。

---

## 6. 完了条件 / Success Criteria (DoD)

1. [x] **Picopass 定義の完全性**: `026`〜`029` のすべての脱糖構文が、独立した名前付き `define-picopass`（および `define-attopass`）として定義されていること。
2. [x] **`fuse-rules` による宣言的 Nanopass 化**: `desugar-constructors`, `desugar-conditionals`, `desugar-bindings`, `desugar-dynamic` の全 4 パスが `(fuse-rules ...)` で束ねられた Nanopass として正常に機能すること。
3. [x] **1行S式ユニットテスト**: 個別の Picopass を直接呼び出す 1 行 S 式単体テストが `test_026`〜`test_029` に拡充され、全件 PASS すること。
4. [x] **既存パス回帰なし**: `make -C ulisp test_passes`（全 147 パス + 39 バッチテスト）および `make -C ulisp test_nanopass`（全 176 テスト + 31 Tracer テスト）が 100% PASS すること。
5. [x] **3-Stage セルフホスティング固定点**: `make -C ulisp bootstrap` が bit-for-bit 完全一致で成功し、スモークテスト（42）が正常完了すること。
6. [x] **静的解析・相対リンク品質**: `make py_compile`、`make static_analysis` がエラー 0 件で通過し、絶対パスリンクが 0 件であること。
