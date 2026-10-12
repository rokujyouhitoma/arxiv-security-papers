;;; =======================================================================
;;; Unit Test Suite: ULisp Pass 05b (S-RTyper & Unboxing Lowering)
;;; Conforms to DSN-33 Architecture Specification & Issue #518
;;; =======================================================================

(define *rtyper-tests-run* 0)
(define *rtyper-tests-passed* 0)

(define (assert-true label cond)
  (set! *rtyper-tests-run* (+ *rtyper-tests-run* 1))
  (if cond
      (begin
        (set! *rtyper-tests-passed* (+ *rtyper-tests-passed* 1))
        (display "  [PASS] ") (display label) (newline))
      (begin
        (display "  [FAIL] ") (display label) (newline)
        (error "Assertion failed:" label))))

(define (assert-equal label expected actual)
  (set! *rtyper-tests-run* (+ *rtyper-tests-run* 1))
  (if (type-equal? expected actual)
      (begin
        (set! *rtyper-tests-passed* (+ *rtyper-tests-passed* 1))
        (display "  [PASS] ") (display label) (newline))
      (begin
        (display "  [FAIL] ") (display label)
        (display " -> Expected: ") (write expected)
        (display " but got: ") (write actual) (newline)
        (error "Assertion failed:" label))))

(display "=======================================================")
(newline)
(display " Starting Pass 05b (S-RTyper) Detailed Test Suite")
(newline)
(display "=======================================================")
(newline)

;; Test 1: Binary operators lowering on constants
(assert-equal "lower + constants" '(%raw-add 10 20) (rtyper-binop '+ 10 20 '()))
(assert-equal "lower - constants" '(%raw-sub 40 15) (rtyper-binop '- 40 15 '()))
(assert-equal "lower * constants" '(%raw-mul 6 7) (rtyper-binop '* 6 7 '()))

;; Test 2: Binary operators on raw variables
(assert-equal "lower + raw vars" '(%raw-add i sum) (rtyper-binop '+ 'i 'sum '(i sum)))
(assert-equal "lower - raw vars" '(%raw-sub n 1) (rtyper-binop '- 'n 1 '(n)))
(assert-equal "lower * raw vars" '(%raw-mul acc x) (rtyper-binop '* 'acc 'x '(acc x)))

;; Test 3: Preserve non-raw dynamic operations
(assert-equal "preserve dynamic +" '(+ a b) (rtyper-binop '+ 'a 'b '()))
(assert-equal "preserve dynamic -" '(- a b) (rtyper-binop '- 'a 'b '()))
(assert-equal "preserve dynamic *" '(* a b) (rtyper-binop '* 'a 'b '()))

;; Test 4: Boundary boxing
(assert-equal "box raw return variable" '(%box-fixnum res) (box-raw-exit 'res '(res) 'loop))
(assert-equal "leave recursive call unboxed" '(loop 1 2) (box-raw-exit '(loop 1 2) '(res) 'loop))
(assert-equal "leave constant unboxed" 42 (box-raw-exit 42 '(res) 'loop))

;; Test 5: End-to-end unboxed Fibonacci loop
(reset-type-annotations!)
(let* ((orig (desugar-all '(let loop ((i 0) (a 0) (b 1))
                            (if (< i 20)
                                (loop (+ i 1) b (+ a b))
                                a))))
       (anf (anf-all (cp0-optimize orig)))
       (ann (annotate-all anf))
       (typed (rtyper-all ann)))
  (assert-true "fib loop typed is pair" (pair? typed))
  ;; Check that %raw-add is present in the lowered loop
  (assert-true "fib loop uses %raw-add"
               (let rec ((e typed))
                 (cond
                   ((not (pair? e)) #f)
                   ((eq? (car e) '%raw-add) #t)
                   (else (or (rec (car e)) (rec (cdr e)))))))
  ;; Check that %box-fixnum is inserted at exit
  (assert-true "fib loop uses %box-fixnum at exit"
               (let rec ((e typed))
                 (cond
                   ((not (pair? e)) #f)
                   ((eq? (car e) '%box-fixnum) #t)
                   (else (or (rec (car e)) (rec (cdr e))))))))

;; Test 6: End-to-end Factorial loop
(reset-type-annotations!)
(let* ((orig (desugar-all '(let loop ((n 10) (acc 1))
                            (if (<= n 1)
                                acc
                                (loop (- n 1) (* acc n))))))
       (anf (anf-all (cp0-optimize orig)))
       (ann (annotate-all anf))
       (typed (rtyper-all ann)))
  (assert-true "fact loop typed is pair" (pair? typed))
  (assert-true "fact loop uses %raw-sub"
               (let rec ((e typed))
                 (cond
                   ((not (pair? e)) #f)
                   ((eq? (car e) '%raw-sub) #t)
                   (else (or (rec (car e)) (rec (cdr e)))))))
  (assert-true "fact loop uses %raw-mul"
               (let rec ((e typed))
                 (cond
                   ((not (pair? e)) #f)
                   ((eq? (car e) '%raw-mul) #t)
                   (else (or (rec (car e)) (rec (cdr e)))))))
  (assert-true "fact loop uses %box-fixnum at exit"
               (let rec ((e typed))
                 (cond
                   ((not (pair? e)) #f)
                   ((eq? (car e) '%box-fixnum) #t)
                   (else (or (rec (car e)) (rec (cdr e))))))))

(display "=======================================================")
(newline)
(display " All ") (display *rtyper-tests-passed*)
(display " Pass 05b (S-RTyper) unit tests PASSED! (0 failures)")
(newline)
(display "=======================================================")
(newline)
