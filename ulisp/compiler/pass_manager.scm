;;; =======================================================================
;;; ULisp Compiler: Unified Pass Manager & Optimization Pipeline Scheduler
;;; Conforms to DSN-33 Architecture Specification & Issue #598
;;; =======================================================================

;;; -----------------------------------------------------------------------
;;; 1. Pass Descriptor Record & Accessors
;;; -----------------------------------------------------------------------
;;; Each pass is represented as a structured 10-element tuple:
;;;   (list 'pass-descriptor id name category opt-level pass-fn verifier-phase in-lang out-lang prerequisites mandatory?)
;;; Optional trailing contract args (:requires ... :preserves ... :invalidates ...
;;; or positional (requires preserves invalidates)) register pass analysis contracts.

(define (parse-pass-descriptor-contract-opts opts)
  (cond
    ((null? opts) (list #f '() #f '()))
    ((and (list? (car opts))
          (pair? (car opts))
          (pair? (caar opts))
          (memq (caaar opts) '(requires preserves invalidates :requires :preserves :invalidates)))
     ;; Alist form: '((requires . (...)) (preserves . (...)) (invalidates . (...)))
     (let loop ((xs (car opts)) (reqs '()) (pres #f) (invs '()))
       (if (null? xs)
           (list #t reqs pres invs)
           (let ((k (caar xs)) (v (cdar xs)))
             (cond
               ((memq k '(requires :requires)) (loop (cdr xs) (normalize-analysis-spec-list v) pres invs))
               ((memq k '(preserves :preserves)) (loop (cdr xs) reqs (normalize-analysis-spec-list v) invs))
               ((memq k '(invalidates :invalidates)) (loop (cdr xs) reqs pres (normalize-analysis-spec-list v)))
               (else (loop (cdr xs) reqs pres invs)))))))
    ((memq (car opts) '(:requires :preserves :invalidates requires preserves invalidates))
     (let loop ((rem opts) (reqs '()) (pres #f) (invs '()))
       (if (or (null? rem) (null? (cdr rem)))
           (list #t reqs pres invs)
           (let ((k (car rem)) (v (normalize-analysis-spec-list (cadr rem))))
             (cond
               ((memq k '(:requires requires)) (loop (cddr rem) (append reqs v) pres invs))
               ((memq k '(:preserves preserves)) (loop (cddr rem) reqs (append (if pres pres '()) v) invs))
               ((memq k '(:invalidates invalidates)) (loop (cddr rem) reqs pres (append invs v)))
               (else (loop (cdr rem) reqs pres invs)))))))
    (else
     ;; Positional form: (reqs [pres [invs]])
     (let* ((reqs (normalize-analysis-spec-list (car opts)))
            (pres (if (pair? (cdr opts)) (normalize-analysis-spec-list (cadr opts)) #f))
            (invs (if (and (pair? (cdr opts)) (pair? (cddr opts)))
                      (normalize-analysis-spec-list (caddr opts))
                      '())))
       (list #t reqs pres invs)))))

(define (make-pass-descriptor-with-opts id name category opt-level pass-fn verifier-phase in-lang out-lang prerequisites mandatory? contract-opts)
  (let ((parsed (parse-pass-descriptor-contract-opts contract-opts)))
    (if (car parsed)
        (register-pass-proc-analysis-contract! pass-fn id (cadr parsed) (caddr parsed) (cadddr parsed))))
  (list 'pass-descriptor id name category opt-level pass-fn verifier-phase in-lang out-lang prerequisites mandatory?))

(cond-expand
  (ulisp
   (define (make-pass-descriptor id name category opt-level pass-fn verifier-phase in-lang out-lang prerequisites mandatory?)
     (make-pass-descriptor-with-opts id name category opt-level pass-fn verifier-phase in-lang out-lang prerequisites mandatory? '())))
  (else
   (define make-pass-descriptor
     (case-lambda
       ((id name category opt-level pass-fn verifier-phase in-lang out-lang prerequisites mandatory?)
        (make-pass-descriptor-with-opts id name category opt-level pass-fn verifier-phase in-lang out-lang prerequisites mandatory? '()))
       ((id name category opt-level pass-fn verifier-phase in-lang out-lang prerequisites mandatory? o1)
        (make-pass-descriptor-with-opts id name category opt-level pass-fn verifier-phase in-lang out-lang prerequisites mandatory? (list o1)))
       ((id name category opt-level pass-fn verifier-phase in-lang out-lang prerequisites mandatory? o1 o2)
        (make-pass-descriptor-with-opts id name category opt-level pass-fn verifier-phase in-lang out-lang prerequisites mandatory? (list o1 o2)))
       ((id name category opt-level pass-fn verifier-phase in-lang out-lang prerequisites mandatory? o1 o2 o3)
        (make-pass-descriptor-with-opts id name category opt-level pass-fn verifier-phase in-lang out-lang prerequisites mandatory? (list o1 o2 o3)))
       ((id name category opt-level pass-fn verifier-phase in-lang out-lang prerequisites mandatory? o1 o2 o3 o4)
        (make-pass-descriptor-with-opts id name category opt-level pass-fn verifier-phase in-lang out-lang prerequisites mandatory? (list o1 o2 o3 o4)))
       ((id name category opt-level pass-fn verifier-phase in-lang out-lang prerequisites mandatory? o1 o2 o3 o4 o5)
        (make-pass-descriptor-with-opts id name category opt-level pass-fn verifier-phase in-lang out-lang prerequisites mandatory? (list o1 o2 o3 o4 o5)))
       ((id name category opt-level pass-fn verifier-phase in-lang out-lang prerequisites mandatory? o1 o2 o3 o4 o5 o6)
        (make-pass-descriptor-with-opts id name category opt-level pass-fn verifier-phase in-lang out-lang prerequisites mandatory? (list o1 o2 o3 o4 o5 o6)))))))

(define (pass-descriptor? obj)
  (and (pair? obj) (eq? (car obj) 'pass-descriptor)))

(define (pass-id p) (cadr p))
(define (pass-name p) (caddr p))
(define (pass-category p) (cadddr p))
(define (pass-opt-level p) (car (cddddr p)))
(define (pass-fn p) (cadr (cddddr p)))
(define (pass-verifier-phase p) (caddr (cddddr p)))
(define (pass-in-lang p) (cadddr (cddddr p)))
(define (pass-out-lang p) (car (cddddr (cddddr p))))
(define (pass-prerequisites p) (cadr (cddddr (cddddr p))))
(define (pass-mandatory? p) (caddr (cddddr (cddddr p))))

(define (set-pass-analysis-contract! pass-or-id requires preserves invalidates)
  (cond
    ((pass-descriptor? pass-or-id)
     (register-pass-proc-analysis-contract! (pass-fn pass-or-id) (pass-id pass-or-id) requires preserves invalidates))
    ((procedure? pass-or-id)
     (let ((existing (lookup-pass-analysis-contract pass-or-id)))
       (register-pass-proc-analysis-contract! pass-or-id
                                              (if existing (car existing) pass-or-id)
                                              requires preserves invalidates)))
    (else
     (register-pass-analysis-contract! pass-or-id requires preserves invalidates))))

(define (pass-analysis-contract pass-or-id)
  (cond
    ((pass-descriptor? pass-or-id)
     (or (lookup-pass-analysis-contract (pass-id pass-or-id))
         (lookup-pass-analysis-contract (pass-fn pass-or-id))))
    ((symbol? pass-or-id)
     (let ((direct (lookup-pass-analysis-contract pass-or-id)))
       (if direct
           direct
           (if (pass-registered? pass-or-id)
               (lookup-pass-analysis-contract (pass-fn (lookup-pass pass-or-id)))
               #f))))
    ((procedure? pass-or-id)
     (lookup-pass-analysis-contract pass-or-id))
    (else #f)))

(define (pass-requires-analyses pass-or-id)
  (let ((c (pass-analysis-contract pass-or-id)))
    (if c (cadr c) '())))

(define (pass-preserves-analyses pass-or-id)
  (let ((c (pass-analysis-contract pass-or-id)))
    (if c (caddr c) #f)))

(define (pass-invalidates-analyses pass-or-id)
  (let ((c (pass-analysis-contract pass-or-id)))
    (if c (cadddr c) '())))

;;; -----------------------------------------------------------------------
;;; 1.1 Pipeline Descriptor Record & Accessors (DSN-33-01 T6.1 / Issue #768)
;;; -----------------------------------------------------------------------
;;; A pipeline descriptor represents a named, end-to-end transformation flow:
;;;   (list 'pipeline-descriptor name doc passes target-ir options)

(define (make-pipeline-descriptor name doc passes target-ir options)
  (list 'pipeline-descriptor name doc passes target-ir options))

(define (pipeline-descriptor? obj)
  (and (pair? obj) (eq? (car obj) 'pipeline-descriptor)))

(define (pipeline-desc-name p) (cadr p))
(define (pipeline-desc-doc p) (caddr p))
(define (pipeline-desc-passes p) (cadddr p))
(define (pipeline-desc-target-ir p) (car (cddddr p)))
(define (pipeline-desc-options p) (cadr (cddddr p)))

;;; -----------------------------------------------------------------------
;;; 1.2 Analysis Property Registry & Cache Invalidation Engine (Issue #840)
;;; -----------------------------------------------------------------------
;;; Analysis descriptor record:
;;;   (list 'analysis-descriptor name compute-fn depends-on doc)

(define (make-analysis-descriptor name compute-fn depends-on doc)
  (list 'analysis-descriptor name compute-fn depends-on doc))

(define (analysis-descriptor? obj)
  (and (pair? obj) (eq? (car obj) 'analysis-descriptor)))

(define (analysis-desc-name d) (cadr d))
(define (analysis-desc-compute-fn d) (caddr d))
(define (analysis-desc-depends-on d) (cadddr d))
(define (analysis-desc-doc d) (car (cddddr d)))

(define *analysis-property-registry* (cons '() '()))
(define *analysis-property-cache* (cons '() '()))
;; Stats vector: #(hits misses recomputations invalidations preserved)
(define *analysis-cache-stats* (vector 0 0 0 0 0))
(define *current-analysis-ast* (cons #f '()))
(define *analysis-visiting-stack* (cons '() '()))
(define *pass-fixpoint-max-iterations* (cons 32 '()))

(define (pass-fixpoint-max-iterations) (car *pass-fixpoint-max-iterations*))
(define (set-pass-fixpoint-max-iterations! n) (set-car! *pass-fixpoint-max-iterations* n))

(define (pm-stats-inc! idx)
  (vector-set! *analysis-cache-stats* idx (+ (vector-ref *analysis-cache-stats* idx) 1)))

(define (reset-analysis-cache!)
  (set-car! *analysis-property-cache* '())
  (vector-set! *analysis-cache-stats* 0 0)
  (vector-set! *analysis-cache-stats* 1 0)
  (vector-set! *analysis-cache-stats* 2 0)
  (vector-set! *analysis-cache-stats* 3 0)
  (vector-set! *analysis-cache-stats* 4 0)
  (set-car! *current-analysis-ast* #f)
  (set-car! *analysis-visiting-stack* '())
  #t)

(define (analysis-cache-stats)
  (list (cons 'hits (vector-ref *analysis-cache-stats* 0))
        (cons 'misses (vector-ref *analysis-cache-stats* 1))
        (cons 'recomputations (vector-ref *analysis-cache-stats* 2))
        (cons 'invalidations (vector-ref *analysis-cache-stats* 3))
        (cons 'preserved (vector-ref *analysis-cache-stats* 4))))

(define (reset-analysis-properties!)
  (set-car! *analysis-property-registry* '())
  (reset-analysis-cache!))

(define (lookup-analysis-property-opt name)
  (let ((e (assq name (car *analysis-property-registry*))))
    (if e (cdr e) #f)))

(define (analysis-property-registered? name)
  (if (lookup-analysis-property-opt name) #t #f))

(define (lookup-analysis-property name)
  (let ((desc (lookup-analysis-property-opt name)))
    (if desc
        desc
        (error "lookup-analysis-property: unregistered analysis property" name))))

(define (list-analysis-properties)
  (map car* (car *analysis-property-registry*)))

(define (analysis-dep-creates-cycle? target-name start-deps)
  (let walk ((queue start-deps) (visited '()))
    (cond
      ((null? queue) #f)
      ((eq? (car queue) target-name) #t)
      ((memq (car queue) visited) (walk (cdr queue) visited))
      (else
       (let* ((cur (car queue))
              (desc (lookup-analysis-property-opt cur))
              (next-deps (if desc (analysis-desc-depends-on desc) '())))
         (walk (append next-deps (cdr queue)) (cons cur visited)))))))

(define (parse-register-analysis-opts opts)
  (let loop ((rem opts) (deps '()) (doc ""))
    (cond
      ((null? rem) (cons deps doc))
      ((and (memq (car rem) '(:depends-on depends-on)) (pair? (cdr rem)))
       (loop (cddr rem) (normalize-analysis-spec-list (cadr rem)) doc))
      ((and (memq (car rem) '(:doc doc)) (pair? (cdr rem)))
       (loop (cddr rem) deps (cadr rem)))
      ((list? (car rem))
       (loop (cdr rem) (normalize-analysis-spec-list (car rem)) doc))
      ((string? (car rem))
       (loop (cdr rem) deps (car rem)))
      (else
       (loop (cdr rem) deps doc)))))

(define (register-analysis-property-opts! name compute-fn opts)
  (let* ((parsed (parse-register-analysis-opts opts))
         (deps (car parsed))
         (doc (cdr parsed)))
    (if (analysis-dep-creates-cycle? name deps)
        (raise (list 'analysis-cycle-error name deps)))
    (let ((desc (make-analysis-descriptor name compute-fn deps doc)))
      (set-car! *analysis-property-registry*
                (alist-upsert-eq (car *analysis-property-registry*) name desc))
      name)))

(define register-analysis-property!
  (case-lambda
    ((name compute-fn)
     (register-analysis-property-opts! name compute-fn '()))
    ((name compute-fn o1)
     (register-analysis-property-opts! name compute-fn (list o1)))
    ((name compute-fn o1 o2)
     (register-analysis-property-opts! name compute-fn (list o1 o2)))
    ((name compute-fn o1 o2 o3)
     (register-analysis-property-opts! name compute-fn (list o1 o2 o3)))
    ((name compute-fn o1 o2 o3 o4)
     (register-analysis-property-opts! name compute-fn (list o1 o2 o3 o4)))))

;; Cache entry vector: #(name valid? value ast compute-count hit-count invalidation-count)
(define (lookup-analysis-cache-entry name)
  (let ((e (assq name (car *analysis-property-cache*))))
    (if e (cdr e) #f)))

(define analysis-valid?
  (case-lambda
    ((name)
     (let ((entry (lookup-analysis-cache-entry name)))
       (if (and entry (vector-ref entry 1)) #t #f)))
    ((name ast)
     (let ((entry (lookup-analysis-cache-entry name)))
       (if (and entry (vector-ref entry 1) (eq? (vector-ref entry 3) ast)) #t #f)))))

(define (get-cached-analysis name)
  (let ((entry (lookup-analysis-cache-entry name)))
    (if (and entry (vector-ref entry 1))
        (vector-ref entry 2)
        #f)))

(define (analysis-compute-count name)
  (let ((entry (lookup-analysis-cache-entry name)))
    (if entry (vector-ref entry 4) 0)))

(define (analysis-hit-count name)
  (let ((entry (lookup-analysis-cache-entry name)))
    (if entry (vector-ref entry 5) 0)))

(define (analysis-invalidation-count name)
  (let ((entry (lookup-analysis-cache-entry name)))
    (if entry (vector-ref entry 6) 0)))

(define (require-analysis-impl name explicit-ast? maybe-ast-val)
  (if (null? (car *analysis-property-registry*))
      (init-default-analysis-properties!))
  (if (memq name (car *analysis-visiting-stack*))
      (raise (list 'analysis-cycle-error name (reverse (cons name (car *analysis-visiting-stack*))))))
  (let ((ast (if explicit-ast? maybe-ast-val (car *current-analysis-ast*))))
    (if explicit-ast?
        (set-car! *current-analysis-ast* ast))
    (let ((entry (lookup-analysis-cache-entry name)))
      (if (and entry
               (vector-ref entry 1)
               (or (not explicit-ast?)
                   (eq? (vector-ref entry 3) ast)))
          (begin
            (pm-stats-inc! 0)
            (vector-set! entry 5 (+ (vector-ref entry 5) 1))
            (vector-ref entry 2))
          (let* ((desc (lookup-analysis-property name))
                 (deps (analysis-desc-depends-on desc))
                 (saved-stack (car *analysis-visiting-stack*)))
            (set-car! *analysis-visiting-stack* (cons name saved-stack))
            (let ((val (guard (ex (else
                                    (set-car! *analysis-visiting-stack* saved-stack)
                                    (raise ex)))
                         (for-each (lambda (d) (require-analysis-impl d #t ast)) deps)
                         ((analysis-desc-compute-fn desc) ast))))
              (set-car! *analysis-visiting-stack* saved-stack)
              (let ((cur-entry (lookup-analysis-cache-entry name)))
                (if cur-entry
                    (begin
                      (vector-set! cur-entry 1 #t)
                      (vector-set! cur-entry 2 val)
                      (vector-set! cur-entry 3 ast)
                      (vector-set! cur-entry 4 (+ (vector-ref cur-entry 4) 1)))
                    (let ((new-entry (vector name #t val ast 1 0 0)))
                      (set-car! *analysis-property-cache*
                                (alist-upsert-eq (car *analysis-property-cache*) name new-entry)))))
              (pm-stats-inc! 1)
              (pm-stats-inc! 2)
              val))))))

(define require-analysis
  (case-lambda
    ((name) (require-analysis-impl name #f #f))
    ((name ast) (require-analysis-impl name #t ast))))

(define (analysis-direct-dependents prop-name)
  (let loop ((reg (car *analysis-property-registry*)) (acc '()))
    (if (null? reg)
        (reverse acc)
        (let* ((desc (cdar reg))
               (dname (analysis-desc-name desc))
               (deps (analysis-desc-depends-on desc)))
          (if (memq prop-name deps)
              (loop (cdr reg) (cons dname acc))
              (loop (cdr reg) acc))))))

(define (mark-single-analysis-invalid! entry)
  (if (and entry (vector-ref entry 1))
      (begin
        (vector-set! entry 1 #f)
        (vector-set! entry 6 (+ (vector-ref entry 6) 1))
        (pm-stats-inc! 3)
        #t)
      #f))

(define (invalidate-analysis! root-name)
  (if (eq? root-name 'all)
      (invalidate-all-analyses!)
      (let loop ((queue (list root-name)) (visited '()))
        (if (pair? queue)
            (let ((cur (car queue))
                  (rest (cdr queue)))
              (if (memq cur visited)
                  (loop rest visited)
                  (let ((entry (lookup-analysis-cache-entry cur))
                        (dependents (analysis-direct-dependents cur)))
                    (mark-single-analysis-invalid! entry)
                    (if (eq? cur 'femto-attrs)
                        (femto-cache-reset!))
                    (loop (append dependents rest) (cons cur visited)))))))))

(define (invalidate-all-analyses!)
  (for-each (lambda (cell) (mark-single-analysis-invalid! (cdr cell)))
            (car *analysis-property-cache*))
  (femto-cache-reset!)
  #t)

(define (ensure-pass-required-analyses! pass-or-id input-ast)
  (set-car! *current-analysis-ast* input-ast)
  (let ((reqs (pass-requires-analyses pass-or-id)))
    (if (pair? reqs)
        (for-each (lambda (p) (require-analysis p input-ast)) reqs))))

(define (apply-pass-analysis-invalidation! pass-or-id input-ast output-ast)
  (set-car! *current-analysis-ast* output-ast)
  (let ((pres (pass-preserves-analyses pass-or-id))
        (invs (pass-invalidates-analyses pass-or-id))
        (unchanged? (eq? input-ast output-ast)))
    (if (memq 'all invs)
        (invalidate-all-analyses!)
        (for-each invalidate-analysis! invs))
    (for-each
      (lambda (cell)
        (let ((name (car cell))
              (entry (cdr cell)))
          (if (vector-ref entry 1)
              (cond
                (unchanged?
                 (pm-stats-inc! 4))
                ((and pres (or (memq 'all pres) (memq name pres)))
                 (vector-set! entry 3 output-ast)
                 (pm-stats-inc! 4))
                (else
                 (mark-single-analysis-invalid! entry))))))
      (car *analysis-property-cache*))))

;;; Built-in AST/CFG Default Analysis Implementations (Issue #840)

(define (pm-list-add-unique sym lst)
  (if (memq sym lst) lst (cons sym lst)))

(define (pm-list-union a b)
  (let loop ((xs a) (acc b))
    (if (null? xs) acc
        (loop (cdr xs) (pm-list-add-unique (car xs) acc)))))

(define (pm-list-diff a b)
  (let loop ((xs a) (acc '()))
    (if (null? xs) (reverse acc)
        (loop (cdr xs) (if (memq (car xs) b) acc (cons (car xs) acc))))))

(define (pm-ast-collect-free-vars expr bound)
  (cond
    ((symbol? expr) (if (memq expr bound) '() (list expr)))
    ((not (pair? expr)) '())
    ((eq? (car expr) 'quote) '())
    ((and (eq? (car expr) 'let) (pair? (cdr expr)) (list? (cadr expr)))
     (let ((bs (cadr expr))
           (body (cddr expr)))
       (let* ((vars (map car* bs))
              (rhs-fvs (let loop ((xs bs) (acc '()))
                         (if (null? xs) acc
                             (loop (cdr xs)
                                   (pm-list-union (pm-ast-collect-free-vars (cadr (car xs)) bound) acc)))))
              (body-fvs (let loop ((es body) (nb (pm-list-union vars bound)) (acc '()))
                          (if (null? es) acc
                              (loop (cdr es) nb (pm-list-union (pm-ast-collect-free-vars (car es) nb) acc))))))
         (pm-list-union rhs-fvs body-fvs))))
    ((and (eq? (car expr) 'letrec) (pair? (cdr expr)) (list? (cadr expr)))
     (let* ((bs (cadr expr))
            (vars (map car* bs))
            (nb (pm-list-union vars bound))
            (rhs-fvs (let loop ((xs bs) (acc '()))
                       (if (null? xs) acc
                           (loop (cdr xs)
                                 (pm-list-union (pm-ast-collect-free-vars (cadr (car xs)) nb) acc)))))
            (body-fvs (let loop ((es (cddr expr)) (acc '()))
                        (if (null? es) acc
                            (loop (cdr es) (pm-list-union (pm-ast-collect-free-vars (car es) nb) acc))))))
       (pm-list-union rhs-fvs body-fvs)))
    ((and (eq? (car expr) 'lambda) (pair? (cdr expr)) (list? (cadr expr)))
     (let ((nb (pm-list-union (cadr expr) bound)))
       (let loop ((es (cddr expr)) (acc '()))
         (if (null? es) acc
             (loop (cdr es) (pm-list-union (pm-ast-collect-free-vars (car es) nb) acc))))))
    (else
     (let loop ((xs (cdr expr)) (acc '()))
       (if (null? xs) acc
           (loop (cdr xs) (pm-list-union (pm-ast-collect-free-vars (car xs) bound) acc)))))))

(define (pm-ast-use-counts ast)
  (let ((counts-cell (cons '() '())))
    (letrec ((visit
              (lambda (x)
                (cond
                  ((symbol? x)
                   (let ((e (assq x (car counts-cell))))
                     (if e
                         (set-cdr! e (+ (cdr e) 1))
                         (set-car! counts-cell (cons (cons x 1) (car counts-cell))))))
                  ((not (pair? x)) #f)
                  ((eq? (car x) 'quote) #f)
                  ((and (memq (car x) '(let let*)) (pair? (cdr x)) (list? (cadr x)))
                   (for-each (lambda (b) (visit (cadr b))) (cadr x))
                   (for-each visit (cddr x)))
                  ((and (eq? (car x) 'letrec) (pair? (cdr x)) (list? (cadr x)))
                   (for-each (lambda (b) (visit (cadr b))) (cadr x))
                   (for-each visit (cddr x)))
                  ((and (eq? (car x) 'lambda) (pair? (cdr x)))
                   (for-each visit (cddr x)))
                  (else
                   (for-each visit (cdr x)))))))
      (visit ast)
      (reverse (car counts-cell)))))

(define (pm-extract-cfg-blocks ast)
  (cond
    ((and (pair? ast) (eq? (car ast) '%cfg) (pair? (cdr ast)))
     (cdr ast))
    (else
     (list (list 'entry (pm-ast-collect-free-vars ast '()) '())))))

(define (pm-compute-cfg-dominators ast)
  (let ((blocks (pm-extract-cfg-blocks ast)))
    (let loop ((bs blocks) (doms '()) (seen '(entry)))
      (if (null? bs)
          (reverse doms)
          (let* ((b (car bs))
                 (lbl (if (pair? b) (car b) 'entry))
                 (bdoms (pm-list-add-unique lbl seen)))
            (loop (cdr bs) (cons (cons lbl bdoms) doms) bdoms))))))

(define (pm-compute-variable-liveness ast)
  (if (and (pair? ast) (eq? (car ast) '%cfg))
      (let loop ((bs (cdr ast)) (res '()))
        (if (null? bs)
            (reverse res)
            (let* ((b (car bs))
                   (lbl (car b))
                   (live (pm-ast-collect-free-vars (cdr b) '())))
              (loop (cdr bs) (cons (cons lbl live) res)))))
      (list (cons 'live-in (pm-ast-collect-free-vars ast '()))
            (cons 'use-counts (pm-ast-use-counts ast)))))

(define (pm-compute-reaching-defs ast)
  (let ((defs-cell (cons '() '())))
    (letrec ((walk
              (lambda (x)
                (cond
                  ((not (pair? x)) #f)
                  ((eq? (car x) 'quote) #f)
                  ((and (memq (car x) '(let let* letrec)) (pair? (cdr x)) (list? (cadr x)))
                   (for-each (lambda (b)
                               (set-car! defs-cell (cons (cons (car b) (cadr b)) (car defs-cell)))
                               (walk (cadr b)))
                             (cadr x))
                   (for-each walk (cddr x)))
                  ((and (eq? (car x) 'define) (pair? (cdr x)))
                   (let ((nm (if (pair? (cadr x)) (car (cadr x)) (cadr x))))
                     (set-car! defs-cell (cons (cons nm (cddr x)) (car defs-cell))))
                   (for-each walk (cddr x)))
                  (else
                   (if (pair? (cdr x)) (for-each walk (cdr x))))))))
      (walk ast)
      (reverse (car defs-cell)))))

(define (pm-compute-alias-sets ast)
  (let ((rdefs (get-cached-analysis 'reaching-defs)))
    (map (lambda (d)
           (let ((var (car d)) (rhs (cdr d)))
             (cons var (cond
                         ((symbol? rhs) (list 'alias rhs))
                         ((and (pair? rhs) (memq (car rhs) '(cons vector %make-closure)))
                          (list 'fresh (car rhs)))
                         (else '(scalar))))))
         (if rdefs rdefs '()))))

(define (pm-compute-free-vars ast)
  (pm-ast-collect-free-vars ast '()))

(define (pm-compute-term-hash-consing ast)
  (list (cons 'femto (femto-cache-stats))
        (cons 'hash-cons-entries (length (car *nanopass-hash-cons-table*)))))

(define (init-default-analysis-properties!)
  (register-analysis-property! 'cfg-dominators pm-compute-cfg-dominators '()
                               "Control-flow graph dominator sets")
  (register-analysis-property! 'variable-liveness pm-compute-variable-liveness '()
                               "Variable liveness sets across blocks and expressions")
  (register-analysis-property! 'reaching-defs pm-compute-reaching-defs '()
                               "Reaching variable definitions across AST/CFG bindings")
  (register-analysis-property! 'alias-sets pm-compute-alias-sets '(reaching-defs)
                               "Pointer/alias sets derived from reaching definitions")
  (register-analysis-property! 'free-vars pm-compute-free-vars '()
                               "Lexical free variables in AST")
  (register-analysis-property! 'use-counts pm-ast-use-counts '()
                               "Symbol occurrence counts in AST")
  (register-analysis-property! 'femto-attrs (lambda (_ast) (femto-cache-stats)) '()
                               "Femtopass memoized AST attribute cache")
  (register-analysis-property! 'term-hash-consing pm-compute-term-hash-consing '()
                               "Nanopass hash-consing DAG snapshot")
  #t)

;; Connect nanopass.scm standalone pass hooks to pass_manager analysis tracker
(set-car! *nanopass-pre-pass-analysis-hook* ensure-pass-required-analyses!)
(set-car! *nanopass-post-pass-analysis-hook* apply-pass-analysis-invalidation!)

;;; -----------------------------------------------------------------------
;;; 2. Global Pass Registry
;;; -----------------------------------------------------------------------

(define *pass-registry* (cons '() '()))

(define (pass-registry)
  (car *pass-registry*))

(define (reset-pass-registry!)
  (set-car! *pass-registry* '()))

;;; -----------------------------------------------------------------------
;;; Pass Registry Initialization Hooks (Pluggable Extensions Integration)
;;; -----------------------------------------------------------------------
(define *pass-registry-init-hooks* (cons '() '()))

(define (pass-registry-init-hooks)
  (car *pass-registry-init-hooks*))

(define (register-pass-registry-init-hook! hook-fn)
  (let ((hooks (car *pass-registry-init-hooks*)))
    (if (not (memq hook-fn hooks))
        (set-car! *pass-registry-init-hooks* (append hooks (list hook-fn))))))

(define (unregister-pass-registry-init-hook! hook-fn)
  (let loop ((hooks (car *pass-registry-init-hooks*)) (acc '()))
    (cond
      ((null? hooks)
       (set-car! *pass-registry-init-hooks* (reverse acc)))
      ((eq? (car hooks) hook-fn)
       (loop (cdr hooks) acc))
      (else
       (loop (cdr hooks) (cons (car hooks) acc))))))

(define (reset-pass-registry-init-hooks!)
  (set-car! *pass-registry-init-hooks* '()))

(define (register-pass! descriptor)
  (let* ((id (pass-id descriptor))
         (current (car *pass-registry*))
         (filtered (let loop ((ps current))
                     (cond
                       ((null? ps) '())
                       ((eq? (pass-id (car ps)) id) (loop (cdr ps)))
                       (else (cons (car ps) (loop (cdr ps))))))))
    (set-car! *pass-registry* (append filtered (list descriptor)))
    id))

(define (lookup-pass id)
  (let loop ((ps (car *pass-registry*)))
    (cond
      ((null? ps)
       (error "lookup-pass: unknown compiler pass" id))
      ((eq? (pass-id (car ps)) id)
       (car ps))
      (else
       (loop (cdr ps))))))

(define (pass-registered? id)
  (let loop ((ps (car *pass-registry*)))
    (cond
      ((null? ps) #f)
      ((eq? (pass-id (car ps)) id) #t)
      (else (loop (cdr ps))))))

(define (inject-pass-after! target-id descriptor)
  (let* ((id (pass-id descriptor))
         (current (car *pass-registry*))
         ;; First, filter out any existing entry with the same id to avoid duplicates
         (cleaned (let filter-loop ((ps current))
                    (cond
                      ((null? ps) '())
                      ((eq? (pass-id (car ps)) id) (filter-loop (cdr ps)))
                      (else (cons (car ps) (filter-loop (cdr ps))))))))
    (let insert-loop ((ps cleaned) (acc '()) (found? #f))
      (cond
        ((null? ps)
         (if found?
             (begin
               (set-car! *pass-registry* (reverse acc))
               id)
             (error "inject-pass-after!: target pass not found in registry" target-id)))
        ((eq? (pass-id (car ps)) target-id)
         (insert-loop (cdr ps)
                      (cons descriptor (cons (car ps) acc))
                      #t))
        (else
         (insert-loop (cdr ps) (cons (car ps) acc) found?))))))

(define (inject-pass-before! target-id descriptor)
  (let* ((id (pass-id descriptor))
         (current (car *pass-registry*))
         (cleaned (let filter-loop ((ps current))
                    (cond
                      ((null? ps) '())
                      ((eq? (pass-id (car ps)) id) (filter-loop (cdr ps)))
                      (else (cons (car ps) (filter-loop (cdr ps))))))))
    (let insert-loop ((ps cleaned) (acc '()) (found? #f))
      (cond
        ((null? ps)
         (if found?
             (begin
               (set-car! *pass-registry* (reverse acc))
               id)
             (error "inject-pass-before!: target pass not found in registry" target-id)))
        ((eq? (pass-id (car ps)) target-id)
         (insert-loop (cdr ps)
                      (cons (car ps) (cons descriptor acc))
                      #t))
        (else
         (insert-loop (cdr ps) (cons (car ps) acc) found?))))))

(define (remove-injected-pass! id)
  (let* ((current (car *pass-registry*))
         (filtered (let loop ((ps current))
                     (cond
                       ((null? ps) '())
                       ((eq? (pass-id (car ps)) id) (loop (cdr ps)))
                       (else (cons (car ps) (loop (cdr ps))))))))
    (set-car! *pass-registry* filtered)
    id))

;;; -----------------------------------------------------------------------
;;; 2.1 Named Pipeline Registry (DSN-33-01 T6.1 / Issue #768)
;;; -----------------------------------------------------------------------

(define *pipeline-registry* (cons '() '()))

(define (pipeline-registry)
  (car *pipeline-registry*))

(define (reset-pipeline-registry!)
  (set-car! *pipeline-registry* '()))

(define (register-pipeline! descriptor)
  (let* ((name (pipeline-desc-name descriptor))
         (passes (pipeline-desc-passes descriptor))
         (current (car *pipeline-registry*))
         (filtered (let loop ((ps current))
                     (cond
                       ((null? ps) '())
                       ((eq? (pipeline-desc-name (car ps)) name) (loop (cdr ps)))
                       (else (cons (car ps) (loop (cdr ps))))))))
    ;; Validate prerequisites and language schema continuity
    (validate-pipeline-prerequisites-by-ids passes)
    (validate-pipeline-continuity-by-ids passes)
    (set-car! *pipeline-registry* (append filtered (list descriptor)))
    name))

(define (lookup-pipeline name)
  (let loop ((ps (car *pipeline-registry*)))
    (cond
      ((null? ps)
       (error "lookup-pipeline: unknown pipeline" name))
      ((eq? (pipeline-desc-name (car ps)) name)
       (car ps))
      (else
       (loop (cdr ps))))))

(define (pipeline-registered? name)
  (let loop ((ps (car *pipeline-registry*)))
    (cond
      ((null? ps) #f)
      ((eq? (pipeline-desc-name (car ps)) name) #t)
      (else (loop (cdr ps))))))

(define (list-pipelines)
  (map pipeline-desc-name (car *pipeline-registry*)))

;;; -----------------------------------------------------------------------
;;; 3. Pipeline Configuration & Tuning Options
;;; -----------------------------------------------------------------------

(define *pipeline-opt-level* (cons 2 '()))
(define (pipeline-opt-level) (car *pipeline-opt-level*))
(define (set-pipeline-opt-level! lvl) (set-car! *pipeline-opt-level* lvl))

(define *pipeline-time-passes* (cons #f '()))
(define (pipeline-time-passes?) (car *pipeline-time-passes*))
(define (enable-pipeline-time-passes!) (set-car! *pipeline-time-passes* #t))
(define (disable-pipeline-time-passes!) (set-car! *pipeline-time-passes* #f))

(define *pipeline-dump-ir* (cons #f '()))
(define (pipeline-dump-ir) (car *pipeline-dump-ir*))
(define (set-pipeline-dump-ir! target) (set-car! *pipeline-dump-ir* target))

(define *pipeline-print-after-all* (cons #f '()))
(define (pipeline-print-after-all?) (car *pipeline-print-after-all*))
(define (enable-pipeline-print-after-all!) (set-car! *pipeline-print-after-all* #t))
(define (disable-pipeline-print-after-all!) (set-car! *pipeline-print-after-all* #f))

(define *pipeline-disabled-passes* (cons '() '()))
(define (pipeline-disabled-passes) (car *pipeline-disabled-passes*))

(define (disable-pass! id)
  (if (not (memq id (car *pipeline-disabled-passes*)))
      (set-car! *pipeline-disabled-passes* (cons id (car *pipeline-disabled-passes*)))))

(define (enable-pass! id)
  (set-car! *pipeline-disabled-passes*
            (let loop ((ps (car *pipeline-disabled-passes*)))
              (cond
                ((null? ps) '())
                ((eq? (car ps) id) (loop (cdr ps)))
                (else (cons (car ps) (loop (cdr ps))))))))

(define (reset-pipeline-options!)
  (set-car! *pipeline-opt-level* 2)
  (set-car! *pipeline-time-passes* #f)
  (set-car! *pipeline-dump-ir* #f)
  (set-car! *pipeline-print-after-all* #f)
  (set-car! *pipeline-disabled-passes* '())
  (reset-analysis-cache!)
  (reset-disabled-picopasses!)
  (reset-picopass-provenance!)
  (disable-picopass-provenance!))

;;; -----------------------------------------------------------------------
;;; 4. Dynamic Pipeline Scheduling & Invariant Validation
;;; -----------------------------------------------------------------------

(define (pass-enabled? desc opt-level disabled-list)
  (let ((id (pass-id desc))
        (pass-opt (pass-opt-level desc))
        (mandatory (pass-mandatory? desc)))
    (if mandatory
        (not (memq id disabled-list))
        (and (<= pass-opt opt-level)
             (not (memq id disabled-list))))))

(define (build-pipeline opt-level disabled-list)
  (let ((all (car *pass-registry*)))
    (let loop ((ps all) (res '()))
      (if (null? ps)
          (reverse res)
          (let ((p (car ps)))
            (if (pass-enabled? p opt-level disabled-list)
                (loop (cdr ps) (cons p res))
                (loop (cdr ps) res)))))))

(define (validate-pipeline-prerequisites pass-list)
  (let loop ((ps pass-list) (seen '()))
    (if (null? ps)
        #t
        (let* ((p (car ps))
               (id (pass-id p))
               (prereqs (pass-prerequisites p)))
          (let check-prereqs ((reqs prereqs))
            (if (null? reqs)
                (loop (cdr ps) (cons id seen))
                (let ((req (car reqs)))
                  (if (not (memq req seen))
                      (error "validate-pipeline-prerequisites: missing required prerequisite pass"
                             (list 'pass id 'requires req))
                      (check-prereqs (cdr reqs))))))))))

;;; -----------------------------------------------------------------------
;;; 4.1 Pipeline Validation Engine (Prerequisites & Continuity)
;;; -----------------------------------------------------------------------

(define (check-pipeline-prerequisites-by-ids pass-ids)
  (let loop ((ids pass-ids) (seen '()))
    (if (null? ids)
        #t
        (let* ((pid (car ids))
               (p (if (pass-registered? pid) (lookup-pass pid) #f)))
          (if (not p)
              #f
              (let* ((prereqs (pass-prerequisites p)))
                (let check-prereqs ((reqs prereqs))
                  (if (null? reqs)
                      (loop (cdr ids) (cons pid seen))
                      (let ((req (car reqs)))
                        (if (not (memq req seen))
                            #f
                            (check-prereqs (cdr reqs))))))))))))

(define (validate-pipeline-prerequisites-by-ids pass-ids)
  (let loop ((ids pass-ids) (seen '()))
    (if (null? ids)
        #t
        (let* ((pid (car ids))
               (p (lookup-pass pid))
               (prereqs (pass-prerequisites p)))
          (let check-prereqs ((reqs prereqs))
            (if (null? reqs)
                (loop (cdr ids) (cons pid seen))
                (let ((req (car reqs)))
                  (if (not (memq req seen))
                      (error "validate-pipeline-prerequisites-by-ids: missing prerequisite pass"
                             (list 'pass pid 'requires req))
                      (check-prereqs (cdr reqs))))))))))

(define (nanopass-language-compatible? out-lang in-lang)
  (cond
    ((or (not out-lang) (not in-lang)) #t)
    ((or (eq? out-lang 'any) (eq? in-lang 'any)) #t)
    ((eq? out-lang in-lang) #t)
    ((and (or (eq? out-lang 'L_anf) (eq? out-lang 'L-StagePoly) (eq? out-lang 'L-Residual-ANF))
          (or (eq? in-lang 'L_anf) (eq? in-lang 'L-StagePoly) (eq? in-lang 'L-Residual-ANF)))
     #t)
    ((and (or (eq? out-lang 'L_lir_core) (eq? out-lang 'L_lir_managed) (eq? out-lang 'L_lir_raw) (eq? out-lang 'L_lir_canonical))
          (or (eq? in-lang 'L_lir_core) (eq? in-lang 'L_lir_managed) (eq? in-lang 'L_lir_raw) (eq? in-lang 'L_lir_canonical)))
     #t)
    (else #f)))

(define (check-pipeline-continuity-by-ids pass-ids)
  (let loop ((ids pass-ids) (prev-desc #f))
    (if (null? ids)
        #t
        (let* ((pid (car ids))
               (desc (if (pass-registered? pid) (lookup-pass pid) #f)))
          (if (not desc)
              #f
              (if (and prev-desc
                       (not (nanopass-language-compatible?
                              (pass-out-lang prev-desc)
                              (pass-in-lang desc))))
                  #f
                  (loop (cdr ids) desc)))))))

(define (validate-pipeline-continuity-by-ids pass-ids)
  (let loop ((ids pass-ids) (prev-desc #f))
    (if (null? ids)
        #t
        (let* ((pid (car ids))
               (desc (lookup-pass pid)))
          (if prev-desc
              (let ((out-lang (pass-out-lang prev-desc))
                    (in-lang (pass-in-lang desc)))
                (if (not (nanopass-language-compatible? out-lang in-lang))
                    (error "validate-pipeline-continuity: language schema mismatch between passes"
                           (list 'from (pass-id prev-desc) 'out-lang out-lang
                                 'to pid 'in-lang in-lang)))))
          (loop (cdr ids) desc)))))

;;; -----------------------------------------------------------------------
;;; 5. Pass Timing & Profiling Statistics
;;; -----------------------------------------------------------------------

(define *pass-manager-timer-ticks* (cons 0 '()))

(define (current-time-monotonic-us)
  (let ((p (sys-clock-gettime-monotonic)))
    (if (and (pair? p) (or (> (car p) 0) (> (cdr p) 0)))
        (+ (* (car p) 1000000) (quotient (cdr p) 1000))
        (begin
          (set-car! *pass-manager-timer-ticks* (+ (car *pass-manager-timer-ticks*) 1000))
          (car *pass-manager-timer-ticks*)))))

(define (current-time-monotonic-ms)
  (quotient (current-time-monotonic-us) 1000))

(define (current-heap-alloc-bytes)
  (gc-current-heap-bytes))

;; Formatters
(define (pad-right str width)
  (let ((len (string-length str)))
    (if (>= len width)
        str
        (let ((res (make-string width)))
          (let loop ((i 0))
            (if (< i len)
                (begin
                  (string-set! res i (string-ref str i))
                  (loop (+ i 1)))
                (let fill ((j len))
                  (if (< j width)
                      (begin
                        (string-set! res j #\space)
                        (fill (+ j 1)))
                      res))))))))

(define (pad-left str width)
  (let ((len (string-length str)))
    (if (>= len width)
        str
        (let* ((pad (- width len))
               (res (make-string width)))
          (let fill ((j 0))
            (if (< j pad)
                (begin
                  (string-set! res j #\space)
                  (fill (+ j 1)))
                (let loop ((i 0))
                  (if (< i len)
                      (begin
                        (string-set! res (+ pad i) (string-ref str i))
                        (loop (+ i 1)))
                      res))))))))

(define (format-fixed-2-ms us)
  (let* ((total-cs (quotient (+ us 5) 10))
         (whole (quotient total-cs 100))
         (frac (modulo total-cs 100))
         (whole-str (number->string whole))
         (frac-str (if (< frac 10)
                       (string-append "0" (number->string frac))
                       (number->string frac))))
    (string-append whole-str "." frac-str " ms")))

(define (format-fixed-1-pct part total)
  (if (<= total 0)
      " 0.0%"
      (let* ((scaled (quotient (* part 1000) total))
             (whole (quotient scaled 10))
             (frac (modulo scaled 10))
             (whole-str (number->string whole))
             (frac-str (number->string frac)))
        (string-append whole-str "." frac-str "%"))))

(define (format-alloc-kb bytes)
  (if (<= bytes 0)
      "0 KB"
      (let ((kb (quotient (+ bytes 1023) 1024)))
        (string-append (number->string kb) " KB"))))

;; Timing Record
(define (make-pass-timing-entry id name elapsed-us alloc-bytes)
  (list id name elapsed-us alloc-bytes))

(define (pass-timing-id e) (car e))
(define (pass-timing-name e) (cadr e))
(define (pass-timing-elapsed-us e) (caddr e))
(define (pass-timing-alloc-bytes e) (cadddr e))

(define *pass-timings* (cons '() '()))

(define (reset-pass-timings!)
  (set-car! *pass-timings* '()))

(define (record-pass-timing! pass-id pass-name elapsed-us alloc-bytes)
  (set-car! *pass-timings*
            (append (car *pass-timings*)
                    (list (make-pass-timing-entry pass-id pass-name elapsed-us alloc-bytes)))))

(define (get-pass-timings)
  (car *pass-timings*))

(define *pass-id-names*
  '((pass-010-library . "pass-010-library")
    (pass-015-dsl-expander . "pass-015-dsl-expander")
    (pass-020-macro-expander . "pass-020-macro-expander")
    (pass-025-top-level . "pass-025-top-level")
    (pass-030-desugar . "pass-030-desugar")
    (pass-035-scope-resolve . "pass-035-scope-resolve")
    (pass-050-cp0 . "pass-050-cp0")
    (pass-060-lvn . "pass-060-lvn")
    (pass-070-anf . "pass-070-anf")
    (pass-075-stage-poly-lower . "pass-075-stage-poly-lower")
    (pass-080-annotator . "pass-080-annotator")
    (pass-090-rtyper . "pass-090-rtyper")
    (pass-100-contify . "pass-100-contify")
    (pass-110-closure-convert . "pass-110-closure-convert")
    (pass-120-alias-escape . "pass-120-alias-escape")
    (pass-130-lir . "pass-130-lir")
    (pass-128-lir-branch-fusion . "pass-128-lir-branch-fusion")
    (pass-133-lir-peephole . "pass-133-lir-peephole")
    (pass-140-backend-x86-64 . "pass-140-backend-x86-64")
    (pass-144-backend-x86-elf . "pass-144-backend-x86-elf")
    (pass-150-backend-aarch64 . "pass-150-backend-aarch64")
    (pass-160-backend-c . "pass-160-backend-c")))

(define (pass-id->string pid)
  (if (string? pid)
      pid
      (let ((entry (assq pid *pass-id-names*)))
        (if entry
            (cdr entry)
            (if (symbol? pid)
                (let ((s (symbol->string pid)))
                  (if (string=? s "?")
                      "pass"
                      s))
                "pass")))))

;; Stderr print wrappers
(define (display-stderr msg)
  (display msg (get-compiler-error-port)))

(define (newline-stderr)
  (newline (get-compiler-error-port)))

(define (print-pass-timing-report)
  (let* ((timings (car *pass-timings*))
         (total-us (let loop ((ts timings) (acc 0))
                     (if (null? ts)
                         acc
                         (loop (cdr ts) (+ acc (pass-timing-elapsed-us (car ts)))))))
         (total-bytes (let loop ((ts timings) (acc 0))
                        (if (null? ts)
                            acc
                            (loop (cdr ts) (+ acc (pass-timing-alloc-bytes (car ts))))))))
    (display-stderr "\n========================================================================================\n")
    (display-stderr "ULisp Nanopass Execution Profile (--time-passes)\n")
    (display-stderr "========================================================================================\n")
    (display-stderr "Pass ID                  Pass Name                         Time (ms)  Share (%)   Heap (KB)\n")
    (display-stderr "----------------------------------------------------------------------------------------\n")
    (let loop ((ts timings))
      (if (pair? ts)
          (let* ((entry (car ts))
                 (pid (pass-timing-id entry))
                 (pname (pass-timing-name entry))
                 (us (pass-timing-elapsed-us entry))
                 (bytes (pass-timing-alloc-bytes entry))
                 (id-str (pass-id->string pid))
                 (name-str (if (string? pname) pname (if (symbol? pname) (symbol->string pname) id-str)))
                 (time-str (format-fixed-2-ms us))
                 (share-str (format-fixed-1-pct us total-us))
                 (heap-str (format-alloc-kb bytes)))
            (display-stderr (pad-right id-str 24))
            (display-stderr " ")
            (display-stderr (pad-right name-str 32))
            (display-stderr " ")
            (display-stderr (pad-left time-str 11))
            (display-stderr " ")
            (display-stderr (pad-left share-str 10))
            (display-stderr " ")
            (display-stderr (pad-left heap-str 10))
            (newline-stderr)
            (loop (cdr ts)))))
    (display-stderr "----------------------------------------------------------------------------------------\n")
    (display-stderr "Total Compilation Time : ")
    (display-stderr (format-fixed-2-ms total-us))
    (newline-stderr)
    (display-stderr "Total Heap Allocation  : ")
    (display-stderr (format-alloc-kb total-bytes))
    (newline-stderr)
    (display-stderr "========================================================================================\n\n")))


;;; -----------------------------------------------------------------------
;;; 6. IR Dump & Observability
;;; -----------------------------------------------------------------------

(define (dump-pass-ir pass-id stage ast)
  (display "\n----------------------------------------------------------------------\n")
  (display "[PASS MANAGER IR DUMP] ")
  (display pass-id)
  (display " (")
  (display stage)
  (display ")\n")
  (display "----------------------------------------------------------------------\n")
  (write (truncate-expr-for-diagnostics ast))
  (newline)
  (display "======================================================================\n\n"))

;;; -----------------------------------------------------------------------
;;; 7. Pipeline Execution Engine
;;; -----------------------------------------------------------------------

(define (run-single-pass pass-desc input-ast verify-mode trace-mode)
  (let* ((id (pass-id pass-desc))
         (pname (pass-name pass-desc))
         (fn (pass-fn pass-desc))
         (vphase (pass-verifier-phase pass-desc))
         (invoke-pass-fn
          (lambda ()
            (let* ((pres-list (pass-preserves-analyses pass-desc))
                   (inv-list (pass-invalidates-analyses pass-desc))
                   (inv-femto? (and inv-list
                                    (or (memq 'all inv-list)
                                        (memq 'femto-attrs inv-list))))
                   (pres-femto? (and pres-list
                                     (or (memq 'all pres-list)
                                         (memq 'femto-attrs pres-list))))
                   (prev-in-runner (nanopass-in-pipeline-runner?)))
              (set-nanopass-in-pipeline-runner! #t)
              (let ((res (guard (ex (else
                                     (set-nanopass-in-pipeline-runner! prev-in-runner)
                                     (if inv-femto?
                                         (femto-cache-reset!)
                                         (if (not pres-femto?)
                                             (femto-cache-reset!)))
                                     (raise ex)))
                           (ensure-pass-required-analyses! pass-desc input-ast)
                           (with-nanopass-term-memo
                             (lambda ()
                               (fn input-ast))))))
                (set-nanopass-in-pipeline-runner! prev-in-runner)
                (if (not (and (not inv-femto?)
                              (or pres-femto?
                                  (eq? res input-ast))))
                    (femto-cache-reset!))
                (apply-pass-analysis-invalidation! pass-desc input-ast res)
                res)))))
    (set-current-pass! id)
    (if (or trace-mode (nanopass-trace-enabled?) (picopass-provenance-enabled?))
        (reset-picopass-provenance!))
    (with-call-frame id input-ast
      (lambda ()
        (if (pipeline-time-passes?)
            (let* ((t0 (current-time-monotonic-us))
                   (m0 (current-heap-alloc-bytes))
                   (output-ast (invoke-pass-fn))
                   (t1 (current-time-monotonic-us))
                   (m1 (current-heap-alloc-bytes))
                   (elapsed-us (let ((d (- t1 t0))) (if (< d 0) 0 d)))
                   (alloc-bytes (let ((d (- m1 m0))) (if (< d 0) 0 d))))
              (record-pass-timing! id pname elapsed-us alloc-bytes)
              (if (or trace-mode (nanopass-trace-enabled?) (picopass-provenance-enabled?))
                  (nanopass-display-ast-diff id input-ast output-ast))
              (if (or (pipeline-print-after-all?)
                      (eq? (pipeline-dump-ir) id)
                      (eq? (pipeline-dump-ir) 'all))
                  (dump-pass-ir id 'output output-ast))
              (if (and verify-mode vphase)
                  (if (not (verify-pass-output vphase output-ast))
                      (error "IR Verifier Invariant Violation in pass" id)))
              (if (or (eq? (pass-out-lang pass-desc) 'L-Residual-ANF)
                      (eq? vphase 'residual-anf)
                      (eq? vphase 'stage-poly-lower))
                  (if (not (verify-residual-anf-conformance output-ast))
                      (error "Grammar Conformance Violation: residual AST contains meta-syntax in pass" id)
                      output-ast)
                  output-ast))
            (let ((output-ast (invoke-pass-fn)))
              (if (or trace-mode (nanopass-trace-enabled?) (picopass-provenance-enabled?))
                  (nanopass-display-ast-diff id input-ast output-ast))
              (if (or (pipeline-print-after-all?)
                      (eq? (pipeline-dump-ir) id)
                      (eq? (pipeline-dump-ir) 'all))
                  (dump-pass-ir id 'output output-ast))
              (if (and verify-mode vphase)
                  (if (not (verify-pass-output vphase output-ast))
                      (error "IR Verifier Invariant Violation in pass" id)))
              (if (or (eq? (pass-out-lang pass-desc) 'L-Residual-ANF)
                      (eq? vphase 'residual-anf)
                      (eq? vphase 'stage-poly-lower))
                  (if (not (verify-residual-anf-conformance output-ast))
                      (error "Grammar Conformance Violation: residual AST contains meta-syntax in pass" id)
                      output-ast)
                  output-ast)))))))

(define (run-pass-pipeline forms verify-mode trace-mode)
  (if (null? (car *pass-registry*))
      (init-default-pass-registry!))
  (reset-nanopass-verification-cache!)
  (reset-analysis-cache!)
  (femto-cache-reset!)
  (nanopass-term-memo-reset!)
  (nanopass-hash-cons-reset!)
  (if verify-mode
      (begin
        (enable-verifier!)
        (if (eq? verify-mode 'strict)
            (set-verifier-strict! #t))))
  (let ((prev-trace (nanopass-trace-enabled?)))
    (if trace-mode
        (enable-nanopass-trace!))
    (let* ((opt-level (pipeline-opt-level))
           (disabled (pipeline-disabled-passes))
           (pipeline (build-pipeline opt-level disabled)))
      (validate-pipeline-prerequisites pipeline)
      (reset-pass-timings!)
      (let loop ((ps pipeline) (current-ast forms))
        (if (null? ps)
            (begin
              (if (not prev-trace)
                  (disable-nanopass-trace!))
              (if verify-mode
                  (if (not (verify-pass-output 'lir current-ast))
                      (error "IR Verifier Invariant Violation in final LIR" current-ast)))
              current-ast)
            (let ((next-ast (run-single-pass (car ps) current-ast verify-mode trace-mode)))
              (loop (cdr ps) next-ast)))))))

;;; -----------------------------------------------------------------------
;;; 7.1 Named Pipeline Execution Engine (DSN-33-01 T6.1 / Issue #768)
;;; -----------------------------------------------------------------------

(define *current-pipeline-name* (cons 'aot-native-pipeline '()))

(define (current-pipeline-name)
  (car *current-pipeline-name*))

(define (select-pipeline! name)
  (if (null? (car *pipeline-registry*))
      (init-default-pipeline-registry!))
  (if (not (pipeline-registered? name))
      (error "select-pipeline!: pipeline not registered" name))
  (set-car! *current-pipeline-name* name)
  name)

(define (run-named-pipeline name forms verify-mode trace-mode)
  (if (null? (car *pass-registry*))
      (init-default-pass-registry!))
  (if (null? (car *pipeline-registry*))
      (init-default-pipeline-registry!))
  (if (not (pipeline-registered? name))
      (error "run-named-pipeline: pipeline not found in registry" name))
  (let* ((pdesc (lookup-pipeline name))
         (pass-ids (pipeline-desc-passes pdesc))
         (target-ir (pipeline-desc-target-ir pdesc)))
    (reset-nanopass-verification-cache!)
    (reset-analysis-cache!)
    (femto-cache-reset!)
    (nanopass-term-memo-reset!)
    (nanopass-hash-cons-reset!)
    (if verify-mode
        (begin
          (enable-verifier!)
          (if (eq? verify-mode 'strict)
              (set-verifier-strict! #t))))
    (let ((prev-trace (nanopass-trace-enabled?)))
      (if trace-mode
          (enable-nanopass-trace!))
      (reset-pass-timings!)
      (let loop ((ids pass-ids) (current-ast forms))
        (if (null? ids)
            (begin
              (if (not prev-trace)
                  (disable-nanopass-trace!))
              (if (and verify-mode (eq? target-ir 'lir))
                  (if (not (verify-pass-output 'lir current-ast))
                      (error "IR Verifier Invariant Violation in final LIR" current-ast)))
              current-ast)
            (let* ((desc (lookup-pass (car ids)))
                   (next-ast (run-single-pass desc current-ast verify-mode trace-mode)))
              (loop (cdr ids) next-ast)))))))

(define (run-current-pipeline forms verify-mode trace-mode)
  (run-named-pipeline (current-pipeline-name) forms verify-mode trace-mode))

;;; -----------------------------------------------------------------------
;;; 7.2 Bounded Iterative Fixpoint Optimization Driver (Issue #840)
;;; -----------------------------------------------------------------------

(define *default-fixpoint-max-iterations* 32)
(define *last-fixpoint-iterations* (cons 0 '()))
(define *last-fixpoint-converged?* (cons #t '()))

(define (last-fixpoint-iterations) (car *last-fixpoint-iterations*))
(define (last-fixpoint-converged?) (car *last-fixpoint-converged?*))

(define (resolve-fixpoint-pass-descriptor spec)
  (cond
   ((pass-descriptor? spec) spec)
   ((symbol? spec)
    (let ((desc (lookup-pass spec)))
      (if (not desc)
          (error "run-pass-fixpoint: pass not found in registry" spec)
          desc)))
   ((procedure? spec)
    (make-pass-descriptor 'fixpoint-anon-pass "Fixpoint Pass" 'frontend 0
      spec #f 'L_any 'L_any '() #f))
   (else
    (error "run-pass-fixpoint: invalid pass spec" spec))))

(define (parse-fixpoint-opts opts)
  (let loop ((rem opts)
             (max-iters *default-fixpoint-max-iterations*)
             (equiv-fn equal?)
             (verify-mode #f)
             (trace-mode #f)
             (on-limit 'return)
             (pos 0))
    (if (null? rem)
        (list max-iters equiv-fn verify-mode trace-mode on-limit)
        (let ((k (car rem)))
          (cond
           ((or (eq? k ':max-iterations) (eq? k 'max-iterations))
            (if (null? (cdr rem))
                (error "run-pass-fixpoint: missing value for :max-iterations")
                (loop (cddr rem) (cadr rem) equiv-fn verify-mode trace-mode on-limit pos)))
           ((or (eq? k ':equiv?) (eq? k 'equiv?))
            (if (null? (cdr rem))
                (error "run-pass-fixpoint: missing value for :equiv?")
                (loop (cddr rem) max-iters (cadr rem) verify-mode trace-mode on-limit pos)))
           ((or (eq? k ':verify) (eq? k 'verify) (eq? k ':verify-mode) (eq? k 'verify-mode))
            (if (null? (cdr rem))
                (error "run-pass-fixpoint: missing value for :verify")
                (loop (cddr rem) max-iters equiv-fn (cadr rem) trace-mode on-limit pos)))
           ((or (eq? k ':trace) (eq? k 'trace) (eq? k ':trace-mode) (eq? k 'trace-mode))
            (if (null? (cdr rem))
                (error "run-pass-fixpoint: missing value for :trace")
                (loop (cddr rem) max-iters equiv-fn verify-mode (cadr rem) on-limit pos)))
           ((or (eq? k ':on-limit) (eq? k 'on-limit))
            (if (null? (cdr rem))
                (error "run-pass-fixpoint: missing value for :on-limit")
                (loop (cddr rem) max-iters equiv-fn verify-mode trace-mode (cadr rem) pos)))
           ((and (= pos 0) (integer? k))
            (loop (cdr rem) k equiv-fn verify-mode trace-mode on-limit (+ pos 1)))
           ((and (= pos 1) (procedure? k))
            (loop (cdr rem) max-iters k verify-mode trace-mode on-limit (+ pos 1)))
           (else
            (error "run-pass-fixpoint: unexpected option" k)))))))

(define (run-pass-fixpoint-opts pass-specs initial-ast opts)
  (let* ((parsed (parse-fixpoint-opts opts))
         (max-iters (car parsed))
         (equiv-fn (cadr parsed))
         (verify-mode (caddr parsed))
         (trace-mode (cadddr parsed))
         (on-limit (car (cddddr parsed)))
         (descs (map resolve-fixpoint-pass-descriptor pass-specs)))
    (if (< max-iters 0)
        (error "run-pass-fixpoint: max-iterations must be non-negative" max-iters))
    (let iter-loop ((iter 0) (ast initial-ast))
      (if (>= iter max-iters)
          (begin
            (set-car! *last-fixpoint-iterations* iter)
            (set-car! *last-fixpoint-converged?* #f)
            (if (eq? on-limit 'error)
                (raise (list 'fixpoint-max-iterations-error iter))
                ast))
          (let pass-loop ((ps descs) (cur-ast ast))
            (if (null? ps)
                (let ((next-iter (+ iter 1)))
                  (if (equiv-fn cur-ast ast)
                      (begin
                        (set-car! *last-fixpoint-iterations* next-iter)
                        (set-car! *last-fixpoint-converged?* #t)
                        cur-ast)
                      (iter-loop next-iter cur-ast)))
                (pass-loop (cdr ps)
                           (run-single-pass (car ps) cur-ast verify-mode trace-mode))))))))

(define run-pass-fixpoint
  (case-lambda
    ((pass-specs initial-ast)
     (run-pass-fixpoint-opts pass-specs initial-ast '()))
    ((pass-specs initial-ast o1)
     (run-pass-fixpoint-opts pass-specs initial-ast (list o1)))
    ((pass-specs initial-ast o1 o2)
     (run-pass-fixpoint-opts pass-specs initial-ast (list o1 o2)))
    ((pass-specs initial-ast o1 o2 o3)
     (run-pass-fixpoint-opts pass-specs initial-ast (list o1 o2 o3)))
    ((pass-specs initial-ast o1 o2 o3 o4)
     (run-pass-fixpoint-opts pass-specs initial-ast (list o1 o2 o3 o4)))))

;;; -----------------------------------------------------------------------
;;; 8. Default Pass Registry Initialization
;;; -----------------------------------------------------------------------

(define *aot-native-pipeline-passes*
  '(pass-010-library
    pass-015-dsl-expander
    pass-020-macro-expander
    pass-025-top-level
    pass-030-desugar
    pass-035-scope-resolve
    pass-040-analysis
    pass-050-cp0
    pass-060-lvn
    pass-070-anf
    pass-075-stage-poly-lower
    pass-080-annotator
    pass-090-rtyper
    pass-100-contify
    pass-110-closure-convert
    pass-120-alias-escape
    pass-130-lir
    pass-131-lower-managed-dialect
    pass-128-lir-branch-fusion
    pass-133-lir-peephole))

(define *repl-fast-pipeline-passes*
  '(pass-010-library
    pass-015-dsl-expander
    pass-020-macro-expander
    pass-025-top-level
    pass-030-desugar
    pass-035-scope-resolve
    pass-070-anf
    pass-110-closure-convert
    pass-130-lir
    pass-131-lower-managed-dialect))

(define *static-check-pipeline-passes*
  '(pass-010-library
    pass-015-dsl-expander
    pass-020-macro-expander
    pass-025-top-level
    pass-030-desugar
    pass-035-scope-resolve
    pass-040-analysis))

(define (init-default-pipeline-registry!)
  (reset-pipeline-registry!)
  (register-pipeline!
    (make-pipeline-descriptor
      'aot-native-pipeline
      "Full AOT compilation pipeline with complete optimization and LIR generation"
      *aot-native-pipeline-passes*
      'lir
      '()))
  (register-pipeline!
    (make-pipeline-descriptor
      'repl-fast-pipeline
      "Ultra-low-latency REPL evaluation pipeline skipping middle-end optimizations"
      *repl-fast-pipeline-passes*
      'lir
      '()))
  (register-pipeline!
    (make-pipeline-descriptor
      'static-check-pipeline
      "Static verification pipeline for diagnostics and LSP without code emission"
      *static-check-pipeline-passes*
      'ast
      '()))
  (set-car! *current-pipeline-name* 'aot-native-pipeline)
  #t)

(define (init-default-pass-registry!)
  (reset-pass-registry!)
  (if (null? (car *analysis-property-registry*))
      (init-default-analysis-properties!))
  ;; Frontend Passes (Opt 0 = Mandatory, Opt 1/2 = Optimization)
  (register-pass!
    (make-pass-descriptor 'pass-010-library "Desugar Libraries and Imports" 'frontend 0
      (lambda (forms) (desugar-libraries-and-imports forms)) #f 'L_cst 'L_cst '() #t))
  (register-pass!
    (make-pass-descriptor 'pass-015-dsl-expander "DSL Expander" 'frontend 0
      (lambda (forms) (expand-dsl-forms forms)) #f 'L_cst 'L_cst '(pass-010-library) #t))
  (register-pass!
    (make-pass-descriptor 'pass-020-macro-expander "Hygienic Macro Expander" 'frontend 0
      (lambda (forms) (expand-macros-in-forms forms)) #f 'L_cst 'L_src '(pass-015-dsl-expander) #t))
  (register-pass!
    (make-pass-descriptor 'pass-025-top-level "Rewrite Top-Level" 'frontend 0
      (lambda (forms) (rewrite-top-level forms)) #f 'L_src 'L_src '(pass-020-macro-expander) #t))
  (register-pass!
    (make-pass-descriptor 'pass-030-desugar "Core Desugar All" 'frontend 0
      (lambda (forms) (desugar-all forms)) 'desugar 'L_src 'L_core '(pass-025-top-level) #t))
  (register-pass!
    (make-pass-descriptor 'pass-035-scope-resolve "Lexical Scope Resolution and Alpha-Conversion" 'frontend 0
      (lambda (forms) (scope-resolve-all forms)) #f 'L_core 'L_core '(pass-030-desugar) #t))
  (register-pass!
    (make-pass-descriptor-with-opts 'pass-040-analysis "Static Arity & Scope Analysis" 'frontend 0
      (lambda (forms) (check-arity-all forms)) #f 'L_core 'L_core '(pass-030-desugar) #t
      (list ':preserves '(all))))
  (register-pass!
    (make-pass-descriptor 'pass-050-cp0 "CP0 Source Optimization" 'frontend 1
      (lambda (forms) (cp0-optimize forms)) #f 'L_core 'L_core '(pass-030-desugar) #f))
  (register-pass!
    (make-pass-descriptor 'pass-060-lvn "Local Value Numbering" 'frontend 2
      (lambda (forms) (lvn-all forms)) #f 'L_core 'L_core '(pass-030-desugar) #f))
  (register-pass!
    (make-pass-descriptor 'pass-070-anf "A-Normal Form Conversion" 'frontend 0
      (lambda (forms) (anf-all forms)) 'anf 'L_core 'L_anf '(pass-030-desugar) #t))
  (register-pass!
    (make-pass-descriptor 'pass-075-stage-poly-lower "Stage-Polymorphic Partial Evaluator" 'frontend 1
      (lambda (forms)
        (if (contains-stage-meta-syntax? forms)
            (stage-poly-lower-all forms)
            forms))
      'stage-poly-lower 'L-StagePoly 'L-Residual-ANF '(pass-070-anf) #f))
  (register-pass!
    (make-pass-descriptor 'pass-080-annotator "Abstract Interpretation Annotator" 'frontend 2
      (lambda (forms) (annotate-all forms)) #f 'L_anf 'L_anf '(pass-070-anf) #f))
  (register-pass!
    (make-pass-descriptor 'pass-090-rtyper "Representation Typer & Unboxing" 'frontend 2
      (lambda (forms) (rtyper-all forms)) #f 'L_anf 'L_anf '(pass-070-anf) #f))
  (register-pass!
    (make-pass-descriptor 'pass-100-contify "Contification" 'frontend 2
      (lambda (forms) (contify-all forms)) #f 'L_anf 'L_anf '(pass-070-anf) #f))
  (register-pass!
    (make-pass-descriptor 'pass-110-closure-convert "Closure Conversion" 'frontend 0
      (lambda (forms) (closure-convert forms)) 'closure 'L_anf 'L_lifted '(pass-070-anf) #t))
  (register-pass!
    (make-pass-descriptor 'pass-120-alias-escape "TBAA and Escape Analysis" 'frontend 2
      (lambda (forms) (alias-escape-all forms)) #f 'L_lifted 'L_lifted '(pass-110-closure-convert) #f))
  ;; Middle-End / LIR Passes
  (register-pass!
    (make-pass-descriptor 'pass-130-lir "LIR Lowering and Generation" 'middle 0
      (lambda (forms) (generate-lir forms)) #f 'L_lifted 'L_lir_raw '(pass-110-closure-convert) #t))
  (register-pass!
    (make-pass-descriptor 'pass-131-lower-managed-dialect "Lower Managed Runtime Dialect" 'middle 0
      (lambda (lir) (lower-managed-dialect lir)) 'core-lir 'L_lir_managed 'L_lir_core '(pass-130-lir) #t))
  (register-pass!
    (make-pass-descriptor-with-opts 'pass-128-lir-branch-fusion "LIR Branch Fusion" 'middle 2
      (lambda (lir) (lir-fuse-branches lir)) #f 'L_lir_core 'L_lir_core '(pass-130-lir) #f
      (list ':invalidates '(cfg-dominators variable-liveness))))
  (register-pass!
    (make-pass-descriptor-with-opts 'pass-133-lir-peephole "LIR Peephole Optimization" 'middle 1
      (lambda (lir) (lir-peephole-optimize lir)) 'lir 'L_lir_core 'L_lir_canonical '(pass-130-lir) #f
      (list ':preserves '(cfg-dominators) ':invalidates '(variable-liveness alias-sets))))
  ;; Execute external pluggable pass initialization hooks (e.g. Synapse Reduction Safepoints)
  (let loop ((hooks (car *pass-registry-init-hooks*)))
    (if (not (null? hooks))
        (begin
          ((car hooks))
          (loop (cdr hooks)))))
  (init-default-pipeline-registry!)
  #t)

;;; -----------------------------------------------------------------------
;;; 10. Rule-level Auto-Bisect (Delta Debugging) Engine (DSN-33-01 T6.2)
;;; -----------------------------------------------------------------------

(define (picopass-split-list lst k)
  (let loop ((rem lst) (i k) (acc '()))
    (if (or (null? rem) (<= i 0))
        (cons (reverse acc) rem)
        (loop (cdr rem) (- i 1) (cons (car rem) acc)))))

(define (auto-bisect-picopasses candidate-rules test-fn)
  (let* ((rule-ids (map (lambda (r) (if (rule-descriptor? r) (rule-name r) r)) candidate-rules))
         (saved-disabled (disabled-picopasses)))
    (dynamic-wind
      (lambda () #f)
      (lambda ()
        (reset-disabled-picopasses!)
        ;; Step 1: Does the bug reproduce when all candidate rules are enabled?
        (if (test-fn)
            #f ; Bug is not reproduced (test-fn passed)
            ;; Step 2: Does the bug disappear when ALL candidate rules are disabled?
            (let ((passes-when-all-disabled?
                   (with-disabled-picopasses rule-ids test-fn)))
              (if (not passes-when-all-disabled?)
                  'cannot-isolate-all-disabled-still-fails
                  ;; Step 3: Delta debugging recursive bisection
                  (let bisect ((rules rule-ids))
                    (cond
                      ((null? rules) #f)
                      ((= (length rules) 1)
                       (car rules)) ; Isolated single culprit rule!
                      (else
                       (let* ((mid (quotient (length rules) 2))
                              (split (picopass-split-list rules mid))
                              (r1 (car split))
                              (r2 (cdr split)))
                         ;; Test if failure persists without r1
                         (let ((fails-without-r1?
                                (not (with-disabled-picopasses r1 test-fn))))
                           (if fails-without-r1?
                               (bisect r2)
                               ;; Otherwise test if failure persists without r2
                               (let ((fails-without-r2?
                                      (not (with-disabled-picopasses r2 test-fn))))
                                 (if fails-without-r2?
                                     (bisect r1)
                                     ;; Both subsets needed -> interaction bug
                                     (list 'interaction r1 r2)))))))))))))
      (lambda ()
        (set-car! *disabled-picopasses* saved-disabled)))))
