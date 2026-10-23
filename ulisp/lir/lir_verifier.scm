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
;;; CFG Invariants: Label Uniqueness, Resolution, and Block Arity Matching
;;; -----------------------------------------------------------------------
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
  (let loop ((is insts))
    (if (null? is)
        #t
        (let ((inst (car is)))
          (cond
            ((not (pair? inst)) (loop (cdr is)))
            ((eq? (car inst) '%block)
             (and (loop (cdddr inst))
                  (loop (cdr is))))
            ((eq? (car inst) '%jump)
             (let* ((target (cadr inst))
                    (args (if (pair? (cddr inst)) (caddr inst) '()))
                    (param-entry (assq target block-params)))
               (cond
                 ((and (not (memq target defined-labels))
                       (not (memq target known-fn-labels)))
                  (lir-report-error "Undefined jump target label" target))
                 ((and param-entry (not (= (length args) (cdr param-entry))))
                  (lir-report-error "Jump argument count does not match %block parameter count" inst))
                 (else
                  (loop (cdr is))))))
            ((eq? (car inst) '%jump-if-false)
             (let* ((target (caddr inst))
                    (args (if (pair? (cdddr inst)) (cadddr inst) '()))
                    (param-entry (assq target block-params)))
               (cond
                 ((and (not (memq target defined-labels))
                       (not (memq target known-fn-labels)))
                  (lir-report-error "Undefined jump target in %jump-if-false" target))
                 ((and param-entry (pair? args) (not (= (length args) (cdr param-entry))))
                  (lir-report-error "%jump-if-false argument count mismatch with %block" inst))
                 (else
                  (loop (cdr is))))))
            ((eq? (car inst) '%jump-if)
             (let* ((then-target (caddr inst))
                    (then-args (cadddr inst))
                    (else-target (car (cddddr inst)))
                    (else-args (cadr (cddddr inst)))
                    (then-entry (assq then-target block-params))
                    (else-entry (assq else-target block-params)))
               (cond
                 ((and (not (memq then-target defined-labels))
                       (not (memq then-target known-fn-labels)))
                  (lir-report-error "Undefined then-target in %jump-if" then-target))
                 ((and (not (memq else-target defined-labels))
                       (not (memq else-target known-fn-labels)))
                  (lir-report-error "Undefined else-target in %jump-if" else-target))
                 ((and then-entry (pair? then-args) (not (= (length then-args) (cdr then-entry))))
                  (lir-report-error "%jump-if then-argument count mismatch with %block" inst))
                 ((and else-entry (pair? else-args) (not (= (length else-args) (cdr else-entry))))
                  (lir-report-error "%jump-if else-argument count mismatch with %block" inst))
                 (else
                  (loop (cdr is))))))
            ((or (eq? (car inst) '%jump-cond)
                 (eq? (car inst) '%jump-if-zero))
             (let ((target (if (eq? (car inst) '%jump-cond) (caddr inst) (cadr inst))))
               (if (and (not (memq target defined-labels))
                        (not (memq target known-fn-labels)))
                   (lir-report-error "Undefined jump condition target" target)
                   (loop (cdr is)))))
            (else
             (loop (cdr is))))))))

(define (lir-verify-insts-and-cfg insts known-fn-labels)
  (let ((label-info (lir-collect-labels-and-params insts)))
    (if (not label-info)
        #f
        (let ((defined-labels (car label-info))
              (block-params (cdr label-info)))
          (and (let i-loop ((is insts))
                 (if (null? is) #t
                     (and (lir-valid-inst? (car is))
                          (i-loop (cdr is)))))
               (lir-verify-cfg-targets insts defined-labels block-params known-fn-labels))))))

;;; -----------------------------------------------------------------------
;;; Function-Level and Program-Level Validation
;;; -----------------------------------------------------------------------
(define (lir-valid-function? fn known-fn-labels)
  (cond
    ((not (and (pair? fn) (eq? (car fn) '%lir-function)))
     (lir-report-error "Function node must start with %lir-function" fn))
    ((not (symbol? (cadr fn)))
     (lir-report-error "%lir-function name must be a symbol" fn))
    (else
     (let* ((params-clause (assq 'params (cddr fn)))
            (frame-clause (assq 'frame-size (cddr fn)))
            (body-clause (assq 'body (cddr fn))))
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
          (lir-verify-insts-and-cfg (cdr body-clause) known-fn-labels)))))))

(define (lir-valid-main? main-clause known-fn-labels)
  (cond
    ((not (and (pair? main-clause) (eq? (car main-clause) '%lir-main)))
     (lir-report-error "%lir-main node must start with %lir-main" main-clause))
    (else
     (let ((frame-clause (assq 'frame-size (cdr main-clause)))
           (body-clause (assq 'body (cdr main-clause))))
       (cond
         ((not (and frame-clause (integer? (cadr frame-clause))
                    (>= (cadr frame-clause) 0)
                    (= (modulo (cadr frame-clause) 8) 0)))
          (lir-report-error "%lir-main frame-size must be a non-negative multiple of 8" main-clause))
         ((not (and body-clause (list? (cdr body-clause))))
          (lir-report-error "%lir-main must have valid (body <insts>...) clause" main-clause))
         (else
          (lir-verify-insts-and-cfg (cdr body-clause) known-fn-labels)))))))

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
                 (known-fn-labels
                  (let extract ((fs funcs) (acc '()))
                    (if (null? fs)
                        (reverse acc)
                        (if (and (pair? (car fs)) (pair? (cdar fs)) (symbol? (cadar fs)))
                            (extract (cdr fs) (cons (cadar fs) acc))
                            (extract (cdr fs) acc))))))
            (and (verify-lir-safepoint prog)
                 (let f-loop ((fs funcs))
                   (if (null? fs) #t
                       (and (lir-valid-function? (car fs) known-fn-labels)
                            (f-loop (cdr fs)))))
                 (lir-valid-main? main-clause known-fn-labels)
                 (if (not (nanopass-ast-valid? 'L_lir_canonical prog))
                     (lir-report-error "Program violates L_lir_canonical schema invariants" prog)
                     #t)))))))))

(define (verify-lir prog)
  (if (not (verifier-enabled?))
      #t
      (validate-lir prog)))
