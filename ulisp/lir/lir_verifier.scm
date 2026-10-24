;;; =======================================================================
;;; ULisp Compiler: Canonical LIR Specification Verifier & Boundary Validator
;;; Conforms to DSN-33 Architecture Specification & Issue #589
;;; =======================================================================

(define *canonical-lir-registers*
  '(%rax %rbx %rcx %rdx %rsi %rdi %rbp %rsp
    %r8  %r9  %r10 %r11 %r12 %r13 %r14 %r15 %al))

(define (lir-symbol-starts-with-percent? sym)
  (and (symbol? sym)
       (let ((str (symbol->string sym)))
         (and (> (string-length str) 1)
              (char=? (string-ref str 0) #\%)))))

(define (lir-valid-register? reg)
  (cond
    ((memq reg *canonical-lir-registers*) #t)
    ((and (pair? reg) (eq? (car reg) '%reg) (pair? (cdr reg))
          (memq (cadr reg) *canonical-lir-registers*)) #t)
    (else #f)))

(define (lir-valid-lvalue? opnd)
  (cond
    ((lir-valid-register? opnd) #t)
    ((and (pair? opnd) (eq? (car opnd) '%stack) (pair? (cdr opnd))
          (integer? (cadr opnd))) #t)
    ((and (pair? opnd) (eq? (car opnd) '%mem) (pair? (cdr opnd)) (pair? (cddr opnd)))
     (and (lir-valid-register? (cadr opnd))
          (or (integer? (caddr opnd)) (lir-valid-register? (caddr opnd)))))
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
          (or (integer? (caddr opnd)) (lir-valid-register? (caddr opnd)))))
    (else #f)))

(define (lir-atomic-operand? opnd)
  (or (integer? opnd)
      (and (symbol? opnd) (not (lir-symbol-starts-with-percent? opnd)))
      (lir-valid-register? opnd)
      (and (pair? opnd) (eq? (car opnd) '%stack) (pair? (cdr opnd)) (integer? (cadr opnd)))))

(define (lir-report-error msg expr)
  (verifier-error 'canonical-lir msg expr))

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

          ((%return)
           (if (or (= (length inst) 1)
                   (and (= (length inst) 2) (lir-valid-operand? (cadr inst))))
               #t
               (lir-report-error "Invalid %return instruction format" inst)))

          ;; Calls & ABI
          ((%c-call)
           (if (and (= (length inst) 3)
                    (or (symbol? (cadr inst)) (string? (cadr inst)))
                    (integer? (caddr inst)))
               #t
               (lir-report-error "%c-call format must be (%c-call <fn-name> <shift>)" inst)))

          ((%call-closure)
           (if (or (and (= (length inst) 2) (integer? (cadr inst)))
                   (and (= (length inst) 3) (integer? (cadr inst)) (or (symbol? (caddr inst)) (not (caddr inst)))))
               #t
               (lir-report-error "%call-closure format must be (%call-closure <shift> [<safepoint>])" inst)))

          ((%direct-call)
           (if (or (and (= (length inst) 3) (symbol? (cadr inst)) (integer? (caddr inst)))
                   (and (= (length inst) 4) (symbol? (cadr inst)) (integer? (caddr inst))
                        (or (symbol? (cadddr inst)) (not (cadddr inst)))))
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
                    (or (integer? (cadddr inst)) (lir-valid-register? (cadddr inst))))
               #t
               (lir-report-error "%load format must be (%load <dst-reg> <base-reg> <offset>)" inst)))

          ((%store)
           (if (and (= (length inst) 4)
                    (lir-valid-register? (cadr inst))
                    (or (integer? (caddr inst)) (lir-valid-register? (caddr inst)))
                    (lir-valid-operand? (cadddr inst)))
               #t
               (lir-report-error "%store format must be (%store <base-reg> <offset> <src>)" inst)))

          ((%load-byte-zx)
           (if (and (= (length inst) 4)
                    (lir-valid-register? (cadr inst))
                    (lir-valid-register? (caddr inst))
                    (integer? (cadddr inst)))
               #t
               (lir-report-error "%load-byte-zx format must be (%load-byte-zx <dst> <base> <offset>)" inst)))

          ((%store-byte)
           (if (and (= (length inst) 4)
                    (lir-valid-register? (cadr inst))
                    (integer? (caddr inst))
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
                    (symbol? (caddr inst)))
               #t
               (lir-report-error "%code-ref format must be (%code-ref <dst> <lbl>)" inst)))

          ((%str-ref)
           (if (and (= (length inst) 3)
                    (lir-valid-register? (cadr inst))
                    (symbol? (caddr inst)))
               #t
               (lir-report-error "%str-ref format must be (%str-ref <dst> <lbl>)" inst)))

          ((%global-ref)
           (if (and (= (length inst) 3)
                    (lir-valid-register? (cadr inst))
                    (symbol? (caddr inst)))
               #t
               (lir-report-error "%global-ref format must be (%global-ref <reg> <var-sym>)" inst)))

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

          ((%shl %shr %sar)
           (if (and (= (length inst) 3)
                    (lir-valid-operand? (cadr inst))
                    (integer? (caddr inst)))
               #t
               (lir-report-error (string-append (symbol->string op) " shift count must be an integer") inst)))

          ((%cqo %syscall %raise)
           (if (= (length inst) 1)
               #t
               (lir-report-error (string-append (symbol->string op) " takes zero operands") inst)))

          ((%idiv)
           (if (and (= (length inst) 2) (lir-valid-operand? (cadr inst)))
               #t
               (lir-report-error "%idiv takes 1 operand" inst)))

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
                   (eq? (car inst) '%jump-if-zero))
               (let ((target (if (eq? (car inst) '%jump-cond) (caddr inst) (cadr inst))))
                 (if (and (not (symbol-hash-set-contains? label-set target))
                          (not (symbol-hash-set-contains? known-set target)))
                     (lir-report-error "Undefined jump condition target" target)
                     (loop (cdr is)))))
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
;;; Public API: validate-lir / verify-lir
;;; -----------------------------------------------------------------------
(define (validate-lir prog)
  (cond
    ((not (and (pair? prog) (eq? (car prog) '%lir-program)))
     (lir-report-error "Root of LIR AST must be %lir-program" prog))
    (else
     (let* ((strings-clause (assq 'strings (cdr prog)))
            (stackmaps-clause (assq 'stackmaps (cdr prog)))
            (funcs-clause (assq '%lir-functions (cdr prog)))
            (main-clause (assq '%lir-main (cdr prog))))
       (cond
         ((not strings-clause)
          (lir-report-error "%lir-program missing (strings ...) clause" prog))
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
