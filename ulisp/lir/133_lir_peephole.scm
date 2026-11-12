;;; =======================================================================
;;; ULisp Compiler Pass 133: LIR Peephole Optimization & Dead Code Elimination
;;; Conforms to DSN-33 Architecture Specification & Issues #595, #767
;;; Implements sliding-window local simplifications, unreachable code pruning,
;;; and distance-independent DAG Store-Reload forwarding.
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

;;; -----------------------------------------------------------------------
;;; First-Class LIR Peephole Picopass Rules (DSN-33-01 T5.3)
;;; -----------------------------------------------------------------------

;; Rule 1: Redundant Self-Move Elimination
;; (%mov reg reg) -> ()
(define-picopass rule-lir-self-mov-elim
  (InstWindow
    (((%mov ,r1 ,r2) . ,rest)
     (guard (equal? r1 r2))
     rest)))

;; Rule 2: Round-Trip Register Move Elimination
;; (%mov r1 r2) (%mov r2 r1) -> (%mov r1 r2)
(define-picopass rule-lir-roundtrip-mov-elim
  (InstWindow
    (((%mov ,r1 ,r2) (%mov ,r3 ,r4) . ,rest)
     (guard (and (equal? r1 r4)
                 (equal? r2 r3)
                 (lir-peephole-reg? r1)
                 (lir-peephole-reg? r2)))
     (cons (list '%mov r1 r2) rest))))

;; Rule 3: Redundant Jump to Next Immediate Label
;; (%jump L1) (%label L1) -> (%label L1)
(define-picopass rule-lir-jump-next-label-elim
  (InstWindow
    (((%jump ,l1) (%label ,l2) . ,rest)
     (guard (equal? l1 l2))
     (cons (list '%label l2) rest))
    (((%direct-jump ,l1) (%label ,l2) . ,rest)
     (guard (equal? l1 l2))
     (cons (list '%label l2) rest))))

;; Rule 4: Identity Arithmetic Simplification
;; (%add reg 0) / (%raw-add reg 0) / (%sub reg 0) / (%raw-sub reg 0) -> ()
(define-picopass rule-lir-identity-arith-elim
  (InstWindow
    (((%add ,r 0) . ,rest) rest)
    (((%raw-add ,r 0) . ,rest) rest)
    (((%sub ,r 0) . ,rest) rest)
    (((%raw-sub ,r 0) . ,rest) rest)))

;; Rule 5: Identity Multiplication Simplification
;; (%imul reg 1) / (%raw-mul reg 1) -> ()
(define-picopass rule-lir-identity-mul-elim
  (InstWindow
    (((%imul ,r 1) . ,rest) rest)
    (((%raw-mul ,r 1) . ,rest) rest)))

;; Rule 6: Unreachable Code Elimination (DCE)
;; (%jump L) / (%return) followed by non-label instructions up to next label
(define-picopass rule-lir-unreachable-dce
  (InstWindow
    (((%jump ,lbl) ,next . ,rest)
     (guard (not (lir-label-inst? next)))
     (cons (list '%jump lbl) (lir-skip-to-next-label rest)))
    (((%direct-jump ,lbl) ,next . ,rest)
     (guard (not (lir-label-inst? next)))
     (cons (list '%direct-jump lbl) (lir-skip-to-next-label rest)))
    (((%return) ,next . ,rest)
     (guard (not (lir-label-inst? next)))
     (cons '(%return) (lir-skip-to-next-label rest)))
    (((%return ,opnd) ,next . ,rest)
     (guard (not (lir-label-inst? next)))
     (cons (list '%return opnd) (lir-skip-to-next-label rest)))))

;; Rule 7: Distance-Independent DAG Store-Reload Forwarding (DSN-33-01 T5.3)
;; Unifies Rule 2b (adjacent store-reload), Rule 2b-2/2b-3 (1-store gap),
;; and multi-instruction gaps across intervening straight-line instructions.
(define-picopass rule-lir-store-load-forward
  (InstWindow
    ;; Distance 0: Adjacent Store-Reload (Rule 2b)
    (((%store %rsp ,off ,src) (%load ,dst %rsp ,off) . ,rest)
     (guard (and (integer? off)
                 (lir-peephole-reg? src)
                 (lir-peephole-reg? dst)))
     (if (equal? dst src)
         (cons (list '%store '%rsp off src) rest)
         (cons (list '%store '%rsp off src)
               (cons (list '%mov dst src) rest))))

    ;; Distance 1: 1 Intervening Instruction (Rule 2b-2, Rule 2b-3, or safe intervening inst)
    (((%store %rsp ,off ,src) ,i1 (%load ,dst %rsp ,off) . ,rest)
     (guard (and (integer? off)
                 (lir-peephole-reg? src)
                 (lir-peephole-reg? dst)
                 (not (lir-inst-terminates-block? i1))
                 (not (lir-inst-memory-barrier? i1))
                 (not (lir-inst-defines-reg? i1 src))
                 (or (not (and (pair? i1) (eq? (car i1) '%store)))
                     (and (eq? (cadr i1) '%rsp) (not (equal? (caddr i1) off))))))
     (if (equal? dst src)
         (cons (list '%store '%rsp off src) (cons i1 rest))
         (cons (list '%store '%rsp off src) (cons i1 (cons (list '%mov dst src) rest)))))

    ;; Distance 2: 2 Intervening Instructions (test 11, test 15)
    (((%store %rsp ,off ,src) ,i1 ,i2 (%load ,dst %rsp ,off) . ,rest)
     (guard (and (integer? off)
                 (lir-peephole-reg? src)
                 (lir-peephole-reg? dst)
                 (not (lir-inst-terminates-block? i1))
                 (not (lir-inst-terminates-block? i2))
                 (not (lir-inst-memory-barrier? i1))
                 (not (lir-inst-memory-barrier? i2))
                 (not (lir-inst-defines-reg? i1 src))
                 (not (lir-inst-defines-reg? i2 src))
                 (or (not (and (pair? i1) (eq? (car i1) '%store)))
                     (and (eq? (cadr i1) '%rsp) (not (equal? (caddr i1) off))))
                 (or (not (and (pair? i2) (eq? (car i2) '%store)))
                     (and (eq? (cadr i2) '%rsp) (not (equal? (caddr i2) off))))))
     (if (equal? dst src)
         (cons (list '%store '%rsp off src) (cons i1 (cons i2 rest)))
         (cons (list '%store '%rsp off src) (cons i1 (cons i2 (cons (list '%mov dst src) rest))))))

    ;; Distance 3: 3 Intervening Instructions (test 12)
    (((%store %rsp ,off ,src) ,i1 ,i2 ,i3 (%load ,dst %rsp ,off) . ,rest)
     (guard (and (integer? off)
                 (lir-peephole-reg? src)
                 (lir-peephole-reg? dst)
                 (not (lir-inst-terminates-block? i1))
                 (not (lir-inst-terminates-block? i2))
                 (not (lir-inst-terminates-block? i3))
                 (not (lir-inst-memory-barrier? i1))
                 (not (lir-inst-memory-barrier? i2))
                 (not (lir-inst-memory-barrier? i3))
                 (not (lir-inst-defines-reg? i1 src))
                 (not (lir-inst-defines-reg? i2 src))
                 (not (lir-inst-defines-reg? i3 src))
                 (or (not (and (pair? i1) (eq? (car i1) '%store)))
                     (and (eq? (cadr i1) '%rsp) (not (equal? (caddr i1) off))))
                 (or (not (and (pair? i2) (eq? (car i2) '%store)))
                     (and (eq? (cadr i2) '%rsp) (not (equal? (caddr i2) off))))
                 (or (not (and (pair? i3) (eq? (car i3) '%store)))
                     (and (eq? (cadr i3) '%rsp) (not (equal? (caddr i3) off))))))
     (if (equal? dst src)
         (cons (list '%store '%rsp off src) (cons i1 (cons i2 (cons i3 rest))))
         (cons (list '%store '%rsp off src) (cons i1 (cons i2 (cons i3 (cons (list '%mov dst src) rest)))))))))

;;; -----------------------------------------------------------------------
;;; Nanopass DSL Pass: lir-peephole-optimize (fuse-window-rules)
;;; -----------------------------------------------------------------------

(define-pass lir-peephole-optimize : L_lir_canonical (ir) -> L_lir_canonical ()
  (fuse-window-rules
    rule-lir-self-mov-elim
    rule-lir-roundtrip-mov-elim
    rule-lir-store-load-forward
    rule-lir-jump-next-label-elim
    rule-lir-identity-arith-elim
    rule-lir-identity-mul-elim
    rule-lir-unreachable-dce))

(define (optimize-peephole-fixpoint insts)
  (lir-peephole-optimize insts))
