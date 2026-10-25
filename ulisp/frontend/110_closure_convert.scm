;;; =======================================================================
;;; ULisp Compiler Pass 3: Explicit Closure Conversion Nanopass
;;; Conforms to DSN-33 Architecture Specification
;;; Note: Lifts nested lambdas to flat %function definitions, transforms
;;;       closure instantiation to %make-closure, free variable accesses
;;;       to %closure-ref, and mutual recursion (letrec) to %closure-set!.
;;; =======================================================================

;;; Boxed global accumulator for lambda-lifted procedure definitions
(define *lifted-functions* (cons '() '()))

(define (reset-lifted-functions!)
  (set-car! *lifted-functions* '()))

(define (add-lifted-function! fn)
  (set-car! *lifted-functions* (cons fn (car *lifted-functions*))))

;;; Top-level functions & variables registry for %direct-call optimization
(define *top-level-fns* (cons '() '()))   ; ((name . label) ...)
(define *top-level-vars* (cons '() '()))  ; (name ...)

(define (reset-top-level-env!)
  (set-car! *top-level-fns* '())
  (set-car! *top-level-vars* '()))

(define (free-vars-with-globals expr bound)
  (let ((top-bound (append (map car* (car *top-level-fns*)) (car *top-level-vars*))))
    (free-vars expr (set-union bound top-bound))))

;;; Variable environment lookup (linear alist, latest bindings shadow older ones)
(define (lookup-var var var-map)
  (let ((entry (assq var var-map)))
    (cond
      (entry (cdr entry))
      ((assq var (car *top-level-fns*))
       ;; Top-level function referenced as first-class value: instantiate static closure
       (list '%make-closure-env (cdr (assq var (car *top-level-fns*)))))
      ((memq var (car *top-level-vars*))
       ;; Top-level global variable reference
       (list '%global-ref var))
      ((lir-primitive? var)
       var)
      ((allow-extern-symbols?)
       ;; External reference fallback: treat as external global variable
       (list '%global-ref var))
      (else var))))

;;; Forward declarations / helpers for mutual recursion in closure conversion
(define (convert-expr expr var-map)
  (cond
    ((symbol? expr)
     (lookup-var expr var-map))
    ((not (pair? expr))
     expr)
    (else
     (let ((op (car expr)))
       (case op
         ((quote)
          expr)
         ((if)
          (let ((test (convert-expr (cadr expr) var-map))
                (then (convert-expr (caddr expr) var-map))
                (else-expr (if (null? (cdddr expr))
                               #f
                               (convert-expr (cadddr expr) var-map))))
            (list 'if test then else-expr)))
         ((begin)
          (cons 'begin (map (lambda (e) (convert-expr e var-map)) (cdr expr))))
         ((let)
          (let* ((bindings (cadr expr))
                 (body (caddr expr))
                 (new-bindings
                  (map (lambda (b)
                         (list (car b) (convert-expr (cadr b) var-map)))
                       bindings))
                 ;; Shadow let-bound variables in body by pushing identity mappings
                 (body-var-map
                  (let loop ((bs bindings) (acc var-map))
                    (if (null? bs) acc
                        (let ((v (caar bs)))
                          (loop (cdr bs) (cons (cons v v) acc))))))
                 (new-body (convert-expr body body-var-map)))
            (list 'let new-bindings new-body)))
         ((letrec)
          (convert-letrec (cadr expr) (caddr expr) var-map))
         ((%cont-fun)
          (let* ((f-name (cadr expr))
                 (params (caddr expr))
                 (f-body (cadddr expr))
                 (in-body (cadr (cdddr expr)))
                 (lbody-map
                  (let loop ((ps params) (acc var-map))
                    (if (null? ps) acc
                        (loop (cdr ps) (cons (cons (car ps) (car ps)) acc)))))
                 (new-f-body (convert-expr f-body lbody-map))
                 (new-in-body (convert-expr in-body var-map)))
            (list '%cont-fun f-name params new-f-body new-in-body)))
         ((%cont-call)
          (cons '%cont-call
                (cons (cadr expr)
                      (map (lambda (e) (convert-expr e var-map)) (cddr expr)))))
         ((%with-handler)
          (list '%with-handler
                (convert-expr (cadr expr) var-map)
                (convert-expr (caddr expr) var-map)))
         ((%raw-call/cc)
          (list '%raw-call/cc
                (convert-expr (cadr expr) var-map)))
         ((%call-with-values)
          (list '%call-with-values
                (convert-expr (cadr expr) var-map)
                (convert-expr (caddr expr) var-map)))
         ((%values)
          (cons '%values
                (map (lambda (e) (convert-expr e var-map)) (cdr expr))))
         ((%make-closure %make-closure-env)
          (cons op (cons (cadr expr) (map (lambda (e) (convert-expr e var-map)) (cddr expr)))))
         ((lambda)
          (convert-lambda #f (cadr expr) (caddr expr) var-map))
         (else
          (if (and (symbol? op)
                   (not (assq op var-map))
                   (not (lir-primitive? op)))
              (cond
                ((assq op (car *top-level-fns*))
                 (let ((label (cdr (assq op (car *top-level-fns*))))
                       (args (map (lambda (e) (convert-expr e var-map)) (cdr expr))))
                   (cons '%direct-call (cons label args))))
                ((allow-extern-symbols?)
                 (let ((label (mangle-fn-label op))
                       (args (map (lambda (e) (convert-expr e var-map)) (cdr expr))))
                   (cons '%direct-call (cons label args))))
                (else
                 (cons (convert-expr op var-map)
                       (map (lambda (e) (convert-expr e var-map)) (cdr expr)))))
              (cons (convert-expr op var-map)
                    (map (lambda (e) (convert-expr e var-map)) (cdr expr))))))))))

;;; Convert a lambda expression, lift it as a top-level %function, and return %make-closure
(define (convert-lambda self-name params body var-map)
  (let* ((bound-vars (if self-name (cons self-name params) params))
         (frees (free-vars-with-globals body bound-vars))
         (label (unique-label-sym "L_lambda"))
         ;; Build callee inner var-map:
         ;; 1. Params shadow outer bindings (map to themselves)
         (env-p (let loop ((ps params) (acc '()))
                  (if (null? ps) acc
                      (loop (cdr ps) (cons (cons (car ps) (car ps)) acc)))))
         ;; 2. Self name (if recursive) maps to %self
         (env-s (if self-name
                    (cons (cons self-name '%self) env-p)
                    env-p))
         ;; 3. Free variables map to (%closure-ref %self idx)
         (inner-var-map
          (let loop ((fs frees) (idx 1) (acc env-s))
            (if (null? fs)
                acc
                (let ((fv (car fs)))
                  (loop (cdr fs) (+ idx 1)
                        (cons (cons fv (list '%closure-ref '%self idx)) acc))))))
         (new-body (convert-expr body inner-var-map))
         (fn-def (list '%function label params new-body)))
    (add-lifted-function! fn-def)
    ;; Instantiation expression: (%make-closure-env 'label captured-args...)
    (let ((captured-args
           (map (lambda (fv) (convert-expr fv var-map)) frees)))
      (cons '%make-closure-env (cons label captured-args)))))

;;; Convert letrec expression into let + %make-closure + backpatching %closure-set!
(define (convert-letrec bindings body var-map)
  (let* ((rec-vars (map car* bindings))
         ;; Shadow rec-vars in outer-var-map by binding them to themselves
         (outer-var-map
          (let loop ((rvs rec-vars) (acc var-map))
            (if (null? rvs) acc
                (loop (cdr rvs) (cons (cons (car rvs) (car rvs)) acc)))))
         (processed-bindings
          (map (lambda (b)
                 (let ((var (car b))
                       (val (cadr b)))
                   (if (and (pair? val) (eq? (car val) 'lambda))
                       (let* ((params (cadr val))
                              (lbody (caddr val))
                              (bound (cons var params))
                              (frees (free-vars-with-globals lbody bound))
                              (label (unique-label-sym "L_lambda"))
                              ;; Callee inner environment:
                              ;; Params map to themselves
                              (env-p (let loop ((ps params) (acc '()))
                                       (if (null? ps) acc
                                           (loop (cdr ps) (cons (cons (car ps) (car ps)) acc)))))
                              ;; Self-name maps to %self
                              (env-s (cons (cons var '%self) env-p))
                              ;; Free variables map to (%closure-ref %self idx)
                              (inner-var-map
                               (let loop ((fs frees) (idx 1) (acc env-s))
                                 (if (null? fs) acc
                                     (let ((fv (car fs)))
                                       (loop (cdr fs) (+ idx 1)
                                             (cons (cons fv (list '%closure-ref '%self idx)) acc))))))
                              (new-lbody (convert-expr lbody inner-var-map))
                              (fn-def (list '%function label params new-lbody)))
                         (add-lifted-function! fn-def)
                         (let ((init-args
                                (map (lambda (fv)
                                       (if (memq fv rec-vars)
                                           #f
                                           (convert-expr fv outer-var-map)))
                                     frees)))
                           (list var
                                 (cons '%make-closure-env (cons label init-args))
                                 frees)))
                       (list var (convert-expr val outer-var-map) '()))))
               bindings))
         (let-bindings
          (map (lambda (pb) (list (car pb) (cadr pb))) processed-bindings))
         (backpatches
          (let loop-b ((pbs processed-bindings) (acc '()))
            (if (null? pbs)
                (reverse acc)
                (let* ((pb (car pbs))
                       (var (car pb))
                       (frees (caddr pb))
                       (patches
                        (let loop-f ((fs frees) (idx 1) (p-acc '()))
                          (if (null? fs)
                              (reverse p-acc)
                              (let ((fv (car fs)))
                                (if (memq fv rec-vars)
                                    (loop-f (cdr fs) (+ idx 1)
                                            (cons (list '%closure-set! var idx fv) p-acc))
                                    (loop-f (cdr fs) (+ idx 1) p-acc)))))))
                  (loop-b (cdr pbs) (append (reverse patches) acc))))))
         (new-body (convert-expr body outer-var-map)))
    (if (null? backpatches)
        (list 'let let-bindings new-body)
        (list 'let let-bindings
              (cons 'begin (append backpatches (list new-body)))))))

;;; Pass 5 Entrypoint: Takes Canonical Core AST or (%program defs main-expr), returns (%program functions main-expr)
(define (closure-convert ast)
  (reset-lifted-functions!)
  (reset-top-level-env!)
  (let ((res
         (if (and (pair? ast) (eq? (car ast) '%program))
             (let* ((defs (cadr ast))
                    (main-expr (caddr ast)))
               ;; 1. Scan defs and populate *top-level-fns* and *top-level-vars*
               (let loop ((ds defs))
                 (if (pair? ds)
                     (begin
                       (let ((d (car ds)))
                         (if (and (pair? d) (eq? (car d) 'define))
                             (let ((name (cadr d))
                                   (val (caddr d)))
                               (if (and (pair? val) (eq? (car val) 'lambda))
                                   (if (not (assq name (car *top-level-fns*)))
                                       (let ((label (mangle-fn-label name)))
                                         (set-car! *top-level-fns* (cons (cons name label) (car *top-level-fns*)))))
                                   (if (not (memq name (car *top-level-vars*)))
                                       (set-car! *top-level-vars* (cons name (car *top-level-vars*))))))))
                       (loop (cdr ds)))))
               ;; 2. Convert each top-level function and add to lifted-functions
               (let loop ((ds defs))
                 (if (pair? ds)
                     (begin
                       (let ((d (car ds)))
                         (if (and (pair? d) (eq? (car d) 'define))
                             (let ((name (cadr d))
                                   (val (caddr d)))
                               (if (and (pair? val) (eq? (car val) 'lambda))
                                   (let* ((label (cdr (assq name (car *top-level-fns*))))
                                          (params (cadr val))
                                          (lbody (caddr val))
                                          (inner-map (map (lambda (p) (cons p p)) params))
                                          (new-body (convert-expr lbody inner-map))
                                          (fn-def (list '%function label params new-body)))
                                     (add-lifted-function! fn-def))))))
                       (loop (cdr ds)))))
               ;; 3. Convert variable inits and main-expr
               (let* ((inits (let loop ((ds defs) (acc '()))
                               (if (null? ds)
                                   (reverse acc)
                                   (let ((d (car ds)))
                                     (if (and (pair? d) (eq? (car d) 'define) (not (assq (cadr d) (car *top-level-fns*))))
                                         (loop (cdr ds) (cons (list '%global-set! (cadr d) (convert-expr (caddr d) '())) acc))
                                         (loop (cdr ds) acc))))))
                      (conv-main (convert-expr main-expr '()))
                      (final-main (if (null? inits) conv-main (cons 'begin (append inits (list conv-main))))))
                 (list '%program (reverse (car *lifted-functions*)) final-main)))
             (let ((main-expr (convert-expr ast '())))
               (list '%program (reverse (car *lifted-functions*)) main-expr)))))
    (if (and (verifier-enabled?) (assq 'L_lifted (nanopass-get-languages)))
        (if (not (nanopass-ast-valid? 'L_lifted res))
            (verifier-error 'closure "Pass 110 output violates L_lifted schema invariants" res)))
    res))
