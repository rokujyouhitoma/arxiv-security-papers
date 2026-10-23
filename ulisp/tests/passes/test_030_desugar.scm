;;; =======================================================================
;;; Unit Test Suite: ULisp Pass 030 (Desugaring)
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

(define (assert-true label cond)
  (assert-equal label #t (if cond #t #f)))

(display "=======================================================") (newline)
(display " Starting Pass 030 (Desugaring) Unit Test Suite") (newline)
(display "=======================================================") (newline)

;; 1. and desugaring
(assert-equal "and 0 args"
              #t
              (desugar-all '(and)))

(assert-equal "and 1 arg"
              42
              (desugar-all '(and 42)))

(assert-equal "and 2 booleans"
              '(if #t #t #f)
              (desugar-all '(and #t #t)))

(assert-equal "and 2 args"
              '(if #t 42 #f)
              (desugar-all '(and #t 42)))

(assert-equal "and multi args"
              '(if 1 (if 2 3 #f) #f)
              (desugar-all '(and 1 2 3)))

;; 2. or desugaring
(assert-equal "or 0 args"
              #f
              (desugar-all '(or)))

(assert-equal "or 1 arg"
              42
              (desugar-all '(or 42)))

(let ((res (desugar-all '(or #f 42))))
  (assert-true "or produces let binding" (pair? res))
  (assert-equal "or root tag is let" 'let (car res)))

;; 3. let* desugaring
(assert-equal "let* nested let"
              '(let ((x 1)) (let ((y 2)) (+ x y)))
              (desugar-all '(let* ((x 1) (y 2)) (+ x y))))

;; 4. cond desugaring
(assert-equal "cond with else"
              '(if (= 1 2) (begin 10) (begin 20))
              (desugar-all '(cond ((= 1 2) 10) (else 20))))

;; 5. list desugaring
(assert-equal "list desugaring to cons"
              '(cons 1 (cons 2 '()))
              (desugar-all '(list 1 2)))

;; 6. named let desugaring
(let ((res (desugar-all '(let loop ((n 10)) (if (= n 0) 0 (loop (- n 1)))))))
  (assert-equal "named let expands to letrec" 'letrec (car res)))

;; 7. let-values desugaring
(let ((res (desugar-all '(let-values (((a b) (values 1 2))) (+ a b)))))
  (assert-equal "let-values expands to %call-with-values" '%call-with-values (car res)))

;; 8. do desugaring
(let ((res (desugar-all '(do ((i 0 (+ i 1))) ((= i 10) i)))))
  (assert-true "do desugars to pair" (pair? res))
  (assert-equal "do expands to letrec" 'letrec (car res)))

;; 9. define-values desugaring
(let ((res (desugar-all '(begin (define-values (a b) (values 1 2)) (+ a b)))))
  (assert-true "define-values in begin desugars to pair" (pair? res))
  (assert-equal "define-values in begin expands to %call-with-values" '%call-with-values (car res)))

;; 10. internal define variables desugaring
(let ((res (desugar-all '(begin (define x 10) (define y 20) (+ x y)))))
  (assert-equal "internal define variables root tag" 'let (car res))
  (assert-equal "internal define variable x" '((x 10)) (cadr res))
  (assert-equal "internal define variable y" 'let (car (caddr res))))

;; 11. internal define procedure desugaring
(let ((res (desugar-all '(begin (define (foo x) (* x 2)) (foo 21)))))
  (assert-equal "internal define procedure root tag" 'letrec (car res))
  (assert-equal "internal define procedure name" 'foo (caar (cadr res))))

;; 12. splicing begin desugaring
(let ((res (desugar-all '(begin (begin (define x 10)) x))))
  (assert-equal "splicing begin with internal define" 'let (car res)))

(display "=======================================================") (newline)
(display " Pass 030: All ") (display *pass-tests-passed*) (display " tests passed!") (newline)
(display "=======================================================") (newline)
