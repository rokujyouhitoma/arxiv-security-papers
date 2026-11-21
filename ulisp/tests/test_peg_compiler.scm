;;; =======================================================================
;;; Test Suite: Pure Scheme Packrat PEG Compiler (Parser & Codegen)
;;; Conforms to DSN-25 Phase 2 & DSN-33-04 §3.2, Issue #894
;;; =======================================================================

(display "\n=== [Test Suite: Pure Scheme Packrat PEG Compiler (Issue #894)] ===\n\n")

;;; -----------------------------------------------------------------------
;;; Group 1: AST Node Construction & S-Expression Roundtrip (Homoiconicity)
;;; -----------------------------------------------------------------------

(display "--- Group 1: AST Construction & S-Expression Isomorphism ---\n")

(let* ((orig-sexpr
        '(grammar Calc
           (directives)
           (rules
            (rule expr (: term (* (: add-op term))))
            (rule term (: factor (* (: mul-op factor))))
            (rule factor (/ (: (lit "(") expr (lit ")"))
                            number))
            (rule add-op (/ (lit "+") (lit "-")))
            (rule mul-op (/ (lit "*") (lit "/")))
            (rule number (+ (char-class "0-9"))))))
       (ast (sexpr->ast orig-sexpr))
       (roundtrip-sexpr (ast->sexpr ast)))
  (assert-equal "AST roundtrip preserves grammar structure" orig-sexpr roundtrip-sexpr))

;;; -----------------------------------------------------------------------
;;; Group 2: Meta-Grammar Parser on CPython PEG Syntax
;;; -----------------------------------------------------------------------

(display "--- Group 2: Meta-Grammar Parser on CPython Syntax ---\n")

(define sample-peg-text
"
grammar SimpleExpr

expr:
    | term '+' expr
    | term

term:
    | factor '*' term
    | factor

factor:
    | '(' expr ')'
    | [0-9]+
")

(let ((ast (parse-peg-grammar sample-peg-text)))
  (assert-true "parse-peg-grammar returns <peg-grammar-def>" (peg-grammar-def? ast))
  (assert-equal "grammar name is SimpleExpr" 'SimpleExpr (peg-grammar-def-name ast))
  (assert-equal "rule count is 3" 3 (length (peg-grammar-def-rules ast)))
  (let ((rule-names (map peg-rule-def-name (peg-grammar-def-rules ast))))
    (assert-equal "rule names match" '(expr term factor) rule-names)))

;;; -----------------------------------------------------------------------
;;; Group 3: Codegen & End-to-End Parsing Execution
;;; -----------------------------------------------------------------------

(display "--- Group 3: Codegen & E2E Parsing Execution ---\n")

(let ((compiled-parser (compile-peg-string sample-peg-text 'expr)))
  (let ((res1 (peg-parse-partial compiled-parser "1+2*3"))
        (res2 (peg-parse-partial compiled-parser "(4+5)*6"))
        (res3 (peg-parse-partial compiled-parser "invalid")))
    (assert-true "1+2*3 matches" (pair? res1))
    (assert-equal "1+2*3 consumes 5 chars" 5 (cdr res1))
    (assert-true "(4+5)*6 matches" (pair? res2))
    (assert-equal "(4+5)*6 consumes 7 chars" 7 (cdr res2))
    (assert-false "invalid fails" res3)))

;;; -----------------------------------------------------------------------
;;; Group 4: Schemely Declarative Macro (define-grammar)
;;; -----------------------------------------------------------------------

(display "--- Group 4: Schemely Declarative Macro (define-grammar) ---\n")

(define-grammar mini-calc
  (expr (/ (: (lit "hello") (lit " ") (lit "world"))
           (: (lit "bye") (lit " ") (lit "world")))))

(let ((r1 (peg-parse-partial mini-calc "hello world"))
      (r2 (peg-parse-partial mini-calc "bye world"))
      (r3 (peg-parse-partial mini-calc "foo world")))
  (assert-true "mini-calc matches hello world" (pair? r1))
  (assert-true "mini-calc matches bye world" (pair? r2))
  (assert-false "mini-calc rejects foo world" r3))

(display "\n[PASS] All PEG Compiler tests passed successfully.\n\n")
