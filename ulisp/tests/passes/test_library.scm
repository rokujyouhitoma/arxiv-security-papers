;;; =======================================================================
;;; Unit Test Suite: ULisp Pass 0a (R7RS define-library & import)
;;; Conforms to DSN-33 Architecture Specification & Issue #548
;;; =======================================================================

(define *library-tests-run* 0)
(define *library-tests-passed* 0)

(define (assert-true label cond)
  (set! *library-tests-run* (+ *library-tests-run* 1))
  (if cond
      (begin
        (set! *library-tests-passed* (+ *library-tests-passed* 1))
        (display "  [PASS] ") (display label) (newline))
      (begin
        (display "  [FAIL] ") (display label) (newline)
        (error "Assertion failed:" label))))

(define (assert-equal label expected actual)
  (set! *library-tests-run* (+ *library-tests-run* 1))
  (if (equal? expected actual)
      (begin
        (set! *library-tests-passed* (+ *library-tests-passed* 1))
        (display "  [PASS] ") (display label) (newline))
      (begin
        (display "  [FAIL] ") (display label)
        (display " -> Expected: ") (write expected)
        (display " but got: ") (write actual) (newline)
        (error "Assertion failed:" label))))

(display "=======================================================")
(newline)
(display " Starting Pass 0a (R7RS define-library & import) Test Suite")
(newline)
(display "=======================================================")
(newline)

;;; --- Group 1: Syntax Predicates & Parsing ---
(display "--- Group 1: Syntax Predicates & Export Parsing ---") (newline)

(assert-true "define-library-form? positive"
             (define-library-form? '(define-library (foo bar) (export x) (begin 1))))

(assert-true "define-library-form? negative"
             (not (define-library-form? '(define (foo x) x))))

(assert-true "import-form? positive"
             (import-form? '(import (scheme base) (foo bar))))

(assert-true "import-form? negative"
             (not (import-form? '(define x 42))))

(assert-true "builtin-library-name? positive scheme base"
             (builtin-library-name? '(scheme base)))

(assert-true "builtin-library-name? positive scheme write"
             (builtin-library-name? '(scheme write)))

(assert-true "builtin-library-name? negative user lib"
             (not (builtin-library-name? '(my math core))))

(assert-equal "parse-export-specs standard and rename"
              '((add . add) (sub . my-sub) (mul . mul))
              (parse-export-specs '(add (rename sub my-sub) mul)))

;;; --- Group 2: Library Name Prefixing ---
(display "--- Group 2: Library Name Prefixing ---") (newline)

(assert-equal "library-name->prefix-str single"
              "__lib_math__"
              (library-name->prefix-str '(math)))

(assert-equal "library-name->prefix-str composite"
              "__lib_example_math_core__"
              (library-name->prefix-str '(example math core)))

;;; --- Group 3: Import-Set Resolution Modifiers ---
(display "--- Group 3: Import-Set Resolution Modifiers ---") (newline)

(define test-reg
  (list (cons '(math simple)
              (make-library-rec '(math simple)
                                '((add . add) (sub . sub) (mul . mul) (div . div))
                                '()
                                '((define (add x y) (+ x y))
                                  (define (sub x y) (- x y))
                                  (define (mul x y) (* x y))
                                  (define (div x y) (/ x y)))))))

;; Direct import
(let ((res (resolve-import-set '(math simple) test-reg)))
  (assert-equal "resolve-import-set direct lib-name" '(math simple) (car res))
  (assert-equal "resolve-import-set direct mapping"
                '((add . add) (sub . sub) (mul . mul) (div . div))
                (cdr res)))

;; only modifier
(let ((res (resolve-import-set '(only (math simple) add mul) test-reg)))
  (assert-equal "resolve-import-set only mapping"
                '((add . add) (mul . mul))
                (cdr res)))

;; except modifier
(let ((res (resolve-import-set '(except (math simple) sub div) test-reg)))
  (assert-equal "resolve-import-set except mapping"
                '((add . add) (mul . mul))
                (cdr res)))

;; prefix modifier
(let ((res (resolve-import-set '(prefix (math simple) m:) test-reg)))
  (assert-equal "resolve-import-set prefix mapping"
                '((add . m:add) (sub . m:sub) (mul . m:mul) (div . m:div))
                (cdr res)))

;; rename modifier
(let ((res (resolve-import-set '(rename (math simple) (add plus) (sub minus)) test-reg)))
  (assert-equal "resolve-import-set rename mapping"
                '((add . plus) (sub . minus) (mul . mul) (div . div))
                (cdr res)))

;; Combined modifiers: prefix and only
(let ((res (resolve-import-set '(prefix (only (math simple) add) calc:) test-reg)))
  (assert-equal "resolve-import-set combined only and prefix"
                '((add . calc:add))
                (cdr res)))

;;; --- Group 4: End-to-End Library Desugaring ---
(display "--- Group 4: End-to-End Library Desugaring ---") (newline)

(define sample-program
  '((define-library (geometry shapes)
      (export area perimeter)
      (import (scheme base))
      (begin
        (define (secret-helper w h) (* w h))
        (define (area w h) (secret-helper w h))
        (define (perimeter w h) (+ (* 2 w) (* 2 h)))))

    (import (prefix (only (geometry shapes) area) geo:))
    (import (rename (only (geometry shapes) perimeter) (perimeter calc-perimeter)))

    (define (main)
      (+ (geo:area 10 20) (calc-perimeter 10 20)))))

(define desugared (desugar-libraries-and-imports sample-program))

;; Verify no define-library or import remains in desugared output
(assert-true "desugared has no define-library"
             (null? (filter define-library-form? desugared)))

(assert-true "desugared has no import"
             (null? (filter import-form? desugared)))

;; Verify that internal definitions exist and aliases are created
(define defined-symbols (extract-defined-names-in-body desugared))

(assert-true "namespaced helper exists"
             (memq '__lib_geometry_shapes__secret-helper defined-symbols))

(assert-true "namespaced area exists"
             (memq '__lib_geometry_shapes__area defined-symbols))

(assert-true "aliased geo:area exists"
             (memq 'geo:area defined-symbols))

(assert-true "aliased calc-perimeter exists"
             (memq 'calc-perimeter defined-symbols))

;; Verify standard scheme base import is cleanly absorbed
(define with-std-import
  '((import (scheme base))
    (define x 10)
    (+ x 20)))

(define desugared-std (desugar-libraries-and-imports with-std-import))
(assert-equal "desugared-std cleans up scheme base import"
              '((define x 10) (+ x 20))
              desugared-std)

;;; --- Group 5: Full AOT Pipeline Compilation to LIR, x86-64, and C ---
(display "--- Group 5: Full AOT Pipeline Compilation to LIR, x86-64, and C ---") (newline)

(define full-test-program
  '((define-library (calc ops)
      (export add-mul)
      (import (scheme base))
      (begin
        (define (add-mul a b c)
          (+ (* a b) c))))

    (import (calc ops))
    (add-mul 10 20 60)))

(let* ((lib-expanded (desugar-libraries-and-imports full-test-program))
       (macro-expanded (expand-macros-in-forms lib-expanded))
       (ast0 (rewrite-top-level macro-expanded))
       (ast1 (desugar-all ast0))
       (ast2 (cp0-optimize ast1))
       (ast2b (lvn-all ast2))
       (ast3 (anf-all ast2b))
       (ast3b (annotate-all ast3))
       (ast3c (rtyper-all ast3b))
       (ast3d (contify-all ast3c))
       (ast4 (closure-convert ast3d))
       (ast4b (alias-escape-all ast4))
       (lir  (generate-lir ast4b)))

  (assert-true "LIR generation succeeded for library program" (pair? lir))

  (with-output-to-file "build/test_library.s"
    (lambda ()
      (emit-x86-64 lir 'all)))
  (assert-true "Emitted build/test_library.s successfully" #t)

  (with-output-to-file "build/test_library.c"
    (lambda ()
      (emit-c lir 'all)))
  (assert-true "Emitted build/test_library.c successfully" #t))

;;; --- Summary ---
(newline)
(display "=======================================================")
(newline)
(display " Pass 0a (R7RS define-library & import) Test Results: ")
(display *library-tests-passed*)
(display " / ")
(display *library-tests-run*)
(display " Passed.")
(newline)
(display "=======================================================")
(newline)

(if (= *library-tests-passed* *library-tests-run*)
    (display "ALL PASS 0A LIBRARY TESTS PASSED!\n")
    (error "SOME TESTS FAILED!"))

