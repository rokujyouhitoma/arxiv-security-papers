;;; =======================================================================
;;; Unit Test Suite: ULisp Pass 000 (Compiler Context & Diagnostic Dump)
;;; Conforms to DSN-33 Architecture Specification & Issue #602
;;; =======================================================================

(define *diag-tests-run* 0)
(define *diag-tests-passed* 0)

(define (assert-true label cond)
  (set! *diag-tests-run* (+ *diag-tests-run* 1))
  (if cond
      (begin
        (set! *diag-tests-passed* (+ *diag-tests-passed* 1))
        (display "  [PASS] ") (display label) (newline))
      (begin
        (display "  [FAIL] ") (display label) (newline)
        (error "Assertion failed:" label))))

(define (assert-equal label expected actual)
  (set! *diag-tests-run* (+ *diag-tests-run* 1))
  (if (equal? expected actual)
      (begin
        (set! *diag-tests-passed* (+ *diag-tests-passed* 1))
        (display "  [PASS] ") (display label) (newline))
      (begin
        (display "  [FAIL] ") (display label)
        (display " -> Expected: ") (write expected)
        (display " but got: ") (write actual) (newline)
        (error "Assertion failed:" label))))

(display "=======================================================")
(newline)
(display " Starting Pass 000 (Compiler Context & Diagnostics) Test Suite")
(newline)
(display "=======================================================")
(newline)

;;; --- Group 1: Basic Context Management ---
(display "--- Group 1: Basic Context Management ---") (newline)

(reset-compiler-context!)
(assert-equal "initial pass is none" 'none (current-pass))
(assert-equal "initial toplevel is none" 'none (current-toplevel-name))
(assert-equal "initial form is none" 'none (current-form))

(set-current-pass! 'pass-130-lir)
(assert-equal "set-current-pass!" 'pass-130-lir (current-pass))

(set-current-toplevel-name! 'filter-evens)
(assert-equal "set-current-toplevel-name!" 'filter-evens (current-toplevel-name))

(set-current-form! '(car ls))
(assert-equal "set-current-form!" '(car ls) (current-form))

(reset-compiler-context!)
(assert-equal "reset pass to none" 'none (current-pass))
(assert-equal "reset toplevel to none" 'none (current-toplevel-name))
(assert-equal "reset form to none" 'none (current-form))

;;; --- Group 2: Safe Expression Truncation ---
(display "--- Group 2: Safe Expression Truncation ---") (newline)

(assert-equal "truncate atom number" 42 (truncate-expr-for-diagnostics 42))
(assert-equal "truncate atom symbol" 'foo (truncate-expr-for-diagnostics 'foo))
(assert-equal "truncate atom string" "hello" (truncate-expr-for-diagnostics "hello"))
(assert-equal "truncate small list" '(a b c) (truncate-expr-for-diagnostics '(a b c)))

;; List exceeding length 5 elements
(let ((long-list '(1 2 3 4 5 6 7 8 9 10)))
  (assert-equal "truncate long list" '(1 2 3 4 5 ...) (truncate-expr-for-diagnostics long-list)))

;; Nested list exceeding depth 3
(let ((deep-list '(a (b (c (d (e 42)))))))
  (assert-equal "truncate deep list" '(a (b (c (...)))) (truncate-expr-for-diagnostics deep-list)))

;;; --- Group 3: Structured Diagnostic Report & Error Functionality ---
(display "--- Group 3: Diagnostic Report & Error Interception ---") (newline)

(set-current-pass! 'pass-000-diagnostics-test)
(set-current-toplevel-name! 'my-function)
(set-current-form! '(car ls))

;; In test mode, suppress diagnostic stdout banner and abort-on-error
(set-car! *compiler-abort-on-error* #f)
(set-car! *compiler-suppress-diagnostics* #t)

;; Call compiler-diagnostic-report directly to ensure it prints without exception
(compiler-diagnostic-report "Simulated Unbound Variable" 'car)
(assert-true "diagnostic report executed cleanly" #t)

;; Call error with 2 arguments
(let ((ret1 (error "Variable resolution error" 'unbound-var)))
  (assert-equal "error with 2 args returns irritant" 'unbound-var ret1))

;;; --- Group 4: Re-entrant Error Handling Guard ---
(display "--- Group 4: Re-entrant Error Handling Guard ---") (newline)

(set-car! *compiler-in-error* #t)
(let ((re-ret (error "Recursive error simulation" 're-arg)))
  (assert-equal "recursive error returns argument safely" 're-arg re-ret))
(set-car! *compiler-in-error* #f)

;; Restore default abort-on-error and diagnostic output for subsequent tests
(set-car! *compiler-abort-on-error* #t)
(set-car! *compiler-suppress-diagnostics* #f)

;;; --- Group 5: Pipeline Integration Context Updates ---
(display "--- Group 5: Pipeline Integration Context Updates ---") (newline)

(reset-compiler-context!)
(let* ((input '((define (my-test-fun x) (+ x 1))
                (my-test-fun 10)))
       (hoisted (rewrite-top-level input)))
  (assert-equal "top-level hoist updates current toplevel" '%main (current-toplevel-name)))

(display "=======================================================")
(newline)
(display " All Pass 000 Tests Passed Successfully! (")
(display *diag-tests-passed*)
(display " / ")
(display *diag-tests-run*)
(display ")")
(newline)
(display "=======================================================")
(newline)
