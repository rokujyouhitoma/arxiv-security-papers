;;; =======================================================================
;;; ULisp Compiler: Canonical LIR Specification Verifier & Boundary Validator
;;; Conforms to DSN-33 Architecture Specification & Issue #589
;;; =======================================================================

(define *canonical-lir-registers*
  '(%rax %rbx %rcx %rdx %rsi %rdi %rbp %rsp
    %r8  %r9  %r10 %r11 %r12 %r13 %r14 %r15 %al))

(define *canonical-lir-float-registers*
  '(%xmm0 %xmm1 %xmm2 %xmm3 %xmm4 %xmm5 %xmm6 %xmm7
    %xmm8 %xmm9 %xmm10 %xmm11 %xmm12 %xmm13 %xmm14 %xmm15))

(define *canonical-lir-machine-types*
  '(i8 i16 i32 i64 u8 u16 u32 u64 f32 f64 ptr raw-bits scheme-val))

(define *managed-dialect-opcodes*
  '(%alloc
    %alloc-stack
    %managed-alloc
    %managed-alloc-stack
    %managed-safepoint-poll
    %managed-write-barrier
    %managed-box
    %managed-unbox
    %box-fixnum
    %unbox-fixnum
    %box-flonum
    %unbox-flonum
    %capture-cc
    %push-handler
    %pop-handler
    %raise
    %set-values-count
    %store-values-buf))

(define (managed-dialect-opcode? op)
  (if (memq op *managed-dialect-opcodes*) #t #f))

(define (lir-machine-type? ty)
  (if (memq ty *canonical-lir-machine-types*) #t #f))

(define (lir-symbol-starts-with-percent? sym)
  (and (symbol? sym)
       (let ((str (symbol->string sym)))
         (and (> (string-length str) 1)
              (char=? (string-ref str 0) #\%)))))

(define (lir-float-register? reg)
  (cond
    ((memq reg *canonical-lir-float-registers*) #t)
    ((and (pair? reg) (eq? (car reg) '%reg) (pair? (cdr reg))
          (memq (cadr reg) *canonical-lir-float-registers*)) #t)
    ((and (pair? reg) (eq? (car reg) '%reg) (pair? (cdr reg)) (pair? (cddr reg))
          (memq (cadr reg) '(f32 f64))) #t)
    ((and (pair? reg) (eq? (car reg) '%freg) (pair? (cdr reg))) #t)
    (else #f)))

(define (lir-float-operand? opnd)
  (or (lir-float-register? opnd)
      (and (pair? opnd) (eq? (car opnd) '%mem))
      (and (pair? opnd) (eq? (car opnd) '%stack))
      (number? opnd)))

(define (lir-valid-register? reg)
  (cond
    ((memq reg *canonical-lir-registers*) #t)
    ((memq reg *canonical-lir-float-registers*) #t)
    ((and (pair? reg) (eq? (car reg) '%reg) (pair? (cdr reg)))
     (cond
       ((and (pair? (cddr reg)) (lir-machine-type? (cadr reg))) #t)
       ((memq (cadr reg) *canonical-lir-registers*) #t)
       ((memq (cadr reg) *canonical-lir-float-registers*) #t)
       (else (symbol? (cadr reg)))))
    ((and (pair? reg) (eq? (car reg) '%freg) (pair? (cdr reg)) (symbol? (cadr reg))) #t)
    (else #f)))

(define (lir-valid-sib? sib)
  (and (pair? sib)
       (eq? (car sib) '%sib)
       (= (length sib) 4)
       (lir-valid-register? (cadr sib))
       (integer? (caddr sib))
       (integer? (cadddr sib))))

(define (lir-valid-offset? off)
  (or (integer? off)
      (lir-valid-register? off)
      (lir-valid-sib? off)))

(define (lir-valid-lvalue? opnd)
  (cond
    ((lir-valid-register? opnd) #t)
    ((and (pair? opnd) (eq? (car opnd) '%stack) (pair? (cdr opnd))
          (integer? (cadr opnd))) #t)
    ((and (pair? opnd) (eq? (car opnd) '%mem) (pair? (cdr opnd)) (pair? (cddr opnd)))
     (and (lir-valid-register? (cadr opnd))
          (lir-valid-offset? (caddr opnd))))
    ((and (symbol? opnd) (not (lir-symbol-starts-with-percent? opnd))) #t)
    (else #f)))

(define (lir-valid-operand? opnd)
  (cond
    ((lir-valid-register? opnd) #t)
    ((integer? opnd) #t)
    ((and (symbol? opnd) (not (lir-symbol-starts-with-percent? opnd))) #t)
    ((and (pair? opnd) (eq? (car opnd) '%stack) (pair? (cdr opnd))
          (integer? (cadr opnd))) #t)
    ((and (pair? opnd) (eq? (car opnd) '%mem) (pair? (cdr opnd)) (pair? (cddr opnd)))
     (and (lir-valid-register? (cadr opnd))
          (lir-valid-offset? (caddr opnd))))
    (else #f)))

(define (lir-atomic-operand? opnd)
  (or (integer? opnd)
      (and (symbol? opnd) (not (lir-symbol-starts-with-percent? opnd)))
      (lir-valid-register? opnd)
      (and (pair? opnd) (eq? (car opnd) '%stack) (pair? (cdr opnd)) (integer? (cadr opnd)))))

(define (lir-report-error msg expr)
  (verifier-error 'canonical-lir msg expr))

;;; -----------------------------------------------------------------------
;;; %inline-asm Verification Helpers (Issue #838, THREAT-838-1..3)
;;; -----------------------------------------------------------------------
(define (lir-inline-asm-digit? ch)
  (let ((c (char->integer ch)))
    (and (>= c 48) (<= c 57))))

(define (lir-verify-inline-asm-template template total-opnds declared-names inst)
  (let ((len (string-length template)))
    (let loop ((i 0))
      (if (>= i len)
          #t
          (let ((ch (string-ref template i)))
            (if (not (char=? ch #\%))
                (loop (+ i 1))
                (if (>= (+ i 1) len)
                    (lir-report-error "Trailing '%' in %inline-asm template" inst)
                    (let ((c1 (string-ref template (+ i 1))))
                      (cond
                        ((char=? c1 #\%)
                         (loop (+ i 2)))
                        ((char=? c1 #\[)
                         (let find-close ((j (+ i 2)))
                           (cond
                             ((>= j len)
                              (lir-report-error "Unclosed '%[' named operand in %inline-asm template" inst))
                             ((char=? (string-ref template j) #\])
                              (if (= j (+ i 2))
                                  (lir-report-error "Empty '%[]' named operand in %inline-asm template" inst)
                                  (let ((nm (string->symbol (substring template (+ i 2) j))))
                                    (if (memq nm declared-names)
                                        (loop (+ j 1))
                                        (lir-report-error "Undefined named operand %[...] in %inline-asm template (THREAT-838-3)" inst)))))
                             (else (find-close (+ j 1))))))
                        ((lir-inline-asm-digit? c1)
                         (let scan-num ((j (+ i 1)) (idx 0))
                           (if (and (< j len) (lir-inline-asm-digit? (string-ref template j)))
                               (scan-num (+ j 1) (+ (* idx 10) (- (char->integer (string-ref template j)) 48)))
                               (if (< idx total-opnds)
                                   (loop j)
                                   (lir-report-error "Out-of-bounds %N operand reference in %inline-asm template (THREAT-838-3)" inst)))))
                        ((and (< (+ i 2) len)
                              (memv c1 '(#\b #\w #\k #\q #\h #\l #\c #\n))
                              (lir-inline-asm-digit? (string-ref template (+ i 2))))
                         (let scan-mod ((j (+ i 2)) (idx 0))
                           (if (and (< j len) (lir-inline-asm-digit? (string-ref template j)))
                               (scan-mod (+ j 1) (+ (* idx 10) (- (char->integer (string-ref template j)) 48)))
                               (if (< idx total-opnds)
                                   (loop j)
                                   (lir-report-error "Out-of-bounds modified %N operand reference in %inline-asm template (THREAT-838-3)" inst)))))
                        (else
                         (loop (+ i 2))))))))))))

(define (lir-verify-inline-asm-clauses-syntax clauses inst)
  (let loop ((cs clauses) (seen-keys '()))
    (if (null? cs)
        #t
        (let ((c (car cs)))
          (cond
            ((not (pair? c))
             (lir-report-error "%inline-asm clause must be a pair" inst))
            ((not (memq (car c) '(:outputs :inputs :clobbers :volatile?)))
             (lir-report-error "Unknown %inline-asm clause keyword" c))
            ((memq (car c) seen-keys)
             (lir-report-error "Duplicate %inline-asm clause keyword" c))
            ((eq? (car c) ':volatile?)
             (if (and (= (length c) 2) (boolean? (cadr c)))
                 (loop (cdr cs) (cons (car c) seen-keys))
                 (lir-report-error "%inline-asm :volatile? clause must be (:volatile? <bool>)" c)))
            (else
             (if (and (= (length c) 2) (list? (cadr c)))
                 (loop (cdr cs) (cons (car c) seen-keys))
                 (lir-report-error "%inline-asm list clause must be (:key (<entry> ...))" c))))))))

(define (lir-verify-inline-asm-outputs outs inst)
  (let loop ((os outs) (seen-regs '()) (names '()))
    (if (null? os)
        (cons seen-regs names)
        (let ((no (inline-asm-normalize-out-entry (car os))))
          (if (not no)
              (lir-report-error "%inline-asm output spec must be (<dst> <constraint>) or (<name> <constraint> <dst>)" (car os))
              (let ((name (car no))
                    (dst (cadr no))
                    (cstr (caddr no)))
                (cond
                  ((not (or (lir-valid-register? dst)
                            (and (symbol? dst) (not (lir-symbol-starts-with-percent? dst)))
                            (and (pair? dst) (eq? (car dst) '%stack)
                                 (pair? (cdr dst)) (integer? (cadr dst)))
                            (and (pair? dst) (eq? (car dst) '%mem) (lir-valid-operand? dst))))
                   (lir-report-error "%inline-asm output destination must be writable location or virtual register" (car os)))
                  ((eq? (inline-asm-normalize-reg-sym dst) '%rsp)
                   (lir-report-error "%inline-asm cannot write directly to stack pointer %rsp (THREAT-838-1)" (car os)))
                  (else
                   (let ((oc (inline-asm-parse-output-constraint cstr)))
                     (cond
                       ((not oc)
                        (lir-report-error "Invalid %inline-asm output constraint (THREAT-838-3)" (car os)))
                       ((and (eq? (car oc) '=reg) (eq? (cadr oc) '%rsp))
                        (lir-report-error "%inline-asm cannot constrain output to reserved %rsp (THREAT-838-1)" (car os)))
                       ((and (eq? (car oc) '=reg) (memq (cadr oc) seen-regs))
                        (lir-report-error "Duplicate fixed physical register in %inline-asm :outputs (THREAT-838-3)" (car os)))
                       (else
                        (let ((new-regs (if (eq? (car oc) '=reg) (cons (cadr oc) seen-regs) seen-regs))
                              (new-names (if (symbol? name) (cons name names) names)))
                          (loop (cdr os) new-regs new-names)))))))))))))

(define (lir-verify-inline-asm-inputs ins num-outs init-names inst)
  (let loop ((is ins) (seen-regs '()) (names init-names))
    (if (null? is)
        names
        (let ((ni (inline-asm-normalize-in-entry (car is))))
          (if (not ni)
              (lir-report-error "%inline-asm input spec must be (<src> <constraint>) or (<name> <constraint> <src>)" (car is))
              (let ((name (car ni))
                    (src (cadr ni))
                    (cstr (caddr ni)))
                (if (not (lir-valid-operand? src))
                    (lir-report-error "Invalid %inline-asm input operand" (car is))
                    (let ((ic (inline-asm-parse-input-constraint cstr num-outs)))
                      (cond
                        ((not ic)
                         (lir-report-error "Invalid or out-of-range %inline-asm input constraint (THREAT-838-3)" (car is)))
                        ((and (eq? (car ic) 'imm) (not (integer? src)))
                         (lir-report-error "%inline-asm immediate constraint ('i'/'n') requires integer operand" (car is)))
                        ((and (eq? (car ic) 'reg) (eq? (cadr ic) '%rsp) (not (eq? src '%rsp)))
                         (lir-report-error "%inline-asm cannot bind non-%rsp value to %rsp (THREAT-838-1)" (car is)))
                        ((and (eq? (car ic) 'reg) (memq (cadr ic) seen-regs))
                         (lir-report-error "Duplicate fixed physical register in %inline-asm :inputs (THREAT-838-3)" (car is)))
                        (else
                         (let ((new-regs (if (eq? (car ic) 'reg) (cons (cadr ic) seen-regs) seen-regs))
                               (new-names (if (symbol? name) (cons name names) names)))
                           (loop (cdr is) new-regs new-names))))))))))))

(define (lir-verify-inline-asm-clobbers clobs inst)
  (let loop ((cs clobs))
    (if (null? cs)
        #t
        (let ((cp (inline-asm-parse-clobber (car cs))))
          (cond
            ((not cp)
             (lir-report-error "Invalid %inline-asm :clobbers entry (THREAT-838-3)" (car cs)))
            ((eq? cp '%rsp)
             (lir-report-error "%inline-asm cannot clobber stack pointer %rsp (THREAT-838-1)" (car cs)))
            (else
             (loop (cdr cs))))))))

(define (lir-verify-inline-asm inst)
  (cond
    ((not (and (pair? (cdr inst)) (string? (cadr inst))))
     (lir-report-error "%inline-asm requires a template string as first operand" inst))
    ((not (lir-verify-inline-asm-clauses-syntax (cddr inst) inst))
     #f)
    (else
     (let* ((parsed (inline-asm-extract-clauses inst))
            (template (car parsed))
            (outs (cadr parsed))
            (ins (caddr parsed))
            (clobs (cadddr parsed))
            (out-res (lir-verify-inline-asm-outputs outs inst)))
       (if (not out-res)
           #f
           (let ((all-names (lir-verify-inline-asm-inputs ins (length outs) (cdr out-res) inst)))
             (if (not all-names)
                 #f
                 (and (lir-verify-inline-asm-clobbers clobs inst)
                      (lir-verify-inline-asm-template
                       template (+ (length outs) (length ins)) all-names inst)))))))))

;;; -----------------------------------------------------------------------
;;; Instruction-Level Validation
;;; -----------------------------------------------------------------------
(define (lir-valid-inst? inst)
  (if (not (pair? inst))
      (lir-report-error "Instruction must be a non-empty pair" inst)
      (let ((op (car inst)))
        (case op
          ;; Control Flow
          ((%label)
           (if (and (= (length inst) 2) (symbol? (cadr inst)))
               #t
               (lir-report-error "%label must have exactly 1 symbol operand" inst)))

          ((%block)
           (if (and (>= (length inst) 3)
                    (symbol? (cadr inst))
                    (list? (caddr inst)))
               (let p-loop ((ps (caddr inst)))
                 (if (null? ps)
                     (let b-loop ((body (cdddr inst)))
                       (if (null? body)
                           #t
                           (and (lir-valid-inst? (car body))
                                (b-loop (cdr body)))))
                     (if (symbol? (car ps))
                         (p-loop (cdr ps))
                         (lir-report-error "%block parameter must be a symbol" (car ps)))))
               (lir-report-error "%block must be (%block <label-sym> (<param-syms>...) <insts>...)" inst)))

          ((%jump)
           (cond
             ((= (length inst) 2)
              (if (symbol? (cadr inst)) #t
                  (lir-report-error "%jump target must be a label symbol" inst)))
             ((= (length inst) 3)
              (if (and (symbol? (cadr inst)) (list? (caddr inst)))
                  (let a-loop ((as (caddr inst)))
                    (if (null? as) #t
                        (if (lir-atomic-operand? (car as))
                            (a-loop (cdr as))
                            (lir-report-error "%jump argument must be an atomic operand" (car as)))))
                  (lir-report-error "%jump format must be (%jump <lbl> (<args>...))" inst)))
             (else
              (lir-report-error "Invalid %jump arity" inst))))

          ((%jump-if-false)
           (cond
             ((= (length inst) 3)
              (if (and (lir-valid-register? (cadr inst)) (symbol? (caddr inst))) #t
                  (lir-report-error "%jump-if-false must have register and label symbol" inst)))
             ((= (length inst) 4)
              (if (and (lir-valid-register? (cadr inst))
                       (symbol? (caddr inst))
                       (list? (cadddr inst)))
                  (let a-loop ((as (cadddr inst)))
                    (if (null? as) #t
                        (if (lir-atomic-operand? (car as))
                            (a-loop (cdr as))
                            (lir-report-error "%jump-if-false argument must be atomic" (car as)))))
                  (lir-report-error "%jump-if-false format must be (%jump-if-false <reg> <lbl> (<args>...))" inst)))
             (else
              (lir-report-error "Invalid %jump-if-false arity" inst))))

          ((%jump-if)
           ;; Format: (%jump-if <reg> <then-lbl> (<then-args>...) <else-lbl> (<else-args>...))
           (if (and (= (length inst) 6)
                    (lir-valid-register? (cadr inst))
                    (symbol? (caddr inst))
                    (list? (cadddr inst))
                    (symbol? (car (cddddr inst)))
                    (list? (cadr (cddddr inst))))
               (and (let a-loop ((as (cadddr inst)))
                      (if (null? as) #t
                          (if (lir-atomic-operand? (car as))
                              (a-loop (cdr as))
                              (lir-report-error "%jump-if then-argument must be atomic" (car as)))))
                    (let b-loop ((as (cadr (cddddr inst))))
                      (if (null? as) #t
                          (if (lir-atomic-operand? (car as))
                              (b-loop (cdr as))
                              (lir-report-error "%jump-if else-argument must be atomic" (car as))))))
               (lir-report-error "%jump-if format must be (%jump-if <reg> <t_lbl> (<ta>...) <e_lbl> (<ea>...))" inst)))

          ((%jump-cond)
           (if (and (= (length inst) 3)
                    (or (symbol? (cadr inst)) (string? (cadr inst)))
                    (symbol? (caddr inst)))
               #t
               (lir-report-error "%jump-cond format must be (%jump-cond <cond-op> <lbl>)" inst)))

          ((%jump-if-zero)
           (if (and (= (length inst) 2) (symbol? (cadr inst)))
               #t
               (lir-report-error "%jump-if-zero format must be (%jump-if-zero <lbl>)" inst)))

          ((%direct-jump)
           (if (and (= (length inst) 2) (symbol? (cadr inst)))
               #t
               (lir-report-error "%direct-jump format must be (%direct-jump <lbl>)" inst)))

          ((%switch)
           ;; Format: (%switch <val> <def-lbl> (<def-args>...) ((<case-val> <case-lbl> (<case-args>...))...))
           ;; or:     (%switch <val> <def-lbl> ((<case-val> <case-lbl>)...))
           (cond
             ((= (length inst) 4)
              (if (and (lir-valid-operand? (cadr inst))
                       (symbol? (caddr inst))
                       (list? (cadddr inst)))
                  (let c-loop ((cs (cadddr inst)))
                    (if (null? cs) #t
                        (let ((c (car cs)))
                          (if (and (list? c) (= (length c) 2)
                                   (lir-valid-operand? (car c))
                                   (symbol? (cadr c)))
                              (c-loop (cdr cs))
                              (lir-report-error "Invalid switch case format in %switch" c)))))
                  (lir-report-error "Invalid 4-argument %switch format" inst)))
             ((= (length inst) 5)
              (if (and (lir-valid-operand? (cadr inst))
                       (symbol? (caddr inst))
                       (list? (cadddr inst))
                       (list? (car (cddddr inst))))
                  (and (let a-loop ((as (cadddr inst)))
                         (if (null? as) #t
                             (if (lir-atomic-operand? (car as))
                                 (a-loop (cdr as))
                                 (lir-report-error "%switch default argument must be atomic" (car as)))))
                       (let c-loop ((cs (car (cddddr inst))))
                         (if (null? cs) #t
                             (let ((c (car cs)))
                               (if (and (list? c) (= (length c) 3)
                                        (lir-valid-operand? (car c))
                                        (symbol? (cadr c))
                                        (list? (caddr c)))
                                   (let ca-loop ((cas (caddr c)))
                                     (if (null? cas)
                                         (c-loop (cdr cs))
                                         (if (lir-atomic-operand? (car cas))
                                             (ca-loop (cdr cas))
                                             (lir-report-error "%switch case argument must be atomic" (car cas)))))
                                   (lir-report-error "Invalid switch case with arguments format in %switch" c))))))
                  (lir-report-error "Invalid 5-argument %switch format" inst)))
             (else
              (lir-report-error "Invalid %switch arity" inst))))

          ((%return)
           (if (or (= (length inst) 1)
                   (and (= (length inst) 2) (lir-valid-operand? (cadr inst))))
               #t
               (lir-report-error "Invalid %return instruction format" inst)))

          ;; Calls & ABI
          ((%c-call %call-foreign)
           (if (or (and (= (length inst) 3)
                        (or (symbol? (cadr inst)) (string? (cadr inst)))
                        (integer? (caddr inst)))
                   (and (= (length inst) 4)
                        (or (symbol? (cadr inst)) (string? (cadr inst)))
                        (integer? (caddr inst))
                        (or (integer? (cadddr inst)) (not (cadddr inst)))))
               #t
               (lir-report-error "%c-call / %call-foreign format must be (%c-call <fn-name> <shift> [<al-val>])" inst)))

          ((%call-indirect)
           (if (or (and (= (length inst) 3)
                        (lir-valid-register? (cadr inst))
                        (integer? (caddr inst)))
                   (and (= (length inst) 4)
                        (lir-valid-register? (cadr inst))
                        (integer? (caddr inst))
                        (or (integer? (cadddr inst)) (not (cadddr inst)))))
               #t
               (lir-report-error "%call-indirect format must be (%call-indirect <reg> <shift> [<al-val>])" inst)))

          ((%call-closure)
           (if (or (and (= (length inst) 2) (integer? (cadr inst)))
                   (and (= (length inst) 3) (integer? (cadr inst))
                        (or (symbol? (caddr inst)) (string? (caddr inst)) (not (caddr inst)))))
               #t
               (lir-report-error "%call-closure format must be (%call-closure <shift> [<safepoint>])" inst)))

          ((%direct-call)
           (if (or (and (= (length inst) 3) (or (symbol? (cadr inst)) (string? (cadr inst))) (integer? (caddr inst)))
                   (and (= (length inst) 4) (or (symbol? (cadr inst)) (string? (cadr inst))) (integer? (caddr inst))
                        (or (symbol? (cadddr inst)) (string? (cadddr inst)) (not (cadddr inst)))))
               #t
               (lir-report-error "%direct-call format must be (%direct-call <lbl> <shift> [<safepoint>])" inst)))

          ((%dispatch-consumer)
           (if (and (= (length inst) 4)
                    (integer? (cadr inst))
                    (integer? (caddr inst))
                    (integer? (cadddr inst)))
               #t
               (lir-report-error "%dispatch-consumer format must be (%dispatch-consumer <c-si> <a-si> <shift>)" inst)))

          ;; Memory & Data Transfer
          ((%mov)
           (if (and (= (length inst) 3)
                    (lir-valid-lvalue? (cadr inst))
                    (lir-valid-operand? (caddr inst)))
               #t
               (lir-report-error "%mov format must be (%mov <dst> <src>)" inst)))

          ((%load)
           (if (and (= (length inst) 4)
                    (lir-valid-register? (cadr inst))
                    (lir-valid-register? (caddr inst))
                    (lir-valid-offset? (cadddr inst)))
               #t
               (lir-report-error "%load format must be (%load <dst-reg> <base-reg> <offset>)" inst)))

          ((%store)
           (if (and (= (length inst) 4)
                    (lir-valid-register? (cadr inst))
                    (lir-valid-offset? (caddr inst))
                    (lir-valid-operand? (cadddr inst)))
               #t
               (lir-report-error "%store format must be (%store <base-reg> <offset> <src>)" inst)))

          ((%load-byte-zx)
           (if (and (= (length inst) 4)
                    (lir-valid-register? (cadr inst))
                    (lir-valid-register? (caddr inst))
                    (lir-valid-offset? (cadddr inst)))
               #t
               (lir-report-error "%load-byte-zx format must be (%load-byte-zx <dst> <base> <offset>)" inst)))

          ((%store-byte)
           (if (and (= (length inst) 4)
                    (lir-valid-register? (cadr inst))
                    (lir-valid-offset? (caddr inst))
                    (or (lir-valid-register? (cadddr inst)) (integer? (cadddr inst))))
               #t
               (lir-report-error "%store-byte format must be (%store-byte <base> <offset> <src>)" inst)))

          ((%push)
           (if (and (= (length inst) 2) (lir-valid-register? (cadr inst)))
               #t
               (lir-report-error "%push format must be (%push <reg>)" inst)))

          ((%pop)
           (if (and (= (length inst) 2) (lir-valid-register? (cadr inst)))
               #t
               (lir-report-error "%pop format must be (%pop <reg>)" inst)))

          ((%code-ref)
           (if (and (= (length inst) 3)
                    (lir-valid-register? (cadr inst))
                    (or (symbol? (caddr inst)) (string? (caddr inst))))
               #t
               (lir-report-error "%code-ref format must be (%code-ref <dst> <lbl>)" inst)))

          ((%str-ref)
           (if (and (= (length inst) 3)
                    (lir-valid-register? (cadr inst))
                    (or (symbol? (caddr inst)) (string? (caddr inst))))
               #t
               (lir-report-error "%str-ref format must be (%str-ref <dst> <lbl>)" inst)))

          ((%global-ref)
           (if (and (= (length inst) 3)
                    (lir-valid-register? (cadr inst))
                    (symbol? (caddr inst)))
               #t
               (lir-report-error "%global-ref format must be (%global-ref <reg> <var-sym>)" inst)))

          ((%global-addr)
           (if (and (= (length inst) 3)
                    (lir-valid-register? (cadr inst))
                    (symbol? (caddr inst)))
               #t
               (lir-report-error "%global-addr format must be (%global-addr <reg> <var-sym>)" inst)))

          ((%global-set!)
           (if (and (= (length inst) 3)
                    (symbol? (cadr inst))
                    (lir-valid-register? (caddr inst)))
               #t
               (lir-report-error "%global-set! format must be (%global-set! <var-sym> <reg>)" inst)))

          ;; Arithmetic / Logic / Primitives
          ((%add %raw-add %sub %raw-sub %imul %raw-mul %bit-and %bit-or %bit-xor %cmp %raw-cmp)
           (if (and (= (length inst) 3)
                    (lir-valid-operand? (cadr inst))
                    (lir-valid-operand? (caddr inst)))
               #t
               (lir-report-error (string-append (symbol->string op) " must have exactly 2 valid operands") inst)))

          ((%neg %inc)
           (if (and (= (length inst) 2) (lir-valid-operand? (cadr inst)))
               #t
               (lir-report-error (string-append (symbol->string op) " must have 1 operand") inst)))

          ((%shl %sar)
           (if (and (= (length inst) 3)
                    (lir-valid-operand? (cadr inst))
                    (not (lir-float-register? (cadr inst)))
                    (or (integer? (caddr inst)) (eq? (caddr inst) '%rcx)))
               #t
               (lir-report-error (string-append (symbol->string op) " shift count must be an integer or %rcx") inst)))

          ((%shr)
           (cond
             ((and (= (length inst) 3)
                   (lir-valid-operand? (cadr inst))
                   (not (lir-float-register? (cadr inst)))
                   (or (integer? (caddr inst)) (eq? (caddr inst) '%rcx)))
              #t)
             ((and (= (length inst) 4)
                   (lir-valid-register? (cadr inst))
                   (not (lir-float-register? (cadr inst)))
                   (lir-valid-operand? (caddr inst))
                   (not (lir-float-register? (caddr inst)))
                   (or (integer? (cadddr inst)) (eq? (cadddr inst) '%rcx)))
              #t)
             ((or (lir-float-register? (cadr inst))
                  (and (= (length inst) 4) (lir-float-register? (caddr inst))))
              (lir-report-error "%shr operands cannot be float registers (CWE-843 defense)" inst))
             (else
              (lir-report-error "%shr format must be (%shr <opnd> <count>) or (%shr <dst-reg> <src-opnd> <count>)" inst))))

          ((%cqo %raise %memory-fence %safepoint-poll)
           (if (= (length inst) 1)
               #t
               (lir-report-error (string-append (symbol->string op) " takes zero operands") inst)))

          ((%syscall)
           (if (or (= (length inst) 1)
                   (and (= (length inst) 2) (integer? (cadr inst))))
               #t
               (lir-report-error "%syscall format must be (%syscall) or (%syscall <si>)" inst)))

          ((%atomic-cas!)
           (if (and (= (length inst) 4)
                    (lir-valid-register? (cadr inst))
                    (lir-valid-register? (caddr inst))
                    (lir-valid-register? (cadddr inst)))
               #t
               (lir-report-error "%atomic-cas! format must be (%atomic-cas! <dst-reg> <box-reg> <new-reg>)" inst)))

          ((%inline-asm)
           (lir-verify-inline-asm inst))

          ((%idiv)
           (if (and (= (length inst) 2) (lir-valid-operand? (cadr inst)))
               #t
               (lir-report-error "%idiv takes 1 operand" inst)))

          ((%udiv %urem)
           (cond
             ((and (= (length inst) 2)
                   (lir-valid-operand? (cadr inst))
                   (not (lir-float-register? (cadr inst))))
              #t)
             ((and (= (length inst) 4)
                   (lir-valid-register? (cadr inst))
                   (not (lir-float-register? (cadr inst)))
                   (lir-valid-operand? (caddr inst))
                   (not (lir-float-register? (caddr inst)))
                   (lir-valid-operand? (cadddr inst))
                   (not (lir-float-register? (cadddr inst))))
              #t)
             ((or (and (>= (length inst) 2) (lir-float-register? (cadr inst)))
                  (and (>= (length inst) 3) (lir-float-register? (caddr inst)))
                  (and (>= (length inst) 4) (lir-float-register? (cadddr inst))))
              (lir-report-error (string-append (symbol->string op) " operands must be integer operands (CWE-843 defense)") inst))
             (else
              (lir-report-error (string-append (symbol->string op) " format must be (op <src>) or (op <dst> <src1> <src2>)") inst))))

          ((%add-overflow %sub-overflow %mul-overflow)
           (if (not (= (length inst) 5))
               (lir-report-error (string-append (symbol->string op) " format must be (op <dst-val> <dst-flag> <src1> <src2>)") inst)
               (let ((dst-val (cadr inst))
                     (dst-flag (caddr inst))
                     (src1 (cadddr inst))
                     (src2 (car (cddddr inst))))
                 (cond
                   ((or (lir-float-register? dst-val) (lir-float-register? dst-flag)
                        (lir-float-register? src1) (lir-float-register? src2))
                    (lir-report-error (string-append (symbol->string op) " operands must be general-purpose integer registers/operands (CWE-843 defense)") inst))
                   ((not (lir-valid-register? dst-val))
                    (lir-report-error (string-append (symbol->string op) " dst-val must be a valid general-purpose register") inst))
                   ((not (lir-valid-register? dst-flag))
                    (lir-report-error (string-append (symbol->string op) " dst-flag must be a valid general-purpose register") inst))
                   ((equal? dst-val dst-flag)
                    (lir-report-error (string-append (symbol->string op) " dst-val and dst-flag registers must be distinct (non-destructive flag output)") inst))
                   ((not (lir-valid-operand? src1))
                    (lir-report-error (string-append (symbol->string op) " src1 must be a valid operand") inst))
                   ((not (lir-valid-operand? src2))
                    (lir-report-error (string-append (symbol->string op) " src2 must be a valid operand") inst))
                   (else #t)))))

          ((%setb %setbe %seta %setae)
           (cond
             ((and (= (length inst) 2)
                   (lir-valid-register? (cadr inst))
                   (not (lir-float-register? (cadr inst))))
              #t)
             ((and (= (length inst) 4)
                   (lir-valid-register? (cadr inst))
                   (not (lir-float-register? (cadr inst)))
                   (lir-valid-operand? (caddr inst))
                   (not (lir-float-register? (caddr inst)))
                   (lir-valid-operand? (cadddr inst))
                   (not (lir-float-register? (cadddr inst))))
              #t)
             ((or (and (>= (length inst) 2) (lir-float-register? (cadr inst)))
                  (and (>= (length inst) 3) (lir-float-register? (caddr inst)))
                  (and (>= (length inst) 4) (lir-float-register? (cadddr inst))))
              (lir-report-error (string-append (symbol->string op) " operands must be general-purpose registers/operands (CWE-843 defense)") inst))
             (else
              (lir-report-error (string-append (symbol->string op) " format must be (op <dst-reg>) or (op <dst-reg> <src1> <src2>)") inst))))

          ((%set-boolean)
           (if (and (= (length inst) 3)
                    (lir-valid-operand? (cadr inst))
                    (or (symbol? (caddr inst)) (string? (caddr inst))))
               #t
               (lir-report-error "%set-boolean format must be (%set-boolean <dst> <cc>)" inst)))

          ((%box-fixnum %unbox-fixnum)
           (if (and (= (length inst) 3)
                    (lir-valid-operand? (cadr inst))
                    (lir-valid-operand? (caddr inst)))
               #t
               (lir-report-error (string-append (symbol->string op) " format must be (op <dst> <src>)") inst)))

          ;; Typed Machine LIR: Memory & Conversions (Issue #826)
          ((%load-typed)
           (if (and (= (length inst) 5)
                    (lir-machine-type? (cadr inst))
                    (lir-valid-register? (caddr inst))
                    (lir-valid-register? (cadddr inst))
                    (lir-valid-offset? (car (cddddr inst))))
               (if (and (memq (cadr inst) '(f32 f64))
                        (not (lir-float-register? (caddr inst))))
                   (lir-report-error "%load-typed float type requires float destination register" inst)
                   #t)
               (lir-report-error "%load-typed format must be (%load-typed <mty> <dst-reg> <base-reg> <offset>)" inst)))

          ((%store-typed)
           (if (and (= (length inst) 5)
                    (lir-machine-type? (cadr inst))
                    (lir-valid-register? (caddr inst))
                    (lir-valid-offset? (cadddr inst))
                    (lir-valid-operand? (car (cddddr inst))))
               (if (and (memq (cadr inst) '(f32 f64))
                        (not (lir-float-operand? (car (cddddr inst)))))
                   (lir-report-error "%store-typed float type requires float source operand" inst)
                   #t)
               (lir-report-error "%store-typed format must be (%store-typed <mty> <base-reg> <offset> <src-opnd>)" inst)))

          ((%fmov)
           (if (and (= (length inst) 3)
                    (lir-float-register? (cadr inst))
                    (lir-float-operand? (caddr inst)))
               #t
               (lir-report-error "%fmov format must be (%fmov <dst-freg> <src-fopnd>)" inst)))

          ((%fadd %fsub %fmul %fdiv %fcmp)
           (if (and (= (length inst) 3)
                    (lir-float-register? (cadr inst))
                    (lir-float-operand? (caddr inst)))
               #t
               (lir-report-error (string-append (symbol->string op) " operands must be floating-point registers/operands (CWE-843 defense)") inst)))

          ((%box-flonum %unbox-flonum)
           (if (and (= (length inst) 3)
                    (lir-valid-operand? (cadr inst))
                    (lir-valid-operand? (caddr inst)))
               #t
               (lir-report-error (string-append (symbol->string op) " format must be (op <dst> <src>)") inst)))

          ((%fneg)
           (if (and (= (length inst) 4)
                    (memq (cadr inst) '(f32 f64))
                    (lir-float-register? (caddr inst))
                    (lir-float-operand? (cadddr inst)))
               #t
               (lir-report-error "%fneg format must be (%fneg <f32|f64> <dst-freg> <src-fopnd>)" inst)))

          ((%fpext)
           (if (and (= (length inst) 4)
                    (eq? (cadr inst) 'f64)
                    (lir-float-register? (caddr inst))
                    (lir-float-operand? (cadddr inst)))
               #t
               (lir-report-error "%fpext format must be (%fpext f64 <dst-freg> <src-fopnd>)" inst)))

          ((%fptrunc)
           (if (and (= (length inst) 4)
                    (eq? (cadr inst) 'f32)
                    (lir-float-register? (caddr inst))
                    (lir-float-operand? (cadddr inst)))
               #t
               (lir-report-error "%fptrunc format must be (%fptrunc f32 <dst-freg> <src-fopnd>)" inst)))

          ((%sitofp)
           (if (and (= (length inst) 3)
                    (lir-float-register? (cadr inst))
                    (lir-valid-operand? (caddr inst)))
               #t
               (lir-report-error "%sitofp format must be (%sitofp <dst-freg> <src-gpr>)" inst)))

          ((%uitofp)
           (if (and (= (length inst) 3)
                    (lir-float-register? (cadr inst))
                    (lir-valid-operand? (caddr inst))
                    (not (lir-float-register? (caddr inst))))
               #t
               (lir-report-error "%uitofp format must be (%uitofp <dst-freg> <src-gpr>)" inst)))

          ((%fptosi)
           (if (and (= (length inst) 3)
                    (lir-valid-register? (cadr inst))
                    (not (lir-float-register? (cadr inst)))
                    (lir-float-operand? (caddr inst)))
               #t
               (lir-report-error "%fptosi format must be (%fptosi <dst-gpr> <src-freg>)" inst)))

          ((%fptoui)
           (if (and (= (length inst) 3)
                    (lir-valid-register? (cadr inst))
                    (not (lir-float-register? (cadr inst)))
                    (lir-float-operand? (caddr inst)))
               #t
               (lir-report-error "%fptoui format must be (%fptoui <dst-gpr> <src-freg>)" inst)))

          ((%fcmp-oeq %fcmp-une %fcmp-olt %fcmp-ole %fcmp-ogt %fcmp-oge)
           (if (and (= (length inst) 4)
                    (lir-valid-register? (cadr inst))
                    (not (lir-float-register? (cadr inst)))
                    (lir-float-register? (caddr inst))
                    (lir-float-operand? (cadddr inst)))
               #t
               (lir-report-error (string-append (symbol->string op) " format must be (op <dst-gpr> <lhs-freg> <rhs-fopnd>)") inst)))

          ((%trunc %zext %sext)
           (if (and (= (length inst) 4)
                    (lir-machine-type? (cadr inst))
                    (lir-valid-register? (caddr inst))
                    (lir-valid-operand? (cadddr inst)))
               #t
               (lir-report-error (string-append (symbol->string op) " format must be (op <mty> <dst> <src>)") inst)))

          ;; Runtime / GC / CC / Values
          ((%alloc)
           (if (and (or (= (length inst) 4) (= (length inst) 5))
                    (lir-valid-operand? (cadr inst))
                    (integer? (caddr inst))
                    (integer? (cadddr inst)))
               #t
               (lir-report-error "%alloc format must be (%alloc <dst> <bytes> <tag> [<si>])" inst)))

          ((%alloc-stack)
           (if (and (= (length inst) 4)
                    (lir-valid-operand? (cadr inst))
                    (integer? (caddr inst))
                    (integer? (cadddr inst)))
               #t
               (lir-report-error "%alloc-stack format must be (%alloc-stack <dst> <offset> <tag>)" inst)))

          ((%capture-cc)
           (if (and (= (length inst) 3)
                    (symbol? (cadr inst))
                    (integer? (caddr inst)))
               #t
               (lir-report-error "%capture-cc format must be (%capture-cc <ret-lbl> <k-si>)" inst)))

          ((%push-handler)
           (if (and (= (length inst) 4)
                    (symbol? (cadr inst))
                    (integer? (caddr inst))
                    (integer? (cadddr inst)))
               #t
               (lir-report-error "%push-handler format must be (%push-handler <catch-lbl> <f-si> <h-si>)" inst)))

          ((%pop-handler)
           (if (and (= (length inst) 2) (integer? (cadr inst)))
               #t
               (lir-report-error "%pop-handler format must be (%pop-handler <f-si>)" inst)))

          ((%set-values-count)
           (if (and (= (length inst) 2) (integer? (cadr inst)))
               #t
               (lir-report-error "%set-values-count takes 1 integer operand" inst)))

          ((%store-values-buf)
           (if (and (= (length inst) 3) (integer? (cadr inst)) (integer? (caddr inst)))
               #t
               (lir-report-error "%store-values-buf takes base-si and count integers" inst)))

          (else
           (lir-report-error (string-append "Unknown Canonical LIR opcode: "
                                            (if (symbol? op) (symbol->string op) "?"))
                             inst))))))

;;; -----------------------------------------------------------------------
;;; Lightweight Symbol Hash Set & Hash Table for O(1) Fast CFG Verification
;;; -----------------------------------------------------------------------
;;; NOTE (self-hosting constraints): this file is compiled by the ulisp
;;; compiler itself during bootstrap, so it must avoid variadic parameter
;;; lists, internal defines, `max`, and the 2-argument form of `make-vector`.
(define (lir-max2 a b) (if (> a b) a b))

(define (lir-symbol-hash-str str)
  (let ((len (string-length str)))
    (let loop ((i 0) (h 5381))
      (if (= i len)
          (modulo h 16777213)
          (let ((c (char->integer (string-ref str i))))
            (loop (+ i 1)
                  (modulo (+ (* h 33) c) 16777213)))))))

(define (lir-make-bucket-vector size)
  (let* ((n (lir-max2 16 size))
         (v (make-vector n)))
    (let loop ((i 0))
      (if (= i n)
          v
          (begin
            (vector-set! v i '())
            (loop (+ i 1)))))))

(define (make-symbol-hash-set size)
  (lir-make-bucket-vector size))

(define (symbol-hash-bucket-index sym size)
  (let ((str (if (symbol? sym) (symbol->string sym) "")))
    (modulo (lir-symbol-hash-str str) size)))

(define (symbol-hash-set-add! set sym)
  (let* ((idx (symbol-hash-bucket-index sym (vector-length set)))
         (bucket (vector-ref set idx)))
    (if (memq sym bucket)
        #f
        (begin
          (vector-set! set idx (cons sym bucket))
          #t))))

(define (symbol-hash-set-contains? set sym)
  (let* ((idx (symbol-hash-bucket-index sym (vector-length set)))
         (bucket (vector-ref set idx)))
    (if (memq sym bucket) #t #f)))

(define (make-symbol-hash-table size)
  (lir-make-bucket-vector size))

(define (symbol-hash-table-put! tbl sym val)
  (let* ((idx (symbol-hash-bucket-index sym (vector-length tbl)))
         (bucket (vector-ref tbl idx))
         (entry (assq sym bucket)))
    (if entry
        (set-cdr! entry val)
        (vector-set! tbl idx (cons (cons sym val) bucket)))))

(define (symbol-hash-table-ref tbl sym default)
  (let* ((idx (symbol-hash-bucket-index sym (vector-length tbl)))
         (bucket (vector-ref tbl idx))
         (entry (assq sym bucket)))
    (if entry (cdr entry) default)))

;;; -----------------------------------------------------------------------
;;; Single-Pass Instruction Verification and CFG Target Resolution (O(N))
;;; -----------------------------------------------------------------------
;;; state = (label-set block-arity-tbl pending-jumps-cell fn-name)

(define (lir-sp-push-jump! pending entry)
  (set-car! pending (cons entry (car pending))))

(define (lir-sp-queue-jump! inst pending)
  (case (car inst)
    ((%jump)
     (let ((args (if (pair? (cddr inst)) (caddr inst) '())))
       (lir-sp-push-jump! pending (list '%jump (cadr inst) (length args) inst))))
    ((%jump-if-false)
     (let ((args (if (pair? (cdddr inst)) (cadddr inst) '())))
       (lir-sp-push-jump! pending (list '%jump-if-false (caddr inst)
                                        (if (pair? args) (length args) #f) inst))))
    ((%jump-if)
     (let ((then-args (cadddr inst))
           (else-args (cadr (cddddr inst))))
       (lir-sp-push-jump! pending (list '%jump-if (caddr inst)
                                        (if (pair? then-args) (length then-args) #f)
                                        inst
                                        (car (cddddr inst))
                                        (if (pair? else-args) (length else-args) #f)))))
    ((%jump-cond)
     (lir-sp-push-jump! pending (list '%jump-cond (caddr inst) #f inst)))
    ((%jump-if-zero)
     (lir-sp-push-jump! pending (list '%jump-if-zero (cadr inst) #f inst)))
    ((%direct-jump)
     (lir-sp-push-jump! pending (list '%direct-jump (cadr inst) #f inst)))
    ((%switch)
     (let* ((def-lbl (caddr inst))
            (def-args (if (and (= (length inst) 5) (list? (cadddr inst))) (cadddr inst) '()))
            (cases (if (= (length inst) 5) (car (cddddr inst)) (cadddr inst))))
       (lir-sp-push-jump! pending (list '%jump def-lbl (if (list? def-args) (length def-args) #f) inst))
       (for-each
        (lambda (c)
          (let ((c-lbl (cadr c))
                (c-args (if (and (= (length c) 3) (list? (caddr c))) (caddr c) '())))
            (lir-sp-push-jump! pending (list '%jump c-lbl (if (list? c-args) (length c-args) #f) inst))))
        cases)))
    (else #t)))

(define (lir-sp-check-block-params params)
  (if (null? params)
      #t
      (if (symbol? (car params))
          (lir-sp-check-block-params (cdr params))
          (lir-report-error "%block parameter must be a symbol" (car params)))))

;; Step 1: single traversal validating syntax, collecting labels & arities,
;; and queuing jump targets for post-pass resolution.
(define (lir-sp-scan insts label-set arity-tbl pending fn-name)
  (if (null? insts)
      #t
      (let ((inst (car insts)))
        (cond
          ((not (pair? inst))
           (lir-report-error "Instruction must be a non-empty pair" inst))
          ((eq? (car inst) '%label)
           (cond
             ((not (and (= (length inst) 2) (symbol? (cadr inst))))
              (lir-report-error "%label must have exactly 1 symbol operand" inst))
             ((not (symbol-hash-set-add! label-set (cadr inst)))
              (lir-report-error "Duplicate label definition within function" (cadr inst)))
             (else
              (lir-sp-scan (cdr insts) label-set arity-tbl pending fn-name))))
          ((eq? (car inst) '%block)
           (cond
             ((not (and (>= (length inst) 3) (symbol? (cadr inst)) (list? (caddr inst))))
              (lir-report-error "%block must be (%block <label-sym> (<param-syms>...) <insts>...)" inst))
             ((not (symbol-hash-set-add! label-set (cadr inst)))
              (lir-report-error "Duplicate block label definition within function" (cadr inst)))
             ((not (lir-sp-check-block-params (caddr inst))) #f)
             (else
              (let ((lbl (cadr inst)))
                (symbol-hash-table-put! arity-tbl lbl (length (caddr inst)))
                (and (with-verifier-context
                      (list (cons 'phase 'canonical-lir) (cons 'function fn-name) (cons 'block lbl))
                      (lambda () (lir-sp-scan (cdddr inst) label-set arity-tbl pending fn-name)))
                     (lir-sp-scan (cdr insts) label-set arity-tbl pending fn-name))))))
          ((not (lir-valid-inst? inst)) #f)
          (else
           (lir-sp-queue-jump! inst pending)
           (lir-sp-scan (cdr insts) label-set arity-tbl pending fn-name))))))

(define (lir-sp-target-known? target label-set known-fn-set)
  (or (symbol-hash-set-contains? label-set target)
      (symbol-hash-set-contains? known-fn-set target)))

(define (lir-sp-arity-mismatch? target argc arity-tbl)
  (and argc
       (let ((expected (symbol-hash-table-ref arity-tbl target #f)))
         (and expected (not (= argc expected))))))

;; Step 2: post-pass target resolution in O(1) per jump.
(define (lir-sp-resolve jumps label-set known-fn-set arity-tbl)
  (if (null? jumps)
      #t
      (let* ((j (car jumps))
             (kind (car j))
             (target (cadr j))
             (argc (caddr j))
             (inst (cadddr j)))
        (cond
          ((not (lir-sp-target-known? target label-set known-fn-set))
           (cond
             ((eq? kind '%jump)
              (lir-report-error "Undefined jump target label" target))
             ((eq? kind '%jump-if-false)
              (lir-report-error "Undefined jump target in %jump-if-false" target))
             ((eq? kind '%jump-if)
              (lir-report-error "Undefined then-target in %jump-if" target))
             (else
              (lir-report-error "Undefined jump condition target" target))))
          ((lir-sp-arity-mismatch? target argc arity-tbl)
           (cond
             ((eq? kind '%jump-if-false)
              (lir-report-error "%jump-if-false argument count mismatch with %block" inst))
             ((eq? kind '%jump-if)
              (lir-report-error "%jump-if then-argument count mismatch with %block" inst))
             (else
              (lir-report-error "Jump argument count does not match %block parameter count" inst))))
          ((eq? kind '%jump-if)
           (let ((else-target (car (cddddr j)))
                 (else-argc (cadr (cddddr j))))
             (cond
               ((not (lir-sp-target-known? else-target label-set known-fn-set))
                (lir-report-error "Undefined else-target in %jump-if" else-target))
               ((lir-sp-arity-mismatch? else-target else-argc arity-tbl)
                (lir-report-error "%jump-if else-argument count mismatch with %block" inst))
               (else
                (lir-sp-resolve (cdr jumps) label-set known-fn-set arity-tbl)))))
          (else
           (lir-sp-resolve (cdr jumps) label-set known-fn-set arity-tbl))))))

(define (lir-verify-insts-single-pass insts known-fn-set fn-name)
  (let ((label-set (make-symbol-hash-set 128))
        (arity-tbl (make-symbol-hash-table 128))
        (pending (cons '() '())))
    (and (lir-sp-scan insts label-set arity-tbl pending fn-name)
         (lir-sp-resolve (reverse (car pending)) label-set known-fn-set arity-tbl))))

;;; Backward-compatibility wrappers for tests and legacy callers
(define (lir-collect-labels-and-params insts)
  (let loop ((is insts) (labels '()) (block-params '()))
    (if (null? is)
        (cons labels block-params)
        (let ((inst (car is)))
          (cond
            ((and (pair? inst) (eq? (car inst) '%label))
             (let ((lbl (cadr inst)))
               (if (memq lbl labels)
                   (begin
                     (lir-report-error "Duplicate label definition within function" lbl)
                     #f)
                   (loop (cdr is) (cons lbl labels) block-params))))
            ((and (pair? inst) (eq? (car inst) '%block))
             (let ((lbl (cadr inst))
                   (params (caddr inst))
                   (sub-insts (cdddr inst)))
               (if (memq lbl labels)
                   (begin
                     (lir-report-error "Duplicate block label definition within function" lbl)
                     #f)
                   (let ((sub-res (lir-collect-labels-and-params sub-insts)))
                     (if (not sub-res)
                         #f
                         (loop (cdr is)
                               (cons lbl (append (car sub-res) labels))
                               (cons (cons lbl (length params))
                                     (append (cdr sub-res) block-params))))))))
            (else
             (loop (cdr is) labels block-params)))))))

(define (lir-verify-cfg-targets insts defined-labels block-params known-fn-labels)
  (let ((label-set (make-symbol-hash-set (lir-max2 16 (* 2 (length defined-labels)))))
        (known-set (make-symbol-hash-set (lir-max2 16 (* 2 (length known-fn-labels)))))
        (arity-tbl (make-symbol-hash-table (lir-max2 16 (* 2 (length block-params))))))
    (for-each (lambda (l) (symbol-hash-set-add! label-set l)) defined-labels)
    (for-each (lambda (k) (symbol-hash-set-add! known-set k)) known-fn-labels)
    (for-each (lambda (bp) (symbol-hash-table-put! arity-tbl (car bp) (cdr bp))) block-params)
    (let loop ((is insts))
      (if (null? is) #t
          (let ((inst (car is)))
            (cond
              ((not (pair? inst)) (loop (cdr is)))
              ((eq? (car inst) '%block)
               (and (loop (cdddr inst))
                    (loop (cdr is))))
              ((eq? (car inst) '%jump)
               (let* ((target (cadr inst))
                      (args (if (pair? (cddr inst)) (caddr inst) '()))
                      (expected-arity (symbol-hash-table-ref arity-tbl target #f)))
                 (cond
                   ((and (not (symbol-hash-set-contains? label-set target))
                         (not (symbol-hash-set-contains? known-set target)))
                    (lir-report-error "Undefined jump target label" target))
                   ((and expected-arity (not (= (length args) expected-arity)))
                    (lir-report-error "Jump argument count does not match %block parameter count" inst))
                   (else
                    (loop (cdr is))))))
              ((eq? (car inst) '%jump-if-false)
               (let* ((target (caddr inst))
                      (args (if (pair? (cdddr inst)) (cadddr inst) '()))
                      (expected-arity (symbol-hash-table-ref arity-tbl target #f)))
                 (cond
                   ((and (not (symbol-hash-set-contains? label-set target))
                         (not (symbol-hash-set-contains? known-set target)))
                    (lir-report-error "Undefined jump target in %jump-if-false" target))
                   ((and expected-arity (pair? args) (not (= (length args) expected-arity)))
                    (lir-report-error "%jump-if-false argument count mismatch with %block" inst))
                   (else
                    (loop (cdr is))))))
              ((eq? (car inst) '%jump-if)
               (let* ((then-target (caddr inst))
                      (then-args (cadddr inst))
                      (else-target (car (cddddr inst)))
                      (else-args (cadr (cddddr inst)))
                      (then-expected (symbol-hash-table-ref arity-tbl then-target #f))
                      (else-expected (symbol-hash-table-ref arity-tbl else-target #f)))
                 (cond
                   ((and (not (symbol-hash-set-contains? label-set then-target))
                         (not (symbol-hash-set-contains? known-set then-target)))
                    (lir-report-error "Undefined then-target in %jump-if" then-target))
                   ((and (not (symbol-hash-set-contains? label-set else-target))
                         (not (symbol-hash-set-contains? known-set else-target)))
                    (lir-report-error "Undefined else-target in %jump-if" else-target))
                   ((and then-expected (pair? then-args) (not (= (length then-args) then-expected)))
                    (lir-report-error "%jump-if then-argument count mismatch with %block" inst))
                   ((and else-expected (pair? else-args) (not (= (length else-args) else-expected)))
                    (lir-report-error "%jump-if else-argument count mismatch with %block" inst))
                   (else
                    (loop (cdr is))))))
              ((or (eq? (car inst) '%jump-cond)
                   (eq? (car inst) '%jump-if-zero)
                   (eq? (car inst) '%direct-jump))
               (let ((target (if (eq? (car inst) '%jump-cond) (caddr inst) (cadr inst))))
                 (if (and (not (symbol-hash-set-contains? label-set target))
                          (not (symbol-hash-set-contains? known-set target)))
                     (lir-report-error "Undefined jump condition target" target)
                     (loop (cdr is)))))
              ((eq? (car inst) '%switch)
               (let* ((def-lbl (caddr inst))
                      (def-args (if (and (= (length inst) 5) (list? (cadddr inst))) (cadddr inst) '()))
                      (cases (if (= (length inst) 5) (car (cddddr inst)) (cadddr inst)))
                      (def-expected (symbol-hash-table-ref arity-tbl def-lbl #f)))
                 (cond
                   ((and (not (symbol-hash-set-contains? label-set def-lbl))
                         (not (symbol-hash-set-contains? known-set def-lbl)))
                    (lir-report-error "Undefined switch default target" def-lbl))
                   ((and def-expected (pair? def-args) (not (= (length def-args) def-expected)))
                    (lir-report-error "%switch default argument count mismatch with %block" inst))
                   (else
                    (for-each
                     (lambda (c)
                       (let* ((c-lbl (cadr c))
                              (c-args (if (and (= (length c) 3) (list? (caddr c))) (caddr c) '()))
                              (c-expected (symbol-hash-table-ref arity-tbl c-lbl #f)))
                         (cond
                           ((and (not (symbol-hash-set-contains? label-set c-lbl))
                                 (not (symbol-hash-set-contains? known-set c-lbl)))
                            (lir-report-error "Undefined switch case target" c-lbl))
                           ((and c-expected (pair? c-args) (not (= (length c-args) c-expected)))
                            (lir-report-error "%switch case argument count mismatch with %block" inst)))))
                     cases)
                    (loop (cdr is))))))
              (else
               (loop (cdr is)))))))))

(define (lir-verify-insts-and-cfg insts known-fn-labels)
  (let ((known-set (make-symbol-hash-set (lir-max2 16 (* 2 (length known-fn-labels))))))
    (for-each (lambda (k) (symbol-hash-set-add! known-set k)) known-fn-labels)
    (lir-verify-insts-single-pass insts known-set '%unnamed-fn)))

;;; -----------------------------------------------------------------------
;;; Function-Level and Program-Level Validation
;;; -----------------------------------------------------------------------
(define (lir-valid-function? fn known-fn-set)
  (cond
    ((not (and (pair? fn) (eq? (car fn) '%lir-function)))
     (lir-report-error "Function node must start with %lir-function" fn))
    ((not (symbol? (cadr fn)))
     (lir-report-error "%lir-function name must be a symbol" fn))
    (else
     (let ((fn-name (cadr fn))
           (params-clause (assq 'params (cddr fn)))
           (frame-clause (assq 'frame-size (cddr fn)))
           (body-clause (assq 'body (cddr fn))))
       (with-verifier-context (list (cons 'phase 'canonical-lir) (cons 'function fn-name))
         (lambda ()
           (cond
             ((not (and params-clause (list? (cadr params-clause))))
              (lir-report-error "%lir-function must have valid (params (...)) clause" fn))
             ((not (and frame-clause (integer? (cadr frame-clause))
                        (>= (cadr frame-clause) 0)
                        (= (modulo (cadr frame-clause) 8) 0)))
              (lir-report-error "%lir-function frame-size must be a non-negative multiple of 8" fn))
             ((not (and body-clause (list? (cdr body-clause))))
              (lir-report-error "%lir-function must have valid (body <insts>...) clause" fn))
             (else
              (lir-verify-insts-single-pass (cdr body-clause) known-fn-set fn-name)))))))))

(define (lir-valid-main? main-clause known-fn-set)
  (cond
    ((not (and (pair? main-clause) (eq? (car main-clause) '%lir-main)))
     (lir-report-error "%lir-main node must start with %lir-main" main-clause))
    (else
     (let ((frame-clause (assq 'frame-size (cdr main-clause)))
           (body-clause (assq 'body (cdr main-clause))))
       (with-verifier-context (list (cons 'phase 'canonical-lir) (cons 'function '%lir-main))
         (lambda ()
           (cond
             ((not (and frame-clause (integer? (cadr frame-clause))
                        (>= (cadr frame-clause) 0)
                        (= (modulo (cadr frame-clause) 8) 0)))
              (lir-report-error "%lir-main frame-size must be a non-negative multiple of 8" main-clause))
             ((not (and body-clause (list? (cdr body-clause))))
              (lir-report-error "%lir-main must have valid (body <insts>...) clause" main-clause))
             (else
              (lir-verify-insts-single-pass (cdr body-clause) known-fn-set '%lir-main)))))))))

;;; -----------------------------------------------------------------------
;;; Public API: validate-lir / verify-lir / validate-core-lir / verify-core-lir
;;; Conforms to DSN-33, DSN-38 & Issue #835 (Core Machine LIR vs Managed Dialect)
;;; -----------------------------------------------------------------------

(define (lir-check-no-managed-insts insts fn-name)
  (let loop ((is insts))
    (if (null? is)
        #t
        (let ((inst (car is)))
          (cond
            ((not (pair? inst))
             (loop (cdr is)))
            ((eq? (car inst) '%block)
             (and (lir-check-no-managed-insts (cdddr inst) fn-name)
                  (loop (cdr is))))
            ((managed-dialect-opcode? (car inst))
             (lir-report-error
              (string-append "Managed runtime dialect opcode forbidden in Core Machine LIR: "
                             (symbol->string (car inst)))
              inst)
             #f)
            (else
             (loop (cdr is))))))))

(define (lir-verify-core-purity prog)
  (let* ((funcs-clause (assq '%lir-functions (cdr prog)))
         (main-clause (assq '%lir-main (cdr prog)))
         (funcs (if funcs-clause (cdr funcs-clause) '())))
    (and
     (let f-loop ((fs funcs))
       (if (null? fs)
           #t
           (let* ((fn (car fs))
                  (lbl (if (pair? (cdr fn)) (cadr fn) '%unknown-fn))
                  (body-clause (assq 'body (cdr fn)))
                  (body-insts (if body-clause (cdr body-clause) '())))
             (and (with-verifier-context (list (cons 'phase 'core-lir) (cons 'function lbl))
                    (lambda () (lir-check-no-managed-insts body-insts lbl)))
                  (f-loop (cdr fs))))))
     (if main-clause
         (let* ((body-clause (assq 'body (cdr main-clause)))
                (body-insts (if body-clause (cdr body-clause) '())))
           (with-verifier-context (list (cons 'phase 'core-lir) (cons 'function '%lir-main))
             (lambda () (lir-check-no-managed-insts body-insts '%lir-main))))
         #t))))

(define (lir-physical-register-sym? sym)
  (and (symbol? sym)
       (or (memq sym *canonical-lir-registers*)
           (memq sym *canonical-lir-float-registers*)
           (eq? sym '%cl))))

(define (lir-virtual-register? x)
  (and (pair? x)
       (or (eq? (car x) '%reg)
           (eq? (car x) '%freg))))

(define (lir-tree-has-virtual-reg? tree)
  (cond
    ((not (pair? tree)) #f)
    ((lir-virtual-register? tree) #t)
    (else (or (lir-tree-has-virtual-reg? (car tree))
              (lir-tree-has-virtual-reg? (cdr tree))))))

(define (lir-block-param-physical? p)
  (or (lir-physical-register-sym? p)
      (and (pair? p) (eq? (car p) '%stack) (pair? (cdr p)) (integer? (cadr p)))))

(define (lir-check-no-virtual-regs insts fn-name)
  (let loop ((is insts))
    (if (null? is)
        #t
        (let ((inst (car is)))
          (cond
            ((not (pair? inst))
             (loop (cdr is)))
            ((eq? (car inst) '%block)
             (let ((params (if (and (pair? (cdr inst)) (pair? (cddr inst)) (list? (caddr inst)))
                               (caddr inst)
                               '()))
                   (body (if (and (pair? (cdr inst)) (pair? (cddr inst))) (cdddr inst) '())))
               (let pchk ((ps params))
                 (cond
                   ((null? ps)
                    (and (lir-check-no-virtual-regs body fn-name)
                         (loop (cdr is))))
                   ((lir-block-param-physical? (car ps))
                    (pchk (cdr ps)))
                   (else
                    (lir-report-error
                     (string-append "Virtual %block parameter forbidden in Machine LIR (L_lir_mach): "
                                    (if (symbol? (car ps)) (symbol->string (car ps)) "non-symbol"))
                     inst)
                    #f)))))
            ((lir-tree-has-virtual-reg? inst)
             (lir-report-error "Unallocated virtual register forbidden in Machine LIR (L_lir_mach)" inst)
             #f)
            (else
             (loop (cdr is))))))))

(define (lir-verify-mach-purity prog)
  (let* ((funcs-clause (assq '%lir-functions (cdr prog)))
         (main-clause (assq '%lir-main (cdr prog)))
         (funcs (if funcs-clause (cdr funcs-clause) '())))
    (and
     (let f-loop ((fs funcs))
       (if (null? fs)
           #t
           (let* ((fn (car fs))
                  (lbl (if (pair? (cdr fn)) (cadr fn) '%unknown-fn))
                  (body-clause (assq 'body (cdr fn)))
                  (body-insts (if body-clause (cdr body-clause) '())))
             (and (with-verifier-context (list (cons 'phase 'mach-lir) (cons 'function lbl))
                    (lambda () (lir-check-no-virtual-regs body-insts lbl)))
                  (f-loop (cdr fs))))))
     (if main-clause
         (let* ((body-clause (assq 'body (cdr main-clause)))
                (body-insts (if body-clause (cdr body-clause) '())))
           (with-verifier-context (list (cons 'phase 'mach-lir) (cons 'function '%lir-main))
             (lambda () (lir-check-no-virtual-regs body-insts '%lir-main))))
         #t))))

(define (validate-core-lir prog)
  (and (validate-lir prog)
       (lir-verify-core-purity prog)
       (if (and (>= (verifier-level) 3)
                (assq 'L_lir_core (nanopass-get-languages)))
           (if (not (nanopass-ast-valid? 'L_lir_core prog))
               (begin
                 (lir-report-error "Program violates L_lir_core schema invariants" prog)
                 #f)
               #t)
           #t)))

(define (verify-core-lir prog)
  (if (not (verifier-enabled?))
      #t
      (validate-core-lir prog)))

(define (validate-mir-ssa prog)
  (and (validate-lir-general prog)
       (lir-verify-core-purity prog)
       (if (and (>= (verifier-level) 3)
                (assq 'L_mir_ssa (nanopass-get-languages)))
           (if (not (nanopass-ast-valid? 'L_mir_ssa prog))
               (begin
                 (lir-report-error "Program violates L_mir_ssa schema invariants" prog)
                 #f)
               #t)
           #t)))

(define (verify-mir-ssa prog)
  (if (not (verifier-enabled?))
      #t
      (validate-mir-ssa prog)))

(define (validate-mach-lir prog)
  (and (validate-lir-general prog)
       (lir-verify-core-purity prog)
       (lir-verify-mach-purity prog)
       (if (and (>= (verifier-level) 3)
                (assq 'L_lir_mach (nanopass-get-languages)))
           (if (not (nanopass-ast-valid? 'L_lir_mach prog))
               (begin
                 (lir-report-error "Program violates L_lir_mach schema invariants" prog)
                 #f)
               #t)
           #t)))

(define (verify-mach-lir prog)
  (if (not (verifier-enabled?))
      #t
      (validate-mach-lir prog)))

(define validate-lir
  (case-lambda
    ((prog) (validate-lir-general prog))
    ((prog dialect)
     (cond
       ((eq? dialect 'core) (validate-core-lir prog))
       ((or (eq? dialect 'mir-ssa) (eq? dialect 'mir)) (validate-mir-ssa prog))
       ((or (eq? dialect 'mach) (eq? dialect 'mach-lir)) (validate-mach-lir prog))
       (else (validate-lir-general prog))))))

(define (lir-valid-data-chunk? dc)
  (cond
    ((integer? dc)
     (and (>= dc 0) (<= dc 255)))
    ((and (pair? dc) (eq? (car dc) 'zero))
     (and (= (length dc) 2)
          (integer? (cadr dc))
          (>= (cadr dc) 0)))
    ((and (pair? dc) (eq? (car dc) 'reloc))
     (and (= (length dc) 3)
          (symbol? (cadr dc))
          (integer? (caddr dc))))
    (else #f)))

(define (lir-valid-data-entry? de)
  (and (pair? de)
       (case (car de)
         ((bss)
          (and (= (length de) 4)
               (symbol? (cadr de))
               (integer? (caddr de))
               (>= (caddr de) 1)
               (integer? (cadddr de))
               (>= (cadddr de) 0)))
         ((bytes)
          (and (>= (length de) 3)
               (symbol? (cadr de))
               (integer? (caddr de))
               (>= (caddr de) 1)
               (let loop ((cs (cdddr de)))
                 (if (null? cs)
                     #t
                     (and (lir-valid-data-chunk? (car cs))
                          (loop (cdr cs)))))))
         (else #f))))

(define (lir-valid-data-clause? data-clause)
  (and (pair? data-clause)
       (eq? (car data-clause) 'data)
       (pair? (cdr data-clause))
       (null? (cddr data-clause))
       (list? (cadr data-clause))
       (let loop ((des (cadr data-clause)))
         (if (null? des)
             #t
             (and (lir-valid-data-entry? (car des))
                  (loop (cdr des)))))))

(define (validate-lir-general prog)
  (cond
    ((not (and (pair? prog) (eq? (car prog) '%lir-program)))
     (lir-report-error "Root of LIR AST must be %lir-program" prog))
    (else
     (let* ((strings-clause (assq 'strings (cdr prog)))
            (data-clause (assq 'data (cdr prog)))
            (stackmaps-clause (assq 'stackmaps (cdr prog)))
            (funcs-clause (assq '%lir-functions (cdr prog)))
            (main-clause (assq '%lir-main (cdr prog))))
       (cond
         ((not strings-clause)
          (lir-report-error "%lir-program missing (strings ...) clause" prog))
         ((and data-clause (not (lir-valid-data-clause? data-clause)))
          (lir-report-error "Invalid (data ...) clause in %lir-program" data-clause))
         ((not stackmaps-clause)
          (lir-report-error "%lir-program missing (stackmaps ...) clause" prog))
         ((not funcs-clause)
          (lir-report-error "%lir-program missing (%lir-functions ...) clause" prog))
         ((not main-clause)
          (lir-report-error "%lir-program missing (%lir-main ...) clause" prog))
         (else
          (let* ((funcs (cdr funcs-clause))
                 (known-fn-set (make-symbol-hash-set (lir-max2 32 (* 2 (length funcs))))))
            ;; Populate known function labels in O(1)
            (let extract ((fs funcs))
              (if (null? fs)
                  #t
                  (begin
                    (if (and (pair? (car fs)) (pair? (cdar fs)) (symbol? (cadar fs)))
                        (symbol-hash-set-add! known-fn-set (cadar fs)))
                    (extract (cdr fs)))))
            (and (verify-lir-safepoint prog)
                 (let f-loop ((fs funcs))
                   (if (null? fs) #t
                       (and (lir-valid-function? (car fs) known-fn-set)
                            (f-loop (cdr fs)))))
                 (lir-valid-main? main-clause known-fn-set)
                 (if (and (>= (verifier-level) 3)
                          (assq 'L_lir_canonical (nanopass-get-languages)))
                     (if (not (nanopass-ast-valid? 'L_lir_canonical prog))
                         (lir-report-error "Program violates L_lir_canonical schema invariants" prog)
                         #t)
                     #t)))))))))

(define (verify-lir prog)
  (if (not (verifier-enabled?))
      #t
      (validate-lir prog)))
