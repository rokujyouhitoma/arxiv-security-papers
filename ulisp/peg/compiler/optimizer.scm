;;; =======================================================================
;;; PEG Grammar AST Optimizer (Prefix Factoring & Sequence Flattening)
;;; Conforms to DSN-25 Phase 2 & DSN-33-04 §3.2, Issue #894
;;; =======================================================================

(define (optimize-expr expr)
  (cond
    ((peg-seq-expr? expr)
     (let* ((opt-elements (map optimize-expr (peg-seq-expr-elements expr)))
            (flattened
             (let loop ((elts opt-elements) (acc '()))
               (if (null? elts)
                   (reverse acc)
                   (let ((e (car elts)))
                     (if (peg-seq-expr? e)
                         (loop (cdr elts) (append (reverse (peg-seq-expr-elements e)) acc))
                         (loop (cdr elts) (cons e acc))))))))
       (cond
         ((null? flattened) (make-peg-seq-expr '()))
         ((null? (cdr flattened)) (car flattened))
         (else (make-peg-seq-expr flattened)))))

    ((peg-choice-expr? expr)
     (let* ((opt-alts (map optimize-expr (peg-choice-expr-alternatives expr)))
            (flattened
             (let loop ((alts opt-alts) (acc '()))
               (if (null? alts)
                   (reverse acc)
                   (let ((a (car alts)))
                     (if (peg-choice-expr? a)
                         (loop (cdr alts) (append (reverse (peg-choice-expr-alternatives a)) acc))
                         (loop (cdr alts) (cons a acc))))))))
       (cond
         ((null? flattened) (make-peg-choice-expr '()))
         ((null? (cdr flattened)) (car flattened))
         (else (make-peg-choice-expr flattened)))))

    ((peg-repeat-expr? expr)
     (make-peg-repeat-expr (optimize-expr (peg-repeat-expr-expr expr))
                           (peg-repeat-expr-min-count expr)
                           (peg-repeat-expr-max-count expr)))

    ((peg-opt-expr? expr)
     (make-peg-opt-expr (optimize-expr (peg-opt-expr-expr expr))))

    ((peg-pred-expr? expr)
     (make-peg-pred-expr (optimize-expr (peg-pred-expr-expr expr))
                         (peg-pred-expr-positive? expr)))

    ((peg-gather-expr? expr)
     (make-peg-gather-expr (optimize-expr (peg-gather-expr-sep expr))
                           (optimize-expr (peg-gather-expr-elem expr))
                           (peg-gather-expr-one-or-more? expr)))

    ((peg-named-expr? expr)
     (make-peg-named-expr (peg-named-expr-name expr)
                          (optimize-expr (peg-named-expr-expr expr))))

    ((peg-action-expr? expr)
     (make-peg-action-expr (optimize-expr (peg-action-expr-expr expr))
                           (peg-action-expr-action-code expr)))

    (else expr)))

(define (optimize-rule rule)
  (make-peg-rule-def (peg-rule-def-name rule)
                     (optimize-expr (peg-rule-def-expr rule))
                     (peg-rule-def-memoize? rule)
                     (peg-rule-def-return-type rule)))

(define (optimize-grammar grammar)
  (make-peg-grammar-def (peg-grammar-def-name grammar)
                        (map optimize-rule (peg-grammar-def-rules grammar))
                        (peg-grammar-def-directives grammar)))
