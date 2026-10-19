;;; =======================================================================
;;; Unit Test Suite: ULisp Pass 110 (Explicit Closure Conversion)
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
(display " Starting Pass 110 (Closure Conversion) Unit Test Suite") (newline)
(display "=======================================================") (newline)

;; 1. Top-level program wrapping
(let ((res (closure-convert 42)))
  (assert-equal "program tag" '%program (car res))
  (assert-equal "main expr" 42 (caddr res)))

;; 2. Lambda lifting to %function
(let* ((res (closure-convert '(lambda (x) (+ x 1))))
       (funcs (cadr res))
       (main-expr (caddr res)))
  (assert-equal "lifts 1 function" 1 (length funcs))
  (assert-equal "function tag" '%function (caar funcs))
  (assert-equal "main is %make-closure" '%make-closure (car main-expr)))

;; 3. Free variable capture via %closure-ref
(let* ((res (closure-convert '(let ((y 10)) (lambda (x) (+ x y)))))
       (funcs (cadr res)))
  (assert-equal "lifts inner lambda" 1 (length funcs))
  (let ((fn-body (cadddr (car funcs))))
    ;; fn-body should contain %closure-ref for y
    (assert-true "body references closure environment"
                 (let rec ((e fn-body))
                   (cond
                     ((not (pair? e)) #f)
                     ((eq? (car e) '%closure-ref) #t)
                     (else (or (rec (car e)) (rec (cdr e)))))))))

;; 4. Quoted symbol literal preservation (static interning without string->symbol)
(let ((res (closure-convert ''a)))
  (assert-equal "preserves quoted symbol" ''a (caddr res)))

(display "=======================================================") (newline)
(display " Pass 110: All ") (display *pass-tests-passed*) (display " tests passed!") (newline)
(display "=======================================================") (newline)
