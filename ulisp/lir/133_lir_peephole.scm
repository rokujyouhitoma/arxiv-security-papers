;;; =======================================================================
;;; ULisp Compiler Pass 133: LIR Peephole Optimization & Dead Code Elimination
;;; Conforms to DSN-33 Architecture Specification & Issue #595
;;; Implements sliding-window local simplifications and unreachable code pruning.
;;; =======================================================================

(define (lir-peephole-reg? opnd)
  (and (symbol? opnd)
       (let ((s (symbol->string opnd)))
         (and (> (string-length s) 1)
              (char=? (string-ref s 0) #\%)))))

(define (lir-unconditional-terminator? inst)
  (and (pair? inst)
       (memq (car inst) '(%jump %direct-jump %return))))

(define (lir-label-inst? inst)
  (and (pair? inst)
       (memq (car inst) '(%label %block))))

(define (lir-peephole-step-window insts)
  (let loop ((rest insts) (acc '()))
    (cond
      ((null? rest)
       (reverse acc))

      ;; -----------------------------------------------------------------
      ;; Rule 1: Redundant Self-Move Elimination
      ;; (%mov reg reg) -> ()
      ;; -----------------------------------------------------------------
      ((and (pair? (car rest))
            (let ((i (car rest)))
              (and (eq? (car i) '%mov)
                   (= (length i) 3)
                   (equal? (cadr i) (caddr i)))))
       (loop (cdr rest) acc))

      ;; -----------------------------------------------------------------
      ;; Rule 2: Round-Trip Register Move Elimination
      ;; (%mov r1 r2) followed immediately by (%mov r2 r1) -> (%mov r1 r2)
      ;; -----------------------------------------------------------------
      ((and (pair? (cdr rest))
            (pair? (car rest))
            (pair? (cadr rest))
            (let ((i1 (car rest))
                  (i2 (cadr rest)))
              (and (eq? (car i1) '%mov)
                   (eq? (car i2) '%mov)
                   (= (length i1) 3)
                   (= (length i2) 3)
                   (equal? (cadr i1) (caddr i2))
                   (equal? (caddr i1) (cadr i2))
                   (lir-peephole-reg? (cadr i1))
                   (lir-peephole-reg? (caddr i1)))))
       ;; Keep only the first mov (%mov r1 r2) and skip the second
       (loop (cddr rest) (cons (car rest) acc)))

      ;; -----------------------------------------------------------------
      ;; Rule 2b: Store-Reload Elimination & Register Forwarding
      ;; (%store %rsp offset src-reg) followed immediately by (%load dst-reg %rsp offset)
      ;; -> if dst-reg == src-reg, keep only (%store %rsp offset src-reg)
      ;; -> else (%store %rsp offset src-reg) followed by (%mov dst-reg src-reg)
      ;; -----------------------------------------------------------------
      ((and (pair? (cdr rest))
            (pair? (car rest))
            (pair? (cadr rest))
            (let ((i1 (car rest))
                  (i2 (cadr rest)))
              (and (eq? (car i1) '%store)
                   (eq? (car i2) '%load)
                   (= (length i1) 4)
                   (= (length i2) 4)
                   (eq? (cadr i1) '%rsp)
                   (eq? (caddr i2) '%rsp)
                   (equal? (caddr i1) (cadddr i2))
                   (lir-peephole-reg? (cadddr i1))
                   (lir-peephole-reg? (cadr i2)))))
       (let* ((i1 (car rest))
              (i2 (cadr rest))
              (src-reg (cadddr i1))
              (dst-reg (cadr i2)))
         (if (equal? dst-reg src-reg)
             (loop (cddr rest) (cons i1 acc))
             (loop (cddr rest) (cons (list '%mov dst-reg src-reg) (cons i1 acc))))))

      ;; -----------------------------------------------------------------
      ;; Rule 2c: Store + Compare + Branch Redundant Reload Elimination
      ;; (%store %rsp off src-reg) (%mov %rax src-reg) (%cmp %rax imm) (%jump-cond cc lbl) (%load %rax %rsp off)
      ;; -> drop the redundant (%load %rax %rsp off) since %rax already holds [rsp + off]
      ;; -----------------------------------------------------------------
      ((and (pair? rest)
            (pair? (cdr rest))
            (pair? (cddr rest))
            (pair? (cdddr rest))
            (pair? (cdr (cdddr rest)))
            (let ((i1 (car rest))
                  (i2 (cadr rest))
                  (i3 (caddr rest))
                  (i4 (cadddr rest))
                  (i5 (car (cdr (cdddr rest)))))
              (and (pair? i1) (eq? (car i1) '%store) (= (length i1) 4) (eq? (cadr i1) '%rsp)
                   (pair? i2) (eq? (car i2) '%mov) (= (length i2) 3) (eq? (cadr i2) '%rax) (equal? (caddr i2) (cadddr i1))
                   (pair? i3) (memq (car i3) '(%cmp %raw-cmp)) (eq? (cadr i3) '%rax)
                   (pair? i4) (eq? (car i4) '%jump-cond)
                   (pair? i5) (eq? (car i5) '%load) (= (length i5) 4) (eq? (cadr i5) '%rax) (eq? (caddr i5) '%rsp)
                   (equal? (cadddr i5) (caddr i1)))))
       (let ((i1 (car rest))
             (i2 (cadr rest))
             (i3 (caddr rest))
             (i4 (cadddr rest))
             (tail (cdr (cdr (cdddr rest)))))
         (loop tail (cons i4 (cons i3 (cons i2 (cons i1 acc)))))))

      ;; -----------------------------------------------------------------
      ;; Rule 3: Redundant Jump to Next Immediate Label
      ;; (%jump L1) followed immediately by (%label L1) -> (%label L1)
      ;; -----------------------------------------------------------------
      ((and (pair? (cdr rest))
            (pair? (car rest))
            (pair? (cadr rest))
            (memq (caar rest) '(%jump %direct-jump))
            (eq? (caadr rest) '%label)
            (eq? (cadr (car rest)) (cadr (cadr rest))))
       ;; Drop jump, keep label
       (loop (cdr rest) acc))

      ;; -----------------------------------------------------------------
      ;; Rule 4: Identity Arithmetic Simplification
      ;; (%add reg 0) / (%raw-add reg 0) -> ()
      ;; (%sub reg 0) / (%raw-sub reg 0) -> ()
      ;; -----------------------------------------------------------------
      ((and (pair? (car rest))
            (let ((i (car rest)))
              (and (memq (car i) '(%add %raw-add %sub %raw-sub))
                   (= (length i) 3)
                   (eqv? (caddr i) 0))))
       (loop (cdr rest) acc))

      ;; -----------------------------------------------------------------
      ;; Rule 5: Identity Multiplication Simplification
      ;; (%imul reg 1) / (%raw-mul reg 1) -> ()
      ;; -----------------------------------------------------------------
      ((and (pair? (car rest))
            (let ((i (car rest)))
              (and (memq (car i) '(%imul %raw-mul))
                   (= (length i) 3)
                   (eqv? (caddr i) 1))))
       (loop (cdr rest) acc))

      ;; -----------------------------------------------------------------
      ;; Rule 6: Unreachable Code Elimination (Dead Code Elimination)
      ;; (%jump L1) / (%return) followed by non-label instructions up to next label
      ;; -----------------------------------------------------------------
      ((and (lir-unconditional-terminator? (car rest))
            (pair? (cdr rest))
            (not (lir-label-inst? (cadr rest))))
       ;; Drop instructions between unconditional terminator and next label/block
       (let skip ((tail (cdr rest)))
         (cond
           ((null? tail)
            (loop '() (cons (car rest) acc)))
           ((lir-label-inst? (car tail))
            (loop tail (cons (car rest) acc)))
           (else
            (skip (cdr tail))))))

      ;; Fallthrough: Keep instruction unchanged
      (else
       (loop (cdr rest) (cons (car rest) acc))))))

(define (optimize-peephole-fixpoint insts)
  (let loop ((cur insts) (iterations 10))
    (if (<= iterations 0)
        cur
        (let ((next (lir-peephole-step-window cur)))
          (if (equal? cur next)
              cur
              (loop next (- iterations 1)))))))

;;; -----------------------------------------------------------------------
;;; Nanopass DSL Pass: lir-peephole-optimize
;;; -----------------------------------------------------------------------

(define-pass lir-peephole-optimize : L_lir_canonical (ir) -> L_lir_canonical ()
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
           (cons 'body (optimize-peephole-fixpoint inst)))))
  (MainDecl : MainDecl (m) -> MainDecl ()
    ((%lir-main (frame-size ,frame_size) (body ,inst ...))
     (list '%lir-main
           (list 'frame-size frame_size)
           (cons 'body (optimize-peephole-fixpoint inst))))))
