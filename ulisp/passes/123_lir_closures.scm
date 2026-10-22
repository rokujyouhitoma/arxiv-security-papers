;;; =======================================================================
;;; ULisp Compiler Pass 123: LIR Closures & Stack Allocation Pass
;;; Conforms to DSN-33 Architecture Specification & Issue #583
;;; =======================================================================
;;; Lowers closure allocation (heap and stack) and stack pairs into LIR instructions.
;;; =======================================================================

(define (lir-compile-make-closure expr si env)
  (let* ((label-arg (cadr expr))
         (label-sym (if (and (pair? label-arg) (eq? (car label-arg) 'quote))
                        (cadr label-arg)
                        label-arg))
         (args (cddr expr))
         (num-args (length args))
         (closure-size (* (+ num-args 1) 8))
         (aligned-size (if (= (modulo closure-size 16) 0) closure-size (+ closure-size 8))))
    ;; 1. Evaluate arguments sequentially and place into temporary stack slots
    (let loop ((as args) (curr-si si))
      (if (not (null? as))
          (begin
            (track-lir-si! curr-si)
            (lir-compile-expr (car as) curr-si env #f)
            (emit-lir! (list '%store '%rsp curr-si '%rax))
            (loop (cdr as) (- curr-si 8)))))
    ;; 2. Allocate closure on heap (%alloc puts tagged pointer into %r10)
    (let ((lowest-si (- si (* num-args 8))))
      (emit-lir! (list '%alloc '%r10 (+ aligned-size 8) 9 lowest-si)))
    ;; 3. Write 8-byte prefix header to [%r10 - 9]
    (let* ((hdr-val (+ (+ (* aligned-size 65536) (* (+ num-args 1) 256)) 2))
           (hdr-fixnum (* hdr-val 4)))
      (emit-lir! (list '%mov '%rdx hdr-fixnum))
      (emit-lir! '(%store %r10 -9 %rdx)))
    ;; 4. Write code pointer to [%r10 - 1]
    (emit-lir! (list '%code-ref '%rax label-sym))
    (emit-lir! '(%store %r10 -1 %rax))
    ;; 5. Copy captured arguments from stack to heap [%r10 - 1 + 8 * i]
    (let loop ((i 1) (curr-si si))
      (if (<= i num-args)
          (begin
            (emit-lir! (list '%load '%rax '%rsp curr-si))
            (emit-lir! (list '%store '%r10 (+ -1 (* i 8)) '%rax))
            (loop (+ i 1) (- curr-si 8)))))
    (emit-lir! '(%mov %rax %r10))))

(define (stack-alloc-attr? attr)
  (or (eq? attr '#:stack-alloc)
      (eq? attr 'stack-alloc)
      (and (symbol? attr)
           (let ((s (symbol->string attr)))
             (or (string=? s ":stack-alloc")
                 (string=? s "#:stack-alloc"))))))

(define (stack-alloc-bytes val)
  (cond
    ((not (pair? val)) 0)
    ((eq? (car val) '%stack-cons) 24)
    ((and (eq? (car val) 'annotate)
          (pair? (cdr val))
          (stack-alloc-attr? (cadr val))
          (pair? (cddr val))
          (pair? (caddr val)))
     (let ((inner (caddr val)))
       (cond
         ((memq (car inner) '(%make-closure-env %make-closure))
          (let* ((num-args (length (cddr inner)))
                 (closure-size (* (+ num-args 1) 8))
                 (aligned-size (if (= (modulo closure-size 16) 0) closure-size (+ closure-size 8))))
            (+ aligned-size 8)))
         ((eq? (car inner) 'cons) 24)
         (else 0))))
    ((eq? (car val) '%make-stack-closure)
     (let* ((num-args (length (cddr val)))
            (closure-size (* (+ num-args 1) 8))
            (aligned-size (if (= (modulo closure-size 16) 0) closure-size (+ closure-size 8))))
       (+ aligned-size 8)))
    (else 0)))

(define (get-stack-vars env)
  (let ((entry (assq '%stack-vars env)))
    (if entry (cdr entry) '())))

(define (set-stack-vars svars env)
  (cons (cons '%stack-vars svars) env))

(define (lir-compile-stack-cons expr si env)
  (let* ((e1 (cadr expr))
         (e2 (caddr expr))
         (base-si (- si 24))
         (tmp1 (- base-si 8))
         (tmp2 (- base-si 16)))
    ;; 1. Evaluate arguments onto temporary stack slots below base-si
    (track-lir-si! tmp1)
    (lir-compile-expr e1 tmp1 env #f)
    (emit-lir! (list '%store '%rsp tmp1 '%rax))
    (track-lir-si! tmp2)
    (lir-compile-expr e2 tmp2 env #f)
    ;; 2. Allocate 24 bytes (header + car + cdr) directly on current stack frame
    (track-lir-si! base-si)
    (emit-lir! '(%mov %rdx 4196356))
    (emit-lir! (list '%store '%rsp base-si '%rdx))
    (emit-lir! (list '%load '%rdx '%rsp tmp1))
    (emit-lir! (list '%store '%rsp (+ base-si 8) '%rdx))
    (emit-lir! (list '%store '%rsp (+ base-si 16) '%rax))
    ;; 3. Return stack-allocated tagged pair pointer (offset +8 from base-si, tag 1)
    (emit-lir! (list '%alloc-stack '%rax (+ base-si 8) 1))))

(define (lir-compile-make-stack-closure expr si env)
  (let* ((label-arg (cadr expr))
         (label-sym (if (and (pair? label-arg) (eq? (car label-arg) 'quote))
                        (cadr label-arg)
                        label-arg))
         (args (cddr expr))
         (num-args (length args))
         (closure-size (* (+ num-args 1) 8))
         (aligned-size (if (= (modulo closure-size 16) 0) closure-size (+ closure-size 8)))
         (total-bytes (+ aligned-size 8))
         (base-si (- si total-bytes))
         (temp-base (- base-si 8)))
    ;; 1. Evaluate arguments sequentially and place into temporary stack slots below temp-base
    (let loop ((as args) (curr-si temp-base))
      (if (not (null? as))
          (begin
            (track-lir-si! curr-si)
            (lir-compile-expr (car as) curr-si env #f)
            (emit-lir! (list '%store '%rsp curr-si '%rax))
            (loop (cdr as) (- curr-si 8)))))
    ;; 2. Format header and store onto stack frame
    (track-lir-si! base-si)
    (let* ((hdr-val (+ (+ (* aligned-size 65536) (* (+ num-args 1) 256)) 2))
           (hdr-fixnum (* hdr-val 4)))
      (emit-lir! (list '%mov '%rdx hdr-fixnum))
      (emit-lir! (list '%store '%rsp base-si '%rdx)))
    (emit-lir! (list '%code-ref '%rax label-sym))
    (emit-lir! (list '%store '%rsp (+ base-si 8) '%rax))
    ;; 3. Copy captured arguments from temporary slots to stack closure slots
    (let loop ((i 1) (curr-si temp-base))
      (if (<= i num-args)
          (begin
            (emit-lir! (list '%load '%rax '%rsp curr-si))
            (emit-lir! (list '%store '%rsp (+ (+ base-si 8) (* i 8)) '%rax))
            (loop (+ i 1) (- curr-si 8)))))
    ;; 4. Tag closure pointer with 0x01 (offset +8 from header)
    (emit-lir! (list '%alloc-stack '%rax (+ base-si 8) 1))))
