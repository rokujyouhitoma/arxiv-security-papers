;;; =======================================================================
;;; ULisp Compiler Pass 0a: R7RS define-library & import Desugaring Pass
;;; Conforms to DSN-33 Architecture Specification & Issue #548 (R7RS 5.6)
;;;
;;; Transforms R7RS-small modular library definitions and import sets
;;; into a flat, deterministic sequence of top-level definitions and expressions.
;;; =======================================================================

;;; -----------------------------------------------------------------------
;;; 1. Library Identification & Built-in Predicates
;;; -----------------------------------------------------------------------

(define (define-library-form? form)
  (and (pair? form) (eq? (car form) 'define-library)))

(define (import-form? form)
  (and (pair? form) (eq? (car form) 'import)))

;;; Built-in R7RS standard libraries that are inherently supported by ULisp runtime
(define (builtin-library-name? name)
  (and (pair? name)
       (or (and (eq? (car name) 'scheme)
                (memq (cadr name) '(base write read time file process-context cxr inexact complex char lazy case-lambda eval repl r5rs load)))
           (and (eq? (car name) 'ulisp)
                (memq (cadr name) '(base core native))))))

;;; Convert library name list e.g. (math matrix) to prefix string "math_matrix__"
(define (library-name->prefix-str lib-name)
  (let loop ((rest lib-name) (acc "__lib_"))
    (if (null? rest)
        (string-append acc "_")
        (let* ((elem (car rest))
               (part (cond
                       ((symbol? elem) (symbol->string elem))
                       ((number? elem) (number->string elem))
                       (else "sub"))))
          (loop (cdr rest) (string-append acc part "_"))))))

;;; -----------------------------------------------------------------------
;;; 2. Library Record Representation
;;; -----------------------------------------------------------------------

;;; Record: (list 'library-rec name exports imports body-forms)
(define (make-library-rec name exports imports body-forms)
  (list 'library-rec name exports imports body-forms))

(define (lib-rec? r)
  (and (pair? r) (eq? (car r) 'library-rec)))

(define (lib-rec-name r) (cadr r))
(define (lib-rec-exports r) (caddr r))
(define (lib-rec-imports r) (cadddr r))
(define (lib-rec-body r) (car (cddddr r)))

;;; Parse (export <export-spec> ...)
;;; Each export-spec is <identifier> or (rename <orig> <new>)
;;; Returns list of (cons <internal-name> <exported-public-name>)
(define (parse-export-specs specs)
  (let loop ((rest specs) (acc '()))
    (if (null? rest)
        (reverse acc)
        (let ((spec (car rest)))
          (cond
            ((symbol? spec)
             (loop (cdr rest) (cons (cons spec spec) acc)))
            ((and (pair? spec)
                  (eq? (car spec) 'rename)
                  (pair? (cdr spec))
                  (pair? (cddr spec)))
             (loop (cdr rest) (cons (cons (cadr spec) (caddr spec)) acc)))
            (else
             (loop (cdr rest) acc)))))))

;;; Parse a complete define-library form into a library-rec
(define (parse-define-library-form form)
  (let* ((name (cadr form))
         (decls (cddr form)))
    (let loop ((rest decls)
               (exports '())
               (imports '())
               (body-forms '()))
      (if (null? rest)
          (make-library-rec name (reverse exports) (reverse imports) (reverse body-forms))
          (let ((d (car rest)))
            (cond
              ;; (export spec ...)
              ((and (pair? d) (eq? (car d) 'export))
               (loop (cdr rest)
                     (append (reverse (parse-export-specs (cdr d))) exports)
                     imports
                     body-forms))

              ;; (import iset ...)
              ((and (pair? d) (eq? (car d) 'import))
               (loop (cdr rest)
                     exports
                     (append (reverse (cdr d)) imports)
                     body-forms))

              ;; (begin expr ...)
              ((and (pair? d) (eq? (car d) 'begin))
               (loop (cdr rest)
                     exports
                     imports
                     (append (reverse (cdr d)) body-forms)))

              ;; (include "path" ...)
              ((and (pair? d) (eq? (car d) 'include))
               (let ((included-forms (slurp-included-files (cdr d))))
                 (loop (cdr rest)
                       exports
                       imports
                       (append (reverse included-forms) body-forms))))

              (else
               ;; Skip unrecognized or unsupported declaration silently
               (loop (cdr rest) exports imports body-forms))))))))

;;; -----------------------------------------------------------------------
;;; 2.5 File Inclusion & Path Resolution (R7RS Section 4.1.7 & 5.6.1)
;;; -----------------------------------------------------------------------

(define (include-form? form)
  (and (pair? form)
       (or (eq? (car form) 'include)
           (eq? (car form) 'include-ci))))

(define *include-path-stack* (cons '() '()))

(define (member-string? s ls)
  (cond
    ((null? ls) #f)
    ((not (pair? ls)) #f)
    ((string=? s (car ls)) #t)
    (else (member-string? s (cdr ls)))))

(define (extract-dir-path path)
  (let loop ((i (- (string-length path) 1)))
    (cond
      ((< i 0) "")
      ((char=? (string-ref path i) #\/)
       (substring path 0 (+ i 1)))
      (else (loop (- i 1))))))

(define (path-traversal? p)
  (if (and (> (string-length p) 0) (char=? (string-ref p 0) #\/))
      #t
      (let loop ((i 0))
        (if (>= (+ i 3) (string-length p))
            #f
            (if (and (char=? (string-ref p i) #\.)
                     (char=? (string-ref p (+ i 1)) #\.)
                     (char=? (string-ref p (+ i 2)) #\/))
                #t
                (loop (+ i 1)))))))

(define (find-included-file path)
  (let ((p (open-input-file path)))
    (if p
        (begin (close-input-port p) path)
        (let* ((prefixed (string-append "ulisp/" path))
               (p2 (open-input-file prefixed)))
          (if p2
              (begin (close-input-port p2) prefixed)
              path)))))

(define (resolve-include-path path)
  (if (path-traversal? path)
      (error "include: path traversal outside allowed directory rejected" path)
      (let ((stack (car *include-path-stack*)))
        (if (and (pair? stack) (not (string=? (extract-dir-path (car stack)) "")))
            (let* ((parent-dir (extract-dir-path (car stack)))
                   (relative-path (string-append parent-dir path))
                   (p0 (open-input-file relative-path)))
              (if p0
                  (begin (close-input-port p0) relative-path)
                  (find-included-file path)))
            (find-included-file path)))))

(define (expand-includes-in-forms forms)
  (let loop ((fs forms) (acc '()))
    (if (null? fs)
        (reverse acc)
        (let ((f (car fs)))
          (cond
            ((include-form? f)
             (let ((included (slurp-included-files (cdr f))))
               (loop (append included (cdr fs)) acc)))
            ((and (source-loc? f) (include-form? (source-loc-form f)))
             (let ((included (slurp-included-files (cdr (source-loc-form f)))))
               (loop (append included (cdr fs)) acc)))
            (else
             (loop (cdr fs) (cons f acc))))))))

;;; File inclusion helper: safely read forms from given files
(define (slurp-included-files paths)
  (let loop ((ps paths) (acc '()))
    (if (null? ps)
        (reverse acc)
        (let ((forms (slurp-single-file (car ps))))
          (loop (cdr ps) (append (reverse forms) acc))))))

(define (read-datum-or-source-loc p path line)
  (let ((expr (read p)))
    (if (eof-object? expr)
        expr
        (list '%source-loc path line 1 expr))))

(define (slurp-single-file raw-path)
  (let ((path (resolve-include-path raw-path)))
    (if (member-string? path (car *include-path-stack*))
        (error "include: circular dependency detected" path)
        (let ((p (open-input-file path)))
          (if (not p)
              (error "include: failed to open source file" path)
              (begin
                (set-car! *include-path-stack* (cons path (car *include-path-stack*)))
                (let loop ((acc '()) (line 1))
                  (let ((expr (read-datum-or-source-loc p path line)))
                    (if (eof-object? expr)
                        (begin
                          (close-input-port p)
                          (set-car! *include-path-stack* (cdr (car *include-path-stack*)))
                          (expand-includes-in-forms (reverse acc)))
                        (loop (cons expr acc) (+ line 1)))))))))))

;;; -----------------------------------------------------------------------
;;; 3. Import-Set Resolution & Name Mapping
;;; -----------------------------------------------------------------------

;;; Given an import-set and the library registry alist:
;;; Returns (cons <library-name> <symbol-mapping>)
;;; where symbol-mapping is ((<exported-name> . <local-bound-name>) ...)
(define (resolve-import-set iset lib-registry)
  (cond
    ((null? iset) (cons '() '()))
    ((not (pair? iset)) (cons '() '()))

    ;; (only <import-set> <id> ...)
    ((eq? (car iset) 'only)
     (let* ((sub (resolve-import-set (cadr iset) lib-registry))
            (lib-name (car sub))
            (sub-map (cdr sub))
            (only-ids (cddr iset)))
       (cons lib-name
             (filter (lambda (entry) (memq (car entry) only-ids)) sub-map))))

    ;; (except <import-set> <id> ...)
    ((eq? (car iset) 'except)
     (let* ((sub (resolve-import-set (cadr iset) lib-registry))
            (lib-name (car sub))
            (sub-map (cdr sub))
            (except-ids (cddr iset)))
       (cons lib-name
             (filter (lambda (entry) (not (memq (car entry) except-ids))) sub-map))))

    ;; (prefix <import-set> <prefix-id>)
    ((eq? (car iset) 'prefix)
     (let* ((sub (resolve-import-set (cadr iset) lib-registry))
            (lib-name (car sub))
            (sub-map (cdr sub))
            (pfx-sym (caddr iset))
            (pfx-str (symbol->string pfx-sym)))
       (cons lib-name
             (map (lambda (entry)
                    (let* ((exp-name (car entry))
                           (loc-name (cdr entry))
                           (new-loc (string->symbol (string-append pfx-str (symbol->string loc-name)))))
                      (cons exp-name new-loc)))
                  sub-map))))

    ;; (rename <import-set> (<orig> <new>) ...)
    ((eq? (car iset) 'rename)
     (let* ((sub (resolve-import-set (cadr iset) lib-registry))
            (lib-name (car sub))
            (sub-map (cdr sub))
            (renames (cddr iset)))
       (cons lib-name
             (map (lambda (entry)
                    (let* ((exp-name (car entry))
                           (loc-name (cdr entry))
                           (rn (assoc loc-name renames)))
                      (if rn
                          (cons exp-name (cadr rn))
                          entry)))
                  sub-map))))

    ;; Library name: (ident ...)
    (else
     (let ((lib-name iset))
       (if (builtin-library-name? lib-name)
           (cons lib-name '())
           (let ((entry (assoc lib-name lib-registry)))
             (if entry
                 (let* ((rec (cdr entry))
                        (exports (lib-rec-exports rec))
                        (mapping (map (lambda (e) (cons (cdr e) (cdr e))) exports)))
                   (cons lib-name mapping))
                 ;; Library not found in current compilation unit
                 (cons lib-name '()))))))))

;;; -----------------------------------------------------------------------
;;; 4. Library Alpha-Renaming & Static Flattening
;;; -----------------------------------------------------------------------

;;; Rename symbols in an expression based on a substitution alist: ((orig . new) ...)
(define (alpha-rename-expr expr subst)
  (cond
    ((null? expr) '())
    ((symbol? expr)
     (let ((entry (assq expr subst)))
       (if entry (cdr entry) expr)))
    ((not (pair? expr))
     expr)
    ((eq? (car expr) 'quote)
     expr)
    ((eq? (car expr) 'define-syntax)
     ;; Do not rename the syntax-rules keyword/pattern structure, only the defined macro name
     (if (and (pair? (cdr expr)) (symbol? (cadr expr)))
         (let* ((orig-name (cadr expr))
                (entry (assq orig-name subst))
                (new-name (if entry (cdr entry) orig-name)))
           (cons 'define-syntax (cons new-name (cddr expr))))
         expr))
    ((eq? (car expr) 'define-record-type)
     ;; (define-record-type <name> (<ctor> <ctor-args> ...) <pred> (<f> <getter> [<setter>]) ...)
     (let* ((type-name (cadr expr))
            (ctor-spec (caddr expr))
            (ctor-name (if (pair? ctor-spec) (car ctor-spec) ctor-spec))
            (ctor-args (if (pair? ctor-spec) (cdr ctor-spec) '()))
            (new-ctor-name (let ((e (assq ctor-name subst))) (if e (cdr e) ctor-name)))
            (pred-name (cadddr expr))
            (new-pred-name (let ((e (assq pred-name subst))) (if e (cdr e) pred-name)))
            (field-specs (cddddr expr))
            (new-field-specs
             (map (lambda (spec)
                    (let* ((fname (car spec))
                           (getter (cadr spec))
                           (new-getter (let ((e (assq getter subst))) (if e (cdr e) getter)))
                           (has-setter? (pair? (cddr spec))))
                      (if has-setter?
                          (let* ((setter (caddr spec))
                                 (new-setter (let ((e (assq setter subst))) (if e (cdr e) setter))))
                            (list fname new-getter new-setter))
                          (list fname new-getter))))
                  field-specs)))
       (cons 'define-record-type
             (cons type-name
                   (cons (cons new-ctor-name ctor-args)
                         (cons new-pred-name new-field-specs))))))
    ((eq? (car expr) 'define-values)
     (let* ((formals (cadr expr))
            (body-expr (caddr expr))
            (new-formals (alpha-rename-expr formals subst))
            (new-body (alpha-rename-expr body-expr subst)))
       (list 'define-values new-formals new-body)))
    (else
     (cons (alpha-rename-expr (car expr) subst)
           (alpha-rename-expr (cdr expr) subst)))))

;;; Extract all defined variable/macro names from a body of definitions
(define (extract-defined-names-in-body body-forms)
  (let loop ((rest body-forms) (acc '()))
    (if (null? rest)
        (reverse acc)
        (let ((form (car rest)))
          (cond
            ((and (pair? form) (eq? (car form) 'define) (pair? (cdr form)))
             (let ((def-target (cadr form)))
               (if (pair? def-target)
                   (loop (cdr rest) (cons (car def-target) acc))
                   (loop (cdr rest) (cons def-target acc)))))
            ((and (pair? form) (eq? (car form) 'define-values) (pair? (cdr form)))
             (let ((formals (cadr form)))
               (let formal-loop ((fs formals) (f-acc acc))
                 (cond
                   ((null? fs) (loop (cdr rest) f-acc))
                   ((pair? fs) (formal-loop (cdr fs) (cons (car fs) f-acc)))
                   ((symbol? fs) (loop (cdr rest) (cons fs f-acc)))
                   (else (loop (cdr rest) f-acc))))))
            ((and (pair? form) (eq? (car form) 'define-syntax) (pair? (cdr form)))
             (loop (cdr rest) (cons (cadr form) acc)))
            ((and (pair? form) (eq? (car form) 'define-record-type) (pair? (cdr form)))
             (let* ((ctor-spec (caddr form))
                    (ctor-name (if (pair? ctor-spec) (car ctor-spec) ctor-spec))
                    (pred-name (cadddr form))
                    (field-specs (cddddr form))
                    (acc1 (cons pred-name (cons ctor-name acc))))
               (let field-loop ((specs field-specs) (acc2 acc1))
                 (if (null? specs)
                     (loop (cdr rest) acc2)
                     (let* ((spec (car specs))
                            (getter (cadr spec))
                            (has-setter? (pair? (cddr spec)))
                            (acc3 (cons getter acc2))
                            (acc4 (if has-setter? (cons (caddr spec) acc3) acc3)))
                       (field-loop (cdr specs) acc4))))))
            (else
             (loop (cdr rest) acc)))))))

;;; Flatten a library definition into a sequence of namespaced top-level forms
;;; Returns (values internal-defs export-aliases)
;;; where export-aliases is ((<exported-public-name> . <namespaced-internal-name>) ...)
(define (instantiate-library lib-rec)
  (let* ((lib-name (lib-rec-name lib-rec))
         (prefix-str (library-name->prefix-str lib-name))
         (exports (lib-rec-exports lib-rec)) ; list of (internal-orig . exported-public)
         (body (lib-rec-body lib-rec))
         (defined-names (extract-defined-names-in-body body)))

    ;; Build substitution mapping for ALL defined names:
    ;; orig-name -> <prefix-str>_orig-name
    (let* ((subst
            (map (lambda (name)
                   (cons name (string->symbol (string-append prefix-str (symbol->string name)))))
                 defined-names))
           ;; Transform the body forms with the substitution mapping
           (renamed-body
            (map (lambda (f) (alpha-rename-expr f subst)) body))
           ;; Build export alias mapping: (exported-public . namespaced-internal-name)
           (export-aliases
            (map (lambda (e)
                   (let* ((internal-orig (car e))
                          (exported-public (cdr e))
                          (entry (assq internal-orig subst))
                          (namespaced-name (if entry (cdr entry) internal-orig)))
                     (cons exported-public namespaced-name)))
                 exports)))
      (cons renamed-body export-aliases))))

;;; -----------------------------------------------------------------------
;;; 5. Main Desugaring Entrypoint: desugar-libraries-and-imports
;;; -----------------------------------------------------------------------

;;; Traverses raw top-level forms:
;;; 1. Collects all (define-library ...) declarations into a registry
;;; 2. Instantiates imported libraries on demand, deduplicating them
;;; 3. Emits namespaced definitions and local binding aliases
;;; Returns a flat list of Scheme forms ready for macro expansion (Pass 00b).
(define (desugar-libraries-and-imports forms)
  ;; Pre-Step: Expand all top-level (include ...) forms recursively
  (let ((all-forms (expand-includes-in-forms forms)))
    ;; Step 1: Extract all library definitions into an alist: ((name . lib-rec) ...)
    (let loop-collect ((rest all-forms) (registry '()) (non-lib-forms '()))
      (if (not (null? rest))
          (let ((f (car rest)))
            (if (define-library-form? (strip-source-loc f))
                (let* ((actual-f (strip-source-loc f))
                       (rec (parse-define-library-form actual-f))
                       (name (lib-rec-name rec)))
                  (loop-collect (cdr rest) (cons (cons name rec) registry) non-lib-forms))
                (loop-collect (cdr rest) registry (cons f non-lib-forms))))

        ;; Step 2: Expand all imports and emit flat forms
        (let ((clean-forms (reverse non-lib-forms)))
          (let loop-expand ((fs clean-forms)
                            (instantiated-libs '())
                            (lib-aliases '())
                            (out-forms '()))
            (if (null? fs)
                (reverse out-forms)
                (let ((f (car fs)))
                  (if (import-form? f)
                      ;; Process (import iset ...)
                      (let loop-isets ((isets (cdr f))
                                       (cur-inst instantiated-libs)
                                       (cur-aliases lib-aliases)
                                       (acc-forms out-forms))
                        (if (null? isets)
                            (loop-expand (cdr fs) cur-inst cur-aliases acc-forms)
                            (let* ((iset (car isets))
                                   (res (resolve-import-set iset registry))
                                   (lib-name (car res))
                                   (sym-map (cdr res)))
                              (if (or (null? lib-name) (builtin-library-name? lib-name))
                                  (loop-isets (cdr isets) cur-inst cur-aliases acc-forms)
                                  (let* ((already-inst (assoc lib-name cur-aliases))
                                         (inst-info
                                          (if already-inst
                                              (cons (car already-inst) (cdr already-inst))
                                              (let ((lib-entry (assoc lib-name registry)))
                                                (if lib-entry
                                                    (let* ((rec (cdr lib-entry))
                                                           (inst-res (instantiate-library rec))
                                                           (lib-defs (car inst-res))
                                                           (aliases (cdr inst-res)))
                                                      (cons lib-defs aliases))
                                                    (cons '() '())))))
                                         (new-defs (if already-inst '() (car inst-info)))
                                         (export-aliases (if already-inst (cdr already-inst) (cdr inst-info)))
                                         (updated-aliases (if already-inst
                                                              cur-aliases
                                                              (cons (cons lib-name export-aliases) cur-aliases)))
                                         (updated-inst (if (memq lib-name cur-inst)
                                                           cur-inst
                                                           (cons lib-name cur-inst)))
                                         (alias-bindings
                                          (map (lambda (entry)
                                                 (let* ((exp-name (car entry))
                                                        (loc-name (cdr entry))
                                                        (ea (assq exp-name export-aliases)))
                                                   (if ea
                                                       (list 'define loc-name (cdr ea))
                                                       #f)))
                                               sym-map))
                                         (valid-bindings (filter (lambda (b) (pair? b)) alias-bindings)))
                                    (loop-isets (cdr isets)
                                                updated-inst
                                                updated-aliases
                                                (append (reverse valid-bindings)
                                                        (append (reverse new-defs) acc-forms))))))))
                      ;; Normal non-import form
                      (loop-expand (cdr fs)
                                   instantiated-libs
                                   lib-aliases
                                   (cons f out-forms)))))))))))
