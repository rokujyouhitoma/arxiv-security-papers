;;; =======================================================================
;;; Unit Test Suite: ULisp Lexical Scope & Alpha-Conversion Engine (Pass 035)
;;; Conforms to Issue #600 & Nanopass Architecture Quality Standard
;;; =======================================================================

(define *scope-tests-passed* 0)
(define *scope-tests-failed* 0)

(define (assert-equal label expected actual)
  (if (equal? expected actual)
      (begin
        (set! *scope-tests-passed* (+ *scope-tests-passed* 1))
        (display "  [PASS] ") (display label) (newline))
      (begin
        (set! *scope-tests-failed* (+ *scope-tests-failed* 1))
        (display "  [FAIL] ") (display label)
        (display " -> Expected: ") (write expected)
        (display " but got: ") (write actual) (newline)
        (error "Assertion failed:" label))))

(define (assert-true label actual)
  (assert-equal label #t (if actual #t #f)))

(define (assert-false label actual)
  (assert-equal label #f (if actual #t #f)))

(display "\n=======================================================\n")
(display " Starting Pass 035 (Scope & Alpha-Conversion) Unit Tests\n")
(display "=======================================================\n")

;;; -----------------------------------------------------------------------
;;; Group 1: Scope Node Records & Contour Hierarchy
;;; -----------------------------------------------------------------------
(display "\n--- Group 1: Scope Node & Contour Hierarchy ---\n")

(define root-scope (make-scope-node #f 'top-level))
(assert-true "1.1 root scope node created" (scope-node? root-scope))
(assert-equal "1.2 root scope kind is top-level" 'top-level (scope-node-kind root-scope))
(assert-false "1.3 root scope has no parent" (scope-node-parent root-scope))

(define child-scope (scope-enter root-scope 'lambda))
(assert-true "1.4 child scope node created" (scope-node? child-scope))
(assert-equal "1.5 child scope kind is lambda" 'lambda (scope-node-kind child-scope))
(assert-true "1.6 child scope parent is root" (eq? root-scope (scope-node-parent child-scope)))
(assert-equal "1.7 root children contains child" (list child-scope) (scope-node-children root-scope))

(scope-bind! root-scope 'g 'g$root)
(scope-bind! child-scope 'x 'x$0)

(assert-equal "1.8 local lookup in child finds x" 'x$0 (scope-lookup-local child-scope 'x))
(assert-false "1.9 local lookup in child does not find g" (scope-lookup-local child-scope 'g))
(assert-equal "1.10 lexical lookup in child finds x" 'x$0 (scope-lookup child-scope 'x))
(assert-equal "1.11 lexical lookup in child resolves g from parent" 'g$root (scope-lookup child-scope 'g))

;;; -----------------------------------------------------------------------
;;; Group 2: Nested Scope Shadowing
;;; -----------------------------------------------------------------------
(display "\n--- Group 2: Nested Scope Shadowing ---\n")

(define grand-scope (scope-enter child-scope 'let))
(scope-bind! grand-scope 'x 'x$grand)

(assert-equal "2.1 grand-child shadows x from child" 'x$grand (scope-lookup grand-scope 'x))
(assert-equal "2.2 child still retains original binding x$0" 'x$0 (scope-lookup child-scope 'x))

;; Free variable tracking
(scope-record-free-var! grand-scope 'free_z)
(assert-true "2.3 free variable recorded in grand scope" (memq 'free_z (scope-node-free-vars grand-scope)))

;;; -----------------------------------------------------------------------
;;; Group 3: Deterministic Alpha Symbol Generator
;;; -----------------------------------------------------------------------
(display "\n--- Group 3: Deterministic Alpha Symbol Generator ---\n")

(reset-alpha-symbol-counter!)
(assert-equal "3.1 first generated symbol has id 0" 'x$0 (make-alpha-symbol 'x))
(assert-equal "3.2 second generated symbol has id 1" 'y$1 (make-alpha-symbol 'y))
(assert-equal "3.3 third generated symbol has id 2" 'x$2 (make-alpha-symbol 'x))

;;; -----------------------------------------------------------------------
;;; Group 4: Alpha-Conversion of Lambda & Parameter Shadowing
;;; -----------------------------------------------------------------------
(display "\n--- Group 4: Alpha-Conversion of Lambda & Parameter Shadowing ---\n")

(reset-alpha-symbol-counter!)
(assert-equal "4.1 simple lambda parameter conversion"
              '(lambda (x$0) (+ x$0 1))
              (scope-resolve-all '(lambda (x) (+ x 1))))

(reset-alpha-symbol-counter!)
(assert-equal "4.2 nested lambda parameter shadowing"
              '(lambda (x$0) (lambda (x$1) (+ x$1 1)))
              (scope-resolve-all '(lambda (x) (lambda (x) (+ x 1)))))

(reset-alpha-symbol-counter!)
(assert-equal "4.3 cross-parameter reference in nested lambda"
              '(lambda (x$0) (lambda (y$1) (+ x$0 y$1)))
              (scope-resolve-all '(lambda (x) (lambda (y) (+ x y)))))

;;; -----------------------------------------------------------------------
;;; Group 5: Alpha-Conversion of Let and Letrec Bindings
;;; -----------------------------------------------------------------------
(display "\n--- Group 5: Let and Letrec Alpha-Conversion ---\n")

(reset-alpha-symbol-counter!)
;; In let, outer x is referenced in the inner RHS before inner x is bound
(assert-equal "5.1 let variable shadowing"
              '(let ((x$0 1)) (let ((x$1 (+ x$0 2))) x$1))
              (scope-resolve-all '(let ((x 1)) (let ((x (+ x 2))) x))))

(reset-alpha-symbol-counter!)
;; In letrec, f and g are mutually recursive
(assert-equal "5.2 letrec mutual recursion alpha conversion"
              '(letrec ((f$0 (lambda (n$2) (if (= n$2 0) 1 (g$1 (- n$2 1)))))
                        (g$1 (lambda (m$3) (f$0 m$3))))
                 (f$0 10))
              (scope-resolve-all
               '(letrec ((f (lambda (n) (if (= n 0) 1 (g (- n 1)))))
                         (g (lambda (m) (f m))))
                  (f 10))))

;;; -----------------------------------------------------------------------
;;; Group 6: Preservation of Quote Datum (No Modification of Literals)
;;; -----------------------------------------------------------------------
(display "\n--- Group 6: Quote Literals Preservation ---\n")

(reset-alpha-symbol-counter!)
(assert-equal "6.1 quoted symbols inside datum preserved verbatim"
              '(let ((x$0 (quote (x y z)))) x$0)
              (scope-resolve-all '(let ((x '(x y z))) x)))

(reset-alpha-symbol-counter!)
(assert-equal "6.2 quoted symbol atom preserved"
              '(let ((x$0 (quote x))) x$0)
              (scope-resolve-all '(let ((x 'x)) x)))

;;; -----------------------------------------------------------------------
;;; Group 7: Top-Level %program Definition Preservation
;;; -----------------------------------------------------------------------
(display "\n--- Group 7: Top-Level %program Preservation ---\n")

(reset-alpha-symbol-counter!)
(define sample-prog
  '(%program
    ((define add-ten (lambda (n) (+ n 10)))
     (define square (lambda (x) (* x x))))
    (add-ten (square 5))))

(define expected-prog
  '(%program
    ((define add-ten (lambda (n$0) (+ n$0 10)))
     (define square (lambda (x$1) (* x$1 x$1))))
    (add-ten (square 5))))

(assert-equal "7.1 %program top-level names preserved, local params alpha-converted"
              expected-prog
              (scope-resolve-all sample-prog))

;;; -----------------------------------------------------------------------
;;; Group 8: Early Unbound Variable Detection
;;; -----------------------------------------------------------------------
(display "\n--- Group 8: Early Unbound Variable Detection ---\n")

;; Closed expression has 0 unbound variables
(assert-equal "8.1 closed expression has no unbound vars"
              '()
              (detect-unbound-variables '(lambda (x) (+ x 1))))

;; Free variable y is unbound
(assert-equal "8.2 free variable detected as unbound"
              '(unbound-y)
              (detect-unbound-variables '(lambda (x) (+ x unbound-y))))

;; Top-level define resolves the variable
(assert-equal "8.3 defined variable is not unbound in %program"
              '()
              (detect-unbound-variables
               '(%program
                 ((define global-var 42))
                 (+ global-var 1))))

;; Truly unbound in %program
(assert-equal "8.4 missing definition detected in %program"
              '(missing-helper)
              (detect-unbound-variables
               '(%program
                 ((define global-var 42))
                 (missing-helper global-var))))

;; Test strict check records unbound variable
(reset-scope-unbound-vars!)
(alpha-convert-program '(lambda (x) (+ x definitely-unbound-var)))
(assert-equal "8.5 unbound variable recorded in strict detection"
              '(definitely-unbound-var)
              (get-scope-unbound-vars))

;;; -----------------------------------------------------------------------
;;; Group 9: Pass 035 Registration & Pipeline Scheduling
;;; -----------------------------------------------------------------------
(display "\n--- Group 9: Pass 035 Registration & Pipeline Verification ---\n")

(init-default-pass-registry!)
(define desc-p35 (lookup-pass 'pass-035-scope-resolve))

(assert-true "9.1 pass-035-scope-resolve is registered" (and desc-p35 #t))
(assert-equal "9.2 pass-035 category is frontend" 'frontend (pass-category desc-p35))
(assert-equal "9.3 pass-035 opt-level is 0 (mandatory)" 0 (pass-opt-level desc-p35))
(assert-true "9.4 pass-035 is mandatory" (pass-mandatory? desc-p35))
(assert-equal "9.5 pass-035 in-lang is L_core" 'L_core (pass-in-lang desc-p35))
(assert-equal "9.6 pass-035 out-lang is L_core" 'L_core (pass-out-lang desc-p35))
(assert-equal "9.7 pass-035 prerequisite is pass-030-desugar" '(pass-030-desugar) (pass-prerequisites desc-p35))

(display "\n=======================================================\n")
(display " Pass 035 Unit Tests Completed: ")
(display *scope-tests-passed*) (display " passed, ")
(display *scope-tests-failed*) (display " failed.\n")
(display "=======================================================\n")

(if (> *scope-tests-failed* 0)
    (error "Pass 035 test suite failed"))
