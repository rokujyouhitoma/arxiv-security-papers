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
    (assert-false "(+ 1 2) omits %bit-and %rdx 3" (has-bit-and-rdx? insts))))

(test-end "Pass 129 (LIR Primitive Selection)")
