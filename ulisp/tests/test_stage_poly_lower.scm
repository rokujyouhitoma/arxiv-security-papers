;;; =======================================================================
;;; Test Suite: Stage-Polymorphic Lowering Nanopass (stage-poly-lower)
;;; Conforms to DSN-33-03 §2.1, §3.3, §6.2 & Issue #879
;;; =======================================================================

(display "\n=== [Test Suite: Stage-Poly Lowering Nanopass (Issue #879)] ===\n")

;;; Helper to recursively verify absence of meta-stage constructs
(define (has-meta-syntax? ast)
  (cond
    ((not (pair? ast)) #f)
    ((memq (car ast) '(stage-now stage-later stage-lift stage-quasiquote)) #t)
    (else
     (or (has-meta-syntax? (car ast))
         (has-meta-syntax? (cdr ast))))))

;;; -----------------------------------------------------------------------
;;; Group 1: stage-now Elimination & Pure Constant Folding
;;; -----------------------------------------------------------------------
(display "\n--- Group 1: stage-now Elimination & Pure Constant Folding ---\n")

;; 1.1 Simple arithmetic in stage-now
(let* ((expr '(stage-now (+ 10 (* 2 5))))
       (res (stage-poly-lower expr '())))
  (assert-equal "1.1 Result is atom-value 20" '(atom-value 20) res)
  (assert-equal "1.1 No meta-syntax remaining" #f (has-meta-syntax? res)))

;; 1.2 stage-now within dynamic addition
(let* ((expr '(+ x (stage-now (* 3 7))))
       (env (list (cons 'x (make-dynamic-val 'unknown 'x #f #f))))
       (res (stage-poly-lower expr env)))
  (assert-equal "1.2 Form is let-anf with folded constant 21" 'let-anf (car res))
  (assert-equal "1.2 Right-hand side is (+ x 21)" '(+ x 21) (cadar (cadr res)))
  (assert-equal "1.2 No meta-syntax remaining" #f (has-meta-syntax? res)))

;;; -----------------------------------------------------------------------
;;; Group 2: stage-later Dynamic Residualization
;;; -----------------------------------------------------------------------
(display "\n--- Group 2: stage-later Dynamic Residualization ---\n")

(let* ((expr '(stage-later (+ a b)))
       (env (list (cons 'a (make-dynamic-val 'unknown 'a #f #f))
                  (cons 'b (make-dynamic-val 'unknown 'b #f #f))))
       (res (stage-poly-lower expr env)))
  (assert-equal "2.1 Residualized as let-anf" 'let-anf (car res))
  (assert-equal "2.1 Body evaluates (+ a b)" '(+ a b) (cadar (cadr res)))
  (assert-equal "2.1 No meta-syntax remaining" #f (has-meta-syntax? res)))

;;; -----------------------------------------------------------------------
;;; Group 3: stage-lift Static Promotion & CSP Protection
;;; -----------------------------------------------------------------------
(display "\n--- Group 3: stage-lift Static Promotion & CSP Protection ---\n")

;; 3.1 Legitimate static value lift
(let* ((expr '(stage-lift (+ 100 200)))
       (res (stage-poly-lower expr '())))
  (assert-equal "3.1 Lifted static constant is atom-value 300" '(atom-value 300) res)
  (assert-equal "3.1 No meta-syntax remaining" #f (has-meta-syntax? res)))

;; 3.2 Prohibited mutable box lift triggers CSP error
(let* ((m-box (cons '%box (cons 99 '())))
       (env (list (cons 'm (make-static-val 'box m-box #f #f))))
       (expr '(stage-lift m))
       (res (stage-poly-lower expr env)))
  (assert-equal "3.2 Mutable lift blocked as CSP error" #t (stage-csp-error? res))
  (assert-equal "3.2 Error rule is illegal-mutable-lift" 'illegal-mutable-lift (stage-csp-error-reason res)))

;;; -----------------------------------------------------------------------
;;; Group 4: Conditionals & Dead Branch Elimination in Lowering
;;; -----------------------------------------------------------------------
(display "\n--- Group 4: Conditionals & Dead Branch Elimination ---\n")

;; 4.1 Static conditional elimination
(let* ((expr '(if (stage-now (< 1 2))
                  (+ x 1)
                  (/ 1 0)))
       (env (list (cons 'x (make-dynamic-val 'unknown 'x #f #f))))
       (res (stage-poly-lower expr env)))
  (assert-equal "4.1 True branch selected" 'let-anf (car res))
  (assert-equal "4.1 Dead exception branch eliminated" '(+ x 1) (cadar (cadr res)))
  (assert-equal "4.1 No meta-syntax remaining" #f (has-meta-syntax? res)))

;; 4.2 Dynamic conditional residualization
(let* ((expr '(if flag
                  (stage-now (+ 5 5))
                  (stage-now (* 5 5))))
       (env (list (cons 'flag (make-dynamic-val 'boolean 'flag #f #f))))
       (res (stage-poly-lower expr env)))
  (assert-equal "4.2 Residual if emitted" 'if (car res))
  (assert-equal "4.2 Test expression" 'flag (cadr res))
  (assert-equal "4.2 Then branch folded to atom-value 10" '(atom-value 10) (caddr res))
  (assert-equal "4.2 Else branch folded to atom-value 25" '(atom-value 25) (cadddr res))
  (assert-equal "4.2 No meta-syntax remaining" #f (has-meta-syntax? res)))

;;; -----------------------------------------------------------------------
;;; Group 5: Complete Meta-Syntax Eradication Assurance
;;; -----------------------------------------------------------------------
(display "\n--- Group 5: Complete Meta-Syntax Eradication Assurance ---\n")

(let* ((complex-expr
        '(let ((k (stage-now (+ 2 3))))
           (if (> k 0)
               (stage-later (+ y (stage-lift (* k 10))))
               (stage-later (- y 1)))))
       (env (list (cons 'y (make-dynamic-val 'unknown 'y #f #f))))
       (res (stage-poly-lower complex-expr env)))
  (assert-equal "5.1 Fully lowered" 'let-anf (car res))
  (assert-equal "5.1 Completely purged of meta-syntax" #f (has-meta-syntax? res)))

(display "\n[RESULT] All Stage-Poly Lowering Nanopass tests PASSED!\n")
