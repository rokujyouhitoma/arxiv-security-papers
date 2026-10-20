;;; =======================================================================
;;; ULisp Compiler Pass 127: LIR Runtime & Advanced Features Pass
;;; Conforms to DSN-33 Architecture Specification & Issue #583
;;; =======================================================================
;;; Lowers runtime advanced operations into LIR instructions:
;;; - Structured exception handling (%with-handler, %push-handler, %pop-handler)
;;; - Multiple values production (%values, %set-values-count, %store-values-buf)
;;; - Multiple values consumption (%call-with-values, %dispatch-consumer)
;;; - First-class continuations (%raw-call/cc, %capture-cc)
;;; =======================================================================

(define (lir-compile-with-handler handler-expr thunk-expr si env tail?)
  (let* ((exit-lbl (unique-label-sym "L_handler_exit_"))
         (catch-lbl (unique-label-sym "L_handler_catch_"))
         (handler-si si)
         (thunk-si (- si 8))
         (frame-si (- si 48))
         (call-si (- frame-si 8)))
    (track-lir-si! handler-si)
    (track-lir-si! thunk-si)
    (track-lir-si! frame-si)
    (track-lir-si! call-si)
    ;; 1. Evaluate handler closure and store at handler-si
    (lir-compile-expr handler-expr handler-si env #f)
    (emit-lir! (list '%store '%rsp handler-si '%rax))
    ;; 2. Evaluate thunk closure and store at thunk-si
    (lir-compile-expr thunk-expr thunk-si env #f)
    (emit-lir! (list '%store '%rsp thunk-si '%rax))
    ;; 3. Push handler frame: %push-handler catch-lbl frame-si handler-si
    (emit-lir! (list '%push-handler catch-lbl frame-si handler-si))
    ;; 4. Call thunk closure with 0 arguments
    (emit-lir! (list '%load '%rax '%rsp thunk-si))
    (emit-lir! '(%mov %r10 %rax))
    (let* ((frame-shift (align-frame-shift (- 0 call-si)))
           (safepoint-lbl (new-safepoint-label!))
           (bitmap (compute-stackmap-bitmap frame-shift call-si '() env)))
      (record-safepoint! safepoint-lbl frame-shift bitmap)
      (emit-lir! (list '%mov '%rax 0))
      (emit-lir! (list '%call-closure frame-shift safepoint-lbl)))
    ;; 5. Normal return from thunk: Pop handler frame and jump to exit
    (emit-lir! (list '%pop-handler frame-si))
    (emit-lir! (list '%jump exit-lbl))
    ;; 6. Exception catch entry: control arrives here on %raise
    (emit-lir! (list '%label catch-lbl))
    (let* ((frame-shift (align-frame-shift (- 0 call-si)))
           (aligned-si (- 0 frame-shift)))
      (track-lir-si! aligned-si)
      (emit-lir! (list '%store '%rsp aligned-si '%rdi))
      (emit-lir! '(%mov %r10 %rax))
      (let* ((safepoint-lbl (new-safepoint-label!))
             (bitmap (compute-stackmap-bitmap frame-shift aligned-si (list '%rdi) env)))
        (record-safepoint! safepoint-lbl frame-shift bitmap)
        (emit-lir! (list '%mov '%rax 4))
        (emit-lir! (list '%call-closure frame-shift safepoint-lbl))))
    ;; 7. Exit label
    (emit-lir! (list '%label exit-lbl))))

(define (lir-compile-values args si env)
  (let ((count (length args)))
    (cond
      ((= count 0)
       (emit-lir! (list '%set-values-count 0))
       (emit-lir! '(%mov %rax 63)))
      ((= count 1)
       (lir-compile-expr (car args) si env #f)
       (emit-lir! (list '%set-values-count 1)))
      (else
       ;; Evaluate each argument and save on stack
       (let loop ((as args) (curr-si si))
         (if (not (null? as))
             (begin
               (track-lir-si! curr-si)
               (lir-compile-expr (car as) curr-si env #f)
               (emit-lir! (list '%store '%rsp curr-si '%rax))
               (loop (cdr as) (- curr-si 8)))))
       (emit-lir! (list '%store-values-buf si count))
       (emit-lir! (list '%set-values-count count))
       ;; Load first argument to RAX
       (emit-lir! (list '%load '%rax '%rsp si))
       ;; Load second argument to RDX
       (emit-lir! (list '%load '%rdx '%rsp (- si 8)))))))

(define (lir-compile-call-with-values producer-expr consumer-expr si env tail?)
  (let* ((consumer-si si)
         (producer-si (- si 8))
         (call-si (- producer-si 8)))
    (track-lir-si! consumer-si)
    (track-lir-si! producer-si)
    (track-lir-si! call-si)
    ;; 1. Evaluate consumer closure and store at consumer-si
    (lir-compile-expr consumer-expr consumer-si env #f)
    (emit-lir! (list '%store '%rsp consumer-si '%rax))
    ;; 2. Evaluate producer closure and store at producer-si
    (lir-compile-expr producer-expr producer-si env #f)
    (emit-lir! (list '%store '%rsp producer-si '%rax))
    ;; 3. Call producer with 0 arguments (initialize default count to 1)
    (emit-lir! (list '%set-values-count 1))
    (emit-lir! (list '%load '%rax '%rsp producer-si))
    (emit-lir! '(%mov %r10 %rax))
    (let* ((frame-shift (align-frame-shift (- 0 call-si)))
           (safepoint-lbl (new-safepoint-label!))
           (bitmap (compute-stackmap-bitmap frame-shift call-si '() env)))
      (record-safepoint! safepoint-lbl frame-shift bitmap)
      (emit-lir! (list '%mov '%rax 0))
      (emit-lir! (list '%call-closure frame-shift safepoint-lbl)))
    ;; 4. Dispatch to consumer based on ulisp_values_count
    (let* ((frame-shift (align-frame-shift (- 0 call-si)))
           (aligned-si (- 0 frame-shift)))
      (track-lir-si! aligned-si)
      (track-lir-si! (- aligned-si 32))
      (emit-lir! (list '%dispatch-consumer consumer-si aligned-si frame-shift)))))

(define (lir-compile-raw-call-cc proc-expr si env tail?)
  (let* ((proc-si si)
         (k-si (- si 8))
         (call-si (- k-si 8))
         (ret-lbl (unique-label-sym "L_callcc_ret_")))
    (track-lir-si! proc-si)
    (track-lir-si! k-si)
    (track-lir-si! call-si)
    ;; 1. Evaluate proc-expr and store at proc-si
    (lir-compile-expr proc-expr proc-si env #f)
    (emit-lir! (list '%store '%rsp proc-si '%rax))
    ;; 2. Capture continuation: creates continuation object in %rax and stores to k-si
    (emit-lir! (list '%capture-cc ret-lbl k-si))
    ;; 3. Call proc with 1 argument (k)
    (emit-lir! (list '%load '%rax '%rsp k-si))
    (emit-lir! (list '%load '%r10 '%rsp proc-si))
    (let* ((frame-shift (align-frame-shift (- 0 call-si)))
           (aligned-si (- 0 frame-shift)))
      (track-lir-si! aligned-si)
      (emit-lir! (list '%store '%rsp aligned-si '%rax))
      (let* ((safepoint-lbl (new-safepoint-label!))
             (bitmap (compute-stackmap-bitmap frame-shift call-si '() env)))
        (record-safepoint! safepoint-lbl frame-shift bitmap)
        (emit-lir! (list '%mov '%rax 4))
        (emit-lir! (list '%call-closure frame-shift safepoint-lbl))))
    ;; 4. Return label: both normal return and (k val) jump here!
    (emit-lir! (list '%block ret-lbl '()))))
