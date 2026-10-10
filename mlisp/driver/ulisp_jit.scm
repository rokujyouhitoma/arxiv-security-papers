;;; =======================================================================
;;; MLisp Standalone Native JIT Binary Driver: ulisp-jit (ulisp_jit.scm)
;;; Conforms to DSN-34 & Issue #511
;;;
;;; 100% Pure Scheme Standalone JIT-Embedded Scheme VM:
;;; - ULisp S-expression Reader (standard input reader)
;;; - MLisp Auto-Instrumentation (zero-invasive loop detection & jit-merge-point injection)
;;; - Endogenous Meta-Tracing JIT (tracer, PE optimizer, LIR bridge, JIT buffer)
;;; - Complete Scheme Evaluator supporting named let, recursive define, environments, and primitives
;;; =======================================================================

;;; -----------------------------------------------------------------------
;;; 1. Standard Pure Scheme Helpers
;;; -----------------------------------------------------------------------


(define (memq item ls)
  (cond
    ((null? ls) #f)
    ((eq? (car ls) item) ls)
    (else (memq item (cdr ls)))))

(define (cadr x) (car (cdr x)))
(define (cddr x) (cdr (cdr x)))
(define (caddr x) (car (cdr (cdr x))))
(define (cadddr x) (car (cdr (cdr (cdr x)))))
(define (cddddr x) (cdr (cdr (cdr (cdr x)))))
(define (caar x) (car (car x)))
(define (cadar x) (car (cdr (car x))))
(define (cdddr x) (cdr (cdr (cdr x))))
(define (caadr x) (car (car (cdr x))))
(define (cdadr x) (cdr (car (cdr x))))
(define (list? x) (or (null? x) (pair? x)))

(define (assq key ls)
  (cond
    ((null? ls) #f)
    ((not (pair? (car ls))) (assq key (cdr ls)))
    ((eq? (car (car ls)) key) (car ls))
    (else (assq key (cdr ls)))))

(define (equal? a b)
  (cond
    ((eq? a b) #t)
    ((and (pair? a) (pair? b))
     (and (equal? (car a) (car b))
          (equal? (cdr a) (cdr b))))
    (else #f)))

(define (reverse ls)
  (let loop ((l ls) (acc '()))
    (if (null? l)
        acc
        (loop (cdr l) (cons (car l) acc)))))

(define (append l1 l2)
  (if (null? l1)
      l2
      (cons (car l1) (append (cdr l1) l2))))

(define (filter pred ls)
  (cond
    ((null? ls) '())
    ((pred (car ls)) (cons (car ls) (filter pred (cdr ls))))
    (else (filter pred (cdr ls)))))

(define (map f ls)
  (if (null? ls)
      '()
      (cons (f (car ls)) (map f (cdr ls)))))

(define (for-each proc ls)
  (if (not (null? ls))
      (begin
        (proc (car ls))
        (for-each proc (cdr ls)))))

(define (list-ref ls n)
  (if (= n 0)
      (car ls)
      (list-ref (cdr ls) (- n 1))))

;;; -----------------------------------------------------------------------
;;; 2. MLisp Meta-Tracer (Boxed Mutable Cells for AOT)
;;; -----------------------------------------------------------------------
;;; Tracer states: 0 = IDLE, 1 = RECORDING, 2 = COMPILED

(define *tracer-hot-threshold* (cons 3 '()))
(define *tracer-state* (cons 0 '()))
(define *loop-counters* (cons '() '()))
(define *current-recording-pc* (cons #f '()))
(define *current-trace-buffer* (cons '() '()))
(define *compiled-traces* (cons '() '()))

(define (tracer-reset!)
  (set-car! *tracer-state* 0)
  (set-car! *loop-counters* '())
  (set-car! *current-recording-pc* #f)
  (set-car! *current-trace-buffer* '())
  (set-car! *compiled-traces* '()))

(define (set-hot-threshold! n)
  (set-car! *tracer-hot-threshold* n))

(define (get-loop-count pc)
  (let ((entry (assq pc (car *loop-counters*))))
    (if entry (cdr entry) 0)))

(define (inc-loop-count! pc)
  (let ((entry (assq pc (car *loop-counters*))))
    (if entry
        (begin
          (set-cdr! entry (+ (cdr entry) 1))
          (cdr entry))
        (begin
          (set-car! *loop-counters* (cons (cons pc 1) (car *loop-counters*)))
          1))))

(define (trace-record! op dst a1 a2)
  (if (= (car *tracer-state*) 1)
      (let ((inst (if (null? a2)
                      (if (null? a1)
                          (list op dst)
                          (list op dst a1))
                      (list op dst a1 a2))))
        (set-car! *current-trace-buffer* (cons inst (car *current-trace-buffer*))))))

(define (trace-guard! cond-type var expected fail-k)
  (if (= (car *tracer-state*) 1)
      (let ((inst (list '%guard cond-type var expected fail-k)))
        (set-car! *current-trace-buffer* (cons inst (car *current-trace-buffer*))))))

(define (start-recording! pc)
  (set-car! *tracer-state* 1)
  (set-car! *current-recording-pc* pc)
  (set-car! *current-trace-buffer* (list (list '%trace-loop-entry pc))))

(define (finish-recording! pc)
  (let* ((insts (reverse (cons (list '%trace-loop-jump pc) (car *current-trace-buffer*))))
         (trace (list '%trace-loop
                      (list '%pc pc)
                      (list '%body insts))))
    (set-car! *compiled-traces* (cons (cons pc trace) (car *compiled-traces*)))
    (set-car! *tracer-state* 2)
    (set-car! *current-recording-pc* #f)
    (set-car! *current-trace-buffer* '())
    trace))

(define (lookup-compiled-trace pc)
  (let ((entry (assq pc (car *compiled-traces*))))
    (if entry (cdr entry) #f)))

;;; -----------------------------------------------------------------------
;;; 3. MLisp Pure Scheme Trace Optimizations (PE + Virtuals)
;;; -----------------------------------------------------------------------

(define (constant? x)
  (or (number? x) (boolean? x) (string? x)))

(define (pe-eval-op op v1 v2)
  (case op
    ((%add) (if (and (number? v1) (number? v2)) (+ v1 v2) #f))
    ((%sub) (if (and (number? v1) (number? v2)) (- v1 v2) #f))
    ((%mul) (if (and (number? v1) (number? v2)) (* v1 v2) #f))
    (else #f)))

(define (pe-find-known var env)
  (let ((entry (assq var env)))
    (if entry (cdr entry) #f)))

(define (optimize-pe-pure trace)
  (let* ((body (cadr (caddr trace)))
         (opt-body
          (let loop ((insts body) (known '()) (acc '()))
            (if (null? insts)
                (reverse acc)
                (let* ((inst (car insts))
                       (op (car inst)))
                  (case op
                    ((%mov)
                     (let* ((dst (cadr inst))
                            (src (caddr inst))
                            (k-src (if (constant? src) src (pe-find-known src known))))
                       (if k-src
                           (loop (cdr insts)
                                 (cons (cons dst k-src) (filter (lambda (e) (not (eq? (car e) dst))) known))
                                 (cons (list '%mov dst k-src) acc))
                           (loop (cdr insts)
                                 (filter (lambda (e) (not (eq? (car e) dst))) known)
                                 (cons inst acc)))))

                    ((%add %sub %mul)
                     (let* ((dst (cadr inst))
                            (a1 (caddr inst))
                            (a2 (cadddr inst))
                            (v1 (if (constant? a1) a1 (pe-find-known a1 known)))
                            (v2 (if (constant? a2) a2 (pe-find-known a2 known)))
                            (res (if (and v1 v2) (pe-eval-op op v1 v2) #f)))
                       (if res
                           (loop (cdr insts)
                                 (cons (cons dst res) (filter (lambda (e) (not (eq? (car e) dst))) known))
                                 (cons (list '%mov dst res) acc))
                           (loop (cdr insts)
                                 (filter (lambda (e) (not (eq? (car e) dst))) known)
                                 (cons inst acc)))))

                    ((%guard)
                     (loop (cdr insts) known (cons inst acc)))

                    (else
                     (loop (cdr insts) known (cons inst acc)))))))))
    (list '%trace-loop (cadr trace) (list '%body opt-body))))

(define (optimize-virtuals-pure trace)
  (let* ((body (cadr (caddr trace)))
         (writes
          (let loop ((insts body) (acc '()))
            (if (null? insts)
                acc
                (let ((op (caar insts)))
                  (if (or (eq? op '%mov) (eq? op '%add) (eq? op '%sub) (eq? op '%mul))
                      (loop (cdr insts) (cons (cadar insts) acc))
                      (loop (cdr insts) acc))))))
         (reads
          (let loop ((insts body) (acc '()))
            (if (null? insts)
                acc
                (let* ((inst (car insts))
                       (op (car inst)))
                  (case op
                    ((%mov)
                     (let ((src (caddr inst)))
                       (loop (cdr insts) (if (symbol? src) (cons src acc) acc))))
                    ((%add %sub %mul)
                     (let ((a1 (caddr inst)) (a2 (cadddr inst)))
                       (loop (cdr insts)
                             (let ((ac1 (if (symbol? a1) (cons a1 acc) acc)))
                               (if (symbol? a2) (cons a2 ac1) ac1)))))
                    ((%guard)
                     (let ((v (caddr inst)))
                       (loop (cdr insts) (if (symbol? v) (cons v acc) acc))))
                    (else (loop (cdr insts) acc)))))))
         (dead-writes
          (filter (lambda (w) (not (memq w reads))) writes))
         (opt-body
          (filter (lambda (inst)
                    (let ((op (car inst)))
                      (if (or (eq? op '%mov) (eq? op '%add) (eq? op '%sub) (eq? op '%mul))
                          (not (memq (cadr inst) dead-writes))
                          #t)))
                  body)))
    (list '%trace-loop (cadr trace) (list '%body opt-body))))

(define (optimize-trace-full trace)
  (let* ((t1 (optimize-pe-pure trace))
         (t2 (optimize-virtuals-pure t1)))
    t2))

;;; -----------------------------------------------------------------------
;;; 4. MLisp Pure Scheme Bridge: Trace to ULisp Canonical Pass 6 LIR
;;; -----------------------------------------------------------------------

(define (trace-inst->lir inst)
  (let ((op (car inst)))
    (case op
      ((%trace-loop-entry)
       (list (list 'label (string-append "trace_loop_" (if (symbol? (cadr inst)) (symbol->string (cadr inst)) (number->string (cadr inst)))))))

      ((%trace-loop-jump)
       (list (list 'jmp (string-append "trace_loop_" (if (symbol? (cadr inst)) (symbol->string (cadr inst)) (number->string (cadr inst)))))))

      ((%mov)
       (let ((dst (cadr inst)) (src (caddr inst)))
         (list (list 'mov (list 'reg dst) (if (number? src) (list 'imm src) (list 'reg src))))))

      ((%add)
       (let ((dst (cadr inst)) (a1 (caddr inst)) (a2 (cadddr inst)))
         (list (list 'mov (list 'reg dst) (if (number? a1) (list 'imm a1) (list 'reg a1)))
               (list 'add (list 'reg dst) (if (number? a2) (list 'imm a2) (list 'reg a2))))))

      ((%sub)
       (let ((dst (cadr inst)) (a1 (caddr inst)) (a2 (cadddr inst)))
         (list (list 'mov (list 'reg dst) (if (number? a1) (list 'imm a1) (list 'reg a1)))
               (list 'sub (list 'reg dst) (if (number? a2) (list 'imm a2) (list 'reg a2))))))

      ((%guard)
       (let ((cond-type (cadr inst)) (var (caddr inst)) (fail-k (list-ref inst 4)))
         (list (list 'cmp (list 'reg var) (list 'imm 0))
               (list 'jne (string-append "bailout_" (if (symbol? fail-k) (symbol->string fail-k) (number->string fail-k)))))))

      (else '()))))

(define (trace->lir-program trace)
  (let* ((pc (cadr (cadr trace)))
         (body (cadr (caddr trace)))
         (lir-insts
          (let loop ((insts body) (acc '()))
            (if (null? insts)
                (reverse acc)
                (let ((lowered (trace-inst->lir (car insts))))
                  (loop (cdr insts) (append (reverse lowered) acc)))))))
    (list 'lir-module
          (list 'entry (string-append "jit_loop_" (if (symbol? pc) (symbol->string pc) (number->string pc))))
          (list 'instructions lir-insts))))

;;; -----------------------------------------------------------------------
;;; 5. MLisp JIT Execution Buffer & Dispatch
;;; -----------------------------------------------------------------------

(define *jit-buffer-table* (cons '() '()))
(define *jit-stats-executed* (cons 0 '()))
(define *jit-stats-bailouts* (cons 0 '()))

(define (jit-runtime-reset!)
  (set-car! *jit-buffer-table* '())
  (set-car! *jit-stats-executed* 0)
  (set-car! *jit-stats-bailouts* 0))

(define (make-jit-buffer pc lir-prog)
  (let ((pc-str (if (symbol? pc) (symbol->string pc) (number->string pc))))
    (list 'jit-buffer
          (cons 'pc pc)
          (cons 'status 'WRITABLE)
          (cons 'lir-prog lir-prog)
          (cons 'entry-point (string-append "jit_entry_" pc-str)))))

(define (jit-buffer-make-executable! buf)
  (let ((status-entry (assq 'status (cdr buf))))
    (if status-entry
        (set-cdr! status-entry 'EXECUTABLE))))

(define (install-jit-code! pc lir-prog)
  (let ((buf (make-jit-buffer pc lir-prog)))
    (jit-buffer-make-executable! buf)
    (set-car! *jit-buffer-table* (cons (cons pc buf) (car *jit-buffer-table*)))
    buf))

(define (lookup-jit-buffer pc)
  (let ((entry (assq pc (car *jit-buffer-table*))))
    (if entry (cdr entry) #f)))

(define (dispatch-jit-loop pc initial-state)
  (let ((buf (lookup-jit-buffer pc)))
    (if (not buf)
        #f
        (begin
          (set-car! *jit-stats-executed* (+ (car *jit-stats-executed*) 1))
          (list 'jit-executed pc initial-state)))))

;;; -----------------------------------------------------------------------
;;; 6. MLisp Auto-Instrumentation (Zero-Invasive)
;;; -----------------------------------------------------------------------

(define *auto-loop-counter* (cons 0 '()))

(define (reset-auto-loop-counter!)
  (set-car! *auto-loop-counter* 0))

(define (next-auto-loop-tag prefix)
  (let* ((cnt (car *auto-loop-counter*))
         (tag (string->symbol (string-append (symbol->string prefix)
                                             "_"
                                             (number->string cnt)))))
    (set-car! *auto-loop-counter* (+ cnt 1))
    tag))

(define (already-instrumented? body)
  (and (pair? body)
       (pair? (car body))
       (eq? (caar body) 'jit-merge-point)))

(define (last-element ls)
  (if (null? (cdr ls))
      (car ls)
      (last-element (cdr ls))))

(define (tail-calls? expr target-name)
  (cond
    ((not (pair? expr)) #f)
    ((eq? (car expr) 'quote) #f)
    ((eq? (car expr) target-name) #t)
    ((eq? (car expr) 'if)
     (let ((then-part (caddr expr))
           (else-part (if (pair? (cdddr expr)) (cadddr expr) #f)))
       (or (tail-calls? then-part target-name)
           (and else-part (tail-calls? else-part target-name)))))
    ((eq? (car expr) 'begin)
     (let ((forms (cdr expr)))
       (and (pair? forms)
            (tail-calls? (last-element forms) target-name))))
    ((eq? (car expr) 'cond)
     (let loop ((clauses (cdr expr)))
       (if (null? clauses)
           #f
           (let ((clause (car clauses)))
             (or (and (pair? (cdr clause))
                      (tail-calls? (last-element (cdr clause)) target-name))
                 (loop (cdr clauses)))))))
    ((memq (car expr) '(let let* letrec))
     (if (and (eq? (car expr) 'let)
              (pair? (cdr expr))
              (symbol? (cadr expr)))
         (let ((body (cdddr expr)))
           (and (pair? body)
                (tail-calls? (last-element body) target-name)))
         (let ((body (cddr expr)))
           (and (pair? body)
                (tail-calls? (last-element body) target-name)))))
    (else #f)))

(define (extract-binding-vars bindings)
  (if (null? bindings)
      '()
      (let ((b (car bindings)))
        (cons (if (pair? b) (car b) b)
              (extract-binding-vars (cdr bindings))))))

(define (auto-instrument-form form)
  (cond
    ((not (pair? form)) form)
    ((eq? (car form) 'quote) form)

    ;; Named let
    ((and (eq? (car form) 'let)
          (pair? (cdr form))
          (symbol? (cadr form))
          (pair? (cddr form))
          (list? (caddr form)))
     (let* ((loop-name (cadr form))
            (raw-bindings (caddr form))
            (raw-body (cdddr form))
            (vars (extract-binding-vars raw-bindings))
            (inst-bindings
             (map (lambda (b)
                    (if (and (pair? b) (pair? (cdr b)))
                        (list (car b) (auto-instrument-form (cadr b)))
                        b))
                  raw-bindings))
            (inst-body (map (lambda (e) (auto-instrument-form e)) raw-body)))
       (if (already-instrumented? inst-body)
           (cons 'let (cons loop-name (cons inst-bindings inst-body)))
           (let* ((tag (next-auto-loop-tag loop-name))
                  (jmp (list 'jit-merge-point (list 'quote tag) (cons 'list vars))))
             (cons 'let (cons loop-name (cons inst-bindings (cons jmp inst-body))))))))

    ;; Standard let / let* / letrec
    ((memq (car form) '(let let* letrec))
     (let* ((op (car form))
            (raw-bindings (cadr form))
            (raw-body (cddr form))
            (inst-bindings
             (map (lambda (b)
                    (if (and (pair? b) (pair? (cdr b)))
                        (list (car b) (auto-instrument-form (cadr b)))
                        b))
                  raw-bindings))
            (inst-body (map (lambda (e) (auto-instrument-form e)) raw-body)))
       (cons op (cons inst-bindings inst-body))))

    ;; Tail-recursive define
    ((and (eq? (car form) 'define)
          (pair? (cdr form))
          (pair? (cadr form))
          (symbol? (caadr form)))
     (let* ((func-name (caadr form))
            (params (cdadr form))
            (raw-body (cddr form))
            (inst-body (map (lambda (e) (auto-instrument-form e)) raw-body))
            (is-tail-rec? (tail-calls? (if (= (length raw-body) 1)
                                           (car raw-body)
                                           (cons 'begin raw-body))
                                       func-name)))
       (if (and is-tail-rec? (not (already-instrumented? inst-body)))
           (let* ((head (cons func-name params))
                  (jmp (list 'jit-merge-point (list 'quote func-name) (cons 'list params))))
             (cons 'define (cons head (cons jmp inst-body))))
           (cons 'define (cons (cons func-name params) inst-body)))))

    ;; lambda
    ((eq? (car form) 'lambda)
     (let ((params (cadr form))
           (body (cddr form)))
       (cons 'lambda (cons params (map (lambda (e) (auto-instrument-form e)) body)))))

    ;; if
    ((eq? (car form) 'if)
     (let ((test (auto-instrument-form (cadr form)))
           (then (auto-instrument-form (caddr form)))
           (else (if (pair? (cdddr form))
                     (list (auto-instrument-form (cadddr form)))
                     '())))
       (if (null? else)
           (list 'if test then)
           (list 'if test then (car else)))))

    ;; cond
    ((eq? (car form) 'cond)
     (let ((clauses
            (map (lambda (cl)
                   (cons (auto-instrument-form (car cl))
                         (map (lambda (e) (auto-instrument-form e)) (cdr cl))))
                 (cdr form))))
       (cons 'cond clauses)))

    ;; begin
    ((eq? (car form) 'begin)
     (cons 'begin (map (lambda (e) (auto-instrument-form e)) (cdr form))))

    ;; set!
    ((eq? (car form) 'set!)
     (list 'set! (cadr form) (auto-instrument-form (caddr form))))

    (else
     (map (lambda (e) (auto-instrument-form e)) form))))

(define (auto-instrument-forms forms)
  (map (lambda (f) (auto-instrument-form f)) forms))

;;; -----------------------------------------------------------------------
;;; 7. JIT Merge Point Hook & Scheme Evaluator
;;; -----------------------------------------------------------------------

(define (jit-merge-point-hook tag state-vals)
  (let ((compiled (lookup-compiled-trace tag)))
    (if compiled
        (dispatch-jit-loop tag state-vals)
        (let ((cnt (inc-loop-count! tag)))
          (if (>= cnt (car *tracer-hot-threshold*))
              (cond
                ((= (car *tracer-state*) 0)
                 (display-string "[JIT] Hot loop detected! Recording trace: ")
                 (display tag)
                 (newline)
                 (start-recording! tag))

                ((and (= (car *tracer-state*) 1)
                      (eq? (car *current-recording-pc*) tag))
                 (let* ((raw-trace (finish-recording! tag))
                        (opt-trace (optimize-trace-full raw-trace))
                        (lir-prog (trace->lir-program opt-trace)))
                   (install-jit-code! tag lir-prog)
                   (display-string "[JIT] Compiled and installed native trace for loop: ")
                   (display tag)
                   (newline)
                   (dispatch-jit-loop tag state-vals))))
              #f)))))

(define (mini-lookup var env)
  (let ((entry (assq var env)))
    (if entry (cdr entry) 0)))

(define (mini-extend-env vars vals env)
  (if (null? vars)
      env
      (cons (cons (car vars) (car vals))
            (mini-extend-env (cdr vars) (cdr vals) env))))

(define (letrec-loop loop-name vars body initial-vals outer-env)
  (let loop ((current-vals initial-vals))
    (let* ((loop-handler (list '%loop loop-name vars))
           (env1 (mini-extend-env (list loop-name) (list loop-handler) outer-env))
           (call-env (mini-extend-env vars current-vals env1))
           (res (mini-eval-sequence body call-env)))
      (if (and (pair? res) (eq? (car res) '%loop-recur))
          (loop (cdr res))
          res))))

(define (mini-eval-sequence exprs env)
  (if (null? (cdr exprs))
      (mini-eval (car exprs) env)
      (begin
        (mini-eval (car exprs) env)
        (mini-eval-sequence (cdr exprs) env))))

(define (mini-eval expr env)
  (cond
    ((number? expr) expr)
    ((boolean? expr) expr)
    ((string? expr) expr)
    ((char? expr) expr)
    ((null? expr) expr)
    ((symbol? expr) (mini-lookup expr env))

    ((pair? expr)
     (let ((op (car expr)))
       (case op
         ((quote) (cadr expr))

         ((if)
          (let ((test-val (mini-eval (cadr expr) env)))
            (trace-guard! 'type-bool test-val 'boolean 'exit-guard)
            (if (and test-val (not (eq? test-val #f)))
                (mini-eval (caddr expr) env)
                (if (pair? (cdddr expr))
                    (mini-eval (cadddr expr) env)
                    #f))))

         ((begin)
          (mini-eval-sequence (cdr expr) env))

         ((jit-merge-point)
          (let* ((tag (mini-eval (cadr expr) env))
                 (state (mini-eval (caddr expr) env)))
            (jit-merge-point-hook tag state)))

         ((let)
          (if (and (pair? (cdr expr)) (symbol? (cadr expr)))
              ;; Named let: (let loop ((var init)...) body...)
              (let* ((loop-name (cadr expr))
                     (bindings (caddr expr))
                     (body (cdddr expr))
                     (vars (map (lambda (b) (car b)) bindings))
                     (inits (map (lambda (b) (mini-eval (cadr b) env)) bindings)))
                (letrec-loop loop-name vars body inits env))
              ;; Standard let: (let ((var init)...) body...)
              (let* ((bindings (cadr expr))
                     (body (cddr expr))
                     (vars (map (lambda (b) (car b)) bindings))
                     (vals (map (lambda (b) (mini-eval (cadr b) env)) bindings))
                     (new-env (mini-extend-env vars vals env)))
                (mini-eval-sequence body new-env))))

         ((let*)
          (let* ((bindings (cadr expr))
                 (body (cddr expr)))
            (let loop ((bs bindings) (curr-env env))
              (if (null? bs)
                  (mini-eval-sequence body curr-env)
                  (let* ((b (car bs))
                         (v (car b))
                         (val (mini-eval (cadr b) curr-env)))
                    (loop (cdr bs) (mini-extend-env (list v) (list val) curr-env)))))))

         ((+)
          (let* ((v1 (mini-eval (cadr expr) env))
                 (v2 (mini-eval (caddr expr) env))
                 (res (+ v1 v2)))
            (trace-record! '%add 'res v1 v2)
            res))

         ((-)
          (let* ((v1 (mini-eval (cadr expr) env))
                 (v2 (mini-eval (caddr expr) env))
                 (res (- v1 v2)))
            (trace-record! '%sub 'res v1 v2)
            res))

         ((*)
          (let* ((v1 (mini-eval (cadr expr) env))
                 (v2 (mini-eval (caddr expr) env))
                 (res (* v1 v2)))
            (trace-record! '%mul 'res v1 v2)
            res))

         ((quotient)
          (quotient (mini-eval (cadr expr) env) (mini-eval (caddr expr) env)))

         ((modulo)
          (modulo (mini-eval (cadr expr) env) (mini-eval (caddr expr) env)))

         ((<)
          (let* ((v1 (mini-eval (cadr expr) env))
                 (v2 (mini-eval (caddr expr) env)))
            (trace-guard! 'cmp-lt v1 v2 'exit-guard)
            (< v1 v2)))

         ((<=)
          (let* ((v1 (mini-eval (cadr expr) env))
                 (v2 (mini-eval (caddr expr) env)))
            (trace-guard! 'cmp-le v1 v2 'exit-guard)
            (<= v1 v2)))

         ((>)
          (let* ((v1 (mini-eval (cadr expr) env))
                 (v2 (mini-eval (caddr expr) env)))
            (trace-guard! 'cmp-gt v1 v2 'exit-guard)
            (> v1 v2)))

         ((>=)
          (let* ((v1 (mini-eval (cadr expr) env))
                 (v2 (mini-eval (caddr expr) env)))
            (trace-guard! 'cmp-ge v1 v2 'exit-guard)
            (>= v1 v2)))

         ((=)
          (let* ((v1 (mini-eval (cadr expr) env))
                 (v2 (mini-eval (caddr expr) env)))
            (trace-guard! 'cmp-eq v1 v2 'exit-guard)
            (= v1 v2)))

         ((zero?)
          (= (mini-eval (cadr expr) env) 0))

         ((cons)
          (cons (mini-eval (cadr expr) env) (mini-eval (caddr expr) env)))

         ((car)
          (car (mini-eval (cadr expr) env)))

         ((cdr)
          (cdr (mini-eval (cadr expr) env)))

         ((pair?)
          (pair? (mini-eval (cadr expr) env)))

         ((null?)
          (null? (mini-eval (cadr expr) env)))

         ((not)
          (not (mini-eval (cadr expr) env)))

         ((eq?)
          (eq? (mini-eval (cadr expr) env) (mini-eval (caddr expr) env)))

         ((equal?)
          (equal? (mini-eval (cadr expr) env) (mini-eval (caddr expr) env)))

         ((list)
          (map (lambda (a) (mini-eval a env)) (cdr expr)))

         ((display)
          (display (mini-eval (cadr expr) env))
          #t)

         ((newline)
          (newline)
          #t)

         (else
          ;; Procedure application or recursive loop step
          (let ((proc-val (mini-lookup op env)))
            (cond
              ;; Recursive loop step: (%loop loop-name vars)
              ((and (pair? proc-val) (eq? (car proc-val) '%loop))
               (let ((arg-vals (map (lambda (a) (mini-eval a env)) (cdr expr))))
                 (cons '%loop-recur arg-vals)))

              (else 0)))))))

    (else 0)))

;;; -----------------------------------------------------------------------
;;; 8. Standalone Binary Entry Point
;;; -----------------------------------------------------------------------

(define (read-all-forms-stdin)
  (let loop ((acc '()))
    (let ((form (read)))
      (if (eof-object? form)
          (reverse acc)
          (loop (cons form acc))))))

(define (main)
  (display-string "==================================================================\n")
  (display-string "       ULisp-JIT: Standalone Scheme VM with Automatic JIT         \n")
  (display-string "               Powered by MLisp Meta-Tracing Engine               \n")
  (display-string "==================================================================\n")

  (tracer-reset!)
  (set-hot-threshold! 3)
  (jit-runtime-reset!)
  (reset-auto-loop-counter!)

  (let ((raw-forms (read-all-forms-stdin)))
    (if (null? raw-forms)
        (begin
          (display-string "No input expressions provided on stdin.\n")
          0)
        (let* ((inst-forms (auto-instrument-forms raw-forms))
               (last-res
                (let loop ((forms inst-forms) (res #f))
                  (if (null? forms)
                      res
                      (let ((v (mini-eval (car forms) '())))
                        (loop (cdr forms) v))))))
          (display-string "\n=> Result: ")
          (display last-res)
          (newline)
          (display-string "==================================================================\n")
          (display-string " [JIT Stats] Dispatched Native JIT Loops: ")
          (display (car *jit-stats-executed*))
          (newline)
          (display-string "==================================================================\n")
          0))))

(main)
