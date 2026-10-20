;;; =======================================================================
;;; ULisp Compiler: Nanopass Framework Metadata & Reflection Engine
;;; Conforms to DSN-33 Architecture Specification & Keep & Dybvig (2013)
;;; =======================================================================

;;; Global language repository
(define *nanopass-languages* '())

(define (nanopass-clear-languages!)
  (set! *nanopass-languages* '()))

;;; Language Record Constructor
;;; name: symbol
;;; nongenerative-id: symbol or #f
;;; entry: symbol
;;; terminals: list of (pred-sym (meta-vars ...))
;;; nonterminals: list of (nt-sym (meta-vars ...) (productions ...))
;;; keywords: list of symbols (production heads)
;;; removed-prods: list of symbols (removed production heads)
(define (nanopass-make-language name nongenerative-id entry terminals nonterminals keywords removed-prods)
  (list 'nanopass-language name nongenerative-id entry terminals nonterminals keywords removed-prods))

(define (nanopass-language? obj)
  (and (pair? obj) (eq? (car obj) 'nanopass-language)))

(define (nanopass-lang-name l) (cadr l))
(define (nanopass-lang-nongenerative-id l) (caddr l))
(define (nanopass-lang-entry l) (cadddr l))
(define (nanopass-lang-terminals l) (car (cddddr l)))
(define (nanopass-lang-nonterminals l) (cadr (cddddr l)))
(define (nanopass-lang-keywords l) (caddr (cddddr l)))
(define (nanopass-lang-removed-prods l) (cadddr (cddddr l)))

;;; Registration & Lookup
(define (nanopass-register-language! lang)
  (let ((name (nanopass-lang-name lang)))
    (set! *nanopass-languages*
          (cons (cons name lang)
                (let loop ((rest *nanopass-languages*))
                  (cond ((null? rest) '())
                        ((eq? (caar rest) name) (cdr rest))
                        (else (cons (car rest) (loop (cdr rest))))))))
    name))

(define (nanopass-lookup-language name)
  (let ((entry (assq name *nanopass-languages*)))
    (if entry
        (cdr entry)
        (error "nanopass-lookup-language: unknown language" name))))

;;; Meta-variable Prefix Matcher
;;; Given a pattern variable name (e.g. 'e1, 'body, 'test_2, 'c) and a list of meta-variable prefixes,
;;; determines if the symbol begins with any of the declared prefixes.
(define (nanopass-meta-var-matches? sym prefixes)
  (let ((s (symbol->string sym)))
    (let loop ((prefs prefixes))
      (if (null? prefs)
          #f
          (let* ((p (symbol->string (car prefs)))
                 (p-len (string-length p))
                 (s-len (string-length s)))
            (if (and (>= s-len p-len)
                     (string=? (substring s 0 p-len) p))
                ;; Suffix check: after prefix, only digits, underscores, or asterisks are allowed
                (let suffix-check ((i p-len))
                  (if (>= i s-len)
                      #t
                      (let ((ch (string-ref s i)))
                        (if (or (char-numeric? ch) (char=? ch #\_) (char=? ch #\*))
                            (suffix-check (+ i 1))
                            (loop (cdr prefs))))))
                (loop (cdr prefs))))))))

;;; Identify nonterminal or terminal for a pattern variable
;;; Returns (terminal pred) or (nonterminal nt-sym) or #f
(define (nanopass-classify-meta-var var lang)
  (let ((terminals (nanopass-lang-terminals lang))
        (nonterminals (nanopass-lang-nonterminals lang)))
    (let check-terms ((ts terminals))
      (if (not (null? ts))
          (let ((term (car ts)))
            (if (nanopass-meta-var-matches? var (cadr term))
                (list 'terminal (car term))
                (check-terms (cdr ts))))
          (let check-nts ((nts nonterminals))
            (if (not (null? nts))
                (let ((nt (car nts)))
                  (if (nanopass-meta-var-matches? var (cadr nt))
                      (list 'nonterminal (car nt))
                      (check-nts (cdr nts))))
                #f))))))

;;; Production Normalization and Matching Equality
(define (nanopass-canonicalize-production prod)
  (cond
    ((and (pair? prod) (or (eq? (car prod) '+) (eq? (car prod) '-)))
     (cdr prod))
    (else prod)))

(define (nanopass-production-equal? p1 p2)
  (equal? (nanopass-canonicalize-production p1)
          (nanopass-canonicalize-production p2)))

;;; Terminal Derivation via `extends`
(define (nanopass-derive-terminals parent-terms delta-clauses)
  (let ((term-table (map (lambda (t) (cons (car t) (cadr t))) parent-terms)))
    (for-each
     (lambda (item)
       (cond
         ((and (pair? item) (eq? (car item) '+))
          (for-each
           (lambda (sub)
             (let* ((pred (car sub))
                    (vars (cadr sub))
                    (existing (assq pred term-table)))
               (if existing
                   (set-cdr! existing (append (cdr existing) vars))
                   (set! term-table (cons (cons pred vars) term-table)))))
           (cdr item)))
         ((and (pair? item) (eq? (car item) '-))
          (for-each
           (lambda (sub)
             (let* ((pred (if (pair? sub) (car sub) sub)))
               (set! term-table
                     (let remove-loop ((ts term-table))
                       (cond ((null? ts) '())
                             ((eq? (caar ts) pred) (cdr ts))
                             (else (cons (car ts) (remove-loop (cdr ts)))))))))
           (cdr item)))
         ((and (pair? item) (symbol? (car item)))
          (let* ((pred (car item))
                 (vars (cadr item))
                 (existing (assq pred term-table)))
            (if existing
                (set-cdr! existing vars)
                (set! term-table (cons (cons pred vars) term-table)))))))
     delta-clauses)
    (map (lambda (e) (list (car e) (cdr e))) (reverse term-table))))

;;; Language Derivation via `extends`
;;; Computes child language nonterminals and tracks removed production heads
(define (nanopass-derive-nonterminals-and-removed parent-nts delta-clauses)
  (let ((nt-table (map (lambda (nt)
                         (cons (car nt) (cons (cadr nt) (caddr nt))))
                       parent-nts))
        (removed-heads '()))
    (for-each
     (lambda (clause)
       (let* ((nt-name (car clause))
              (meta-vars (cadr clause))
              (body-clauses (cddr clause))
              (existing (assq nt-name nt-table)))
         (if existing
             (let ((current-prods (cddr existing))
                   (current-vars (cadr existing)))
               (let ((new-vars (append current-vars
                                       (let filter-vars ((v meta-vars))
                                         (cond ((null? v) '())
                                               ((memq (car v) current-vars) (filter-vars (cdr v)))
                                               (else (cons (car v) (filter-vars (cdr v)))))))))
                 (let loop ((rest body-clauses) (prods current-prods))
                   (if (null? rest)
                       (set-cdr! existing (cons new-vars prods))
                       (let ((item (car rest)))
                         (cond
                           ((and (pair? item) (eq? (car item) '+))
                            (loop (cdr rest) (append prods (cdr item))))
                           ((and (pair? item) (eq? (car item) '-))
                            (let ((to-remove (cdr item)))
                              (for-each
                               (lambda (rm)
                                 (let ((c (nanopass-canonicalize-production rm)))
                                   (if (and (pair? c) (symbol? (car c)))
                                       (set! removed-heads (cons (car c) removed-heads)))))
                               to-remove)
                              (loop (cdr rest)
                                    (let remove-loop ((ps prods))
                                      (cond ((null? ps) '())
                                            ((let has-match? ((rm to-remove))
                                               (and (pair? rm)
                                                    (or (nanopass-production-equal? (car ps) (car rm))
                                                        (has-match? (cdr rm)))))
                                             (remove-loop (cdr ps)))
                                            (else (cons (car ps) (remove-loop (cdr ps)))))))))
                           (else
                            (loop (cdr rest) (append prods (list item))))))))))
             (let ((prods (let loop ((rest body-clauses) (acc '()))
                            (if (null? rest)
                                acc
                                (let ((item (car rest)))
                                  (cond ((and (pair? item) (eq? (car item) '+))
                                         (loop (cdr rest) (append acc (cdr item))))
                                        ((and (pair? item) (eq? (car item) '-))
                                         (loop (cdr rest) acc))
                                        (else
                                         (loop (cdr rest) (append acc (list item))))))))))
               (set! nt-table (cons (cons nt-name (cons meta-vars prods)) nt-table))))))
     delta-clauses)
    (list (map (lambda (entry)
                 (list (car entry) (cadr entry) (cddr entry)))
               (reverse nt-table))
          removed-heads)))

(define (nanopass-derive-nonterminals parent-nts delta-clauses)
  (car (nanopass-derive-nonterminals-and-removed parent-nts delta-clauses)))

;;; Extract keyword heads from nonterminals
(define (nanopass-extract-keywords-from-nts nts terminals)
  (let loop ((rest nts) (acc '()))
    (if (null? rest)
        acc
        (let* ((prods (caddr (car rest)))
               (kw-in-prods
                (let p-loop ((ps prods) (k-acc '()))
                  (if (null? ps)
                      k-acc
                      (let ((p (car ps)))
                        (if (and (pair? p) (symbol? (car p)))
                            (let ((head (car p)))
                              ;; Exclude if head matches any terminal or nonterminal meta-var
                              (let ((is-meta?
                                     (or (let t-chk ((ts terminals))
                                           (and (pair? ts)
                                                (or (nanopass-meta-var-matches? head (cadr (car ts)))
                                                    (t-chk (cdr ts)))))
                                         (let nt-chk ((ns nts))
                                           (and (pair? ns)
                                                (or (nanopass-meta-var-matches? head (cadr (car ns)))
                                                    (nt-chk (cdr ns))))))))
                                (if (or is-meta? (memq head k-acc))
                                    (p-loop (cdr ps) k-acc)
                                    (p-loop (cdr ps) (cons head k-acc)))))
                            (p-loop (cdr ps) k-acc)))))))
          (loop (cdr rest) (append kw-in-prods acc))))))

;;; Language Specification Builder
(define (nanopass-parse-language-spec name clauses)
  (let loop ((rest clauses)
             (parent #f)
             (entry-sym #f)
             (nongenerative-id #f)
             (terminal-clauses '())
             (nonterminal-clauses '()))
    (if (null? rest)
        (if parent
            (let* ((parent-lang (nanopass-lookup-language parent))
                   (parent-entry (nanopass-lang-entry parent-lang))
                   (parent-id (nanopass-lang-nongenerative-id parent-lang))
                   (parent-terms (nanopass-lang-terminals parent-lang))
                   (parent-nts (nanopass-lang-nonterminals parent-lang))
                   (parent-kws (nanopass-lang-keywords parent-lang))
                   (parent-removed (nanopass-lang-removed-prods parent-lang))
                   (final-entry (if entry-sym entry-sym parent-entry))
                   (final-id (if nongenerative-id nongenerative-id (string->symbol (string-append (symbol->string parent) "->" (symbol->string name)))))
                   (final-terms (if (null? terminal-clauses) parent-terms (nanopass-derive-terminals parent-terms terminal-clauses)))
                   (nts-and-rm (nanopass-derive-nonterminals-and-removed parent-nts nonterminal-clauses))
                   (final-nts (car nts-and-rm))
                   (new-removed (cadr nts-and-rm))
                   (final-removed (append new-removed parent-removed))
                   (raw-kws (nanopass-extract-keywords-from-nts final-nts final-terms))
                   (final-kws (append raw-kws (let filter-kws ((ks parent-kws))
                                                (cond ((null? ks) '())
                                                      ((memq (car ks) raw-kws) (filter-kws (cdr ks)))
                                                      (else (cons (car ks) (filter-kws (cdr ks)))))))))
              (nanopass-make-language name final-id final-entry final-terms final-nts final-kws final-removed))
            (let* ((parsed-terms (if (null? terminal-clauses) '() terminal-clauses))
                   (final-entry (if entry-sym
                                    entry-sym
                                    (if (not (null? nonterminal-clauses))
                                        (caar nonterminal-clauses)
                                        'Expr)))
                   (parsed-nts (map (lambda (nt)
                                      (list (car nt) (cadr nt) (cddr nt)))
                                    nonterminal-clauses))
                   (kws (nanopass-extract-keywords-from-nts parsed-nts parsed-terms)))
              (nanopass-make-language name nongenerative-id final-entry parsed-terms parsed-nts kws '())))
        (let ((c (car rest)))
          (cond
            ((and (pair? c) (eq? (car c) 'extends))
             (loop (cdr rest) (cadr c) entry-sym nongenerative-id terminal-clauses nonterminal-clauses))
            ((and (pair? c) (eq? (car c) 'entry))
             (loop (cdr rest) parent (cadr c) nongenerative-id terminal-clauses nonterminal-clauses))
            ((and (pair? c) (eq? (car c) 'nongenerative-id))
             (loop (cdr rest) parent entry-sym (cadr c) terminal-clauses nonterminal-clauses))
            ((and (pair? c) (eq? (car c) 'terminals))
             (loop (cdr rest) parent entry-sym nongenerative-id (append terminal-clauses (cdr c)) nonterminal-clauses))
            ((and (pair? c) (symbol? (car c)))
             (loop (cdr rest) parent entry-sym nongenerative-id terminal-clauses (append nonterminal-clauses (list c))))
            (else
             (loop (cdr rest) parent entry-sym nongenerative-id terminal-clauses nonterminal-clauses)))))))

;;; Terminal Predicate Checker
(define (nanopass-terminal-matches? pred val)
  (case pred
    ((symbol symbol?) (symbol? val))
    ((number number?) (number? val))
    ((integer integer?) (and (number? val) (integer? val)))
    ((fixnum fixnum?) (number? val))
    ((string string?) (string? val))
    ((boolean boolean?) (boolean? val))
    ((char char?) (char? val))
    ((pair pair?) (pair? val))
    ((null null?) (null? val))
    ((constant constant?)
     (or (number? val) (string? val) (boolean? val) (char? val)))
    (else #t)))

;;; AST Validation & Parser Engine
(define (nanopass-ast-valid? lang-name expr . opt-nt)
  (let* ((lang (nanopass-lookup-language lang-name))
         (nt-name (if (pair? opt-nt) (car opt-nt) (nanopass-lang-entry lang))))
    (nanopass-check-valid-node expr nt-name lang)))

(define (nanopass-check-valid-node expr nt-name lang)
  ;; Check if expr is a list starting with an explicitly removed production head
  (if (and (pair? expr) (symbol? (car expr)) (memq (car expr) (nanopass-lang-removed-prods lang)))
      #f
      ;; 1. Check terminals
      (let ((terminals (nanopass-lang-terminals lang)))
        (let check-t ((ts terminals))
          (if (not (null? ts))
              (let* ((term (car ts))
                     (pred (car term)))
                (if (nanopass-terminal-matches? pred expr)
                    #t
                    (check-t (cdr ts))))
              ;; 2. Check nonterminal productions
              (let* ((nts (nanopass-lang-nonterminals lang))
                     (nt-entry (assq nt-name nts)))
                (if (not nt-entry)
                    #f
                    (let ((prods (caddr nt-entry)))
                      (let check-p ((ps prods))
                        (if (null? ps)
                            #f
                            (let ((p (car ps)))
                              (if (nanopass-production-matches? p expr lang nt-name)
                                  #t
                                  (check-p (cdr ps))))))))))))))

(define (nanopass-production-matches? prod expr lang curr-nt)
  (cond
    ((symbol? prod)
     (let ((cls (nanopass-classify-meta-var prod lang)))
       (cond
         ((not cls) (eq? prod expr))
         ((eq? (car cls) 'terminal)
          (nanopass-terminal-matches? (cadr cls) expr))
         ((eq? (car cls) 'nonterminal)
          (nanopass-check-valid-node expr (cadr cls) lang))
         (else #f))))
    ((pair? prod)
     (if (not (pair? expr))
         #f
         (let ((head (car prod)))
           (cond
             ((eq? head 'quote)
              (and (eq? (car expr) 'quote)
                   (pair? (cdr expr))
                   (null? (cddr expr))))
             ((symbol? head)
              (let ((cls (nanopass-classify-meta-var head lang)))
                (if cls
                    ;; Function call / application: (e0 e1 ...)
                    ;; Only valid if (car expr) is NOT a reserved keyword of the language family
                    (if (memq (car expr) (nanopass-lang-keywords lang))
                        #f
                        (and (nanopass-check-valid-node (car expr) curr-nt lang)
                             (let check-args ((args (cdr expr)))
                               (or (null? args)
                                   (and (pair? args)
                                        (nanopass-check-valid-node (car args) curr-nt lang)
                                        (check-args (cdr args)))))))
                    ;; Keyword-headed production: (if ...), (cond ...), (let ...), etc.
                    (if (eq? head (car expr))
                        (nanopass-match-subforms (cdr prod) (cdr expr) lang curr-nt)
                        #f))))
             (else #f)))))
    (else (equal? prod expr))))

(define (nanopass-match-subforms prod-rest expr-rest lang curr-nt)
  (cond
    ((and (null? prod-rest) (null? expr-rest)) #t)
    ((or (null? prod-rest) (null? expr-rest))
     (and (pair? prod-rest)
          (or (eq? (car prod-rest) '...)
              (and (pair? (cdr prod-rest)) (eq? (cadr prod-rest) '...)))
          (null? expr-rest)))
    ((eq? (car prod-rest) '...) #t)
    ((and (pair? (cdr prod-rest)) (eq? (cadr prod-rest) '...))
     (let ((item-pat (car prod-rest)))
       (let loop ((es expr-rest))
         (if (null? es)
             #t
             (and (pair? es)
                  (nanopass-match-subpattern item-pat (car es) lang curr-nt)
                  (loop (cdr es)))))))
    ((pair? (car prod-rest))
     (and (pair? expr-rest)
          (nanopass-match-subpattern (car prod-rest) (car expr-rest) lang curr-nt)
          (nanopass-match-subforms (cdr prod-rest) (cdr expr-rest) lang curr-nt)))
    (else
     (and (pair? expr-rest)
          (let* ((p (car prod-rest))
                 (cls (nanopass-classify-meta-var p lang)))
            (if cls
                (nanopass-check-valid-node (car expr-rest) (if (eq? (car cls) 'nonterminal) (cadr cls) curr-nt) lang)
                (equal? p (car expr-rest))))
          (nanopass-match-subforms (cdr prod-rest) (cdr expr-rest) lang curr-nt)))))

(define (nanopass-match-subpattern pat val lang curr-nt)
  (cond
    ((symbol? pat)
     (let ((cls (nanopass-classify-meta-var pat lang)))
       (if cls
           (nanopass-check-valid-node val (if (eq? (car cls) 'nonterminal) (cadr cls) curr-nt) lang)
           (equal? pat val))))
    ((pair? pat)
     (and (pair? val)
          (nanopass-match-subforms pat val lang curr-nt)))
    (else (equal? pat val))))

;;; Parser & Unparser Procs
(define (nanopass-parse lang-name expr . opt-nt)
  (let* ((nt-name (if (pair? opt-nt) (car opt-nt) (nanopass-lang-entry (nanopass-lookup-language lang-name))))
         (is-valid? (nanopass-ast-valid? lang-name expr nt-name)))
    (if is-valid?
        expr
        (error "nanopass-parse: invalid expression for language" lang-name expr))))

(define (nanopass-unparse lang-name ir . opt-nt)
  ir)

;;; S-Expression Reflection API
(define (language->s-expression lang-name)
  (let ((lang (nanopass-lookup-language lang-name)))
    (list 'language
          (nanopass-lang-name lang)
          (list 'entry (nanopass-lang-entry lang))
          (list 'nongenerative-id (nanopass-lang-nongenerative-id lang))
          (cons 'terminals (nanopass-lang-terminals lang))
          (cons 'nonterminals (nanopass-lang-nonterminals lang))
          (cons 'keywords (nanopass-lang-keywords lang))
          (cons 'removed (nanopass-lang-removed-prods lang)))))

;;; Language Invariant Diff Analysis API
(define (language-diff lang1-name lang2-name)
  (let* ((l1 (nanopass-lookup-language lang1-name))
         (l2 (nanopass-lookup-language lang2-name))
         (nts1 (nanopass-lang-nonterminals l1))
         (nts2 (nanopass-lang-nonterminals l2))
         (all-prods (lambda (nts)
                      (let loop ((rest nts) (acc '()))
                        (if (null? rest)
                            acc
                            (loop (cdr rest) (append acc (caddr (car rest))))))))
         (p1 (all-prods nts1))
         (p2 (all-prods nts2)))
    (list (list 'removed
                (let loop ((ps p1) (acc '()))
                  (cond ((null? ps) (reverse acc))
                        ((let exists? ((cur p2))
                           (and (pair? cur)
                                (or (nanopass-production-equal? (car ps) (car cur))
                                    (exists? (cdr cur)))))
                         (loop (cdr ps) acc))
                        (else (loop (cdr ps) (cons (car ps) acc))))))
          (list 'added
                (let loop ((ps p2) (acc '()))
                  (cond ((null? ps) (reverse acc))
                        ((let exists? ((cur p1))
                           (and (pair? cur)
                                (or (nanopass-production-equal? (car ps) (car cur))
                                    (exists? (cdr cur)))))
                         (loop (cdr ps) acc))
                        (else (loop (cdr ps) (cons (car ps) acc)))))))))

;;; Pattern Matching and Variable Binding for `define-pass`
;;; A pattern variable can be:
;;;   (unquote var)        -> binds var = val
;;;   (unquote (var))      -> catamorphism: binds var = (recurse-fn val)
;;;   _                    -> wildcard, binds nothing
;;; Returns (cons #t env-alist) on match, #f on mismatch
(define (nanopass-match-pattern-inner pat expr recurse-fn)
  (cond
    ((eq? pat '_)
     (cons #t '()))
    ((symbol? pat)
     (let ((s (symbol->string pat)))
       (cond
         ;; Comma prefix variable `,var`
         ((and (> (string-length s) 1) (char=? (string-ref s 0) #\,))
          (let ((vname (string->symbol (substring s 1 (string-length s)))))
            (cons #t (list (cons vname expr)))))
         (else
          (if (eq? pat expr)
              (cons #t '())
              #f)))))
    ((pair? pat)
     (cond
       ;; (unquote ...)
       ((eq? (car pat) 'unquote)
        (let ((sub (cadr pat)))
          (cond
            ((pair? sub)
             ;; Catamorphism: (unquote (var)) -> recurse!
             (let ((vname (car sub)))
               (cons #t (list (cons vname (recurse-fn expr))))))
            ((symbol? sub)
             (cons #t (list (cons sub expr))))
            (else #f))))
       (else
        (if (not (pair? expr))
            #f
            (let ((car-match (nanopass-match-pattern-inner (car pat) (car expr) recurse-fn)))
              (if (not car-match)
                  #f
                  (let ((cdr-match (nanopass-match-pattern-inner (cdr pat) (cdr expr) recurse-fn)))
                    (if (not cdr-match)
                        #f
                        (cons #t (append (cdr car-match) (cdr cdr-match)))))))))))
    (else
     (if (equal? pat expr)
         (cons #t '())
         #f))))

;;; Extract bound variable names from pattern in declaration order
(define (nanopass-extract-pattern-vars pat)
  (cond
    ((eq? pat '_) '())
    ((symbol? pat)
     (let ((s (symbol->string pat)))
       (if (and (> (string-length s) 1) (char=? (string-ref s 0) #\,))
           (list (string->symbol (substring s 1 (string-length s))))
           '())))
    ((pair? pat)
     (if (eq? (car pat) 'unquote)
         (let ((sub (cadr pat)))
           (cond
             ((pair? sub) (list (car sub)))
             ((symbol? sub) (list sub))
             (else '())))
         (append (nanopass-extract-pattern-vars (car pat))
                 (nanopass-extract-pattern-vars (cdr pat)))))
    (else '())))

;;; Match clause helper: returns list of values for expected vars, or #f
(define (nanopass-match-clause pat expr expected-vars recurse-fn)
  (let ((res (nanopass-match-pattern-inner pat expr recurse-fn)))
    (if (not res)
        #f
        (let ((env (cdr res)))
          (let loop ((vars expected-vars) (vals '()))
            (if (null? vars)
                (reverse vals)
                (let ((entry (assq (car vars) env)))
                  (if entry
                      (loop (cdr vars) (cons (cdr entry) vals))
                      (loop (cdr vars) (cons #f vals))))))))))

;;; Try matching clause and evaluate handler proc
(define (nanopass-try-clause pat vars expr recurse-fn proc)
  (let ((vals (nanopass-match-clause pat expr vars recurse-fn)))
    (if (not vals)
        #f
        (apply proc vals))))

;;; Catamorphism Automatic Traversal Code Synthesizer
;;; Automatically traverses non-matching AST nodes recursively.
(define (nanopass-catamorphism-step lang-in lang-out nt-name ir recurse-fn)
  (cond
    ((not (pair? ir))
     ir)
    (else
     (let ((op (car ir)))
       (case op
         ((quote)
          ir)
         ((if)
          (if (null? (cdddr ir))
              (list 'if (recurse-fn (cadr ir)) (recurse-fn (caddr ir)))
              (list 'if (recurse-fn (cadr ir)) (recurse-fn (caddr ir)) (recurse-fn (cadddr ir)))))
         ((begin)
          (cons 'begin (map recurse-fn (cdr ir))))
         ((lambda)
          (cons 'lambda (cons (cadr ir) (map recurse-fn (cddr ir)))))
         ((let)
          (if (symbol? (cadr ir))
              (list 'let (cadr ir)
                    (map (lambda (b) (list (car b) (recurse-fn (cadr b)))) (caddr ir))
                    (if (null? (cddddr ir))
                        (recurse-fn (cadddr ir))
                        (cons 'begin (map recurse-fn (cdddr ir)))))
              (list 'let
                    (map (lambda (b) (list (car b) (recurse-fn (cadr b)))) (cadr ir))
                    (if (null? (cdddr ir))
                        (recurse-fn (caddr ir))
                        (cons 'begin (map recurse-fn (cddr ir)))))))
         ((letrec)
          (list 'letrec
                (map (lambda (b) (list (car b) (recurse-fn (cadr b)))) (cadr ir))
                (if (null? (cdddr ir))
                    (recurse-fn (caddr ir))
                    (cons 'begin (map recurse-fn (cddr ir))))))
         ((set!)
          (list 'set! (cadr ir) (recurse-fn (caddr ir))))
         ((%program)
          (list '%program
                (map (lambda (d)
                       (if (and (pair? d) (eq? (car d) 'define))
                           (list 'define (cadr d) (recurse-fn (caddr d)))
                           (recurse-fn d)))
                     (cadr ir))
                (recurse-fn (caddr ir))))
         (else
          ;; General function application
          (cons (recurse-fn op) (map recurse-fn (cdr ir)))))))))
