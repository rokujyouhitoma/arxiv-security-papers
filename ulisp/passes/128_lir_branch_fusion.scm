;;; =======================================================================
;;; ULisp Compiler Pass 128: LIR Branch & Comparison Flag Fusion
;;; Conforms to DSN-33 Architecture Specification & Issue #571
;;; Fuses relational comparisons directly into conditional jumps (%jump-cond)
;;; eliminating intermediate boolean instantiation.
;;; =======================================================================

(define (lir-cmp-false-cc op)
  (case op
    ((= eq?) "jne")
    ((<)     "jge")
    ((<=)    "jg")
    ((>)     "jle")
    ((>=)    "jl")
    (else    "jne")))

(define (lir-cmp-true-cc op)
  (case op
    ((= eq?) "je")
    ((<)     "jl")
    ((<=)    "jle")
    ((>)     "jg")
    ((>=)    "jge")
    (else    "je")))

(define (extract-fused-cmp-int e)
  (cond
    ((integer? e) (* e 4))
    ((and (pair? e) (eq? (car e) '%unbox-fixnum) (integer? (cadr e))) (cadr e))
    (else #f)))

(define (lir-compile-fused-cmp-cond op e1 e2 target-label jmp-cc-fn si env)
  (let* ((jmp-op (jmp-cc-fn op))
         (r1 (env-reg-var? e1 env))
         (r2 (env-reg-var? e2 env))
         (c1 (extract-fused-cmp-int e1))
         (c2 (extract-fused-cmp-int e2)))
    (cond
      ;; 1. e1 is reg, e2 is integer constant -> direct cmp reg, c2
      ((and r1 c2)
       (emit-lir! (list '%cmp r1 c2))
       (emit-lir! (list '%jump-cond jmp-op target-label)))

      ;; 2. e2 is reg, e1 is integer constant -> reverse comparison
      ((and r2 c1)
       (let ((rev-op (case op
                       ((= eq?) '=)
                       ((<)     '>)
                       ((<=)    '>=)
                       ((>)     '<)
                       ((>=)    '<=)
                       (else    op))))
         (emit-lir! (list '%cmp r2 c1))
         (emit-lir! (list '%jump-cond (jmp-cc-fn rev-op) target-label))))

      ;; 3. Both are register variables -> cmp r1, r2
      ((and r1 r2)
       (emit-lir! (list '%cmp r1 r2))
       (emit-lir! (list '%jump-cond jmp-op target-label)))

      ;; 4. e1 is reg, e2 is expr -> evaluate e2 to rax, then cmp r1, rax
      (r1
       (lir-compile-expr e2 si env #f)
       (emit-lir! (list '%cmp r1 '%rax))
       (emit-lir! (list '%jump-cond jmp-op target-label)))

      ;; 5. e2 is reg, e1 is expr -> evaluate e1 to rax, then cmp rax, r2
      (r2
       (lir-compile-expr e1 si env #f)
       (emit-lir! (list '%cmp '%rax r2))
       (emit-lir! (list '%jump-cond jmp-op target-label)))

      ;; 6. General fallback: evaluate e1 to stack, evaluate e2 to rax, then cmp (stack si), rax
      (else
       (track-lir-si! si)
       (lir-compile-operand-for-op op e1 si env)
       (emit-lir! (list '%store '%rsp si '%rax))
       (track-lir-si! (- si 8))
       (lir-compile-operand-for-op op e2 (- si 8) env)
       (emit-lir! (list '%cmp (list '%stack si) '%rax))
       (emit-lir! (list '%jump-cond jmp-op target-label))))))

(define (lir-compile-fused-cmp op e1 e2 else-label si env)
  (lir-compile-fused-cmp-cond op e1 e2 else-label lir-cmp-false-cc si env))
