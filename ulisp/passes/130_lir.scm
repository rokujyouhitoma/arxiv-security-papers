;;; =======================================================================
;;; ULisp Compiler Pass 130: Low-Level Intermediate Representation (LIR)
;;; =======================================================================


;;; Boxed accumulators for LIR instructions and stack tracking
(define *lir-instructions* (cons '() '()))
(define *lir-min-si* (cons 0 '()))
(define (get-raw-vars env)
  (let ((entry (assq '%raw-vars env)))
    (if entry (cdr entry) '())))

(define (set-raw-vars rvars env)
  (cons (cons '%raw-vars rvars) env))

(define (raw-expr? expr raw-env)
  (cond
    ((not (pair? expr))
     (and (symbol? expr) (memq expr raw-env)))
    ((memq (car expr) '(%raw-add %raw-sub %raw-mul %raw-cmp %raw-load %raw-syscall %to-raw %unbox-fixnum))
     #t)
    (else #f)))

(define (reset-lir!)
  (set-car! *lir-instructions* '())
  (set-car! *lir-min-si* 0))

(define (emit-lir! inst)
  (set-car! *lir-instructions* (cons inst (car *lir-instructions*))))

(define (track-lir-si! si)
  (if (< si (car *lir-min-si*))
      (set-car! *lir-min-si* si)))

(define (immediate? expr)
  (or (integer? expr)
      (boolean? expr)
      (char? expr)
      (null? expr)
      (string? expr)))

(define (lir-immediate expr)
  (cond
    ((integer? expr)
     (* expr 4))
    ((boolean? expr)
     (if expr 111 47))   ; 0x6F: #t, 0x2F: #f
    ((char? expr)
     (+ (* (char->integer expr) 256) 14))
    ((null? expr)
     63)                 ; 0x3F: '()
    ((string? expr)
     (let ((label (intern-string expr)))
       (list '%string-ref label)))))

(define (lir-compile-variable var env)
  (let ((binding (assq var env)))
    (if (not binding)
        (error (string-append "Unbound variable in LIR: " (symbol->string var)) var)
        (let ((info (cdr binding)))
          (cond
            ((number? info)
             (emit-lir! (list '%load '%rax '%rsp info)))
            ((and (pair? info) (eq? (car info) 'reg))
             (let ((reg (cdr info)))
               (if (not (eq? reg '%rax))
                   (emit-lir! (list '%mov '%rax reg)))))
            ((and (symbol? info) (memq info '(%rax %rbx %rcx %rdx %rsi %rdi %rbp %rsp %r8 %r9 %r10 %r11 %r12 %r13 %r14 %r15)))
             (if (not (eq? info '%rax))
                 (emit-lir! (list '%mov '%rax info))))
            ((and (pair? info) (eq? (car info) 'param))
             (emit-lir! (list '%load '%rax '%rsp (cdr info))))
            ((and (pair? info) (eq? (car info) 'self))
             (emit-lir! (list '%load '%rax '%rsp (cdr info))))
            (else
             (error "Invalid binding format in LIR:" binding)))))))

;;; Primitive instruction selection (zero-arg, unary, binary, ternary, raw-syscall)
;;; has been factored into passes/129_lir_primitives.scm.

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
    (let* ((hdr-val (+ (* aligned-size 65536) (* (+ num-args 1) 256) 2))
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

(define (lir-compile-stack-cons expr si env)
  (let ((e1 (cadr expr))
        (e2 (caddr expr))
        (base-si (- si 24)))
    ;; 1. Evaluate arguments onto temporary stack slots
    (track-lir-si! si)
    (lir-compile-expr e1 si env #f)
    (emit-lir! (list '%store '%rsp si '%rax))
    (track-lir-si! (- si 8))
    (lir-compile-expr e2 (- si 8) env #f)
    ;; 2. Allocate 24 bytes (header + car + cdr) directly on current stack frame
    (track-lir-si! base-si)
    (emit-lir! '(%mov %rdx 4196356))
    (emit-lir! (list '%store '%rsp base-si '%rdx))
    (emit-lir! (list '%load '%rdx '%rsp si))
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
         (base-si (- si total-bytes)))
    ;; 1. Evaluate arguments sequentially and place into temporary stack slots
    (let loop ((as args) (curr-si si))
      (if (not (null? as))
          (begin
            (track-lir-si! curr-si)
            (lir-compile-expr (car as) curr-si env #f)
            (emit-lir! (list '%store '%rsp curr-si '%rax))
            (loop (cdr as) (- curr-si 8)))))
    ;; 2. Format header and store onto stack frame
    (track-lir-si! base-si)
    (let* ((hdr-val (+ (* aligned-size 65536) (* (+ num-args 1) 256) 2))
           (hdr-fixnum (* hdr-val 4)))
      (emit-lir! (list '%mov '%rdx hdr-fixnum))
      (emit-lir! (list '%store '%rsp base-si '%rdx)))
    (emit-lir! (list '%code-ref '%rax label-sym))
    (emit-lir! (list '%store '%rsp (+ base-si 8) '%rax))
    ;; 3. Copy captured arguments from temporary slots to stack closure slots
    (let loop ((i 1) (curr-si si))
      (if (<= i num-args)
          (begin
            (emit-lir! (list '%load '%rax '%rsp curr-si))
            (emit-lir! (list '%store '%rsp (+ base-si 8 (* i 8)) '%rax))
            (loop (+ i 1) (- curr-si 8)))))
    ;; 4. Tag closure pointer with 0x01 (offset +8 from header)
    (emit-lir! (list '%alloc-stack '%rax (+ base-si 8) 1))))

(define (expr-references-var? expr var)
  (cond
    ((eq? expr var) #t)
    ((pair? expr)
     (or (expr-references-var? (car expr) var)
         (expr-references-var? (cdr expr) var)))
    (else #f)))

(define (expr-free-references-var? expr var)
  (cond
    ((eq? expr var) #t)
    ((not (pair? expr)) #f)
    (else
     (let ((op (car expr)))
       (case op
         ((quote) #f)
         ((let letrec)
          (let* ((bindings (cadr expr))
                 (body (caddr expr))
                 (shadowed? (assq var bindings)))
            (or (let loop ((bs bindings))
                  (and (pair? bs)
                       (or (expr-free-references-var? (cadar bs) var)
                           (loop (cdr bs)))))
                (if shadowed?
                    #f
                    (expr-free-references-var? body var)))))
         ((lambda)
          (let ((params (cadr expr))
                (body (caddr expr)))
            (if (memq var params)
                #f
                (expr-free-references-var? body var))))
         ((%cont-fun)
          (let ((f-name (cadr expr))
                (params (caddr expr))
                (f-body (cadddr expr))
                (in-body (cadr (cdddr expr))))
            (or (if (memq var params) #f (expr-free-references-var? f-body var))
                (expr-free-references-var? in-body var))))
         (else
          (or (expr-free-references-var? (car expr) var)
              (expr-free-references-var? (cdr expr) var))))))))

(define (extract-in-place-const op e)
  (let* ((raw-c (if (integer? (cadr e)) (cadr e) (caddr e)))
         (is-raw? (memq op '(%raw-add %raw-sub))))
    (if is-raw? raw-c (* raw-c 4))))

(define (cont-target-all-regs? target-info)
  (let* ((p-bindings (caddr target-info))
         (num-args (length p-bindings)))
    (and (> num-args 0)
         (let check-regs ((pbs p-bindings))
           (if (null? pbs) #t
               (let ((info (cdar pbs)))
                 (and (or (and (pair? info) (eq? (car info) 'reg))
                          (memq info '(%rbx %r13 %r14 %r15)))
                      (check-regs (cdr pbs)))))))))

(define (emit-in-place-jump! entry-lbl regs)
  (if entry-lbl
      (emit-lir! (list '%jump entry-lbl regs))))

(define (lir-compile-in-place-cont-call f-name exprs target-info si env)
  (let* ((entry-lbl (cadr target-info))
         (p-bindings (caddr target-info))
         (num-args (length exprs))
         (p-names (map car* p-bindings))
         (p-regs (map (lambda (pb)
                        (let ((info (cdr pb)))
                          (if (pair? info) (cdr info) info)))
                      p-bindings)))
    (cond
      ;; === 2-Argument Hot Loop In-Place Shuffle ===
      ((= num-args 2)
       (let* ((p0 (car p-names))
              (p1 (cadr p-names))
              (r0 (car p-regs))
              (r1 (cadr p-regs))
              (e0 (car exprs))
              (e1 (cadr exprs))
              ;; Check if e0 references p1
              (e0-refs-p1? (expr-references-var? e0 p1))
              ;; Check if e1 references p0
              (e1-refs-p0? (expr-references-var? e1 p0)))
         (cond
           ;; Case 1: Swap (loop p1 p0)
           ((and (eq? e0 p1) (eq? e1 p0))
            (emit-lir! (list '%mov '%r10 r0))
            (emit-lir! (list '%mov r0 r1))
            (emit-lir! (list '%mov r1 '%r10))
            (emit-in-place-jump! entry-lbl (list r0 r1)))

           ;; Case 1b: Identity on one variable
           ((and (eq? e1 p1) (not e0-refs-p1?))
            (cond
              ((and (pair? e0)
                    (memq (car e0) '(+ %raw-add))
                    (or (and (eq? (cadr e0) p0) (integer? (caddr e0)))
                        (and (integer? (cadr e0)) (eq? (caddr e0) p0))))
               (let ((c (extract-in-place-const (car e0) e0)))
                 (emit-lir! (list '%add r0 c))))
              ((and (pair? e0)
                    (memq (car e0) '(- %raw-sub))
                    (eq? (cadr e0) p0)
                    (integer? (caddr e0)))
               (let ((c (extract-in-place-const (car e0) e0)))
                 (emit-lir! (list '%sub r0 c))))
              (else
               (lir-compile-expr e0 si env #f)
               (if (not (eq? r0 '%rax))
                   (emit-lir! (list '%mov r0 '%rax)))))
            (emit-in-place-jump! entry-lbl (list r0 r1)))

           ((and (eq? e0 p0) (not e1-refs-p0?))
            (cond
              ((and (pair? e1)
                    (memq (car e1) '(+ %raw-add))
                    (or (and (eq? (cadr e1) p1) (integer? (caddr e1)))
                        (and (integer? (cadr e1)) (eq? (caddr e1) p1))))
               (let ((c (extract-in-place-const (car e1) e1)))
                 (emit-lir! (list '%add r1 c))))
              ((and (pair? e1)
                    (memq (car e1) '(- %raw-sub))
                    (eq? (cadr e1) p1)
                    (integer? (caddr e1)))
               (let ((c (extract-in-place-const (car e1) e1)))
                 (emit-lir! (list '%sub r1 c))))
              (else
               (lir-compile-expr e1 si env #f)
               (if (not (eq? r1 '%rax))
                   (emit-lir! (list '%mov r1 '%rax)))))
            (emit-in-place-jump! entry-lbl (list r0 r1)))

           ;; Case 2: DAG dependency (e1 depends on p0, e0 does NOT depend on p1)
           ;; e.g. e0 = (+ i 1), e1 = (+ acc i). Evaluate e1 into r1 first, then e0 into r0!
           ((and e1-refs-p0? (not e0-refs-p1?))
            ;; Fast path: e1 is (%raw-add i acc) or (+ acc i) -> direct in-place add!
            (cond
              ((and (pair? e1)
                    (memq (car e1) '(+ %raw-add))
                    (or (and (eq? (cadr e1) p0) (eq? (caddr e1) p1))
                        (and (eq? (cadr e1) p1) (eq? (caddr e1) p0))))
               (emit-lir! (list '%add r1 r0)))
              ((and (pair? e1)
                    (memq (car e1) '(- %raw-sub))
                    (eq? (cadr e1) p1)
                    (eq? (caddr e1) p0))
               (emit-lir! (list '%sub r1 r0)))
              (else
               (lir-compile-expr e1 si env #f)
               (if (not (eq? r1 '%rax))
                   (emit-lir! (list '%mov r1 '%rax)))))
            ;; Now evaluate e0 into r0 in-place!
            (cond
              ((and (pair? e0)
                    (memq (car e0) '(+ %raw-add))
                    (or (and (eq? (cadr e0) p0) (integer? (caddr e0)))
                        (and (integer? (cadr e0)) (eq? (caddr e0) p0))))
               (let ((c (extract-in-place-const (car e0) e0)))
                 (emit-lir! (list '%add r0 c))))
              ((and (pair? e0)
                    (memq (car e0) '(- %raw-sub))
                    (eq? (cadr e0) p0)
                    (integer? (caddr e0)))
               (let ((c (extract-in-place-const (car e0) e0)))
                 (emit-lir! (list '%sub r0 c))))
              (else
               (lir-compile-expr e0 si env #f)
               (if (not (eq? r0 '%rax))
                   (emit-lir! (list '%mov r0 '%rax)))))
            (emit-in-place-jump! entry-lbl (list r0 r1)))

           ;; Case 3: DAG dependency (e0 depends on p1, e1 does NOT depend on p0)
           ;; Evaluate e0 into r0 first, then e1 into r1!
           ((and e0-refs-p1? (not e1-refs-p0?))
            (cond
              ((and (pair? e0)
                    (memq (car e0) '(+ %raw-add))
                    (or (and (eq? (cadr e0) p0) (eq? (caddr e0) p1))
                        (and (eq? (cadr e0) p1) (eq? (caddr e0) p0))))
               (emit-lir! (list '%add r0 r1)))
              (else
               (lir-compile-expr e0 si env #f)
               (if (not (eq? r0 '%rax))
                   (emit-lir! (list '%mov r0 '%rax)))))
            ;; Now evaluate e1 into r1 in-place!
            (cond
              ((and (pair? e1)
                    (memq (car e1) '(+ %raw-add))
                    (or (and (eq? (cadr e1) p1) (integer? (caddr e1)))
                        (and (integer? (cadr e1)) (eq? (caddr e1) p1))))
               (let ((c (extract-in-place-const (car e1) e1)))
                 (emit-lir! (list '%add r1 c))))
              ((and (pair? e1)
                    (memq (car e1) '(- %raw-sub))
                    (eq? (cadr e1) p1)
                    (integer? (caddr e1)))
               (let ((c (extract-in-place-const (car e1) e1)))
                 (emit-lir! (list '%sub r1 c))))
              (else
               (lir-compile-expr e1 si env #f)
               (if (not (eq? r1 '%rax))
                   (emit-lir! (list '%mov r1 '%rax)))))
            (emit-in-place-jump! entry-lbl (list r0 r1)))

           ;; Case 4: General 2-argument parallel update: preserve e0 on stack slot si across e1 evaluation
           (else
            (track-lir-si! si)
            (lir-compile-expr e0 si env #f)
            (emit-lir! (list '%store '%rsp si '%rax))
            (lir-compile-expr e1 (- si 8) env #f)
            (if (not (eq? r1 '%rax))
                (emit-lir! (list '%mov r1 '%rax)))
            (emit-lir! (list '%load r0 '%rsp si))
            (emit-in-place-jump! entry-lbl (list r0 r1))))))

      ;; === 1-Argument In-Place Update ===
      ((= num-args 1)
       (let ((r0 (car p-regs))
             (p0 (car p-names))
             (e0 (car exprs)))
         (cond
           ((and (pair? e0)
                 (memq (car e0) '(+ %raw-add))
                 (or (and (eq? (cadr e0) p0) (integer? (caddr e0)))
                     (and (integer? (cadr e0)) (eq? (caddr e0) p0))))
            (let ((c (extract-in-place-const (car e0) e0)))
              (emit-lir! (list '%add r0 c))))
           ((and (pair? e0)
                 (memq (car e0) '(- %raw-sub))
                 (eq? (cadr e0) p0)
                 (integer? (caddr e0)))
            (let ((c (extract-in-place-const (car e0) e0)))
              (emit-lir! (list '%sub r0 c))))
           (else
            (lir-compile-expr e0 si env #f)
            (if (not (eq? r0 '%rax))
                (emit-lir! (list '%mov r0 '%rax)))))
         (emit-in-place-jump! entry-lbl (list r0))))

      ;; === Fallback for >= 3 arguments using stack-free %cont-call ===
      (else
       (let loop ((es exprs) (curr-si si) (temp-sis '()))
         (if (pair? es)
             (begin
               (track-lir-si! curr-si)
               (lir-compile-expr (car es) curr-si env #f)
               (emit-lir! (list '%store '%rsp curr-si '%rax))
               (loop (cdr es) (- curr-si 8) (cons curr-si temp-sis)))
             (begin
               (let xfer ((ts (reverse temp-sis)) (pbs p-bindings))
                 (if (and (pair? ts) (pair? pbs))
                     (let ((t-si (car ts))
                           (p-info (cdar pbs)))
                       (cond
                         ((and (pair? p-info) (eq? (car p-info) 'reg))
                          (emit-lir! (list '%load (cdr p-info) '%rsp t-si)))
                         ((memq p-info '(%rax %rbx %rcx %rdx %rsi %rdi %rbp %rsp %r8 %r9 %r10 %r11 %r12 %r13 %r14 %r15))
                          (emit-lir! (list '%load p-info '%rsp t-si)))
                         (else
                          (emit-lir! (list '%load '%rdx '%rsp t-si))
                          (emit-lir! (list '%store '%rsp p-info '%rdx))))
                       (xfer (cdr ts) (cdr pbs)))))
               (emit-in-place-jump! entry-lbl
                                (map (lambda (pb)
                                       (let ((p-info (cdr pb)))
                                         (cond
                                           ((and (pair? p-info) (eq? (car p-info) 'reg))
                                            (cdr p-info))
                                           ((memq p-info '(%rax %rbx %rcx %rdx %rsi %rdi %rbp %rsp %r8 %r9 %r10 %r11 %r12 %r13 %r14 %r15))
                                            p-info)
                                           (else
                                            (list '%stack p-info)))))
                                     p-bindings)))))))))

(define (lir-compile-let bindings body si env tail?)
  (cond
    ;; In-place Tail Loop Argument Shuffle: (let ((t0 e0) (t1 e1) ...) (%cont-call loop t0 t1 ...))
    ((and (pair? body)
          (eq? (car body) '%cont-call)
          (let* ((f-name (cadr body))
                 (call-args (cddr body))
                 (binding-vars (map car* bindings))
                 (b-entry (assq f-name env)))
            (and (equal? call-args binding-vars)
                 b-entry
                 (pair? (cdr b-entry))
                 (eq? (cadr b-entry) '%cont-target)
                 (cont-target-all-regs? (cdr b-entry)))))
     (let* ((f-name (cadr body))
            (target-info (cdr (assq f-name env)))
            (exprs (map cadr bindings)))
       (lir-compile-in-place-cont-call f-name exprs target-info si env)))

    ;; Flag / Branch Fusion on ANF: (let ((var (cmp-or-pred-expr ...))) (if var then-e else-e))
    ((and (= (length bindings) 1)
          (let* ((b (car bindings))
                 (var (car b))
                 (val (cadr b)))
            (and (pair? val)
                 (memq (car val) '(= < <= > >= eq? null? zero? pair? not))
                 (pair? body)
                 (eq? (car body) 'if)
                 (eq? (cadr body) var)
                 (not (expr-free-references-var? (caddr body) var))
                 (not (expr-free-references-var? (cdddr body) var)))))
     (let* ((b (car bindings))
            (val (cadr b))
            (then-e (caddr body))
            (else-opt (cdddr body)))
       (lir-compile-if val then-e else-opt si env tail?)))

    ;; Path Splitting on join nodes: (let ((var (if cond then-e else-e))) body)
    ((and (= (length bindings) 1)
          (let* ((b (car bindings))
                 (val (cadr b)))
            (and (pair? val)
                 (eq? (car val) 'if)
                 (<= (expr-size body) 40)
                 (let ((var (car b)))
                   (expr-has-conditional-or-pred-on-var? body var)))))
     (let* ((b (car bindings))
            (var (car b))
            (if-expr (cadr b))
            (cond-part (cadr if-expr))
            (then-e (caddr if-expr))
            (else-e (if (null? (cdddr if-expr)) #f (cadddr if-expr))))
       (lir-compile-if cond-part
                       (list 'let (list (list var then-e)) body)
                       (list (list 'let (list (list var else-e)) body))
                       si env tail?)))
    (else
     (let loop ((bs bindings)
                (curr-si si)
                (new-env env))
       (if (null? bs)
           (lir-compile-expr body curr-si new-env tail?)
           (let* ((b (car bs))
                  (var (car b))
                  (val (cadr b))
                  (rvars (get-raw-vars new-env))
                  (is-raw (raw-expr? val rvars))
                  (next-rvars (if is-raw (cons var rvars) rvars)))
             (track-lir-si! curr-si)
             (lir-compile-expr val curr-si env #f)
             (emit-lir! (list '%store '%rsp curr-si '%rax))
             (loop (cdr bs)
                   (- curr-si 8)
                   (cons (cons var curr-si) (set-raw-vars next-rvars new-env)))))))))

(define (cont-recurse-tail? f-name expr)
  (cond
    ((not (pair? expr)) #f)
    ((eq? (car expr) '%cont-call)
     (eq? (cadr expr) f-name))
    ((eq? (car expr) 'let)
     (cont-recurse-tail? f-name (caddr expr)))
    (else #f)))

(define (cont-loop-rotation-candidate? f-name f-body)
  (cond
     ;; Pattern A: (let ((var (cmp-op lhs rhs))) (if var then-exit else-recurse))
    ((and (pair? f-body)
          (eq? (car f-body) 'let)
          (= (length (cadr f-body)) 1))
     (let* ((b (car (cadr f-body)))
            (var (car b))
            (val (cadr b))
            (inner (caddr f-body)))
       (if (and (pair? val)
                (memq (car val) '(= < <= > >= eq?))
                (= (length val) 3)
                (pair? inner)
                (eq? (car inner) 'if)
                (eq? (cadr inner) var)
                (not (expr-free-references-var? (caddr inner) var))
                (not (expr-free-references-var? (cdddr inner) var))
                (not (occurs-in? '%cont-call (caddr inner)))
                (pair? (cdddr inner))
                (cont-recurse-tail? f-name (car (cdddr inner))))
           (list val (caddr inner) (car (cdddr inner)))
           #f)))
    ;; Pattern B: (if (cmp-op lhs rhs) then-exit else-recurse)
    ((and (pair? f-body)
          (eq? (car f-body) 'if)
          (pair? (cadr f-body))
          (memq (car (cadr f-body)) '(= < <= > >= eq?))
          (= (length (cadr f-body)) 3))
     (let ((val (cadr f-body))
           (then-exit (caddr f-body))
           (else-recurse (if (pair? (cdddr f-body)) (car (cdddr f-body)) #f)))
       (if (and else-recurse
                (not (occurs-in? '%cont-call then-exit))
                (cont-recurse-tail? f-name else-recurse))
           (list val then-exit else-recurse)
           #f)))
    (else #f)))

(define (lir-compile-if test then else-opt si env tail?)
  (let ((else-label (unique-label-sym "L_else"))
        (end-label (unique-label-sym "L_end")))
    (cond
      ;; 1. Branch Fusion: binary comparisons (=, <, <=, >, >=, eq?)
      ((and (pair? test) (memq (car test) '(= < <= > >= eq?)) (= (length test) 3))
       (lir-compile-fused-cmp (car test) (cadr test) (caddr test) else-label si env))

      ;; 2. Branch Fusion: null?
      ((and (pair? test) (eq? (car test) 'null?) (= (length test) 2))
       (lir-compile-expr (cadr test) si env #f)
       (emit-lir! (list '%cmp '%rax 63))
       (emit-lir! (list '%jump-cond "jne" else-label)))

      ;; 3. Branch Fusion: zero?
      ((and (pair? test) (eq? (car test) 'zero?) (= (length test) 2))
       (let ((r (env-reg-var? (cadr test) env)))
         (if r
             (emit-lir! (list '%cmp r 0))
             (begin
               (lir-compile-expr (cadr test) si env #f)
               (emit-lir! (list '%cmp '%rax 0))))
         (emit-lir! (list '%jump-cond "jne" else-label))))

      ;; 4. Branch Fusion: pair?
      ((and (pair? test) (eq? (car test) 'pair?) (= (length test) 2))
       (lir-compile-expr (cadr test) si env #f)
       (emit-lir! '(%bit-and %rax 3))
       (emit-lir! (list '%cmp '%rax 1))
       (emit-lir! (list '%jump-cond "jne" else-label)))

      ;; 5. Branch Fusion: not
      ((and (pair? test) (eq? (car test) 'not) (= (length test) 2))
       (lir-compile-expr (cadr test) si env #f)
       (emit-lir! (list '%cmp '%rax 47))
       (emit-lir! (list '%jump-cond "jne" else-label)))

      ;; 6. Standard boolean expression fallback
      (else
       (lir-compile-expr test si env #f)
       (emit-lir! (list '%jump-if-false '%rax else-label))))

    (lir-compile-expr then si env tail?)
    (emit-lir! (list '%jump end-label (list '%rax)))
    (emit-lir! (list '%block else-label '()))
    (if (null? else-opt)
        (emit-lir! '(%mov %rax 47))
        (lir-compile-expr (car else-opt) si env tail?))
    (emit-lir! (list '%block end-label (list '%rax)))))

(define (lir-compile-begin exprs si env tail?)
  (if (null? exprs)
      (emit-lir! '(%mov %rax 63))
      (let loop ((es exprs))
        (if (null? (cdr es))
            (lir-compile-expr (car es) si env tail?)
            (begin
              (lir-compile-expr (car es) si env #f)
              (loop (cdr es)))))))

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

(define (cont-body-has-external-call? expr f-name)
  (cond
    ((null? expr) #f)
    ((not (pair? expr)) #f)
    (else
     (let ((op (car expr)))
       (case op
         ((quote) #f)
         ((%cont-call)
          (if (eq? (cadr expr) f-name)
              (let loop ((args (cddr expr)))
                (and (pair? args)
                     (or (cont-body-has-external-call? (car args) f-name)
                         (loop (cdr args)))))
              #t))
         ((%direct-call %call %closure-call %c-call %syscall %raw-call/cc %make-closure)
          #t)
         ((if)
          (or (cont-body-has-external-call? (cadr expr) f-name)
              (cont-body-has-external-call? (caddr expr) f-name)
              (if (null? (cdddr expr)) #f (cont-body-has-external-call? (cadddr expr) f-name))))
         ((begin)
          (let loop ((es (cdr expr)))
            (and (pair? es)
                 (or (cont-body-has-external-call? (car es) f-name)
                     (loop (cdr es))))))
         ((let letrec)
          (let* ((bindings (cadr expr))
                 (body (caddr expr))
                 (b-calls (let loop ((bs bindings))
                            (and (pair? bs)
                                 (or (cont-body-has-external-call? (cadar bs) f-name)
                                     (loop (cdr bs)))))))
            (or b-calls (cont-body-has-external-call? body f-name))))
         ((%cont-fun)
          (or (cont-body-has-external-call? (cadddr expr) f-name)
              (cont-body-has-external-call? (cadr (cdddr expr)) f-name)))
         ((%box-fixnum %unbox-fixnum %raw-add %raw-sub %raw-mul %raw-div %raw-cmp
           %bitwise-and %bitwise-ior %shift-left %shift-right %store %load
           + - * / = < <= > >= eq? null? zero? pair? not)
          (let loop ((args (cdr expr)))
            (and (pair? args)
                 (or (cont-body-has-external-call? (car args) f-name)
                     (loop (cdr args))))))
         (else
          (if (symbol? op)
              #t
              (or (cont-body-has-external-call? (car expr) f-name)
                  (cont-body-has-external-call? (cdr expr) f-name)))))))))

(define (lir-compile-cont-fun f-name params f-body in-body si env tail?)
  (let* ((entry-lbl (unique-label-sym "L_cont_entry_"))
         (exit-lbl  (unique-label-sym "L_cont_exit_"))
         (num-params (length params))
         ;; Allocate callee-saved registers (%rbx, %r13, %r14) for leaf loops with <= 3 parameters
         (use-reg-alloc? (and (<= num-params 3)
                              (not (cont-body-has-external-call? f-body f-name))))
         (rot-cand (and use-reg-alloc? (cont-loop-rotation-candidate? f-name f-body)))
         (callee-saved-regs '(%rbx %r13 %r14)))
    (cond
      ;; === Path 1: Rotated Do-While Loop (Loop Rotation / Inversion) ===
      (rot-cand
       (let* ((assigned-regs
               (let loop ((i 0) (acc '()))
                 (if (< i num-params)
                     (loop (+ i 1) (cons (list-ref callee-saved-regs i) acc))
                     (reverse acc))))
              (saved-slots
               (let loop ((rs assigned-regs) (curr-si si) (acc '()))
                 (if (null? rs)
                     acc
                     (begin
                       (track-lir-si! curr-si)
                       (emit-lir! (list '%store '%rsp curr-si (car rs)))
                       (loop (cdr rs) (- curr-si 8) (cons (cons (car rs) curr-si) acc))))))
              (p-bindings
               (let loop ((ps params) (rs assigned-regs) (acc '()))
                 (if (null? ps)
                     (reverse acc)
                     (loop (cdr ps) (cdr rs)
                           (cons (cons (car ps) (cons 'reg (car rs))) acc)))))
              (raw-vars (if (unboxed-fn? f-name)
                            (append params (get-raw-vars env))
                            (get-raw-vars env)))
              (body-env (set-raw-vars raw-vars (append p-bindings env)))
              (next-si (- si (* num-params 8)))
              (cmp-expr (car rot-cand))
              (then-exit (cadr rot-cand))
              (else-recurse (caddr rot-cand))
              (body-lbl (unique-label-sym "L_loop_body_"))
              (done-lbl (unique-label-sym "L_loop_done_"))
              ;; Note: in rot-env, target entry-lbl is #f so in-place update omits terminal %jump!
              (rot-cont-info (list '%cont-target #f p-bindings))
              (rot-env (cons (cons f-name rot-cont-info) body-env))
              ;; In init-env, initial call jumps to entry-lbl
              (init-cont-info (list '%cont-target entry-lbl p-bindings))
              (init-env (cons (cons f-name init-cont-info) body-env)))
         ;; 1. Compile in-body first: evaluates initial args into registers and jumps to entry-lbl
         (lir-compile-expr in-body next-si init-env tail?)
         (emit-lir! (list '%jump exit-lbl))

         ;; 2. Loop entry with guard check: if condition true, jump to done-lbl!
         (emit-lir! (list '%block entry-lbl assigned-regs))
         (lir-compile-fused-cmp-cond (car cmp-expr) (cadr cmp-expr) (caddr cmp-expr)
                                     done-lbl lir-cmp-true-cc next-si rot-env)

         ;; 3. Loop body: in-place update args, then backward conditional branch!
         (emit-lir! (list '%block body-lbl '()))
         (lir-compile-expr else-recurse next-si rot-env #f)
         (lir-compile-fused-cmp-cond (car cmp-expr) (cadr cmp-expr) (caddr cmp-expr)
                                     body-lbl lir-cmp-false-cc next-si rot-env)

         ;; 4. Loop exit / termination
         (emit-lir! (list '%block done-lbl '()))
         (lir-compile-expr then-exit next-si rot-env tail?)
         (emit-lir! (list '%label exit-lbl))
         ;; 5. Restore saved callee-saved registers upon exiting the loop
         (for-each
          (lambda (entry)
            (let ((reg (car entry))
                  (slot (cdr entry)))
              (emit-lir! (list '%load reg '%rsp slot))))
          (reverse saved-slots))))

      ;; === Path 2: Standard Leaf Loop Register Allocation ===
      (use-reg-alloc?
       (let* ((assigned-regs
               (let loop ((i 0) (acc '()))
                 (if (< i num-params)
                     (loop (+ i 1) (cons (list-ref callee-saved-regs i) acc))
                     (reverse acc))))
              ;; 1. Save original callee-saved registers to frame stack slots
              (saved-slots
               (let loop ((rs assigned-regs) (curr-si si) (acc '()))
                 (if (null? rs)
                     acc
                     (begin
                       (track-lir-si! curr-si)
                       (emit-lir! (list '%store '%rsp curr-si (car rs)))
                       (loop (cdr rs) (- curr-si 8) (cons (cons (car rs) curr-si) acc))))))
              (p-bindings
               (let loop ((ps params) (rs assigned-regs) (acc '()))
                 (if (null? ps)
                     (reverse acc)
                     (loop (cdr ps) (cdr rs)
                           (cons (cons (car ps) (cons 'reg (car rs))) acc)))))
              (raw-vars (if (unboxed-fn? f-name)
                            (append params (get-raw-vars env))
                            (get-raw-vars env)))
              (body-env (set-raw-vars raw-vars (append p-bindings env)))
              (next-si (- si (* num-params 8)))
              ;; Record contification target info in env
              (cont-info (list '%cont-target entry-lbl p-bindings))
              (full-env (cons (cons f-name cont-info) body-env)))
         ;; Compile in-body first (evaluates initial call into registers and jumps to entry-lbl)
         (lir-compile-expr in-body next-si full-env tail?)
         (emit-lir! (list '%jump exit-lbl))
         ;; Continuation function body entry: emitted as %block with register block arguments!
         (emit-lir! (list '%block entry-lbl assigned-regs))
         (lir-compile-expr f-body next-si full-env tail?)
         (emit-lir! (list '%label exit-lbl))
         ;; Restore saved callee-saved registers upon exiting the loop
         (for-each
          (lambda (entry)
            (let ((reg (car entry))
                  (slot (cdr entry)))
              (emit-lir! (list '%load reg '%rsp slot))))
          (reverse saved-slots))))

      ;; === Path 3: Stack-based Fallback Path (> 3 params or non-leaf) ===
      (else
        (let* ((param-slots
                (let loop ((ps params) (curr-si si) (acc-slots '()) (acc-env env))
                  (if (null? ps)
                      (cons (reverse acc-slots) acc-env)
                      (begin
                        (track-lir-si! curr-si)
                        (loop (cdr ps)
                              (- curr-si 8)
                              (cons (cons (car ps) curr-si) acc-slots)
                              (cons (cons (car ps) curr-si) acc-env))))))
               (p-offsets (car param-slots))
               (raw-vars (if (unboxed-fn? f-name)
                             (append params (get-raw-vars env))
                             (get-raw-vars env)))
               (body-env (set-raw-vars raw-vars (cdr param-slots)))
               (next-si (- si (* (length params) 8)))
               ;; Record contification target info in env
               (cont-info (list '%cont-target entry-lbl p-offsets))
               (full-env (cons (cons f-name cont-info) body-env)))
          ;; Compile in-body first
          (lir-compile-expr in-body next-si full-env tail?)
          (emit-lir! (list '%jump exit-lbl))
          ;; Continuation function body entry: emitted as %block with block arguments!
          (emit-lir! (list '%block entry-lbl (map (lambda (po) (list '%stack (cdr po))) p-offsets)))
          (lir-compile-expr f-body next-si full-env tail?)
          (emit-lir! (list '%label exit-lbl)))))))

(define (lir-compile-cont-call f-name args si env)
  (let ((binding (assq f-name env)))
    (if (not (and binding (pair? (cdr binding)) (eq? (cadr binding) '%cont-target)))
        (error "Unresolved %cont-call target:" f-name)
        (let* ((target-info (cdr binding))
               (entry-lbl (cadr target-info))
               (p-bindings (caddr target-info))
               (num-args (length args))
               (all-reg-targets? (cont-target-all-regs? target-info)))
          (if (not (= num-args (length p-bindings)))
              (error "Arity mismatch in %cont-call:" f-name)
              (cond
                ;; === In-Place / Register-Only Transfer Path ===
                (all-reg-targets?
                 (lir-compile-in-place-cont-call f-name args target-info si env))

                (else
                 ;; === General Transfer Path (sequential stack evaluation) ===
                 (let eval-loop ((as args) (curr-si si) (temp-sis '()))
                   (if (pair? as)
                       (begin
                         (track-lir-si! curr-si)
                         (lir-compile-expr (car as) curr-si env #f)
                         (emit-lir! (list '%store '%rsp curr-si '%rax))
                         (eval-loop (cdr as) (- curr-si 8) (cons curr-si temp-sis)))
                       (begin
                         ;; Transfer temporary values to parameter slots or registers
                         (let xfer-loop ((ts (reverse temp-sis)) (pbs p-bindings))
                           (if (and (pair? ts) (pair? pbs))
                               (let ((t-si (car ts))
                                     (p-info (cdar pbs)))
                                 (cond
                                   ((and (pair? p-info) (eq? (car p-info) 'reg))
                                    (emit-lir! (list '%load (cdr p-info) '%rsp t-si)))
                                   ((memq p-info '(%rax %rbx %rcx %rdx %rsi %rdi %rbp %rsp %r8 %r9 %r10 %r11 %r12 %r13 %r14 %r15))
                                    (emit-lir! (list '%load p-info '%rsp t-si)))
                                   (else
                                    (emit-lir! (list '%load '%rdx '%rsp t-si))
                                    (emit-lir! (list '%store '%rsp p-info '%rdx))))
                                 (xfer-loop (cdr ts) (cdr pbs)))))
                         ;; Directly jump to continuation target with block arguments!
                         (emit-lir! (list '%jump entry-lbl
                                          (map (lambda (pb)
                                                 (let ((p-info (cdr pb)))
                                                   (cond
                                                     ((and (pair? p-info) (eq? (car p-info) 'reg))
                                                      (cdr p-info))
                                                     ((memq p-info '(%rax %rbx %rcx %rdx %rsi %rdi %rbp %rsp %r8 %r9 %r10 %r11 %r12 %r13 %r14 %r15))
                                                      p-info)
                                                     (else
                                                      (list '%stack p-info)))))
                                               p-bindings)))))))))))))

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

(define (lir-compile-expr expr si env tail?)
  (cond
    ((immediate? expr)
     (let ((val (lir-immediate expr)))
       (if (and (pair? val) (eq? (car val) '%string-ref))
           (emit-lir! (list '%str-ref '%rax (cadr val)))
           (emit-lir! (list '%mov '%rax val)))))
    ((symbol? expr)
     (lir-compile-variable expr env))
    ((pair? expr)
     (let ((op (car expr)))
       (cond
         ((zero-arg-prim? op)
          (lir-compile-zero-arg op si env))
         ((eq? op '-)
          (if (null? (cddr expr))
              (lir-compile-unary '- (cadr expr) si env)
              (lir-compile-binop '- (cadr expr) (caddr expr) si env)))
         ((unary-prim? op)
          (lir-compile-unary op (cadr expr) si env))
         ((eq? op '%make-closure)
          (lir-compile-make-closure expr si env))
         ((eq? op '%make-stack-closure)
          (lir-compile-make-stack-closure expr si env))
         ((eq? op '%stack-cons)
          (lir-compile-stack-cons expr si env))
         ((eq? op '%closure-ref)
          (let* ((idx (caddr expr))
                 (offset (- (* idx 8) 1)))
            (lir-compile-expr (cadr expr) si env #f)
            (emit-lir! (list '%load '%rax '%rax offset))))
         ((eq? op '%closure-set!)
          (let* ((c-expr (cadr expr))
                 (idx (caddr expr))
                 (val-expr (cadddr expr))
                 (offset (- (* idx 8) 1)))
            (track-lir-si! si)
            (lir-compile-expr c-expr si env #f)
            (emit-lir! (list '%store '%rsp si '%rax))
            (track-lir-si! (- si 8))
            (lir-compile-expr val-expr (- si 8) env #f)
            (emit-lir! (list '%load '%rdx '%rsp si))
            (emit-lir! (list '%store '%rdx offset '%rax))
            (emit-lir! '(%mov %rax 63))))
         ((binop-prim? op)
          (lir-compile-binop op (cadr expr) (caddr expr) si env))
         ((triop-prim? op)
          (lir-compile-triop op (cadr expr) (caddr expr) (cadddr expr) si env))
         ((septop-prim? op)
          (lir-compile-raw-syscall (cdr expr) si env))
         ((eq? op '%cont-fun)
          (lir-compile-cont-fun (cadr expr) (caddr expr) (cadddr expr) (cadr (cdddr expr)) si env tail?))
         ((eq? op '%cont-call)
          (lir-compile-cont-call (cadr expr) (cddr expr) si env))
         ((eq? op '%with-handler)
          (lir-compile-with-handler (cadr expr) (caddr expr) si env tail?))
         ((eq? op '%raw-call/cc)
          (lir-compile-raw-call-cc (cadr expr) si env tail?))
         ((eq? op '%values)
          (lir-compile-values (cdr expr) si env))
         ((eq? op '%call-with-values)
          (lir-compile-call-with-values (cadr expr) (caddr expr) si env tail?))
         ((eq? op 'let)
          (lir-compile-let (cadr expr) (caddr expr) si env tail?))
         ((eq? op 'if)
          (lir-compile-if (cadr expr) (caddr expr) (cdddr expr) si env tail?))
         ((eq? op 'begin)
          (lir-compile-begin (cdr expr) si env tail?))
         ((eq? op 'quote)
          (let ((datum (cadr expr)))
            (cond
              ((symbol? datum)
               (let ((id (intern-symbol datum)))
                 (emit-lir! (list '%mov '%rax id))))
              ((immediate? datum)
               (let ((val (lir-immediate datum)))
                 (if (and (pair? val) (eq? (car val) '%string-ref))
                     (emit-lir! (list '%str-ref '%rax (cadr val)))
                     (emit-lir! (list '%mov '%rax val)))))
              ((pair? datum)
               (lir-compile-expr (list 'cons
                                       (list 'quote (car datum))
                                       (list 'quote (cdr datum)))
                                 si env #f))
              (else
               (error "Invalid quoted datum in LIR:" datum)))))
         ((eq? op '%direct-call)
          (lir-compile-direct-call (cadr expr) (cddr expr) si env tail?))
         ((eq? op '%global-ref)
          (emit-lir! (list '%global-ref '%rax (cadr expr))))
         ((eq? op '%global-set!)
          (track-lir-si! si)
          (lir-compile-expr (caddr expr) si env #f)
          (emit-lir! (list '%global-set! (cadr expr) '%rax)))
         (else
          ;; General procedure call
          (lir-compile-call op (cdr expr) si env tail?)))))
    (else
     (error "Invalid syntax in LIR compiler:" expr))))

;;; Compile a single lifted %function to LIR representation
(define (lir-compile-function fn)
  (let* ((label (cadr fn))
         (params (caddr fn))
         (body (cadddr fn))
         (num-params (length params))
         (initial-raw-vars (if (unboxed-fn? label) params '())))
    (reset-lir!)
    ;; Build callee env:
    ;; %self at [rsp - 8]
    ;; params at [rsp + 8 * (num-params - i)]
    (let* ((self-env (list (cons '%self (cons 'self -8))))
           (param-env
            (let loop ((ps params) (i 0) (acc '()))
              (if (null? ps) acc
                  (let ((offset (* 8 (- num-params i))))
                    (loop (cdr ps) (+ i 1)
                          (cons (cons (car ps) (cons 'param offset)) acc))))))
           (callee-env (cons (cons '%num-params num-params)
                             (cons (cons '%raw-vars initial-raw-vars)
                                   (append self-env param-env))))
           (callee-si -24))
      (track-lir-si! -8)
      (track-lir-si! -16)
      (track-lir-si! callee-si)
      (emit-lir! '(%store %rsp -16 %rax))
      (lir-compile-expr body callee-si callee-env #t)
      (emit-lir! '(%return))
      (let* ((needed-frame (- 0 (car *lir-min-si*)))
             (frame-size (align-frame-shift needed-frame))
             (insts (reverse (car *lir-instructions*))))
        (list '%lir-function
              label
              (list 'params params)
              (list 'frame-size frame-size)
              (cons 'body insts))))))

;;; Pass 6 Entrypoint: Transforms Pass 5 %program AST into %lir-program
(define (generate-lir prog)
  (reset-safepoints!)
  (reset-symbol-table!)
  (let ((funcs (cadr prog))
         (main-expr (caddr prog)))
    (reset-lir!)
    (track-lir-si! -8)
    (lir-compile-expr main-expr -8 (list (cons '%raw-vars '())) #f)
    (emit-lir! '(%return))
    (let* ((main-insts (reverse (car *lir-instructions*)))
           (main-frame (align-frame-shift (- 0 (car *lir-min-si*))))
           (lir-main (list '%lir-main
                           (list 'frame-size main-frame)
                           (cons 'body main-insts)))
           (lir-funcs (map lir-compile-function funcs))
           (safepoints (reverse (car *lir-safepoints*))))
      (list '%lir-program
            (list 'strings (car *strings*))
            (list 'stackmaps safepoints)
            (cons '%lir-functions lir-funcs)
            lir-main))))

