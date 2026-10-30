;;; =======================================================================
;;; Unit Test Suite: ULisp Pass 026 (Constructor Desugaring)
;;; Conforms to Issue #574 & Nanopass Architecture Quality Standard
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
(display " Starting Pass 026 (Constructor Desugaring) Unit Test") (newline)
(display "=======================================================") (newline)

;; 1. desugar-list
(assert-equal "desugar-list empty"
              ''()
              (desugar-list '()))

(assert-equal "desugar-list 2 elements"
              '(cons 1 (cons 2 '()))
              (desugar-list '(1 2)))

;; 2. desugar-string & desugar-string-append
(let ((s-empty (desugar-string '())))
  (assert-true "desugar-string empty returns let" (and (pair? s-empty) (eq? (car s-empty) 'let))))

(let ((s-res (desugar-string '(#\a #\b))))
  (assert-true "desugar-string returns let" (and (pair? s-res) (eq? (car s-res) 'let))))

(assert-equal "desugar-string-append empty"
              ""
              (desugar-string-append '()))

(assert-equal "desugar-string-append 1 element"
              "hello"
              (desugar-string-append '("hello")))

(assert-equal "desugar-string-append 2 elements"
              '(string-append2 "hello" "world")
              (desugar-string-append '("hello" "world")))

;; 3. desugar-vector & vector-append
(let ((v-res (desugar-vector '(1 2))))
  (assert-true "desugar-vector returns let" (and (pair? v-res) (eq? (car v-res) 'let))))

(assert-equal "desugar-vector-append empty"
              '(%make-vector 0)
              (desugar-vector-append '()))

(assert-equal "desugar-vector-append 2 elements"
              '(vector-append2 v1 v2)
              (desugar-vector-append '(v1 v2)))

;; 4. desugar-bytevector & bytevector-append
(let ((bv-res (desugar-bytevector '(65 66))))
  (assert-true "desugar-bytevector returns let" (and (pair? bv-res) (eq? (car bv-res) 'let))))

(assert-equal "desugar-bytevector-append empty"
              '(%make-bytevector 0)
              (desugar-bytevector-append '()))

(assert-equal "desugar-bytevector-append 2 elements"
              '(bytevector-append2 b1 b2)
              (desugar-bytevector-append '(b1 b2)))

(display "=======================================================") (newline)
(display " Pass 026: All ") (display *pass-tests-passed*) (display " tests passed!") (newline)
(display "=======================================================") (newline)
