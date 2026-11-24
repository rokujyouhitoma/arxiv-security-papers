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
    ((integer? e)
     (let ((q (quotient e 1073741824)))
       (if (or (>= q 536870912) (<= q -536870912))
           #f
           (* e 4))))
    ((and (pair? e) (eq? (car e) '%unbox-fixnum) (integer? (cadr e))) (cadr e))
    (else #f)))

(define (lir-known-fixnum-const? e)
  (let ((x (if (ast-has-span? e) (ast-strip-span e) e)))
    (cond
      ((integer? x)
       (let ((q (quotient x 1073741824)))
         (and (< q 536870912) (> q -536870912))))
      ((and (pair? x)
            (memq (car x) '(quote atom-value %unbox-fixnum %box-fixnum))
            (pair? (cdr x)))
       (lir-known-fixnum-const? (cadr x)))
      (else #f))))

(define (emit-lir-bin-tag-check! e1 e2 si lbl-slow)
  (let ((k1? (lir-known-fixnum-const? e1))
        (k2? (lir-known-fixnum-const? e2)))
    (cond
      ((and k1? k2?)
       #f)
      (k2?
       (emit-lir! (list '%load '%rdx '%rsp si))
       (emit-lir! (list '%bit-and '%rdx 3))
       (emit-lir! (list '%cmp '%rdx 0))
       (emit-lir! (list '%jump-cond "jne" lbl-slow)))
      (k1?
       (emit-lir! '(%mov %rdx %rax))
       (emit-lir! (list '%bit-and '%rdx 3))
       (emit-lir! (list '%cmp '%rdx 0))
       (emit-lir! (list '%jump-cond "jne" lbl-slow)))
      (else
       (emit-lir! '(%mov %rdx %rax))
       (emit-lir! (list '%bit-or '%rdx (list '%stack si)))
       (emit-lir! (list '%bit-and '%rdx 3))
       (emit-lir! (list '%cmp '%rdx 0))
       (emit-lir! (list '%jump-cond "jne" lbl-slow))))))

(define (lir-num-cmp-slow-fn op)
  (case op
    ((=)  'ulisp_fn_num_eq)
    ((<)  'ulisp_fn_num_lt)
    ((<=) 'ulisp_fn_num_lt_eq)
    ((>)  'ulisp_fn_num_gt)
    ((>=) 'ulisp_fn_num_gt_eq)
    (else #f)))

(define (lir-compile-fused-cmp-cond op e1 e2 target-label jmp-cc-fn si env)
  (let* ((jmp-op (jmp-cc-fn op))
         (r1 (env-reg-var? e1 env))
         (r2 (env-reg-var? e2 env))
         (c1 (extract-fused-cmp-int e1))
         (c2 (extract-fused-cmp-int e2))
         (raw-vars (get-raw-vars env))
         (is-raw? (or (raw-expr? e1 raw-vars) (raw-expr? e2 raw-vars)))
         (allow-imm? (or (eq? op 'eq?) is-raw?
                         (and (integer? e1) (integer? e2))
                         (and (pair? e2) (eq? (car e2) '%unbox-fixnum))
                         (and (pair? e1) (eq? (car e1) '%unbox-fixnum)))))
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

      ;; 6. e2 is integer constant (raw or eq?) -> evaluate e1 to rax, then cmp rax, c2
      ((and c2 allow-imm?)
       (lir-compile-operand-for-op op e1 si env)
       (emit-lir! (list '%cmp '%rax c2))
       (emit-lir! (list '%jump-cond jmp-op target-label)))

      ;; 7. e1 is integer constant (raw or eq?) -> evaluate e2 to rax, then reverse cmp rax, c1
      ((and c1 allow-imm?)
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

      ;; 8. General fallback: evaluate e1 to stack, evaluate e2 to rax
      (else
       (track-lir-si! si)
       (lir-compile-operand-for-op op e1 si env)
       (emit-lir! (list '%store '%rsp si '%rax))
       (track-lir-si! (- si 8))
       (lir-compile-operand-for-op op e2 (- si 8) env)
       (let ((slow-fn (if (not is-raw?) (lir-num-cmp-slow-fn op) #f)))
         (if slow-fn
             (let ((lbl-slow (unique-label-sym "cmp_br_slow"))
                   (lbl-cont (unique-label-sym "cmp_br_cont"))
                   (jump-if-true? (string=? (jmp-cc-fn '=) "je")))
               (emit-lir-bin-tag-check! e1 e2 si lbl-slow)
               (emit-lir! (list '%cmp (list '%stack si) '%rax))
               (emit-lir! (list '%jump-cond jmp-op target-label))
               (emit-lir! (list '%jump lbl-cont))
               (emit-lir! (list '%label lbl-slow))
               (emit-lir! (list '%load '%rdi '%rsp si))
               (emit-lir! '(%mov %rsi %rax))
               (let* ((frame-shift (align-frame-shift (- 0 si)))
                      (bitmap (compute-stackmap-bitmap frame-shift (- 0 frame-shift) '() env))
                      (safepoint-lbl (new-safepoint-label!)))
                 (record-safepoint! safepoint-lbl frame-shift bitmap)
                 (emit-lir! (list '%mov '%rax 8))
                 (emit-lir! (list '%direct-call slow-fn frame-shift safepoint-lbl)))
               (emit-lir! (list '%cmp '%rax 47))
               (emit-lir! (list '%jump-cond (if jump-if-true? "jne" "je") target-label))
               (emit-lir! (list '%label lbl-cont)))
             (begin
               (emit-lir! (list '%cmp (list '%stack si) '%rax))
               (emit-lir! (list '%jump-cond jmp-op target-label)))))))))

(define (lir-compile-fused-cmp op e1 e2 else-label si env)
  (lir-compile-fused-cmp-cond op e1 e2 else-label lir-cmp-false-cc si env))

;;; -----------------------------------------------------------------------
;;; First-Class Branch Fusion Picopass Rules (DSN-33-01 T5.3)
;;; -----------------------------------------------------------------------

;; Pattern 1: (%cmp opnd1 opnd2) followed by (%set-boolean reg cond) and (%jump-if-false reg lbl)
;; -> (%cmp opnd1 opnd2) followed by (%jump-cond (invert-cc cond) lbl)
(define-picopass rule-lir-fuse-cmp-branch-invert
  (InstWindow
    (((%cmp ,opnd1 ,opnd2) (%set-boolean ,reg1 ,cond) (%jump-if-false ,reg2 ,lbl) . ,rest)
     (guard (equal? reg1 reg2))
     (cons (list '%cmp opnd1 opnd2)
           (cons (list '%jump-cond (lir-invert-cond-op cond) lbl)
                 rest)))
    (((%raw-cmp ,opnd1 ,opnd2) (%set-boolean ,reg1 ,cond) (%jump-if-false ,reg2 ,lbl) . ,rest)
     (guard (equal? reg1 reg2))
     (cons (list '%raw-cmp opnd1 opnd2)
           (cons (list '%jump-cond (lir-invert-cond-op cond) lbl)
                 rest)))))

;; Pattern 2: (%set-boolean reg cond) followed by (%jump-if-false reg lbl)
;; -> (%jump-cond (invert-cc cond) lbl)
(define-picopass rule-lir-fuse-set-boolean-branch
  (InstWindow
    (((%set-boolean ,reg1 ,cond) (%jump-if-false ,reg2 ,lbl) . ,rest)
     (guard (equal? reg1 reg2))
     (cons (list '%jump-cond (lir-invert-cond-op cond) lbl)
           rest))))

;; Pattern 3: (%cmp reg const) followed by (%jump-if-false reg2 lbl)
;; -> (%cmp reg const) followed by (%jump-cond "jne" lbl)
(define-picopass rule-lir-fuse-cmp-jne-branch
  (InstWindow
    (((%cmp ,opnd1 ,opnd2) (%jump-if-false ,reg ,lbl) . ,rest)
     (cons (list '%cmp opnd1 opnd2)
           (cons (list '%jump-cond "jne" lbl)
                 rest)))
    (((%raw-cmp ,opnd1 ,opnd2) (%jump-if-false ,reg ,lbl) . ,rest)
     (cons (list '%raw-cmp opnd1 opnd2)
           (cons (list '%jump-cond "jne" lbl)
                 rest)))))

;;; -----------------------------------------------------------------------
;;; Nanopass DSL Pass: lir-fuse-branches (fuse-window-rules)
;;; -----------------------------------------------------------------------

(define-pass %lir-fuse-branches-window : L_lir_canonical (ir) -> L_lir_canonical ()
  (fuse-window-rules
    rule-lir-fuse-cmp-branch-invert
    rule-lir-fuse-set-boolean-branch
    rule-lir-fuse-cmp-jne-branch))

;;; -----------------------------------------------------------------------
;;; C99 Comparison Diamond, Short-Circuit & Jump Fusion (Issue #927)
;;; -----------------------------------------------------------------------

(define (%bf-c99-invert-cc cc)
  (case cc
    ((je)  'jne)
    ((jne) 'je)
    ((jl)  'jge)
    ((jge) 'jl)
    ((jle) 'jg)
    ((jg)  'jle)
    ((jb)  'jae)
    ((jae) 'jb)
    ((jbe) 'ja)
    ((ja)  'jbe)
    (else
     (cond
       ((equal? cc "je")  "jne")
       ((equal? cc "jne") "je")
       ((equal? cc "jl")  "jge")
       ((equal? cc "jge") "jl")
       ((equal? cc "jle") "jg")
       ((equal? cc "jg")  "jle")
       (else #f)))))

(define (%bf-ht-make)
  (make-vector 1024 '()))

(define (%bf-ht-ref ht sym default)
  (let* ((idx (symbol->hash-idx sym))
         (entry (assq sym (vector-ref ht idx))))
    (if entry (cdr entry) default)))

(define (%bf-ht-set! ht sym val)
  (let* ((idx (symbol->hash-idx sym))
         (bucket (vector-ref ht idx))
         (entry (assq sym bucket)))
    (if entry
        (set-cdr! entry val)
        (vector-set! ht idx (cons (cons sym val) bucket)))))

(define (%bf-ht-inc! ht sym)
  (let* ((idx (symbol->hash-idx sym))
         (bucket (vector-ref ht idx))
         (entry (assq sym bucket)))
    (if entry
        (set-cdr! entry (+ (cdr entry) 1))
        (vector-set! ht idx (cons (cons sym 1) bucket)))))

(define (%bf-c99-has-cmp-rax-zero? insts)
  (let loop ((xs insts))
    (if (null? xs)
        #f
        (let ((inst (car xs)))
          (if (and (pair? inst)
                   (eq? (car inst) '%cmp)
                   (pair? (cdr inst))
                   (eq? (cadr inst) '%rax)
                   (pair? (cddr inst))
                   (eqv? (caddr inst) 0)
                   (null? (cdddr inst)))
              #t
              (loop (cdr xs)))))))

(define (%bf-c99-drop-adjacent-jumps insts)
  ;; O(N) fast pass for Scheme & simple functions: handles Patterns B3/B4
  ;; without allocating hash tables or scanning lists twice; returns original
  ;; `insts` by eq? when unchanged.
  (let loop ((xs insts) (rev-prefix '()) (changed? #f))
    (if (null? xs)
        (if changed? (reverse rev-prefix) insts)
        (let ((i0 (car xs))
              (t1 (cdr xs)))
          (if (and (pair? t1)
                   (pair? i0)
                   (pair? (car t1))
                   (eq? (caar t1) '%label)
                   (pair? (cdar t1))
                   (let ((next-lbl (cadar t1))
                         (op (car i0)))
                     (or (and (eq? op '%jump-cond)
                              (pair? (cdr i0))
                              (pair? (cddr i0))
                              (null? (cdddr i0))
                              (eq? (caddr i0) next-lbl))
                         (and (eq? op '%direct-jump)
                              (pair? (cdr i0))
                              (eq? (cadr i0) next-lbl)))))
              (loop t1
                    (if changed?
                        rev-prefix
                        (let copy ((p insts) (acc '()))
                          (if (eq? p xs)
                              acc
                              (copy (cdr p) (cons (car p) acc)))))
                    #t)
              (loop t1
                    (if changed? (cons i0 rev-prefix) rev-prefix)
                    changed?))))))

(define (%bf-c99-count-label-refs insts)
  (let ((def-ht (%bf-ht-make))
        (refs-ht (%bf-ht-make)))
    (for-each
     (lambda (inst)
       (if (and (pair? inst) (eq? (car inst) '%label) (pair? (cdr inst)) (symbol? (cadr inst)))
           (%bf-ht-set! def-ht (cadr inst) #t)))
     insts)
    (letrec ((scan-refs
              (lambda (x)
                (cond
                  ((symbol? x)
                   (if (%bf-ht-ref def-ht x #f)
                       (%bf-ht-inc! refs-ht x)))
                  ((pair? x)
                   (scan-refs (car x))
                   (scan-refs (cdr x)))))))
      (for-each
       (lambda (inst)
         (if (not (and (pair? inst) (eq? (car inst) '%label)))
             (scan-refs inst)))
       insts))
    refs-ht))

(define (%bf-c99-build-label-map insts)
  (let ((lbl-ht (%bf-ht-make)))
    (let loop ((xs insts))
      (if (null? xs)
          lbl-ht
          (let ((inst (car xs)))
            (if (and (pair? inst) (eq? (car inst) '%label) (pair? (cdr inst)) (symbol? (cadr inst)))
                (%bf-ht-set! lbl-ht (cadr inst) (cdr xs)))
            (loop (cdr xs)))))))

(define (%bf-c99-tree-has? tree sym)
  (cond
    ((eq? tree sym) #t)
    ((pair? tree)
     (or (%bf-c99-tree-has? (car tree) sym)
         (%bf-c99-tree-has? (cdr tree) sym)))
    (else #f)))

(define (%bf-c99-rax-overwritten-before-read? insts lbl-ht depth)
  (if (> depth 8)
      #f
      (let loop ((xs insts) (steps 0))
        (cond
          ((or (null? xs) (> steps 10)) #f)
          ((not (pair? (car xs))) #f)
          (else
           (let* ((inst (car xs))
                  (op (car inst)))
             (cond
               ((eq? op '%label)
                (loop (cdr xs) steps))
               ((or (eq? op '%direct-jump) (eq? op '%jump))
                (let ((tail (and (symbol? (cadr inst)) (%bf-ht-ref lbl-ht (cadr inst) #f))))
                  (if tail
                      (%bf-c99-rax-overwritten-before-read? tail lbl-ht (+ depth 1))
                      #f)))
               ((and (eq? op '%mov) (pair? (cdr inst)) (pair? (cddr inst)) (null? (cdddr inst))
                     (eq? (cadr inst) '%rax))
                (not (%bf-c99-tree-has? (caddr inst) '%rax)))
               ((and (eq? op '%load) (pair? (cdr inst)) (pair? (cddr inst)) (pair? (cdddr inst))
                     (eq? (cadr inst) '%rax))
                (and (not (eq? (caddr inst) '%rax))
                     (not (%bf-c99-tree-has? (cadddr inst) '%rax))))
               ((and (eq? op '%load-typed) (>= (length inst) 5) (eq? (caddr inst) '%rax))
                (and (not (eq? (cadddr inst) '%rax))
                     (not (%bf-c99-tree-has? (car (cddddr inst)) '%rax))))
               ((and (case op ((%global-addr %global-ref %str-ref %code-ref %pop %load-byte-zx) #t) (else #f))
                     (pair? (cdr inst))
                     (eq? (cadr inst) '%rax))
                (if (pair? (cddr inst))
                    (not (%bf-c99-tree-has? (cddr inst) '%rax))
                    #t))
               ;; Calls read %rax only for varargs (%al) if not cleared, conservatively check %rax mention
               ((%bf-c99-tree-has? inst '%rax)
                #f)
               ((eq? op '%return)
                #f)
               ((lir-inst-terminates-block? inst)
                #f)
               (else
                (loop (cdr xs) (+ steps 1))))))))))

(define (%bf-c99-resolve-redirect redirects lbl)
  (let loop ((cur lbl) (seen '()))
    (if (memq cur seen)
        cur
        (let ((slot (assq cur redirects)))
          (if slot
              (loop (cdr slot) (cons cur seen))
              cur)))))

(define (%bf-c99-apply-redirects insts redirects)
  (if (null? redirects)
      insts
      (let ((redir-ht (%bf-ht-make)))
        (for-each (lambda (p)
                    (%bf-ht-set! redir-ht (car p) (%bf-c99-resolve-redirect redirects (car p))))
                  redirects)
        (letrec ((rw
                  (lambda (x)
                    (cond
                      ((symbol? x)
                       (or (%bf-ht-ref redir-ht x #f) x))
                      ((pair? x)
                       (cons (rw (car x)) (rw (cdr x))))
                      (else x)))))
          (map (lambda (inst)
                 (if (and (pair? inst) (eq? (car inst) '%label))
                     inst
                     (rw inst)))
               insts)))))

(define (%bf-c99-match-mov-rax-k? inst)
  (and (pair? inst)
       (eq? (car inst) '%mov)
       (pair? (cdr inst))
       (eq? (cadr inst) '%rax)
       (pair? (cddr inst))
       (null? (cdddr inst))
       (let ((k (caddr inst)))
         (or (eqv? k 0) (eqv? k 1)))))

(define (%bf-c99-cmp-rax-0? inst)
  (and (pair? inst)
       (eq? (car inst) '%cmp)
       (pair? (cdr inst))
       (eq? (cadr inst) '%rax)
       (pair? (cddr inst))
       (eqv? (caddr inst) 0)
       (null? (cdddr inst))))

(define (%bf-c99-fuse-once insts)
  (if (or (null? insts) (null? (cdr insts)))
      insts
      (let* ((refs-ht (%bf-c99-count-label-refs insts))
             (lbl-ht (%bf-c99-build-label-map insts))
             (redirect-box (cons '() '()))
             (dead-rax?
              (lambda (fallthrough target-lbl)
                (and (%bf-c99-rax-overwritten-before-read? fallthrough lbl-ht 0)
                     (let ((t-tail (and (symbol? target-lbl) (%bf-ht-ref lbl-ht target-lbl #f))))
                       (and t-tail
                            (%bf-c99-rax-overwritten-before-read? t-tail lbl-ht 0))))))
             (copy-prefix
              (lambda (stop-cell)
                (let loop ((p insts) (acc '()))
                  (if (eq? p stop-cell)
                      acc
                      (loop (cdr p) (cons (car p) acc)))))))
        (let loop ((xs insts) (acc '()) (changed? #f))
          (if (null? xs)
              (if changed?
                  (%bf-c99-apply-redirects (reverse acc) (car redirect-box))
                  insts)
              (let ((i0 (car xs))
                    (t1 (cdr xs)))
                (cond
                  ;; Pattern B1: 9-instruction C99 comparison materialization + compare-zero + branch
                  ((and (pair? i0)
                        (eq? (car i0) '%cmp)
                        (pair? t1) (pair? (cdr t1)) (pair? (cddr t1)) (pair? (cdddr t1))
                        (let ((t5 (cddddr t1)))
                          (and (pair? t5) (pair? (cdr t5)) (pair? (cddr t5)) (pair? (cdddr t5))
                               (let ((x1 (car t1))
                                     (x2 (cadr t1))
                                     (x3 (caddr t1))
                                     (x4 (cadddr t1))
                                     (x5 (car t5))
                                     (x6 (cadr t5))
                                     (x7 (caddr t5))
                                     (x8 (cadddr t5)))
                                 (and (pair? x1) (eq? (car x1) '%jump-cond)
                                      (pair? x2) (eq? (car x2) '%mov) (pair? (cdr x2)) (eq? (cadr x2) '%rax)
                                      (pair? (cddr x2)) (eqv? (caddr x2) 0) (null? (cdddr x2))
                                      (pair? x3) (eq? (car x3) '%direct-jump)
                                      (pair? x4) (eq? (car x4) '%label)
                                      (pair? x5) (eq? (car x5) '%mov) (pair? (cdr x5)) (eq? (cadr x5) '%rax)
                                      (pair? (cddr x5)) (eqv? (caddr x5) 1) (null? (cdddr x5))
                                      (pair? x6) (eq? (car x6) '%label)
                                      (%bf-c99-cmp-rax-0? x7)
                                      (pair? x8) (eq? (car x8) '%jump-cond)
                                      (eq? (caddr x1) (cadr x4))
                                      (eq? (cadr x3) (cadr x6))
                                      (symbol? (cadr x4)) (= (%bf-ht-ref refs-ht (cadr x4) 0) 1)
                                      (symbol? (cadr x6)) (= (%bf-ht-ref refs-ht (cadr x6) 0) 1)
                                      (or (eq? (cadr x8) 'je) (eq? (cadr x8) 'jne))
                                      (%bf-c99-invert-cc (cadr x1))
                                      (dead-rax? (cddddr t5) (caddr x8)))))))
                   (let* ((t5 (cddddr t1))
                          (x1 (car t1))
                          (x8 (cadddr t5))
                          (cc (cadr x1))
                          (jcc (cadr x8))
                          (target (caddr x8))
                          (fused-cc (if (eq? jcc 'je) (%bf-c99-invert-cc cc) cc))
                          (cur-acc (if changed? acc (copy-prefix xs))))
                     (loop (cddddr t5)
                           (cons (list '%jump-cond fused-cc target)
                                 (cons i0 cur-acc))
                           #t)))

                  ;; Pattern B2: Short-circuit && / || diamond tail feeding (%cmp %rax 0) (%jump-cond je/jne target)
                  ((and (%bf-c99-match-mov-rax-k? i0)
                        (pair? t1) (pair? (cdr t1)) (pair? (cddr t1)) (pair? (cdddr t1))
                        (let ((t5 (cddddr t1)))
                          (and (pair? t5) (pair? (cdr t5))
                               (let ((x1 (car t1))
                                     (x2 (cadr t1))
                                     (x3 (caddr t1))
                                     (x4 (cadddr t1))
                                     (x5 (car t5))
                                     (x6 (cadr t5)))
                                 (and (pair? x1) (eq? (car x1) '%direct-jump)
                                      (pair? x2) (eq? (car x2) '%label)
                                      (%bf-c99-match-mov-rax-k? x3)
                                      (not (= (caddr i0) (caddr x3)))
                                      (pair? x4) (eq? (car x4) '%label)
                                      (%bf-c99-cmp-rax-0? x5)
                                      (pair? x6) (eq? (car x6) '%jump-cond)
                                      (eq? (cadr x1) (cadr x4))
                                      (symbol? (cadr x4)) (= (%bf-ht-ref refs-ht (cadr x4) 0) 1)
                                      (or (eq? (cadr x6) 'je) (eq? (cadr x6) 'jne))
                                      (not (eq? (caddr x6) (cadr x2)))
                                      (not (eq? (caddr x6) (cadr x4)))
                                      (dead-rax? (cddr t5) (caddr x6)))))))
                   (let* ((t5 (cddddr t1))
                          (x2 (cadr t1))
                          (x6 (cadr t5))
                          (k1 (caddr i0))
                          (mid-lbl (cadr x2))
                          (jcc (cadr x6))
                          (target (caddr x6))
                          (k1-taken? (if (eq? jcc 'je) (= k1 0) (not (= k1 0))))
                          (cur-acc (if changed? acc (copy-prefix xs))))
                     (if k1-taken?
                         (loop (cddr t5)
                               (cons (list '%label mid-lbl)
                                     (cons (list '%direct-jump target) cur-acc))
                               #t)
                         (begin
                           (set-car! redirect-box (cons (cons mid-lbl target) (car redirect-box)))
                           (loop (cddr t5) cur-acc #t)))))

                  ;; Pattern B3: Conditional jump to immediately following label -> drop jump
                  ((and (pair? t1)
                        (pair? i0)
                        (eq? (car i0) '%jump-cond)
                        (pair? (cdr i0)) (pair? (cddr i0)) (null? (cdddr i0))
                        (pair? (car t1))
                        (eq? (caar t1) '%label)
                        (eq? (caddr i0) (cadar t1)))
                   (loop t1 (if changed? acc (copy-prefix xs)) #t))

                  ;; Pattern B4: Direct jump to immediately following label -> drop jump
                  ((and (pair? t1)
                        (pair? i0)
                        (eq? (car i0) '%direct-jump)
                        (pair? (cdr i0))
                        (pair? (car t1))
                        (eq? (caar t1) '%label)
                        (eq? (cadr i0) (cadar t1)))
                   (loop t1 (if changed? acc (copy-prefix xs)) #t))

                  (else
                   (loop t1 (if changed? (cons i0 acc) acc) changed?)))))))))

(define (lir-fuse-c99-branches-in-body insts)
  (if (or (null? insts) (null? (cdr insts)))
      insts
      (if (%bf-c99-has-cmp-rax-zero? insts)
          (let ((r1 (%bf-c99-fuse-once insts)))
            (if (eq? r1 insts)
                insts
                (let ((r2 (%bf-c99-fuse-once r1)))
                  (if (eq? r2 r1) r1 r2))))
          (%bf-c99-drop-adjacent-jumps insts))))

(define (%bf-c99-transform-clause form)
  (if (not (pair? form))
      form
      (case (car form)
        ((%lir-function)
         (let ((new-c (map (lambda (sub)
                             (if (and (pair? sub) (eq? (car sub) 'body))
                                 (let* ((ob (cdr sub))
                                        (nb (lir-fuse-c99-branches-in-body ob)))
                                   (if (eq? nb ob) sub (cons 'body nb)))
                                 sub))
                           (cdr form))))
           (cons '%lir-function new-c)))
        ((%lir-main)
         (let ((new-c (map (lambda (sub)
                             (if (and (pair? sub) (eq? (car sub) 'body))
                                 (let* ((ob (cdr sub))
                                        (nb (lir-fuse-c99-branches-in-body ob)))
                                   (if (eq? nb ob) sub (cons 'body nb)))
                                 sub))
                           (cdr form))))
           (cons '%lir-main new-c)))
        ((%lir-functions)
         (let ((nf (map %bf-c99-transform-clause (cdr form))))
           (cons '%lir-functions nf)))
        (else form))))

(define (lir-fuse-c99-branches-in-ir ir)
  (cond
    ((null? ir) '())
    ((and (pair? ir) (eq? (car ir) '%lir-program))
     (cons '%lir-program (map %bf-c99-transform-clause (cdr ir))))
    ((pair? ir)
     (if (or (eq? (car ir) '%lir-function) (eq? (car ir) '%lir-main))
         (%bf-c99-transform-clause ir)
         (lir-fuse-c99-branches-in-body ir)))
    (else ir)))

(define (lir-fuse-branches ir)
  (let* ((w (%lir-fuse-branches-window ir))
         (c (lir-fuse-c99-branches-in-ir w)))
    (if (eq? c ir) ir c)))

(define (optimize-branch-fusion insts)
  (lir-fuse-branches insts))
