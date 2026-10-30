;;; =======================================================================
;;; ULisp Compiler Pass 143: Native x86-64 Machine Peephole Optimization
;;; Conforms to DSN-33 Architecture Specification & Issue #596
;;; Implements sliding-window local simplifications on L_asm_x86 AST.
;;; =======================================================================

(define (x86-asm-reg? opnd)
  (or (and (symbol? opnd)
           (memq opnd '(rax rbx rcx rdx rsi rdi rbp rsp
                        r8  r9  r10 r11 r12 r13 r14 r15 al)))
      (and (pair? opnd)
           (eq? (car opnd) '%reg))))

(define (x86-asm-zero-imm? opnd)
  (or (eqv? opnd 0)
      (and (pair? opnd)
           (eq? (car opnd) '%imm)
           (eqv? (cadr opnd) 0))))

(define (x86-asm-unconditional-terminator? inst)
  (and (pair? inst)
       (memq (car inst) '(jmp ret))))

(define (x86-asm-label-inst? inst)
  (and (pair? inst)
       (eq? (car inst) '%label)))

(define (x86-peephole-step-window insts)
  (let loop ((rest insts) (acc '()))
    (cond
      ((null? rest)
       (reverse acc))

      ;; -----------------------------------------------------------------
      ;; Rule 1: Redundant Self-Move Elimination
      ;; (mov r r) -> ()
      ;; -----------------------------------------------------------------
      ((and (pair? (car rest))
            (let ((i (car rest)))
              (and (eq? (car i) 'mov)
                   (= (length i) 3)
                   (x86-asm-reg? (cadr i))
                   (equal? (cadr i) (caddr i)))))
       (loop (cdr rest) acc))

      ;; -----------------------------------------------------------------
      ;; Rule 2: Round-Trip Register Move Elimination
      ;; (mov r1 r2) followed immediately by (mov r2 r1) -> (mov r1 r2)
      ;; -----------------------------------------------------------------
      ((and (pair? (cdr rest))
            (pair? (car rest))
            (pair? (cadr rest))
            (let ((i1 (car rest))
                  (i2 (cadr rest)))
              (and (eq? (car i1) 'mov)
                   (eq? (car i2) 'mov)
                   (= (length i1) 3)
                   (= (length i2) 3)
                   (equal? (cadr i1) (caddr i2))
                   (equal? (caddr i1) (cadr i2))
                   (x86-asm-reg? (cadr i1))
                   (x86-asm-reg? (caddr i1)))))
       (loop (cddr rest) (cons (car rest) acc)))

      ;; -----------------------------------------------------------------
      ;; Rule 3: Zero-idiom XOR Optimization
      ;; (mov reg 0) / (mov reg (%imm 0)) -> (xor reg reg)
      ;; -----------------------------------------------------------------
      ((and (pair? (car rest))
            (let ((i (car rest)))
              (and (eq? (car i) 'mov)
                   (= (length i) 3)
                   (x86-asm-reg? (cadr i))
                   (x86-asm-zero-imm? (caddr i)))))
       (let ((reg (cadr (car rest))))
         (loop (cdr rest) (cons (list 'xor reg reg) acc))))

      ;; -----------------------------------------------------------------
      ;; Rule 4: Redundant Jump to Next Immediate Label
      ;; (jmp L1) followed immediately by (%label L1) -> (%label L1)
      ;; -----------------------------------------------------------------
      ((and (pair? (cdr rest))
            (pair? (car rest))
            (pair? (cadr rest))
            (eq? (car (car rest)) 'jmp)
            (eq? (car (cadr rest)) '%label)
            (equal? (cadr (car rest)) (cadr (cadr rest))))
       (loop (cdr rest) acc))

      ;; -----------------------------------------------------------------
      ;; Rule 4b: Redundant Jump Over Align to Next Immediate Label
      ;; (jmp L1) followed immediately by (%p2align _) and (%label L1) -> (%p2align _) (%label L1)
      ;; -----------------------------------------------------------------
      ((and (pair? (cdr rest))
            (pair? (cddr rest))
            (pair? (car rest))
            (pair? (cadr rest))
            (pair? (caddr rest))
            (eq? (car (car rest)) 'jmp)
            (eq? (car (cadr rest)) '%p2align)
            (eq? (car (caddr rest)) '%label)
            (equal? (cadr (car rest)) (cadr (caddr rest))))
       (loop (cdr rest) acc))

      ;; -----------------------------------------------------------------
      ;; Rule 5: Unreachable Code Elimination (Dead Code Elimination)
      ;; (jmp L) or (ret) followed by non-label instructions up to next label
      ;; -----------------------------------------------------------------
      ((and (x86-asm-unconditional-terminator? (car rest))
            (pair? (cdr rest))
            (not (x86-asm-label-inst? (cadr rest)))
            (not (and (pair? (cadr rest)) (eq? (caadr rest) '%p2align))))
       (let skip ((tail (cdr rest)))
         (cond
           ((null? tail)
            (loop '() (cons (car rest) acc)))
           ((or (x86-asm-label-inst? (car tail))
                (and (pair? (car tail)) (eq? (caar tail) '%p2align)))
            (loop tail (cons (car rest) acc)))
           (else
            (skip (cdr tail))))))

      ;; -----------------------------------------------------------------
      ;; Rule 4c: Jump to Return Simplification across intermediate blocks
      ;; (jmp L1) ... (%label L_other) ... (%label L1) (ret) -> (ret)
      ;; -----------------------------------------------------------------
      ((and (pair? (car rest))
            (eq? (car (car rest)) 'jmp)
            (let ((target (cadr (car rest))))
              (let find-lbl ((scan (cdr rest)) (seen-other-label? #f))
                (cond
                  ((null? scan) #f)
                  ((and (pair? (car scan))
                        (eq? (caar scan) '%label)
                        (equal? (cadar scan) target))
                   (and seen-other-label?
                        (pair? (cdr scan))
                        (pair? (cadr scan))
                        (eq? (caadr scan) 'ret)))
                  ((and (pair? (car scan)) (eq? (caar scan) '%label))
                   (find-lbl (cdr scan) #t))
                  (else (find-lbl (cdr scan) seen-other-label?))))))
       (loop (cdr rest) (cons '(ret) acc)))

      ;; Fallthrough: Keep instruction unchanged
      (else
       (loop (cdr rest) (cons (car rest) acc))))))

(define (optimize-x86-peephole-insts insts)
  (let loop ((cur insts) (iterations 10))
    (if (<= iterations 0)
        cur
        (let ((next (x86-peephole-step-window cur)))
          (if (equal? cur next)
              cur
              (loop next (- iterations 1)))))))

(define (optimize-x86-peephole-function fn)
  (let* ((lbl (cadr fn))
         (frame-size-entry (assq 'frame-size (cddr fn)))
         (frame-size (if frame-size-entry (cadr frame-size-entry) 0))
         (body-entry (assq 'body (cddr fn)))
         (body (if body-entry (cdr body-entry) '()))
         (opt-body (optimize-x86-peephole-insts body)))
    (list '%asm-function
          lbl
          (list 'frame-size frame-size)
          (cons 'body opt-body))))

(define (optimize-x86-peephole-main m)
  (let* ((frame-size-entry (assq 'frame-size (cdr m)))
         (frame-size (if frame-size-entry (cadr frame-size-entry) 0))
         (body-entry (assq 'body (cdr m)))
         (body (if body-entry (cdr body-entry) '()))
         (opt-body (optimize-x86-peephole-insts body)))
    (list '%asm-main
          (list 'frame-size frame-size)
          (cons 'body opt-body))))

(define (optimize-x86-peephole prog)
  (let* ((strings (assq 'strings (cdr prog)))
         (stackmaps (assq 'stackmaps (cdr prog)))
         (funcs-entry (assq '%asm-functions (cdr prog)))
         (funcs (if funcs-entry (cdr funcs-entry) '()))
         (main-entry (assq '%asm-main (cdr prog))))
    (list '%asm-program
          (if strings strings '(strings ()))
          (if stackmaps stackmaps '(stackmaps ()))
          (cons '%asm-functions (map optimize-x86-peephole-function funcs))
          (if main-entry
              (optimize-x86-peephole-main main-entry)
              '(%asm-main (frame-size 0) (body ()))))))
