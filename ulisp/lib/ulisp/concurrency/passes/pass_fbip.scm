;;; =======================================================================
;;; Synapse Concurrency Library: FBIP (Perceus) In-Place Reuse Pass
;;; Path: lib/ulisp/concurrency/passes/pass_fbip.scm
;;; Conforms to DSN-37 Section 1.1, 12.3 & Phase 3 Task 3.3 (Issue #639)
;;;
;;; Pluggable Compiler Pass provided by (ulisp concurrency):
;;; Injected after pass-synapse-check-affine via
;;; (inject-synapse-fbip-pass!).
;;;
;;; Optimizes immutable data structure updates within ASC kernels:
;;; Statically identifies pairs/vectors that have no live aliases and are
;;; marked for RAII drop, and converts fresh heap allocations (cons, etc.)
;;; into direct in-place memory reuse (%fbip-reuse-pair!), bypassing arena
;;; bump-pointer advancement for zero-allocation recursive loops.
;;; =======================================================================

;;; -----------------------------------------------------------------------
;;; 1. Utilities & AST Predicates
;;; -----------------------------------------------------------------------

(define (affine-drop-form? expr)
  (and (pair? expr)
       (eq? (car expr) '%affine-drop!)
       (pair? (cdr expr))
       (symbol? (cadr expr))))

(define (affine-drop-var expr)
  (cadr expr))

(define (cons-form? expr)
  (and (pair? expr)
       (eq? (car expr) 'cons)
       (pair? (cdr expr))
       (pair? (cddr expr))
       (null? (cdddr expr))))

(define (collect-drops expr)
  (let loop ((e expr) (acc '()))
    (cond
      ((not (pair? e)) acc)
      ((affine-drop-form? e)
       (let ((v (affine-drop-var e)))
         (if (memq v acc) acc (cons v acc))))
      (else
       (let inner ((items e) (cur-acc acc))
         (if (null? items)
             cur-acc
             (if (pair? items)
                 (inner (cdr items) (loop (car items) cur-acc))
                 cur-acc)))))))

;;; -----------------------------------------------------------------------
;;; 2. FBIP Pattern Matching & In-Place Transformation
;;; -----------------------------------------------------------------------

(define (fbip-transform-block expr available-drops)
  ;; Recursively walks the expression, attempting to match:
  ;; 1. Fresh (cons e1 e2) when a reusable pair drop is in available-drops
  ;; 2. Removes the now-redundant (%affine-drop! target)
  (cond
    ((not (pair? expr))
     (cons expr available-drops))

    ;; Quote
    ((eq? (car expr) 'quote)
     (cons expr available-drops))

    ;; Drop form: if its variable was already consumed for reuse, eliminate it!
    ((affine-drop-form? expr)
     (let ((v (affine-drop-var expr)))
       (if (not (memq v available-drops))
           ;; Already reused! Eliminate this drop by replacing with #f
           (cons #f available-drops)
           ;; Still active drop
           (cons expr available-drops))))

    ;; Fresh cons: if we have a reusable drop available, convert to in-place reuse!
    ((and (cons-form? expr) (pair? available-drops))
     (let* ((reuse-var (car available-drops))
            (remaining-drops (cdr available-drops))
            (e1 (cadr expr))
            (e2 (caddr expr))
            (r1 (fbip-transform-block e1 remaining-drops))
            (trans-e1 (car r1))
            (r2 (fbip-transform-block e2 (cdr r1)))
            (trans-e2 (car r2))
            (final-drops (cdr r2)))
       (cons (list '%fbip-reuse-pair! reuse-var trans-e1 trans-e2)
             final-drops)))

    ;; Sequence: (begin e ...)
    ((eq? (car expr) 'begin)
     (let loop ((items (cdr expr)) (acc-items '()) (cur-drops available-drops))
       (if (null? items)
           ;; Filter out eliminated #f drops from begin sequence
           (let ((filtered (let filter-loop ((es (reverse acc-items)))
                             (cond
                               ((null? es) '())
                               ((and (boolean? (car es)) (not (car es)))
                                (filter-loop (cdr es)))
                               (else
                                (cons (car es) (filter-loop (cdr es))))))))
             (cons (cond
                     ((null? filtered) #f)
                     ((null? (cdr filtered)) (car filtered))
                     (else (cons 'begin filtered)))
                   cur-drops))
           (let* ((res (fbip-transform-block (car items) cur-drops)))
             (loop (cdr items)
                   (cons (car res) acc-items)
                   (cdr res))))))

    ;; Conditional: (if test then [else])
    ((eq? (car expr) 'if)
     (let* ((test-r (fbip-transform-block (cadr expr) available-drops))
            (test-ast (car test-r))
            (then-r (fbip-transform-block (caddr expr) (cdr test-r)))
            (then-ast (car then-r))
            (has-else? (pair? (cdddr expr))))
       (if (not has-else?)
           (cons (list 'if test-ast then-ast) (cdr then-r))
           (let* ((else-r (fbip-transform-block (cadddr expr) (cdr test-r)))
                  (else-ast (car else-r)))
             (cons (list 'if test-ast then-ast else-ast)
                   (cdr then-r))))))

    ;; Local binding: (let ((v e) ...) body ...)
    ((and (eq? (car expr) 'let) (pair? (cdr expr)) (pair? (cadr expr)))
     (let* ((bindings (cadr expr))
            (bodies (cddr expr))
            ;; Collect drops inside body
            (body-drops (collect-drops (cons 'begin bodies)))
            (all-avail (let merge ((ds body-drops) (acc available-drops))
                         (if (null? ds)
                             acc
                             (if (memq (car ds) acc)
                                 (merge (cdr ds) acc)
                                 (merge (cdr ds) (cons (car ds) acc)))))))
       ;; Process bindings
       (let loop ((bs bindings) (acc-b '()) (cur-drops all-avail))
         (if (pair? bs)
             (let* ((b (car bs))
                    (v (car b))
                    (init-r (fbip-transform-block (cadr b) cur-drops)))
               (loop (cdr bs)
                     (cons (list v (car init-r)) acc-b)
                     (cdr init-r)))
             ;; Process body with collected drops
             (let* ((body-r (fbip-transform-block (cons 'begin bodies) cur-drops))
                    (b-ast (car body-r))
                    (b-elems (if (and (pair? b-ast) (eq? (car b-ast) 'begin))
                                 (cdr b-ast)
                                 (list b-ast))))
               (cons (cons 'let (cons (reverse acc-b) b-elems))
                     (cdr body-r)))))))

    ;; General application / recursive walk
    (else
     (let loop ((items expr) (acc '()) (cur-drops available-drops))
       (if (null? items)
           (cons (reverse acc) cur-drops)
           (let ((r (fbip-transform-block (car items) cur-drops)))
             (loop (cdr items)
                   (cons (car r) acc)
                   (cdr r))))))))

;;; -----------------------------------------------------------------------
;;; 3. ASC Kernel Transformation
;;; -----------------------------------------------------------------------

(define (fbip-transform-kernel kernel-node)
  (if (or (not (pair? kernel-node)) (not (eq? (car kernel-node) '%asc-kernel)))
      kernel-node
      (let* ((header (cadr kernel-node))
             (body (caddr kernel-node))
             ;; Collect all initial drop candidates inside kernel body
             (drops (collect-drops body))
             (trans-r (fbip-transform-block body drops))
             (trans-body (car trans-r)))
        (list '%asc-kernel header trans-body))))

(define (fbip-pass forms)
  (map (lambda (form)
         (if (and (pair? form) (eq? (car form) '%asc-kernel))
             (fbip-transform-kernel form)
             form))
       forms))

;;; -----------------------------------------------------------------------
;;; 4. Pluggable Pass Injection & Registration API
;;; -----------------------------------------------------------------------

(define (synapse-fbip-descriptor)
  (make-pass-descriptor
    'pass-synapse-fbip
    "Synapse FBIP (Perceus) In-Place Reuse Pass"
    'frontend
    0
    fbip-pass
    #f
    'L_core
    'L_core
    '(pass-synapse-check-affine)
    #t))

(define (inject-synapse-fbip-pass!)
  (inject-pass-after! 'pass-synapse-check-affine (synapse-fbip-descriptor)))

(define (remove-synapse-fbip-pass!)
  (remove-injected-pass! 'pass-synapse-fbip))

