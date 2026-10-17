;;; =======================================================================
;;; ULisp Test: In-Place Tail Loop Argument Shuffle (Issue #546)
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
(display " Starting In-Place Tail Loop Argument Shuffle Test Suite (Issue #546)")
(newline)
(display "=======================================================")
(newline)

;; --- Test 1: Standard 2-arg accumulator loop (loop (+ i 1) (+ acc i)) ---
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

  ;; 1. Verify in-place %add r13 rbx exists
  (let ((add-acc (filter (lambda (i) (and (pair? i) (eq? (car i) '%add) (eq? (cadr i) '%r13) (eq? (caddr i) '%rbx))) main-body)))
    (assert-true "in-place add for accumulator (add r13, rbx) generated"
                 (pair? add-acc)))

  ;; 2. Verify in-place %add rbx 1 exists
  (let ((add-i (filter (lambda (i) (and (pair? i) (eq? (car i) '%add) (eq? (cadr i) '%rbx) (equal? (caddr i) 1))) main-body)))
    (assert-true "in-place increment for counter (add rbx, 1) generated"
                 (pair? add-i)))

  ;; 3. Verify zero temporary stack stores/loads across entire function
  (let ((temp-stores (filter (lambda (i) (and (pair? i) (eq? (car i) '%store) (eq? (cadr i) '%rsp) (< (caddr i) -16))) main-body))
        (temp-loads (filter (lambda (i) (and (pair? i) (eq? (car i) '%load) (eq? (caddr i) '%rsp) (< (cadddr i) -16))) main-body)))
    (assert-true "zero temporary stack stores (spills) across entire loop function"
                 (= (length temp-stores) 0))
    (assert-true "zero temporary stack loads (reloads) across entire loop function"
                 (= (length temp-loads) 0)))

  ;; 4. Emit assembly to build/test_inplace_shuffle.s
  (with-output-to-file "build/test_inplace_shuffle.s"
    (lambda ()
      (emit-x86-64 lir 'none)))
  (assert-true "emitted build/test_inplace_shuffle.s successfully" #t))

;; --- Test 2: Variable Swap Loop (swap-loop b a) ---
(let* ((ast-swap '(letrec ((swap-loop (lambda (a b)
                                        (if (= a 20)
                                            b
                                            (swap-loop b a)))))
                    (swap-loop 10 20)))
       (ast1 (desugar-all ast-swap))
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

  ;; Check that %r10 scratch register is used for cycle break in swap
  (let ((scratch-uses (filter (lambda (i) (and (pair? i)
                                               (eq? (car i) '%mov)
                                               (or (eq? (cadr i) '%r10)
                                                   (eq? (caddr i) '%r10))))
                              main-body)))
    (assert-true "swap loop uses scratch register %r10 for cycle break"
                 (>= (length scratch-uses) 1)))

  (with-output-to-file "build/test_swap_loop.s"
    (lambda ()
      (emit-x86-64 lir 'none)))
  (assert-true "emitted build/test_swap_loop.s successfully" #t))

;; --- Test 3: Countdown Loop with Decrement (countdown (- n 1) (+ acc n)) ---
(let* ((ast-cd '(letrec ((countdown (lambda (n acc)
                                      (if (= n 0)
                                          acc
                                          (countdown (- n 1) (+ acc n))))))
                  (countdown 100 0)))
       (ast1 (desugar-all ast-cd))
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

  ;; Verify in-place %sub exists
  (let ((sub-n (filter (lambda (i) (and (pair? i) (eq? (car i) '%sub) (equal? (caddr i) 1))) main-body)))
    (assert-true "in-place subtraction (%sub rbx 1) generated for countdown"
                 (pair? sub-n)))

  (with-output-to-file "build/test_countdown.s"
    (lambda ()
      (emit-x86-64 lir 'none)))
  (assert-true "emitted build/test_countdown.s successfully" #t))

(newline)
(display "=======================================================")
(newline)
(display " All In-Place Tail Loop Argument Shuffle Tests PASSED: ")
(display *tests-passed*)
(display "/")
(display (+ *tests-passed* *tests-failed*))
(newline)
(display "=======================================================")
(newline)
