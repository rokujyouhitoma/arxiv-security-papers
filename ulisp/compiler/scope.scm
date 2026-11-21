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
;;;   (list 'scope-node parent kind bindings-cell free-vars-cell children-cell
;;;         scope-id ns-bindings-cell free-binding-ids-cell)
;;;
;;; Fields:
;;;   - parent: enclosing scope-node or #f (for root/top-level)
;;;   - kind: symbol ('top-level, 'function, 'block, 'lambda, 'let, 'letrec, '%cont-fun)
;;;   - bindings-cell: (cons bindings '()) where bindings is ((orig-sym . alpha-sym) ...)
;;;   - free-vars-cell: (cons free-vars '()) where free-vars is (sym ...)
;;;   - children-cell: (cons children '()) where children is (scope-node ...)
;;;   - scope-id: monotonic non-negative integer scope identifier
;;;   - ns-bindings-cell: (cons bindings '()) where bindings is (<binding> ...)
;;;   - free-binding-ids-cell: (cons bset '()) sorted integer set of free <binding-id>s

(define *scope-id-counter* (cons 0 '()))
(define *scope-strict-redefinition* (cons #f '()))
(define *last-resolved-scope-tree* (cons #f '()))

(define (reset-scope-id-counter!)
  (set-car! *scope-id-counter* 0))

(define (next-scope-id!)
  (let ((id (car *scope-id-counter*)))
    (set-car! *scope-id-counter* (+ id 1))
    id))

(define (scope-error! msg detail)
  (raise (list 'scope-error msg detail)))

(define (set-scope-strict-redefinition! bool)
  (set-car! *scope-strict-redefinition* bool))

(define (scope-strict-redefinition?)
  (car *scope-strict-redefinition*))

(define (with-strict-scope-redefinition thunk)
  (let ((prev (scope-strict-redefinition?)))
    (set-scope-strict-redefinition! #t)
    (guard (ex (else
                (set-scope-strict-redefinition! prev)
                (raise ex)))
      (let ((res (thunk)))
        (set-scope-strict-redefinition! prev)
        res))))

(define (get-last-resolved-scope-tree)
  (car *last-resolved-scope-tree*))

(define (make-scope-node parent kind)
  (list 'scope-node
        parent
        kind
        (cons '() '())
        (cons '() '())
        (cons '() '())
        (next-scope-id!)
        (cons '() '())
        (cons '() '())))

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

(define (scope-node-id node)
  (list-ref node 6))

(define (scope-node-ns-bindings-cell node)
  (list-ref node 7))

(define (scope-node-ns-bindings node)
  (car (scope-node-ns-bindings-cell node)))

(define (scope-node-free-binding-ids-cell node)
  (list-ref node 8))

(define (scope-node-free-binding-ids node)
  (car (scope-node-free-binding-ids-cell node)))

(define (scope-enter parent kind)
  (let ((child (make-scope-node parent kind)))
    (if (scope-node? parent)
        (let ((cc (scope-node-children-cell parent)))
          (set-car! cc (append (car cc) (list child)))))
    child))

(define (scope-bind-impl! node orig-sym alpha-sym kind-opt)
  (let ((bc (scope-node-bindings-cell node)))
    (set-car! bc (cons (cons orig-sym alpha-sym) (car bc))))
  (let* ((existing (if (not (eq? orig-sym alpha-sym))
                       (lookup-binding-by-symbol alpha-sym)
                       #f))
         (b (or existing
                (let* ((k (if (pair? kind-opt)
                              (car kind-opt)
                              (if (eq? (scope-node-kind node) 'lambda)
                                  'parameter
                                  'variable)))
                       (is-top? (eq? (scope-node-kind node) 'top-level))
                       (sc (if is-top? 'global 'lexical))
                       (vis (if is-top? 'global 'local))
                       (nb (make-binding (next-binding-id!)
                                         orig-sym
                                         alpha-sym
                                         k
                                         'ordinary
                                         (scope-node-id node)
                                         sc
                                         #f
                                         vis
                                         scope-set-empty
                                         (current-ast-span))))
                  (register-binding! nb)))))
    (let ((nbc (scope-node-ns-bindings-cell node)))
      (set-car! nbc (cons b (car nbc))))
    b))

(define scope-bind!
  (case-lambda
    ((node orig-sym alpha-sym) (scope-bind-impl! node orig-sym alpha-sym '()))
    ((node orig-sym alpha-sym kind) (scope-bind-impl! node orig-sym alpha-sym (list kind)))))

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

(define (scope-record-free-binding-id! node bid)
  (if (and (scope-node? node) (integer? bid))
      (let ((fc (scope-node-free-binding-ids-cell node)))
        (set-car! fc (binding-id-set-add bid (car fc))))))

;;; -----------------------------------------------------------------------
;;; Part 1b: Multi-Namespace Lookup, C99 Lexer Hack & Scope Manager
;;; -----------------------------------------------------------------------

(define (scope-find-function-contour node)
  (let loop ((curr node))
    (cond
      ((not (scope-node? curr)) node)
      ((memq (scope-node-kind curr) '(function lambda)) curr)
      ((not (scope-node? (scope-node-parent curr))) curr)
      (else (loop (scope-node-parent curr))))))

(define (scope-lookup-binding-local-ns node sym ns)
  (if (not (scope-node? node))
      #f
      (let loop ((bs (scope-node-ns-bindings node)))
        (cond
          ((null? bs) #f)
          ((and (eq? (binding-namespace (car bs)) ns)
                (eq? (binding-source-name (car bs)) sym))
           (car bs))
          (else (loop (cdr bs)))))))

(define scope-lookup-binding-local
  (case-lambda
    ((node sym) (scope-lookup-binding-local-ns node sym 'ordinary))
    ((node sym ns) (scope-lookup-binding-local-ns node sym ns))))

(define (scope-lookup-binding-ns node sym ns)
  (if (not (scope-node? node))
      #f
      (if (eq? ns 'label)
          (scope-lookup-binding-local-ns (scope-find-function-contour node) sym 'label)
          (let loop ((curr node))
            (if (not (scope-node? curr))
                #f
                (let ((found (scope-lookup-binding-local-ns curr sym ns)))
                  (if found
                      found
                      (loop (scope-node-parent curr)))))))))

(define scope-lookup-binding
  (case-lambda
    ((node sym) (scope-lookup-binding-ns node sym 'ordinary))
    ((node sym ns) (scope-lookup-binding-ns node sym ns))))

(define (scope-lookup-hygienic-ns node sym use-scope-set ns)
  (if (not (scope-node? node))
      #f
      (let collect ((curr node) (cands '()))
        (if (not (scope-node? curr))
            (resolve-hygienic-binding (reverse cands) use-scope-set)
            (let scan ((bs (scope-node-ns-bindings curr)) (acc cands))
              (if (null? bs)
                  (collect (scope-node-parent curr) acc)
                  (let ((b (car bs)))
                    (if (and (eq? (binding-namespace b) ns)
                             (eq? (binding-source-name b) sym))
                        (scan (cdr bs) (cons b acc))
                        (scan (cdr bs) acc)))))))))

(define scope-lookup-hygienic
  (case-lambda
    ((node sym use-scope-set) (scope-lookup-hygienic-ns node sym use-scope-set 'ordinary))
    ((node sym use-scope-set ns) (scope-lookup-hygienic-ns node sym use-scope-set ns))))

(define (scope-lookup-kind node sym)
  (let ((b (scope-lookup-binding node sym 'ordinary)))
    (if b (binding-kind b) #f)))

(define (scope-typedef-name? node sym)
  (eq? (scope-lookup-kind node sym) 'typedef))

(define (scope-parse-define-opts opts)
  (let loop ((rest opts)
             (ns #f)
             (u-sym #f)
             (sc #f)
             (ty #f)
             (vis #f)
             (sset scope-set-empty)
             (span #f)
             (strict? #f)
             (no-legacy? #f))
    (if (not (and (pair? rest) (pair? (cdr rest))))
        (list ns u-sym sc ty vis sset span strict? no-legacy?)
        (let ((k (car rest))
              (v (cadr rest))
              (tl (cddr rest)))
          (cond
            ((memq k '(:namespace namespace))
             (loop tl v u-sym sc ty vis sset span strict? no-legacy?))
            ((memq k '(:unique-sym unique-sym))
             (loop tl ns v sc ty vis sset span strict? no-legacy?))
            ((memq k '(:storage-class storage-class))
             (loop tl ns u-sym v ty vis sset span strict? no-legacy?))
            ((memq k '(:type-attr type-attr))
             (loop tl ns u-sym sc v vis sset span strict? no-legacy?))
            ((memq k '(:visibility visibility))
             (loop tl ns u-sym sc ty v sset span strict? no-legacy?))
            ((memq k '(:scope-set scope-set))
             (loop tl ns u-sym sc ty vis v span strict? no-legacy?))
            ((memq k '(:source-span source-span))
             (loop tl ns u-sym sc ty vis sset v strict? no-legacy?))
            ((memq k '(:strict strict))
             (loop tl ns u-sym sc ty vis sset span v no-legacy?))
            ((memq k '(:no-legacy-bind no-legacy-bind))
             (loop tl ns u-sym sc ty vis sset span strict? v))
            (else
             (loop tl ns u-sym sc ty vis sset span strict? no-legacy?)))))))

(define (scope-define-opts node source-name kind opts)
  (if (not (scope-node? node))
      (scope-error! "scope-define!: invalid scope-node" node))
  (let* ((parsed (scope-parse-define-opts opts))
         (opt-ns (list-ref parsed 0))
         (opt-usym (list-ref parsed 1))
         (opt-sc (list-ref parsed 2))
         (opt-ty (list-ref parsed 3))
         (opt-vis (list-ref parsed 4))
         (opt-sset (list-ref parsed 5))
         (opt-span (list-ref parsed 6))
         (opt-strict (list-ref parsed 7))
         (opt-no-legacy (list-ref parsed 8))
         (ns (or opt-ns (infer-binding-namespace kind)))
         (target-node (if (eq? ns 'label)
                          (scope-find-function-contour node)
                          node))
         (sset (if (list? opt-sset) opt-sset scope-set-empty))
         (vis (or opt-vis
                  (if (eq? (scope-node-kind target-node) 'top-level)
                      'global
                      'local)))
         (sc (or opt-sc
                 (cond
                   ((eq? kind 'typedef) 'typedef)
                   ((eq? (scope-node-kind target-node) 'top-level) 'global)
                   (else 'lexical))))
         (span (or opt-span (current-ast-span))))
    (if (or opt-strict (scope-strict-redefinition?))
        (let check ((bs (scope-node-ns-bindings target-node)))
          (if (pair? bs)
              (let ((existing (car bs)))
                (if (and (eq? (binding-namespace existing) ns)
                         (eq? (binding-source-name existing) source-name)
                         (scope-set-equal? (binding-scope-set existing) sset))
                    (scope-error! "Redefinition of symbol in same scope"
                                  (list source-name kind ns))
                    (check (cdr bs)))))))
    (let* ((u-sym (or opt-usym
                      (if (or (memq kind '(typedef enum-const tag-struct tag-union tag-enum label macro builtin))
                              (memq vis '(global extern)))
                          source-name
                          (make-alpha-symbol source-name))))
           (b (make-binding (next-binding-id!)
                            source-name
                            u-sym
                            kind
                            ns
                            (scope-node-id target-node)
                            sc
                            opt-ty
                            vis
                            sset
                            span)))
      (register-binding! b)
      (let ((nbc (scope-node-ns-bindings-cell target-node)))
        (set-car! nbc (cons b (car nbc))))
      (if (and (eq? ns 'ordinary) (not opt-no-legacy))
          (let ((bc (scope-node-bindings-cell target-node)))
            (set-car! bc (cons (cons source-name u-sym) (car bc)))))
      b)))

(define scope-define!
  (case-lambda
    ((node source-name kind)
     (scope-define-opts node source-name kind '()))
    ((node source-name kind o1)
     (scope-define-opts node source-name kind (list o1)))
    ((node source-name kind o1 o2)
     (scope-define-opts node source-name kind (list o1 o2)))))

(define (make-scope-manager)
  (let ((root (make-scope-node #f 'top-level)))
    (list 'scope-manager root (cons root '()))))

(define (scope-manager? obj)
  (and (pair? obj) (eq? (car obj) 'scope-manager)))

(define (scope-manager-root mgr)
  (cadr mgr))

(define (scope-manager-current mgr)
  (car (caddr mgr)))

(define (scope-manager-push! mgr kind)
  (let* ((curr (scope-manager-current mgr))
         (child (scope-enter curr kind)))
    (set-car! (caddr mgr) child)
    child))

(define (scope-manager-pop! mgr)
  (let* ((curr (scope-manager-current mgr))
         (parent (scope-node-parent curr)))
    (if (not (scope-node? parent))
        (scope-error! "Scope stack underflow: cannot pop root scope"
                      (list (scope-node-id curr) (scope-node-kind curr))))
    (set-car! (caddr mgr) parent)
    parent))

(define scope-manager-define!
  (case-lambda
    ((mgr sym kind)
     (scope-define-opts (scope-manager-current mgr) sym kind '()))
    ((mgr sym kind o1)
     (scope-define-opts (scope-manager-current mgr) sym kind (list o1)))
    ((mgr sym kind o1 o2)
     (scope-define-opts (scope-manager-current mgr) sym kind (list o1 o2)))))

(define scope-manager-lookup
  (case-lambda
    ((mgr sym)
     (scope-lookup-binding-ns (scope-manager-current mgr) sym 'ordinary))
    ((mgr sym ns)
     (scope-lookup-binding-ns (scope-manager-current mgr) sym ns))))

(define scope-manager-lookup-local
  (case-lambda
    ((mgr sym)
     (scope-lookup-binding-local-ns (scope-manager-current mgr) sym 'ordinary))
    ((mgr sym ns)
     (scope-lookup-binding-local-ns (scope-manager-current mgr) sym ns))))

(define (scope-manager-lookup-kind mgr sym)
  (scope-lookup-kind (scope-manager-current mgr) sym))

(define (scope-manager-typedef-name? mgr sym)
  (scope-typedef-name? (scope-manager-current mgr) sym))

;;; -----------------------------------------------------------------------
;;; Part 2: Deterministic Alpha Symbol Generator
;;; -----------------------------------------------------------------------

(define *alpha-symbol-counter* (cons 0 '()))

(define (reset-alpha-symbol-counter!)
  (set-car! *alpha-symbol-counter* 0)
  (reset-binding-registry!)
  (reset-scope-id-counter!))

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
  '(quote if begin set! lambda let letrec letrec*
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
    %num-args %get-rsp %get-heap-ptr %get-heap-limit-ptr %get-gc-state-ptr %get-environ-ptr %get-stackmap-table %get-initial-heap-ptr %get-initial-heap sys-initial-heap
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
        (let ((d (ast-strip-span (car ds))))
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

(define (scope-make-symbol-set syms)
  (let ((v (make-vector 1024 '())))
    (let loop ((xs syms))
      (if (pair? xs)
          (let* ((s (car xs))
                 (idx (symbol->hash-idx s))
                 (bucket (vector-ref v idx)))
            (if (not (memq s bucket))
                (vector-set! v idx (cons s bucket)))
            (loop (cdr xs)))
          v))))

(define (scope-symbol-set-contains? v sym)
  (if (and (vector? v) (symbol? sym))
      (let* ((idx (symbol->hash-idx sym))
             (bucket (vector-ref v idx)))
        (if (memq sym bucket) #t #f))
      #f))

(define (scope-known-global-or-prim? sym globals)
  (or (if (vector? globals)
          (scope-symbol-set-contains? globals sym)
          (if (memq sym globals) #t #f))
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
    ;; 0. Source Span / Loc Wrappers: preserve metadata & set current-ast-span
    ((ast-has-span? expr)
     (let ((span (ast-source-span expr))
           (inner (ast-strip-span expr)))
       (ast-with-span
        (with-ast-span span
          (lambda () (alpha-convert-expr inner scope globals)))
        span)))

    ((source-loc? expr)
     (let ((file (source-loc-file expr))
           (line (source-loc-line expr))
           (col (source-loc-col expr))
           (inner (source-loc-form expr))
           (span (ast-source-span expr)))
       (list '%source-loc file line col
             (with-ast-span span
               (lambda () (alpha-convert-expr inner scope globals))))))

    ;; 1. Literal Quote: datum inside (quote ...) is preserved verbatim
    ((and (pair? expr) (eq? (car expr) 'quote))
     expr)

    ;; 2. Atomic Symbol: Variable reference
    ((symbol? expr)
     (let ((alpha-sym (scope-lookup scope expr)))
       (cond
         (alpha-sym
          ;; Propagate free-variable usage & Binding IDs up the lexical contour tree
          (if (not (scope-lookup-local scope expr))
              (let ((b (lookup-binding-by-symbol alpha-sym)))
                (let propagate ((curr scope))
                  (if (and (scope-node? curr)
                           (not (eq? (scope-node-kind curr) 'top-level))
                           (not (scope-lookup-local curr expr)))
                      (if (memq expr (scope-node-free-vars curr))
                          #t
                          (begin
                            (scope-record-free-var! curr expr)
                            (if (binding? b)
                                (scope-record-free-binding-id! curr (binding-id b)))
                            (propagate (scope-node-parent curr))))))))
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
                    (cond
                      ((null? ps)
                       (reverse acc))
                      ((symbol? ps)
                       (let ((a-p (make-alpha-symbol ps)))
                         (scope-bind! child-scope ps a-p)
                         (let append-dotted ((lst (reverse acc)))
                           (if (null? lst)
                               a-p
                               (cons (car lst) (append-dotted (cdr lst)))))))
                      (else
                       (let* ((p (car ps))
                              (a-p (make-alpha-symbol p)))
                         (scope-bind! child-scope p a-p)
                         (loop (cdr ps) (cons a-p acc)))))))
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
         (all-globals (scope-make-symbol-set (append top-defines base-globals)))
         (top-scope (make-scope-node #f 'top-level))
         (_set-root (set-car! *last-resolved-scope-tree* top-scope))
         (_reg-defs
          (let reg-loop ((ds defs))
            (if (pair? ds)
                (let* ((raw-d (car ds))
                       (d (ast-strip-span raw-d))
                       (d-span (ast-source-span raw-d)))
                  (if (and (pair? d) (eq? (car d) 'define) (pair? (cdr d)) (pair? (cddr d)))
                      (let* ((spec (cadr d))
                             (def-name (if (pair? spec) (car spec) spec))
                             (val-stripped (ast-strip-span (caddr d)))
                             (kind (if (or (pair? spec)
                                           (and (pair? val-stripped) (eq? (car val-stripped) 'lambda)))
                                       'function
                                       'variable)))
                        (if (symbol? def-name)
                            (scope-define-opts top-scope def-name kind
                                               (list ':unique-sym def-name
                                                     ':storage-class 'global
                                                     ':visibility 'global
                                                     ':source-span d-span
                                                     ':no-legacy-bind #t)))))
                  (reg-loop (cdr ds))))))
         (converted-defs
          (let loop ((ds defs) (acc '()))
            (if (null? ds)
                (reverse acc)
                (let* ((raw-d (car ds))
                       (d (ast-strip-span raw-d))
                       (d-span (ast-source-span raw-d)))
                  (if (and (pair? d) (eq? (car d) 'define) (pair? (cdr d)) (pair? (cddr d)))
                      (let* ((name (cadr d))
                             (val (caddr d))
                             (conv-val (if d-span
                                           (with-ast-span d-span
                                             (lambda () (alpha-convert-expr val top-scope all-globals)))
                                           (alpha-convert-expr val top-scope all-globals)))
                             (res-def (list 'define name conv-val)))
                        (loop (cdr ds)
                              (cons (cond
                                      ((ast-has-span? raw-d) (ast-with-span res-def d-span))
                                      ((source-loc? raw-d)
                                       (list '%source-loc
                                             (source-loc-file raw-d)
                                             (source-loc-line raw-d)
                                             (source-loc-col raw-d)
                                             res-def))
                                      (else res-def))
                                    acc)))
                      (loop (cdr ds) (cons (alpha-convert-expr raw-d top-scope all-globals) acc)))))))
         (converted-main (alpha-convert-expr main top-scope all-globals)))
    (list '%program converted-defs converted-main)))

(define (alpha-convert-program ast)
  (reset-scope-unbound-vars!)
  (if (and (pair? ast) (eq? (car ast) '%program))
      (alpha-convert-program-node ast '())
      (let* ((top-scope (make-scope-node #f 'top-level)))
        (set-car! *last-resolved-scope-tree* top-scope)
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
