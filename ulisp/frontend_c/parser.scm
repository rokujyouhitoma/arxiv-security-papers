;;; =======================================================================
;;; ULisp C99 Frontend: PEG-Based C99 Parser & L_c_ast Builder
;;; Conforms to DSN-33-11 §4.2, DSN-33-22 §3, DSN-33-32 & Issue #931 / #915
;;; Uses tools/grammars/c99.peg with Warth left-recursion, <source-span> (#824),
;;; and <binding-id> / Scope Manager (#837) for typedef disambiguation.
;;; =======================================================================

;;; -----------------------------------------------------------------------
;;; 1. CST / String Utilities
;;; -----------------------------------------------------------------------

(define (%c99-cst->string node)
  (cond
    ((string? node) node)
    ((char? node) (string node))
    ((symbol? node) (symbol->string node))
    ((boolean? node) "")
    ((null? node) "")
    ((pair? node)
     (if (and (symbol? (car node)) (not (pair? (cdr node))) (not (null? (cdr node))))
         (%c99-cst->string (cdr node))
         (string-append (%c99-cst->string (car node))
                        (%c99-cst->string (cdr node)))))
    (else "")))

(define (%c99-string-trim-right-ws str)
  (let loop ((i (- (string-length str) 1)))
    (if (< i 0)
        ""
        (let ((ch (string-ref str i)))
          (if (or (char=? ch #\space)
                  (char=? ch #\tab)
                  (char=? ch #\newline)
                  (char=? ch #\return))
              (loop (- i 1))
              (substring str 0 (+ i 1)))))))

(define (%c99-read-grammar-text)
  (guard (ex (else
              (guard (ex2 (else
                           (error "Unable to locate tools/grammars/c99.peg" ex2)))
                (read-all-file-text "../tools/grammars/c99.peg"))))
    (read-all-file-text "tools/grammars/c99.peg")))

;;; -----------------------------------------------------------------------
;;; 2. C99 Parse Environment (Scope Manager + Typedef Table + Source Span)
;;; -----------------------------------------------------------------------

(define-record-type <c99-parse-env>
  (%make-c99-parse-env scope-mgr file text)
  c99-parse-env?
  (scope-mgr c99-parse-env-scope-mgr)
  (file      c99-parse-env-file)
  (text      c99-parse-env-text c99-parse-env-text-set!))

(define (make-c99-parse-env . maybe-file)
  (let ((fname (if (pair? maybe-file) (car maybe-file) "<c99-input>")))
    (%make-c99-parse-env (make-scope-manager) fname "")))

(define (c99-push-scope! env kind)
  (scope-manager-push! (c99-parse-env-scope-mgr env) kind))

(define (c99-pop-scope! env)
  (let ((mgr (c99-parse-env-scope-mgr env)))
    (if (scope-node? (scope-node-parent (scope-manager-current mgr)))
        (scope-manager-pop! mgr)
        #f)))

(define (c99-register-typedef! env sym . maybe-span)
  (let* ((mgr (c99-parse-env-scope-mgr env))
         (sp (if (pair? maybe-span) (car maybe-span) #f)))
    (if sp
        (scope-manager-define! mgr sym 'typedef ':source-span sp)
        (scope-manager-define! mgr sym 'typedef))))

(define (c99-register-var! env sym kind . maybe-span)
  (let* ((mgr (c99-parse-env-scope-mgr env))
         (sp (if (pair? maybe-span) (car maybe-span) #f)))
    (if sp
        (scope-manager-define! mgr sym kind ':source-span sp)
        (scope-manager-define! mgr sym kind))))

(define (c99-typedef-bound? env sym)
  (scope-manager-typedef-name? (c99-parse-env-scope-mgr env) sym))

(define (c99-lookup-binding env sym . maybe-ns)
  (let ((mgr (c99-parse-env-scope-mgr env)))
    (if (pair? maybe-ns)
        (scope-manager-lookup mgr sym (car maybe-ns))
        (scope-manager-lookup mgr sym))))

(define (c99-lookup-binding-id env sym . maybe-ns)
  (let ((b (if (pair? maybe-ns)
               (c99-lookup-binding env sym (car maybe-ns))
               (c99-lookup-binding env sym))))
    (if b (binding-id b) #f)))

;;; -----------------------------------------------------------------------
;;; 3. Cached Grammar AST & Standalone PEG Parser
;;; -----------------------------------------------------------------------

(define *c99-peg-grammar-ast* (cons #f '()))
(define *c99-standalone-parser* (cons #f '()))

(define (c99-peg-grammar-ast)
  (or (car *c99-peg-grammar-ast*)
      (let* ((txt (%c99-read-grammar-text))
             (ast (optimize-grammar (parse-peg-grammar txt))))
        (set-car! *c99-peg-grammar-ast* ast)
        ast)))

(define (c99-peg-parser . maybe-entry)
  (if (pair? maybe-entry)
      (compile-peg-grammar (c99-peg-grammar-ast) (car maybe-entry))
      (or (car *c99-standalone-parser*)
          (let ((p (compile-peg-grammar (c99-peg-grammar-ast) 'translation_unit)))
            (set-car! *c99-standalone-parser* p)
            p))))

;;; -----------------------------------------------------------------------
;;; 4. Source Span Attachment & AST Helpers
;;; -----------------------------------------------------------------------

(define (%c99-make-span-from-pos env ctx start-pos end-pos)
  (let* ((txt (parse-ctx-text ctx))
         (slc (calc-line-col txt start-pos))
         (elc (calc-line-col txt (max start-pos end-pos))))
    (make-source-span (c99-parse-env-file env)
                      (car slc) (cdr slc)
                      (car elc) (cdr elc)
                      #f
                      (next-source-span-id!))))

(define (%c99-wrap-span env parser)
  (lambda (ctx pos sk fk)
    (parser ctx pos
            (lambda (val next-pos inner-fk)
              (let ((sp (%c99-make-span-from-pos env ctx pos next-pos)))
                (sk (ast-with-span val sp) next-pos inner-fk)))
            fk)))

;;; Extracts declared identifier symbols from declarator / init-declarator trees
(define (%c99-extract-declarator-names node)
  (let ((raw (ast-strip-span node)))
    (cond
      ((null? raw) '())
      ((boolean? raw) '())
      ((string? raw) '())
      ((symbol? raw) '())
      ((pair? raw)
       (cond
         ((eq? (car raw) 'c-decl-id)
          (list (cadr raw)))
         ((eq? (car raw) 'c-fn-declarator)
          (%c99-extract-declarator-names (cadr raw)))
         ((eq? (car raw) 'c-arr-declarator)
          (%c99-extract-declarator-names (cadr raw)))
         ((eq? (car raw) 'c-ptr-declarator)
          (%c99-extract-declarator-names (caddr raw)))
         ((eq? (car raw) 'c-param-list)
          '())
         (else
          (append (%c99-extract-declarator-names (car raw))
                  (%c99-extract-declarator-names (cdr raw))))))
      (else '()))))

;;; Extracts parameter symbols from the outermost function declarator
(define (%c99-extract-fn-param-names decl-node)
  (let ((raw (ast-strip-span decl-node)))
    (cond
      ((not (pair? raw)) '())
      ((eq? (car raw) 'c-fn-declarator)
       (let ((inner (ast-strip-span (cadr raw)))
             (params (caddr raw)))
         (if (and (pair? inner) (eq? (car inner) 'c-decl-id))
             (%c99-collect-param-ids params)
             (let ((sub (%c99-extract-fn-param-names inner)))
               (if (null? sub) (%c99-collect-param-ids params) sub)))))
      ((eq? (car raw) 'c-ptr-declarator)
       (%c99-extract-fn-param-names (caddr raw)))
      (else '()))))

(define (%c99-collect-param-ids node)
  (let ((raw (ast-strip-span node)))
    (cond
      ((not (pair? raw)) '())
      ((eq? (car raw) 'c-param)
       (let ((d (caddr raw)))
         (if d (%c99-extract-declarator-names d) '())))
      (else
       (append (%c99-collect-param-ids (car raw))
               (%c99-collect-param-ids (cdr raw)))))))

(define (%c99-has-typedef-spec? specs-node)
  (let ((raw (ast-strip-span specs-node)))
    (cond
      ((eq? raw 'typedef) #t)
      ((pair? raw)
       (or (%c99-has-typedef-spec? (car raw))
           (%c99-has-typedef-spec? (cdr raw))))
      (else #f))))

(define (%c99-flatten-tag-syms node)
  (let ((raw (ast-strip-span node)))
    (cond
      ((null? raw) '())
      ((boolean? raw) '())
      ((string? raw) '())
      ((symbol? raw) (list raw))
      ((pair? raw)
       (append (%c99-flatten-tag-syms (car raw))
               (%c99-flatten-tag-syms (cdr raw))))
      (else '()))))

;;; -----------------------------------------------------------------------
;;; 5. Environment-Aware C99 PEG Compiler (Produces L_c_ast with Span & Binding ID)
;;; -----------------------------------------------------------------------

(define (compile-c99-parser-with-env env . maybe-entry)
  (let* ((grammar (c99-peg-grammar-ast))
         (rules (peg-grammar-def-rules grammar))
         (entry-name (if (pair? maybe-entry) (car maybe-entry) 'translation_unit))
         (rule-table '()))
    (define (lookup name)
      (let ((slot (assoc name rule-table)))
        (if slot (cdr slot) #f)))

    ;; Initialize forward rule slots
    (for-each
     (lambda (r)
       (set! rule-table (cons (cons (peg-rule-def-name r) #f) rule-table)))
     rules)

    ;; Compile each rule with C99 semantic hooks
    (for-each
     (lambda (r)
       (let* ((name (peg-rule-def-name r))
              (raw-body
               (cond
                 ;; Because typedef_name is strictly enforced by scope predicate,
                 ;; typedef_init_declarator can match full init_declarator (including "T *p;")
                 ((eq? name 'typedef_init_declarator)
                  (let ((init-decl (lookup 'init_declarator)))
                    (lambda (ctx pos sk fk)
                      ((lookup 'init_declarator) ctx pos sk fk))))
                 (else
                  (compile-expr->parser (peg-rule-def-expr r) lookup))))
              (decorated (decorate-c99-rule name raw-body env lookup))
              (wrapped (if (peg-rule-def-memoize? r)
                           ;; Do not memoize context-sensitive typedef_name predicate globally across scope mutations
                           (if (eq? name 'typedef_name)
                               decorated
                               (peg:rule name decorated))
                           decorated)))
         (let ((slot (assoc name rule-table)))
           (set-cdr! slot wrapped))))
     rules)

    (or (lookup entry-name)
        (error "Unknown C99 grammar entry rule" entry-name))))

(define (decorate-c99-rule name base-parser env lookup)
  (case name
    ((identifier)
     (peg:map (lambda (res)
                (string->symbol (%c99-cst->string res)))
              base-parser))

    ((typedef_name)
     (lambda (ctx pos sk fk)
       (base-parser ctx pos
                    (lambda (sym next-pos inner-fk)
                      (if (c99-typedef-bound? env sym)
                          (sk (list 'c-typedef-name sym (c99-lookup-binding-id env sym))
                              next-pos inner-fk)
                          (fk)))
                    fk)))

    ((storage_class_specifier builtin_type_specifier type_qualifier function_specifier)
     (peg:map (lambda (res)
                (string->symbol (%c99-string-trim-right-ws (%c99-cst->string res))))
              base-parser))

    ((constant)
     (%c99-wrap-span env
      (peg:map (lambda (res)
                 (list 'c-const (%c99-cst->string res)))
               base-parser)))

    ((string_literal)
     (%c99-wrap-span env
      (peg:map (lambda (res)
                 (list 'c-str (%c99-cst->string res)))
               base-parser)))

    ((direct_declarator)
     (peg:map (lambda (res)
                (cond
                  ;; Base: identifier ws -> (ident sym)
                  ((and (pair? res) (symbol? (car res)))
                   (list 'c-decl-id (car res)))
                  ;; Parenthesized declarator: '(' ws decl ')' ws
                  ((and (pair? res) (string? (car res)) (string=? (car res) "("))
                   (caddr res))
                  ;; Left-recursive array: dd '[' ... ']' ws
                  ((and (pair? res) (pair? (car res)) (string? (cadr res)) (string=? (cadr res) "["))
                   (list 'c-arr-declarator (car res) (cddr res)))
                  ;; Left-recursive fn: dd '(' ws params ')' ws
                  ((and (pair? res) (pair? (car res)) (string? (cadr res)) (string=? (cadr res) "("))
                   (list 'c-fn-declarator (car res) (cadddr res)))
                  (else res)))
              base-parser))

    ((declarator)
     (peg:map (lambda (res)
                (let ((ptr (car res))
                      (dd (cadr res)))
                  (if ptr
                      (list 'c-ptr-declarator ptr dd)
                      dd)))
              base-parser))

    ((parameter_declaration)
     (peg:map (lambda (res)
                (list 'c-param (car res) (cadr res)))
              base-parser))

    ((struct_or_union_specifier)
     (%c99-wrap-span env
      (lambda (ctx pos sk fk)
        (base-parser ctx pos
                     (lambda (res next-pos inner-fk)
                       (let* ((kind-str (%c99-cst->string (car res)))
                              (is-union? (string=? kind-str "union"))
                              (tag-sym (caddr res))
                              (sp (%c99-make-span-from-pos env ctx pos next-pos)))
                         (if (symbol? tag-sym)
                             (c99-register-var! env tag-sym (if is-union? 'tag-union 'tag-struct) sp))
                         (sk (list (if is-union? 'c-union 'c-struct)
                                   tag-sym
                                   (if (>= (length res) 7) (list-ref res 5) '()))
                             next-pos inner-fk)))
                     fk))))

    ((enum_specifier)
     (%c99-wrap-span env
      (lambda (ctx pos sk fk)
        (base-parser ctx pos
                     (lambda (res next-pos inner-fk)
                       (let* ((tag-sym (caddr res))
                              (sp (%c99-make-span-from-pos env ctx pos next-pos)))
                         (if (symbol? tag-sym)
                             (c99-register-var! env tag-sym 'tag-enum sp))
                         (sk (list 'c-enum tag-sym (cdddr res))
                             next-pos inner-fk)))
                     fk))))

    ((enumerator)
     (lambda (ctx pos sk fk)
       (base-parser ctx pos
                    (lambda (res next-pos inner-fk)
                      (let* ((ec-sym (let ((syms (%c99-flatten-tag-syms (car res))))
                                       (if (pair? syms) (car syms) #f)))
                             (sp (%c99-make-span-from-pos env ctx pos next-pos)))
                        (if ec-sym
                            (c99-register-var! env ec-sym 'enum-const sp))
                        (sk (list 'c-enumerator ec-sym (cadr res))
                            next-pos inner-fk)))
                    fk)))

    ((explicit_declaration typedef_declaration)
     (lambda (ctx pos sk fk)
       (base-parser ctx pos
                    (lambda (res next-pos inner-fk)
                      (let* ((specs (car res))
                             (inits (cadr res))
                             (sp (%c99-make-span-from-pos env ctx pos next-pos))
                             (is-td? (%c99-has-typedef-spec? specs))
                             (decl-names (if inits (%c99-extract-declarator-names inits) '())))
                        (for-each
                         (lambda (sym)
                           (if is-td?
                               (c99-register-typedef! env sym sp)
                               (c99-register-var! env sym 'variable sp)))
                         decl-names)
                        (let ((node (ast-with-span
                                     (list (if is-td? 'c-typedef 'c-decl)
                                           specs
                                           inits)
                                     sp)))
                          (sk node next-pos inner-fk))))
                    fk)))

    ((compound_stmt)
     (lambda (ctx pos sk fk)
       (let ((p-lbrace (peg:seq (peg:lit "{") (lookup 'ws)))
             (p-items  (peg:star (lookup 'block_item)))
             (p-rbrace (peg:seq (peg:lit "}") (lookup 'ws))))
         (p-lbrace ctx pos
                   (lambda (_lb pos1 fk1)
                     (c99-push-scope! env 'block)
                     (p-items ctx pos1
                              (lambda (items pos2 fk2)
                                (p-rbrace ctx pos2
                                          (lambda (_rb end-pos fk3)
                                            (c99-pop-scope! env)
                                            (let ((sp (%c99-make-span-from-pos env ctx pos end-pos)))
                                              (sk (ast-with-span (cons 'c-block items) sp)
                                                  end-pos fk3)))
                                          (lambda ()
                                            (c99-pop-scope! env)
                                            (fk2))))
                              (lambda ()
                                (c99-pop-scope! env)
                                (fk1))))
                   fk))))

    ((function_definition)
     (lambda (ctx pos sk fk)
       (let ((p-specs (lookup 'declaration_specifiers))
             (p-decl  (lookup 'declarator))
             (p-dlist (peg:opt (lookup 'declaration_list)))
             (p-body  (lookup 'compound_stmt)))
         (p-specs ctx pos
                  (lambda (specs pos1 fk1)
                    (p-decl ctx pos1
                            (lambda (decl pos2 fk2)
                              (let* ((fn-names (%c99-extract-declarator-names decl))
                                     (fn-sym (if (pair? fn-names) (car fn-names) 'anon_fn))
                                     (param-syms (%c99-extract-fn-param-names decl))
                                     (fn-sp (%c99-make-span-from-pos env ctx pos pos2)))
                                (c99-register-var! env fn-sym 'function fn-sp)
                                (c99-push-scope! env 'function)
                                (let ((param-bindings
                                       (map (lambda (psym)
                                              (let ((b (c99-register-var! env psym 'parameter fn-sp)))
                                                (list psym (binding-id b))))
                                            param-syms)))
                                  (p-dlist ctx pos2
                                           (lambda (dlist pos3 fk3)
                                             (p-body ctx pos3
                                                     (lambda (body end-pos fk4)
                                                       (c99-pop-scope! env)
                                                       (let ((sp (%c99-make-span-from-pos env ctx pos end-pos)))
                                                         (sk (ast-with-span
                                                              (list 'c-fn-def fn-sym specs decl param-bindings body)
                                                              sp)
                                                             end-pos fk4)))
                                                     (lambda ()
                                                       (c99-pop-scope! env)
                                                       (fk3))))
                                           (lambda ()
                                             (c99-pop-scope! env)
                                             (fk2))))))
                            fk1))
                  fk))))

    ((primary_expr)
     (lambda (ctx pos sk fk)
       (base-parser ctx pos
                    (lambda (res next-pos inner-fk)
                      (let ((sp (%c99-make-span-from-pos env ctx pos next-pos)))
                        (if (and (pair? res) (symbol? (car res)))
                            (let* ((sym (car res))
                                   (bid (c99-lookup-binding-id env sym)))
                              (sk (ast-with-span (list 'c-var-ref sym bid) sp)
                                  next-pos inner-fk))
                            (sk (ast-with-span res sp) next-pos inner-fk))))
                    fk)))

    ((selection_stmt)
     (%c99-wrap-span env
      (peg:map (lambda (res)
                 (let ((kw (car res)))
                   (if (string=? kw "if")
                       (list 'c-if (list-ref res 4) (list-ref res 7) (list-ref res 8))
                       (list 'c-switch (list-ref res 4) (list-ref res 7)))))
               base-parser)))

    ((iteration_stmt)
     (%c99-wrap-span env
      (peg:map (lambda (res)
                 (let ((kw (car res)))
                   (cond
                     ((string=? kw "while") (list 'c-while (list-ref res 4) (list-ref res 7)))
                     ((string=? kw "do") (list 'c-do-while (list-ref res 2) (list-ref res 7)))
                     ((string=? kw "for") (list 'c-for (cdddr res)))
                     (else (list 'c-iter res)))))
               base-parser)))

    ((jump_stmt)
     (%c99-wrap-span env
      (peg:map (lambda (res)
                 (let ((kw (car res)))
                   (cond
                     ((string=? kw "goto") (list 'c-goto (list-ref res 3)))
                     ((string=? kw "continue") '(c-continue))
                     ((string=? kw "break") '(c-break))
                     ((string=? kw "return") (list 'c-return (list-ref res 3)))
                     (else (list 'c-jump res)))))
               base-parser)))

    ((labeled_stmt)
     (%c99-wrap-span env
      (peg:map (lambda (res)
                 (let ((head (car res)))
                   (cond
                     ((and (string? head) (string=? head "case"))
                      (list 'c-case (list-ref res 3) (list-ref res 6)))
                     ((and (string? head) (string=? head "default"))
                      (list 'c-default (list-ref res 5)))
                     ((symbol? head)
                      (c99-register-var! env head 'label)
                      (list 'c-label head (list-ref res 4)))
                     (else (list 'c-labeled res)))))
               base-parser)))

    ((expr_stmt)
     (%c99-wrap-span env
      (peg:map (lambda (res)
                 (list 'c-expr-stmt (car res)))
               base-parser)))

    ((translation_unit)
     (%c99-wrap-span env
      (peg:map (lambda (res)
                 (cons 'c-translation-unit (cadr res)))
               base-parser)))

    (else base-parser)))

;;; -----------------------------------------------------------------------
;;; 6. Top-Level Parse API & Pretty Diagnostic Integration
;;; -----------------------------------------------------------------------

(define (%c99-run-entry-parser src-text filename entry-rule)
  (reset-alpha-symbol-counter!)
  (diagnostic-register-source-string! filename src-text)
  (let* ((env (make-c99-parse-env filename))
         (parser (compile-c99-parser-with-env env entry-rule))
         (ctx (make-parse-context src-text))
         (txt-len (string-length src-text))
         (matched #f)
         (result-val #f)
         (result-pos 0))
    (c99-parse-env-text-set! env src-text)
    (parser
     ctx 0
     (lambda (val next-pos fk)
       (if (= next-pos txt-len)
           (begin
             (set! matched #t)
             (set! result-val val)
             (set! result-pos next-pos))
           (fk)))
     (lambda ()
       (set! matched #f)))
    (if matched
        result-val
        (let* ((err-pos (parse-ctx-max-pos ctx))
               (lc (calc-line-col src-text err-pos))
               (exp (parse-ctx-expected ctx))
               (sp (make-source-span filename (car lc) (cdr lc) (car lc) (cdr lc)
                                     #f (next-source-span-id!)))
               (msg (string-append "C99 syntax error near "
                                   (if (pair? exp) (car exp) "unexpected token")))
               (diag (make-diagnostic 'error "C99-001" sp msg)))
          (report-diagnostic diag)
          (raise (list 'c99-syntax-error msg sp exp))))))

(define (parse-c99-string src-text . maybe-filename)
  (let ((fname (if (pair? maybe-filename) (car maybe-filename) "<c99-input>")))
    (%c99-run-entry-parser src-text fname 'translation_unit)))

(define (parse-c99-expr-string expr-text . maybe-filename)
  (let ((fname (if (pair? maybe-filename) (car maybe-filename) "<c99-expr>")))
    (%c99-run-entry-parser expr-text fname 'expr)))
