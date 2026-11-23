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
               (emit-lir! '(%mov %rdx %rax))
               (emit-lir! (list '%bit-or '%rdx (list '%stack si)))
               (emit-lir! (list '%bit-and '%rdx 3))
               (emit-lir! (list '%cmp '%rdx 0))
               (emit-lir! (list '%jump-cond "jne" lbl-slow))
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

(define (%bf-c99-add-label-ref! tbl lbl)
  (let ((slot (assq lbl (car tbl))))
    (if slot
        (set-cdr! slot (+ (cdr slot) 1))
        (set-car! tbl (cons (cons lbl 1) (car tbl))))))

(define (%bf-c99-count-label-refs insts)
  (let ((def-lbls-box (cons '() '()))
        (refs-box (cons '() '())))
    (for-each
     (lambda (inst)
       (if (and (pair? inst) (eq? (car inst) '%label) (pair? (cdr inst)))
           (set-car! def-lbls-box (cons (cadr inst) (car def-lbls-box)))))
     insts)
    (let ((def-lbls (car def-lbls-box)))
      (letrec ((scan-refs
                (lambda (x)
                  (cond
                    ((symbol? x)
                     (if (memq x def-lbls) (%bf-c99-add-label-ref! refs-box x)))
                    ((pair? x)
                     (scan-refs (car x))
                     (scan-refs (cdr x)))))))
        (for-each
         (lambda (inst)
           (if (not (and (pair? inst) (eq? (car inst) '%label)))
               (scan-refs inst)))
         insts)))
    (car refs-box)))

(define (%bf-c99-label-ref-count refs lbl)
  (let ((s (assq lbl refs)))
    (if s (cdr s) 0)))

(define (%bf-c99-build-label-map insts)
  (let loop ((xs insts) (acc '()))
    (if (null? xs)
        (reverse acc)
        (let ((inst (car xs)))
          (if (and (pair? inst) (eq? (car inst) '%label) (pair? (cdr inst)))
              (loop (cdr xs) (cons (cons (cadr inst) (cdr xs)) acc))
              (loop (cdr xs) acc))))))

(define (%bf-c99-tree-has? tree sym)
  (cond
    ((eq? tree sym) #t)
    ((pair? tree)
     (or (%bf-c99-tree-has? (car tree) sym)
         (%bf-c99-tree-has? (cdr tree) sym)))
    (else #f)))

(define (%bf-c99-rax-overwritten-before-read? insts lbl-map depth)
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
               ((memq op '(%direct-jump %jump))
                (let ((slot (assq (cadr inst) lbl-map)))
                  (if slot
                      (%bf-c99-rax-overwritten-before-read? (cdr slot) lbl-map (+ depth 1))
                      #f)))
               ((and (eq? op '%mov) (>= (length inst) 3) (eq? (cadr inst) '%rax))
                (not (%bf-c99-tree-has? (caddr inst) '%rax)))
               ((and (eq? op '%load) (>= (length inst) 4) (eq? (cadr inst) '%rax))
                (and (not (eq? (caddr inst) '%rax))
                     (not (%bf-c99-tree-has? (cadddr inst) '%rax))))
               ((and (eq? op '%load-typed) (>= (length inst) 5) (eq? (caddr inst) '%rax))
                (and (not (eq? (cadddr inst) '%rax))
                     (not (%bf-c99-tree-has? (car (cddddr inst)) '%rax))))
               ((and (memq op '(%global-addr %global-ref %str-ref %code-ref %pop %load-byte-zx))
                     (>= (length inst) 2)
                     (eq? (cadr inst) '%rax))
                (if (>= (length inst) 3)
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
      (letrec ((rw
                (lambda (x)
                  (cond
                    ((symbol? x)
                     (if (assq x redirects)
                         (%bf-c99-resolve-redirect redirects x)
                         x))
                    ((pair? x)
                     (cons (rw (car x)) (rw (cdr x))))
                    (else x)))))
        (map (lambda (inst)
               (if (and (pair? inst) (eq? (car inst) '%label))
                   inst
                   (rw inst)))
             insts))))

(define (%bf-c99-fuse-once insts)
  (if (or (null? insts) (null? (cdr insts)))
      insts
      (let* ((refs (%bf-c99-count-label-refs insts))
             (lbl-map (%bf-c99-build-label-map insts))
             (redirect-box (cons '() '()))
             (dead-rax?
              (lambda (fallthrough target-lbl)
                (and (%bf-c99-rax-overwritten-before-read? fallthrough lbl-map 0)
                     (let ((t-slot (assq target-lbl lbl-map)))
                       (and t-slot
                            (%bf-c99-rax-overwritten-before-read? (cdr t-slot) lbl-map 0)))))))
        (let loop ((xs insts) (acc '()))
          (if (null? xs)
              (%bf-c99-apply-redirects (reverse acc) (car redirect-box))
              (let ((i0 (car xs))
                    (t1 (cdr xs)))
                (cond
                  ;; Pattern B1: 9-instruction C99 comparison materialization + compare-zero + branch
                  ((and (>= (length xs) 9)
                        (pair? (list-ref xs 0)) (eq? (car (list-ref xs 0)) '%cmp)
                        (pair? (list-ref xs 1)) (eq? (car (list-ref xs 1)) '%jump-cond)
                        (pair? (list-ref xs 2)) (equal? (list-ref xs 2) '(%mov %rax 0))
                        (pair? (list-ref xs 3)) (eq? (car (list-ref xs 3)) '%direct-jump)
                        (pair? (list-ref xs 4)) (eq? (car (list-ref xs 4)) '%label)
                        (pair? (list-ref xs 5)) (equal? (list-ref xs 5) '(%mov %rax 1))
                        (pair? (list-ref xs 6)) (eq? (car (list-ref xs 6)) '%label)
                        (pair? (list-ref xs 7)) (equal? (list-ref xs 7) '(%cmp %rax 0))
                        (pair? (list-ref xs 8)) (eq? (car (list-ref xs 8)) '%jump-cond)
                        (eq? (caddr (list-ref xs 1)) (cadr (list-ref xs 4)))
                        (eq? (cadr (list-ref xs 3)) (cadr (list-ref xs 6)))
                        (= (%bf-c99-label-ref-count refs (cadr (list-ref xs 4))) 1)
                        (= (%bf-c99-label-ref-count refs (cadr (list-ref xs 6))) 1)
                        (memq (cadr (list-ref xs 8)) '(je jne))
                        (%bf-c99-invert-cc (cadr (list-ref xs 1)))
                        (dead-rax? (list-tail xs 9) (caddr (list-ref xs 8))))
                   (let* ((cc (cadr (list-ref xs 1)))
                          (jcc (cadr (list-ref xs 8)))
                          (target (caddr (list-ref xs 8)))
                          (fused-cc (if (eq? jcc 'je) (%bf-c99-invert-cc cc) cc)))
                     (loop (list-tail xs 9)
                           (cons (list '%jump-cond fused-cc target)
                                 (cons (list-ref xs 0) acc)))))

                  ;; Pattern B2: Short-circuit && / || diamond tail feeding (%cmp %rax 0) (%jump-cond je/jne target)
                  ((and (>= (length xs) 7)
                        (pair? (list-ref xs 0)) (eq? (car (list-ref xs 0)) '%mov)
                        (= (length (list-ref xs 0)) 3)
                        (eq? (cadr (list-ref xs 0)) '%rax)
                        (memq (caddr (list-ref xs 0)) '(0 1))
                        (pair? (list-ref xs 1)) (eq? (car (list-ref xs 1)) '%direct-jump)
                        (pair? (list-ref xs 2)) (eq? (car (list-ref xs 2)) '%label)
                        (pair? (list-ref xs 3)) (eq? (car (list-ref xs 3)) '%mov)
                        (= (length (list-ref xs 3)) 3)
                        (eq? (cadr (list-ref xs 3)) '%rax)
                        (memq (caddr (list-ref xs 3)) '(0 1))
                        (not (= (caddr (list-ref xs 0)) (caddr (list-ref xs 3))))
                        (pair? (list-ref xs 4)) (eq? (car (list-ref xs 4)) '%label)
                        (pair? (list-ref xs 5)) (equal? (list-ref xs 5) '(%cmp %rax 0))
                        (pair? (list-ref xs 6)) (eq? (car (list-ref xs 6)) '%jump-cond)
                        (eq? (cadr (list-ref xs 1)) (cadr (list-ref xs 4)))
                        (= (%bf-c99-label-ref-count refs (cadr (list-ref xs 4))) 1)
                        (memq (cadr (list-ref xs 6)) '(je jne))
                        (not (eq? (caddr (list-ref xs 6)) (cadr (list-ref xs 2))))
                        (not (eq? (caddr (list-ref xs 6)) (cadr (list-ref xs 4))))
                        (dead-rax? (list-tail xs 7) (caddr (list-ref xs 6))))
                   (let* ((k1 (caddr (list-ref xs 0)))
                          (mid-lbl (cadr (list-ref xs 2)))
                          (jcc (cadr (list-ref xs 6)))
                          (target (caddr (list-ref xs 6)))
                          (k1-taken? (if (eq? jcc 'je) (= k1 0) (not (= k1 0)))))
                     (if k1-taken?
                         ;; k1 jumps to target; k2 (i.e. mid-lbl) falls through directly
                         (loop (list-tail xs 7)
                               (cons (list '%label mid-lbl)
                                     (cons (list '%direct-jump target) acc)))
                         ;; k1 falls through; mid-lbl (k2) jumps to target
                         (begin
                           (set-car! redirect-box (cons (cons mid-lbl target) (car redirect-box)))
                           (loop (list-tail xs 7) acc)))))

                  ;; Pattern B3: Conditional jump to immediately following label -> drop jump
                  ((and (pair? t1)
                        (pair? i0)
                        (eq? (car i0) '%jump-cond)
                        (= (length i0) 3)
                        (pair? (car t1))
                        (eq? (caar t1) '%label)
                        (eq? (caddr i0) (cadar t1)))
                   (loop t1 acc))

                  ;; Pattern B4: Direct jump to immediately following label -> drop jump
                  ((and (pair? t1)
                        (pair? i0)
                        (eq? (car i0) '%direct-jump)
                        (pair? (car t1))
                        (eq? (caar t1) '%label)
                        (eq? (cadr i0) (cadar t1)))
                   (loop t1 acc))

                  (else
                   (loop t1 (cons i0 acc))))))))))

(define (lir-fuse-c99-branches-in-body insts)
  (let ((r1 (%bf-c99-fuse-once insts)))
    (if (equal? r1 insts)
        insts
        (let ((r2 (%bf-c99-fuse-once r1)))
          (if (equal? r2 r1) r1 r2)))))

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
           (if (equal? new-c (cdr form)) form (cons '%lir-function new-c))))
        ((%lir-main)
         (let ((new-c (map (lambda (sub)
                             (if (and (pair? sub) (eq? (car sub) 'body))
                                 (let* ((ob (cdr sub))
                                        (nb (lir-fuse-c99-branches-in-body ob)))
                                   (if (eq? nb ob) sub (cons 'body nb)))
                                 sub))
                           (cdr form))))
           (if (equal? new-c (cdr form)) form (cons '%lir-main new-c))))
        ((%lir-functions)
         (let ((nf (map %bf-c99-transform-clause (cdr form))))
           (if (equal? nf (cdr form)) form (cons '%lir-functions nf))))
        (else form))))

(define (lir-fuse-c99-branches-in-ir ir)
  (cond
    ((null? ir) '())
    ((and (pair? ir) (eq? (car ir) '%lir-program))
     (let ((nb (map %bf-c99-transform-clause (cdr ir))))
       (if (equal? nb (cdr ir)) ir (cons '%lir-program nb))))
    ((pair? ir)
     (if (memq (car ir) '(%lir-function %lir-main))
         (%bf-c99-transform-clause ir)
         (lir-fuse-c99-branches-in-body ir)))
    (else ir)))

(define (lir-fuse-branches ir)
  (let* ((w (%lir-fuse-branches-window ir))
         (c (lir-fuse-c99-branches-in-ir w)))
    (if (equal? c ir) ir c)))

(define (optimize-branch-fusion insts)
  (lir-fuse-branches insts))
