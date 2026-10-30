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
                        (if cur-num-params (= cur-num-params num-args) #f)))
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
    ((integer? arg) #t)
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
         (can-tco? (and tail? (if cur-num-params (= cur-num-params num-args) #f)))
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
              (if self-loop-head
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
                (if self-loop-head
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
