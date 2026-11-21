;;; =======================================================================
;;; ULisp Language Workbench: Guest Frame Descriptor & Slot Lowering
;;; Conforms to DSN-33-04 §2.1 & §2.2, DSN-33-03 §3.3 & Issue #892
;;; =======================================================================
;;; Provides:
;;; - <guest-frame-descriptor>: Compile-time static stack frame layout
;;; - gfd-empty, gfd-add-slot!, gfd-lookup-slot, gfd-mark-escape!
;;; - gfd-emit-slot-ref, gfd-emit-slot-set!: Lowering to vector-ref / local-slot-ref
;;; - lower-guest-env-to-frame: AST lowering eliminating dynamic alist lookups
;;; =======================================================================

;;; -----------------------------------------------------------------------
;;; 1. <guest-frame-descriptor> Record Definition
;;; -----------------------------------------------------------------------

(define-record-type <guest-frame-descriptor>
  (%make-guest-frame-descriptor-raw num-slots slot-names slot-types escape-mask)
  guest-frame-descriptor?
  (num-slots   gfd-num-slots   gfd-num-slots-set!)
  (slot-names  gfd-slot-names  gfd-slot-names-set!)
  (slot-types  gfd-slot-types  gfd-slot-types-set!)
  (escape-mask gfd-escape-mask gfd-escape-mask-set!))

;;; Creates an empty frame descriptor with 0 slots
(define (gfd-empty)
  (%make-guest-frame-descriptor-raw 0 '() '() 0))

;;; Creates a frame descriptor with initial capacity / given slot names
(define (make-guest-frame-descriptor slot-names)
  (let loop ((names slot-names) (idx 0) (gfd (gfd-empty)))
    (if (null? names)
        gfd
        (begin
          (gfd-add-slot! gfd (car names) 'any)
          (loop (cdr names) (+ idx 1) gfd)))))

;;; -----------------------------------------------------------------------
;;; 2. Frame Descriptor Slot Operations
;;; -----------------------------------------------------------------------

;;; Returns the current slot count (Fixnum)
(define (gfd-slot-count gfd)
  (gfd-num-slots gfd))

;;; Finds the 0-based index of a variable name in the frame descriptor.
;;; Returns the integer slot index if found, or #f if not present.
(define (gfd-lookup-slot gfd name)
  (let ((names (gfd-slot-names gfd)))
    (let loop ((lst names) (idx 0))
      (cond
        ((null? lst) #f)
        ((eq? (car lst) name) idx)
        (else (loop (cdr lst) (+ idx 1)))))))

;;; Adds a new slot to the frame descriptor if not already present.
;;; Returns the assigned slot index (Fixnum).
(define gfd-add-slot!
  (case-lambda
    ((gfd name)
     (gfd-add-slot! gfd name 'any))
    ((gfd name type-hint)
     (let ((existing (gfd-lookup-slot gfd name)))
       (if existing
           existing
           (let* ((curr-cnt (gfd-num-slots gfd))
                  (new-names (append (gfd-slot-names gfd) (list name)))
                  (new-types (append (gfd-slot-types gfd) (list type-hint))))
             (gfd-num-slots-set! gfd (+ curr-cnt 1))
             (gfd-slot-names-set! gfd new-names)
             (gfd-slot-types-set! gfd new-types)
             curr-cnt))))))

;;; Marks a slot as escaping (captured in a closure, dynamic eval, etc.)
(define (gfd-mark-escape! gfd slot-idx)
  (let ((mask (gfd-escape-mask gfd)))
    ;; Set bit at slot-idx: mask | (1 << slot-idx)
    (let ((bit (bitwise-arithmetic-shift 1 slot-idx)))
      (gfd-escape-mask-set! gfd (bitwise-ior mask bit)))))

;;; Checks if a slot escapes
(define (gfd-escapes? gfd slot-idx)
  (let ((mask (gfd-escape-mask gfd)))
    (let ((bit (bitwise-arithmetic-shift 1 slot-idx)))
      (not (zero? (bitwise-and mask bit))))))

;;; Returns the variable name at slot-idx
(define (gfd-slot-name gfd slot-idx)
  (let ((names (gfd-slot-names gfd)))
    (if (and (>= slot-idx 0) (< slot-idx (gfd-num-slots gfd)))
        (list-ref names slot-idx)
        #f)))

;;; Returns the static type hint at slot-idx
(define (gfd-slot-type gfd slot-idx)
  (let ((types (gfd-slot-types gfd)))
    (if (and (>= slot-idx 0) (< slot-idx (gfd-num-slots gfd)))
        (list-ref types slot-idx)
        'any)))

;;; -----------------------------------------------------------------------
;;; 3. Residual Code Generation (Lowering to Vector / Local Slot)
;;; -----------------------------------------------------------------------

;;; Emits a residual slot reference expression:
;;; - Escaping: (vector-ref <frame-sym> <slot-idx>)
;;; - Non-escaping: (local-slot-ref <slot-idx>) or directly the virtual register
(define (gfd-emit-slot-ref frame-sym slot-idx escape?)
  (if escape?
      (list 'vector-ref frame-sym slot-idx)
      (list 'local-slot-ref slot-idx)))

;;; Emits a residual slot mutation expression:
;;; - Escaping: (vector-set! <frame-sym> <slot-idx> <val-expr>)
;;; - Non-escaping: (local-slot-set! <slot-idx> <val-expr>)
(define (gfd-emit-slot-set! frame-sym slot-idx val-expr escape?)
  (if escape?
      (list 'vector-set! frame-sym slot-idx val-expr)
      (list 'local-slot-set! slot-idx val-expr)))

;;; Emits initial frame allocation: (make-vector <num-slots> #f)
(define (gfd-emit-frame-alloc gfd)
  (list 'make-vector (gfd-num-slots gfd) #f))

;;; -----------------------------------------------------------------------
;;; 4. Global Dynamic Context for Stage-Poly Lowering Integration
;;; -----------------------------------------------------------------------

;; Cell holding current active <guest-frame-descriptor> during lowering
(define *current-guest-frame-descriptor-cell* (cons #f '()))

(define (get-current-guest-frame-descriptor)
  (car *current-guest-frame-descriptor-cell*))

(define (set-current-guest-frame-descriptor! gfd)
  (set-car! *current-guest-frame-descriptor-cell* gfd))

(define (with-guest-frame-descriptor gfd thunk)
  (let ((prev (get-current-guest-frame-descriptor)))
    (set-current-guest-frame-descriptor! gfd)
    (let ((result (thunk)))
      (set-current-guest-frame-descriptor! prev)
      result)))

;;; -----------------------------------------------------------------------
;;; 5. AST Lowering: Eliminating Dynamic Alist Lookups
;;; -----------------------------------------------------------------------

;;; Traverses an AST and lowers alist-based environment accesses:
;;; - (cdr (assq 'x env)) -> (vector-ref frame idx)
;;; - (assq 'x env) -> (cons 'x (vector-ref frame idx)) [if entry needed]
;;; - (env-lookup env 'x) -> (vector-ref frame idx)
;;; - (ctfe-env-lookup env 'x) -> (vector-ref frame idx)
(define (lower-guest-env-to-frame ast gfd frame-sym)
  (cond
    ((not (pair? ast)) ast)

    ;; Pattern 1: (cdr (assq 'var env))
    ((and (eq? (car ast) 'cdr)
          (pair? (cdr ast))
          (pair? (cadr ast))
          (eq? (car (cadr ast)) 'assq)
          (pair? (cdr (cadr ast)))
          (pair? (cddr (cadr ast))))
     (let* ((assq-node (cadr ast))
            (key-expr (cadr assq-node))
            (env-expr (caddr assq-node)))
       (let ((var-name (if (and (pair? key-expr) (eq? (car key-expr) 'quote))
                           (cadr key-expr)
                           (if (symbol? key-expr) key-expr #f))))
         (if (and var-name (eq? env-expr 'env))
             (let ((slot-idx (gfd-lookup-slot gfd var-name)))
               (if slot-idx
                   (let ((esc? (gfd-escapes? gfd slot-idx)))
                     (gfd-emit-slot-ref frame-sym slot-idx esc?))
                   ast))
             (cons 'cdr (list (lower-guest-env-to-frame (cadr ast) gfd frame-sym)))))))

    ;; Pattern 2: (assq 'var env) - when used directly as an entry
    ((and (eq? (car ast) 'assq)
          (pair? (cdr ast))
          (pair? (cddr ast)))
     (let* ((key-expr (cadr ast))
            (env-expr (caddr ast)))
       (let ((var-name (if (and (pair? key-expr) (eq? (car key-expr) 'quote))
                           (cadr key-expr)
                           (if (symbol? key-expr) key-expr #f))))
         (if (and var-name (eq? env-expr 'env))
             (let ((slot-idx (gfd-lookup-slot gfd var-name)))
               (if slot-idx
                   (let* ((esc? (gfd-escapes? gfd slot-idx))
                          (val-ref (gfd-emit-slot-ref frame-sym slot-idx esc?)))
                     (list 'cons (list 'quote var-name) val-ref))
                   ast))
             ast))))

    ;; Pattern 3: (env-lookup env 'var) or (ctfe-env-lookup env 'var)
    ((and (memq (car ast) '(env-lookup ctfe-env-lookup guest-env-lookup))
          (pair? (cdr ast))
          (pair? (cddr ast)))
     (let* ((env-expr (cadr ast))
            (key-expr (caddr ast)))
       (let ((var-name (if (and (pair? key-expr) (eq? (car key-expr) 'quote))
                           (cadr key-expr)
                           (if (symbol? key-expr) key-expr #f))))
         (if (and var-name (or (eq? env-expr 'env) (eq? env-expr frame-sym)))
             (let ((slot-idx (gfd-lookup-slot gfd var-name)))
               (if slot-idx
                   (let ((esc? (gfd-escapes? gfd slot-idx)))
                     (gfd-emit-slot-ref frame-sym slot-idx esc?))
                   ast))
             (cons (car ast) (map (lambda (x) (lower-guest-env-to-frame x gfd frame-sym)) (cdr ast)))))))

    ;; Recursively lower sub-expressions
    (else
     (cons (lower-guest-env-to-frame (car ast) gfd frame-sym)
           (lower-guest-env-to-frame (cdr ast) gfd frame-sym)))))
