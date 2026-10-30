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

;;; Checks whether `var` escapes (appears in non-operator position) within `expr`.
(define (var-escapes? var expr)
  (cond
    ((symbol? expr)
     (eq? expr var))
    ((not (pair? expr))
     #f)
    (else
     (let ((op (car expr)))
       (case op
         ((quote) #f)
         ((if)
          (or (var-escapes? var (cadr expr))
              (var-escapes? var (caddr expr))
              (if (null? (cdddr expr)) #f (var-escapes? var (cadddr expr)))))
         ((begin)
          (let loop ((es (cdr expr)))
            (and (pair? es)
                 (or (var-escapes? var (car es))
                     (loop (cdr es))))))
         ((let)
          (let ((bindings (cadr expr))
                (body (caddr expr)))
            (or (let loop ((bs bindings))
                  (and (pair? bs)
                       (or (var-escapes? var (cadar bs))
                           (loop (cdr bs)))))
                (if (memq var (map car* bindings))
                    #f
                    (var-escapes? var body)))))
         ((letrec)
          (let ((bindings (cadr expr))
                (body (caddr expr)))
            (if (memq var (map car* bindings))
                #f
                (or (let loop ((bs bindings))
                      (and (pair? bs)
                           (or (var-escapes? var (cadar bs))
                               (loop (cdr bs)))))
                    (var-escapes? var body)))))
         ((lambda)
          (let ((params (cadr expr))
                (body (caddr expr)))
            (if (memq var params)
                #f
                (occurs-in? var body))))
         (else
          (if (eq? op var)
              (let loop ((as (cdr expr)))
                (and (pair? as)
                     (or (var-escapes? var (car as))
                         (loop (cdr as)))))
              (or (var-escapes? var op)
                  (let loop ((as (cdr expr)))
                    (and (pair? as)
                         (or (var-escapes? var (car as))
                             (loop (cdr as)))))))))))))

(define (binding-lambda? val)
  (and (pair? val) (eq? (car val) 'lambda)))

(define (known-fn-binding? var val rec-vars)
  (if (binding-lambda? val)
      (let* ((params (cadr val))
             (lbody (caddr val))
             (bound (append rec-vars params))
             (frees (free-vars-with-globals lbody bound)))
        (null? frees))
      #f))

;;; Variable environment lookup (linear alist, latest bindings shadow older ones)
(define (lookup-var var var-map)
  (let ((entry (assq var var-map)))
    (cond
      ((and entry (pair? (cdr entry)) (eq? (cadr entry) '%known-fn))
       ;; Known function referenced as first-class value: instantiate static closure
       (list '%make-closure-env (caddr entry)))
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
          (convert-let (cadr expr) (caddr expr) var-map))
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
          (let ((known-entry (and (symbol? op) (assq op var-map))))
            (cond
              ;; 1. Local known function via var-map (%known-fn label)
              ((and known-entry (pair? (cdr known-entry)) (eq? (cadr known-entry) '%known-fn))
               (let ((label (caddr known-entry))
                     (args (map (lambda (e) (convert-expr e var-map)) (cdr expr))))
                 (cons '%direct-call (cons label args))))
              ;; 2. Top-level known function or extern function
              ((and (symbol? op)
                    (not known-entry)
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
                        (map (lambda (e) (convert-expr e var-map)) (cdr expr))))))
              (else
               (cons (convert-expr op var-map)
                     (map (lambda (e) (convert-expr e var-map)) (cdr expr))))))))))))

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

;;; Convert let expression, identifying non-escaping lambdas as known functions
(define (convert-let bindings body var-map)
  (let* ((known-info
          (map (lambda (b)
                 (let ((var (car b)) (val (cadr b)))
                   (if (and (binding-lambda? val)
                            (null? (free-vars-with-globals (caddr val) (cadr val)))
                            (not (var-escapes? var body))
                            (not (var-escapes? var (caddr val))))
                       (let ((label (unique-label-sym (string-append "L_known_" (sanitize-label-str (symbol->string var))))))
                         (list var label val))
                       #f)))
               bindings))
         (known-env-entries
          (let loop ((kis known-info) (acc '()))
            (cond
              ((null? kis) (reverse acc))
              ((car kis)
               (let ((ki (car kis)))
                 (loop (cdr kis) (cons (cons (car ki) (list '%known-fn (cadr ki))) acc))))
              (else (loop (cdr kis) acc))))))
    ;; Lift each known function
    (let loop ((kis known-info))
      (if (pair? kis)
          (begin
            (if (car kis)
                (let* ((ki (car kis))
                       (label (cadr ki))
                       (val (caddr ki))
                       (params (cadr val))
                       (lbody (caddr val))
                       (inner-map (append (map (lambda (p) (cons p p)) params)
                                          (append known-env-entries var-map)))
                       (new-lbody (convert-expr lbody inner-map))
                       (fn-def (list '%function label params new-lbody)))
                  (if (unboxed-fn? (car ki))
                      (record-unboxed-fn! label))
                  (if (unboxed-ret-fn? (car ki))
                      (record-unboxed-ret-fn! label))
                  (add-lifted-function! fn-def)))
            (loop (cdr kis)))))
    ;; Prepare let-bindings for non-known bindings
    (let* ((normal-bindings
            (let loop ((bs bindings) (kis known-info) (acc '()))
              (cond
                ((null? bs) (reverse acc))
                ((not (car kis))
                 (let ((b (car bs)))
                   (loop (cdr bs) (cdr kis) (cons (list (car b) (convert-expr (cadr b) var-map)) acc))))
                (else
                 ;; Non-escaping known function: omit binding!
                 (loop (cdr bs) (cdr kis) acc)))))
           (body-var-map
            (let loop ((bs normal-bindings) (acc (append known-env-entries var-map)))
              (if (null? bs) acc
                  (let ((v (caar bs)))
                    (loop (cdr bs) (cons (cons v v) acc))))))
           (new-body (convert-expr body body-var-map)))
      (if (null? normal-bindings)
          new-body
          (list 'let normal-bindings new-body)))))

;;; ;;; Convert letrec expression into direct known function calls + %make-closure backpatching
(define (convert-letrec bindings body var-map)
  (let* ((rec-vars (map car* bindings))
         (rec-fn-vars (let loop ((bs bindings) (acc '()))
                        (if (null? bs) (reverse acc)
                            (let ((b (car bs)))
                              (if (binding-lambda? (cadr b))
                                  (loop (cdr bs) (cons (car b) acc))
                                  (loop (cdr bs) acc))))))
         ;; 1. Identify known functions: must be a closed lambda, and must NOT escape from body or any binding!
         (known-info
          (map (lambda (b)
                 (let ((var (car b)) (val (cadr b)))
                   (if (known-fn-binding? var val rec-fn-vars)
                       (let ((esc? (or (var-escapes? var body)
                                       (let loop ((bs bindings))
                                         (and (pair? bs)
                                              (or (let* ((other-b (car bs))
                                                         (other-var (car other-b))
                                                         (other-val (cadr other-b)))
                                                    (if (eq? other-var var)
                                                        (var-escapes? var (caddr other-val))
                                                        (if (binding-lambda? other-val)
                                                            (var-escapes? var (caddr other-val))
                                                            (occurs-in? var other-val))))
                                                  (loop (cdr bs))))))))
                         (if esc?
                             #f
                             (let ((label (unique-label-sym (string-append "L_known_" (sanitize-label-str (symbol->string var))))))
                               (list var label val))))
                       #f)))
               bindings))
         (known-env-entries
          (let loop ((kis known-info) (acc '()))
            (cond
              ((null? kis) (reverse acc))
              ((car kis)
               (let ((ki (car kis)))
                 (loop (cdr kis) (cons (cons (car ki) (list '%known-fn (cadr ki))) acc))))
              (else (loop (cdr kis) acc))))))
    ;; 2. Convert and lift each known function
    (let loop ((kis known-info))
      (if (pair? kis)
          (begin
            (if (car kis)
                (let* ((ki (car kis))
                       (label (cadr ki))
                       (val (caddr ki))
                       (params (cadr val))
                       (lbody (caddr val))
                       (inner-map
                        (append (map (lambda (p) (cons p p)) params)
                                (append known-env-entries var-map)))
                       (new-lbody (convert-expr lbody inner-map))
                       (fn-def (list '%function label params new-lbody)))
                  (if (unboxed-fn? (car ki))
                      (record-unboxed-fn! label))
                  (if (unboxed-ret-fn? (car ki))
                      (record-unboxed-ret-fn! label))
                  (add-lifted-function! fn-def)))
            (loop (cdr kis)))))
    ;; 3. Filter non-known bindings and process them with original closure conversion
    (let* ((non-known-bindings
            (let loop ((bs bindings) (kis known-info) (acc '()))
              (cond
                ((null? bs) (reverse acc))
                ((not (car kis))
                 (loop (cdr bs) (cdr kis) (cons (car bs) acc)))
                (else
                 (loop (cdr bs) (cdr kis) acc)))))
           (base-outer-var-map (append known-env-entries var-map)))
      (if (null? non-known-bindings)
          ;; Fast path: ALL bindings are known non-escaping functions! ZERO closures allocated!
          (convert-expr body base-outer-var-map)
          ;; Mixed or escaping path: standard closure conversion for non-known bindings
          (let* ((outer-var-map
                  (let loop ((rvs rec-vars) (acc base-outer-var-map))
                    (if (null? rvs) acc
                        (loop (cdr rvs) (cons (cons (car rvs) (car rvs)) acc)))))
                 (processed-bindings
                  (map (lambda (b)
                         (let ((var (car b)) (val (cadr b)))
                           (if (and (pair? val) (eq? (car val) 'lambda))
                               (let* ((params (cadr val))
                                      (lbody (caddr val))
                                      (bound (cons var params))
                                      (frees (free-vars-with-globals lbody bound))
                                      (label (unique-label-sym "L_lambda"))
                                      (env-p (map (lambda (p) (cons p p)) params))
                                      (env-s (cons (cons var '%self) env-p))
                                      (inner-var-map
                                       (let loop ((fs frees) (idx 1) (acc (append env-s known-env-entries)))
                                         (if (null? fs) acc
                                             (let ((fv (car fs)))
                                               (loop (cdr fs) (+ idx 1)
                                                     (cons (cons fv (list '%closure-ref '%self idx)) acc))))))
                                      (new-lbody (convert-expr lbody inner-var-map))
                                      (fn-def (list '%function label params new-lbody)))
                                 (add-lifted-function! fn-def)
                                 (let ((init-args
                                        (map (lambda (fv)
                                               (if (memq fv rec-vars) #f (convert-expr fv outer-var-map)))
                                             frees)))
                                   (list var (cons '%make-closure-env (cons label init-args)) frees)))
                               (list var (convert-expr val outer-var-map) '()))))
                       non-known-bindings))
                 (let-bindings
                  (map (lambda (pb) (list (car pb) (cadr pb))) processed-bindings))
                 (backpatches
                  (let loop-b ((pbs processed-bindings) (acc '()))
                    (if (null? pbs) (reverse acc)
                        (let* ((pb (car pbs))
                               (var (car pb))
                               (frees (caddr pb))
                               (patches
                                (let loop-f ((fs frees) (idx 1) (p-acc '()))
                                  (if (null? fs) (reverse p-acc)
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
                      (cons 'begin (append backpatches (list new-body))))))))))

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
