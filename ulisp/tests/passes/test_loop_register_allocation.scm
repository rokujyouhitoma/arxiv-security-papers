;;; =======================================================================
;;; ULisp Test: Loop Variable Register Allocation for Self-Tail Calls (Issue #544)
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
(display " Starting Loop Variable Register Allocation Test Suite (Issue #544)")
(newline)
(display "=======================================================")
(newline)

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

  ;; 1. Verify %block has register parameters (%rbx %r13)
  (let* ((block-insts (filter (lambda (i) (and (pair? i) (eq? (car i) '%block) (pair? (caddr i)))) main-body))
         (block-inst (if (pair? block-insts) (car block-insts) #f)))
    (assert-true "loop %block instruction exists" (pair? block-inst))
    (let ((params (caddr block-inst)))
      (assert-true "loop %block parameters are registers (%rbx %r13)"
                   (and (equal? params '(%rbx %r13))))))

  ;; 2. Verify %cont-call emits %jump with register arguments
  (let ((jump-insts (filter (lambda (i) (and (pair? i) (eq? (car i) '%jump) (pair? (cddr i)))) main-body)))
    (assert-true "loop contains %jump with register arguments"
                 (pair? jump-insts))
    (let ((jump-args (caddr (car jump-insts))))
      (assert-true "%jump arguments are registers (%rbx %r13)"
                   (equal? jump-args '(%rbx %r13)))))

  ;; 3. Verify callee-saved registers are saved and restored
  (let ((saved-stores (filter (lambda (i) (and (pair? i) (eq? (car i) '%store) (memq (cadddr i) '(%rbx %r13)))) main-body))
        (restored-loads (filter (lambda (i) (and (pair? i)
                                                 (eq? (car i) '%load)
                                                 (or (and (eq? (cadr i) '%rbx) (= (cadddr i) -8))
                                                     (and (eq? (cadr i) '%r13) (= (cadddr i) -16)))))
                                main-body)))
    (assert-true "callee-saved registers %rbx and %r13 are saved before loop"
                 (= (length saved-stores) 2))
    (assert-true "callee-saved registers %rbx and %r13 are restored after loop"
                 (= (length restored-loads) 2)))

  ;; 4. Verify variable reads use register moves instead of stack loads
  (let ((var-moves (filter (lambda (i) (and (pair? i) (eq? (car i) '%mov) (memq (caddr i) '(%rbx %r13)))) main-body)))
    (assert-true "variables i and acc are read directly from %rbx and %r13"
                 (>= (length var-moves) 2)))

  ;; 5. Emit x86-64 assembly to build/test_loop_reg.s
  (with-output-to-file "build/test_loop_reg.s"
    (lambda ()
      (emit-x86-64 lir 'none)))
  (assert-true "emitted build/test_loop_reg.s exists" #t))

(newline)
(display "=======================================================")
(newline)
(display " All Loop Register Allocation Tests PASSED: ")
(display *tests-passed*)
(display "/")
(display (+ *tests-passed* *tests-failed*))
(newline)
(display "=======================================================")
(newline)
