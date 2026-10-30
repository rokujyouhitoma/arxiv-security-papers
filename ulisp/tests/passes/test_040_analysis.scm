;;; =======================================================================
;;; Unit Test Suite: ULisp Pass 040 (Scope & Free Variable Analysis)
;;; Conforms to Issue #572 & Nanopass Architecture Quality Standard
;;; =======================================================================

(define *pass-tests-passed* 0)
(define *pass-tests-failed* 0)

(define (assert-equal label expected actual)
  (if (equal? expected actual)
      (begin
        (set! *pass-tests-passed* (+ *pass-tests-passed* 1))
        (display "  [PASS] ") (display label) (newline))
      (begin
        (set! *pass-tests-failed* (+ *pass-tests-failed* 1))
        (display "  [FAIL] ") (display label)
        (display " -> Expected: ") (write expected)
        (display " but got: ") (write actual) (newline)
        (error "Assertion failed:" label))))

(display "=======================================================") (newline)
(display " Starting Pass 040 (Scope Analysis) Unit Test Suite") (newline)
(display "=======================================================") (newline)

;; 1. Open expression has free variables
(assert-equal "free vars in addition"
              '(x y)
              (free-vars '(+ x y) '()))

;; 2. Lambda parameter is bound
(assert-equal "bound parameter excluded"
              '(y)
              (free-vars '(lambda (x) (+ x y)) '()))

;; 3. Let-bound variable is bound
(assert-equal "let binding excluded"
              '(y)
              (free-vars '(let ((x 1)) (+ x y)) '()))

;; 4. Completely closed expression has 0 free vars
(assert-equal "closed lambda"
              '()
              (free-vars '(lambda (x) (+ x 1)) '()))

;; 5. Nested lambda shadowing
(assert-equal "shadowed lambda parameter"
              '()
              (free-vars '(lambda (x) (lambda (x) (+ x 1))) '()))

;; 6. Letrec mutual recursion free vars
(assert-equal "letrec internal self references bound"
              '(z)
              (free-vars '(letrec ((f (lambda (n) (if (= n 0) z (g (- n 1)))))
                                   (g (lambda (m) (f m))))
                            (f 10))
                         '()))

;;; --- Group 2: Static Arity Verification (Issue #629) ---
(display "--- Group 2: Static Arity Verification (Issue #629) ---") (newline)

;; 7. Valid expressions pass check-arity-all
(assert-equal "valid binary primitive +"
              '(+ 1 2)
              (check-arity-all '(+ 1 2)))

(assert-equal "valid unary primitive car"
              '(car '(1 2))
              (check-arity-all '(car '(1 2))))

(assert-equal "valid top-level function call"
              '(%program ((define add2 (lambda (x y) (+ x y)))) (add2 10 20))
              (check-arity-all '(%program ((define add2 (lambda (x y) (+ x y)))) (add2 10 20))))

(assert-equal "valid local function call"
              '(let ((sq (lambda (x) (* x x)))) (sq 5))
              (check-arity-all '(let ((sq (lambda (x) (* x x)))) (sq 5))))

;; 8. Arity mismatch error interception
;; Configure compiler to intercept errors without aborting
(set-car! *compiler-abort-on-error* #f)
(set-car! *compiler-suppress-diagnostics* #t)

(define *last-error-val* 'none)
(define orig-error error)
(define (error msg val)
  (set! *last-error-val* val)
  (orig-error msg val))

;; (car 1 2) -> unary primitive called with 2 args
(set! *last-error-val* 'none)
(check-arity-all '(car 1 2))
(assert-equal "car with 2 args triggers arity error" '(car 1 2) *last-error-val*)

;; (append 1 2 3) -> 2-arg builtin called with 3 args
(set! *last-error-val* 'none)
(check-arity-all '(append 1 2 3))
(assert-equal "append with 3 args triggers arity error" '(append 1 2 3) *last-error-val*)

;; (cons 1) -> 2-arg primitive called with 1 arg
(set! *last-error-val* 'none)
(check-arity-all '(cons 1))
(assert-equal "cons with 1 arg triggers arity error" '(cons 1) *last-error-val*)

;; Top-level function arity mismatch
(set! *last-error-val* 'none)
(check-arity-all '(%program ((define fn2 (lambda (a b) (+ a b)))) (fn2 1 2 3)))
(assert-equal "top-level arity mismatch triggers error" '(fn2 1 2 3) *last-error-val*)

;; Local function arity mismatch
(set! *last-error-val* 'none)
(check-arity-all '(let ((fn1 (lambda (x) (+ x 1)))) (fn1 10 20)))
(assert-equal "local arity mismatch triggers error" '(fn1 10 20) *last-error-val*)

;; Restore compiler error settings
(define error orig-error)
(set-car! *compiler-abort-on-error* #t)
(set-car! *compiler-suppress-diagnostics* #f)

(display "=======================================================") (newline)
(display " Pass 040: All ") (display *pass-tests-passed*) (display " tests passed!") (newline)
(display "=======================================================") (newline)
