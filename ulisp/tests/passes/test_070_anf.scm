;;; =======================================================================
;;; Unit Test Suite: ULisp Pass 070 (A-Normal Form / ANF Normalization)
;;; Conforms to Issue #572, Issue #594 & Nanopass Architecture Quality Standard
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

(define (assert-true label cond)
  (assert-equal label #t (if cond #t #f)))

(define (assert-false label cond)
  (assert-equal label #f (if cond #t #f)))

(display "=======================================================") (newline)
(display " Starting Pass 070 (ANF Normalization) Unit Test Suite") (newline)
(display "=======================================================") (newline)

;; 1. Immediate expressions remain unchanged
(assert-equal "atomic integer"
              42
              (anf-all 42))
(assert-true "atomic integer satisfies L_anf?"
             (L_anf? (anf-all 42)))

(assert-equal "atomic boolean"
              #t
              (anf-all #t))
(assert-true "atomic boolean satisfies L_anf?"
             (L_anf? (anf-all #t)))

(assert-equal "atomic symbol"
              'x
              (anf-all 'x))
(assert-true "atomic symbol satisfies L_anf?"
             (L_anf? (anf-all 'x)))

;; 2. Nested compound expressions are normalized with let-bindings
(let ((anf-res (anf-all '(+ (+ 1 2) 3))))
  (assert-true "anf introduces let for compound arg"
               (and (pair? anf-res) (eq? (car anf-res) 'let)))
  (assert-true "anf output conforms to L_anf?"
               (L_anf? anf-res)))

;; 3. If condition is normalized
(let ((anf-if (anf-all '(if (+ 1 2) 10 20))))
  (assert-true "anf normalizes if condition"
               (and (pair? anf-if) (eq? (car anf-if) 'let)))
  (assert-true "anf if output conforms to L_anf?"
               (L_anf? anf-if)))

;; 4. Procedure call arguments normalized
(let ((anf-call (anf-all '(f (+ a 1) (* b 2)))))
  (assert-true "anf normalizes call args into let chain"
               (and (pair? anf-call) (eq? (car anf-call) 'let)))
  (assert-true "anf call output conforms to L_anf?"
               (L_anf? anf-call)))

;; 5. Multi-level nested arithmetic
(let ((anf-nested (anf-all '(* (+ 1 2) (- 10 (/ 8 2))))))
  (assert-true "multi-level arithmetic normalizes to L_anf"
               (L_anf? anf-nested)))

;; 6. %program structure with top-level definitions
(let ((anf-prog (anf-all '(%program ((define x (+ 1 2)) (define (f y) (+ y 1))) (+ x (f 10))))))
  (assert-true "%program normalizes and conforms to L_anf?"
               (L_anf? anf-prog)))

;; 7. Schema Invariant Rejection Tests (L_anf? rejects un-normalized ASTs)
(assert-false "L_anf? rejects un-normalized compound call argument"
              (L_anf? '(+ (+ 1 2) 3)))

(assert-false "L_anf? rejects un-normalized compound if condition"
              (L_anf? '(if (+ 1 2) 10 20)))

(assert-false "L_anf? rejects un-normalized compound operator call"
              (L_anf? '(f (g x))))

(display "=======================================================") (newline)
(display " Pass 070: All ") (display *pass-tests-passed*) (display " tests passed!") (newline)
(display "=======================================================") (newline)
