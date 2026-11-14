;;; =======================================================================
;;; Unit Test Suite: ULisp Pass 026 (Constructor Desugaring)
;;; Conforms to Issue #574 & Nanopass Architecture Quality Standard
;;; Refactored to include 1-line Picopass S-expression tests per Issue #762 (DSN-33-01 T4.1)
;;; =======================================================================




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

;;; -----------------------------------------------------------------------
;;; Section 5: Pass 026 1-Line Picopass Direct S-Expression Unit Tests (DSN-33-01 T4.1)
;;; -----------------------------------------------------------------------

;; 5. rule-desugar-list
(assert-equal "rule-desugar-list direct call"
              '(cons 1 (cons 2 '()))
              (rule-desugar-list '(list 1 2)))

(assert-equal "rule-desugar-list unmatching form returns #f"
              #f
              (rule-desugar-list '(foo 1 2)))

;; 6. rule-desugar-vector
(assert-equal "rule-desugar-vector make-vector"
              '(%make-vector 10)
              (rule-desugar-vector '(make-vector 10)))

(assert-equal "rule-desugar-vector vector-append"
              '(vector-append2 a b)
              (rule-desugar-vector '(vector-append a b)))

;; 7. rule-desugar-bytevector
(assert-equal "rule-desugar-bytevector make-bytevector"
              '(%make-bytevector 16)
              (rule-desugar-bytevector '(make-bytevector 16)))

(assert-equal "rule-desugar-bytevector bytevector-append"
              '(bytevector-append2 x y)
              (rule-desugar-bytevector '(bytevector-append x y)))

;; 8. rule-desugar-string-ops
(assert-equal "rule-desugar-string-ops string-append"
              '(string-append2 "foo" "bar")
              (rule-desugar-string-ops '(string-append "foo" "bar")))

;; 9. rule-desugar-math-variadic
(assert-equal "rule-desugar-math-variadic gcd 2 args"
              '(gcd-2 6 9)
              (rule-desugar-math-variadic '(gcd 6 9)))

(assert-equal "rule-desugar-math-variadic lcm 2 args"
              '(lcm-2 4 6)
              (rule-desugar-math-variadic '(lcm 4 6)))

(assert-equal "rule-desugar-math-variadic max 2 args"
              '(max-2 10 20)
              (rule-desugar-math-variadic '(max 10 20)))

(assert-equal "rule-desugar-math-variadic min 2 args"
              '(min-2 10 20)
              (rule-desugar-math-variadic '(min 10 20)))

;; 10. rule-desugar-format
(assert-equal "rule-desugar-format"
              '(%format "val: ~a" (list 42))
              (rule-desugar-format '(format "val: ~a" 42)))

;; 11. rule-desugar-cxr
(assert-equal "rule-desugar-cxr caar"
              '(car (car x))
              (rule-desugar-cxr '(caar x)))

(assert-equal "rule-desugar-cxr cadr"
              '(car (cdr x))
              (rule-desugar-cxr '(cadr x)))

(assert-equal "rule-desugar-cxr cdddr"
              '(cdr (cdr (cdr x)))
              (rule-desugar-cxr '(cdddr x)))

;; 12. Full Nanopass desugar-constructors with fuse-rules
(assert-equal "desugar-constructors on list"
              '(cons 1 (cons 2 '()))
              (desugar-constructors '(list 1 2)))

(assert-equal "desugar-constructors on cadr"
              '(car (cdr x))
              (desugar-constructors '(cadr x)))

(assert-equal "desugar-constructors on nested list and gcd"
              '(cons (gcd-2 10 20) (cons 30 '()))
              (desugar-constructors '(list (gcd 10 20) 30)))

(display "=======================================================") (newline)
(display " Pass 026: All ") (display *pass-tests-passed*) (display " tests passed!") (newline)
(display "=======================================================") (newline)
