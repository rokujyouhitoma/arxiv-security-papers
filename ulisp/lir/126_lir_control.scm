;;; =======================================================================
;;; ULisp Compiler Pass 126: LIR Control Flow & Join Path Splitting Pass
;;; Conforms to DSN-33 Architecture Specification & Issue #583
;;; =======================================================================
;;; Lowers high-level control structures (let, if, begin) into LIR blocks,
;;; performing Join Node Path Splitting and ANF Condition/Branch Flag Fusion.
;;; =======================================================================

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
                  (next-rvars (if is-raw (cons var rvars) rvars))
                  (extra-bytes (stack-alloc-bytes val))
                  (svars (get-stack-vars new-env))
                  (next-svars (if (> extra-bytes 0) (cons var svars) svars))
                  (next-si (if (> extra-bytes 0)
                               (- curr-si (+ 8 extra-bytes))
                               (- curr-si 8))))
             (track-lir-si! curr-si)
             (if (> extra-bytes 0)
                 (track-lir-si! next-si))
             (lir-compile-expr val curr-si env #f)
             (emit-lir! (list '%store '%rsp curr-si '%rax))
             (loop (cdr bs)
                   next-si
                   (cons (cons var curr-si)
                         (set-stack-vars next-svars (set-raw-vars next-rvars new-env))))))))))

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
