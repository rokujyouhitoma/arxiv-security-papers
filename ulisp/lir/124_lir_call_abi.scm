;;; =======================================================================
;;; ULisp Compiler Pass 124: LIR Procedure Invocations & Call ABI Pass
;;; Conforms to DSN-33 Architecture Specification & Issue #583, #625
;;; =======================================================================
;;; Lowers general closure calls and direct static-label calls into LIR instructions,
;;; handling System V AMD64 register argument passing (rdi, rsi, rdx, rcx, r8, r9),
;;; stack spill argument evaluation, frame shift alignment, Tail Call Optimization (TCO),
;;; and exact GC safepoint registration.
;;; =======================================================================

(define *arg-registers* '(%rdi %rsi %rdx %rcx %r8 %r9))

(define (lir-compile-call proc args si env tail?)
  (let* ((num-args (length args))
         (cur-params-entry (assq '%num-params env))
         (cur-num-params (if cur-params-entry (cdr cur-params-entry) #f))
         (stack-vars (get-stack-vars env))
         (is-stack-closure? (and (symbol? proc) (memq proc stack-vars)))
         (can-tco? (and tail?
                        (not is-stack-closure?)
                        (if cur-num-params
                            (or (= cur-num-params num-args)
                                (and (<= cur-num-params 6) (<= num-args 6)))
                            #f)))
         (frame-shift (align-frame-shift (if (= num-args 0)
                                             (- 0 si)
                                             (- (* 8 (- num-args 1)) si))))
         (aligned-si (if (= num-args 0)
                         (- 0 frame-shift)
                         (- (* 8 (- num-args 1)) frame-shift))))
    ;; 1. Evaluate arguments sequentially and place into temporary stack slots
    (let loop ((as args) (curr-si aligned-si))
      (if (not (null? as))
          (begin
            (track-lir-si! curr-si)
            (lir-compile-expr (car as) curr-si env #f)
            (emit-lir! (list '%store '%rsp curr-si '%rax))
            (loop (cdr as) (- curr-si 8)))))

    (let ((end-args-si (- aligned-si (* num-args 8))))
      (track-lir-si! end-args-si)
      ;; 2. Evaluate procedure expression -> RAX
      (lir-compile-expr proc end-args-si env #f)
      (emit-lir! '(%mov %r10 %rax))

      (if can-tco?
          ;; --- TAIL CALL OPTIMIZATION (TCO) ---
          (begin
            (let loop ((i 0))
              (if (< i num-args)
                  (if (< i 6)
                      (let ((temp-offset (- aligned-si (* i 8)))
                            (reg (list-ref *arg-registers* i)))
                        (emit-lir! (list '%load reg '%rsp temp-offset))
                        (loop (+ i 1)))
                      (let ((temp-offset (- aligned-si (* i 8)))
                            (param-offset (* 8 (- num-args i))))
                        (emit-lir! (list '%load '%r11 '%rsp temp-offset))
                        (emit-lir! (list '%store '%rsp param-offset '%r11))
                        (loop (+ i 1))))))
            (emit-lir! '(%load %r11 %r10 -1))
            (emit-lir! (list '%mov '%rax (* num-args 4)))
            (emit-lir! '(%jump %r11)))

          ;; --- NON-TAIL CALL ---
          (let* ((bitmap (compute-stackmap-bitmap frame-shift aligned-si args env))
                 (safepoint-lbl (new-safepoint-label!)))
            (record-safepoint! safepoint-lbl frame-shift bitmap)
            ;; Load register arguments (0..min(num-args, 6)-1)
            (let loop ((i 0))
              (if (and (< i num-args) (< i 6))
                  (let ((temp-offset (- aligned-si (* i 8)))
                        (reg (list-ref *arg-registers* i)))
                    (emit-lir! (list '%load reg '%rsp temp-offset))
                    (loop (+ i 1)))))
            (emit-lir! (list '%mov '%rax (* num-args 4)))
            (emit-lir! (list '%call-closure frame-shift safepoint-lbl)))))))

(define (direct-call-simple-arg? arg env)
  (cond
    ((integer? arg)
     (let ((q (quotient arg 1073741824)))
       (and (< q 536870912) (> q -536870912))))
    ((and (symbol? arg) (number? (env-stack-slot? arg env))) #t)
    ((and (pair? arg) (eq? (car arg) '%unbox-fixnum))
     (let ((inner (cadr arg)))
       (or (integer? inner)
           (and (symbol? inner)
                (number? (env-stack-slot? inner env))
                (memq inner (get-raw-vars env))))))
    (else #f)))

(define (every-direct-simple-arg? args env)
  (let loop ((as args))
    (if (null? as)
        #t
        (and (direct-call-simple-arg? (car as) env)
             (loop (cdr as))))))

(define (emit-direct-simple-arg! arg reg env)
  (cond
    ((integer? arg)
     (emit-lir! (list '%mov reg (* arg 4))))
    ((symbol? arg)
     (let ((slot (env-stack-slot? arg env)))
       (emit-lir! (list '%load reg '%rsp slot))))
    ((and (pair? arg) (eq? (car arg) '%unbox-fixnum))
     (let ((inner (cadr arg)))
       (if (integer? inner)
           (emit-lir! (list '%mov reg inner))
           (let ((slot (env-stack-slot? inner env)))
             (emit-lir! (list '%load reg '%rsp slot))))))))

(define (lir-compile-direct-call label args si env tail?)
  (let* ((num-args (length args))
         (cur-params-entry (assq '%num-params env))
         (cur-num-params (if cur-params-entry (cdr cur-params-entry) #f))
         (can-tco? (and tail?
                        (if cur-num-params
                            (or (= cur-num-params num-args)
                                (and (<= cur-num-params 6) (<= num-args 6)))
                            #f)))
         (cur-fn-entry (assq '%current-func env))
         (is-self-call (and cur-fn-entry (eq? (cdr cur-fn-entry) label)))
         (loop-head-entry (and is-self-call (assq '%self-loop-head env)))
         (self-loop-head (if loop-head-entry (cdr loop-head-entry) #f))
         (direct-simple? (and (<= num-args 6) (every-direct-simple-arg? args env))))
    (if direct-simple?
        ;; Fast path: All arguments are immediate constants or stack variables (no temp stack spill needed)
        (let ((frame-shift (align-frame-shift (- 0 si))))
          (let loop ((as args) (i 0))
            (if (not (null? as))
                (begin
                  (emit-direct-simple-arg! (car as) (list-ref *arg-registers* i) env)
                  (loop (cdr as) (+ i 1)))))
          (if can-tco?
              (if (and self-loop-head (= cur-num-params num-args))
                  (emit-lir! (list '%jump self-loop-head))
                  (begin
                    (emit-lir! (list '%mov '%rax (* num-args 4)))
                    (emit-lir! (list '%direct-jump label))))
              (let* ((bitmap (compute-stackmap-bitmap frame-shift (- 0 frame-shift) '() env))
                     (safepoint-lbl (new-safepoint-label!)))
                (record-safepoint! safepoint-lbl frame-shift bitmap)
                (emit-lir! (list '%mov '%rax (* num-args 4)))
                (emit-lir! (list '%direct-call label frame-shift safepoint-lbl)))))
        ;; Standard path: Evaluate arguments sequentially into temporary stack slots
        (let* ((frame-shift (align-frame-shift (if (= num-args 0)
                                                   (- 0 si)
                                                   (- (* 8 (- num-args 1)) si))))
               (aligned-si (if (= num-args 0)
                               (- 0 frame-shift)
                               (- (* 8 (- num-args 1)) frame-shift))))
          ;; 1. Evaluate arguments sequentially and place into temporary stack slots
          (let loop ((as args) (curr-si aligned-si))
            (if (not (null? as))
                (begin
                  (track-lir-si! curr-si)
                  (lir-compile-expr (car as) curr-si env #f)
                  (emit-lir! (list '%store '%rsp curr-si '%rax))
                  (loop (cdr as) (- curr-si 8)))))

          (if can-tco?
              ;; --- TAIL CALL OPTIMIZATION (TCO) via Direct Jump ---
              (begin
                (let loop ((i 0))
                  (if (< i num-args)
                      (if (< i 6)
                          (let ((temp-offset (- aligned-si (* i 8)))
                                (reg (list-ref *arg-registers* i)))
                            (emit-lir! (list '%load reg '%rsp temp-offset))
                            (loop (+ i 1)))
                          (let ((temp-offset (- aligned-si (* i 8)))
                                (param-offset (* 8 (- num-args i))))
                            (emit-lir! (list '%load '%r11 '%rsp temp-offset))
                            (emit-lir! (list '%store '%rsp param-offset '%r11))
                            (loop (+ i 1))))))
                (if (and self-loop-head (= cur-num-params num-args))
                    (emit-lir! (list '%jump self-loop-head))
                    (begin
                      (emit-lir! (list '%mov '%rax (* num-args 4)))
                      (emit-lir! (list '%direct-jump label)))))

              ;; --- NON-TAIL DIRECT CALL ---
              (let* ((bitmap (compute-stackmap-bitmap frame-shift aligned-si args env))
                     (safepoint-lbl (new-safepoint-label!)))
                (record-safepoint! safepoint-lbl frame-shift bitmap)
                ;; Load register arguments (0..min(num-args, 6)-1)
                (let loop ((i 0))
                  (if (and (< i num-args) (< i 6))
                      (let ((temp-offset (- aligned-si (* i 8)))
                            (reg (list-ref *arg-registers* i)))
                        (emit-lir! (list '%load reg '%rsp temp-offset))
                        (loop (+ i 1)))))
                (emit-lir! (list '%mov '%rax (* num-args 4)))
                (emit-lir! (list '%direct-call label frame-shift safepoint-lbl))))))))

;;; -----------------------------------------------------------------------
;;; Foreign Function Interface (C-FFI) / System V AMD64 ABI Calls
;;; -----------------------------------------------------------------------

(define (parse-foreign-args args)
  (let loop ((as args) (rev-types '()) (rev-exprs '()))
    (if (null? as)
        (cons (reverse rev-types) (reverse rev-exprs))
        (let ((item (car as)))
          (cond
            ((and (pair? item)
                  (symbol? (car item))
                  (memq (car item) '(string cstr f32 f64 float double i8 u8 i16 u16 i32 u32 i64 u64 int ptr fixnum))
                  (pair? (cdr item))
                  (null? (cddr item)))
             (loop (cdr as)
                   (cons (car item) rev-types)
                   (cons (cadr item) rev-exprs)))
            ((string? item)
             (loop (cdr as)
                   (cons 'string rev-types)
                   (cons item rev-exprs)))
            (else
             (loop (cdr as)
                   (cons 'ptr rev-types)
                   (cons item rev-exprs))))))))

(define (lir-compile-foreign-call func raw-args si env convention return-type varargs?)
  (let* ((parsed (parse-foreign-args raw-args))
         (arg-types (car parsed))
         (arg-exprs (cdr parsed))
         (num-args (length arg-exprs))
         (layout (compute-call-abi-layout convention arg-types varargs?))
         (locations (abi-layout-locations layout))
         (stack-bytes (abi-layout-stack-bytes layout))
         (al-val (abi-layout-al-val layout))
         (eval-frame-shift (align-frame-shift (if (= num-args 0)
                                                  (- 0 si)
                                                  (- (* 8 (- num-args 1)) si))))
         (aligned-si (if (= num-args 0)
                         (- 0 eval-frame-shift)
                         (- (* 8 (- num-args 1)) eval-frame-shift))))
    ;; 1. Evaluate arguments sequentially and place into temporary stack slots
    (let loop ((as arg-exprs) (types arg-types) (curr-si aligned-si) (i 0))
      (if (not (null? as))
          (let ((expr (car as))
                (ty (car types)))
            (track-lir-si! curr-si)
            (if (and (arg-type-float? ty) (number? expr))
                (begin
                  (if (integer? expr)
                      (begin
                        (emit-lir! (list '%mov '%rax expr))
                        (emit-lir! '(%sitofp %xmm0 %rax)))
                      (begin
                        (emit-lir! (list '%mov '%rax (inexact->exact (round (* expr 1000000)))))
                        (emit-lir! '(%sitofp %xmm0 %rax))))
                  (emit-lir! (list '%store-typed 'f64 '%rsp curr-si '%xmm0)))
                (begin
                  (lir-compile-expr expr curr-si env #f)
                  (cond
                    ((memq ty '(string cstr))
                     (emit-lir! '(%sub %rax 3))
                     (emit-lir! (list '%store '%rsp curr-si '%rax)))
                    ((eq? ty 'fixnum)
                     (emit-lir! '(%sar %rax 2))
                     (emit-lir! (list '%store '%rsp curr-si '%rax)))
                    ((arg-type-float? ty)
                     (emit-lir! '(%unbox-flonum %xmm0 %rax))
                     (emit-lir! (list '%store-typed 'f64 '%rsp curr-si '%xmm0)))
                    (else
                     (emit-lir! (list '%store '%rsp curr-si '%rax))))))
            (loop (cdr as) (cdr types) (- curr-si 8) (+ i 1)))))

    (let* ((end-si (- aligned-si (* num-args 8)))
           (final-frame-shift (align-frame-shift (+ (- 0 end-si) stack-bytes))))
      (track-lir-si! (- 0 final-frame-shift))

      ;; 2. For stack spill arguments, write to outgoing stack slots
      (let loop ((locs locations))
        (if (not (null? locs))
            (let ((loc (car locs)))
              (if (eq? (abi-arg-loc-kind loc) 'stack)
                  (let* ((idx (abi-arg-loc-index loc))
                         (temp-slot (- aligned-si (* idx 8)))
                         (stk-offset (abi-arg-loc-offset loc))
                         (target-slot (- stk-offset final-frame-shift))
                         (ty (abi-arg-loc-type loc)))
                    (track-lir-si! target-slot)
                    (if (arg-type-float? ty)
                        (begin
                          (emit-lir! (list '%load-typed 'f64 '%xmm0 '%rsp temp-slot))
                          (emit-lir! (list '%store-typed 'f64 '%rsp target-slot '%xmm0)))
                        (begin
                          (emit-lir! (list '%load '%r11 '%rsp temp-slot))
                          (emit-lir! (list '%store '%rsp target-slot '%r11))))))
              (loop (cdr locs)))))

      ;; 3. Load register arguments (GPR and XMM)
      (let loop ((locs locations))
        (if (not (null? locs))
            (let ((loc (car locs)))
              (cond
                ((eq? (abi-arg-loc-kind loc) 'gpr)
                 (let* ((idx (abi-arg-loc-index loc))
                        (temp-slot (- aligned-si (* idx 8)))
                        (reg (abi-arg-loc-target loc)))
                   (emit-lir! (list '%load reg '%rsp temp-slot))))
                ((eq? (abi-arg-loc-kind loc) 'xmm)
                 (let* ((idx (abi-arg-loc-index loc))
                        (temp-slot (- aligned-si (* idx 8)))
                        (reg (abi-arg-loc-target loc))
                        (ty (abi-arg-loc-type loc)))
                   (if (eq? ty 'f32)
                       (emit-lir! (list '%load-typed 'f32 reg '%rsp temp-slot))
                       (emit-lir! (list '%load-typed 'f64 reg '%rsp temp-slot))))))
              (loop (cdr locs)))))

      ;; 4. Emit foreign call instruction
      (let ((fn-name (cond
                       ((string? func) func)
                       ((symbol? func) (symbol->string func))
                       (else func))))
        (emit-lir! (list '%c-call fn-name final-frame-shift al-val)))

      ;; 5. Handle return value
      (cond
        ((eq? return-type 'void)
         (emit-lir! '(%mov %rax 63)))
        ((arg-type-float? return-type)
         (emit-lir! '(%alloc %rax 16 3))
         (emit-lir! '(%store-typed f64 %rax 8 %xmm0)))
        ((memq return-type '(fixnum int))
         (emit-lir! '(%shl %rax 2)))
        (else #t)))))

(define (lir-compile-c-call expr si env tail?)
  (let ((func (cadr expr))
        (rest (cddr expr)))
    (cond
      ((and (pair? rest) (list? (car rest)))
       (let* ((args (car rest))
              (ret-type (if (pair? (cdr rest)) (cadr rest) 'any))
              (varargs? (if (and (pair? (cdr rest)) (pair? (cddr rest))) (caddr rest) #f)))
         (lir-compile-foreign-call func args si env 'sysv-abi ret-type varargs?)))
      (else
       (lir-compile-foreign-call func rest si env 'sysv-abi 'any #f)))))

(define (lir-compile-foreign-call-expr expr si env tail?)
  (let* ((conv (cadr expr))
         (ret-type (caddr expr))
         (func (cadddr expr))
         (args (car (cddddr expr)))
         (varargs? (if (pair? (cdr (cddddr expr))) (cadr (cddddr expr)) #f)))
    (lir-compile-foreign-call func args si env conv ret-type varargs?)))
