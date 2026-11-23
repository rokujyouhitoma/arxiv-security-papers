;;; =======================================================================
;;; ULisp Compiler Pass 133: LIR Peephole Optimization & Dead Code Elimination
;;; Conforms to DSN-33 Architecture Specification & Issues #595, #767
;;; Implements sliding-window local simplifications, unreachable code pruning,
;;; and distance-independent DAG Store-Reload forwarding.
;;; =======================================================================

(define (lir-peephole-reg? opnd)
  (and (symbol? opnd)
       (case opnd
         ((%rax %rcx %rdx %rbx %rsp %rbp %rsi %rdi
           %r8 %r9 %r10 %r11 %r12 %r13 %r14 %r15)
          #t)
         (else
          (let ((s (symbol->string opnd)))
            (and (> (string-length s) 1)
                 (char=? (string-ref s 0) #\%)))))))

(define (lir-unconditional-terminator? inst)
  (and (pair? inst)
       (memq (car inst) '(%jump %direct-jump %switch %return))))

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
                 (not (lir-inst-may-alias-stack-slot? i1 off))))
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
                 (not (lir-inst-may-alias-stack-slot? i1 off))
                 (not (lir-inst-may-alias-stack-slot? i2 off))))
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
                 (not (lir-inst-may-alias-stack-slot? i1 off))
                 (not (lir-inst-may-alias-stack-slot? i2 off))
                 (not (lir-inst-may-alias-stack-slot? i3 off))))
     (if (equal? dst src)
         (cons (list '%store '%rsp off src) (cons i1 (cons i2 (cons i3 rest))))
         (cons (list '%store '%rsp off src) (cons i1 (cons i2 (cons i3 (cons (list '%mov dst src) rest)))))))))

;; Rule 8: Redundant Box-Unbox Pair Elimination (Issue #826)
;; (%box-fixnum r1 r2) (%unbox-fixnum r3 r1) -> (%mov r3 r2)
;; (%unbox-fixnum r1 r2) (%box-fixnum r3 r1) -> (%mov r3 r2)
;; (%box-flonum r1 r2) (%unbox-flonum r3 r1) -> (%fmov r3 r2)
;; (%unbox-flonum r1 r2) (%box-flonum r3 r1) -> (%fmov r3 r2)
(define-picopass rule-lir-box-unbox-elim
  (InstWindow
    (((%box-fixnum ,d1 ,s1) (%unbox-fixnum ,d2 ,s2) . ,rest)
     (guard (equal? d1 s2))
     (if (equal? d2 s1)
         rest
         (cons (list '%mov d2 s1) rest)))
    (((%unbox-fixnum ,d1 ,s1) (%box-fixnum ,d2 ,s2) . ,rest)
     (guard (equal? d1 s2))
     (if (equal? d2 s1)
         rest
         (cons (list '%mov d2 s1) rest)))
    (((%box-flonum ,d1 ,s1) (%unbox-flonum ,d2 ,s2) . ,rest)
     (guard (equal? d1 s2))
     (if (equal? d2 s1)
         rest
         (cons (list '%fmov d2 s1) rest)))
    (((%unbox-flonum ,d1 ,s1) (%box-flonum ,d2 ,s2) . ,rest)
     (guard (equal? d1 s2))
     (if (equal? d2 s1)
         rest
         (cons (list '%fmov d2 s1) rest)))))

;; Rule 9: Redundant Source Location Elimination
;; (%loc fid line col1) (%loc fid line col2) -> (%loc fid line col2)
(define-picopass rule-lir-redundant-loc-elim
  (InstWindow
    (((%loc ,f1 ,l1 ,c1) (%loc ,f2 ,l2 ,c2) . ,rest)
     (guard (and (equal? f1 f2) (equal? l1 l2)))
     (cons (list '%loc f2 l2 c2) rest))))

;; Rule 10: Redundant Self Floating-Point Move Elimination (Issue #934)
;; (%fmov reg reg) -> ()
(define-picopass rule-lir-self-fmov-elim
  (InstWindow
    (((%fmov ,r1 ,r2) . ,rest)
     (guard (equal? r1 r2))
     rest)))

;; Rule 11: Distance-Independent f64 Store-Reload Forwarding (Issue #934)
;; Strictly restricted to f64 because 160_backend_c rounds f32 on %store-typed/%load-typed
;; whereas %fmov performs raw 64-bit IEEE-754 register transfer.
(define-picopass rule-lir-f64-store-load-forward
  (InstWindow
    ;; Distance 0: Adjacent f64 Store-Reload
    (((%store-typed f64 %rsp ,off ,src) (%load-typed f64 ,dst %rsp ,off) . ,rest)
     (guard (and (integer? off)
                 (lir-peephole-reg? src)
                 (lir-peephole-reg? dst)))
     (if (equal? dst src)
         (cons (list '%store-typed 'f64 '%rsp off src) rest)
         (cons (list '%store-typed 'f64 '%rsp off src)
               (cons (list '%fmov dst src) rest))))

    ;; Distance 1
    (((%store-typed f64 %rsp ,off ,src) ,i1 (%load-typed f64 ,dst %rsp ,off) . ,rest)
     (guard (and (integer? off)
                 (lir-peephole-reg? src)
                 (lir-peephole-reg? dst)
                 (not (lir-inst-terminates-block? i1))
                 (not (lir-inst-memory-barrier? i1))
                 (not (lir-inst-defines-reg? i1 src))
                 (not (lir-inst-may-alias-stack-slot? i1 off))))
     (if (equal? dst src)
         (cons (list '%store-typed 'f64 '%rsp off src) (cons i1 rest))
         (cons (list '%store-typed 'f64 '%rsp off src)
               (cons i1 (cons (list '%fmov dst src) rest)))))

    ;; Distance 2
    (((%store-typed f64 %rsp ,off ,src) ,i1 ,i2 (%load-typed f64 ,dst %rsp ,off) . ,rest)
     (guard (and (integer? off)
                 (lir-peephole-reg? src)
                 (lir-peephole-reg? dst)
                 (not (lir-inst-terminates-block? i1))
                 (not (lir-inst-terminates-block? i2))
                 (not (lir-inst-memory-barrier? i1))
                 (not (lir-inst-memory-barrier? i2))
                 (not (lir-inst-defines-reg? i1 src))
                 (not (lir-inst-defines-reg? i2 src))
                 (not (lir-inst-may-alias-stack-slot? i1 off))
                 (not (lir-inst-may-alias-stack-slot? i2 off))))
     (if (equal? dst src)
         (cons (list '%store-typed 'f64 '%rsp off src) (cons i1 (cons i2 rest)))
         (cons (list '%store-typed 'f64 '%rsp off src)
               (cons i1 (cons i2 (cons (list '%fmov dst src) rest))))))

    ;; Distance 3
    (((%store-typed f64 %rsp ,off ,src) ,i1 ,i2 ,i3 (%load-typed f64 ,dst %rsp ,off) . ,rest)
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
                 (not (lir-inst-may-alias-stack-slot? i1 off))
                 (not (lir-inst-may-alias-stack-slot? i2 off))
                 (not (lir-inst-may-alias-stack-slot? i3 off))))
     (if (equal? dst src)
         (cons (list '%store-typed 'f64 '%rsp off src) (cons i1 (cons i2 (cons i3 rest))))
         (cons (list '%store-typed 'f64 '%rsp off src)
               (cons i1 (cons i2 (cons i3 (cons (list '%fmov dst src) rest)))))))))

;;; -----------------------------------------------------------------------
;;; Linear O(N) Backward-Liveness Stack Dead-Store Elimination (Issue #934)
;;; -----------------------------------------------------------------------

(define (lir-iv-insert ivs lo hi)
  (if (>= lo hi)
      ivs
      (let loop ((xs ivs) (cur-lo lo) (cur-hi hi) (acc '()))
        (cond
          ((null? xs)
           (reverse (cons (cons cur-lo cur-hi) acc)))
          ((< (cdar xs) cur-lo)
           (loop (cdr xs) cur-lo cur-hi (cons (car xs) acc)))
          ((> (caar xs) cur-hi)
           (let append-rest ((ys xs) (out (cons (cons cur-lo cur-hi) acc)))
             (if (null? ys)
                 (reverse out)
                 (append-rest (cdr ys) (cons (car ys) out)))))
          (else
           (loop (cdr xs)
                 (min cur-lo (caar xs))
                 (max cur-hi (cdar xs))
                 acc))))))

(define (lir-iv-remove ivs lo hi)
  (if (>= lo hi)
      ivs
      (let loop ((xs ivs) (acc '()))
        (if (null? xs)
            (reverse acc)
            (let ((xlo (caar xs))
                  (xhi (cdar xs)))
              (cond
                ((or (<= xhi lo) (>= xlo hi))
                 (loop (cdr xs) (cons (car xs) acc)))
                (else
                 (let* ((acc1 (if (< xlo lo) (cons (cons xlo lo) acc) acc))
                        (acc2 (if (< hi xhi) (cons (cons hi xhi) acc1) acc1)))
                   (loop (cdr xs) acc2)))))))))

(define (lir-iv-subsumed? ivs lo hi)
  (let loop ((xs ivs))
    (cond
      ((null? xs) #f)
      ((> (caar xs) lo) #f)
      ((<= (caar xs) lo)
       (if (>= (cdar xs) hi)
           #t
           (loop (cdr xs))))
      (else (loop (cdr xs))))))

(define (lir-iv-overlaps? ivs lo hi)
  (let loop ((xs ivs))
    (cond
      ((null? xs) #f)
      ((>= (caar xs) hi) #f)
      ((> (cdar xs) lo) #t)
      (else (loop (cdr xs))))))

(define (lir-dse-type-width ty)
  (case ty
    ((i8 u8 bool) 1)
    ((i16 u16) 2)
    ((i32 u32 f32) 4)
    (else 8)))

(define (lir-dse-tree-contains-sym? x sym)
  (cond
    ((eq? x sym) #t)
    ((pair? x) (or (lir-dse-tree-contains-sym? (car x) sym)
                   (lir-dse-tree-contains-sym? (cdr x) sym)))
    (else #f)))

(define (lir-dse-inst-escapes-rsp? inst)
  (if (not (pair? inst))
      #f
      (let ((op (car inst)))
        (cond
          ((memq op '(%inline-asm %alloc-stack %managed-alloc-stack %capture-cc))
           #t)
          ((memq op '(%store %store-byte))
           (and (>= (length inst) 4) (eq? (list-ref inst 3) '%rsp)))
          ((eq? op '%store-typed)
           (and (>= (length inst) 5) (eq? (list-ref inst 4) '%rsp)))
          ((memq op '(%load %load-byte-zx))
           (and (>= (length inst) 4) (eq? (list-ref inst 3) '%rsp)))
          ((eq? op '%load-typed)
           (and (>= (length inst) 5) (eq? (list-ref inst 4) '%rsp)))
          ((memq op '(%add %sub %raw-add %raw-sub))
           (and (>= (length inst) 3)
                (or (eq? (caddr inst) '%rsp)
                    (and (not (eq? (cadr inst) '%rsp))
                         (lir-dse-tree-contains-sym? (cdr inst) '%rsp)))))
          (else
           (lir-dse-tree-contains-sym? (cdr inst) '%rsp))))))

(define (lir-dse-inst-modifies-rsp? inst)
  (and (pair? inst) (lir-inst-defines-reg? inst '%rsp)))

(define (lir-dse-inst-indirect-read? inst)
  (and (pair? inst)
       (let ((op (car inst)))
         (or (and (memq op '(%load %load-byte-zx))
                  (>= (length inst) 4)
                  (not (eq? (caddr inst) '%rsp)))
             (and (eq? op '%load-typed)
                  (>= (length inst) 5)
                  (not (eq? (cadddr inst) '%rsp)))
             (memq op '(%unbox-flonum %unbox-fixnum %atomic-cas!
                        %managed-unbox %managed-write-barrier
                        %box-flonum %managed-box))))))

(define (lir-dse-neg-store-range inst)
  ;; Returns (lo . hi) if inst stores strictly into negative %rsp offset (< 0) with known integer width, else #f
  (if (not (pair? inst))
      #f
      (let ((op (car inst)))
        (cond
          ((and (eq? op '%store)
                (>= (length inst) 4)
                (eq? (cadr inst) '%rsp)
                (integer? (caddr inst)))
           (let ((off (caddr inst)))
             (if (and (< off 0) (<= (+ off 8) 0) (not (eq? (cadddr inst) '%rsp)))
                 (cons off (+ off 8))
                 #f)))
          ((and (eq? op '%store-byte)
                (>= (length inst) 4)
                (eq? (cadr inst) '%rsp)
                (integer? (caddr inst)))
           (let ((off (caddr inst)))
             (if (and (< off 0) (<= (+ off 1) 0) (not (eq? (cadddr inst) '%rsp)))
                 (cons off (+ off 1))
                 #f)))
          ((and (eq? op '%store-typed)
                (>= (length inst) 5)
                (eq? (caddr inst) '%rsp)
                (integer? (cadddr inst)))
           (let* ((off (cadddr inst))
                  (w (lir-dse-type-width (cadr inst))))
             (if (and (< off 0) (<= (+ off w) 0) (not (eq? (list-ref inst 4) '%rsp)))
                 (cons off (+ off w))
                 #f)))
          (else #f)))))

(define (lir-dse-rsp-load-range inst)
  ;; Returns (lo . hi) for direct %rsp load, 'unknown if non-const %rsp load, or #f if not a %rsp load
  (if (not (pair? inst))
      #f
      (let ((op (car inst)))
        (cond
          ((and (eq? op '%load) (>= (length inst) 4) (eq? (caddr inst) '%rsp))
           (let ((off (cadddr inst)))
             (if (integer? off) (cons off (+ off 8)) 'unknown)))
          ((and (eq? op '%load-byte-zx) (>= (length inst) 4) (eq? (caddr inst) '%rsp))
           (let ((off (cadddr inst)))
             (if (integer? off) (cons off (+ off 1)) 'unknown)))
          ((and (eq? op '%load-typed) (>= (length inst) 5) (eq? (cadddr inst) '%rsp))
           (let ((off (list-ref inst 4))
                 (w (lir-dse-type-width (cadr inst))))
             (if (integer? off) (cons off (+ off w)) 'unknown)))
          (else #f)))))

(define (lir-dse-live-dead? live lo hi)
  (if (eq? (car live) 'exact)
      (not (lir-iv-overlaps? (cdr live) lo hi))
      (lir-iv-subsumed? (cdr live) lo hi)))

(define (lir-dse-live-mark-read live lo hi)
  (if (eq? (car live) 'exact)
      (cons 'exact (lir-iv-insert (cdr live) lo hi))
      (cons 'all-except (lir-iv-remove (cdr live) lo hi))))

(define (lir-dse-live-mark-written live lo hi)
  (if (eq? (car live) 'exact)
      (cons 'exact (lir-iv-remove (cdr live) lo hi))
      (cons 'all-except (lir-iv-insert (cdr live) lo hi))))

(define (lir-dse-fold-stack-opnds tree live)
  ;; Records any (%stack off) operands anywhere in tree into liveness state.
  (cond
    ((not (pair? tree)) live)
    ((eq? (car tree) '%stack)
     (let ((off (and (pair? (cdr tree)) (cadr tree))))
       (if (integer? off)
           (lir-dse-live-mark-read live off (+ off 8))
           '(all-except))))
    (else
     (lir-dse-fold-stack-opnds (cdr tree)
                               (lir-dse-fold-stack-opnds (car tree) live)))))

(define (lir-dse-collect-leaf-reads insts)
  ;; Scans all direct %rsp reads & (%stack off) reads in a function -> (unknown? . ivs)
  (let loop ((xs insts) (unk #f) (ivs '()))
    (if (or unk (null? xs))
        (cons unk ivs)
        (let* ((inst (car xs))
               (ld (lir-dse-rsp-load-range inst))
               (live0 (cons 'exact ivs))
               (live1 (lir-dse-fold-stack-opnds inst live0)))
          (cond
            ((eq? ld 'unknown)
             (loop (cdr xs) #t '()))
            ((eq? (car live1) 'all-except)
             (loop (cdr xs) #t '()))
            (ld
             (loop (cdr xs) #f (lir-iv-insert (cdr live1) (car ld) (cdr ld))))
            (else
             (loop (cdr xs) #f (cdr live1))))))))

(define (lir-eliminate-dead-stack-stores insts)
  (if (null? insts)
      '()
      (let* ((has-escape?
              (let loop ((xs insts))
                (and (pair? xs)
                     (or (lir-dse-inst-escapes-rsp? (car xs))
                         (loop (cdr xs))))))
             (has-barrier?
              (let loop ((xs insts))
                (and (pair? xs)
                     (or (lir-inst-memory-barrier? (car xs))
                         (lir-dse-inst-modifies-rsp? (car xs))
                         (loop (cdr xs))))))
             (leaf-info (if (and (not has-escape?) (not has-barrier?))
                            (lir-dse-collect-leaf-reads insts)
                            (cons #t '())))
             (leaf-exact-reads? (not (car leaf-info)))
             (leaf-read-ivs (cdr leaf-info)))
        (let loop ((xs (reverse insts))
                   (live '(all-except))
                   (acc '()))
          (if (null? xs)
              acc
              (let* ((inst (car xs))
                     (st (and (not (lir-dse-tree-contains-sym? inst '%stack))
                              (lir-dse-neg-store-range inst))))
                (if st
                    (let* ((lo (car st))
                           (hi (cdr st))
                           (dead? (or (and leaf-exact-reads?
                                           (not (lir-iv-overlaps? leaf-read-ivs lo hi)))
                                      (lir-dse-live-dead? live lo hi))))
                      (if dead?
                          (loop (cdr xs) live acc)
                          (loop (cdr xs) (lir-dse-live-mark-written live lo hi) (cons inst acc))))
                    (let ((next-live
                           (cond
                             ((and (pair? inst) (eq? (car inst) '%return))
                              (lir-dse-fold-stack-opnds (cdr inst) '(exact)))
                             ((or (not (pair? inst))
                                  (lir-inst-memory-barrier? inst)
                                  (and (lir-inst-terminates-block? inst)
                                       (not (lir-label-inst? inst)))
                                  (lir-dse-inst-modifies-rsp? inst))
                              '(all-except))
                             ((lir-dse-rsp-load-range inst)
                              => (lambda (ld)
                                   (if (eq? ld 'unknown)
                                       '(all-except)
                                       (lir-dse-fold-stack-opnds
                                        inst
                                        (lir-dse-live-mark-read live (car ld) (cdr ld))))))
                             ((and has-escape? (lir-dse-inst-indirect-read? inst))
                              '(all-except))
                             (else
                              (lir-dse-fold-stack-opnds inst live)))))
                      (loop (cdr xs) next-live (cons inst acc))))))))))

(define (lir-dse-transform-clause form)
  (if (not (pair? form))
      form
      (case (car form)
        ((%lir-function)
         (cons '%lir-function
               (map (lambda (sub)
                      (if (and (pair? sub) (eq? (car sub) 'body))
                          (cons 'body (lir-eliminate-dead-stack-stores (cdr sub)))
                          sub))
                    (cdr form))))
        ((%lir-main)
         (cons '%lir-main
               (map (lambda (sub)
                      (if (and (pair? sub) (eq? (car sub) 'body))
                          (cons 'body (lir-eliminate-dead-stack-stores (cdr sub)))
                          sub))
                    (cdr form))))
        ((%lir-functions)
         (cons '%lir-functions
               (map lir-dse-transform-clause (cdr form))))
        (else form))))

(define (lir-eliminate-dead-stack-stores-in-ir ir)
  (cond
    ((null? ir) '())
    ((and (pair? ir) (eq? (car ir) '%lir-program))
     (cons '%lir-program
           (map lir-dse-transform-clause (cdr ir))))
    ((pair? ir)
     (if (memq (car ir) '(%lir-function %lir-main))
         (lir-dse-transform-clause ir)
         (lir-eliminate-dead-stack-stores ir)))
    (else ir)))

;;; -----------------------------------------------------------------------
;;; Nanopass DSL Pass: lir-peephole-window-pass (fuse-window-rules) + DSE
;;; -----------------------------------------------------------------------

(define-pass lir-peephole-window-pass : L_lir_canonical (ir) -> L_lir_canonical ()
  (fuse-window-rules
    rule-lir-self-mov-elim
    rule-lir-self-fmov-elim
    rule-lir-roundtrip-mov-elim
    rule-lir-store-load-forward
    rule-lir-f64-store-load-forward
    rule-lir-jump-next-label-elim
    rule-lir-identity-arith-elim
    rule-lir-identity-mul-elim
    rule-lir-box-unbox-elim
    rule-lir-redundant-loc-elim
    rule-lir-unreachable-dce))

(define (lir-peephole-optimize ir)
  (let* ((w1 (lir-peephole-window-pass ir))
         (dse (lir-eliminate-dead-stack-stores-in-ir w1)))
    (if (equal? w1 dse)
        dse
        (lir-peephole-window-pass dse))))

(define (optimize-peephole-fixpoint insts)
  (lir-peephole-optimize insts))
