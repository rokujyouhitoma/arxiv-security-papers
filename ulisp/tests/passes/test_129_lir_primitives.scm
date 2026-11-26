;;; =======================================================================
;;; Unit Test: Pass 129 (LIR Primitive Instruction Selection)
;;; =======================================================================



(display "=======================================================\n")
(test-begin "Pass 129 (LIR Primitive Selection)")

;; Issue #955: Constant Fixnum Operand Tag Check Folding
(let* ((env '((p . -16)))
       (capture-binop
        (lambda (op e1 e2)
          (reset-lir!)
          (lir-compile-binop op e1 e2 -8 env)
          (reverse (car *lir-instructions*))))
       (has-bit-or-stack?
        (lambda (insts)
          (let loop ((xs insts))
            (cond ((null? xs) #f)
                  ((and (pair? (car xs))
                        (eq? (caar xs) '%bit-or)
                        (eq? (cadar xs) '%rdx))
                   #t)
                  (else (loop (cdr xs)))))))
       (has-bit-and-rdx?
        (lambda (insts)
          (let loop ((xs insts))
            (cond ((null? xs) #f)
                  ((equal? (car xs) '(%bit-and %rdx 3)) #t)
                  (else (loop (cdr xs))))))))
  ;; 1. (+ (car p) 1) -> %load %rdx %rsp -8 + %bit-and %rdx 3, no %bit-or %rdx
  (let ((insts (capture-binop '+ '(car p) 1)))
    (assert-false "(+ (car p) 1) omits %bit-or %rdx" (has-bit-or-stack? insts))
    (assert-true "(+ (car p) 1) keeps %load %rdx %rsp -8" (member '(%load %rdx %rsp -8) insts))
    (assert-true "(+ (car p) 1) keeps %bit-and %rdx 3" (has-bit-and-rdx? insts)))

  ;; 2. (+ 1 (car p)) -> %mov %rdx %rax + %bit-and %rdx 3, no %bit-or %rdx
  (let ((insts (capture-binop '+ 1 '(car p))))
    (assert-false "(+ 1 (car p)) omits %bit-or %rdx" (has-bit-or-stack? insts))
    (assert-true "(+ 1 (car p)) checks %rax via %mov %rdx %rax" (member '(%mov %rdx %rax) insts))
    (assert-true "(+ 1 (car p)) keeps %bit-and %rdx 3" (has-bit-and-rdx? insts)))

  ;; 3. (+ (car p) (cdr p)) -> emits %bit-or %rdx (%stack -8)
  (let ((insts (capture-binop '+ '(car p) '(cdr p))))
    (assert-true "(+ (car p) (cdr p)) emits %bit-or %rdx (%stack -8)"
                 (member '(%bit-or %rdx (%stack -8)) insts)))

  ;; 4. (+ (car p) #t) -> non-fixnum constant must still emit full tag check
  (let ((insts (capture-binop '+ '(car p) #t)))
    (assert-true "(+ (car p) #t) emits %bit-or %rdx (%stack -8)"
                 (member '(%bit-or %rdx (%stack -8)) insts)))

  ;; 5. (+ 1 2) -> both fixnum constants omit tag check completely
  (let ((insts (capture-binop '+ 1 2)))
    (assert-false "(+ 1 2) omits %bit-or %rdx" (has-bit-or-stack? insts))
    (assert-false "(+ 1 2) omits %bit-and %rdx 3" (has-bit-and-rdx? insts)))

  ;; 6. Issue #957: Shared slow-path trampoline stubs (no inline %load %rdi / %mov %rsi / %mov %rax 8)
  (let* ((insts-a8 (capture-binop '+ '(car p) '(cdr p)))
         (insts-a16 (begin
                      (reset-lir!)
                      (lir-compile-binop '< '(car p) '(cdr p) -16 env)
                      (reverse (car *lir-instructions*))))
         (insts-neg (begin
                      (reset-lir!)
                      (lir-compile-unary '- '(car p) -8 env)
                      (reverse (car *lir-instructions*))))
         (has-direct? (lambda (insts lbl)
                        (let loop ((xs insts))
                          (and (pair? xs)
                               (or (and (pair? (car xs))
                                        (eq? (caar xs) '%direct-call)
                                        (eq? (cadar xs) lbl))
                                   (loop (cdr xs))))))))
    (assert-true "si=-8 (+): emits %direct-call to __ulisp_slow_ulisp_fn_num_plus_a8"
                 (has-direct? insts-a8 '__ulisp_slow_ulisp_fn_num_plus_a8))
    (assert-false "si=-8 (+): omits inline (%mov %rsi %rax)"
                  (member '(%mov %rsi %rax) insts-a8))
    (assert-false "si=-8 (+): omits inline (%mov %rax 8)"
                  (member '(%mov %rax 8) insts-a8))
    (assert-true "si=-16 (<): emits %direct-call to __ulisp_slow_ulisp_fn_num_lt_a16"
                 (has-direct? insts-a16 '__ulisp_slow_ulisp_fn_num_lt_a16))
    (assert-true "unary (-): emits %direct-call to __ulisp_slow_neg"
                 (has-direct? insts-neg '__ulisp_slow_neg))
    (assert-false "unary (-): omits inline (%mov %rax 4)"
                  (member '(%mov %rax 4) insts-neg))))

(test-end "Pass 129 (LIR Primitive Selection)")
