;;; =======================================================================
;;; Unit Test Suite: ULisp Pass 029 (Dynamic Environment & Multiple Values)
;;; Conforms to Issue #574 & Nanopass Architecture Quality Standard
;;; =======================================================================




(test-begin "Pass 029 (Dynamic & Values Desugaring)")

;; 1. desugar-let-values
(let ((lv (desugar-let-values '(((a b) (values 1 2))) '((+ a b)))))
  (assert-true "desugar-let-values produces call-with-values" (pair? lv))
  (assert-equal "desugar-let-values root is call-with-values" 'call-with-values (car lv)))

;; 2. desugar-let*-values
(let ((lsv (desugar-let*-values '(((a b) (values 1 2)) ((c) 3)) '((+ a b c)))))
  (assert-true "desugar-let*-values produces call-with-values" (pair? lsv))
  (assert-equal "desugar-let*-values root is call-with-values" 'call-with-values (car lsv)))

;; 3. desugar-guard
(let ((g (desugar-guard '(e ((else 0))) '((/ 1 0)))))
  (assert-true "desugar-guard produces %with-handler" (pair? g))
  (assert-equal "desugar-guard root is %with-handler" '%with-handler (car g)))

;; 4. desugar-parameterize
(let ((p (desugar-parameterize '((param1 100)) '((do-something)))))
  (assert-true "desugar-parameterize produces let" (pair? p))
  (assert-equal "desugar-parameterize root is let" 'let (car p)))

;; 5. desugar-define-values
(let ((dv (desugar-define-values '(a b) '(values 1 2) '((+ a b)))))
  (assert-true "desugar-define-values produces let-values" (pair? dv))
  (assert-equal "desugar-define-values root is let-values" 'let-values (car dv)))

(let ((dv-single (desugar-define-values '(x) '(values 42) '())))
  (assert-true "desugar-define-values single produces call-with-values" (pair? dv-single))
  (assert-equal "desugar-define-values single root is call-with-values" 'call-with-values (car dv-single)))

(let ((dyn-res (desugar-dynamic '(begin (define-values (x y) (values 10 20)) (+ x y)))))
  (assert-true "desugar-dynamic expands begin define-values" (pair? dyn-res))
  (assert-equal "desugar-dynamic expands to %call-with-values" '%call-with-values (car dyn-res)))

;;; -----------------------------------------------------------------------
;;; Section 6: Pass 029 1-Line Picopass Direct S-Expression Unit Tests (DSN-33-01 T4.1)
;;; -----------------------------------------------------------------------

;; 6. rule-desugar-let-values
(let ((res (rule-desugar-let-values '(let-values (((a b) (values 1 2))) (+ a b)))))
  (assert-true "rule-desugar-let-values produces call-with-values" (pair? res))
  (assert-equal "rule-desugar-let-values root" 'call-with-values (car res)))

;; 7. rule-desugar-define-values
(let ((res (rule-desugar-define-values '(define-values (x y) (values 1 2)))))
  (assert-true "rule-desugar-define-values produces call-with-values" (pair? res))
  (assert-equal "rule-desugar-define-values root" 'call-with-values (car res)))

;; 8. rule-desugar-guard
(let ((res (rule-desugar-guard '(guard (e (else 0)) (/ 1 0)))))
  (assert-true "rule-desugar-guard produces %with-handler" (pair? res))
  (assert-equal "rule-desugar-guard root" '%with-handler (car res)))

;; 9. rule-desugar-parameterize
(let ((res (rule-desugar-parameterize '(parameterize ((p 1)) (p)))))
  (assert-true "rule-desugar-parameterize produces let" (pair? res))
  (assert-equal "rule-desugar-parameterize root" 'let (car res)))

;; 10. rule-desugar-delay
(let ((res (rule-desugar-delay '(delay (+ 1 2)))))
  (assert-true "rule-desugar-delay produces promise" (pair? res))
  (assert-equal "rule-desugar-delay root" '%%make-promise (car res)))

;; 11. rule-desugar-parameter-ops
(assert-equal "rule-desugar-parameter-ops 1 arg"
              '(make-parameter-1 100)
              (rule-desugar-parameter-ops '(make-parameter 100)))

;; 12. rule-desugar-values
(assert-equal "rule-desugar-values 2 args"
              '(%values 1 2)
              (rule-desugar-values '(values 1 2)))

(assert-equal "rule-desugar-values 1 arg is identity"
              42
              (rule-desugar-values '(values 42)))

(assert-equal "rule-desugar-values call-with-values"
              '(%call-with-values producer consumer)
              (rule-desugar-values '(call-with-values producer consumer)))

;; 13. rule-desugar-error-assume
(let ((res (rule-desugar-error-assume '(error "msg" 1 2))))
  (assert-true "rule-desugar-error-assume produces raise" (pair? res))
  (assert-equal "rule-desugar-error-assume root" 'raise (car res)))

(assert-equal "rule-desugar-error-assume with-exception-handler"
              '(%with-handler handler thunk)
              (rule-desugar-error-assume '(with-exception-handler handler thunk)))

;; 14. atto-no-unexpanded-let-syntax (invariant verification)
(assert-equal "atto-no-unexpanded-let-syntax passes normal expr"
              #t
              (atto-no-unexpanded-let-syntax '(+ 1 2)))

;; 15. Full Nanopass desugar-dynamic with fuse-rules
(let ((res (desugar-dynamic '(delay (+ 1 2)))))
  (assert-true "desugar-dynamic on delay produces promise" (pair? res))
  (assert-equal "desugar-dynamic on delay root" '%%make-promise (car res)))

(test-end "Pass 029 (Dynamic & Values Desugaring)")
