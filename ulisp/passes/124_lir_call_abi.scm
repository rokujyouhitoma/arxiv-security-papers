;;; =======================================================================
;;; ULisp Compiler Pass 124: LIR Procedure Invocations & Call ABI Pass
;;; Conforms to DSN-33 Architecture Specification & Issue #583
;;; =======================================================================
;;; Lowers general closure calls and direct static-label calls into LIR instructions,
;;; handling argument stack evaluation, frame shift alignment, Tail Call Optimization (TCO),
;;; and exact GC safepoint registration.
;;; =======================================================================

(define (lir-compile-call proc args si env tail?)
  (let* ((num-args (length args))
         (cur-params-entry (assq '%num-params env))
         (cur-num-params (if cur-params-entry (cdr cur-params-entry) #f))
         (can-tco? (and tail? (if cur-num-params (= cur-num-params num-args) #f)))
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
                  (let ((temp-offset (- aligned-si (* i 8)))
                        (param-offset (* 8 (- num-args i))))
                    (emit-lir! (list '%load '%rdx '%rsp temp-offset))
                    (emit-lir! (list '%store '%rsp param-offset '%rdx))
                    (loop (+ i 1)))))
            (emit-lir! '(%load %rdx %r10 -1))
            (emit-lir! (list '%mov '%rax (* num-args 4)))
            (emit-lir! '(%jump %rdx)))

          ;; --- NON-TAIL CALL ---
          (let* ((bitmap (compute-stackmap-bitmap frame-shift aligned-si args env))
                 (safepoint-lbl (new-safepoint-label!)))
            (record-safepoint! safepoint-lbl frame-shift bitmap)
            (emit-lir! (list '%mov '%rax (* num-args 4)))
            (emit-lir! (list '%call-closure frame-shift safepoint-lbl)))))))

(define (lir-compile-direct-call label args si env tail?)
  (let* ((num-args (length args))
         (cur-params-entry (assq '%num-params env))
         (cur-num-params (if cur-params-entry (cdr cur-params-entry) #f))
         (can-tco? (and tail? (if cur-num-params (= cur-num-params num-args) #f)))
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

    (if can-tco?
        ;; --- TAIL CALL OPTIMIZATION (TCO) via Direct Jump ---
        (begin
          (let loop ((i 0))
            (if (< i num-args)
                (let ((temp-offset (- aligned-si (* i 8)))
                      (param-offset (* 8 (- num-args i))))
                  (emit-lir! (list '%load '%rdx '%rsp temp-offset))
                  (emit-lir! (list '%store '%rsp param-offset '%rdx))
                  (loop (+ i 1)))))
          (emit-lir! (list '%mov '%rax (* num-args 4)))
          (emit-lir! (list '%direct-jump label)))

        ;; --- NON-TAIL DIRECT CALL ---
        (let* ((bitmap (compute-stackmap-bitmap frame-shift aligned-si args env))
               (safepoint-lbl (new-safepoint-label!)))
          (record-safepoint! safepoint-lbl frame-shift bitmap)
          (emit-lir! (list '%mov '%rax (* num-args 4)))
          (emit-lir! (list '%direct-call label frame-shift safepoint-lbl))))))
