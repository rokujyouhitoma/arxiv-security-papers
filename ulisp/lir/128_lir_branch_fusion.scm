;;; =======================================================================
;;; ULisp Compiler Pass 128: LIR Branch & Comparison Flag Fusion
;;; Conforms to DSN-33 Architecture Specification & Issues #571, #595
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

(define (lir-invert-cond-op op)
  (cond
    ((or (equal? op "je") (eq? op 'je) (eq? op 'equal) (eq? op 'zero)) "jne")
    ((or (equal? op "jne") (eq? op 'jne) (eq? op 'not-equal) (eq? op 'not-zero)) "je")
    ((or (equal? op "jl") (eq? op 'jl) (eq? op 'less)) "jge")
    ((or (equal? op "jle") (eq? op 'jle) (eq? op 'less-equal)) "jg")
    ((or (equal? op "jg") (eq? op 'jg) (eq? op 'greater)) "jle")
    ((or (equal? op "jge") (eq? op 'jge) (eq? op 'greater-equal)) "jl")
    (else "jne")))

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

      ;; 6. e2 is integer constant -> evaluate e1 to rax, then cmp rax, c2
      (c2
       (lir-compile-operand-for-op op e1 si env)
       (emit-lir! (list '%cmp '%rax c2))
       (emit-lir! (list '%jump-cond jmp-op target-label)))

      ;; 7. e1 is integer constant -> evaluate e2 to rax, then reverse cmp rax, c1
      (c1
       (let ((rev-op (case op
                       ((= eq?) '=)
                       ((<)     '>)
                       ((<=)    '>=)
                       ((>)     '<)
                       ((>=)    '<=)
                       (else    op))))
         (lir-compile-operand-for-op op e2 si env)
         (emit-lir! (list '%cmp '%rax c1))
         (emit-lir! (list '%jump-cond (jmp-cc-fn rev-op) target-label))))

      ;; 8. General fallback: evaluate e1 to stack, evaluate e2 to rax, then cmp (stack si), rax
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

;;; -----------------------------------------------------------------------
;;; Linear LIR Branch Fusion Transformer
;;; -----------------------------------------------------------------------

(define (optimize-branch-fusion insts)
  (let loop ((rest insts) (acc '()))
    (cond
      ((null? rest)
       (reverse acc))

      ;; Pattern 1: (%cmp opnd1 opnd2) followed by (%set-boolean reg cond) and (%jump-if-false reg lbl)
      ;; -> (%cmp opnd1 opnd2) followed by (%jump-cond (invert-cc cond) lbl)
      ((and (pair? rest)
            (pair? (cdr rest))
            (pair? (cddr rest))
            (pair? (car rest))
            (memq (caar rest) '(%cmp %raw-cmp))
            (pair? (cadr rest))
            (eq? (car (cadr rest)) '%set-boolean)
            (pair? (caddr rest))
            (eq? (car (caddr rest)) '%jump-if-false)
            (equal? (cadr (cadr rest)) (cadr (caddr rest))))
       (let* ((cmp-inst (car rest))
              (set-b (cadr rest))
              (jmp-inst (caddr rest))
              (cond-op (caddr set-b))
              (target-lbl (caddr jmp-inst))
              (fused-jmp (list '%jump-cond (lir-invert-cond-op cond-op) target-lbl)))
         (loop (cdddr rest) (cons fused-jmp (cons cmp-inst acc)))))

      ;; Pattern 2: (%set-boolean reg cond) followed by (%jump-if-false reg lbl)
      ;; -> (%jump-cond (invert-cc cond) lbl)
      ((and (pair? rest)
            (pair? (cdr rest))
            (pair? (car rest))
            (eq? (caar rest) '%set-boolean)
            (pair? (cadr rest))
            (eq? (car (cadr rest)) '%jump-if-false)
            (equal? (cadar rest) (cadr (cadr rest))))
       (let* ((set-b (car rest))
              (jmp-inst (cadr rest))
              (cond-op (caddr set-b))
              (target-lbl (caddr jmp-inst))
              (fused-jmp (list '%jump-cond (lir-invert-cond-op cond-op) target-lbl)))
         (loop (cddr rest) (cons fused-jmp acc))))

      ;; Pattern 3: (%cmp reg const) followed by (%jump-if-false reg2 lbl)
      ((and (pair? rest)
            (pair? (cdr rest))
            (pair? (car rest))
            (memq (caar rest) '(%cmp %raw-cmp))
            (pair? (cadr rest))
            (eq? (car (cadr rest)) '%jump-if-false))
       (let* ((cmp-inst (car rest))
              (jmp-inst (cadr rest))
              (target-lbl (caddr jmp-inst))
              (fused-jmp (list '%jump-cond "jne" target-lbl)))
         (loop (cddr rest) (cons fused-jmp (cons cmp-inst acc)))))

      (else
       (loop (cdr rest) (cons (car rest) acc))))))

;;; -----------------------------------------------------------------------
;;; Nanopass DSL Pass: lir-fuse-branches
;;; -----------------------------------------------------------------------

(define-pass lir-fuse-branches : L_lir_canonical (ir) -> L_lir_canonical ()
  (entry Program)
  (Program : Program (p) -> Program ()
    ((%lir-program (strings ,se) (stackmaps ,sm) (%lir-functions ,f ...) ,m)
     (list '%lir-program
           (list 'strings se)
           (list 'stackmaps sm)
           (cons '%lir-functions (map FunctionDecl f))
           (MainDecl m))))
  (FunctionDecl : FunctionDecl (f) -> FunctionDecl ()
    ((%lir-function ,lbl (params (,x ...)) (frame-size ,frame_size) (body ,inst ...))
     (list '%lir-function
           lbl
           (list 'params x)
           (list 'frame-size frame_size)
           (cons 'body (optimize-branch-fusion inst)))))
  (MainDecl : MainDecl (m) -> MainDecl ()
    ((%lir-main (frame-size ,frame_size) (body ,inst ...))
     (list '%lir-main
           (list 'frame-size frame_size)
           (cons 'body (optimize-branch-fusion inst))))))
