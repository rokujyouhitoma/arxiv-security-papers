;;; =======================================================================
;;; ULisp Compiler Pass 6b: TBAA & Escape Analysis Nanopass
;;; Conforms to DSN-33 Section 8.5 & Issue #525
;;; Based on Cornell CS 6120 (Lesson 10 Alias Analysis) & Bacon's Unified Theory
;;;
;;; Features:
;;; 1. Type-Based Alias Analysis (TBAA): Proves non-interference between
;;;    disjoint Scheme type heaps (Pair, Closure, Vector, Raw memory).
;;;    Enables Redundant Load Elimination (RLE) across stores of disjoint types.
;;; 2. Flow-Sensitive Escape Analysis: Identifies local non-escaping `cons`
;;;    and `%make-closure` instances and promotes them to stack-allocated objects
;;;    (`%stack-cons`, `%make-stack-closure`), completely bypassing heap bump allocation.
;;; =======================================================================

;;; -----------------------------------------------------------------------
;;; Part 1: Type-Based Alias Analysis (TBAA) & Redundant Load Elimination
;;; -----------------------------------------------------------------------

;;; Returns the TBAA type class of a memory expression
;;; Returns 'pair, 'closure, 'vector, 'raw, or 'unknown
(define (tbaa-type-class expr)
  (if (not (pair? expr))
      'unknown
      (case (car expr)
        ((annotate) (tbaa-type-class (caddr expr)))
        ((car cdr set-car! set-cdr!) 'pair)
        ((%closure-ref %closure-set!) 'closure)
        ((vector-ref vector-set!) 'vector)
        ((bytevector-u8-ref bytevector-u8-set!) 'bytevector)
        ((%raw-load %raw-store!) 'raw)
        (else 'unknown))))

;;; Predicate: Are two memory operations provably disjoint by type?
(define (tbaa-disjoint? t1 t2)
  (cond
    ((or (eq? t1 'unknown) (eq? t2 'unknown)) #f)
    ((eq? t1 t2) #f)
    (else #t)))

;;; Invalidate cached loads affected by a store expression
;;; If store is of type 'T, all cached loads of type 'T (or unknown) are invalidated,
;;; but cached loads of disjoint types are PRESERVED!
(define (tbaa-invalidate-loads store-expr avail-loads)
  (let ((st-type (tbaa-type-class store-expr)))
    (if (eq? st-type 'unknown)
        ;; Unknown store (e.g. arbitrary function call): conservative purge
        '()
        ;; Disjoint type store: retain all loads whose type class is disjoint
        (let loop ((loads avail-loads) (acc '()))
          (if (null? loads)
              (reverse acc)
              (let* ((entry (car loads))
                     (load-type (cadr entry)))
                (if (tbaa-disjoint? st-type load-type)
                    (loop (cdr loads) (cons entry acc))
                    (loop (cdr loads) acc))))))))

;;; Search for an available load matching (op target index/offset)
;;; Entry format: (load-expr type-class var-name)
(define (tbaa-find-load op-expr avail-loads)
  (let loop ((loads avail-loads))
    (if (null? loads)
        #f
        (let ((entry (car loads)))
          (if (equal? (car entry) op-expr)
              (caddr entry)
              (loop (cdr loads)))))))

;;; -----------------------------------------------------------------------
;;; Part 2: Flow-Sensitive Escape Analysis
;;; -----------------------------------------------------------------------

(define *stack-alloc-attr* (string->symbol ":stack-alloc"))

;;; Collect all variables that escape a given expression context
;;; An object escapes if:
;;; - It is returned from the function (in tail position)
;;; - It is passed as an argument to an external call (non-primitive / escaping op)
;;; - It is stored into another escaping data structure or global
(define (collect-escaped-vars expr is-tail)
  (cond
    ((symbol? expr)
     (if is-tail (list expr) '()))
    ((not (pair? expr))
     '())
    (else
     (let ((op (car expr)))
       (case op
         ((quote) '())
         ((annotate)
          (collect-escaped-vars (caddr expr) is-tail))
         ((if)
          (let ((test-esc (collect-escaped-vars (cadr expr) #f))
                (then-esc (collect-escaped-vars (caddr expr) is-tail))
                (else-esc (if (null? (cdddr expr))
                              '()
                              (collect-escaped-vars (cadddr expr) is-tail))))
            (append test-esc (append then-esc else-esc))))
         ((begin)
          (let loop ((es (cdr expr)) (acc '()))
            (if (null? es)
                acc
                (let ((tail? (and is-tail (null? (cdr es)))))
                  (loop (cdr es)
                        (append acc (collect-escaped-vars (car es) tail?)))))))
         ((let)
          (let* ((bindings (cadr expr))
                 (body (caddr expr))
                 (b-escs
                  (let loop ((bs bindings) (acc '()))
                    (if (null? bs) acc
                        (loop (cdr bs)
                              (append acc (collect-escaped-vars (cadar bs) #f))))))
                 (body-escs (collect-escaped-vars body is-tail)))
            (append b-escs body-escs)))
         ;; Safe local destructors: car, cdr, %closure-ref, null?, pair? do NOT cause target to escape
         ((car cdr null? pair? not zero? fixnum? integer? string? boolean?)
          (collect-escaped-vars (cadr expr) #f))
         ((%closure-ref)
          '())
         ((%global-ref)
          '())
         ((%direct-call)
          (let loop ((args (cddr expr)) (acc '()))
            (if (null? args) acc
                (let ((arg (car args)))
                  (loop (cdr args)
                        (if (symbol? arg)
                            (cons arg acc)
                            (append (collect-escaped-vars arg #f) acc)))))))
         ((%global-set!)
          (let ((stored-val (caddr expr)))
            (if (symbol? stored-val)
                (list stored-val)
                (collect-escaped-vars stored-val #f))))
         ;; Mutations: if storing a value into a heap object, the stored value escapes!
         ((set-car! set-cdr!)
          (let ((stored-val (caddr expr)))
            (if (symbol? stored-val)
                (cons stored-val (collect-escaped-vars (cadr expr) #f))
                (collect-escaped-vars stored-val #f))))
         ((vector-set!)
          (let ((stored-val (cadddr expr)))
            (if (symbol? stored-val)
                (cons stored-val (append (collect-escaped-vars (cadr expr) #f)
                                         (collect-escaped-vars (caddr expr) #f)))
                (append (collect-escaped-vars (cadr expr) #f)
                        (append (collect-escaped-vars (caddr expr) #f)
                                (collect-escaped-vars stored-val #f))))))
         ;; Standard function call or primitive: all arguments escape unless known safe
         (else
          (let ((args-esc
                 (let loop ((args (cdr expr)) (acc '()))
                   (if (null? args) acc
                       (let ((arg (car args)))
                         (loop (cdr args)
                               (if (symbol? arg)
                                   (cons arg acc)
                                   (append (collect-escaped-vars arg #f) acc))))))))
            (if (symbol? op)
                args-esc
                (append (collect-escaped-vars op #f) args-esc)))))))))

;;; -----------------------------------------------------------------------
;;; Part 3: AST Transformation (Stack Promotion & Redundant Load Elimination)
;;; -----------------------------------------------------------------------

(define (alias-escape-transform-expr expr escaped-set avail-loads)
  (cond
    ((not (pair? expr)) expr)
    (else
     (let ((op (car expr)))
       (case op
         ((quote) expr)
         ((annotate)
          (list 'annotate (cadr expr)
                (alias-escape-transform-expr (caddr expr) escaped-set avail-loads)))

         ;; TBAA Load: (car p), (cdr p), (%closure-ref c i)
         ((car cdr %closure-ref)
          (let ((cached-var (tbaa-find-load expr avail-loads)))
            (if cached-var
                cached-var
                (cons op (map (lambda (e) (alias-escape-transform-expr e escaped-set avail-loads))
                              (cdr expr))))))

         ;; TBAA Store: invalidates only non-disjoint types
         ((set-car! set-cdr! %closure-set! vector-set! bytevector-u8-set! %raw-store!)
          (cons op (map (lambda (e) (alias-escape-transform-expr e escaped-set avail-loads))
                        (cdr expr))))

         ((%direct-call)
          (cons '%direct-call
                (cons (cadr expr)
                      (map (lambda (e) (alias-escape-transform-expr e escaped-set avail-loads))
                           (cddr expr)))))

         ((%global-ref)
          expr)

         ((%global-set!)
          (list '%global-set! (cadr expr)
                (alias-escape-transform-expr (caddr expr) escaped-set avail-loads)))

         ((if)
          (let* ((test (alias-escape-transform-expr (cadr expr) escaped-set avail-loads))
                 (then (alias-escape-transform-expr (caddr expr) escaped-set avail-loads))
                 (else-part (if (null? (cdddr expr))
                                #f
                                (alias-escape-transform-expr (cadddr expr) escaped-set avail-loads))))
            (list 'if test then else-part)))

         ((begin)
          (let loop ((es (cdr expr)) (cur-loads avail-loads) (acc '()))
            (if (null? es)
                (cons 'begin (reverse acc))
                (let* ((e (car es))
                       (transformed (alias-escape-transform-expr e escaped-set cur-loads))
                       (next-loads
                        (if (and (pair? e) (memq (car e) '(set-car! set-cdr! %closure-set! vector-set! bytevector-u8-set! %raw-store!)))
                            (tbaa-invalidate-loads e cur-loads)
                            cur-loads)))
                  (loop (cdr es) next-loads (cons transformed acc))))))

         ((let)
          (let* ((bindings (cadr expr))
                 (body (caddr expr))
                 ;; Process bindings and detect Stack Allocations
                 (trans-bindings
                  (map
                   (lambda (b)
                     (let* ((var (car b))
                            (val (cadr b))
                            (escapes? (memq var escaped-set)))
                       (cond
                         ;; Non-escaping pair: promote to %stack-cons
                         ((and (not escapes?) (pair? val) (eq? (car val) 'cons))
                          (list var (cons '%stack-cons
                                          (map (lambda (e) (alias-escape-transform-expr e escaped-set avail-loads))
                                               (cdr val)))))
                         ;; Non-escaping %make-closure-env: promote to (annotate #:stack-alloc (%make-closure-env ...))
                         ((and (not escapes?) (pair? val) (eq? (car val) '%make-closure-env))
                          (list var (list 'annotate *stack-alloc-attr*
                                          (cons '%make-closure-env
                                                (map (lambda (e) (alias-escape-transform-expr e escaped-set avail-loads))
                                                     (cdr val))))))
                         ;; Non-escaping closure: promote to %make-stack-closure
                         ((and (not escapes?) (pair? val) (eq? (car val) '%make-closure))
                          (list var (cons '%make-stack-closure
                                          (map (lambda (e) (alias-escape-transform-expr e escaped-set avail-loads))
                                               (cdr val)))))
                         (else
                          (list var (alias-escape-transform-expr val escaped-set avail-loads))))))
                   bindings))
                 ;; Record available loads from bindings
                 (new-avail-loads
                  (let loop ((bs trans-bindings) (cur-loads avail-loads))
                    (if (null? bs) cur-loads
                        (let* ((b (car bs))
                               (v (car b))
                               (raw-rhs (cadr b))
                               (rhs (if (and (pair? raw-rhs) (eq? (car raw-rhs) 'annotate))
                                        (caddr raw-rhs)
                                        raw-rhs)))
                          (if (and (pair? rhs) (memq (car rhs) '(car cdr %closure-ref)))
                              (let ((tc (tbaa-type-class rhs)))
                                (loop (cdr bs) (cons (list rhs tc v) cur-loads)))
                              (loop (cdr bs) cur-loads))))))
                 (new-body (alias-escape-transform-expr body escaped-set new-avail-loads)))
            (list 'let trans-bindings new-body)))

         ((%cont-fun)
          (let* ((f-name (cadr expr))
                 (params (caddr expr))
                 (f-body (cadddr expr))
                 (in-body (cadr (cdddr expr)))
                 (f-esc (collect-escaped-vars f-body #t))
                 (new-f-body (alias-escape-transform-expr f-body f-esc avail-loads))
                 (new-in-body (alias-escape-transform-expr in-body escaped-set avail-loads)))
            (list '%cont-fun f-name params new-f-body new-in-body)))

         (else
          (cons (alias-escape-transform-expr op escaped-set avail-loads)
                (map (lambda (e) (alias-escape-transform-expr e escaped-set avail-loads))
                     (cdr expr)))))))))

;;; Optimize a single procedure or top-level expression
(define (alias-escape-optimize-function fn-def)
  (let* ((label (cadr fn-def))
         (params (caddr fn-def))
         (body (cadddr fn-def))
         (escaped-set (collect-escaped-vars body #t))
         (optimized-body (alias-escape-transform-expr body escaped-set '())))
    (list '%function label params optimized-body)))

;;; Pass 6b Main Entrypoint
;;; Input: (%program functions main-expr)
;;; Output: (%program optimized-functions optimized-main-expr)
(define (alias-escape-all program)
  (if (and (pair? program) (eq? (car program) '%program))
      (let* ((functions (cadr program))
             (main-expr (caddr program))
             (opt-functions (map alias-escape-optimize-function functions))
             (main-esc (collect-escaped-vars main-expr #t))
             (opt-main (alias-escape-transform-expr main-expr main-esc '())))
        (list '%program opt-functions opt-main))
      ;; Fallback if single expression
      (let ((esc (collect-escaped-vars program #t)))
        (alias-escape-transform-expr program esc '()))))
