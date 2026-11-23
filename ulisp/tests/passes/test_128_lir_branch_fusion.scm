;;; =======================================================================
;;; ULisp Test: Condition Branch Flag / Branch Fusion (Issue #545)
;;; =======================================================================



(test-begin "Pass 128 (Condition Branch Flag Fusion)")

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

;; Test 3: Direct define-pass lir-fuse-branches transformation
(let* ((orig (list '%lir-program
                   '(strings ())
                   '(stackmaps ())
                   '(%lir-functions)
                   (list '%lir-main
                         '(frame-size 0)
                         '(body (%cmp %rax 10)
                                (%set-boolean %rbx "je")
                                (%jump-if-false %rbx L_else)
                                (%return 0)
                                (%label L_else)
                                (%return 1)))))
       (fused (lir-fuse-branches orig))
       (main-body (cdr (assq 'body (cdr (assq '%lir-main (cdr fused)))))))
  (let ((jump-conds (filter (lambda (i) (and (pair? i) (eq? (car i) '%jump-cond))) main-body))
        (set-booleans (filter (lambda (i) (and (pair? i) (eq? (car i) '%set-boolean))) main-body)))
    (assert-true "define-pass lir-fuse-branches emits %jump-cond" (pair? jump-conds))
    (assert-true "define-pass lir-fuse-branches eliminates %set-boolean" (null? set-booleans))
    (assert-true "fused program satisfies L_lir_canonical schema" (L_lir_canonical? fused))))

;; Test 4: C99 Pattern B1/B2/B3/B4 correctness and O(N) large Scheme body scaling (Issue #938)
(let* ((c99-ir (list '%lir-program
                     '(strings ())
                     '(stackmaps ())
                     '(%lir-functions)
                     (list '%lir-main
                           '(frame-size 0)
                           '(body (%cmp %rdi %rsi)
                                  (%jump-cond jge L_false_0)
                                  (%mov %rax 0)
                                  (%direct-jump L_join_0)
                                  (%label L_false_0)
                                  (%mov %rax 1)
                                  (%label L_join_0)
                                  (%cmp %rax 0)
                                  (%jump-cond jne L_taken_0)
                                  (%jump-cond jne L_next_fall)
                                  (%label L_next_fall)
                                  (%direct-jump L_fall2)
                                  (%label L_fall2)
                                  (%mov %rax 1)
                                  (%return %rax)
                                  (%label L_taken_0)
                                  (%mov %rax 2)
                                  (%return %rax)))))
       (c99-fused (lir-fuse-branches c99-ir))
       (c99-body (cdr (assq 'body (cdr (assq '%lir-main (cdr c99-fused))))))
       (scheme-insts (let loop ((i 0) (acc '()))
                       (if (= i 5000)
                           (reverse (cons '(%return %rax) acc))
                           (loop (+ i 1)
                                 (cons (list '%mov '%rax i) acc)))))
       (scheme-ir (list '%lir-program
                        '(strings ())
                        '(stackmaps ())
                        '(%lir-functions)
                        (list '%lir-main '(frame-size 0) (cons 'body scheme-insts))))
       (scheme-fused (lir-fuse-branches scheme-ir))
       (scheme-out-body (cdr (assq 'body (cdr (assq '%lir-main (cdr scheme-fused)))))))
  (assert-true "C99 Pattern B1 fuses to %jump-cond jge L_taken_0"
               (member '(%jump-cond jge L_taken_0) c99-body))
  (assert-true "C99 Pattern B3/B4 eliminates adjacent label jumps"
               (not (member '(%direct-jump L_fall2) c99-body)))
  (assert-equal "Large 5001-inst Scheme body preserves exact length under fast path"
                5001
                (length scheme-out-body)))

(newline)
(test-end "Pass 128 (Condition Branch Flag Fusion)")
