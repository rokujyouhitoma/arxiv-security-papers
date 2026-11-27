;;; =======================================================================
;;; ULisp Compiler Pass 143: Native x86-64 Machine Peephole Optimization
;;; Conforms to DSN-33 Architecture Specification & Issues #596, #814
;;; Implements sliding-window local simplifications on L_asm_x86 AST
;;; via Nanopass define-picopass rules and fuse-window-rules.
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

(define (x86-asm-reachable-boundary? inst)
  (and (pair? inst)
       (or (eq? (car inst) '%label)
           (eq? (car inst) '%p2align))))

(define (x86-asm-skip-unreachable rest)
  (let loop ((rem rest))
    (cond
      ((null? rem) '())
      ((x86-asm-reachable-boundary? (car rem)) rem)
      (else (loop (cdr rem))))))

(define (x86-asm-jump-targets-ret-across-labels? target rest)
  (let find-lbl ((scan rest) (seen-other-label? #f))
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
      (else
       (find-lbl (cdr scan) seen-other-label?)))))

;;; -----------------------------------------------------------------------
;;; First-Class x86-64 Peephole Picopass Rules (DSN-33-01 T5.3 / Issue #814)
;;; -----------------------------------------------------------------------

;; Rule 1: Redundant Self-Move Elimination
;; (mov r r) -> ()
(define-picopass rule-x86-self-mov-elim
  (InstWindow
    (((mov ,r1 ,r2) . ,rest)
     (guard (and (equal? r1 r2)
                 (x86-asm-reg? r1)))
     rest)))

;; Rule 2: Round-Trip Register Move Elimination
;; (mov r1 r2) followed immediately by (mov r2 r1) -> (mov r1 r2)
(define-picopass rule-x86-roundtrip-mov-elim
  (InstWindow
    (((mov ,r1 ,r2) (mov ,r3 ,r4) . ,rest)
     (guard (and (equal? r1 r4)
                 (equal? r2 r3)
                 (x86-asm-reg? r1)
                 (x86-asm-reg? r2)))
     (cons (list 'mov r1 r2) rest))))

(define (x86-asm-reads-flags? inst)
  (and (pair? inst)
       (or (memq (car inst) '(jcc set))
           (and (eq? (car inst) '%raw-asm)
                (string? (cadr inst))
                (or (string-starts-with? (cadr inst) "    set")
                    (string-starts-with? (cadr inst) "    cmov")
                    (string-starts-with? (cadr inst) "    j"))))))

;; Rule 3: Zero-idiom XOR Optimization (guard against live RFLAGS, Issue #953)
;; (mov reg 0) / (mov reg (%imm 0)) -> (xor reg reg)
(define-picopass rule-x86-zero-xor
  (InstWindow
    (((mov ,reg ,imm) . ,rest)
     (guard (and (x86-asm-reg? reg)
                 (x86-asm-zero-imm? imm)
                 (or (null? rest) (not (x86-asm-reads-flags? (car rest))))))
     (cons (list 'xor reg reg) rest))))

;; Rule 4: Redundant Jump to Next Immediate Label
;; (jmp L1) followed immediately by (%label L1) -> (%label L1)
(define-picopass rule-x86-jump-next-label
  (InstWindow
    (((jmp ,l1) (%label ,l2) . ,rest)
     (guard (equal? l1 l2))
     (cons (list '%label l2) rest))))

;; Rule 4b: Redundant Jump Over Align to Next Immediate Label
;; (jmp L1) followed immediately by (%p2align _) and (%label L1) -> (%p2align _) (%label L1)
(define-picopass rule-x86-jump-p2align-next-label
  (InstWindow
    (((jmp ,l1) (%p2align ,a) (%label ,l2) . ,rest)
     (guard (equal? l1 l2))
     (cons (list '%p2align a) (cons (list '%label l2) rest)))))

;; Rule 4d: LEA Optimization
;; (mov r1 r2) followed by (add r1 imm) -> (lea r1 (%disp imm r2))
(define-picopass rule-x86-lea-optimize
  (InstWindow
    (((mov ,r1 ,r2) (add ,r3 ,imm) . ,rest)
     (guard (and (x86-asm-reg? r1)
                 (x86-asm-reg? r2)
                 (not (equal? r1 r2))
                 (equal? r3 r1)
                 (x86-imm-int imm)
                 (x86-disp32-int? (x86-imm-int imm))
                 (or (null? rest) (not (x86-asm-reads-flags? (car rest))))))
     (cons (list 'lea r1 (list '%disp (x86-imm-int imm) r2)) rest))))

(define (x86-imm-int opnd)
  (cond
    ((integer? opnd) opnd)
    ((and (pair? opnd) (eq? (car opnd) '%imm) (integer? (cadr opnd))) (cadr opnd))
    (else #f)))

(define (x86-disp32-int? n)
  (and (integer? n) (>= n -2147483648) (<= n 2147483647)))

;; Rule 4e: LEA + Add/Sub Constant Folding (Issue #936)
;; (lea r1 (%disp d1 base)) (add r1 imm) -> (lea r1 (%disp (+ d1 imm) base))
;; (lea r1 (%disp d1 base)) (sub r1 imm) -> (lea r1 (%disp (- d1 imm) base))
(define-picopass rule-x86-lea-add-fold
  (InstWindow
    (((lea ,r1 (%disp ,d1 ,base)) (add ,r2 ,imm) . ,rest)
     (guard (and (x86-asm-reg? r1)
                 (x86-asm-reg? base)
                 (integer? d1)
                 (equal? r2 r1)
                 (x86-imm-int imm)
                 (or (null? rest) (not (x86-asm-reads-flags? (car rest))))
                 (x86-disp32-int? (+ d1 (x86-imm-int imm)))))
     (let ((s (+ d1 (x86-imm-int imm))))
       (if (= s 0)
           (if (equal? r1 base) rest (cons (list 'mov r1 base) rest))
           (cons (list 'lea r1 (list '%disp s base)) rest))))
    (((lea ,r1 (%disp ,d1 ,base)) (sub ,r2 ,imm) . ,rest)
     (guard (and (x86-asm-reg? r1)
                 (x86-asm-reg? base)
                 (integer? d1)
                 (equal? r2 r1)
                 (x86-imm-int imm)
                 (or (null? rest) (not (x86-asm-reads-flags? (car rest))))
                 (x86-disp32-int? (- d1 (x86-imm-int imm)))))
     (let ((s (- d1 (x86-imm-int imm))))
       (if (= s 0)
           (if (equal? r1 base) rest (cons (list 'mov r1 base) rest))
           (cons (list 'lea r1 (list '%disp s base)) rest))))))

;; Rule 5: Unreachable Code Elimination (Dead Code Elimination)
;; (jmp L) or (ret) followed by non-boundary instructions up to next label/align
(define-picopass rule-x86-unreachable-dce
  (InstWindow
    (((jmp ,lbl) ,next . ,rest)
     (guard (not (x86-asm-reachable-boundary? next)))
     (cons (list 'jmp lbl) (x86-asm-skip-unreachable rest)))
    (((ret) ,next . ,rest)
     (guard (not (x86-asm-reachable-boundary? next)))
     (cons '(ret) (x86-asm-skip-unreachable rest)))))

;; Rule 4c: Jump to Return Simplification across intermediate blocks
;; (jmp L1) ... (%label L_other) ... (%label L1) (ret) -> (ret)
(define-picopass rule-x86-jump-to-ret
  (InstWindow
    (((jmp ,lbl) . ,rest)
     (guard (x86-asm-jump-targets-ret-across-labels? lbl rest))
     (cons '(ret) rest))))

;; Rule 6: Overflow Flag Branch Fusion (Issue #955)
;; (%raw-asm "    seto dl") (%raw-asm "    movzx rdx, dl") (cmp rdx 0) (jcc jne/je L)
;; -> (jcc jo/jno L)
(define-picopass rule-x86-overflow-branch-fuse
  (InstWindow
    (((%raw-asm ,s1) (%raw-asm ,s2) (cmp ,reg ,imm) (jcc ,cc ,lbl) . ,rest)
     (guard (and (string? s1)
                 (string=? s1 "    seto dl")
                 (string? s2)
                 (string=? s2 "    movzx rdx, dl")
                 (eq? reg 'rdx)
                 (x86-asm-zero-imm? imm)
                 (memq cc '(jne jnz je jz))))
     (cons (list 'jcc (if (memq cc '(jne jnz)) 'jo 'jno) lbl) rest))))

;; Rule 7: Redundant Compare-Zero Elimination After Bitwise AND (Issue #955)
;; (and reg imm) (cmp reg 0) (jcc je/jne/jz/jnz L) -> (and reg imm) (jcc je/jne/jz/jnz L)
;; (and reg imm) (cmp reg 0) (%raw-asm "    sete al" / "    setne al") -> (and reg imm) (%raw-asm ...)
(define-picopass rule-x86-and-cmp-zero-branch-fuse
  (InstWindow
    (((and ,r1 ,mask) (cmp ,r2 ,zero) (jcc ,cc ,lbl) . ,rest)
     (guard (and (x86-asm-reg? r1)
                 (equal? r1 r2)
                 (x86-asm-zero-imm? zero)
                 (memq cc '(je jne jz jnz))))
     (cons (list 'and r1 mask)
           (cons (list 'jcc cc lbl) rest)))
    (((and ,r1 ,mask) (cmp ,r2 ,zero) (%raw-asm ,s) . ,rest)
     (guard (and (x86-asm-reg? r1)
                 (equal? r1 r2)
                 (x86-asm-zero-imm? zero)
                 (string? s)
                 (or (string=? s "    sete al")
                     (string=? s "    setne al"))))
     (cons (list 'and r1 mask)
           (cons (list '%raw-asm s) rest)))))

;;; -----------------------------------------------------------------------
;;; Nanopass DSL Pass: x86-peephole-pass (fuse-window-rules)
;;; -----------------------------------------------------------------------

(define-pass x86-peephole-pass : L_asm_x86 (ir) -> L_asm_x86 ()
  (fuse-window-rules
    rule-x86-self-mov-elim
    rule-x86-roundtrip-mov-elim
    rule-x86-zero-xor
    rule-x86-jump-next-label
    rule-x86-jump-p2align-next-label
    rule-x86-lea-optimize
    rule-x86-lea-add-fold
    rule-x86-overflow-branch-fuse
    rule-x86-and-cmp-zero-branch-fuse
    rule-x86-unreachable-dce
    rule-x86-jump-to-ret))

;;; Transparent backwards-compatible wrappers
(define (optimize-x86-peephole-insts insts)
  (x86-peephole-pass insts))

(define (optimize-x86-peephole prog)
  (x86-peephole-pass prog))
