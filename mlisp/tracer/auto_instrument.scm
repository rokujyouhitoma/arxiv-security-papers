;;; =======================================================================
;;; MLisp Auto-Instrumentation Pass: auto_instrument.scm
;;; Conforms to DSN-34 & Issue #510
;;;
;;; 100% Pure Scheme Automatic JIT Instrumentation for Scheme AST.
;;; Automatically detects loop structures (Named let, tail-recursive define)
;;; and transparently injects (jit-merge-point ...) without requiring any
;;; modifications to the user's Scheme source code (Zero-Invasive).
;;; =======================================================================

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

;;; Helper: check if a list of expressions already begins with jit-merge-point
(define (already-instrumented? body)
  (and (pair? body)
       (pair? (car body))
       (eq? (caar body) 'jit-merge-point)))

;;; Helper: get the last element of a non-empty list
(define (last-element ls)
  (if (null? (cdr ls))
      (car ls)
      (last-element (cdr ls))))

;;; Helper: determine if target-name is called in tail position within expr
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
         ;; Named let: recursive calls to target-name could be inside its body
         (let ((body (cdddr expr)))
           (and (pair? body)
                (tail-calls? (last-element body) target-name)))
         ;; Standard let/let*/letrec: check tail expression of body
         (let ((body (cddr expr)))
           (and (pair? body)
                (tail-calls? (last-element body) target-name)))))
    (else #f)))

;;; Extract variables from a let-binding list: ((var val) ...) -> (var ...)
(define (extract-binding-vars bindings)
  (if (null? bindings)
      '()
      (let ((b (car bindings)))
        (cons (if (pair? b) (car b) b)
              (extract-binding-vars (cdr bindings))))))

;;; =======================================================================
;;; Primary Recursive AST Transformer
;;; =======================================================================

(define (auto-instrument-form form)
  (cond
    ;; Atoms and non-pairs are returned unchanged
    ((not (pair? form)) form)

    ;; Quoted forms are literal constants
    ((eq? (car form) 'quote) form)

    ;; -------------------------------------------------------------------
    ;; Case 1: Named let (Loop Pattern A)
    ;; Syntax: (let loop-name ((var init) ...) body ...)
    ;; -------------------------------------------------------------------
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
            (inst-body (map auto-instrument-form raw-body)))
       (if (already-instrumented? inst-body)
           ;; Already has jit-merge-point (idempotent)
           `(let ,loop-name ,inst-bindings ,@inst-body)
           ;; Inject automatic jit-merge-point
           (let ((tag (next-auto-loop-tag loop-name)))
             `(let ,loop-name ,inst-bindings
                (jit-merge-point ',tag (list ,@vars))
                ,@inst-body)))))

    ;; -------------------------------------------------------------------
    ;; Case 2: Standard let / let* / letrec
    ;; -------------------------------------------------------------------
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
            (inst-body (map auto-instrument-form raw-body)))
       `(,op ,inst-bindings ,@inst-body)))

    ;; -------------------------------------------------------------------
    ;; Case 3: define with function syntax (Tail-recursive Pattern B)
    ;; Syntax: (define (func-name params...) body...)
    ;; -------------------------------------------------------------------
    ((and (eq? (car form) 'define)
          (pair? (cdr form))
          (pair? (cadr form))
          (symbol? (caadr form)))
     (let* ((func-name (caadr form))
            (params (cdadr form))
            (raw-body (cddr form))
            (inst-body (map auto-instrument-form raw-body))
            (is-tail-rec? (tail-calls? (if (= (length raw-body) 1)
                                           (car raw-body)
                                           (cons 'begin raw-body))
                                       func-name)))
       (if (and is-tail-rec? (not (already-instrumented? inst-body)))
           ;; Tail-recursive loop detected! Inject jit-merge-point
           `(define (,func-name ,@params)
              (jit-merge-point ',func-name (list ,@params))
              ,@inst-body)
           ;; Standard non-recursive or already instrumented function
           `(define (,func-name ,@params) ,@inst-body))))

    ;; -------------------------------------------------------------------
    ;; Case 4: lambda abstraction
    ;; -------------------------------------------------------------------
    ((eq? (car form) 'lambda)
     (let ((params (cadr form))
           (body (cddr form)))
       `(lambda ,params ,@(map auto-instrument-form body))))

    ;; -------------------------------------------------------------------
    ;; Case 5: conditionals (if, cond)
    ;; -------------------------------------------------------------------
    ((eq? (car form) 'if)
     (let ((test (auto-instrument-form (cadr form)))
           (then (auto-instrument-form (caddr form)))
           (else (if (pair? (cdddr form))
                     (list (auto-instrument-form (cadddr form)))
                     '())))
       `(if ,test ,then ,@else)))

    ((eq? (car form) 'cond)
     (let ((clauses
            (map (lambda (cl)
                   (cons (auto-instrument-form (car cl))
                         (map auto-instrument-form (cdr cl))))
                 (cdr form))))
       `(cond ,@clauses)))

    ;; -------------------------------------------------------------------
    ;; Case 6: sequencing and assignment (begin, set!)
    ;; -------------------------------------------------------------------
    ((eq? (car form) 'begin)
     `(begin ,@(map auto-instrument-form (cdr form))))

    ((eq? (car form) 'set!)
     `(set! ,(cadr form) ,(auto-instrument-form (caddr form))))

    ;; -------------------------------------------------------------------
    ;; Case 7: standard application or other form
    ;; -------------------------------------------------------------------
    (else
     (map auto-instrument-form form))))

;;; Batch transform a list of top-level S-expressions
(define (auto-instrument-forms forms)
  (map auto-instrument-form forms))
