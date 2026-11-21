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
         ((eq? (car raw) 'c-init-decl)
          (%c99-extract-declarator-names (cadr raw)))
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

(define (%c99-flatten-decl-specs node)
  (let ((raw (ast-strip-span node)))
    (cond
      ((null? raw) '())
      ((boolean? raw) '())
      ((string? raw) '())
      ((symbol? raw) (list raw))
      ((and (pair? raw)
            (memq (car raw) '(c-struct c-union c-enum c-typedef-name)))
       (list raw))
      ((pair? raw)
       (append (%c99-flatten-decl-specs (car raw))
               (%c99-flatten-decl-specs (cdr raw))))
      (else '()))))

(define (%c99-list-last xs)
  (if (null? (cdr xs)) (car xs) (%c99-list-last (cdr xs))))

(define (%c99-binop-str->sym s)
  (cond
    ((string=? s ",")  'comma)
    ((string=? s "||") 'lor)
    ((string=? s "&&") 'land)
    ((string=? s "|")  'bit-or)
    ((string=? s "^")  'bit-xor)
    ((string=? s "&")  'bit-and)
    ((string=? s "%")  'rem)
    (else (string->symbol s))))

(define (%c99-assign-str->sym s)
  (cond
    ((string=? s "%=") 'rem=)
    ((string=? s "&=") 'bit-and=)
    ((string=? s "^=") 'bit-xor=)
    ((string=? s "|=") 'bit-or=)
    (else (string->symbol s))))

(define (%c99-unop-str->sym s)
  (cond
    ((string=? s "&") 'addr)
    ((string=? s "*") 'deref)
    ((string=? s "+") 'uplus)
    ((string=? s "-") 'neg)
    ((string=? s "~") 'bit-not)
    ((string=? s "!") 'lnot)
    (else (string->symbol s))))

(define (%c99-merge-c-str-literals items env ctx pos end-pos)
  (if (and (pair? items) (null? (cdr items)))
      (caar items)
      (let* ((parts
              (map (lambda (it)
                     (let* ((snode (ast-strip-span (car it)))
                            (raw (cadr snode))
                            (n (string-length raw)))
                       (cond
                         ((and (>= n 3) (char=? (string-ref raw 0) #\L) (char=? (string-ref raw 1) #\"))
                          (substring raw 2 (- n 1)))
                         ((and (>= n 2) (char=? (string-ref raw 0) #\"))
                          (substring raw 1 (- n 1)))
                         (else raw))))
                   items))
             (joined (string-append "\"" (apply string-append parts) "\""))
             (sp (%c99-make-span-from-pos env ctx pos end-pos)))
        (ast-with-span (list 'c-str joined) sp))))

(define (%c99-fold-binop-cst res env ctx pos end-pos)
  (let ((lhs (cdr (car res)))
        (rest (cdr (cadr res))))
    (if (null? rest)
        lhs
        (let loop ((items rest) (acc lhs))
          (if (null? items)
              acc
              (let* ((item (car items))
                     (op-str (%c99-string-trim-right-ws (%c99-cst->string (car item))))
                     (op-sym (%c99-binop-str->sym op-str))
                     (rhs (%c99-list-last item))
                     (sp (%c99-make-span-from-pos env ctx pos end-pos)))
                (loop (cdr items)
                      (ast-with-span (list 'c-binop op-sym acc rhs) sp))))))))

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

    ((storage_class_specifier builtin_type_specifier type_qualifier function_specifier struct_or_union)
     (peg:map (lambda (res)
                (string->symbol (%c99-string-trim-right-ws (%c99-cst->string res))))
              base-parser))

    ((explicit_declaration_specifiers typedef_declaration_specifiers specifier_qualifier_list)
     (peg:map %c99-flatten-decl-specs base-parser))

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

    ((pointer)
     (peg:map (lambda (res)
                (map (lambda (level)
                       (let ((q (if (>= (length level) 3) (list-ref level 2) #f)))
                         (if q (%c99-flatten-decl-specs q) '())))
                     res))
              base-parser))

    ((direct_declarator)
     (peg:map (lambda (res)
                (cond
                  ;; Base: identifier ws
                  ((and (pair? res) (symbol? (car res)))
                   (list 'c-decl-id (car res)))
                  ;; Parenthesized declarator: '(' ws decl ')' ws
                  ((and (pair? res) (string? (car res)) (string=? (car res) "("))
                   (list-ref res 2))
                  ;; Left-recursive array
                  ((and (pair? res) (pair? (car res)) (string? (cadr res)) (string=? (cadr res) "["))
                   (let ((nlen (length res)))
                     (cond
                       ((= nlen 7)
                        (list 'c-arr-declarator (car res) (list-ref res 4)))
                       ((= nlen 10)
                        (list 'c-arr-declarator (car res) (list-ref res 7)))
                       (else
                        (list 'c-arr-declarator (car res) #f)))))
                  ;; Left-recursive fn
                  ((and (pair? res) (pair? (car res)) (string? (cadr res)) (string=? (cadr res) "("))
                   (list 'c-fn-declarator (car res)
                         (let ((p (list-ref res 3)))
                           (if p p '(c-param-list () #f)))))
                  (else res)))
              base-parser))

    ((declarator)
     (peg:map (lambda (res)
                (let ((ptr (car res))
                      (dd (cadr res)))
                  (if (pair? ptr)
                      (list 'c-ptr-declarator ptr dd)
                      dd)))
              base-parser))

    ((direct_abstract_declarator)
     (peg:map (lambda (res)
                (cond
                  ((not (pair? res)) res)
                  ((string? (car res))
                   (cond
                     ((string=? (car res) "(")
                      (let ((inner (list-ref res 2)))
                        (if (or (not inner) (and (pair? inner) (eq? (car inner) 'c-param-list)))
                            (list 'c-fn-declarator #f (or inner '(c-param-list () #f)))
                            inner)))
                     ((string=? (car res) "[")
                      (let ((nlen (length res)))
                        (cond
                          ((= nlen 6)
                           (list 'c-arr-declarator #f (list-ref res 3)))
                          ((= nlen 9)
                           (list 'c-arr-declarator #f (list-ref res 6)))
                          (else
                           (list 'c-arr-declarator #f #f)))))
                     (else res)))
                  ((and (pair? (car res)) (string? (cadr res)) (string=? (cadr res) "["))
                   (let ((nlen (length res)))
                     (cond
                       ((= nlen 7)
                        (list 'c-arr-declarator (car res) (list-ref res 4)))
                       ((= nlen 10)
                        (list 'c-arr-declarator (car res) (list-ref res 7)))
                       (else
                        (list 'c-arr-declarator (car res) #f)))))
                  ((and (pair? (car res)) (string? (cadr res)) (string=? (cadr res) "("))
                   (list 'c-fn-declarator (car res) (or (list-ref res 3) '(c-param-list () #f))))
                  (else res)))
              base-parser))

    ((abstract_declarator)
     (peg:map (lambda (res)
                (if (and (pair? res) (pair? (car res))
                         (or (null? (caar res)) (list? (caar res)))
                         (not (memq (caar res) '(c-arr-declarator c-fn-declarator c-ptr-declarator))))
                    (list 'c-ptr-declarator (car res) (cadr res))
                    res))
              base-parser))

    ((type_name)
     (peg:map (lambda (res)
                (list 'c-type-name (car res) (cadr res)))
              base-parser))

    ((parameter_list)
     (peg:map (lambda (res)
                (cons (cdr (car res))
                      (map cadddr (cdr (cadr res)))))
              base-parser))

    ((parameter_type_list)
     (peg:map (lambda (res)
                (list 'c-param-list (car res) (if (cadr res) #t #f)))
              base-parser))

    ((parameter_declaration)
     (peg:map (lambda (res)
                (list 'c-param (car res) (cadr res)))
              base-parser))

    ((init_declarator)
     (peg:map (lambda (res)
                (let ((decl (car res))
                      (opt-init (cadr res)))
                  (list 'c-init-decl decl
                        (if (pair? opt-init) (list-ref opt-init 2) #f))))
              base-parser))

    ((init_declarator_list typedef_init_declarator_list struct_declarator_list argument_expr_list)
     (peg:map (lambda (res)
                (cons (cdr (car res))
                      (map caddr (cdr (cadr res)))))
              base-parser))

    ((struct_declarator)
     (peg:map (lambda (res)
                (if (and (pair? res) (>= (length res) 4)
                         (string? (cadr res)) (string=? (cadr res) ":"))
                    (list 'c-struct-decl (car res) (list-ref res 3))
                    (list 'c-struct-decl res #f)))
              base-parser))

    ((struct_declaration)
     (peg:map (lambda (res)
                (list 'c-field-decl (car res) (or (cadr res) '())))
              base-parser))

    ((designator)
     (peg:map (lambda (res)
                (if (string=? (car res) "[")
                    (list 'c-desig-index (list-ref res 2))
                    (list 'c-desig-field (list-ref res 2))))
              base-parser))

    ((designation)
     (peg:map car base-parser))

    ((initializer_item)
     (peg:map (lambda (res)
                (list 'c-init-item (car res) (cadr res)))
              base-parser))

    ((initializer_list enumerator_list)
     (peg:map (lambda (res)
                (cons (cdr (car res))
                      (map cadddr (cdr (cadr res)))))
              base-parser))

    ((initializer)
     (peg:map (lambda (res)
                (if (and (pair? res) (string? (car res)) (string=? (car res) "{"))
                    (list 'c-init-list (list-ref res 2))
                    res))
              base-parser))

    ((struct_or_union_specifier)
     (%c99-wrap-span env
      (lambda (ctx pos sk fk)
        (base-parser ctx pos
                     (lambda (res next-pos inner-fk)
                       (let* ((is-union? (eq? (car res) 'union))
                              (tag-sym (list-ref res 2))
                              (fields (if (>= (length res) 7) (list-ref res 6) '()))
                              (sp (%c99-make-span-from-pos env ctx pos next-pos)))
                         (if (symbol? tag-sym)
                             (c99-register-var! env tag-sym (if is-union? 'tag-union 'tag-struct) sp))
                         (sk (list (if is-union? 'c-union 'c-struct)
                                   tag-sym
                                   fields)
                             next-pos inner-fk)))
                     fk))))

    ((enum_specifier)
     (%c99-wrap-span env
      (lambda (ctx pos sk fk)
        (base-parser ctx pos
                     (lambda (res next-pos inner-fk)
                       (let* ((tag-sym (list-ref res 3))
                              (enums (if (>= (length res) 8) (list-ref res 7) '()))
                              (sp (%c99-make-span-from-pos env ctx pos next-pos)))
                         (if (symbol? tag-sym)
                             (c99-register-var! env tag-sym 'tag-enum sp))
                         (sk (list 'c-enum tag-sym enums)
                             next-pos inner-fk)))
                     fk))))

    ((enumerator)
     (lambda (ctx pos sk fk)
       (base-parser ctx pos
                    (lambda (res next-pos inner-fk)
                      (let* ((ec-sym (let ((syms (%c99-flatten-tag-syms (car res))))
                                       (if (pair? syms) (car syms) #f)))
                             (opt-eq (cadr res))
                             (val-expr (if (pair? opt-eq) (list-ref opt-eq 2) #f))
                             (sp (%c99-make-span-from-pos env ctx pos next-pos)))
                        (if ec-sym
                            (c99-register-var! env ec-sym 'enum-const sp))
                        (sk (list 'c-enumerator ec-sym val-expr)
                            next-pos inner-fk)))
                    fk)))

    ((explicit_declaration typedef_declaration)
     (lambda (ctx pos sk fk)
       (base-parser ctx pos
                    (lambda (res next-pos inner-fk)
                      (let* ((specs (car res))
                             (inits (or (cadr res) '()))
                             (sp (%c99-make-span-from-pos env ctx pos next-pos))
                             (is-td? (%c99-has-typedef-spec? specs))
                             (decl-names (if (pair? inits) (%c99-extract-declarator-names inits) '())))
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

    ((expr logical_or_expr logical_and_expr inclusive_or_expr exclusive_or_expr
      and_expr equality_expr relational_expr shift_expr additive_expr multiplicative_expr)
     (lambda (ctx pos sk fk)
       (base-parser ctx pos
                    (lambda (res next-pos inner-fk)
                      (sk (%c99-fold-binop-cst res env ctx pos next-pos)
                          next-pos inner-fk))
                    fk)))

    ((assignment_operator)
     (peg:map (lambda (res)
                (list 'c-assign-op (%c99-assign-str->sym (%c99-string-trim-right-ws (%c99-cst->string res)))))
              base-parser))

    ((assignment_expr)
     (lambda (ctx pos sk fk)
       (base-parser ctx pos
                    (lambda (res next-pos inner-fk)
                      (if (and (pair? res) (pair? (cdr res))
                               (pair? (cadr res)) (eq? (caadr res) 'c-assign-op))
                          (let ((sp (%c99-make-span-from-pos env ctx pos next-pos)))
                            (sk (ast-with-span
                                 (list 'c-assign (cadadr res) (car res) (list-ref res 3))
                                 sp)
                                next-pos inner-fk))
                          (sk res next-pos inner-fk)))
                    fk)))

    ((conditional_expr)
     (lambda (ctx pos sk fk)
       (base-parser ctx pos
                    (lambda (res next-pos inner-fk)
                      (if (and (pair? res) (= (length res) 2))
                          (let ((opt-tail (cadr res)))
                            (if (pair? opt-tail)
                                (let ((sp (%c99-make-span-from-pos env ctx pos next-pos)))
                                  (sk (ast-with-span
                                       (list 'c-ternary (car res) (list-ref opt-tail 2) (list-ref opt-tail 5))
                                       sp)
                                      next-pos inner-fk))
                                (sk (car res) next-pos inner-fk)))
                          (sk res next-pos inner-fk)))
                    fk)))

    ((cast_expr)
     (lambda (ctx pos sk fk)
       (base-parser ctx pos
                    (lambda (res next-pos inner-fk)
                      (if (and (pair? res) (string? (car res)) (string=? (car res) "("))
                          (let ((sp (%c99-make-span-from-pos env ctx pos next-pos)))
                            (sk (ast-with-span
                                 (list 'c-cast (list-ref res 2) (list-ref res 6))
                                 sp)
                                next-pos inner-fk))
                          (sk res next-pos inner-fk)))
                    fk)))

    ((unary_operator)
     (peg:map (lambda (res)
                (list 'c-unop-tag (%c99-unop-str->sym (%c99-string-trim-right-ws (%c99-cst->string res)))))
              base-parser))

    ((unary_expr)
     (lambda (ctx pos sk fk)
       (base-parser ctx pos
                    (lambda (res next-pos inner-fk)
                      (let ((sp (%c99-make-span-from-pos env ctx pos next-pos)))
                        (cond
                          ((and (pair? res) (string? (car res))
                                (or (string=? (car res) "++") (string=? (car res) "--")))
                           (sk (ast-with-span
                                (list 'c-unop (if (string=? (car res) "++") 'pre++ 'pre--)
                                      (list-ref res 2))
                                sp)
                               next-pos inner-fk))
                          ((and (pair? res) (pair? (car res)) (eq? (caar res) 'c-unop-tag))
                           (sk (ast-with-span
                                (list 'c-unop (cadar res) (list-ref res 2))
                                sp)
                               next-pos inner-fk))
                          ((and (pair? res) (string? (car res)) (string=? (car res) "sizeof"))
                           (if (= (length res) 9)
                               (sk (ast-with-span (list 'c-sizeof-type (list-ref res 5)) sp)
                                   next-pos inner-fk)
                               (sk (ast-with-span (list 'c-sizeof-expr (list-ref res 3)) sp)
                                   next-pos inner-fk)))
                          (else
                           (sk res next-pos inner-fk)))))
                    fk)))

    ((postfix_expr)
     (lambda (ctx pos sk fk)
       (base-parser ctx pos
                    (lambda (res next-pos inner-fk)
                      (let ((sp (%c99-make-span-from-pos env ctx pos next-pos)))
                        (cond
                          ((not (pair? res))
                           (sk res next-pos inner-fk))
                          ((and (string? (car res)) (string=? (car res) "("))
                           (sk (ast-with-span
                                (list 'c-compound-lit (list-ref res 2) (list-ref res 7))
                                sp)
                               next-pos inner-fk))
                          ((and (pair? (cdr res)) (string? (cadr res)))
                           (let ((op (cadr res))
                                 (base (car res)))
                             (cond
                               ((string=? op "[")
                                (sk (ast-with-span (list 'c-index base (list-ref res 3)) sp)
                                    next-pos inner-fk))
                               ((string=? op "(")
                                (let ((args (list-ref res 3)))
                                  (sk (ast-with-span
                                       (cons 'c-call (cons base (if (pair? args) args '())))
                                       sp)
                                      next-pos inner-fk)))
                               ((string=? op ".")
                                (sk (ast-with-span (list 'c-member base (list-ref res 3) #f) sp)
                                    next-pos inner-fk))
                               ((string=? op "->")
                                (sk (ast-with-span (list 'c-member base (list-ref res 3) #t) sp)
                                    next-pos inner-fk))
                               ((or (string=? op "++") (string=? op "--"))
                                (sk (ast-with-span
                                     (list 'c-unop (if (string=? op "++") 'post++ 'post--) base)
                                     sp)
                                    next-pos inner-fk))
                               (else
                                (sk res next-pos inner-fk)))))
                          (else
                           (sk res next-pos inner-fk)))))
                    fk)))

    ((primary_expr)
     (lambda (ctx pos sk fk)
       (base-parser ctx pos
                    (lambda (res next-pos inner-fk)
                      (let ((sp (%c99-make-span-from-pos env ctx pos next-pos)))
                        (cond
                          ((and (pair? res) (symbol? (car res)))
                           (let* ((sym (car res))
                                  (bid (c99-lookup-binding-id env sym)))
                             (sk (ast-with-span (list 'c-var-ref sym bid) sp)
                                 next-pos inner-fk)))
                          ((and (pair? res)
                                (ast-has-span? (car res))
                                (eq? (car (ast-strip-span (car res))) 'c-const))
                           (sk (car res) next-pos inner-fk))
                          ((and (pair? res) (string? (car res)) (string=? (car res) "("))
                           (sk (list-ref res 2) next-pos inner-fk))
                          ((and (pair? res)
                                (pair? (car res))
                                (ast-has-span? (caar res))
                                (eq? (car (ast-strip-span (caar res))) 'c-str))
                           (sk (%c99-merge-c-str-literals res env ctx pos next-pos)
                               next-pos inner-fk))
                          (else
                           (sk (ast-with-span res sp) next-pos inner-fk)))))
                    fk)))

    ((selection_stmt)
     (%c99-wrap-span env
      (peg:map (lambda (res)
                 (let ((kw (car res)))
                   (if (string=? kw "if")
                       (let ((opt-else (list-ref res 9)))
                         (if (pair? opt-else)
                             (list 'c-if (list-ref res 5) (list-ref res 8) (list-ref opt-else 3))
                             (list 'c-if (list-ref res 5) (list-ref res 8))))
                       (list 'c-switch (list-ref res 5) (list-ref res 8)))))
               base-parser)))

    ((iteration_stmt)
     (%c99-wrap-span env
      (peg:map (lambda (res)
                 (let ((kw (car res)))
                   (cond
                     ((string=? kw "while")
                      (list 'c-while (list-ref res 5) (list-ref res 8)))
                     ((string=? kw "do")
                      (list 'c-do-while (list-ref res 3) (list-ref res 9)))
                     ((string=? kw "for")
                      (let* ((c1 (list-ref res 5))
                             (c1-stripped (ast-strip-span c1))
                             (init-node (if (and (pair? c1-stripped)
                                                 (memq (car c1-stripped) '(c-decl c-typedef)))
                                            c1
                                            (if (pair? c1) (car c1) #f)))
                             (cond-node (list-ref res 6))
                             (step-node (list-ref res 9))
                             (body-node (list-ref res 12)))
                        (list 'c-for init-node cond-node step-node body-node)))
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
               (diag (make-diagnostic 'error "C99-PARSE-001" sp msg)))
          (report-diagnostic diag)
          (raise (list 'c99-syntax-error msg sp exp "C99-PARSE-001"))))))

(define (parse-c99-string src-text . maybe-filename)
  (let ((fname (if (pair? maybe-filename) (car maybe-filename) "<c99-input>")))
    (%c99-run-entry-parser src-text fname 'translation_unit)))

(define (parse-c99-expr-string expr-text . maybe-filename)
  (let ((fname (if (pair? maybe-filename) (car maybe-filename) "<c99-expr>")))
    (%c99-run-entry-parser expr-text fname 'expr)))

(define (parse-c99-tokens tokens . maybe-filename)
  (let* ((fname (if (pair? maybe-filename)
                    (car maybe-filename)
                    (if (pair? tokens)
                        (span-file (c-token-span (car tokens)))
                        "<c99-tokens>")))
         (concat (c-concat-adjacent-string-tokens tokens))
         (src-str (c-tokens->source-string concat)))
    (parse-c99-string src-str fname)))

(define (parse-c99-preprocessed-string src-text . rest)
  (let* ((fname (if (pair? rest) (car rest) "<c99-input>"))
         (ctx   (if (and (pair? rest) (pair? (cdr rest)))
                    (cadr rest)
                    (make-default-cpp-context)))
         (pp-toks (cpp-preprocess-string src-text fname ctx)))
    (parse-c99-tokens pp-toks fname)))

(define (parse-c99-file filepath . maybe-cpp-ctx)
  (let* ((ctx (if (pair? maybe-cpp-ctx) (car maybe-cpp-ctx) (make-default-cpp-context)))
         (pp-toks (cpp-preprocess-file filepath ctx)))
    (parse-c99-tokens pp-toks filepath)))
