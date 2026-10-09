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

;;; Variable environment lookup (linear alist, latest bindings shadow older ones)
(define (lookup-var var var-map)
  (let ((entry (assq var var-map)))
    (if entry (cdr entry) var)))

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
          (let ((datum (cadr expr)))
            (cond
              ((symbol? datum)
               (convert-expr (list 'string->symbol (symbol->string datum)) var-map))
              ((and (pair? datum) (has-symbol? datum))
               (convert-expr (list 'cons
                                   (list 'quote (car datum))
                                   (list 'quote (cdr datum)))
                             var-map))
              (else
               expr))))
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
         ((lambda)
          (convert-lambda #f (cadr expr) (caddr expr) var-map))
         (else
          (cons (convert-expr op var-map)
                (map (lambda (e) (convert-expr e var-map)) (cdr expr)))))))))

;;; Convert a lambda expression, lift it as a top-level %function, and return %make-closure
(define (convert-lambda self-name params body var-map)
  (let* ((bound-vars (if self-name (cons self-name params) params))
         (frees (free-vars body bound-vars))
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
    ;; Instantiation expression: (%make-closure 'label captured-args...)
    (let ((captured-args
           (map (lambda (fv) (convert-expr fv var-map)) frees)))
      (cons '%make-closure (cons label captured-args)))))

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
                              (frees (free-vars lbody bound))
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
                                 (cons '%make-closure (cons label init-args))
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

;;; Pass 3 Entrypoint: Takes Canonical Core AST, returns (%program functions main-expr)
(define (closure-convert ast)
  (reset-lifted-functions!)
  (let ((main-expr (convert-expr ast '())))
    (list '%program (reverse (car *lifted-functions*)) main-expr)))
