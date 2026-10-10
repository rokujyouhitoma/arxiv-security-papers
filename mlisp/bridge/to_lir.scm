;;; =======================================================================
;;; MLisp Bridge: Trace to ULisp Low-Level IR (to_lir.scm)
;;; Conforms to DSN-34 Architecture Specification & Issue #507
;;;
;;; 100% Pure Scheme Implementation:
;;; Transforms optimized MLisp S-expression traces into canonical
;;; ULisp %lir-program structures (Pass 6 specification).
;;; The resulting LIR can be directly emitted to native assembly or C
;;; via ULisp's multi-backend code generators (Pass 7).
;;; =======================================================================

;;; Map symbolic variable names to LIR virtual registers or stack offsets
(define *reg-pool* '(%rax %rdx %rcx %r10))

(define (allocate-lir-registers vars)
  (let loop ((vs vars)
             (pool *reg-pool*)
             (stack-offset -16)
             (vmap '()))
    (if (null? vs)
        vmap
        (let ((v (car vs)))
          (if (not (null? pool))
              (loop (cdr vs) (cdr pool) stack-offset
                    (cons (cons v (car pool)) vmap))
              (loop (cdr vs) pool (- stack-offset 8)
                    (cons (cons v (list '%stack stack-offset)) vmap)))))))

;;; Resolve an operand to its allocated LIR register/stack slot, or immediate
(define (lir-opnd vmap x)
  (cond
    ((number? x) x)
    ((boolean? x) (if x 111 47))
    ((symbol? x)
     (let ((entry (assq x vmap)))
       (if entry (cdr entry) '%rax)))
    (else x)))

;;; Generate unique labels for trace control flow
(define *trace-label-counter* 0)

(define (gen-trace-label prefix)
  (set! *trace-label-counter* (+ *trace-label-counter* 1))
  (let ((p-str (if (symbol? prefix) (symbol->string prefix) (number->string prefix))))
    (string->symbol (string-append "jit_" p-str "_"
                                   (number->string *trace-label-counter*)))))

;;; Translate a single trace instruction into LIR instruction(s)
(define (trace-inst->lir inst vmap loop-entry-lbl loop-jump-lbl)
  (let ((op (car inst)))
    (case op
      ;; Loop entry marker -> %label
      ((%trace-loop-entry)
       (list (list '%label loop-entry-lbl)))

      ;; Loop jump marker -> %jump back to loop entry
      ((%trace-loop-jump)
       (list (list '%jump loop-entry-lbl)))

      ;; Assignment / Move
      ((%mov)
       (let* ((dst (lir-opnd vmap (cadr inst)))
              (src (lir-opnd vmap (caddr inst))))
         (list (list '%mov dst src))))

      ;; Binary arithmetic (%add dst arg1 arg2)
      ((%add)
       (let* ((dst (lir-opnd vmap (cadr inst)))
              (arg1 (lir-opnd vmap (caddr inst)))
              (arg2 (lir-opnd vmap (cadddr inst))))
         (if (equal? dst arg1)
             ;; In-place: dst += arg2
             (list (list '%add dst arg2))
             ;; Two-step: dst = arg1; dst += arg2
             (list (list '%mov dst arg1)
                   (list '%add dst arg2)))))

      ;; Binary subtraction (%sub dst arg1 arg2)
      ((%sub)
       (let* ((dst (lir-opnd vmap (cadr inst)))
              (arg1 (lir-opnd vmap (caddr inst)))
              (arg2 (lir-opnd vmap (cadddr inst))))
         (if (equal? dst arg1)
             (list (list '%sub dst arg2))
             (list (list '%mov dst arg1)
                   (list '%sub dst arg2)))))

      ;; Binary multiplication (%mul dst arg1 arg2)
      ((%mul)
       (let* ((dst (lir-opnd vmap (cadr inst)))
              (arg1 (lir-opnd vmap (caddr inst)))
              (arg2 (lir-opnd vmap (cadddr inst))))
         (if (equal? dst arg1)
             (list (list '%imul dst arg2))
             (list (list '%mov dst arg1)
                   (list '%imul dst arg2)))))

      ;; Speculative Guard (%guard cond-type arg1 arg2 fail-lbl)
      ((%guard)
       (let* ((cond-type (cadr inst))
              (arg1 (lir-opnd vmap (caddr inst)))
              (arg2 (lir-opnd vmap (cadddr inst)))
              (fail-lbl (car (cddddr inst)))
              (ok-lbl (gen-trace-label 'guard_ok)))
         (case cond-type
           ;; Type fixnum check: test if lowest 2 bits are zero
           ((type-fixnum fixnum-check)
            (list (list '%mov '%rdx arg1)
                  (list '%bit-and '%rdx 3)
                  (list '%cmp '%rdx 0)
                  (list '%jump-if-zero ok-lbl)
                  (list '%jump fail-lbl)
                  (list '%label ok-lbl)))

           ;; Comparison guards
           ((cmp-lt <)
            (list (list '%cmp arg1 arg2)
                  ;; if arg1 < arg2, continue to ok-lbl, else bail out
                  (list '%set-boolean '%rax "setl")
                  (list '%cmp '%rax 111)   ; 111 is #t
                  (list '%jump-if-zero ok-lbl)
                  (list '%jump fail-lbl)
                  (list '%label ok-lbl)))

           ((cmp-ge >=)
            (list (list '%cmp arg1 arg2)
                  (list '%set-boolean '%rax "setge")
                  (list '%cmp '%rax 111)
                  (list '%jump-if-zero ok-lbl)
                  (list '%jump fail-lbl)
                  (list '%label ok-lbl)))

           (else
            (list (list '%cmp arg1 arg2)
                  (list '%jump-if-zero ok-lbl)
                  (list '%jump fail-lbl)
                  (list '%label ok-lbl))))))

      ;; Fallback: preserve
      (else
       (list inst)))))

;;; Collect all variable symbols referenced in a trace
(define (collect-trace-variables body)
  (let loop ((rest body)
             (acc '()))
    (if (null? rest)
        acc
        (let* ((inst (car rest))
               (args (cdr inst))
               (syms (filter (lambda (x)
                               (and (symbol? x)
                                    (not (memq x '(%guard cmp-lt cmp-ge %mov %add %sub %mul)))))
                             args)))
          (loop (cdr rest) (append syms acc))))))

;;; Translate complete MLisp trace S-expression to canonical ULisp %lir-program
(define (trace->lir-program trace)
  (if (not (and (pair? trace) (eq? (car trace) '%trace-loop)))
      (error "Invalid trace format for LIR bridge:" trace)
      (let* ((fields (cdr trace))
             (pc-entry (assq '%pc fields))
             (pc (if pc-entry (cadr pc-entry) 'loop_main))
             (body-entry (assq '%body fields))
             (body (if body-entry (cadr body-entry) '()))
             (vars (collect-trace-variables body))
             (vmap (allocate-lir-registers vars))
             (pc-str (if (symbol? pc) (symbol->string pc) (number->string pc)))
             (loop-entry-lbl (gen-trace-label (string->symbol (string-append "entry_" pc-str))))
             (loop-jump-lbl (gen-trace-label (string->symbol (string-append "jump_" pc-str))))
             ;; Translate all trace instructions into LIR stream
             (lir-insts
              (apply append
                     (map (lambda (inst)
                            (trace-inst->lir inst vmap loop-entry-lbl loop-jump-lbl))
                          body)))
             ;; Add entry initialization and exit return
             (full-body
              (append (list (list '%label (string->symbol (string-append "jit_func_" pc-str))))
                      lir-insts
                      (list '(%return)))))
        `(%lir-program
           (strings ())
           (%lir-functions ())
           (%lir-main
             (frame-size 32)
             (body ,full-body))))))
