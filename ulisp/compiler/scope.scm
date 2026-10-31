;;; =======================================================================
;;; ULisp Compiler: Unified Lexical Scope & Alpha-Conversion Engine (Pass 035)
;;; Conforms to DSN-33 Architecture Specification & Issue #600
;;; Guarantees Barendregt Variable Convention (globally unique bound variables)
;;; and performs early deterministic detection of unbound variables.
;;; =======================================================================

;;; -----------------------------------------------------------------------
;;; Part 1: Scope Tree Data Structure & Lexical Contour Navigation
;;; -----------------------------------------------------------------------

;;; Scope node representation:
;;;   (list 'scope-node parent kind bindings-cell free-vars-cell children-cell)
;;;
;;; Fields:
;;;   - parent: enclosing scope-node or #f (for root/top-level)
;;;   - kind: symbol ('top-level, 'lambda, 'let, 'letrec, '%cont-fun)
;;;   - bindings-cell: (cons bindings '()) where bindings is ((orig-sym . alpha-sym) ...)
;;;   - free-vars-cell: (cons free-vars '()) where free-vars is (sym ...)
;;;   - children-cell: (cons children '()) where children is (scope-node ...)

(define (make-scope-node parent kind)
  (list 'scope-node parent kind (cons '() '()) (cons '() '()) (cons '() '())))

(define (scope-node? obj)
  (and (pair? obj) (eq? (car obj) 'scope-node)))

(define (scope-node-parent node)
  (cadr node))

(define (scope-node-kind node)
  (caddr node))

(define (scope-node-bindings-cell node)
  (cadddr node))

(define (scope-node-bindings node)
  (car (scope-node-bindings-cell node)))

(define (scope-node-free-vars-cell node)
  (car (cddddr node)))

(define (scope-node-free-vars node)
  (car (scope-node-free-vars-cell node)))

(define (scope-node-children-cell node)
  (cadr (cddddr node)))

(define (scope-node-children node)
  (car (scope-node-children-cell node)))

(define (scope-enter parent kind)
  (let ((child (make-scope-node parent kind)))
    (if (scope-node? parent)
        (let ((cc (scope-node-children-cell parent)))
          (set-car! cc (append (car cc) (list child)))))
    child))

(define (scope-bind! node orig-sym alpha-sym)
  (let ((bc (scope-node-bindings-cell node)))
    (set-car! bc (cons (cons orig-sym alpha-sym) (car bc)))))

(define (scope-lookup-local node orig-sym)
  (let ((entry (assq orig-sym (scope-node-bindings node))))
    (if entry
        (cdr entry)
        #f)))

(define (scope-lookup-lexical node orig-sym)
  (if (not (scope-node? node))
      #f
      (let ((entry (assq orig-sym (scope-node-bindings node))))
        (if entry
            (cons node (cdr entry))
            (scope-lookup-lexical (scope-node-parent node) orig-sym)))))

(define (scope-lookup node orig-sym)
  (let ((res (scope-lookup-lexical node orig-sym)))
    (if res
        (cdr res)
        #f)))

(define (scope-record-free-var! node sym)
  (if (scope-node? node)
      (let ((fc (scope-node-free-vars-cell node)))
        (if (not (memq sym (car fc)))
            (set-car! fc (cons sym (car fc)))))))

;;; -----------------------------------------------------------------------
;;; Part 2: Deterministic Alpha Symbol Generator
;;; -----------------------------------------------------------------------

(define *alpha-symbol-counter* (cons 0 '()))

(define (reset-alpha-symbol-counter!)
  (set-car! *alpha-symbol-counter* 0))

(define (alpha-next-id!)
  (let ((c (car *alpha-symbol-counter*)))
    (set-car! *alpha-symbol-counter* (+ c 1))
    c))

(define (make-alpha-symbol orig-sym)
  (let* ((orig-str (symbol->string orig-sym))
         (id (alpha-next-id!))
         (new-str (string-append orig-str "$" (number->string id))))
    (string->symbol new-str)))

;;; -----------------------------------------------------------------------
;;; Part 3: Known Primitives, Runtime Built-ins & Global Definitions
;;; -----------------------------------------------------------------------

(define *scope-runtime-special-forms*
  '(quote if begin set! lambda let letrec
    %make-closure %make-closure-env %closure-ref %closure-set!
    %cont-fun %cont-call %with-handler %raw-call/cc %call-with-values
    %values %program define define-values define-record-type))

(define (scope-special-form? sym)
  (if (memq sym *scope-runtime-special-forms*) #t #f))

(define *scope-standard-builtins*
  '(+ - * / = < <= > >= modulo quotient remainder abs
    zero? not eq? eqv? equal? pair? null? boolean? char?
    string? vector? bytevector? procedure? symbol? number?
    integer? exact? inexact? real? rational? complex?
    fixnum? exact-integer? list?
    car cdr set-car! set-cdr! caar cadr cdar cddr caaar caadr cadar caddr cdaar cdadr cddar cdddr
    cons list append reverse length memq assq
    make-string string-length string-ref string-set! string-copy string-copy! string-fill! string-append
    string=? string<? string>? string<=? string>=?
    string-ci=? string-ci<? string-ci>? string-ci<=? string-ci>=?
    string-upcase string-downcase string-foldcase
    char=? char<? char>? char<=? char>=?
    char-ci=? char-ci<? char-ci>? char-ci<=? char-ci>=?
    char-alphabetic? char-numeric? char-whitespace? char-upper-case? char-lower-case?
    digit-value char-upcase char-downcase char-foldcase
    make-vector vector-length vector-ref vector-set! vector-copy vector-copy! vector-fill! vector-append
    vector->list list->vector string->list list->string
    make-bytevector bytevector-length bytevector-u8-ref bytevector-u8-set! bytevector-copy bytevector-copy! bytevector-append
    write-char read-char peek-char write-string display newline write read error raise
    call-with-values values call/cc dynamic-wind
    open-input-file flush-output-port eof-object eof-object?
    power-assert-report dump-lir-unbound-variable-diagnostic
    %raw-load %raw-load-u8 %raw-store! %raw-syscall %raw-add %raw-sub %raw-mul %raw-cmp
    %ptr-add %ptr-tag %ptr-untag %ptr-tag-add %to-raw %to-fixnum %box-fixnum %unbox-fixnum
    %num-args %get-rsp %get-heap-ptr %get-heap-limit-ptr %get-gc-state-ptr %get-environ-ptr %get-stackmap-table
    %memory-fence %atomic-cas!))

(define (scope-primitive-symbol? sym)
  (or (scope-special-form? sym)
      (if (memq sym *scope-standard-builtins*) #t #f)
      (zero-arg-prim? sym)
      (unary-prim? sym)
      (binop-prim? sym)
      (triop-prim? sym)
      (septop-prim? sym)
      (closure-prim? sym)
      (pure-prim? sym)
      ;; Any low-level compiler internal symbol starting with '%' is treated as a runtime builtin
      (let ((s (symbol->string sym)))
        (and (> (string-length s) 0)
             (char=? (string-ref s 0) #\%)))))

(define (collect-top-level-defines defs)
  (let loop ((ds defs) (acc '()))
    (if (null? ds)
        (reverse acc)
        (let ((d (car ds)))
          (cond
            ((and (pair? d) (eq? (car d) 'define) (pair? (cdr d)))
             (let ((spec (cadr d)))
               (if (pair? spec)
                   (loop (cdr ds) (cons (car spec) acc))
                   (loop (cdr ds) (cons spec acc)))))
            ((and (pair? d) (eq? (car d) 'define-values) (pair? (cdr d)))
             (let ((formals (cadr d)))
               (if (list? formals)
                   (loop (cdr ds) (append (reverse formals) acc))
                   (loop (cdr ds) acc))))
            (else
             (loop (cdr ds) acc)))))))

(define (scope-known-global-or-prim? sym globals)
  (or (if (memq sym globals) #t #f)
      (scope-primitive-symbol? sym)))

;;; -----------------------------------------------------------------------
;;; Part 4: Early Unbound Variable Detection
;;; -----------------------------------------------------------------------

(define *scope-unbound-vars* (cons '() '()))
(define *scope-strict-unbound-check* (cons #f '()))

(define (reset-scope-unbound-vars!)
  (set-car! *scope-unbound-vars* '()))

(define (record-scope-unbound-var! var context)
  (if (not (memq var (car *scope-unbound-vars*)))
      (set-car! *scope-unbound-vars* (cons var (car *scope-unbound-vars*)))))

(define (get-scope-unbound-vars)
  (reverse (car *scope-unbound-vars*)))

(define (set-scope-strict-unbound-check! bool)
  (set-car! *scope-strict-unbound-check* bool))

(define (scope-strict-unbound-check?)
  (car *scope-strict-unbound-check*))

;;; -----------------------------------------------------------------------
;;; Part 5: Alpha-Conversion Engine (Barendregt Variable Normalization)
;;; -----------------------------------------------------------------------

(define (alpha-convert-list es scope globals)
  (let loop ((rest es) (acc '()))
    (if (null? rest)
        (reverse acc)
        (loop (cdr rest) (cons (alpha-convert-expr (car rest) scope globals) acc)))))

(define (alpha-convert-expr expr scope globals)
  (cond
    ;; 1. Literal Quote: datum inside (quote ...) is preserved verbatim
    ((and (pair? expr) (eq? (car expr) 'quote))
     expr)

    ;; 2. Atomic Symbol: Variable reference
    ((symbol? expr)
     (let ((alpha-sym (scope-lookup scope expr)))
       (cond
         (alpha-sym
          ;; Propagate free-variable usage up the lexical contour tree
          (let propagate ((curr scope))
            (if (and (scope-node? curr)
                     (not (scope-lookup-local curr expr)))
                (begin
                  (scope-record-free-var! curr expr)
                  (propagate (scope-node-parent curr)))))
          alpha-sym)
         ((scope-known-global-or-prim? expr globals)
          expr)
         (else
          (record-scope-unbound-var! expr scope)
          (if (scope-strict-unbound-check?)
              (error (string-append "Static Scope Error: Unbound variable '" (symbol->string expr) "'") expr)
              expr)))))

    ;; 3. Non-symbol atomics (numbers, booleans, chars, strings, null)
    ((not (pair? expr))
     expr)

    ;; 4. Composite Forms
    (else
     (let ((op (car expr)))
       (case op
         ;; 4.1 Conditional: (if test then [else])
         ((if)
          (let ((test (alpha-convert-expr (cadr expr) scope globals))
                (then (alpha-convert-expr (caddr expr) scope globals))
                (else-expr (if (null? (cdddr expr))
                               #f
                               (alpha-convert-expr (cadddr expr) scope globals))))
            (if (null? (cdddr expr))
                (list 'if test then)
                (list 'if test then else-expr))))

         ;; 4.2 Sequencing: (begin e ...)
         ((begin)
          (cons 'begin (alpha-convert-list (cdr expr) scope globals)))

         ;; 4.3 Assignment: (set! var val)
         ((set!)
          (let* ((var (cadr expr))
                 (val (alpha-convert-expr (caddr expr) scope globals))
                 (alpha-var (scope-lookup scope var)))
            (if alpha-var
                (list 'set! alpha-var val)
                (if (scope-known-global-or-prim? var globals)
                    (list 'set! var val)
                    (begin
                      (record-scope-unbound-var! var scope)
                      (if (scope-strict-unbound-check?)
                          (error (string-append "Static Scope Error: Unbound variable in set! '" (symbol->string var) "'") var)
                          (list 'set! var val)))))))

         ;; 4.4 Abstraction: (lambda (params ...) body)
         ((lambda)
          (let* ((params (cadr expr))
                 (body (caddr expr))
                 (child-scope (scope-enter scope 'lambda))
                 (alpha-params
                  (let loop ((ps params) (acc '()))
                    (if (null? ps)
                        (reverse acc)
                        (let* ((p (car ps))
                               (a-p (make-alpha-symbol p)))
                          (scope-bind! child-scope p a-p)
                          (loop (cdr ps) (cons a-p acc))))))
                 (converted-body (alpha-convert-expr body child-scope globals)))
            (list 'lambda alpha-params converted-body)))

         ;; 4.5 Local Binding: (let ((var expr) ...) body)
         ((let)
          (let* ((bindings (cadr expr))
                 (body (caddr expr))
                 ;; Binding RHS expressions are evaluated in the outer scope
                 (converted-rhs
                  (let loop ((bs bindings) (acc '()))
                    (if (null? bs)
                        (reverse acc)
                        (let* ((b (car bs))
                               (v (cadr b)))
                          (loop (cdr bs) (cons (alpha-convert-expr v scope globals) acc))))))
                 ;; Body is evaluated in the new child scope with alpha variables
                 (child-scope (scope-enter scope 'let))
                 (alpha-vars
                  (let loop ((bs bindings) (acc '()))
                    (if (null? bs)
                        (reverse acc)
                        (let* ((b (car bs))
                               (k (car b))
                               (a-k (make-alpha-symbol k)))
                          (scope-bind! child-scope k a-k)
                          (loop (cdr bs) (cons a-k acc))))))
                 (new-bindings
                  (let loop ((vars alpha-vars) (vals converted-rhs) (acc '()))
                    (if (null? vars)
                        (reverse acc)
                        (loop (cdr vars) (cdr vals) (cons (list (car vars) (car vals)) acc)))))
                 (converted-body (alpha-convert-expr body child-scope globals)))
            (list 'let new-bindings converted-body)))

         ;; 4.6 Recursive Binding: (letrec ((var expr) ...) body)
         ((letrec)
          (let* ((bindings (cadr expr))
                 (body (caddr expr))
                 (child-scope (scope-enter scope 'letrec))
                 ;; All variables are bound in child-scope prior to RHS conversion
                 (alpha-vars
                  (let loop ((bs bindings) (acc '()))
                    (if (null? bs)
                        (reverse acc)
                        (let* ((b (car bs))
                               (k (car b))
                               (a-k (make-alpha-symbol k)))
                          (scope-bind! child-scope k a-k)
                          (loop (cdr bs) (cons a-k acc))))))
                 (converted-rhs
                  (let loop ((bs bindings) (acc '()))
                    (if (null? bs)
                        (reverse acc)
                        (let* ((b (car bs))
                               (v (cadr b)))
                          (loop (cdr bs) (cons (alpha-convert-expr v child-scope globals) acc))))))
                 (new-bindings
                  (let loop ((vars alpha-vars) (vals converted-rhs) (acc '()))
                    (if (null? vars)
                        (reverse acc)
                        (loop (cdr vars) (cdr vals) (cons (list (car vars) (car vals)) acc)))))
                 (converted-body (alpha-convert-expr body child-scope globals)))
            (list 'letrec new-bindings converted-body)))

         ;; 4.7 Continuation Function: (%cont-fun f-name (params ...) f-body in-body)
         ((%cont-fun)
          (let* ((f-name (cadr expr))
                 (params (caddr expr))
                 (f-body (cadddr expr))
                 (in-body (cadr (cdddr expr)))
                 (alpha-f (make-alpha-symbol f-name))
                 ;; f-body scope binds parameters and alpha-f
                 (f-scope (scope-enter scope '%cont-fun))
                 (alpha-params
                  (let loop ((ps params) (acc '()))
                    (if (null? ps)
                        (reverse acc)
                        (let* ((p (car ps))
                               (a-p (make-alpha-symbol p)))
                          (scope-bind! f-scope p a-p)
                          (loop (cdr ps) (cons a-p acc)))))))
            (scope-bind! f-scope f-name alpha-f)
            (let ((new-f-body (alpha-convert-expr f-body f-scope globals))
                  ;; in-body has alpha-f in scope
                  (in-scope (scope-enter scope '%cont-fun)))
              (scope-bind! in-scope f-name alpha-f)
              (let ((new-in-body (alpha-convert-expr in-body in-scope globals)))
                (list '%cont-fun alpha-f alpha-params new-f-body new-in-body)))))

         ;; 4.8 Continuation Call: (%cont-call target es ...)
         ((%cont-call)
          (let ((target (alpha-convert-expr (cadr expr) scope globals))
                (args (alpha-convert-list (cddr expr) scope globals)))
            (cons '%cont-call (cons target args))))

         ;; 4.9 Dynamic Exception Handler: (%with-handler h body)
         ((%with-handler)
          (list '%with-handler
                (alpha-convert-expr (cadr expr) scope globals)
                (alpha-convert-expr (caddr expr) scope globals)))

         ;; 4.10 Call/cc raw: (%raw-call/cc arg)
         ((%raw-call/cc)
          (list '%raw-call/cc (alpha-convert-expr (cadr expr) scope globals)))

         ;; 4.11 Values & Call-with-values
         ((%values)
          (cons '%values (alpha-convert-list (cdr expr) scope globals)))

         ((%call-with-values)
          (list '%call-with-values
                (alpha-convert-expr (cadr expr) scope globals)
                (alpha-convert-expr (caddr expr) scope globals)))

         ;; 4.12 Closures (lowered primitives)
         ((%make-closure)
          (cons '%make-closure (cons (cadr expr) (alpha-convert-list (cddr expr) scope globals))))

         ((%make-closure-env)
          (cons '%make-closure-env (cons (cadr expr) (alpha-convert-list (cddr expr) scope globals))))

         ;; 4.13 Program Container: (%program defs main)
         ((%program)
          (alpha-convert-program-node expr globals))

         ;; 4.14 General Function / Primitive Application: (op arg ...)
         (else
          (let ((conv-op (alpha-convert-expr op scope globals))
                (conv-args (alpha-convert-list (cdr expr) scope globals)))
            (cons conv-op conv-args))))))))

;;; -----------------------------------------------------------------------
;;; Part 6: Program-Level Conversion & Verification
;;; -----------------------------------------------------------------------

(define (alpha-convert-program-node prog-expr base-globals)
  (let* ((defs (cadr prog-expr))
         (main (caddr prog-expr))
         (top-defines (collect-top-level-defines defs))
         (all-globals (append top-defines base-globals))
         (top-scope (make-scope-node #f 'top-level))
         (converted-defs
          (let loop ((ds defs) (acc '()))
            (if (null? ds)
                (reverse acc)
                (let ((d (car ds)))
                  (if (and (pair? d) (eq? (car d) 'define))
                      (let* ((name (cadr d))
                             (val (caddr d))
                             (conv-val (alpha-convert-expr val top-scope all-globals)))
                        (loop (cdr ds) (cons (list 'define name conv-val) acc)))
                      (loop (cdr ds) (cons (alpha-convert-expr d top-scope all-globals) acc)))))))
         (converted-main (alpha-convert-expr main top-scope all-globals)))
    (list '%program converted-defs converted-main)))

(define (alpha-convert-program ast)
  (reset-scope-unbound-vars!)
  (if (and (pair? ast) (eq? (car ast) '%program))
      (alpha-convert-program-node ast '())
      (let* ((top-scope (make-scope-node #f 'top-level)))
        (alpha-convert-expr ast top-scope '()))))

;;; -----------------------------------------------------------------------
;;; Part 7: Public API & Pass 035 Integration Entry Point
;;; -----------------------------------------------------------------------

(define (scope-resolve-all ast)
  (reset-alpha-symbol-counter!)
  (alpha-convert-program ast))

(define (detect-unbound-variables ast)
  (let ((saved-strict (scope-strict-unbound-check?)))
    (set-scope-strict-unbound-check! #f)
    (reset-scope-unbound-vars!)
    (alpha-convert-program ast)
    (let ((unbounds (get-scope-unbound-vars)))
      (set-scope-strict-unbound-check! saved-strict)
      unbounds)))

(define (scope-check-unbound! ast)
  (let ((saved-strict (scope-strict-unbound-check?)))
    (set-scope-strict-unbound-check! #t)
    (reset-scope-unbound-vars!)
    (let ((res (alpha-convert-program ast)))
      (set-scope-strict-unbound-check! saved-strict)
      res)))
