;;; =======================================================================
;;; ULisp Compiler Pass 0b: Hygienic syntax-rules Macro Expander
;;; Conforms to DSN-33 Architecture Specification & Issue #533 (R7RS 4.3)
;;;
;;; Provides self-contained compile-time hygienic macro expansion
;;; without relying on host runtime eval. Fully operational in both host
;;; Scheme (ILisp) and self-hosted native AOT binaries (Stage 1/2/3).
;;; =======================================================================

;;; -----------------------------------------------------------------------
;;; 1. Hygiene & Unique Identifier Generation
;;; -----------------------------------------------------------------------

(define *hygiene-counter* (cons 0 '()))

(define (reset-hygiene-counter!)
  (set-car! *hygiene-counter* 0))

(define (hygiene-gensym sym)
  (let ((cnt (car *hygiene-counter*)))
    (set-car! *hygiene-counter* (+ cnt 1))
    (string->symbol (string-append "__hyg_" (symbol->string sym) "_" (number->string cnt)))))

;;; Built-in core keywords and primitives that must NOT be renamed during hygienic expansion
(define (core-form-or-primitive? sym)
  (memq sym '(if begin lambda let let* letrec letrec* quote set! define define-values define-syntax syntax-rules syntax-error define-record-type
              let-syntax letrec-syntax
              cond case and or when unless delay delay-force do case-lambda
              cons car cdr pair? null? list append not eq? eqv? equal?
              list-copy make-list
              vector vector-ref vector-set! vector-length make-vector vector-copy vector-copy! vector-append vector-fill! vector-map vector-for-each vector->list list->vector vector->string vector->string-range
              string string-ref string-set! string-length make-string string-append string-copy string-copy! string-fill! string-map string-for-each substring string=? string<? string>? string<=? string>=? string->symbol symbol->string string->list string->list-range list->string string->vector string->vector-range
              bytevector bytevector-u8-ref bytevector-u8-set! bytevector-length make-bytevector bytevector-copy bytevector-copy! bytevector-append bytevector=?
              + - * = < > <= >= modulo quotient / square remainder gcd gcd-2 lcm lcm-2 expt %math-abs
              zero? fixnum? integer? number? exact? exact-integer? inexact? real? rational? complex?
              boolean? char? symbol? string? list? vector? bytevector?
              write-char %write-char write-string %write-string read-char %read-char peek-char %peek-char eof-object?
              values call-with-values dynamic-wind call/cc call-with-current-continuation
              guard raise %raw-call/cc %with-handler
              %memory-fence %atomic-cas!)))

;;; -----------------------------------------------------------------------
;;; 2. Pattern Matching Utilities
;;; -----------------------------------------------------------------------

(define (ellipsis? x)
  (and (symbol? x) (eq? x '...)))

(define (underscore? x)
  (and (symbol? x) (eq? x '_)))

(define (literal? sym literals)
  (and (symbol? sym) (memq sym literals)))

;;; Extract all pattern variables from a pattern
(define (extract-pattern-vars pat literals)
  (cond
    ((null? pat) '())
    ((underscore? pat) '())
    ((ellipsis? pat) '())
    ((symbol? pat)
     (if (literal? pat literals)
         '()
         (list pat)))
    ((pair? pat)
     (append (extract-pattern-vars (car pat) literals)
             (extract-pattern-vars (cdr pat) literals)))
    (else '())))

;;; Compute length of a proper or dotted list
(define (pattern-length p)
  (let loop ((cur p) (len 0))
    (cond
      ((null? cur) len)
      ((pair? cur) (loop (cdr cur) (+ len 1)))
      (else (+ len 1)))))

;;; Match a single element pattern against input
(define (match-element pat input literals env)
  (cond
    ((underscore? pat)
     (cons #t env))
    ((literal? pat literals)
     (if (and (symbol? input) (eq? pat input))
         (cons #t env)
         (cons #f '())))
    ((symbol? pat)
     (cons #t (cons (cons pat input) env)))
    ((pair? pat)
     (if (pair? input)
         (match-pattern-sequence pat input literals env)
         (cons #f '())))
    (else
     (if (equal? pat input)
         (cons #t env)
         (cons #f '())))))

;;; Match a sequence of pattern elements against input list
(define (match-pattern-sequence pat input literals env)
  (cond
    ((and (null? pat) (null? input))
     (cons #t env))
    ((null? pat)
     (cons #f '()))
    ((not (pair? pat))
     ;; Dotted tail match
     (match-element pat input literals env))
    ;; Ellipsis pattern: (elem ... . rest-pat)
    ((and (pair? (cdr pat)) (ellipsis? (cadr pat)))
     (let* ((elem-pat (car pat))
            (rest-pat (cddr pat))
            (elem-vars (extract-pattern-vars elem-pat literals))
            (min-rest-len (length (if (pair? rest-pat) rest-pat '())))
            (input-len (if (list? input) (length input) 0)))
       (if (< input-len min-rest-len)
           (cons #f '())
           (let* ((num-ellipsis (- input-len min-rest-len))
                  ;; Split input into ellipsis items and rest items
                  (ellipsis-items (let take ((n num-ellipsis) (cur input))
                                    (if (<= n 0) '()
                                        (cons (car cur) (take (- n 1) (cdr cur))))))
                  (rest-items (let drop ((n num-ellipsis) (cur input))
                                (if (<= n 0) cur
                                    (drop (- n 1) (cdr cur))))))
             ;; Match each ellipsis item against elem-pat
             (let loop ((items ellipsis-items) (matched-envs '()))
               (if (null? items)
                   ;; Aggregate matched variables into lists
                   (let* ((agg-bindings
                           (map (lambda (var)
                                  (cons var
                                        (map (lambda (sub-env)
                                               (let ((p (assq var sub-env)))
                                                 (if p (cdr p) #f)))
                                             (reverse matched-envs))))
                                elem-vars))
                          (env-with-ellipsis (append agg-bindings env)))
                     ;; Match rest of pattern
                     (match-pattern-sequence rest-pat rest-items literals env-with-ellipsis))
                   (let ((sub-match (match-element elem-pat (car items) literals '())))
                     (if (car sub-match)
                         (loop (cdr items) (cons (cdr sub-match) matched-envs))
                         (cons #f '())))))))))
    ;; Normal element
    ((pair? input)
     (let ((head-match (match-element (car pat) (car input) literals env)))
       (if (car head-match)
           (match-pattern-sequence (cdr pat) (cdr input) literals (cdr head-match))
           (cons #f '()))))
    (else
     (cons #f '()))))

;;; Match an entire macro pattern against input form
;;; Pattern starts with keyword or underscore: (_ a b ...)
(define (match-macro-pattern pat input literals)
  (if (and (pair? pat) (pair? input))
      (match-pattern-sequence (cdr pat) (cdr input) literals '())
      (cons #f '())))

;;; -----------------------------------------------------------------------
;;; 3. Template Expansion and Hygienic Renaming
;;; -----------------------------------------------------------------------

(define (extract-formals formals pat-vars)
  (cond
    ((null? formals) '())
    ((symbol? formals)
     (if (memq formals pat-vars) '() (list formals)))
    ((pair? formals)
     (append (extract-formals (car formals) pat-vars)
             (extract-formals (cdr formals) pat-vars)))
    (else '())))

(define (extract-binding-vars bindings pat-vars)
  (cond
    ((null? bindings) '())
    ((pair? bindings)
     (let ((b (car bindings)))
       (append (if (and (pair? b) (symbol? (car b)) (not (memq (car b) pat-vars)))
                   (list (car b))
                   '())
               (extract-binding-vars (cdr bindings) pat-vars))))
    (else '())))

;;; Collect all variables introduced by binding forms in a template that need renaming (macro-introduced local identifiers)
(define (collect-template-binders tmpl pat-vars literals)
  (cond
    ((not (pair? tmpl)) '())
    ((eq? (car tmpl) 'quote) '())
    ;; (lambda <formals> <body> ...)
    ((and (eq? (car tmpl) 'lambda) (pair? (cdr tmpl)))
     (let ((formals (cadr tmpl))
           (body (cddr tmpl)))
       (append (extract-formals formals pat-vars)
               (collect-template-binders body pat-vars literals))))
    ;; (let ((<var> <init>) ...) <body> ...)
    ;; or named let: (let <name> ((<var> <init>) ...) <body> ...)
    ((and (memq (car tmpl) '(let let* letrec letrec*)) (pair? (cdr tmpl)))
     (cond
       ;; named let: (let <name> ((<var> <init>) ...) ...)
       ((and (eq? (car tmpl) 'let) (symbol? (cadr tmpl)) (pair? (cddr tmpl)))
        (let ((name (cadr tmpl))
              (bindings (caddr tmpl))
              (body (cdddr tmpl)))
          (append (if (memq name pat-vars) '() (list name))
                  (append (extract-binding-vars bindings pat-vars)
                          (append (collect-template-binders bindings pat-vars literals)
                                  (collect-template-binders body pat-vars literals))))))
       ;; normal let / let* / letrec: (let ((<var> <init>) ...) ...)
       ((pair? (cdr tmpl))
        (let ((bindings (cadr tmpl))
              (body (cddr tmpl)))
          (append (extract-binding-vars bindings pat-vars)
                  (append (collect-template-binders bindings pat-vars literals)
                          (collect-template-binders body pat-vars literals)))))
       (else '())))
    (else
     (append (collect-template-binders (car tmpl) pat-vars literals)
             (collect-template-binders (cdr tmpl) pat-vars literals)))))

(define (remove-duplicates ls)
  (let loop ((cur ls) (res '()))
    (cond
      ((null? cur) (reverse res))
      ((memq (car cur) res) (loop (cdr cur) res))
      (else (loop (cdr cur) (cons (car cur) res))))))

;;; Expand a template with given pattern environment and renaming map
(define (expand-template tmpl env literals rename-map)
  (cond
    ((null? tmpl) '())
    ((symbol? tmpl)
     (let ((p (assq tmpl env)))
       (if p
           (cdr p)
           (let ((r (assq tmpl rename-map)))
             (if r
                 (cdr r)
                 tmpl)))))
    ((pair? tmpl)
     (cond
       ;; Quote remains untransformed except for variables if not pure
       ((eq? (car tmpl) 'quote)
        tmpl)
       ;; Ellipsis repetition in template: (elem ... . rest)
       ((and (pair? (cdr tmpl)) (ellipsis? (cadr tmpl)))
        (let* ((elem-tmpl (car tmpl))
               (rest-tmpl (cddr tmpl))
               ;; Find variables used in elem-tmpl that are lists in env
               (vars-in-elem (remove-duplicates (extract-pattern-vars elem-tmpl literals)))
               (ellipsis-vars (filter (lambda (v)
                                        (let ((p (assq v env)))
                                          (and p (list? (cdr p)))))
                                      vars-in-elem)))
          (if (null? ellipsis-vars)
              ;; Zero repetitions or non-ellipsis variable
              (expand-template rest-tmpl env literals rename-map)
              (let* ((first-v (car ellipsis-vars))
                     (repeat-count (length (cdr (assq first-v env))))
                     (repeated-elements
                      (let loop ((i 0) (acc '()))
                        (if (>= i repeat-count)
                            (reverse acc)
                            (let* ((sub-env
                                    (map (lambda (v)
                                           (cons v (list-ref (cdr (assq v env)) i)))
                                         ellipsis-vars))
                                   (merged-env (append sub-env env))
                                   (expanded-elem (expand-template elem-tmpl merged-env literals rename-map)))
                              (loop (+ i 1) (cons expanded-elem acc)))))))
                (append repeated-elements (expand-template rest-tmpl env literals rename-map))))))
       (else
        (cons (expand-template (car tmpl) env literals rename-map)
              (expand-template (cdr tmpl) env literals rename-map)))))
    (else tmpl)))

;;; -----------------------------------------------------------------------
;;; 4. syntax-rules Macro Transformer
;;; -----------------------------------------------------------------------

;;; Representation: ('syntax-rules-macro name literals rules)
;;; rule: (pattern template)
(define (syntax-rules-macro? obj)
  (and (pair? obj) (eq? (car obj) 'syntax-rules-macro)))

(define (macro-name m) (cadr m))
(define (macro-literals m) (caddr m))
(define (macro-rules m) (cadddr m))

(define (apply-syntax-rules-macro m input)
  (let ((literals (macro-literals m))
        (rules (macro-rules m)))
    (let loop ((rls rules))
      (if (null? rls)
          (error "apply-syntax-rules-macro: no matching syntax-rules pattern for" input)
          (let* ((rule (car rls))
                 (pat (car rule))
                 (tmpl (cadr rule))
                 (match-res (match-macro-pattern pat input literals)))
            (if (car match-res)
                (let* ((env (cdr match-res))
                       (pat-vars (extract-pattern-vars pat literals))
                       (binders-to-rename (remove-duplicates (collect-template-binders tmpl pat-vars literals)))
                       (rename-map (map (lambda (s) (cons s (hygiene-gensym s))) binders-to-rename)))
                  (expand-template tmpl env literals rename-map))
                (loop (cdr rls))))))))

;;; -----------------------------------------------------------------------
;;; 5. Macro Definition Parsing and Top-level Expansion Pass
;;; -----------------------------------------------------------------------

(define (macro-def? form)
  (and (pair? form)
       (eq? (car form) 'define-syntax)))

(define (parse-syntax-rules-def form)
  ;; (define-syntax <name> (syntax-rules (<literal> ...) (<pattern> <template>) ...))
  (if (and (pair? (cdr form))
           (symbol? (cadr form))
           (pair? (cddr form))
           (pair? (caddr form))
           (eq? (car (caddr form)) 'syntax-rules))
      (let* ((name (cadr form))
             (sr-spec (caddr form))
             (literals (cadr sr-spec))
             (rules (cddr sr-spec)))
        (list 'syntax-rules-macro name literals rules))
      (error "parse-syntax-rules-def: invalid define-syntax syntax" form)))

(define (rename-symbol-in-tree tree old-sym new-sym)
  (cond
    ((null? tree) '())
    ((eq? tree old-sym) new-sym)
    ((pair? tree)
     (cons (rename-symbol-in-tree (car tree) old-sym new-sym)
           (rename-symbol-in-tree (cdr tree) old-sym new-sym)))
    ((vector? tree)
     (list->vector (rename-symbol-in-tree (vector->list tree) old-sym new-sym)))
    (else tree)))

(define (apply-rename-map tree rename-map)
  (let loop ((cur rename-map) (res tree))
    (if (null? cur)
        res
        (let* ((entry (car cur))
               (old-sym (car entry))
               (new-sym (cdr entry)))
          (loop (cdr cur) (rename-symbol-in-tree res old-sym new-sym))))))

(define (parse-macro-binding b)
  ;; b is (<name> (syntax-rules (<literal> ...) (<pattern> <template>) ...))
  (if (and (pair? b)
           (symbol? (car b))
           (pair? (cdr b))
           (pair? (cadr b))
           (eq? (car (cadr b)) 'syntax-rules)
           (pair? (cdr (cadr b))))
      (let* ((name (car b))
             (sr-spec (cadr b))
             (literals (cadr sr-spec))
             (rules (cddr sr-spec)))
        (cons name (list 'syntax-rules-macro name literals rules)))
      (error "syntax-error [R7RS §4.3.1]: invalid macro binding syntax" b)))

(define (expand-let-syntax expr macro-table is-rec)
  (if (and (pair? (cdr expr))
           (list? (cadr expr))
           (pair? (cddr expr)))
      (let* ((raw-bindings (cadr expr))
             (body (cddr expr)))
        (if is-rec
            ;; letrec-syntax: transformers and body share the new-macro-table
            (let* ((local-entries (map parse-macro-binding raw-bindings))
                   (new-macro-table (append local-entries macro-table))
                   (expanded-body
                    (if (null? (cdr body))
                        (macro-expand-all (car body) new-macro-table)
                        (cons 'begin
                              (map (lambda (e) (macro-expand-all e new-macro-table)) body)))))
              expanded-body)
            ;; let-syntax: transformers are in outer scope, body is in new scope
            (let loop ((bs raw-bindings)
                       (local-entries '())
                       (extra-outer '())
                       (restore-map '()))
              (if (null? bs)
                  (let* ((new-macro-table (append local-entries (append extra-outer macro-table)))
                         (expanded-body
                          (if (null? (cdr body))
                              (macro-expand-all (car body) new-macro-table)
                              (cons 'begin
                                    (map (lambda (e) (macro-expand-all e new-macro-table)) body)))))
                    (apply-rename-map expanded-body restore-map))
                  (let* ((b (car bs))
                         (parsed (parse-macro-binding b))
                         (name (car parsed))
                         (macro-desc (cdr parsed))
                         (literals (macro-literals macro-desc))
                         (rules (macro-rules macro-desc))
                         (outer-entry (assq name macro-table)))
                    (if outer-entry
                        ;; Outer macro exists: rename name in template to alias pointing to outer macro
                        (let* ((alias (hygiene-gensym name))
                               (renamed-rules
                                (map (lambda (r)
                                       (list (car r)
                                             (rename-symbol-in-tree (cadr r) name alias)))
                                     rules))
                               (new-desc (list 'syntax-rules-macro name literals renamed-rules)))
                          (loop (cdr bs)
                                (cons (cons name new-desc) local-entries)
                                (cons (cons alias (cdr outer-entry)) extra-outer)
                                restore-map))
                        ;; No outer macro: rename name in template to restore-alias so it is not re-expanded locally
                        (let* ((restore-alias (hygiene-gensym name))
                               (renamed-rules
                                (map (lambda (r)
                                       (list (car r)
                                             (rename-symbol-in-tree (cadr r) name restore-alias)))
                                     rules))
                               (new-desc (list 'syntax-rules-macro name literals renamed-rules)))
                          (loop (cdr bs)
                                (cons (cons name new-desc) local-entries)
                                extra-outer
                                (cons (cons restore-alias name) restore-map)))))))))
      (error "syntax-error [R7RS §4.3.1]: invalid let-syntax/letrec-syntax syntax" expr)))

(define (macro-expand-1 expr macro-table)
  (if (and (pair? expr) (symbol? (car expr)))
      (let ((entry (assq (car expr) macro-table)))
        (if entry
            (let* ((macro-desc (cdr entry))
                   (expanded (apply-syntax-rules-macro macro-desc expr)))
              (cons #t expanded))
            (cons #f expr)))
      (cons #f expr)))

(define (macro-expand-top-expr expr macro-table)
  (let ((res (macro-expand-1 expr macro-table)))
    (if (car res)
        (macro-expand-top-expr (cdr res) macro-table)
        (cdr res))))

(define (safe-macro-expand-list ls macro-table)
  (let loop ((cur ls) (acc (quote ())))
    (cond
      ((null? cur) (reverse acc))
      ((not (pair? cur)) (append (reverse acc) (macro-expand-all cur macro-table)))
      (else
       (loop (cdr cur) (cons (macro-expand-all (car cur) macro-table) acc))))))

;;; Expand case clauses: datum lists (and `else`) are preserved verbatim,
;;; only clause bodies are macro-expanded.
(define (safe-macro-expand-case-clauses clauses macro-table)
  (let loop ((cur clauses) (acc (quote ())))
    (cond
      ((null? cur) (reverse acc))
      ((not (pair? cur)) (append (reverse acc) cur))
      ((pair? (car cur))
       (let ((clause (car cur)))
         (loop (cdr cur)
               (cons (cons (car clause)
                           (safe-macro-expand-list (cdr clause) macro-table))
                     acc))))
      (else
       (loop (cdr cur) (cons (car cur) acc))))))

(define (safe-macro-expand-bindings bs macro-table)
  (let loop ((cur bs) (acc (quote ())))
    (cond
      ((null? cur) (reverse acc))
      ((not (pair? cur)) (append (reverse acc) cur))
      ((pair? (car cur))
       (let* ((b (car cur))
              (var (car b))
              (val-exprs (safe-macro-expand-list (cdr b) macro-table)))
         (loop (cdr cur) (cons (cons var val-exprs) acc))))
      (else
       (loop (cdr cur) (cons (car cur) acc))))))

(define (macro-expand-all expr macro-table)
  (let ((expanded (macro-expand-top-expr expr macro-table)))
    (cond
      ((not (pair? expanded))
       expanded)
      ((eq? (car expanded) (quote quote))
       expanded)
      ((eq? (car expanded) (quote syntax-error))
       (let ((msg (if (and (pair? (cdr expanded)) (string? (cadr expanded)))
                      (cadr expanded)
                      "invalid syntax"))
             (irritants (if (and (pair? (cdr expanded)) (string? (cadr expanded)))
                            (cddr expanded)
                            (cdr expanded))))
         (error (string-append "syntax-error: " msg) irritants)))
      ((eq? (car expanded) (quote case))
       (if (and (pair? (cdr expanded)) (pair? (cddr expanded)))
           (cons (quote case)
                 (cons (macro-expand-all (cadr expanded) macro-table)
                       (safe-macro-expand-case-clauses (cddr expanded) macro-table)))
           expanded))
      ((eq? (car expanded) (quote case-lambda))
       (cons (quote case-lambda)
             (map (lambda (clause)
                    (if (pair? clause)
                        (cons (car clause)
                              (safe-macro-expand-list (cdr clause) macro-table))
                        clause))
                  (cdr expanded))))
      ((eq? (car expanded) (quote lambda))
       (if (and (pair? (cdr expanded)) (pair? (cddr expanded)))
           (cons (quote lambda)
                 (cons (cadr expanded)
                       (safe-macro-expand-list (cddr expanded) macro-table)))
           expanded))
      ((eq? (car expanded) (quote define))
       (if (and (pair? (cdr expanded)) (pair? (cddr expanded)))
           (cons (quote define)
                 (cons (cadr expanded)
                       (safe-macro-expand-list (cddr expanded) macro-table)))
           expanded))
      ((eq? (car expanded) (quote define-record-type))
       expanded)
      ((eq? (car expanded) (quote let-syntax))
       (expand-let-syntax expanded macro-table #f))
      ((eq? (car expanded) (quote letrec-syntax))
       (expand-let-syntax expanded macro-table #t))
      ((or (eq? (car expanded) (quote let))
           (eq? (car expanded) (quote let*))
           (eq? (car expanded) (quote letrec))
           (eq? (car expanded) (quote letrec*)))
       (if (and (pair? (cdr expanded)) (symbol? (cadr expanded)))
           (if (and (pair? (cddr expanded)) (pair? (cdddr expanded)))
               (cons (car expanded)
                     (cons (cadr expanded)
                           (cons (safe-macro-expand-bindings (caddr expanded) macro-table)
                                 (safe-macro-expand-list (cdddr expanded) macro-table))))
               expanded)
           (if (and (pair? (cdr expanded)) (pair? (cddr expanded)))
               (cons (car expanded)
                     (cons (safe-macro-expand-bindings (cadr expanded) macro-table)
                           (safe-macro-expand-list (cddr expanded) macro-table)))
               expanded)))
      (else
       (safe-macro-expand-list expanded macro-table)))))


(define (expand-macros-in-forms forms)
  (let loop ((fs forms) (macro-table '()) (res '()))
    (if (null? fs)
        (reverse res)
        (let ((f (car fs)))
          (cond
            ((source-loc? f)
             (let* ((file (source-loc-file f))
                    (line (source-loc-line f))
                    (col (source-loc-col f))
                    (inner (source-loc-form f)))
               (if (macro-def? inner)
                   (let* ((macro-desc (parse-syntax-rules-def inner))
                          (name (macro-name macro-desc)))
                     (loop (cdr fs) (cons (cons name macro-desc) macro-table) res))
                   (let ((exp-f (macro-expand-all inner macro-table)))
                     (loop (cdr fs) macro-table (cons (list '%source-loc file line col exp-f) res))))))
            ((macro-def? f)
             (let* ((macro-desc (parse-syntax-rules-def f))
                    (name (macro-name macro-desc)))
               (loop (cdr fs) (cons (cons name macro-desc) macro-table) res)))
            (else
             (let ((exp-f (macro-expand-all f macro-table)))
               (loop (cdr fs) macro-table (cons exp-f res)))))))))

