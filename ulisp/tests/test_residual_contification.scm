;;; =======================================================================
;;; Test Suite: Residual Function Contification Guarantees (Issue #882)
;;; Conforms to DSN-33-03 §5.4
;;; =======================================================================

(display "\n=== [Test Suite: Residual Function Contification Guarantees (Issue #882)] ===\n\n")

;;; -----------------------------------------------------------------------
;;; Group 1: Closed Call Graph & Tail Recursion Verification
;;; -----------------------------------------------------------------------
(display "--- Group 1: Closed Call Graph & Tail Recursion Verification ---\n")

;; Single self-recursive tail loop
(let ((fn-name 'loop-step)
      (fn-body '(if (<= n 0) acc (loop-step (- n 1) (+ acc n))))
      (in-body '(loop-step 10 0)))
  (assert-equal "1.1 Self-recursive tail loop meets Contification guarantees"
                #t
                (verify-residual-contification-guarantees fn-name fn-body in-body)))

;; Mutual recursive loop pair
(let ((letrec-ast '(letrec ((even? (lambda (n) (if (= n 0) #t (odd? (- n 1)))))
                            (odd?  (lambda (n) (if (= n 0) #f (even? (- n 1))))))
                     (even? 42))))
  (assert-equal "1.2 Mutual recursive letrec meets Contification guarantees"
                #t
                (verify-letrec-contifiable-guarantees letrec-ast)))

;;; -----------------------------------------------------------------------
;;; Group 2: Escape Detection & Rejection
;;; -----------------------------------------------------------------------
(display "\n--- Group 2: Escape Detection & Rejection ---\n")

;; Escaping function passed as an argument
(let ((fn-name 'bad-fn)
      (fn-body '(+ x 1))
      (in-body '(map bad-fn '(1 2 3)))) ; bad-fn escapes as argument to map!
  (assert-equal "2.1 Escaping function in argument position correctly rejected"
                #f
                (verify-residual-contification-guarantees fn-name fn-body in-body)))

;; Escaping function in data structure
(let ((letrec-escaping '(letrec ((helper (lambda (x) (+ x 1))))
                          (cons helper '()))))
  (assert-equal "2.2 Letrec with data-structure escape correctly rejected"
                #f
                (verify-letrec-contifiable-guarantees letrec-escaping)))

;;; -----------------------------------------------------------------------
;;; Group 3: Pass 100 Contification Transformation Verification
;;; -----------------------------------------------------------------------
(display "\n--- Group 3: Pass 100 Contification Transformation ---\n")

(let* ((orig-ast '(letrec ((loop (lambda (n acc)
                                   (if (<= n 0) acc (loop (- n 1) (+ acc n))))))
                    (loop 10 0)))
       (contified (contify-expr orig-ast)))
  (assert-equal "3.1 Pass 100 transforms letrec to %cont-fun"
                '%cont-fun
                (car contified))
  (assert-equal "3.2 %cont-fun function name is loop"
                'loop
                (cadr contified)))

(display "\n[RESULT] All Residual Function Contification Guarantee tests PASSED!\n")
