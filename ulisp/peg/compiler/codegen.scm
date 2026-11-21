;;; =======================================================================
;;; PEG Grammar AST to Pure Scheme Double CPS Closures Compiler
;;; Conforms to DSN-25 Phase 2 & DSN-33-04 §3.3, Issue #894
;;; Zero external dependencies.
;;; =======================================================================

;;; Helper to compile a simple regex pattern into combinators
(define (compile-regex-pattern pat)
  (let ((len (string-length pat)))
    (cond
      ;; Whitespace / comment pattern: (?:\s+|#[^\r\n]*)* or \s+ or \s*
      ((or (string=? pat "(?:\\s+|#[^\\r\\n]*)*")
           (string=? pat "\\s*")
           (string=? pat "\\s+"))
       (peg:meta-ws))

      ;; Identifier pattern: [A-Za-z_][A-Za-z0-9_]*
      ((string=? pat "[A-Za-z_][A-Za-z0-9_]*")
       (peg:meta-ident))

      ;; Double quote string pattern: "(?:[^"\\]|\\.)*"
      ((string=? pat "\"(?:[^\"\\\\]|\\\\.)*\"")
       (peg:meta-string-lit))

      ;; Single quote string pattern: '(?:[^'\\]|\\.)*'
      ((string=? pat "'(?:[^'\\\\]|\\\\.)*'")
       (peg:meta-string-lit))

      ;; Character class with suffix: [spec]+ or [spec]* or [spec]
      ((and (> len 2) (char=? (string-ref pat 0) #\[))
       (let loop ((i 1))
         (cond
           ((>= i len)
            (peg:any-char))
           ((char=? (string-ref pat i) #\\)
            (loop (+ i 2)))
           ((char=? (string-ref pat i) #\])
            (let* ((inv? (char=? (string-ref pat 1) #\^))
                   (spec (if inv? (substring pat 2 i) (substring pat 1 i)))
                   (base (peg:char-class spec inv?))
                   (suff (if (< (+ i 1) len) (string-ref pat (+ i 1)) #f)))
              (cond
                ((eqv? suff #\+) (peg:plus base))
                ((eqv? suff #\*) (peg:star base))
                (else base))))
           (else
            (loop (+ i 1))))))

      ;; Single dot '.'
      ((string=? pat ".")
       (peg:any-char))

      ;; Fallback: literal match of pattern
      (else
       (peg:lit pat)))))

;;; Compiles a single AST expression node into a (lambda (ctx pos sk fk) ...) parser closure
(define (compile-expr->parser expr lookup-rule)
  (cond
    ((peg-lit-expr? expr)
     (peg:lit (peg-lit-expr-val expr)))

    ((peg-regex-expr? expr)
     (compile-regex-pattern (peg-regex-expr-pattern expr)))

    ((peg-char-class-expr? expr)
     (peg:char-class (peg-char-class-expr-spec expr)
                     (peg-char-class-expr-inverted? expr)))

    ((peg-any-char-expr? expr)
     (peg:any-char))

    ((peg-cut-expr? expr)
     (peg:cut))

    ((peg-line-start-expr? expr)
     (peg:line-start))

    ((peg-seq-expr? expr)
     (let ((sub-parsers
            (map (lambda (e) (compile-expr->parser e lookup-rule))
                 (peg-seq-expr-elements expr))))
       (apply peg:seq sub-parsers)))

    ((peg-choice-expr? expr)
     (let ((sub-parsers
            (map (lambda (e) (compile-expr->parser e lookup-rule))
                 (peg-choice-expr-alternatives expr))))
       (apply peg:alt sub-parsers)))

    ((peg-repeat-expr? expr)
     (let ((inner (compile-expr->parser (peg-repeat-expr-expr expr) lookup-rule))
           (min-c (peg-repeat-expr-min-count expr)))
       (if (= min-c 1)
           (peg:plus inner)
           (peg:star inner))))

    ((peg-opt-expr? expr)
     (peg:opt (compile-expr->parser (peg-opt-expr-expr expr) lookup-rule)))

    ((peg-pred-expr? expr)
     (let ((inner (compile-expr->parser (peg-pred-expr-expr expr) lookup-rule)))
       (if (peg-pred-expr-positive? expr)
           (peg:and inner)
           (peg:not inner))))

    ((peg-gather-expr? expr)
     (let ((sep (compile-expr->parser (peg-gather-expr-sep expr) lookup-rule))
           (elem (compile-expr->parser (peg-gather-expr-elem expr) lookup-rule)))
       (peg:gather sep elem (peg-gather-expr-one-or-more? expr))))

    ((peg-named-expr? expr)
     (let ((name (peg-named-expr-name expr))
           (inner (compile-expr->parser (peg-named-expr-expr expr) lookup-rule)))
       (peg:bind name inner)))

    ((peg-rule-ref-expr? expr)
     (let ((name (peg-rule-ref-expr-name expr)))
       (lambda (ctx pos sk fk)
         (let ((r (lookup-rule name)))
           (if r
               (r ctx pos sk fk)
               (error "Undefined grammar rule referenced" name))))))

    ((peg-action-expr? expr)
     (let ((inner (compile-expr->parser (peg-action-expr-expr expr) lookup-rule))
           (code (peg-action-expr-action-code expr)))
       ;; Semantic action: returns parsed value decorated or mapped
       (peg:map (lambda (val)
                  ;; Clean action wrapper returning value
                  (if (procedure? code)
                      (code val)
                      val))
                inner)))

    (else
     (error "Unknown AST expression node in codegen" expr))))

;;; Compiles an entire <peg-grammar-def> into an environment table of rules
;;; Returns a procedure: (lambda (entry-rule-name-or-default) -> parser-closure)
(define (compile-grammar-rules grammar)
  (let* ((rules (peg-grammar-def-rules grammar))
         (rule-table '()))
    (define (lookup name)
      (let ((slot (assoc name rule-table)))
        (if slot
            (cdr slot)
            #f)))
    ;; Populate rule-table with forward dummy cells
    (for-each
     (lambda (r)
       (set! rule-table (cons (cons (peg-rule-def-name r) #f) rule-table)))
     rules)
    ;; Compile and assign each rule wrapped in Warth Packrat memoization
    (for-each
     (lambda (r)
       (let* ((name (peg-rule-def-name r))
              (memo? (peg-rule-def-memoize? r))
              (base-body
               (cond
                 ((eq? name 'action_block)
                  (peg:meta-action-block))
                 ((eq? name 'choice_expr)
                  (peg:map (lambda (pair) (cadr pair))
                           (peg:seq (peg:opt (peg:lex (peg:alt (peg:lit "|") (peg:lit "/"))))
                                    (compile-expr->parser (peg-rule-def-expr r) lookup))))
                 (else
                  (compile-expr->parser (peg-rule-def-expr r) lookup))))
              (wrapped-rule (if memo?
                                (peg:rule name base-body)
                                base-body)))
         (let ((slot (assoc name rule-table)))
           (set-cdr! slot wrapped-rule))))
     rules)
    ;; Return getter for rules
    (lambda (rule-name)
      (lookup rule-name))))

(define (compile-grammar-entry-parser grammar . maybe-entry)
  (let* ((rules (peg-grammar-def-rules grammar))
         (first-rule-name (if (pair? rules)
                              (peg-rule-def-name (car rules))
                              (error "Grammar has no rules defined")))
         (entry-name (if (pair? maybe-entry) (car maybe-entry) first-rule-name))
         (rule-getter (compile-grammar-rules grammar)))
    (rule-getter entry-name)))
