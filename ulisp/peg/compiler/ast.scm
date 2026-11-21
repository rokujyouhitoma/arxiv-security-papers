;;; =======================================================================
;;; PEG Grammar Specification AST Node Definitions & S-Expression Isomorphism
;;; Conforms to DSN-25 Phase 2 & DSN-33-04 §3.2, Issue #894
;;; Homoiconic S-expression representation: ast->sexpr / sexpr->ast
;;; =======================================================================

;;; -----------------------------------------------------------------------
;;; 1. AST Record Definitions
;;; -----------------------------------------------------------------------

(define-record-type <peg-grammar-def>
  (make-peg-grammar-def name rules directives)
  peg-grammar-def?
  (name       peg-grammar-def-name)
  (rules      peg-grammar-def-rules)
  (directives peg-grammar-def-directives))

(define-record-type <peg-rule-def>
  (make-peg-rule-def name expr memoize? return-type)
  peg-rule-def?
  (name        peg-rule-def-name)
  (expr        peg-rule-def-expr)
  (memoize?    peg-rule-def-memoize?)
  (return-type peg-rule-def-return-type))

(define-record-type <peg-lit-expr>
  (make-peg-lit-expr val)
  peg-lit-expr?
  (val peg-lit-expr-val))

(define-record-type <peg-regex-expr>
  (make-peg-regex-expr pattern)
  peg-regex-expr?
  (pattern peg-regex-expr-pattern))

(define-record-type <peg-char-class-expr>
  (make-peg-char-class-expr spec inverted?)
  peg-char-class-expr?
  (spec      peg-char-class-expr-spec)
  (inverted? peg-char-class-expr-inverted?))

(define-record-type <peg-any-char-expr>
  (make-peg-any-char-expr)
  peg-any-char-expr?)

(define-record-type <peg-cut-expr>
  (make-peg-cut-expr)
  peg-cut-expr?)

(define-record-type <peg-line-start-expr>
  (make-peg-line-start-expr)
  peg-line-start-expr?)

(define-record-type <peg-seq-expr>
  (make-peg-seq-expr elements)
  peg-seq-expr?
  (elements peg-seq-expr-elements))

(define-record-type <peg-choice-expr>
  (make-peg-choice-expr alternatives)
  peg-choice-expr?
  (alternatives peg-choice-expr-alternatives))

(define-record-type <peg-repeat-expr>
  (make-peg-repeat-expr expr min-count max-count)
  peg-repeat-expr?
  (expr      peg-repeat-expr-expr)
  (min-count peg-repeat-expr-min-count)
  (max-count peg-repeat-expr-max-count))

(define-record-type <peg-opt-expr>
  (make-peg-opt-expr expr)
  peg-opt-expr?
  (expr peg-opt-expr-expr))

(define-record-type <peg-pred-expr>
  (make-peg-pred-expr expr positive?)
  peg-pred-expr?
  (expr      peg-pred-expr-expr)
  (positive? peg-pred-expr-positive?))

(define-record-type <peg-gather-expr>
  (make-peg-gather-expr sep elem one-or-more?)
  peg-gather-expr?
  (sep          peg-gather-expr-sep)
  (elem         peg-gather-expr-elem)
  (one-or-more? peg-gather-expr-one-or-more?))

(define-record-type <peg-rule-ref-expr>
  (make-peg-rule-ref-expr name)
  peg-rule-ref-expr?
  (name peg-rule-ref-expr-name))

(define-record-type <peg-named-expr>
  (make-peg-named-expr name expr)
  peg-named-expr?
  (name peg-named-expr-name)
  (expr peg-named-expr-expr))

(define-record-type <peg-action-expr>
  (make-peg-action-expr expr action-code)
  peg-action-expr?
  (expr        peg-action-expr-expr)
  (action-code peg-action-expr-action-code))

;;; -----------------------------------------------------------------------
;;; 2. S-Expression Isomorphism: ast->sexpr & sexpr->ast
;;; -----------------------------------------------------------------------

(define (ast->sexpr node)
  (cond
    ((peg-grammar-def? node)
     `(grammar ,(peg-grammar-def-name node)
        (directives ,@(peg-grammar-def-directives node))
        (rules ,@(map ast->sexpr (peg-grammar-def-rules node)))))
    ((peg-rule-def? node)
     `(rule ,(peg-rule-def-name node)
            ,@(if (peg-rule-def-memoize? node) '((memo)) '())
            ,@(if (peg-rule-def-return-type node) `((type ,(peg-rule-def-return-type node))) '())
            ,(ast->sexpr (peg-rule-def-expr node))))
    ((peg-lit-expr? node)
     `(lit ,(peg-lit-expr-val node)))
    ((peg-regex-expr? node)
     `(regex ,(peg-regex-expr-pattern node)))
    ((peg-char-class-expr? node)
     (if (peg-char-class-expr-inverted? node)
         `(char-class-inv ,(peg-char-class-expr-spec node))
         `(char-class ,(peg-char-class-expr-spec node))))
    ((peg-any-char-expr? node)
     'any-char)
    ((peg-cut-expr? node)
     'cut)
    ((peg-line-start-expr? node)
     'line-start)
    ((peg-seq-expr? node)
     `(: ,@(map ast->sexpr (peg-seq-expr-elements node))))
    ((peg-choice-expr? node)
     `(/ ,@(map ast->sexpr (peg-choice-expr-alternatives node))))
    ((peg-repeat-expr? node)
     (let ((min-c (peg-repeat-expr-min-count node)))
       (if (= min-c 1)
           `(+ ,(ast->sexpr (peg-repeat-expr-expr node)))
           `(* ,(ast->sexpr (peg-repeat-expr-expr node))))))
    ((peg-opt-expr? node)
     `(? ,(ast->sexpr (peg-opt-expr-expr node))))
    ((peg-pred-expr? node)
     (if (peg-pred-expr-positive? node)
         `(& ,(ast->sexpr (peg-pred-expr-expr node)))
         `(! ,(ast->sexpr (peg-pred-expr-expr node)))))
    ((peg-gather-expr? node)
     (if (peg-gather-expr-one-or-more? node)
         `(gather+ ,(ast->sexpr (peg-gather-expr-sep node))
                   ,(ast->sexpr (peg-gather-expr-elem node)))
         `(gather* ,(ast->sexpr (peg-gather-expr-sep node))
                   ,(ast->sexpr (peg-gather-expr-elem node)))))
    ((peg-rule-ref-expr? node)
     (peg-rule-ref-expr-name node))
    ((peg-named-expr? node)
     `(bind ,(peg-named-expr-name node) ,(ast->sexpr (peg-named-expr-expr node))))
    ((peg-action-expr? node)
     `(=> ,(ast->sexpr (peg-action-expr-expr node))
          ,(peg-action-expr-action-code node)))
    (else
     (error "Unknown PEG AST node in ast->sexpr" node))))

(define (sexpr->ast s)
  (cond
    ((symbol? s)
     (case s
       ((any-char) (make-peg-any-char-expr))
       ((cut) (make-peg-cut-expr))
       ((line-start) (make-peg-line-start-expr))
       (else (make-peg-rule-ref-expr s))))
    ((string? s)
     (make-peg-lit-expr s))
    ((pair? s)
     (case (car s)
       ((grammar)
        (let* ((name (cadr s))
               (body (cddr s))
               (dirs (cond ((assoc 'directives body) => cdr) (else '())))
               (raw-rules (cond ((assoc 'rules body) => cdr) (else '()))))
          (make-peg-grammar-def name (map sexpr->ast raw-rules) dirs)))
       ((rule)
        (let* ((name (cadr s))
               (rest (cddr s))
               (memo? (if (member '(memo) rest) #t #f))
               (type (let ((t (assoc 'type rest))) (if t (cadr t) #f)))
               (expr-s (let loop ((items rest))
                         (cond
                           ((null? items) (error "Missing expression in rule" name))
                           ((and (pair? (car items)) (memq (caar items) '(memo type)))
                            (loop (cdr items)))
                           (else (car items))))))
          (make-peg-rule-def name (sexpr->ast expr-s) memo? type)))
       ((lit) (make-peg-lit-expr (cadr s)))
       ((regex) (make-peg-regex-expr (cadr s)))
       ((char-class) (make-peg-char-class-expr (cadr s) #f))
       ((char-class-inv) (make-peg-char-class-expr (cadr s) #t))
       ((:) (make-peg-seq-expr (map sexpr->ast (cdr s))))
       ((/) (make-peg-choice-expr (map sexpr->ast (cdr s))))
       ((*) (make-peg-repeat-expr (sexpr->ast (cadr s)) 0 #f))
       ((+) (make-peg-repeat-expr (sexpr->ast (cadr s)) 1 #f))
       ((?) (make-peg-opt-expr (sexpr->ast (cadr s))))
       ((&) (make-peg-pred-expr (sexpr->ast (cadr s)) #t))
       ((!) (make-peg-pred-expr (sexpr->ast (cadr s)) #f))
       ((gather+) (make-peg-gather-expr (sexpr->ast (cadr s)) (sexpr->ast (caddr s)) #t))
       ((gather*) (make-peg-gather-expr (sexpr->ast (cadr s)) (sexpr->ast (caddr s)) #f))
       ((bind) (make-peg-named-expr (cadr s) (sexpr->ast (caddr s))))
       ((=>) (make-peg-action-expr (sexpr->ast (cadr s)) (caddr s)))
       (else
        (error "Unknown S-expression tag in sexpr->ast" s))))
    (else
     (error "Invalid S-expression for PEG AST" s))))
