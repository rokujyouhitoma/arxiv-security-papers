;;; =======================================================================
;;; ULisp Compiler: Nanopass Framework Core DSL (define-language / define-pass)
;;; Conforms to DSN-33 Architecture Specification & Keep & Dybvig (2013)
;;; =======================================================================

;;; Helper to parse header of define-pass
;;; (define-pass pass-name : L_in (ir extra_in ...) -> L_out (extra_out ...) body ...)
;;; or (define-pass pass-name : L_in (ir extra_in ...) -> * (extra_out ...) body ...)
;;; or (define-pass pass-name (ir extra_in ...) body ...)
(define (nanopass-parse-pass-header form)
  (let ((name (cadr form))
        (rest (cddr form)))
    (if (and (pair? rest) (eq? (car rest) ':))
        (let* ((l-in (cadr rest))
               (in-args (caddr rest))
               (in-arg-list (if (pair? in-args) in-args (list in-args)))
               (after-arrow (cddddr rest))
               (l-out (car after-arrow))
               (has-extra-out? (and (pair? (cdr after-arrow)) (list? (cadr after-arrow))))
               (extra-out (if has-extra-out? (cadr after-arrow) '()))
               (clauses (if has-extra-out? (cddr after-arrow) (cdr after-arrow))))
          (list name l-in in-arg-list l-out extra-out clauses))
        (let* ((in-args (car rest))
               (in-arg-list (if (pair? in-args) in-args (list in-args)))
               (clauses (cdr rest)))
          (list name 'L_src in-arg-list 'L_core '() clauses)))))

;;; Expand a single rule in a nonterminal transformer
(define (nanopass-expand-rule rule nt-name)
  (let* ((pat (car rule))
         (rest (cdr rule))
         (has-guard? (and (pair? rest)
                          (pair? (car rest))
                          (eq? (car (car rest)) 'guard)))
         (guard-expr (if has-guard? (cadr (car rest)) #t))
         (raw-body (if has-guard?
                       (if (null? (cddr rest)) (cadr rest) (cons 'begin (cdr rest)))
                       (if (null? (cdr rest)) (car rest) (cons 'begin rest))))
         (vars (nanopass-extract-pattern-vars pat))
         (body-expr (nanopass-expand-template raw-body vars)))
    (list pat vars guard-expr body-expr)))

;;; Bind matched pattern variables from list `m-var` without allocating a closure
(define (nanopass-var-ref-expr m-var idx)
  (cond
    ((= idx 0) (list 'car m-var))
    ((= idx 1) (list 'cadr m-var))
    ((= idx 2) (list 'caddr m-var))
    ((= idx 3) (list 'cadddr m-var))
    (else (list 'list-ref m-var idx))))

(define (nanopass-bind-matched-vars vars m-var body-expr)
  (if (null? vars)
      body-expr
      (list 'let
            (let loop ((vs vars) (i 0) (acc '()))
              (if (null? vs)
                  (reverse acc)
                  (loop (cdr vs) (+ i 1)
                        (cons (list (car vs) (nanopass-var-ref-expr m-var i)) acc))))
            body-expr)))

;;; Build cascaded if-expression for nonterminal transformer rules
(define (nanopass-rule-head-symbol pat)
  (cond
    ((not (pair? pat)) #f)
    ((eq? (car pat) 'unquote) #f)
    ((eq? (car pat) '_) #f)
    ((eq? (car pat) '...) #f)
    ((symbol? (car pat)) (car pat))
    (else #f)))

;;; Check if pattern can potentially match a pair
(define (nanopass-rule-can-match-pair? pat)
  (or (pair? pat) (eq? pat '_)))

;;; Check if pattern can potentially match an atom
(define (nanopass-rule-can-match-atom? pat)
  (or (not (pair? pat)) (eq? (car pat) 'unquote)))

;;; Append a rule into the appropriate tag bucket preserving tag & rule order
(define (nanopass-add-rule-to-bucket tag rule buckets)
  (let loop ((rem buckets) (acc '()))
    (cond
      ((null? rem)
       (append buckets (list (list tag rule))))
      ((eq? (caar rem) tag)
       (append (reverse acc)
               (cons (append (car rem) (list rule))
                     (cdr rem))))
      (else
       (loop (cdr rem) (cons (car rem) acc))))))

;;; Partition a list of expanded rules into:
;;; (list buckets pair-fallbacks atom-rules)
;;; where buckets is ((tag r1 r2 ...) ...)
(define (nanopass-partition-rules rules)
  (let loop ((rem rules)
             (buckets '())
             (pair-fallbacks '())
             (atom-rules '()))
    (if (null? rem)
        (list buckets (reverse pair-fallbacks) (reverse atom-rules))
        (let* ((r (car rem))
               (pat (car r))
               (tag (nanopass-rule-head-symbol pat)))
          (if tag
              (loop (cdr rem)
                    (nanopass-add-rule-to-bucket tag r buckets)
                    pair-fallbacks
                    atom-rules)
              (loop (cdr rem)
                    buckets
                    (if (nanopass-rule-can-match-pair? pat)
                        (cons r pair-fallbacks)
                        pair-fallbacks)
                    (if (nanopass-rule-can-match-atom? pat)
                        (cons r atom-rules)
                        atom-rules)))))))

;;; Compile a single expanded rule into an if-check with fallback
(define (nanopass-compile-single-rule-cascade r ir-var nt-name fallback-expr)
  (let* ((pat (car r))
         (vars (cadr r))
         (guard-expr (caddr r))
         (body-expr (cadddr r))
         (m-var (unique-symbol "__m_")))
    (if (eq? guard-expr #t)
        (list 'let (list (list m-var
                               (list (string->symbol "nanopass-match-clause")
                                     (list 'quote pat)
                                     ir-var
                                     (list 'quote vars)
                                     nt-name)))
              (list 'if m-var
                    (nanopass-bind-matched-vars vars m-var body-expr)
                    fallback-expr))
        (let ((c-var (unique-symbol "__c_")))
          (list 'let (list (list c-var
                                 (list 'let (list (list m-var
                                                        (list (string->symbol "nanopass-match-clause")
                                                              (list 'quote pat)
                                                              ir-var
                                                              (list 'quote vars)
                                                              nt-name)))
                                        (list 'if m-var
                                              (nanopass-bind-matched-vars
                                               vars m-var
                                               (list 'if guard-expr
                                                     (list 'cons #t body-expr)
                                                     #f))
                                              #f))))
                (list 'if c-var
                      (list 'cdr c-var)
                      fallback-expr))))))

;;; Compile a list of expanded rules sequentially with fallback-expr at the tail
(define (nanopass-compile-rule-list rs ir-var nt-name fallback-expr)
  (let loop ((rem rs))
    (if (null? rem)
        fallback-expr
        (nanopass-compile-single-rule-cascade (car rem) ir-var nt-name (loop (cdr rem))))))

;;; Make catamorphism recursive call
(define (nanopass-make-catamorphism-call l-in l-out nt-name ir-var in-arg-list extra-out)
  (let ((extra-in (cdr in-arg-list)))
    (if (null? extra-in)
        (list (string->symbol "nanopass-catamorphism-step")
              (list 'quote l-in)
              (list 'quote l-out)
              (list 'quote nt-name)
              ir-var
              nt-name
              ''()
              (list 'quote extra-out))
        (list (string->symbol "nanopass-catamorphism-step")
              (list 'quote l-in)
              (list 'quote l-out)
              (list 'quote nt-name)
              ir-var
              nt-name
              (cons 'list extra-in)
              (list 'quote extra-out)))))

;;; Extract expanded clauses from a list of rule names or descriptors
(define (nanopass-extract-fused-clauses specs nt-name)
  (let ((flat-specs (if (and (= (length specs) 1) (list? (car specs)))
                        (car specs)
                        specs)))
    (let loop ((rem flat-specs) (acc '()))
      (if (null? rem)
          (reverse acc)
          (let* ((spec (car rem))
                 (desc (nanopass-lookup-rule spec))
                 (clauses (rule-clauses desc)))
            (loop (cdr rem) (append (reverse clauses) acc)))))))

;;; Flatten NT rules: inline (fuse-rules ...) and (fuse-tree-rules ...),
;;; and expand regular rules
(define (nanopass-flatten-nt-rules raw-rules nt-name)
  (let loop ((rem raw-rules) (acc '()))
    (cond
      ((null? rem)
       (reverse acc))
      ((and (pair? (car rem)) (memq (caar rem) '(fuse-rules fuse-tree-rules)))
       (let* ((specs (cdar rem))
              (fused-clauses (nanopass-extract-fused-clauses specs nt-name)))
         (loop (cdr rem) (append (reverse fused-clauses) acc))))
      (else
       (let ((expanded (nanopass-expand-rule (car rem) nt-name)))
         (loop (cdr rem) (cons expanded acc)))))))

;;; Group rule descriptors by target NT name for top-level fuse-rules
(define (nanopass-group-rules-by-nt specs default-nt)
  (let loop ((rem specs) (groups '()))
    (if (null? rem)
        (reverse (map (lambda (g) (cons (car g) (reverse (cdr g)))) groups))
        (let* ((spec (car rem))
               (desc (nanopass-lookup-rule spec))
               (nt (if (rule-nt-name desc) (rule-nt-name desc) default-nt))
               (cls (rule-clauses desc)))
          (let add-to-groups ((gs groups) (acc '()))
            (cond
              ((null? gs)
               (loop (cdr rem) (cons (cons nt (reverse cls)) groups)))
              ((eq? (caar gs) nt)
               (loop (cdr rem)
                     (append (reverse acc)
                             (cons (cons nt (append (reverse cls) (cdar gs)))
                                   (cdr gs)))))
              (else
               (add-to-groups (cdr gs) (cons (car gs) acc)))))))))

;;; Build cascaded dispatch expression for nonterminal transformer rules
;;; Incorporates O(1) Head-Tag bucketing (case dispatch), pair fallback, and atom fast-path.
(define (nanopass-build-rules-cascade rules l-in l-out nt-name in-arg-list extra-out)
  (let* ((ir-var (car in-arg-list))
         (cata-call (nanopass-make-catamorphism-call l-in l-out nt-name ir-var in-arg-list extra-out))
         (partitioned (nanopass-partition-rules rules))
         (buckets (car partitioned))
         (pair-fallbacks (cadr partitioned))
         (atom-rules (caddr partitioned))
         (pair-fallback-expr (nanopass-compile-rule-list pair-fallbacks ir-var nt-name cata-call))
         (atom-fallback-expr (nanopass-compile-rule-list atom-rules ir-var nt-name cata-call)))
    (if (null? buckets)
        (if (and (null? pair-fallbacks) (null? atom-rules))
            cata-call
            (if (equal? pair-fallbacks atom-rules)
                pair-fallback-expr
                (list 'if (list 'pair? ir-var)
                      pair-fallback-expr
                      atom-fallback-expr)))
        (let ((case-expr
               (cons 'case
                     (cons (list 'car ir-var)
                           (append (map (lambda (b)
                                          (list (list (car b))
                                                (nanopass-compile-rule-list (cdr b) ir-var nt-name pair-fallback-expr)))
                                        buckets)
                                   (list (list 'else pair-fallback-expr)))))))
          (list 'if (list 'pair? ir-var)
                (list 'if (list 'symbol? (list 'car ir-var))
                      case-expr
                      pair-fallback-expr)
                atom-fallback-expr)))))

;;; Normalize rules whether passed as list of rules or single wrapped list
(define (nanopass-normalize-rules raw-rules)
  (if (and (= (length raw-rules) 1)
           (pair? (car raw-rules))
           (> (length (car raw-rules)) 1)
           (pair? (caar raw-rules))
           (pair? (cadar raw-rules))
           (pair? (cddar raw-rules))
           (not (eq? (caar raw-rules) 'unquote))
           (not (and (pair? (cadar raw-rules)) (eq? (caadar raw-rules) 'guard))))
      (car raw-rules)
      raw-rules))

;;; Parse a nonterminal clause in define-pass
(define (nanopass-parse-nt-clause clause)
  (let ((nt-name (car clause))
        (rest (cdr clause)))
    (if (and (pair? rest) (eq? (car rest) ':))
        ;; (NT : NT_in (ir extra1 ...) -> NT_out (extra_out ...) rules ...)
        ;; or (NT : NT_in (ir extra1 ...) -> * (extra_out ...) rules ...)
        (let* ((nt-in (cadr rest))
               (in-args (caddr rest))
               (in-arg-list (if (pair? in-args) in-args (list in-args)))
               (after-arrow (cddddr rest))
               (nt-out (car after-arrow))
               (has-extra-out? (and (pair? (cdr after-arrow)) (list? (cadr after-arrow))))
               (extra-out (if has-extra-out? (cadr after-arrow) '()))
               (raw-rules (if has-extra-out? (cddr after-arrow) (cdr after-arrow)))
               (rules (nanopass-normalize-rules raw-rules)))
          (list nt-name in-arg-list nt-out extra-out rules))
        ;; Shorthand: (NT (ir extra1 ...) rules ...)
        (let* ((in-args (car rest))
               (in-arg-list (if (pair? in-args) in-args (list in-args)))
               (rules (nanopass-normalize-rules (cdr rest))))
          (list nt-name in-arg-list nt-name '() rules)))))

;;; Expand define-pass AST
(define (nanopass-expand-define-pass-with-trace form force-trace?)
  (let* ((parsed (nanopass-parse-pass-header form))
         (name (car parsed))
         (l-in (cadr parsed))
         (in-arg-list (caddr parsed))
         (l-out (cadddr parsed))
         (extra-out (car (cddddr parsed)))
         (clauses (cadr (cddddr parsed))))
    (let loop ((rest clauses)
               (defs '())
               (nt-procs '())
               (entry-nt #f))
      (if (null? rest)
          (let* ((final-entry (if entry-nt entry-nt 'Expr))
                 (ir-var (car in-arg-list))
                 (res-var (unique-symbol "__res_"))
                 (body-call (cons final-entry in-arg-list)))
            (list 'define (cons name in-arg-list)
                  (list 'letrec
                        (append (reverse defs) (reverse nt-procs))
                        (list 'begin
                              (list (string->symbol "set-current-pass!") (list 'quote name))
                              (list 'if (list (string->symbol "nanopass-verifier-enabled?"))
                                    (list (string->symbol "nanopass-verify-ast") (list 'quote name) (list 'quote l-in) ir-var ''entry)
                                    #f)
                              (list (string->symbol "with-call-frame") (list 'quote name) ir-var
                                    (list 'lambda '()
                                          (list 'let (list (list res-var body-call))
                                                (list 'if (list (string->symbol "nanopass-verifier-enabled?"))
                                                      (list (string->symbol "nanopass-verify-ast") (list 'quote name) (list 'quote l-out) res-var ''exit)
                                                      #f)
                                                (if force-trace?
                                                    (list 'begin
                                                          (list 'if (list 'not (list (string->symbol "nanopass-in-pipeline-runner?")))
                                                                (list (string->symbol "nanopass-display-ast-diff") (list 'quote name) ir-var res-var)
                                                                #f)
                                                          res-var)
                                                    (list 'begin
                                                          (list 'if (list 'and (list (string->symbol "nanopass-trace-enabled?"))
                                                                               (list 'not (list (string->symbol "nanopass-in-pipeline-runner?"))))
                                                                (list (string->symbol "nanopass-display-ast-diff") (list 'quote name) ir-var res-var)
                                                                #f)
                                                          res-var)))))))))
          (let ((c (car rest)))
            (cond
              ;; (definitions def1 def2 ...)
              ((and (pair? c) (eq? (car c) 'definitions))
               (let ((norm-defs
                      (map (lambda (d)
                             (if (and (pair? d) (eq? (car d) 'define))
                                 (let ((spec (cadr d)))
                                   (if (pair? spec)
                                       (list (car spec) (cons 'lambda (cons (cdr spec) (cddr d))))
                                       (list spec (caddr d))))
                                 d))
                           (cdr c))))
                 (loop (cdr rest) (append (reverse norm-defs) defs) nt-procs entry-nt)))
              ;; (entry EntryNT)
              ((and (pair? c) (eq? (car c) 'entry))
               (loop (cdr rest) defs nt-procs (cadr c)))
              ;; (fuse-rules r1 r2 ...) or (fuse-tree-rules r1 r2 ...) at top-level
              ((and (pair? c) (memq (car c) '(fuse-rules fuse-tree-rules)))
               (let* ((specs (cdr c))
                      (flat-specs (if (and (= (length specs) 1) (list? (car specs))) (car specs) specs))
                      (groups (nanopass-group-rules-by-nt flat-specs (if entry-nt entry-nt 'Expr))))
                 (let group-loop ((gs groups) (cur-procs nt-procs) (cur-entry entry-nt))
                   (if (null? gs)
                       (loop (cdr rest) defs cur-procs cur-entry)
                       (let* ((g (car gs))
                              (g-nt (car g))
                              (g-clauses (cdr g))
                              (body-expr (nanopass-build-rules-cascade g-clauses l-in l-out g-nt in-arg-list extra-out))
                              (proc-binding (list g-nt (list 'lambda in-arg-list body-expr))))
                         (group-loop (cdr gs)
                                     (cons proc-binding cur-procs)
                                     (if cur-entry cur-entry g-nt)))))))
              ;; (NT : NT_in (ir extra ...) -> NT_out (extra_out ...) rules ...)
              ;; or (NT (ir extra ...) rules ...)
              ((and (pair? c) (symbol? (car c)))
               (let* ((parsed-nt (nanopass-parse-nt-clause c))
                      (nt-name (car parsed-nt))
                      (nt-in-args (cadr parsed-nt))
                      (nt-out (caddr parsed-nt))
                      (nt-extra-out (cadddr parsed-nt))
                      (raw-rules (car (cddddr parsed-nt)))
                      (expanded-rules (nanopass-flatten-nt-rules raw-rules nt-name))
                      (body-expr (nanopass-build-rules-cascade expanded-rules l-in nt-out nt-name nt-in-args (if (pair? nt-extra-out) nt-extra-out extra-out)))
                      (proc-binding (list nt-name (list 'lambda nt-in-args body-expr))))
                 (loop (cdr rest)
                       defs
                       (cons proc-binding nt-procs)
                       (if entry-nt entry-nt nt-name))))
              (else
               (loop (cdr rest) defs nt-procs entry-nt))))))))

(define (nanopass-expand-define-pass form)
  (nanopass-expand-define-pass-with-trace form #f))

(define (nanopass-expand-trace-define-pass form)
  (let ((pass-form (cons 'define-pass (cdr form))))
    (nanopass-expand-define-pass-with-trace pass-form #t)))

;;; Expand define-language AST
(define (nanopass-expand-define-language form)
  (let* ((name (cadr form))
         (clauses (cddr form)))
    (list 'begin
          (list 'define (string->symbol (string-append "__lang_" (symbol->raw-name name)))
                (list (string->symbol "nanopass-register-language!")
                      (list (string->symbol "nanopass-parse-language-spec")
                            (list 'quote name)
                            (list 'quote clauses))))
          (list 'define (string->symbol (string-append "parse-" (symbol->raw-name name)))
                (list 'lambda (list 'expr)
                      (list (string->symbol "nanopass-parse") (list 'quote name) 'expr)))
          (list 'define (string->symbol (string-append "unparse-" (symbol->raw-name name)))
                (list 'lambda (list 'ir)
                      (list (string->symbol "nanopass-unparse") (list 'quote name) 'ir)))
          (list 'define (string->symbol (string-append (symbol->raw-name name) "?"))
                (list 'lambda (list 'expr)
                      (list (string->symbol "nanopass-ast-valid?") (list 'quote name) 'expr))))))

;;; Expand define-parser AST
(define (nanopass-expand-define-parser form)
  (let ((proc-name (cadr form))
        (lang-name (caddr form)))
    (list 'define (list proc-name 'expr)
          (list (string->symbol "nanopass-parse") (list 'quote lang-name) 'expr))))

;;; Expand define-unparser AST
(define (nanopass-expand-define-unparser form)
  (let ((proc-name (cadr form))
        (lang-name (caddr form)))
    (list 'define (list proc-name 'ir)
          (list (string->symbol "nanopass-unparse") (list 'quote lang-name) 'ir))))

;;; =======================================================================
;;; Picopass / Femtopass / Attopass DSL Expanders (DSN-33-01 T2.1)
;;; =======================================================================

(define (nanopass-keyword-symbol? s)
  (if (not (symbol? s))
      #f
      (let ((str (symbol->raw-name s)))
        (and (> (string-length str) 1)
             (char=? (string-ref str 0) #\:)))))

(define (nanopass-parse-rule-spec form default-kind)
  (let ((name (cadr form))
        (rest (cddr form)))
    (let loop ((rem rest)
               (opts '())
               (nt-name 'Expr)
               (in-attrs '())
               (out-attrs '())
               (clauses '()))
      (cond
        ((null? rem)
         (list name default-kind nt-name in-attrs out-attrs clauses opts))
        ;; Keyword options: :reads, :writes, :eliminates, :head-tags, :nt
        ((and (nanopass-keyword-symbol? (car rem)) (pair? (cdr rem)))
         (loop (cddr rem) (cons (cons (car rem) (cadr rem)) opts) nt-name in-attrs out-attrs clauses))
        ((and (pair? (car rem)) (nanopass-keyword-symbol? (caar rem)))
         (loop (cdr rem) (cons (car rem) opts) nt-name in-attrs out-attrs clauses))
        ;; NT clause: (Expr ...) or (Expr : (in) -> (out) ...)
        ((pair? (car rem))
         (let ((spec (car rem)))
           (cond
             ((and (pair? spec) (symbol? (car spec)) (pair? (cdr spec)) (eq? (cadr spec) ':))
              ;; (NT : (in-attrs ...) -> (out-attrs ...) clauses ...)
              (let* ((parsed-nt (car spec))
                     (after-colon (cddr spec))
                     (ins (if (pair? after-colon) (car after-colon) '()))
                     (after-arrow (if (and (pair? after-colon) (pair? (cdr after-colon)))
                                      (cddr after-colon)
                                      '()))
                     (outs (if (and (pair? after-arrow) (eq? (car after-arrow) '->) (pair? (cdr after-arrow)))
                               (cadr after-arrow)
                               '()))
                     (cs (if (and (pair? after-arrow) (eq? (car after-arrow) '->) (pair? (cdr after-arrow)))
                             (cddr after-arrow)
                             (if (pair? after-arrow) (cdr after-arrow) '()))))
                (loop (cdr rem) opts parsed-nt ins outs cs)))
             ((and (pair? spec) (symbol? (car spec)))
              ;; (NT clauses ...)
              (loop (cdr rem) opts (car spec) in-attrs out-attrs (cdr spec)))
             (else
              ;; List of clauses directly
              (loop (cdr rem) opts nt-name in-attrs out-attrs spec)))))
        ((symbol? (car rem))
         ;; (define-picopass name NT clauses ...)
         (loop (cddr rem) opts (car rem) in-attrs out-attrs (cadr rem)))
        (else
         (loop (cdr rem) opts nt-name in-attrs out-attrs clauses))))))

(define (nanopass-build-rule-cascade rules kind nt-name ir-var)
  (let loop ((rs rules))
    (if (null? rs)
        (cond
          ((eq? kind 'pico) #f)
          ((eq? kind 'femto) #f)
          ((eq? kind 'atto) #t)
          (else #f))
        (let* ((r (car rs))
               (pat (car r))
               (vars (cadr r))
               (guard-expr (caddr r))
               (body-expr (cadddr r))
               (m-var (unique-symbol "__m_")))
          (list 'let (list (list m-var
                                 (list (string->symbol "nanopass-match-clause")
                                       (list 'quote pat)
                                       ir-var
                                       (list 'quote vars)
                                       (list 'quote nt-name))))
                (list 'if m-var
                      (if (eq? guard-expr #t)
                          (nanopass-bind-matched-vars vars m-var body-expr)
                          (nanopass-bind-matched-vars vars m-var
                                                      (list 'if guard-expr
                                                            body-expr
                                                            (loop (cdr rs)))))
                      (loop (cdr rs))))))))

(define (nanopass-expand-rule-dsl form default-kind)
  (let* ((parsed (nanopass-parse-rule-spec form default-kind))
         (name (car parsed))
         (rule-kind (cadr parsed))
         (nt-name (caddr parsed))
         (in-attrs (cadddr parsed))
         (raw-clauses (car (cddddr (cdr parsed))))
         (opts (cadr (cddddr (cdr parsed))))
         (expanded-rules (map (lambda (r) (nanopass-expand-rule r nt-name)) raw-clauses))
         (opt-head-tags (let ((e (assq ':head-tags opts))) (if e (cdr e) #f)))
         (opt-reads (let ((e (assq ':reads opts))) (if e (cdr e) #f)))
         (opt-writes (let ((e (assq ':writes opts))) (if e (cdr e) #f)))
         (opt-eliminates (let ((e (assq ':eliminates opts))) (if e (cdr e) #f)))
         (head-tags (if opt-head-tags opt-head-tags (nanopass-extract-head-tags expanded-rules)))
         (reads (if opt-reads opt-reads (nanopass-extract-pattern-reads expanded-rules)))
         (writes (if opt-writes opt-writes (nanopass-extract-template-writes expanded-rules)))
         (eliminates (if opt-eliminates opt-eliminates (nanopass-infer-eliminates head-tags writes)))
         (desc-var (unique-symbol (string-append "__desc_" (symbol->raw-name name))))
         (cascade (nanopass-build-rule-cascade expanded-rules rule-kind nt-name 'ir))
         (proc-body
          (if (eq? rule-kind 'femto)
              (let* ((recurse-params (cons 'sub-node in-attrs))
                     (recurse-binding
                      (list 'femto-recurse
                            (list 'lambda recurse-params
                                  (cons name recurse-params)))))
                (list 'letrec (list recurse-binding)
                      cascade))
              cascade)))
    ;; Register rule descriptor at compile-time for downstream pass fusion (e.g. fuse-rules)
    (nanopass-register-rule!
      (nanopass-make-rule-descriptor name rule-kind nt-name head-tags reads writes eliminates expanded-rules #f))
    (list 'begin
          (list 'define desc-var
                (list (string->symbol "nanopass-make-rule-descriptor")
                      (list 'quote name)
                      (list 'quote rule-kind)
                      (list 'quote nt-name)
                      (list 'quote head-tags)
                      (list 'quote reads)
                      (list 'quote writes)
                      (list 'quote eliminates)
                      (list 'quote expanded-rules)
                      #f))
          (list 'define (cons name (if (null? in-attrs) '(ir) (cons 'ir in-attrs)))
                proc-body)
          (list (string->symbol "nanopass-rule-set-proc!") desc-var name)
          (list (string->symbol "nanopass-register-rule!") desc-var)
          (list 'quote name))))

(define (nanopass-expand-define-picopass form)
  (nanopass-expand-rule-dsl form 'pico))

(define (nanopass-expand-define-femtopass form)
  (nanopass-expand-rule-dsl form 'femto))

(define (nanopass-expand-define-attopass form)
  (nanopass-expand-rule-dsl form 'atto))

;;; -----------------------------------------------------------------------
;;; Host / Interpreter Macros (for ilisp and interactive environments)
;;; -----------------------------------------------------------------------
(define-macro (define-language . args)
  (nanopass-expand-define-language (cons 'define-language args)))

(define-macro (define-pass . args)
  (nanopass-expand-define-pass (cons 'define-pass args)))

(define-macro (trace-define-pass . args)
  (nanopass-expand-trace-define-pass (cons 'trace-define-pass args)))

(define-macro (define-parser . args)
  (nanopass-expand-define-parser (cons 'define-parser args)))

(define-macro (define-unparser . args)
  (nanopass-expand-define-unparser (cons 'define-unparser args)))

(define-macro (define-picopass . args)
  (nanopass-expand-define-picopass (cons 'define-picopass args)))

(define-macro (define-femtopass . args)
  (nanopass-expand-define-femtopass (cons 'define-femtopass args)))

(define-macro (define-attopass . args)
  (nanopass-expand-define-attopass (cons 'define-attopass args)))

(define-macro (in-context . args)
  (if (= (length args) 2)
      (list (car args) (cadr args))
      (list (string->symbol "nanopass-parse-nt") (list 'quote (car args)) (caddr args) (list 'quote (cadr args)))))

(define-macro (nanopass-template . args)
  (nanopass-expand-template (car args) '()))

(define-macro (picopass-seq* . rules)
  (if (null? rules)
      '(lambda (ir) #f)
      (if (null? (cdr rules))
          (car rules)
          (let loop ((rem (cdr rules)) (acc (car rules)))
            (if (null? rem)
                acc
                (loop (cdr rem) (list 'picopass-seq acc (car rem))))))))

(define-macro (picopass-choice* . rules)
  (if (null? rules)
      '(lambda (ir) #f)
      (if (null? (cdr rules))
          (car rules)
          (let loop ((rem (cdr rules)) (acc (car rules)))
            (if (null? rem)
                acc
                (loop (cdr rem) (list 'picopass-choice acc (car rem))))))))

(define-macro (fuse-rules . args)
  (error "fuse-rules: cannot be used outside of define-pass" args))

(define-macro (fuse-tree-rules . args)
  (error "fuse-tree-rules: cannot be used outside of define-pass" args))
