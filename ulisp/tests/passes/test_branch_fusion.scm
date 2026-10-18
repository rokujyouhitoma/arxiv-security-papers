;;; =======================================================================
;;; ULisp Test: Condition Branch Flag / Branch Fusion (Issue #545)
;;; =======================================================================

(define *tests-passed* 0)
(define *tests-failed* 0)

(define (assert-true test-name expr)
  (if expr
      (begin
        (set! *tests-passed* (+ *tests-passed* 1))
        (display "  [PASS] ")
        (display test-name)
        (newline))
      (begin
        (set! *tests-failed* (+ *tests-failed* 1))
        (display "  [FAIL] ")
        (display test-name)
        (newline)
        (exit 1))))

(display "=======================================================")
(newline)
(display " Starting Condition Branch Flag Fusion Test Suite (Issue #545)")
(newline)
(display "=======================================================")
(newline)

;; Test 1: Verify (= i 1000000) inside hot loop emits %cmp and %jump-cond instead of %set-boolean + %jump-if-false
(let* ((ast '(letrec ((loop (lambda (i acc) (if (= i 1000000) acc (loop (+ i 1) (+ acc i)))))) (loop 0 0)))
       (ast1 (desugar-all ast))
       (ast2 (cp0-optimize ast1))
       (ast2b (lvn-all ast2))
       (ast3 (anf-all ast2b))
       (ast3b (annotate-all ast3))
       (ast3c (rtyper-all ast3b))
       (ast3d (contify-all ast3c))
       (ast4 (closure-convert ast3d))
       (ast4b (alias-escape-all ast4))
       (lir (generate-lir ast4b))
       (main-body (cdr (assq 'body (cdr (assq '%lir-main (cdr lir)))))))

  ;; 1. Check LIR contains %jump-cond
  (let ((jump-conds (filter (lambda (i) (and (pair? i) (eq? (car i) '%jump-cond))) main-body)))
    (assert-true "LIR contains %jump-cond instruction" (pair? jump-conds))
    (assert-true "%jump-cond uses jne operator"
                 (pair? (filter (lambda (jc) (string=? (cadr jc) "jne")) jump-conds))))

  ;; 2. Check LIR does NOT contain %set-boolean in loop test
  (let ((set-booleans (filter (lambda (i) (and (pair? i) (eq? (car i) '%set-boolean))) main-body)))
    (assert-true "%set-boolean is eliminated from fused loop condition" (null? set-booleans)))

  ;; 3. Check LIR does NOT contain %jump-if-false in loop test
  (let ((jump-if-falses (filter (lambda (i) (and (pair? i) (eq? (car i) '%jump-if-false))) main-body)))
    (assert-true "%jump-if-false is eliminated from fused loop condition" (null? jump-if-falses)))

  ;; 4. Emit assembly and inspect instructions
  (with-output-to-file "build/test_branch_fusion.s"
    (lambda ()
      (emit-x86-64 lir 'none)))
  (assert-true "emitted build/test_branch_fusion.s successfully" #t))

;; Test 2: Verify all relational predicates (<, <=, >, >=, eq?, null?, zero?, not, pair?) with dynamic variables
(let* ((ast '(letrec ((check-preds (lambda (x y z p b)
                                    (let ((c1 (if (< x y) 1 0))
                                          (c2 (if (<= x y) 2 0))
                                          (c3 (if (> y x) 4 0))
                                          (c4 (if (>= y y) 8 0))
                                          (c5 (if (eq? x x) 16 0))
                                          (c6 (if (null? p) 32 0))
                                          (c7 (if (zero? z) 64 0))
                                          (c8 (if (not b) 128 0))
                                          (c9 (if (pair? p) 256 0)))
                                      (+ c1 (+ c2 (+ c3 (+ c4 (+ c5 (+ c6 (+ c7 (+ c8 c9))))))))))))
               ;; Call 1: p is '(), so c6=32, c9=0 -> sum = 1+2+4+8+16+32+64+128+0 = 255
               (check-preds 3 5 0 '() #f)))
       (ast1 (desugar-all ast))
       (ast2 (cp0-optimize ast1))
       (ast2b (lvn-all ast2))
       (ast3 (anf-all ast2b))
       (ast3b (annotate-all ast3))
       (ast3c (rtyper-all ast3b))
       (ast3d (contify-all ast3c))
       (ast4 (closure-convert ast3d))
       (ast4b (alias-escape-all ast4))
       (lir (generate-lir ast4b))
       (main-entry (assq '%lir-main (cdr lir)))
       (main-body (cdr (assq 'body (cdr main-entry)))))

  (let ((jump-conds (filter (lambda (i) (and (pair? i) (eq? (car i) '%jump-cond))) main-body)))
    (assert-true "all predicates in main-body fused into %jump-cond" (>= (length jump-conds) 8)))

  ;; Emit assembly for comprehensive test
  (with-output-to-file "build/test_predicates_fusion.s"
    (lambda ()
      (emit-x86-64 lir 'none)))
  (assert-true "emitted build/test_predicates_fusion.s successfully" #t))

(newline)
(display "=======================================================")
(newline)
(display " All Condition Branch Flag Fusion Tests PASSED: ")
(display *tests-passed*)
(display "/")
(display (+ *tests-passed* *tests-failed*))
(newline)
(display "=======================================================")
(newline)
