;;; =======================================================================
;;; Unit Test Suite: ULisp Pass 027 (Conditionals Desugaring)
;;; Conforms to Issue #574 & Nanopass Architecture Quality Standard
;;; Refactored to include 1-line Picopass S-expression tests per Issue #762 (DSN-33-01 T4.1)
;;; =======================================================================




(test-begin "Pass 027 (Conditionals Desugaring)")

;; 1. desugar-and
(assert-equal "desugar-and empty"
              #t
              (desugar-and '()))

(assert-equal "desugar-and 1 arg"
              42
              (desugar-and '(42)))

(assert-equal "desugar-and 2 args"
              '(if #t 42 #f)
              (desugar-and '(#t 42)))

;; 2. desugar-or
(assert-equal "desugar-or empty"
              #f
              (desugar-or '()))

(assert-equal "desugar-or 1 arg"
              42
              (desugar-or '(42)))

(let ((res (desugar-or '(#f 42))))
  (assert-true "desugar-or 2 args produces let" (pair? res))
  (assert-equal "desugar-or root is let" 'let (car res)))

;; 3. desugar-cond
(assert-equal "desugar-cond empty"
              #f
              (desugar-cond '()))

(assert-equal "desugar-cond with else"
              '(if (= 1 2) (begin 10) (begin 20))
              (desugar-cond '(((= 1 2) 10) (else 20))))

;; 4. desugar-case
(let ((case-res (desugar-case 'x '(((1 2) (display "one or two")) (else (display "other"))))))
  (assert-true "desugar-case produces let" (pair? case-res))
  (assert-equal "desugar-case root is let" 'let (car case-res)))

;;; -----------------------------------------------------------------------
;;; Section 5: Pass 027 1-Line Picopass Direct S-Expression Unit Tests (DSN-33-01 T4.1)
;;; -----------------------------------------------------------------------

;; 5. rule-desugar-and
(assert-equal "rule-desugar-and direct call"
              '(if a b #f)
              (rule-desugar-and '(and a b)))

(assert-equal "rule-desugar-and unmatching form returns #f"
              #f
              (rule-desugar-and '(or a b)))

;; 6. rule-desugar-or
(let ((or-res (rule-desugar-or '(or a b))))
  (assert-true "rule-desugar-or produces let" (pair? or-res))
  (assert-equal "rule-desugar-or root is let" 'let (car or-res)))

;; 7. rule-desugar-cond
(assert-equal "rule-desugar-cond direct call"
              '(if (= x 1) (begin 10) (begin 20))
              (rule-desugar-cond '(cond ((= x 1) 10) (else 20))))

;; 8. rule-desugar-case
(let ((c-res (rule-desugar-case '(case x ((1) 10) (else 20)))))
  (assert-true "rule-desugar-case produces let" (pair? c-res))
  (assert-equal "rule-desugar-case root is let" 'let (car c-res)))

;; 9. rule-desugar-chain-cmp
(let ((cmp-res (rule-desugar-chain-cmp '(char<? a b c))))
  (assert-true "rule-desugar-chain-cmp produces let" (pair? cmp-res))
  (assert-equal "rule-desugar-chain-cmp root is let" 'let (car cmp-res)))

;; 10. Full Nanopass desugar-conditionals with fuse-rules
(assert-equal "desugar-conditionals on cond"
              '(if (= a 1) (begin 10) (begin 20))
              (desugar-conditionals '(cond ((= a 1) 10) (else 20))))

(assert-equal "desugar-conditionals on nested and"
              '(if x (if y z #f) #f)
              (desugar-conditionals '(and x (and y z))))

(test-end "Pass 027 (Conditionals Desugaring)")
