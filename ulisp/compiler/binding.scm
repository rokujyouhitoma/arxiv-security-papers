;;; =======================================================================
;;; ULisp Compiler: Unified First-Class Symbol Binding & Scope Sets Engine
;;; Conforms to DSN-33-02 §3.2, DSN-38 §2 (B3/B4) & Issue #837
;;; =======================================================================
;;; Provides:
;;;   1. First-class <binding> records with monotonic Binding IDs
;;;   2. Global bidirectional *binding-registry* (by ID and unique symbol)
;;;   3. Canonical ascending integer set operations (binding-id-set-*)
;;;   4. Hygienic macro Scope Sets (Flatt 2016: "Binding as Sets of Scopes")
;;; =======================================================================

;;; -----------------------------------------------------------------------
;;; 1. Structured Error Helper & Monotonic Counters
;;; -----------------------------------------------------------------------

(define (binding-error! msg detail)
  (raise (list 'binding-error msg detail)))

(define *binding-id-counter* (cons 0 '()))
(define *hygiene-scope-counter* (cons 0 '()))

(define (reset-binding-id-counter!)
  (set-car! *binding-id-counter* 0))

(define (next-binding-id!)
  (let ((id (car *binding-id-counter*)))
    (set-car! *binding-id-counter* (+ id 1))
    id))

(define (reset-hygiene-scope-counter!)
  (set-car! *hygiene-scope-counter* 0))

(define (fresh-hygiene-scope!)
  (let ((next (+ (car *hygiene-scope-counter*) 1)))
    (set-car! *hygiene-scope-counter* next)
    next))

;;; -----------------------------------------------------------------------
;;; 2. Shared Strictly-Ascending Integer Set Algebra
;;; -----------------------------------------------------------------------

(define (int-set-member? x s)
  (cond
    ((null? s) #f)
    ((= x (car s)) #t)
    ((< x (car s)) #f)
    (else (int-set-member? x (cdr s)))))

(define (int-set-add x s)
  (cond
    ((null? s) (list x))
    ((< x (car s)) (cons x s))
    ((= x (car s)) s)
    (else (cons (car s) (int-set-add x (cdr s))))))

(define (int-set-remove x s)
  (cond
    ((null? s) '())
    ((< x (car s)) s)
    ((= x (car s)) (cdr s))
    (else (cons (car s) (int-set-remove x (cdr s))))))

(define (int-set-union s1 s2)
  (cond
    ((null? s1) s2)
    ((null? s2) s1)
    ((< (car s1) (car s2))
     (cons (car s1) (int-set-union (cdr s1) s2)))
    ((< (car s2) (car s1))
     (cons (car s2) (int-set-union s1 (cdr s2))))
    (else
     (cons (car s1) (int-set-union (cdr s1) (cdr s2))))))

(define (int-set-intersection s1 s2)
  (cond
    ((or (null? s1) (null? s2)) '())
    ((< (car s1) (car s2))
     (int-set-intersection (cdr s1) s2))
    ((< (car s2) (car s1))
     (int-set-intersection s1 (cdr s2)))
    (else
     (cons (car s1) (int-set-intersection (cdr s1) (cdr s2))))))

(define (int-set-difference s1 s2)
  (cond
    ((null? s1) '())
    ((null? s2) s1)
    ((< (car s1) (car s2))
     (cons (car s1) (int-set-difference (cdr s1) s2)))
    ((< (car s2) (car s1))
     (int-set-difference s1 (cdr s2)))
    (else
     (int-set-difference (cdr s1) (cdr s2)))))

(define (int-set-subset? s1 s2)
  (cond
    ((null? s1) #t)
    ((null? s2) #f)
    ((< (car s1) (car s2)) #f)
    ((= (car s1) (car s2))
     (int-set-subset? (cdr s1) (cdr s2)))
    (else
     (int-set-subset? s1 (cdr s2)))))

(define (int-set-equal? s1 s2)
  (cond
    ((and (null? s1) (null? s2)) #t)
    ((or (null? s1) (null? s2)) #f)
    ((= (car s1) (car s2))
     (int-set-equal? (cdr s1) (cdr s2)))
    (else #f)))

(define (normalize-int-set xs)
  (if (not (list? xs))
      '()
      (let loop ((rest xs) (acc '()))
        (if (null? rest)
            acc
            (if (integer? (car rest))
                (loop (cdr rest) (int-set-add (car rest) acc))
                (loop (cdr rest) acc))))))

;;; -----------------------------------------------------------------------
;;; 3. First-Class <binding> Record Definition & Accessors
;;; -----------------------------------------------------------------------

(define (infer-binding-namespace kind)
  (case kind
    ((tag-struct tag-union tag-enum) 'tag)
    ((label) 'label)
    ((macro) 'macro)
    (else 'ordinary)))

(define (make-binding id source-name unique-sym kind namespace scope-id
                      storage-class type-attr visibility scope-set source-span)
  (if (or (not (integer? id)) (< id 0))
      (binding-error! "make-binding: id must be a non-negative integer" id))
  (if (not (symbol? source-name))
      (binding-error! "make-binding: source-name must be a symbol" source-name))
  (if (not (symbol? unique-sym))
      (binding-error! "make-binding: unique-sym must be a symbol" unique-sym))
  (if (not (symbol? kind))
      (binding-error! "make-binding: kind must be a symbol" kind))
  (if (not (symbol? namespace))
      (binding-error! "make-binding: namespace must be a symbol" namespace))
  (list 'binding
        id
        source-name
        unique-sym
        kind
        namespace
        scope-id
        (cons storage-class '())
        (cons type-attr '())
        (cons visibility '())
        (cons (normalize-int-set scope-set) '())
        (cons source-span '())))

(define (binding? obj)
  (and (pair? obj)
       (eq? (car obj) 'binding)
       (>= (length obj) 12)))

(define (binding-id b)            (list-ref b 1))
(define (binding-source-name b)   (list-ref b 2))
(define (binding-unique-sym b)    (list-ref b 3))
(define (binding-kind b)          (list-ref b 4))
(define (binding-namespace b)     (list-ref b 5))
(define (binding-scope-id b)      (list-ref b 6))
(define (binding-storage-class b) (car (list-ref b 7)))
(define (binding-type-attr b)     (car (list-ref b 8)))
(define (binding-visibility b)    (car (list-ref b 9)))
(define (binding-scope-set b)     (car (list-ref b 10)))
(define (binding-source-span b)   (car (list-ref b 11)))

(define (set-binding-storage-class! b sc)
  (set-car! (list-ref b 7) sc))

(define (set-binding-type-attr! b ty)
  (set-car! (list-ref b 8) ty))

(define (set-binding-visibility! b vis)
  (set-car! (list-ref b 9) vis))

(define (set-binding-scope-set! b sset)
  (set-car! (list-ref b 10) (normalize-int-set sset)))

(define (set-binding-source-span! b span)
  (set-car! (list-ref b 11) span))

;;; -----------------------------------------------------------------------
;;; 4. Global Binding Registry (*binding-registry*)
;;; -----------------------------------------------------------------------

(define *binding-table-size* 1024)
(define *binding-by-id-buckets* (make-vector 1024 '()))
(define *binding-by-sym-buckets* (make-vector 1024 '()))
(define *all-bindings-list* (cons '() '()))

(define (reset-binding-registry!)
  (reset-binding-id-counter!)
  (reset-hygiene-scope-counter!)
  (let loop ((i 0))
    (if (< i *binding-table-size*)
        (begin
          (vector-set! *binding-by-id-buckets* i '())
          (vector-set! *binding-by-sym-buckets* i '())
          (loop (+ i 1)))))
  (set-car! *all-bindings-list* '()))

(define (register-binding! b)
  (if (not (binding? b))
      (binding-error! "register-binding!: expected <binding>" b))
  (let* ((id (binding-id b))
         (usym (binding-unique-sym b))
         (id-idx (modulo id *binding-table-size*))
         (id-bucket (vector-ref *binding-by-id-buckets* id-idx))
         (id-entry (assv id id-bucket))
         (sym-idx (symbol->hash-idx usym))
         (sym-bucket (vector-ref *binding-by-sym-buckets* sym-idx))
         (sym-entry (assq usym sym-bucket)))
    (if id-entry
        (set-cdr! id-entry b)
        (begin
          (vector-set! *binding-by-id-buckets* id-idx (cons (cons id b) id-bucket))
          (set-car! *all-bindings-list* (cons b (car *all-bindings-list*)))))
    (if sym-entry
        (set-cdr! sym-entry b)
        (vector-set! *binding-by-sym-buckets* sym-idx (cons (cons usym b) sym-bucket)))
    b))

(define (lookup-binding-by-id id)
  (if (integer? id)
      (let* ((idx (modulo id *binding-table-size*))
             (bucket (vector-ref *binding-by-id-buckets* idx))
             (entry (assv id bucket)))
        (if entry (cdr entry) #f))
      #f))

(define (lookup-binding-by-symbol sym)
  (if (symbol? sym)
      (let* ((idx (symbol->hash-idx sym))
             (bucket (vector-ref *binding-by-sym-buckets* idx))
             (entry (assq sym bucket)))
        (if entry (cdr entry) #f))
      #f))

(define (all-registered-bindings)
  (reverse (car *all-bindings-list*)))

;;; -----------------------------------------------------------------------
;;; 5. Binding ID Set Public API
;;; -----------------------------------------------------------------------

(define binding-id-set-empty '())

(define (binding-id-set-member? id bset)
  (int-set-member? id bset))

(define (binding-id-set-add id bset)
  (int-set-add id bset))

(define (binding-id-set-remove id bset)
  (int-set-remove id bset))

(define (binding-id-set-union bset1 bset2)
  (int-set-union bset1 bset2))

(define (binding-id-set-intersection bset1 bset2)
  (int-set-intersection bset1 bset2))

(define (binding-id-set-difference bset1 bset2)
  (int-set-difference bset1 bset2))

(define (binding-id-set-subset? bset1 bset2)
  (int-set-subset? bset1 bset2))

(define (binding-id-set-equal? bset1 bset2)
  (int-set-equal? bset1 bset2))

(define (symbols->binding-id-set syms)
  (let loop ((rest syms) (acc binding-id-set-empty))
    (if (null? rest)
        acc
        (let ((b (lookup-binding-by-symbol (car rest))))
          (if b
              (loop (cdr rest) (binding-id-set-add (binding-id b) acc))
              (loop (cdr rest) acc))))))

(define (binding-id-set->symbols bset)
  (let loop ((rest bset) (acc '()))
    (if (null? rest)
        (reverse acc)
        (let ((b (lookup-binding-by-id (car rest))))
          (if b
              (loop (cdr rest) (cons (binding-unique-sym b) acc))
              (loop (cdr rest) acc))))))

;;; -----------------------------------------------------------------------
;;; 6. Hygienic Macro Scope Sets ("Binding as Sets of Scopes")
;;; -----------------------------------------------------------------------

(define scope-set-empty '())

(define (scope-set-member? mark sset)
  (int-set-member? mark sset))

(define (scope-set-add mark sset)
  (int-set-add mark sset))

(define (scope-set-remove mark sset)
  (int-set-remove mark sset))

(define (scope-set-flip mark sset)
  (if (int-set-member? mark sset)
      (int-set-remove mark sset)
      (int-set-add mark sset)))

(define (scope-set-subset? sset1 sset2)
  (int-set-subset? sset1 sset2))

(define (scope-set-equal? sset1 sset2)
  (int-set-equal? sset1 sset2))

(define (scope-set-size sset)
  (length sset))

(define (resolve-hygienic-binding candidate-bindings use-scope-set)
  (let* ((use-set (normalize-int-set use-scope-set))
         (matching (filter (lambda (b)
                             (scope-set-subset? (binding-scope-set b) use-set))
                           candidate-bindings)))
    (if (null? matching)
        #f
        (let ((best (let loop ((rest (cdr matching))
                               (cur-best (car matching))
                               (cur-size (scope-set-size (binding-scope-set (car matching)))))
                      (if (null? rest)
                          cur-best
                          (let ((sz (scope-set-size (binding-scope-set (car rest)))))
                            (if (> sz cur-size)
                                (loop (cdr rest) (car rest) sz)
                                (loop (cdr rest) cur-best cur-size)))))))
          (let verify ((rest matching))
            (if (null? rest)
                best
                (if (not (scope-set-subset? (binding-scope-set (car rest))
                                            (binding-scope-set best)))
                    (binding-error! "Ambiguous hygienic binding resolution"
                                    (list use-set
                                          (binding-scope-set best)
                                          (binding-scope-set (car rest))))
                    (verify (cdr rest)))))))))
