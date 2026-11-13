;;; =======================================================================
;;; ULisp Compiler: Nanopass Framework Metadata & Reflection Engine
;;; Conforms to DSN-33 Architecture Specification & Keep & Dybvig (2013)
;;; =======================================================================

;;; Global language repository
(define *nanopass-languages* (cons '() '()))

(define (nanopass-clear-languages!)
  (set-car! *nanopass-languages* '()))

(define (nanopass-get-languages)
  (car *nanopass-languages*))

;;; Language Record Constructor
;;; name: symbol
;;; nongenerative-id: symbol or #f
;;; entry: symbol
;;; terminals: list of (pred-sym (meta-vars ...))
;;; nonterminals: list of (nt-sym (meta-vars ...) (productions ...))
;;; keywords: list of symbols (production heads)
;;; removed-prods: list of symbols (removed production heads)
(define (nanopass-make-language name nongenerative-id entry terminals nonterminals keywords removed-prods parent)
  (list 'nanopass-language name nongenerative-id entry terminals nonterminals keywords removed-prods parent))

(define (nanopass-lang-parent l)
  (if (> (length l) 8) (list-ref l 8) #f))

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
    (set-car! *nanopass-languages*
              (cons (cons name lang)
                    (let loop ((rest (car *nanopass-languages*)))
                      (cond ((null? rest) '())
                            ((eq? (caar rest) name) (cdr rest))
                            (else (cons (car rest) (loop (cdr rest))))))))
    name))

(define (nanopass-lookup-language name)
  (let ((entry (assq name (car *nanopass-languages*))))
    (if entry
        (cdr entry)
        (error "nanopass-lookup-language: unknown language" name))))

;;; Meta-variable Prefix Matcher
;;; Given a pattern variable name (e.g. 'e1, 'body, 'test_2, 'c) and a list of meta-variable prefixes,
;;; determines if the symbol begins with any of the declared prefixes.
(define (nanopass-meta-suffix-check? s i s-len)
  (if (>= i s-len)
      #t
      (let ((ch (string-ref s i)))
        (if (or (and (char>=? ch #\0) (char<=? ch #\9)) (char=? ch #\_) (char=? ch #\*))
            (nanopass-meta-suffix-check? s (+ i 1) s-len)
            #f))))

(define (nanopass-meta-var-matches-str? s prefs s-len)
  (if (null? prefs)
      #f
      (let* ((p (symbol->raw-name (car prefs)))
             (p-len (string-length p)))
        (if (and (>= s-len p-len)
                 (string-starts-with? s p)
                 (nanopass-meta-suffix-check? s p-len s-len))
            #t
            (nanopass-meta-var-matches-str? s (cdr prefs) s-len)))))

(define (nanopass-meta-var-matches? sym prefixes)
  (let* ((s (symbol->raw-name sym))
         (s-len (string-length s)))
    (nanopass-meta-var-matches-str? s prefixes s-len)))

;;; Identify nonterminal or terminal for a pattern variable
;;; Returns (terminal pred) or (nonterminal nt-sym) or #f
(define (nanopass-check-terms-str var-str s-len ts)
  (if (null? ts)
      #f
      (let ((term (car ts)))
        (if (nanopass-meta-var-matches-str? var-str (cadr term) s-len)
            (list 'terminal (car term))
            (nanopass-check-terms-str var-str s-len (cdr ts))))))

(define (nanopass-check-nts-str var-str s-len nts)
  (if (null? nts)
      #f
      (let ((nt (car nts)))
        (if (nanopass-meta-var-matches-str? var-str (cadr nt) s-len)
            (list 'nonterminal (car nt))
            (nanopass-check-nts-str var-str s-len (cdr nts))))))

(define (nanopass-classify-meta-var-uncached var-str lang)
  (let ((s-len (string-length var-str))
        (terminals (nanopass-lang-terminals lang))
        (nonterminals (nanopass-lang-nonterminals lang)))
    (let ((term-res (nanopass-check-terms-str var-str s-len terminals)))
      (if term-res
          term-res
          (nanopass-check-nts-str var-str s-len nonterminals)))))

(define *classify-meta-var-cache* (make-vector 1024 '()))

(define (nanopass-classify-meta-var var lang)
  (if (not (symbol? var))
      #f
      (let* ((lang-name (if (nanopass-language? lang) (nanopass-lang-name lang) 'unknown))
             (var-str (symbol->raw-name var))
             (lang-str (symbol->raw-name lang-name))
             (h (modulo (+ (string-fast-hash-1024 var-str) (* (string-fast-hash-1024 lang-str) 31)) 1024))
             (bucket (vector-ref *classify-meta-var-cache* h)))
        (let loop ((entries bucket))
          (if (null? entries)
              (let* ((res (nanopass-classify-meta-var-uncached var-str lang))
                     (new-entry (cons (cons var lang-name) res)))
                (vector-set! *classify-meta-var-cache* h (cons new-entry bucket))
                res)
              (let ((e (car entries)))
                (if (and (eq? (caar e) var) (eq? (cdar e) lang-name))
                    (cdr e)
                    (loop (cdr entries)))))))))

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
  (let ((term-table-cell (cons (map (lambda (t) (cons (car t) (cadr t))) parent-terms) '())))
    (for-each
     (lambda (item)
       (cond
         ((and (pair? item) (eq? (car item) '+))
          (for-each
           (lambda (sub)
             (let* ((pred (car sub))
                    (vars (cadr sub))
                    (existing (assq pred (car term-table-cell))))
               (if existing
                   (set-cdr! existing (append (cdr existing) vars))
                   (set-car! term-table-cell (cons (cons pred vars) (car term-table-cell))))))
           (cdr item)))
         ((and (pair? item) (eq? (car item) '-))
          (for-each
           (lambda (sub)
             (let* ((pred (if (pair? sub) (car sub) sub)))
               (set-car! term-table-cell
                         (let remove-loop ((ts (car term-table-cell)))
                           (cond ((null? ts) '())
                                 ((eq? (caar ts) pred) (cdr ts))
                                 (else (cons (car ts) (remove-loop (cdr ts)))))))))
           (cdr item)))
         ((and (pair? item) (symbol? (car item)))
          (let* ((pred (car item))
                 (vars (cadr item))
                 (existing (assq pred (car term-table-cell))))
            (if existing
                (set-cdr! existing vars)
                (set-car! term-table-cell (cons (cons pred vars) (car term-table-cell))))))))
     delta-clauses)
    (map (lambda (e) (list (car e) (cdr e))) (reverse (car term-table-cell)))))

;;; Language Derivation via `extends`
;;; Computes child language nonterminals and tracks removed production heads
(define (nanopass-derive-nonterminals-and-removed parent-nts delta-clauses)
  (let ((nt-table-cell (cons (reverse
                              (map (lambda (nt)
                                     (cons (car nt) (cons (cadr nt) (caddr nt))))
                                   parent-nts))
                             '()))
        (removed-heads-cell (cons '() '())))
    (for-each
     (lambda (clause)
       (let* ((nt-name (car clause))
              (meta-vars (cadr clause))
              (body-clauses (cddr clause))
              (existing (assq nt-name (car nt-table-cell))))
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
                                       (if (not (memq (car c) (car removed-heads-cell)))
                                           (set-car! removed-heads-cell (cons (car c) (car removed-heads-cell)))))))
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
               (set-car! nt-table-cell (cons (cons nt-name (cons meta-vars prods)) (car nt-table-cell)))))))
     delta-clauses)
    (list (map (lambda (entry)
                 (list (car entry) (cadr entry) (cddr entry)))
               (reverse (car nt-table-cell)))
          (reverse (car removed-heads-cell)))))

(define (nanopass-derive-nonterminals parent-nts delta-clauses)
  (car (nanopass-derive-nonterminals-and-removed parent-nts delta-clauses)))

;;; Check whether a symbol matches any terminal or nonterminal meta-variable prefix
(define (nanopass-symbol-is-meta-var? sym nts terminals)
  (or (let t-chk ((ts terminals))
        (and (pair? ts)
             (or (nanopass-meta-var-matches? sym (cadr (car ts)))
                 (t-chk (cdr ts)))))
      (let nt-chk ((ns nts))
        (and (pair? ns)
             (or (nanopass-meta-var-matches? sym (cadr (car ns)))
                 (nt-chk (cdr ns)))))))

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
                              (if (or (nanopass-symbol-is-meta-var? head nts terminals)
                                      (memq head k-acc))
                                  (p-loop (cdr ps) k-acc)
                                  (p-loop (cdr ps) (cons head k-acc))))
                            (p-loop (cdr ps) k-acc)))))))
          (loop (cdr rest) (append kw-in-prods acc))))))

;;; Filter removed production heads: exclude active keywords in final-nts and meta-variables
(define (nanopass-filter-removed-heads candidate-heads active-kws nts terminals)
  (let loop ((hs candidate-heads) (acc '()))
    (cond
      ((null? hs) (reverse acc))
      ((or (memq (car hs) active-kws)
           (memq (car hs) acc)
           (nanopass-symbol-is-meta-var? (car hs) nts terminals))
       (loop (cdr hs) acc))
      (else
       (loop (cdr hs) (cons (car hs) acc))))))

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
                   (raw-kws (nanopass-extract-keywords-from-nts final-nts final-terms))
                   (final-removed (nanopass-filter-removed-heads
                                   (append new-removed parent-removed)
                                   raw-kws
                                   final-nts
                                   final-terms))
                   (final-kws (append raw-kws (let filter-kws ((ks parent-kws))
                                                (cond ((null? ks) '())
                                                      ((memq (car ks) raw-kws) (filter-kws (cdr ks)))
                                                      (else (cons (car ks) (filter-kws (cdr ks)))))))))
              (nanopass-make-language name final-id final-entry final-terms final-nts final-kws final-removed parent))
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
              (nanopass-make-language name nongenerative-id final-entry parsed-terms parsed-nts kws '() #f)))
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
;;; NOTE: the self-hosted compiler has no rest-argument lambdas, so the
;;; optional nonterminal is split into a separate fixed-arity entry point.
(define (nanopass-ast-valid-nt? lang-name expr nt-name)
  (nanopass-check-valid-node expr nt-name (nanopass-lookup-language lang-name)))

(define (nanopass-ast-valid? lang-name expr)
  (nanopass-ast-valid-nt? lang-name expr
                          (nanopass-lang-entry (nanopass-lookup-language lang-name))))

(define (nanopass-check-valid-node expr nt-name lang)
  ;; Check if expr is a list starting with an explicitly removed production head
  ;; (Only if it is not re-introduced as an active keyword in this language)
  (if (and (pair? expr)
           (symbol? (car expr))
           (memq (car expr) (nanopass-lang-removed-prods lang))
           (not (memq (car expr) (nanopass-lang-keywords lang))))
      #f
      ;; Check nonterminal productions
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
                          (check-p (cdr ps)))))))))))

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
                    ;; Function call / application: (e0 e1 ...) or (a0 a ...)
                    ;; Only valid if (car expr) is NOT a reserved keyword of the language family
                    (if (memq (car expr) (nanopass-lang-keywords lang))
                        #f
                        (and (if (eq? (car cls) 'terminal)
                                 (nanopass-terminal-matches? (cadr cls) (car expr))
                                 (nanopass-check-valid-node (car expr) (cadr cls) lang))
                             (nanopass-match-subforms (cdr prod) (cdr expr) lang curr-nt)))
                    ;; Keyword-headed production: (if ...), (cond ...), (let ...), (%program ...), etc.
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
                (if (eq? (car cls) 'terminal)
                    (nanopass-terminal-matches? (cadr cls) (car expr-rest))
                    (nanopass-check-valid-node (car expr-rest) (cadr cls) lang))
                (equal? p (car expr-rest))))
          (nanopass-match-subforms (cdr prod-rest) (cdr expr-rest) lang curr-nt)))))

(define (nanopass-match-subpattern pat val lang curr-nt)
  (cond
    ((symbol? pat)
     (let ((cls (nanopass-classify-meta-var pat lang)))
       (if cls
           (if (eq? (car cls) 'terminal)
               (nanopass-terminal-matches? (cadr cls) val)
               (nanopass-check-valid-node val (cadr cls) lang))
           (equal? pat val))))
    ((pair? pat)
     (if (null? val)
         (or (eq? (car pat) '...)
             (and (pair? (cdr pat)) (eq? (cadr pat) '...)))
         (and (pair? val)
              (nanopass-match-subforms pat val lang curr-nt))))
    (else (equal? pat val))))

;;; Parser & Unparser Procs
(define (nanopass-parse-nt lang-name expr nt-name)
  (if (nanopass-ast-valid-nt? lang-name expr nt-name)
      expr
      (error "nanopass-parse: invalid expression for language" lang-name expr)))

(define (nanopass-parse lang-name expr)
  (nanopass-parse-nt lang-name expr
                     (nanopass-lang-entry (nanopass-lookup-language lang-name))))

(define (nanopass-unparse lang-name ir)
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

(define (nanopass-get-all-languages)
  (let loop ((cur (car *nanopass-languages*)) (acc '()))
    (if (null? cur)
        acc
        (loop (cdr cur) (cons (car (car cur)) acc)))))

(define (language-parent-chain lang-name)
  (let loop ((cur lang-name) (acc '()))
    (if (not cur)
        acc
        (let* ((lang (nanopass-lookup-language cur))
               (p (nanopass-lang-parent lang)))
          (loop p (cons cur acc))))))

(define (language-declaration lang-name)
  (let ((lang (nanopass-lookup-language lang-name)))
    (list 'language-declaration
          (nanopass-lang-name lang)
          (list 'parent (nanopass-lang-parent lang))
          (list 'entry (nanopass-lang-entry lang))
          (list 'nongenerative-id (nanopass-lang-nongenerative-id lang))
          (cons 'terminals (nanopass-lang-terminals lang))
          (cons 'nonterminals (nanopass-lang-nonterminals lang))
          (cons 'keywords (nanopass-lang-keywords lang))
          (cons 'removed (nanopass-lang-removed-prods lang)))))

;;; AST Structural Diff Engine
(define (nanopass-ast-diff-list l1 l2)
  (if (eq? l1 l2)
      l1
      (let loop ((c1 l1) (c2 l2) (acc '()))
        (if (or (null? c1) (null? c2))
            (reverse acc)
            (let ((o (car c1))
                  (n (car c2)))
              (loop (cdr c1) (cdr c2)
                    (cons (if (or (eq? o n) (equal? o n)) o (nanopass-ast-diff o n)) acc)))))))

(define (nanopass-ast-diff old-ir new-ir)
  (cond
    ((or (eq? old-ir new-ir) (equal? old-ir new-ir))
     #f)
    ((and (pair? old-ir) (pair? new-ir))
     (let ((head-old (car old-ir))
           (head-new (car new-ir)))
       (if (and (symbol? head-old) (eq? head-old head-new) (= (length old-ir) (length new-ir)))
           (cons head-old (nanopass-ast-diff-list (cdr old-ir) (cdr new-ir)))
           (list 'diff:modified old-ir new-ir))))
    (else
     (list 'diff:modified old-ir new-ir))))

;;; AST Diff Tracer Configuration and Display
(define *nanopass-trace* (cons #f '()))
(define (nanopass-trace-enabled?) (car *nanopass-trace*))
(define (enable-nanopass-trace!) (set-car! *nanopass-trace* #t))
(define (disable-nanopass-trace!) (set-car! *nanopass-trace* #f))

;;; Picopass Provenance Tracking & Firing History (DSN-33-01 T6.2 / Issue #769)
(define *picopass-provenance-enabled* (cons #f '()))
(define (picopass-provenance-enabled?) (car *picopass-provenance-enabled*))
(define (enable-picopass-provenance!) (set-car! *picopass-provenance-enabled* #t))
(define (disable-picopass-provenance!) (set-car! *picopass-provenance-enabled* #f))

;; Firing counts alist: ((rule-name . count) ...)
(define *picopass-firing-counts* (cons '() '()))

;; Firing log entries: list of (rule-name old-ir new-ir)
(define *picopass-firing-log* (cons '() '()))
(define *picopass-max-log-entries* 500)

(define (reset-picopass-provenance!)
  (set-car! *picopass-firing-counts* '())
  (set-car! *picopass-firing-log* '()))

(define (record-picopass-firing! rule-name old-ir new-ir)
  (if (car *picopass-provenance-enabled*)
      (begin
        ;; 1. Update firing counter
        (let* ((counts (car *picopass-firing-counts*))
               (entry (assq rule-name counts)))
          (if entry
              (set-cdr! entry (+ (cdr entry) 1))
              (set-car! *picopass-firing-counts* (cons (cons rule-name 1) counts))))
        ;; 2. Bounded log append
        (let ((log (car *picopass-firing-log*)))
          (if (< (length log) *picopass-max-log-entries*)
              (set-car! *picopass-firing-log*
                        (cons (list rule-name
                                    (nanopass-truncate-expr old-ir 6 10)
                                    (nanopass-truncate-expr new-ir 6 10))
                              log))
              #f)))))

(define (get-picopass-firing-counts)
  (car *picopass-firing-counts*))

(define (get-picopass-firing-log)
  (reverse (car *picopass-firing-log*)))

;;; Pipeline runner guard to prevent duplicate AST diff emission when a `define-pass`
;;; is invoked inside `run-single-pass` / `run-pass-pipeline` (DSN-33-01 T1.3).
(define *nanopass-in-pipeline-runner* (cons #f '()))
(define (nanopass-in-pipeline-runner?) (car *nanopass-in-pipeline-runner*))
(define (set-nanopass-in-pipeline-runner! flag) (set-car! *nanopass-in-pipeline-runner* flag))

;;; Counter tracking total `nanopass-display-ast-diff` invocations for deterministic testing.
(define *nanopass-ast-diff-display-count* (cons 0 '()))
(define (nanopass-ast-diff-display-count) (car *nanopass-ast-diff-display-count*))
(define (reset-nanopass-ast-diff-display-count!) (set-car! *nanopass-ast-diff-display-count* 0))

(define (nanopass-truncate-expr expr depth max-len)
  (cond
    ((<= depth 0) '...)
    ((not (pair? expr)) expr)
    (else
     (let loop ((cur expr) (len 0) (acc '()))
       (cond
         ((null? cur) (reverse acc))
         ((not (pair? cur)) (append (reverse acc) cur))
         ((>= len max-len) (append (reverse acc) (list '...)))
         (else
          (loop (cdr cur) (+ len 1) (cons (nanopass-truncate-expr (car cur) (- depth 1) max-len) acc))))))))

(define (nanopass-display-esc)
  (write-char (integer->char 27)))

(define (nanopass-display-ast-diff pass-name old-ir new-ir)
  (set-car! *nanopass-ast-diff-display-count* (+ (car *nanopass-ast-diff-display-count*) 1))
  (let ((max-depth 8)
        (max-len 16))
    (nanopass-display-esc)
    (display "[36m--- [PASS: ")
    (display pass-name)
    (display "] -----------------------------------------------------")
    (nanopass-display-esc)
    (display "[0m\n")
    (if (or (eq? old-ir new-ir) (equal? old-ir new-ir))
        (display "  (AST unchanged)\n")
        (begin
          (nanopass-display-esc)
          (display "[31m- ")
          (write (nanopass-truncate-expr old-ir max-depth max-len))
          (nanopass-display-esc)
          (display "[0m\n")
          (nanopass-display-esc)
          (display "[32m+ ")
          (write (nanopass-truncate-expr new-ir max-depth max-len))
          (nanopass-display-esc)
          (display "[0m\n")))
    (let ((counts (get-picopass-firing-counts)))
      (if (pair? counts)
          (begin
            (nanopass-display-esc)
            (display "[33m  [Picopass Firings]:\n")
            (nanopass-display-esc)
            (display "[0m")
            (for-each (lambda (entry)
                        (display "    * ")
                        (display (car entry))
                        (display ": ")
                        (display (cdr entry))
                        (display " hit(s)\n"))
                      counts))))
    (nanopass-display-esc)
    (display "[36m----------------------------------------------------------------------")
    (nanopass-display-esc)
    (display "[0m\n")))

;;; Verifier Hooks Configuration & Error Reporting
(define *nanopass-verifier-enabled* (cons #f '()))
(define (nanopass-verifier-enabled?) (car *nanopass-verifier-enabled*))
(define (enable-nanopass-verifier!) (set-car! *nanopass-verifier-enabled* #t))
(define (disable-nanopass-verifier!) (set-car! *nanopass-verifier-enabled* #f))

;;; Verification Cache to eliminate redundant full-tree traversals (DSN-33-01 T4.3)
(define *nanopass-last-verified-ast* (cons #f '()))
(define *nanopass-last-verified-lang* (cons #f '()))

(define (reset-nanopass-verification-cache!)
  (set-car! *nanopass-last-verified-ast* #f)
  (set-car! *nanopass-last-verified-lang* #f))

(define (nanopass-ast-already-verified? lang-name expr)
  (and (eq? expr (car *nanopass-last-verified-ast*))
       (eq? lang-name (car *nanopass-last-verified-lang*))))

(define (nanopass-record-verified-ast! lang-name expr)
  (set-car! *nanopass-last-verified-ast* expr)
  (set-car! *nanopass-last-verified-lang* lang-name))

(define (nanopass-verification-failure pass-name lang-name expr phase)
  (display "\n*** [NANOPASS VERIFIER ERROR] Pass: ")
  (display pass-name)
  (display " (")
  (display phase)
  (display ") failed language constraint for ")
  (display lang-name)
  (display "\n    Violating AST: ")
  (write expr)
  (newline)
  (raise (list 'nanopass-verifier-error pass-name lang-name)))

(define (nanopass-verify-ast pass-name lang-name val phase)
  (if (or (eq? lang-name '*) (not (symbol? lang-name)))
      #t
      (if (nanopass-ast-already-verified? lang-name val)
          #t  ; AST was already verified against lang-name, skip traversal in O(1)!
          (let ((lang-entry (assq lang-name (car *nanopass-languages*))))
            (if (not lang-entry)
                #t
                (if (not (nanopass-ast-valid? lang-name val))
                    (nanopass-verification-failure pass-name lang-name val phase)
                    (begin
                      (nanopass-record-verified-ast! lang-name val)
                      #t)))))))


(define (nanopass-proper-list? x)
  (let loop ((cur x))
    (cond
      ((null? cur) #t)
      ((pair? cur) (loop (cdr cur)))
      (else #f))))

;;; Helper sequence operations for ellipsis matching
(define (nanopass-take lst n)
  (let loop ((l lst) (i n) (acc '()))
    (if (or (null? l) (not (pair? l)) (<= i 0))
        (reverse acc)
        (loop (cdr l) (- i 1) (cons (car l) acc)))))

(define (nanopass-drop lst n)
  (let loop ((l lst) (i n))
    (if (or (null? l) (not (pair? l)) (<= i 0))
        l
        (loop (cdr l) (- i 1)))))

(define (nanopass-tail-min-length rest)
  (cond
    ((null? rest) 0)
    ((pair? rest)
     (if (eq? (car rest) '...)
         0
         (+ 1 (nanopass-tail-min-length (cdr rest)))))
    (else 0)))

;;; Match a repeated pattern against an expression list via ellipsis (...)
;;; Returns (cons #t env-alist) where each variable in item-pat maps to a list of values, or #f
(define (nanopass-match-ellipsis item-pat expr-list recurse-fn)
  (let ((vars (nanopass-extract-pattern-vars item-pat)))
    (if (not (nanopass-proper-list? expr-list))
        #f
        (let loop ((es expr-list) (acc '()))
          (if (null? es)
              (cons #t
                    (map (lambda (v)
                           (cons v (map (lambda (env)
                                          (let ((entry (assq v env)))
                                            (if entry (cdr entry) #f)))
                                        (reverse acc))))
                         vars))
              (let ((m (nanopass-match-pattern-inner item-pat (car es) recurse-fn)))
                (if (not m)
                    #f
                    (loop (cdr es) (cons (cdr m) acc)))))))))


;;; Helper to test if a symbol occurs anywhere in an expression tree
(define (nanopass-expr-contains-symbol? expr sym)
  (cond
    ((eq? expr sym) #t)
    ((pair? expr)
     (or (nanopass-expr-contains-symbol? (car expr) sym)
         (nanopass-expr-contains-symbol? (cdr expr) sym)))
    (else #f)))

(define (nanopass-map2 f l1 l2)
  (let loop ((c1 l1) (c2 l2) (acc '()))
    (if (or (null? c1) (null? c2))
        (reverse acc)
        (loop (cdr c1) (cdr c2) (cons (f (car c1) (car c2)) acc)))))

(define (nanopass-map3 f l1 l2 l3)
  (let loop ((c1 l1) (c2 l2) (c3 l3) (acc '()))
    (if (or (null? c1) (null? c2) (null? c3))
        (reverse acc)
        (loop (cdr c1) (cdr c2) (cdr c3) (cons (f (car c1) (car c2) (car c3)) acc)))))

(define (nanopass-build-map-expr proc-expr arg-vars)
  (cond
    ((= (length arg-vars) 1)
     (list 'map proc-expr (car arg-vars)))
    ((= (length arg-vars) 2)
     (list 'nanopass-map2 proc-expr (car arg-vars) (cadr arg-vars)))
    ((= (length arg-vars) 3)
     (list 'nanopass-map3 proc-expr (car arg-vars) (cadr arg-vars) (caddr arg-vars)))
    (else
     (cons 'map (cons proc-expr arg-vars)))))

;;; Expand quasiquote templates with ellipsis (...) splicing
(define (nanopass-expand-qq tmpl vars depth)
  (cond
    ((not (pair? tmpl)) tmpl)
    ((eq? (car tmpl) 'quasiquote)
     (list 'quasiquote (nanopass-expand-qq (cadr tmpl) vars (+ depth 1))))
    ((eq? (car tmpl) 'unquote)
     (if (= depth 1)
         (list 'unquote (nanopass-expand-template (cadr tmpl) vars))
         (list 'unquote (nanopass-expand-qq (cadr tmpl) vars (- depth 1)))))
    ((eq? (car tmpl) 'unquote-splicing)
     (if (= depth 1)
         (list 'unquote-splicing (nanopass-expand-template (cadr tmpl) vars))
         (list 'unquote-splicing (nanopass-expand-qq (cadr tmpl) vars (- depth 1)))))
    ((and (= depth 1) (pair? (cdr tmpl)) (eq? (cadr tmpl) '...))
     ;; Splicing element at current list level: (item ... . rest)
     (let* ((item (car tmpl))
            (rest (cddr tmpl))
            (expanded-rest (nanopass-expand-qq rest vars depth))
            (matched-vars (filter (lambda (v) (nanopass-expr-contains-symbol? item v)) vars)))
       (cond
         ((and (pair? item) (eq? (car item) 'unquote))
          (cons (list 'unquote-splicing (nanopass-expand-template (cadr item) vars))
                expanded-rest))
         ((not (null? matched-vars))
          (let ((proc (list 'lambda matched-vars
                            (list 'quasiquote (nanopass-expand-qq item vars depth)))))
            (cons (list 'unquote-splicing (nanopass-build-map-expr proc matched-vars))
                  expanded-rest)))
         (else
          (cons item (cons '... expanded-rest))))))
    (else
     (let ((head (car tmpl))
           (tail (cdr tmpl)))
       ;; Special check: if head is a list of the form (sub ...)
       (if (and (= depth 1)
                (pair? head)
                (pair? (cdr head))
                (eq? (cadr head) '...)
                (null? (cddr head)))
           (let* ((sub (car head))
                  (matched-vars (filter (lambda (v) (nanopass-expr-contains-symbol? sub v)) vars)))
             (if (not (null? matched-vars))
                 (let ((proc (list 'lambda matched-vars
                                   (list 'quasiquote (nanopass-expand-qq sub vars depth)))))
                   (cons (list 'unquote (nanopass-build-map-expr proc matched-vars))
                         (nanopass-expand-qq tail vars depth)))
                 (cons (nanopass-expand-qq head vars depth)
                       (nanopass-expand-qq tail vars depth))))
           (cons (nanopass-expand-qq head vars depth)
                 (nanopass-expand-qq tail vars depth)))))))

;;; Output template expander: processes quasiquote and ellipsis expressions in rule bodies
(define (nanopass-expand-template expr vars)
  (cond
    ((not (pair? expr)) expr)
    ((eq? (car expr) 'quasiquote)
     (list 'quasiquote (nanopass-expand-qq (cadr expr) vars 1)))
    ((eq? (car expr) 'in-context)
     (let ((args (cdr expr)))
       (if (= (length args) 2)
           (list (car args) (nanopass-expand-template (cadr args) vars))
           (list 'nanopass-parse-nt (list 'quote (car args)) (nanopass-expand-template (caddr args) vars) (list 'quote (cadr args))))))
    (else
     (cons (nanopass-expand-template (car expr) vars)
           (nanopass-expand-template (cdr expr) vars)))))

;;; Pattern Matching and Variable Binding for `define-pass`
;;; A pattern variable can be:
;;;   (unquote var)        -> binds var = val
;;;   (unquote (var))      -> catamorphism: binds var = (recurse-fn val)
;;;   _                    -> wildcard, binds nothing
;;;   (item ... . rest)    -> ellipsis repetition: binds variables in item to lists of values
;;; Returns (cons #t env-alist) on match, #f on mismatch
(define (nanopass-match-pattern-inner pat expr recurse-fn)
  (cond
    ((eq? pat '_)
     (cons #t '()))
    ((symbol? pat)
     (if (eq? pat expr)
         (cons #t '())
         #f))
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
       ;; Ellipsis: (item ... . rest)
       ((and (pair? (cdr pat)) (eq? (cadr pat) '...))
        (let* ((item (car pat))
               (rest (cddr pat)))
          (if (null? rest)
              (nanopass-match-ellipsis item expr recurse-fn)
              (let* ((k (nanopass-tail-min-length rest)))
                (if (or (not (nanopass-proper-list? expr)) (< (length expr) k))
                    #f
                    (let* ((split-idx (- (length expr) k))
                           (prefix (nanopass-take expr split-idx))
                           (suffix (nanopass-drop expr split-idx))
                           (m-pre (nanopass-match-ellipsis item prefix recurse-fn)))
                      (if (not m-pre)
                          #f
                          (let ((m-suf (nanopass-match-pattern-inner rest suffix recurse-fn)))
                            (if (not m-suf)
                                #f
                                (cons #t (append (cdr m-pre) (cdr m-suf))))))))))))
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
    ((eq? pat '...) '())
    ((symbol? pat) '())
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
  (if (and (pair? pat)
           (symbol? (car pat))
           (not (eq? (car pat) 'unquote))
           (not (eq? (car pat) '_))
           (not (and (pair? (cdr pat)) (eq? (cadr pat) '...)))
           (or (not (pair? expr))
               (not (eq? (car expr) (car pat)))))
      #f
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
                          (loop (cdr vars) (cons #f vals)))))))))))

;;; Manual `apply` for clause handlers (arity 0-8)
(define (nanopass-apply-list proc vals)
  (let ((n (length vals)))
    (cond
      ((= n 0) (proc))
      ((= n 1) (proc (car vals)))
      ((= n 2) (proc (car vals) (cadr vals)))
      ((= n 3) (proc (car vals) (cadr vals) (caddr vals)))
      ((= n 4) (proc (car vals) (cadr vals) (caddr vals) (cadddr vals)))
      ((= n 5) (proc (car vals) (cadr vals) (caddr vals) (cadddr vals) (car (cddddr vals))))
      ((= n 6) (proc (car vals) (cadr vals) (caddr vals) (cadddr vals) (car (cddddr vals))
                     (cadr (cddddr vals))))
      ((= n 7) (proc (car vals) (cadr vals) (caddr vals) (cadddr vals) (car (cddddr vals))
                     (cadr (cddddr vals)) (caddr (cddddr vals))))
      ((= n 8) (proc (car vals) (cadr vals) (caddr vals) (cadddr vals) (car (cddddr vals))
                     (cadr (cddddr vals)) (caddr (cddddr vals)) (cadddr (cddddr vals))))
      (else (error "nanopass-apply-list: too many pattern variables" n)))))

;;; Try matching clause and evaluate handler proc
(define (nanopass-try-clause pat vars expr recurse-fn proc)
  (let ((vals (nanopass-match-clause pat expr vars recurse-fn)))
    (if (not vals)
        #f
        (nanopass-apply-list proc vals))))

;;; =======================================================================
;;; First-Class Rule Descriptor & Registry Engine (DSN-33-01 T2.1)
;;; =======================================================================

;;; Global rule repository: (cons (list (cons key desc) ...) '())
(define *nanopass-rules* (cons '() '()))

(define (nanopass-clear-rules!)
  (set-car! *nanopass-rules* '()))

(define (nanopass-get-all-rules)
  (let loop ((entries (car *nanopass-rules*)) (seen '()) (acc '()))
    (if (null? entries)
        (reverse acc)
        (let* ((desc (cdar entries))
               (name (rule-name desc)))
          (if (memq name seen)
              (loop (cdr entries) seen acc)
              (loop (cdr entries) (cons name seen) (cons desc acc)))))))

;;; Rule Descriptor Constructor
;;; (list 'rule-descriptor name kind nt-name head-tags reads writes eliminates clauses proc)
(define (nanopass-make-rule-descriptor name kind nt-name head-tags reads writes eliminates clauses proc)
  (list 'rule-descriptor name kind nt-name head-tags reads writes eliminates clauses proc))

(define (rule-descriptor? obj)
  (and (pair? obj) (eq? (car obj) 'rule-descriptor)))

(define (rule-name r) (cadr r))
(define (rule-kind r) (caddr r))
(define (rule-nt-name r) (cadddr r))
(define (rule-head-tags r) (car (cddddr r)))
(define (rule-reads r) (cadr (cddddr r)))
(define (rule-writes r) (caddr (cddddr r)))
(define (rule-eliminates r) (cadddr (cddddr r)))
(define (rule-clauses r) (car (cddddr (cddddr r))))
(define (rule-proc r) (cadr (cddddr (cddddr r))))

(define *mandatory-picopasses* (cons '() '()))
(define (mandatory-picopasses) (car *mandatory-picopasses*))
(define (register-mandatory-picopass! name)
  (if (not (memq name (car *mandatory-picopasses*)))
      (set-car! *mandatory-picopasses* (cons name (car *mandatory-picopasses*)))))
(define (picopass-mandatory? name)
  (and (memq name (car *mandatory-picopasses*)) #t))
(define (rule-mandatory? r)
  (let ((name (if (rule-descriptor? r) (rule-name r) r)))
    (picopass-mandatory? name)))

(define (nanopass-rule-set-proc! r proc)
  (set-car! (cdr (cddddr (cddddr r))) proc))

;;; Registration & Lookup
(define (nanopass-register-rule! desc)
  (if (not (rule-descriptor? desc))
      (error "nanopass-register-rule!: invalid rule descriptor" desc)
      (let ((name (rule-name desc))
            (proc (rule-proc desc)))
        (let* ((curr (car *nanopass-rules*))
               (filtered (let loop ((rem curr))
                           (cond ((null? rem) '())
                                 ((and (symbol? (caar rem)) (eq? (caar rem) name))
                                  (loop (cdr rem)))
                                 ((and proc (eq? (caar rem) proc))
                                  (loop (cdr rem)))
                                 (else (cons (car rem) (loop (cdr rem)))))))
               (with-name (cons (cons name desc) filtered))
               (with-proc (if proc (cons (cons proc desc) with-name) with-name)))
          (set-car! *nanopass-rules* with-proc)
          name))))

(define (nanopass-lookup-rule-opt name-or-proc)
  (cond
    ((rule-descriptor? name-or-proc)
     name-or-proc)
    ((symbol? name-or-proc)
     (let ((entry (assq name-or-proc (car *nanopass-rules*))))
       (if entry (cdr entry) #f)))
    (else
     (let ((entry (assq name-or-proc (car *nanopass-rules*))))
       (if entry (cdr entry) #f)))))

(define (nanopass-lookup-rule name-or-proc)
  (let ((desc (nanopass-lookup-rule-opt name-or-proc)))
    (if desc
        desc
        (error "nanopass-lookup-rule: unknown rule" name-or-proc))))

(define (rule-descriptor name-or-proc)
  (nanopass-lookup-rule name-or-proc))

;;; -----------------------------------------------------------------------
;;; Picopass Rule Disabling API (DSN-33-01 T6.2 / Issue #769)
;;; -----------------------------------------------------------------------

(define *disabled-picopasses* (cons '() '()))
(define (disabled-picopasses) (car *disabled-picopasses*))

(define (picopass-enabled? rule-name)
  (if (null? (car *disabled-picopasses*))
      #t
      (not (memq rule-name (car *disabled-picopasses*)))))

(define (disable-picopass! rule-name)
  (if (picopass-mandatory? rule-name)
      #f
      (begin
        (if (not (memq rule-name (car *disabled-picopasses*)))
            (set-car! *disabled-picopasses* (cons rule-name (car *disabled-picopasses*))))
        #t)))

(define (enable-picopass! rule-name)
  (set-car! *disabled-picopasses*
            (let loop ((rs (car *disabled-picopasses*)))
              (cond
                ((null? rs) '())
                ((eq? (car rs) rule-name) (loop (cdr rs)))
                (else (cons (car rs) (loop (cdr rs))))))))

(define (reset-disabled-picopasses!)
  (set-car! *disabled-picopasses* '()))

(define (with-disabled-picopasses rules thunk)
  (let ((saved (car *disabled-picopasses*)))
    (dynamic-wind
      (lambda ()
        (for-each disable-picopass! rules))
      thunk
      (lambda ()
        (set-car! *disabled-picopasses* saved)))))

;;; Structured Assertion Failure Helper
(define (picopass-fail message ir)
  (raise (list 'picopass-assertion-failed message ir)))

;;; Static Analysis Helpers for Rule Descriptors
(define (nanopass-pattern-head-tag pat)
  (cond
    ((pair? pat)
     (cond
       ((eq? (car pat) 'unquote) '*)
       ((eq? (car pat) '_) '*)
       ((symbol? (car pat)) (car pat))
       ((pair? (car pat))
        (let ((inner (car pat)))
          (cond
            ((eq? (car inner) 'unquote) '*)
            ((symbol? (car inner)) (car inner))
            (else '*))))
       (else '*)))
    (else '*)))

(define (nanopass-extract-head-tags clauses)
  (let loop ((cs clauses) (tags '()))
    (if (null? cs)
        (let ((unique-tags (let rem ((ts (reverse tags)) (acc '()))
                             (cond ((null? ts) (reverse acc))
                                   ((memq (car ts) acc) (rem (cdr ts) acc))
                                   (else (rem (cdr ts) (cons (car ts) acc)))))))
          (if (memq '* unique-tags)
              '*
              unique-tags))
        (let* ((c (car cs))
               (pat (if (pair? c) (car c) c))
               (ht (nanopass-pattern-head-tag pat)))
          (loop (cdr cs) (cons ht tags))))))

(define (nanopass-collect-pattern-literals pat)
  (cond
    ((eq? pat '...) '())
    ((eq? pat '_) '())
    ((symbol? pat) (list pat))
    ((pair? pat)
     (if (eq? (car pat) 'unquote)
         '()
         (append (nanopass-collect-pattern-literals (car pat))
                 (nanopass-collect-pattern-literals (cdr pat)))))
    (else '())))

(define (nanopass-extract-pattern-reads clauses)
  (let loop ((cs clauses) (acc '()))
    (if (null? cs)
        (let rem ((ts (reverse acc)) (res '()))
          (cond ((null? ts) (reverse res))
                ((memq (car ts) res) (rem (cdr ts) res))
                (else (rem (cdr ts) (cons (car ts) res)))))
        (let* ((c (car cs))
               (pat (if (pair? c) (car c) c))
               (lits (nanopass-collect-pattern-literals pat)))
          (loop (cdr cs) (append (reverse lits) acc))))))

(define (nanopass-collect-template-heads expr)
  (cond
    ((not (pair? expr)) '())
    ((eq? (car expr) 'quote)
     (if (and (pair? (cdr expr)) (symbol? (cadr expr)))
         (list (cadr expr))
         '()))
    ((eq? (car expr) 'quasiquote)
     (let recur ((sub (cadr expr)))
       (cond
         ((not (pair? sub)) '())
         ((eq? (car sub) 'unquote) '())
         ((eq? (car sub) 'unquote-splicing) '())
         ((symbol? (car sub))
          (cons (car sub)
                (append (recur (car sub)) (recur (cdr sub)))))
         (else
          (append (recur (car sub)) (recur (cdr sub)))))))
    ((symbol? (car expr))
     (let* ((head (car expr))
            (rest-heads (nanopass-collect-template-heads (cdr expr))))
       (if (memq head '(if begin let letrec let* lambda void set! error))
           (cons head rest-heads)
           rest-heads)))
    (else
     (append (nanopass-collect-template-heads (car expr))
             (nanopass-collect-template-heads (cdr expr))))))

(define (nanopass-extract-template-writes clauses)
  (let loop ((cs clauses) (acc '()))
    (if (null? cs)
        (let rem ((ts (reverse acc)) (res '()))
          (cond ((null? ts) (reverse res))
                ((memq (car ts) res) (rem (cdr ts) res))
                (else (rem (cdr ts) (cons (car ts) res)))))
        (let* ((c (car cs))
               (body (cond
                       ((and (pair? c) (pair? (cdr c)) (pair? (cddr c)) (pair? (cdddr c)))
                        (cadddr c))
                       ((and (pair? c) (pair? (cdr c)))
                        (cadr c))
                       (else '())))
               (heads (nanopass-collect-template-heads body)))
          (loop (cdr cs) (append (reverse heads) acc))))))

(define (nanopass-infer-eliminates head-tags writes)
  (if (or (eq? head-tags '*) (not (list? head-tags)))
      '()
      (let loop ((tags head-tags) (acc '()))
        (cond
          ((null? tags) (reverse acc))
          ((memq (car tags) writes) (loop (cdr tags) acc))
          (else (loop (cdr tags) (cons (car tags) acc)))))))

;;; -----------------------------------------------------------------------
;;; Part 8: Picopass Strategy Combinators (DSN-33-01 T2.2)
;;; -----------------------------------------------------------------------

(define (nanopass-resolve-rule-proc r)
  (cond
    ((rule-descriptor? r)
     (rule-proc r))
    ((symbol? r)
     (let ((desc (nanopass-lookup-rule-opt r)))
       (if (and desc (rule-proc desc))
           (rule-proc desc)
           #f)))
    ((procedure? r)
     r)
    (else #f)))

(define (nanopass-resolve-rule-descriptor r)
  (cond
    ((rule-descriptor? r) r)
    ((symbol? r) (nanopass-lookup-rule-opt r))
    ((procedure? r) (nanopass-lookup-rule-opt r))
    (else #f)))

(define (nanopass-combine-sets s1 s2)
  (let ((l1 (if (list? s1) s1 '()))
        (l2 (if (list? s2) s2 '())))
    (let loop ((items l2) (acc l1))
      (cond
        ((null? items) acc)
        ((memq (car items) acc) (loop (cdr items) acc))
        (else (loop (cdr items) (append acc (list (car items)))))))))

(define (nanopass-combine-head-tags t1 t2)
  (cond
    ((or (eq? t1 '*) (eq? t2 '*)) '*)
    ((and (list? t1) (list? t2)) (nanopass-combine-sets t1 t2))
    ((list? t1) t1)
    ((list? t2) t2)
    (else '*)))

;;; 1. Sequential Composition: (picopass-seq r1 r2)  (p1 ▷ p2)
(define (picopass-seq r1 r2)
  (let ((p1 (nanopass-resolve-rule-proc r1))
        (p2 (nanopass-resolve-rule-proc r2))
        (d1 (nanopass-resolve-rule-descriptor r1))
        (d2 (nanopass-resolve-rule-descriptor r2)))
    (if (not (procedure? p1))
        (error "picopass-seq: first argument is not a valid rule or procedure" r1)
        (if (not (procedure? p2))
            (error "picopass-seq: second argument is not a valid rule or procedure" r2)
            (let* ((name (unique-symbol "picopass_seq_"))
                   (nt-name (if d1 (rule-nt-name d1) (if d2 (rule-nt-name d2) 'Expr)))
                   (head-tags (if d1 (rule-head-tags d1) '*))
                   (reads (nanopass-combine-sets (if d1 (rule-reads d1) '())
                                                (if d2 (rule-reads d2) '())))
                   (writes (if (and d2 (pair? (rule-writes d2)))
                               (rule-writes d2)
                               (if d1 (rule-writes d1) '())))
                   (eliminates (nanopass-combine-sets (if d1 (rule-eliminates d1) '())
                                                      (if d2 (rule-eliminates d2) '())))
                   (clauses (append (if d1 (rule-clauses d1) '())
                                    (if d2 (rule-clauses d2) '())))
                   (composite
                    (lambda (ir)
                      (let ((res1 (p1 ir)))
                        (if res1
                            (let ((res2 (p2 res1)))
                              (if res2 res2 res1))
                            #f))))
                   (desc (nanopass-make-rule-descriptor
                          name 'pico nt-name head-tags reads writes eliminates clauses composite)))
              (nanopass-register-rule! desc)
              composite)))))

(define (picopass-compose-list rules)
  (cond
    ((null? rules)
     (let* ((name (unique-symbol "picopass_empty_seq_"))
            (composite (lambda (ir) #f))
            (desc (nanopass-make-rule-descriptor name 'pico 'Expr '() '() '() '() '() composite)))
       (nanopass-register-rule! desc)
       composite))
    ((null? (cdr rules))
     (let ((p (nanopass-resolve-rule-proc (car rules))))
       (if p p (error "picopass-compose-list: invalid rule" (car rules)))))
    (else
     (let loop ((rem (cdr rules)) (acc (car rules)))
       (if (null? rem)
           acc
           (loop (cdr rem) (picopass-seq acc (car rem))))))))

;;; 2. Deterministic Choice: (picopass-choice r1 r2)  (p1 ⊕ p2)
(define (picopass-choice r1 r2)
  (let ((p1 (nanopass-resolve-rule-proc r1))
        (p2 (nanopass-resolve-rule-proc r2))
        (d1 (nanopass-resolve-rule-descriptor r1))
        (d2 (nanopass-resolve-rule-descriptor r2)))
    (if (not (procedure? p1))
        (error "picopass-choice: first argument is not a valid rule or procedure" r1)
        (if (not (procedure? p2))
            (error "picopass-choice: second argument is not a valid rule or procedure" r2)
            (let* ((name (unique-symbol "picopass_choice_"))
                   (nt-name (if d1 (rule-nt-name d1) (if d2 (rule-nt-name d2) 'Expr)))
                   (head-tags (nanopass-combine-head-tags (if d1 (rule-head-tags d1) '*)
                                                         (if d2 (rule-head-tags d2) '*)))
                   (reads (nanopass-combine-sets (if d1 (rule-reads d1) '())
                                                (if d2 (rule-reads d2) '())))
                   (writes (nanopass-combine-sets (if d1 (rule-writes d1) '())
                                                 (if d2 (rule-writes d2) '())))
                   (eliminates (nanopass-combine-sets (if d1 (rule-eliminates d1) '())
                                                      (if d2 (rule-eliminates d2) '())))
                   (clauses (append (if d1 (rule-clauses d1) '())
                                    (if d2 (rule-clauses d2) '())))
                   (composite
                    (lambda (ir)
                      (let ((res1 (p1 ir)))
                        (if res1
                            res1
                            (p2 ir)))))
                   (desc (nanopass-make-rule-descriptor
                          name 'pico nt-name head-tags reads writes eliminates clauses composite)))
              (nanopass-register-rule! desc)
              composite)))))

(define (picopass-choice-list rules)
  (cond
    ((null? rules)
     (let* ((name (unique-symbol "picopass_empty_choice_"))
            (composite (lambda (ir) #f))
            (desc (nanopass-make-rule-descriptor name 'pico 'Expr '() '() '() '() '() composite)))
       (nanopass-register-rule! desc)
       composite))
    ((null? (cdr rules))
     (let ((p (nanopass-resolve-rule-proc (car rules))))
       (if p p (error "picopass-choice-list: invalid rule" (car rules)))))
    (else
     (let loop ((rem (cdr rules)) (acc (car rules)))
       (if (null? rem)
           acc
           (loop (cdr rem) (picopass-choice acc (car rem))))))))

;;; 3. Local Fixpoint Iteration: (picopass-fixpoint rule) / (picopass-fixpoint-limit rule max-steps)  (p*)
(define (picopass-fixpoint-limit rule max-steps)
  (let ((p (nanopass-resolve-rule-proc rule))
        (d (nanopass-resolve-rule-descriptor rule)))
    (if (not (procedure? p))
        (error "picopass-fixpoint-limit: argument is not a valid rule or procedure" rule)
        (let* ((name (unique-symbol "picopass_fixpoint_"))
               (nt-name (if d (rule-nt-name d) 'Expr))
               (head-tags (if d (rule-head-tags d) '*))
               (reads (if d (rule-reads d) '()))
               (writes (if d (rule-writes d) '()))
               (eliminates (if d (rule-eliminates d) '()))
               (clauses (if d (rule-clauses d) '()))
               (composite
                (lambda (ir)
                  (let ((first-res (p ir)))
                    (if (or (not first-res) (equal? first-res ir))
                        #f
                        (let loop ((curr first-res) (step 1))
                          (if (>= step max-steps)
                              (picopass-fail "picopass-fixpoint: step limit exceeded (infinite rewrite loop)" ir)
                              (let ((next (p curr)))
                                (if (or (not next) (equal? next curr))
                                    curr
                                    (loop next (+ step 1))))))))))
               (desc (nanopass-make-rule-descriptor
                      name 'pico nt-name head-tags reads writes eliminates clauses composite)))
          (nanopass-register-rule! desc)
          composite))))

(define (picopass-fixpoint rule)
  (picopass-fixpoint-limit rule 64))

;;; 4. Guarded Composition: (picopass-when guard-rule pico-rule)  (guard ⇒ pico)
(define (picopass-when guard-rule pico-rule)
  (let ((gp (nanopass-resolve-rule-proc guard-rule))
        (pp (nanopass-resolve-rule-proc pico-rule))
        (gd (nanopass-resolve-rule-descriptor guard-rule))
        (pd (nanopass-resolve-rule-descriptor pico-rule)))
    (if (not (procedure? gp))
        (error "picopass-when: first argument is not a valid guard procedure" guard-rule)
        (if (not (procedure? pp))
            (error "picopass-when: second argument is not a valid rule procedure" pico-rule)
            (let* ((name (unique-symbol "picopass_when_"))
                   (nt-name (if pd (rule-nt-name pd) (if gd (rule-nt-name gd) 'Expr)))
                   (head-tags (if pd (rule-head-tags pd) '*))
                   (reads (nanopass-combine-sets (if gd (rule-reads gd) '())
                                                (if pd (rule-reads pd) '())))
                   (writes (if pd (rule-writes pd) '()))
                   (eliminates (if pd (rule-eliminates pd) '()))
                   (clauses (if pd (rule-clauses pd) '()))
                   (composite
                    (lambda (ir)
                      (let ((g-res (gp ir)))
                        (if g-res
                            (pp ir)
                            #f))))
                   (desc (nanopass-make-rule-descriptor
                          name 'pico nt-name head-tags reads writes eliminates clauses composite)))
              (nanopass-register-rule! desc)
              composite)))))

;;; Catamorphism Automatic Traversal Code Synthesizer (DSN-33-01 T1.2)
;;; Automatically traverses non-matching AST nodes recursively according to
;;; `define-language` production schemas.
;;; Supports both AST transformation (with inherited attributes) and pure analyzer passes (lang-out = '*).

;;; Optional language lookup without raising an error
(define (nanopass-lookup-language-opt name)
  (if (not (symbol? name))
      #f
      (let ((entry (assq name (car *nanopass-languages*))))
        (if entry (cdr entry) #f))))

;;; Find the matching production for `ir` in `lang` (searching `nt-name` first, then all nonterminals)
;;; Returns `(cons matched-nt prod)` or `#f`.
(define (nanopass-find-matching-production ir nt-name lang)
  (let* ((nts (nanopass-lang-nonterminals lang))
         (try-nt
          (lambda (nt-entry)
            (let ((curr-nt (car nt-entry))
                  (prods (caddr nt-entry)))
              (let loop ((ps prods))
                (cond
                  ((null? ps) #f)
                  ((nanopass-production-matches? (car ps) ir lang curr-nt)
                   (cons curr-nt (car ps)))
                  (else (loop (cdr ps))))))))
         (primary-entry (if (symbol? nt-name) (assq nt-name nts) #f))
         (primary-match (if primary-entry (try-nt primary-entry) #f)))
    (if primary-match
        primary-match
        (if primary-entry
            #f
            (let loop-nts ((rest nts))
              (if (null? rest)
                  #f
                  (let ((e (car rest)))
                    (if (and primary-entry (eq? (car e) nt-name))
                        (loop-nts (cdr rest))
                        (let ((m (try-nt e)))
                          (if m m (loop-nts (cdr rest))))))))))))

;;; Schema-driven subpattern transformer
;;; When `pat` is a nonterminal meta-variable (e.g. `d` for `Def`), if `target-nt` is `Def`
;;; and `val` is a top-level `(define ...)` definition while `curr-nt` is `Program` (so an
;;; `Expr`-only pass with an internal-define rule would otherwise turn top-level `define` into `let`),
;;; we traverse `val` directly via `Def`'s production `(define x e)` so its top-level `define`
;;; wrapper is preserved and `call-recurse` is applied to its body `e`.
;;; For all other nonterminals (`FunctionDecl`, `MainDecl`, `Inst`, `Expr`, etc.), we invoke
;;; `call-recurse` on `val` so any user-defined rules on `val` are tried first before falling
;;; back to `nanopass-catamorphism-step`!
(define (nanopass-schema-transform-subpattern pat val lang curr-nt call-recurse)
  (cond
    ((symbol? pat)
     (let ((cls (nanopass-classify-meta-var pat lang)))
       (if (and cls (eq? (car cls) 'nonterminal))
           (let ((target-nt (cadr cls)))
             (if (and (eq? target-nt 'Def)
                      (pair? val)
                      (eq? (car val) 'define))
                 (let ((sub-match (nanopass-find-matching-production val 'Def lang)))
                   (if (and sub-match (pair? (cdr sub-match)))
                       (nanopass-schema-transform-node (cdr sub-match) val lang 'Def call-recurse)
                       (call-recurse val)))
                 (call-recurse val)))
           val)))
    ((pair? pat)
     (if (null? val)
         '()
         (if (pair? val)
             (nanopass-schema-transform-subforms pat val lang curr-nt call-recurse)
             val)))
    (else val)))

;;; Smart Reconstruction Helpers (DSN-33-01 T1.3)
;;; Preserves pointer identity (`eq?`) on unchanged AST cons cells and lists
;;; during catamorphism traversal to avoid redundant heap allocations.
(define (nanopass-cons-sharing orig-pair new-car new-cdr)
  (if (and (pair? orig-pair)
           (eq? new-car (car orig-pair))
           (eq? new-cdr (cdr orig-pair)))
      orig-pair
      (cons new-car new-cdr)))

(define (nanopass-map-sharing fn lst)
  (if (not (pair? lst))
      lst
      (let* ((old-head (car lst))
             (old-tail (cdr lst))
             (new-head (fn old-head))
             (new-tail (nanopass-map-sharing fn old-tail)))
        (if (and (eq? new-head old-head)
                 (eq? new-tail old-tail))
            lst
            (cons new-head new-tail)))))

(define (nanopass-transform-each lst item-pat lang curr-nt call-recurse)
  (if (not (pair? lst))
      lst
      (let* ((old-head (car lst))
             (old-tail (cdr lst))
             (new-head (nanopass-schema-transform-subpattern item-pat old-head lang curr-nt call-recurse))
             (new-tail (nanopass-transform-each old-tail item-pat lang curr-nt call-recurse)))
        (if (and (eq? new-head old-head)
                 (eq? new-tail old-tail))
            lst
            (cons new-head new-tail)))))

;;; Schema-driven subforms list transformer (with Smart Reconstruction)
(define (nanopass-schema-transform-subforms prod-rest expr-rest lang curr-nt call-recurse)
  (cond
    ((or (null? prod-rest) (null? expr-rest))
     expr-rest)
    ((eq? (car prod-rest) '...)
     expr-rest)
    ;; Ellipsis pattern: (item-pat ... . tail-prod)
    ((and (pair? (cdr prod-rest)) (eq? (cadr prod-rest) '...))
     (let* ((item-pat (car prod-rest))
            (tail-prod (cddr prod-rest)))
       (if (null? tail-prod)
           (nanopass-transform-each expr-rest item-pat lang curr-nt call-recurse)
           (let* ((k (length tail-prod))
                  (n (length expr-rest))
                  (split-idx (if (>= n k) (- n k) 0))
                  (prefix (nanopass-take expr-rest split-idx))
                  (suffix (nanopass-drop expr-rest split-idx))
                  (new-prefix
                   (nanopass-transform-each prefix item-pat lang curr-nt call-recurse))
                  (new-suffix
                   (nanopass-schema-transform-subforms tail-prod suffix lang curr-nt call-recurse)))
             (if (and (eq? new-prefix prefix)
                      (eq? new-suffix suffix))
                 expr-rest
                 (append new-prefix new-suffix))))))
    (else
     (let ((new-head (nanopass-schema-transform-subpattern (car prod-rest) (car expr-rest) lang curr-nt call-recurse))
           (new-tail (nanopass-schema-transform-subforms (cdr prod-rest) (cdr expr-rest) lang curr-nt call-recurse)))
       (nanopass-cons-sharing expr-rest new-head new-tail)))))

;;; Schema-driven node transformer for matched production `prod` (with Smart Reconstruction)
(define (nanopass-schema-transform-node prod ir lang curr-nt call-recurse)
  (cond
    ((not (pair? ir)) ir)
    ((symbol? prod)
     ;; Production is a single meta-var (e.g. `e`, `d`, `a`, `lval`) that matched a pair `ir`.
     ;; Delegate to the sub-production that matched `ir` inside that nonterminal.
     (let ((cls (nanopass-classify-meta-var prod lang)))
       (if (and cls (eq? (car cls) 'nonterminal))
           (let ((sub-match (nanopass-find-matching-production ir (cadr cls) lang)))
             (if (and sub-match (not (equal? (cdr sub-match) prod)))
                 (nanopass-schema-transform-node (cdr sub-match) ir lang (car sub-match) call-recurse)
                 ir))
           ir)))
    ((pair? prod)
     (let ((head (car prod)))
       (cond
         ((eq? head 'quote)
          ir)
         ((symbol? head)
          (let ((cls (nanopass-classify-meta-var head lang)))
            (if cls
                ;; Application / head meta-variable: (e0 e1 ...) or (a0 a ...)
                (let ((new-head (if (eq? (car cls) 'nonterminal)
                                    (call-recurse (car ir))
                                    (car ir)))
                      (new-tail (nanopass-schema-transform-subforms (cdr prod) (cdr ir) lang curr-nt call-recurse)))
                  (nanopass-cons-sharing ir new-head new-tail))
                ;; Keyword-headed form: (if ...), (lambda ...), (%block ...), (%lir-program ...), etc.
                (let ((new-tail (nanopass-schema-transform-subforms (cdr prod) (cdr ir) lang curr-nt call-recurse)))
                  (nanopass-cons-sharing ir (car ir) new-tail)))))
         (else
          (nanopass-schema-transform-subforms prod ir lang curr-nt call-recurse)))))
    (else ir)))

;;; Fallback S-expression structural transform (when language/production is unregistered)
;;; Preserves exact list structure and `eq?` structural sharing on unchanged subtrees.
(define (nanopass-fallback-transform-binding b call-recurse)
  (if (and (pair? b) (pair? (cdr b)))
      (let* ((tail (cdr b))
             (new-val (call-recurse (car tail)))
             (new-tail (nanopass-cons-sharing tail new-val (cdr tail))))
        (nanopass-cons-sharing b (car b) new-tail))
      b))

(define (nanopass-fallback-transform-node ir call-recurse)
  (if (not (pair? ir))
      ir
      (let ((op (car ir)))
        (case op
          ((quote)
           ir)
          ((if begin)
           (nanopass-cons-sharing ir op (nanopass-map-sharing call-recurse (cdr ir))))
          ((lambda)
           (let* ((rest (cdr ir))
                  (new-body (nanopass-map-sharing call-recurse (cdr rest)))
                  (new-rest (nanopass-cons-sharing rest (car rest) new-body)))
             (nanopass-cons-sharing ir op new-rest)))
          ((let)
           (if (and (pair? (cdr ir)) (symbol? (cadr ir)))
               (let* ((r1 (cdr ir))
                      (r2 (cdr r1))
                      (new-bindings
                       (nanopass-map-sharing
                        (lambda (b) (nanopass-fallback-transform-binding b call-recurse))
                        (car r2)))
                      (new-body (nanopass-map-sharing call-recurse (cdr r2)))
                      (new-r2 (nanopass-cons-sharing r2 new-bindings new-body))
                      (new-r1 (nanopass-cons-sharing r1 (car r1) new-r2)))
                 (nanopass-cons-sharing ir op new-r1))
               (let* ((r1 (cdr ir))
                      (new-bindings
                       (nanopass-map-sharing
                        (lambda (b) (nanopass-fallback-transform-binding b call-recurse))
                        (car r1)))
                      (new-body (nanopass-map-sharing call-recurse (cdr r1)))
                      (new-r1 (nanopass-cons-sharing r1 new-bindings new-body)))
                 (nanopass-cons-sharing ir op new-r1))))
          ((letrec let* letrec*)
           (let* ((r1 (cdr ir))
                  (new-bindings
                   (nanopass-map-sharing
                    (lambda (b) (nanopass-fallback-transform-binding b call-recurse))
                    (car r1)))
                  (new-body (nanopass-map-sharing call-recurse (cdr r1)))
                  (new-r1 (nanopass-cons-sharing r1 new-bindings new-body)))
             (nanopass-cons-sharing ir op new-r1)))
          ((set!)
           (let* ((r1 (cdr ir))
                  (r2 (cdr r1))
                  (new-val (call-recurse (car r2)))
                  (new-r2 (nanopass-cons-sharing r2 new-val (cdr r2)))
                  (new-r1 (nanopass-cons-sharing r1 (car r1) new-r2)))
             (nanopass-cons-sharing ir op new-r1)))
          ((%program)
           (let* ((r1 (cdr ir))
                  (r2 (cdr r1))
                  (new-defs
                   (nanopass-map-sharing
                    (lambda (d)
                      (if (and (pair? d) (eq? (car d) 'define))
                          (let* ((dr1 (cdr d))
                                 (new-dbody (nanopass-map-sharing call-recurse (cdr dr1)))
                                 (new-dr1 (nanopass-cons-sharing dr1 (car dr1) new-dbody)))
                            (nanopass-cons-sharing d (car d) new-dr1))
                          (call-recurse d)))
                    (car r1)))
                  (new-body (call-recurse (car r2)))
                  (new-r2 (nanopass-cons-sharing r2 new-body (cdr r2)))
                  (new-r1 (nanopass-cons-sharing r1 new-defs new-r2)))
             (nanopass-cons-sharing ir op new-r1)))
          (else
           (nanopass-map-sharing call-recurse ir))))))

;;; Schema-driven analyzer accumulator fold for subpattern
(define (nanopass-schema-analyze-subpattern pat val lang acc step-acc)
  (cond
    ((symbol? pat)
     (let ((cls (nanopass-classify-meta-var pat lang)))
       (if (and cls (eq? (car cls) 'nonterminal))
           (step-acc val acc)
           acc)))
    ((pair? pat)
     (if (pair? val)
         (nanopass-schema-analyze-subforms pat val lang acc step-acc)
         acc))
    (else acc)))

;;; Schema-driven analyzer accumulator fold for subforms list
(define (nanopass-schema-analyze-subforms prod-rest expr-rest lang acc step-acc)
  (cond
    ((or (null? prod-rest) (null? expr-rest))
     acc)
    ((eq? (car prod-rest) '...)
     acc)
    ((and (pair? (cdr prod-rest)) (eq? (cadr prod-rest) '...))
     (let* ((item-pat (car prod-rest))
            (tail-prod (cddr prod-rest)))
       (if (null? tail-prod)
           (let loop ((es expr-rest) (cur-acc acc))
             (if (null? es)
                 cur-acc
                 (loop (cdr es)
                       (nanopass-schema-analyze-subpattern item-pat (car es) lang cur-acc step-acc))))
           (let* ((k (length tail-prod))
                  (n (length expr-rest))
                  (split-idx (if (>= n k) (- n k) 0))
                  (prefix (nanopass-take expr-rest split-idx))
                  (suffix (nanopass-drop expr-rest split-idx))
                  (acc1 (let loop ((es prefix) (cur-acc acc))
                          (if (null? es)
                              cur-acc
                              (loop (cdr es)
                                    (nanopass-schema-analyze-subpattern item-pat (car es) lang cur-acc step-acc))))))
             (nanopass-schema-analyze-subforms tail-prod suffix lang acc1 step-acc)))))
    (else
     (let ((next-acc (nanopass-schema-analyze-subpattern (car prod-rest) (car expr-rest) lang acc step-acc)))
       (nanopass-schema-analyze-subforms (cdr prod-rest) (cdr expr-rest) lang next-acc step-acc)))))

;;; Schema-driven analyzer accumulator fold for matched production `prod`
(define (nanopass-schema-analyze-node prod ir lang acc step-acc)
  (cond
    ((not (pair? ir)) acc)
    ((symbol? prod)
     (let ((cls (nanopass-classify-meta-var prod lang)))
       (if (and cls (eq? (car cls) 'nonterminal))
           (let ((sub-match (nanopass-find-matching-production ir (cadr cls) lang)))
             (if (and sub-match (not (equal? (cdr sub-match) prod)))
                 (nanopass-schema-analyze-node (cdr sub-match) ir lang acc step-acc)
                 acc))
           acc)))
    ((pair? prod)
     (let ((head (car prod)))
       (cond
         ((eq? head 'quote)
          acc)
         ((symbol? head)
          (let ((cls (nanopass-classify-meta-var head lang)))
            (if cls
                ;; In pure analyzer mode, if `(car ir)` is a symbol (operator/primitive name),
                ;; only fold into `(car ir)` when it is a compound expression (`pair?`),
                ;; matching Nanopass analyzer convention.
                (let ((acc1 (if (and (eq? (car cls) 'nonterminal) (pair? (car ir)))
                                (step-acc (car ir) acc)
                                acc)))
                  (nanopass-schema-analyze-subforms (cdr prod) (cdr ir) lang acc1 step-acc))
                (nanopass-schema-analyze-subforms (cdr prod) (cdr ir) lang acc step-acc))))
         (else
          (nanopass-schema-analyze-subforms prod ir lang acc step-acc)))))
    (else acc)))

(define (nanopass-catamorphism-step lang-in lang-out nt-name ir recurse-fn extra-args extra-out)
  (let ((extra-args (if (pair? extra-args) extra-args '()))
        (extra-out (if (pair? extra-out) extra-out '()))
        (lang (nanopass-lookup-language-opt lang-in)))
    (if (eq? lang-out '*)
        ;; Pure Analyzer mode: default for unmatched atom is accumulator (if threaded) or #f
        (cond
          ((not (pair? ir))
           (if (and (pair? extra-args) (pair? extra-out))
               (car (reverse extra-args))
               #f))
          (else
           (if (pair? extra-args)
               (let* ((rev-extra (reverse extra-args))
                      (initial-acc (car rev-extra))
                      (prefix (reverse (cdr rev-extra)))
                      (step-acc
                       (lambda (item cur-acc)
                         (nanopass-apply-list recurse-fn (cons item (append prefix (list cur-acc))))))
                      (matched (if lang (nanopass-find-matching-production ir nt-name lang) #f)))
                 (if matched
                     (nanopass-schema-analyze-node (cdr matched) ir lang initial-acc step-acc)
                     (let ((elements (if (symbol? (car ir)) (cdr ir) ir)))
                       (let loop ((cur elements) (acc initial-acc))
                         (cond
                           ((null? cur) acc)
                           ((not (pair? cur))
                            (step-acc cur acc))
                           (else
                            (loop (cdr cur) (step-acc (car cur) acc))))))))
               #f)))
        ;; Transform mode: reconstruct AST according to define-language schema while propagating inherited attributes
        (let ((call-recurse
               (lambda (node)
                 (if (or (not (car *nanopass-term-memo-enabled?*))
                         (not (car *nanopass-term-memo-active?*))
                         (not (pair? node))
                         (pair? extra-args))
                     (if (null? extra-args)
                         (recurse-fn node)
                         (nanopass-apply-list recurse-fn (cons node extra-args)))
                     (let ((hit (assq node (car *nanopass-term-memo*))))
                       (if hit
                           (begin
                             (set-car! *nanopass-term-memo-stats* (+ (car *nanopass-term-memo-stats*) 1))
                             (cdr hit))
                           (begin
                             (set-cdr! *nanopass-term-memo-stats* (+ (cdr *nanopass-term-memo-stats*) 1))
                             (let ((res (recurse-fn node)))
                               (set-car! *nanopass-term-memo*
                                         (cons (cons node res) (car *nanopass-term-memo*)))
                               res))))))))
          (if (not (pair? ir))
              ir
              (let ((matched (if lang (nanopass-find-matching-production ir nt-name lang) #f)))
                (if matched
                    (nanopass-schema-transform-node (cdr matched) ir lang (car matched) call-recurse)
                    (nanopass-fallback-transform-node ir call-recurse))))))))

;;; -----------------------------------------------------------------------
;;; Part 10: Local Re-dispatch Parameters & Schema Coverage Validation (DSN-33-01 T3.2)
;;; -----------------------------------------------------------------------

;;; Bounded fuel counter for Local Re-dispatch on a single AST node position.
;;; Prevents infinite rewrite cycles (e.g. A -> B -> A) and ensures terminating execution (CWE-400 mitigation).
(define *nanopass-redispatch-limit* 64)

;;; Collect all eliminated syntax tags and head tags from rule descriptors or names
(define (nanopass-collect-rule-eliminates rule-specs)
  (let ((flat-specs (if (and (= (length rule-specs) 1) (list? (car rule-specs)))
                        (car rule-specs)
                        rule-specs)))
    (let loop ((rem flat-specs) (acc '()))
      (if (null? rem)
          acc
          (let* ((spec (car rem))
                 (desc (nanopass-resolve-rule-descriptor spec)))
            (if (not desc)
                (loop (cdr rem) acc)
                (let* ((elims (rule-eliminates desc))
                       (heads (rule-head-tags desc))
                       (acc1 (cond
                               ((list? elims) (nanopass-combine-sets acc elims))
                               ((and (symbol? elims) (not (eq? elims '*))) (nanopass-combine-sets acc (list elims)))
                               (else acc)))
                       (acc2 (cond
                               ((list? heads) (nanopass-combine-sets acc1 heads))
                               ((and (symbol? heads) (not (eq? heads '*))) (nanopass-combine-sets acc1 (list heads)))
                               (else acc1))))
                  (loop (cdr rem) acc2))))))))

;;; Extract removed production head symbols from language definition or language-diff
(define (nanopass-get-language-removed-tags l-in l-out)
  (if (or (eq? l-in l-out) (eq? l-out '*))
      '()
      (let* ((out-lang (nanopass-lookup-language-opt l-out))
             (in-lang (nanopass-lookup-language-opt l-in)))
        (if (and in-lang out-lang)
            (let* ((diff (language-diff l-in l-out))
                   (diff-removed-entry (assq 'removed diff))
                   (diff-prods (if diff-removed-entry (cadr diff-removed-entry) '()))
                   (diff-heads (let loop ((ps diff-prods) (acc '()))
                                 (cond
                                   ((null? ps) (reverse acc))
                                   ((and (pair? (car ps)) (symbol? (caar ps)))
                                    (if (memq (caar ps) acc)
                                        (loop (cdr ps) acc)
                                        (loop (cdr ps) (cons (caar ps) acc))))
                                   (else (loop (cdr ps) acc)))))
                   (direct-removed (nanopass-lang-removed-prods out-lang))
                   (parents (language-parent-chain l-out)))
              (if (memq l-in parents)
                  (nanopass-combine-sets diff-heads direct-removed)
                  diff-heads))
            '()))))

;;; Verify that all syntax constructs removed in l-out (- ...) are covered
;;; by the eliminates/head-tags of the fused rules in rule-specs.
;;; Returns a list of missing tags (empty list '() on 100% coverage).
(define (nanopass-verify-fusion-coverage l-in l-out rule-specs)
  (let ((removed-tags (nanopass-get-language-removed-tags l-in l-out)))
    (if (null? removed-tags)
        '()
        (let* ((covered-tags (nanopass-collect-rule-eliminates rule-specs))
               (missing (let loop ((rem removed-tags) (acc '()))
                          (cond
                            ((null? rem) (reverse acc))
                            ((memq (car rem) covered-tags)
                             (loop (cdr rem) acc))
                            (else
                             (loop (cdr rem) (cons (car rem) acc)))))))
          missing))))

;;; =======================================================================
;;; Sliding Window Traversal & Convergence Driver for Linear IR (InstWindow)
;;; Conforms to DSN-33-01 Section 4.4 & 6.3 (fuse-window-rules, T3.3)
;;; =======================================================================

(define *nanopass-window-fixpoint-limit* 16)
(define *nanopass-window-step-limit* 1024)

;;; Single-pass sliding window traversal:
;;; Evaluates try-match-proc at each instruction boundary.
;;; If matched, replaces prefix and performs local re-dispatch.
;;; If no match, advances window by 1 instruction.
;;; Returns (cons transformed-insts changed-boolean)
(define (nanopass-sliding-window-pass try-match-proc insts)
  (let loop ((rest insts)
             (acc '())
             (changed? #f)
             (step-fuel *nanopass-window-step-limit*))
    (cond
      ((null? rest)
       (cons (reverse acc) changed?))
      ((<= step-fuel 0)
       (cons (append (reverse acc) rest) changed?))
      (else
       (let ((m (try-match-proc rest)))
         (if (and (pair? m) (car m))
             (let ((new-suffix (cdr m)))
               (if (eq? new-suffix rest)
                   (loop (cdr rest) (cons (car rest) acc) changed? step-fuel)
                   (loop new-suffix acc #t (- step-fuel 1))))
             (loop (cdr rest) (cons (car rest) acc) changed? step-fuel)))))))

;;; Bounded fixpoint loop for sliding window optimizations
(define (nanopass-sliding-window-fixpoint try-match-proc insts)
  (let loop ((cur insts)
             (iterations *nanopass-window-fixpoint-limit*))
    (if (<= iterations 0)
        cur
        (let* ((res (nanopass-sliding-window-pass try-match-proc cur))
               (next (car res))
               (changed? (cdr res)))
          (if (or (not changed?) (eq? cur next))
              next
              (loop next (- iterations 1)))))))

;;; Optimize body instructions inside %lir-function
(define (nanopass-optimize-function-body opt-proc f)
  (if (and (pair? f) (eq? (car f) '%lir-function))
      (let* ((lbl (cadr f))
             (params (caddr f))
             (frame-size (cadddr f))
             (body-clause (car (cddddr f)))
             (insts (if (and (pair? body-clause) (eq? (car body-clause) 'body))
                        (cdr body-clause)
                        '()))
             (opt-insts (opt-proc insts)))
        (list '%lir-function lbl params frame-size (cons 'body opt-insts)))
      f))

;;; Optimize body instructions inside %lir-main
(define (nanopass-optimize-main-body opt-proc m)
  (if (and (pair? m) (eq? (car m) '%lir-main))
      (let* ((frame-size (cadr m))
             (body-clause (caddr m))
             (insts (if (and (pair? body-clause) (eq? (car body-clause) 'body))
                        (cdr body-clause)
                        '()))
             (opt-insts (opt-proc insts)))
        (list '%lir-main frame-size (cons 'body opt-insts)))
      m))

;;; Dual-mode wrapper: handles %lir-program, %lir-function, %lir-main, or flat instruction lists
(define (nanopass-wrap-window-rules-input opt-proc ir)
  (cond
    ((and (pair? ir) (eq? (car ir) '%lir-program))
     (let* ((rest (cdr ir))
            (strings-entry (if (pair? rest) (car rest) '(strings ())))
            (stackmaps-entry (if (and (pair? rest) (pair? (cdr rest))) (cadr rest) '(stackmaps ())))
            (functions-clause (if (and (pair? rest) (pair? (cdr rest)) (pair? (cddr rest))) (caddr rest) '(%lir-functions)))
            (main-clause (if (and (pair? rest) (pair? (cdr rest)) (pair? (cddr rest)) (pair? (cdddr rest))) (cadddr rest) '(%lir-main (frame-size 0) (body))))
            (raw-funcs (if (and (pair? functions-clause) (eq? (car functions-clause) '%lir-functions))
                           (cdr functions-clause)
                           '()))
            (opt-funcs (map (lambda (f) (nanopass-optimize-function-body opt-proc f)) raw-funcs))
            (opt-main (nanopass-optimize-main-body opt-proc main-clause)))
       (list '%lir-program strings-entry stackmaps-entry (cons '%lir-functions opt-funcs) opt-main)))
    ((and (pair? ir) (eq? (car ir) '%lir-function))
     (nanopass-optimize-function-body opt-proc ir))
    ((and (pair? ir) (eq? (car ir) '%lir-main))
     (nanopass-optimize-main-body opt-proc ir))
    ((list? ir)
     (opt-proc ir))
    (else ir)))

;;; =======================================================================
;;; Part 12: Rule Dependency DAG & Graph Analysis (DSN-33-01 T5.1)
;;; =======================================================================

(define (nanopass-normalize-set s)
  (cond
    ((null? s) '())
    ((list? s) s)
    ((symbol? s) (list s))
    (else '())))

(define (nanopass-set-intersects? s1 s2)
  (let ((l1 (nanopass-normalize-set s1))
        (l2 (nanopass-normalize-set s2)))
    (let loop ((items l1))
      (cond
        ((null? items) #f)
        ((memq (car items) l2) #t)
        (else (loop (cdr items)))))))

(define (nanopass-make-rule-dag nodes edges in-degrees out-degrees rule-map)
  (list 'rule-dag nodes edges in-degrees out-degrees rule-map))

(define (rule-dag? obj)
  (and (pair? obj) (eq? (car obj) 'rule-dag)))

(define (rule-dag-nodes dag) (cadr dag))
(define (rule-dag-edges dag) (caddr dag))
(define (rule-dag-in-degrees dag) (cadddr dag))
(define (rule-dag-out-degrees dag) (car (cddddr dag)))
(define (rule-dag-rule-map dag) (cadr (cddddr dag)))

(define (nanopass-rule-dag-nodes dag) (rule-dag-nodes dag))
(define (nanopass-rule-dag-edges dag) (rule-dag-edges dag))
(define (nanopass-rule-dag-in-degrees dag) (rule-dag-in-degrees dag))
(define (nanopass-rule-dag-out-degrees dag) (rule-dag-out-degrees dag))

(define (nanopass-compute-rule-edges descs)
  (let loop-a ((rem-a descs) (edges '()))
    (if (null? rem-a)
        (reverse edges)
        (let ((a (car rem-a)))
          (let loop-b ((rem-b descs) (cur-edges edges))
            (if (null? rem-b)
                (loop-a (cdr rem-a) cur-edges)
                (let ((b (car rem-b)))
                  (let* ((w-a (rule-writes a))
                         (e-a (rule-eliminates a))
                         (r-b (rule-reads b))
                         (h-b (rule-head-tags b))
                         (dep? (or (nanopass-set-intersects? w-a r-b)
                                   (nanopass-set-intersects? e-a r-b)
                                   (and (list? h-b) (nanopass-set-intersects? w-a h-b)))))
                    (if dep?
                        (loop-b (cdr rem-b) (cons (cons (rule-name a) (rule-name b)) cur-edges))
                        (loop-b (cdr rem-b) cur-edges))))))))))

(define (nanopass-build-rule-dag rule-specs)
  (let* ((flat-specs (if (and (= (length rule-specs) 1) (list? (car rule-specs)))
                         (car rule-specs)
                         rule-specs))
         (descs (let loop ((rem flat-specs) (acc '()))
                  (if (null? rem)
                      (reverse acc)
                      (let ((d (nanopass-resolve-rule-descriptor (car rem))))
                        (if d
                            (loop (cdr rem) (cons d acc))
                            (loop (cdr rem) acc))))))
         (nodes (map rule-name descs))
         (rule-map (map (lambda (d) (cons (rule-name d) d)) descs)))
    (let* ((edges (nanopass-compute-rule-edges descs))
           (in-deg-map (map (lambda (n)
                              (cons n (length (filter (lambda (e) (eq? (cdr e) n)) edges))))
                            nodes))
           (out-deg-map (map (lambda (n)
                               (cons n (length (filter (lambda (e) (eq? (car e) n)) edges))))
                             nodes)))
      (nanopass-make-rule-dag nodes edges in-deg-map out-deg-map rule-map))))

;;; Topological sorting with level stratification (Kahn's algorithm)
(define (nanopass-rule-dag-stratify-levels dag)
  (let* ((nodes (rule-dag-nodes dag))
         (edges (rule-dag-edges dag))
         (in-degrees (map (lambda (entry) (cons (car entry) (cdr entry)))
                          (rule-dag-in-degrees dag))))
    (let loop ((rem-nodes nodes) (levels '()))
      (if (null? rem-nodes)
          (reverse levels)
          (let ((current-zero (filter (lambda (n)
                                        (let ((deg-entry (assq n in-degrees)))
                                          (and deg-entry (= (cdr deg-entry) 0))))
                                      rem-nodes)))
            (if (null? current-zero)
                ;; Cycle detected!
                #f
                (begin
                  (for-each (lambda (u)
                              (for-each (lambda (e)
                                          (if (eq? (car e) u)
                                              (let ((v-entry (assq (cdr e) in-degrees)))
                                                (if v-entry
                                                    (set-cdr! v-entry (- (cdr v-entry) 1))))))
                                        edges))
                            current-zero)
                  (let ((next-rem (filter (lambda (n) (not (memq n current-zero))) rem-nodes)))
                    (loop next-rem (cons current-zero levels))))))))))

(define (nanopass-rule-dag-topological-sort dag)
  (let ((levels (nanopass-rule-dag-stratify-levels dag)))
    (if (not levels)
        #f
        (let loop ((rem levels) (acc '()))
          (if (null? rem)
              (reverse acc)
              (loop (cdr rem) (append (reverse (car rem)) acc)))))))

;;; Strongly Connected Components (Tarjan's algorithm)
(define (nanopass-rule-dag-scc dag)
  (let* ((nodes (rule-dag-nodes dag))
         (edges (rule-dag-edges dag))
         (index-counter (cons 0 '()))
         (indices (cons '() '()))
         (lowlinks (cons '() '()))
         (stack (cons '() '()))
         (on-stack (cons '() '()))
         (sccs (cons '() '())))
    (letrec ((get-neighbors
              (lambda (u)
                (let loop ((rem edges) (acc '()))
                  (cond
                    ((null? rem) (reverse acc))
                    ((eq? (caar rem) u) (loop (cdr rem) (cons (cdar rem) acc)))
                    (else (loop (cdr rem) acc))))))
             (strongconnect
              (lambda (v)
                (let ((idx (car index-counter)))
                  (set-car! index-counter (+ idx 1))
                  (set-car! indices (cons (cons v idx) (car indices)))
                  (set-car! lowlinks (cons (cons v idx) (car lowlinks)))
                  (set-car! stack (cons v (car stack)))
                  (set-car! on-stack (cons v (car on-stack)))
                  (let loop ((neighbors (get-neighbors v)))
                    (if (not (null? neighbors))
                        (let ((w (car neighbors)))
                          (let ((w-idx (assq w (car indices))))
                            (cond
                              ((not w-idx)
                               (strongconnect w)
                               (let* ((v-low (cdr (assq v (car lowlinks))))
                                      (w-low (cdr (assq w (car lowlinks))))
                                      (new-low (if (< v-low w-low) v-low w-low)))
                                 (set-cdr! (assq v (car lowlinks)) new-low)))
                              ((memq w (car on-stack))
                               (let* ((v-low (cdr (assq v (car lowlinks))))
                                      (w-i (cdr w-idx))
                                      (new-low (if (< v-low w-i) v-low w-i)))
                                 (set-cdr! (assq v (car lowlinks)) new-low)))))
                          (loop (cdr neighbors)))))
                  (let ((v-idx (cdr (assq v (car indices))))
                        (v-low (cdr (assq v (car lowlinks)))))
                    (if (= v-low v-idx)
                        (let pop-loop ((comp '()))
                          (let ((top (car (car stack))))
                            (set-car! stack (cdr (car stack)))
                            (set-car! on-stack (let rm ((s (car on-stack)))
                                                 (cond ((null? s) '())
                                                       ((eq? (car s) top) (cdr s))
                                                       (else (cons (car s) (rm (cdr s)))))))
                            (let ((new-comp (cons top comp)))
                              (if (eq? top v)
                                  (set-car! sccs (cons (reverse new-comp) (car sccs)))
                                  (pop-loop new-comp)))))))))))
      (for-each (lambda (n)
                  (if (not (assq n (car indices)))
                      (strongconnect n)))
                nodes)
      (reverse (car sccs)))))

(define (nanopass-rule-dag-cycles dag)
  (let* ((edges (rule-dag-edges dag))
         (sccs (nanopass-rule-dag-scc dag)))
    (filter (lambda (comp)
              (or (> (length comp) 1)
                  (and (= (length comp) 1)
                       (let ((v (car comp)))
                         (let check-self ((rem edges))
                           (cond
                             ((null? rem) #f)
                             ((and (eq? (caar rem) v) (eq? (cdar rem) v)) #t)
                             (else (check-self (cdr rem)))))))))
            sccs)))

(define (nanopass-rule-dag-reachable? dag start target)
  (let ((edges (rule-dag-edges dag)))
    (let loop ((visited '()) (worklist (list start)))
      (cond
        ((null? worklist) #f)
        ((eq? (car worklist) target) #t)
        ((memq (car worklist) visited)
         (loop visited (cdr worklist)))
        (else
         (let* ((curr (car worklist))
                (succs (let find-succs ((rem edges) (acc '()))
                         (cond
                           ((null? rem) acc)
                           ((eq? (caar rem) curr)
                            (find-succs (cdr rem) (cons (cdar rem) acc)))
                           (else (find-succs (cdr rem) acc))))))
           (loop (cons curr visited) (append (cdr worklist) succs))))))))

(define (nanopass-rule-dag-independent-pair? dag u v)
  (and (not (eq? u v))
       (not (nanopass-rule-dag-reachable? dag u v))
       (not (nanopass-rule-dag-reachable? dag v u))))

(define (nanopass-rule-dag-antichains dag)
  (let ((levels (nanopass-rule-dag-stratify-levels dag)))
    (if levels
        levels
        (map list (rule-dag-nodes dag)))))

;;; =======================================================================
;;; Part 13: Femtopass Analysis Cache & Invalidation Protocol (DSN-33-01 T5.1)
;;; =======================================================================

(define *femto-analysis-cache* (cons '() '()))
(define *femto-cache-stats* (cons 0 0)) ; (cons hits misses)
(define *femto-attr-tag-dependencies* (cons '() '())) ; alist of (attr-name . tag-list)

(define (femto-cache-reset!)
  (set-car! *femto-analysis-cache* '())
  (set-car! *femto-cache-stats* 0)
  (set-cdr! *femto-cache-stats* 0))

(define (femto-register-attr-dependencies! attr-name tags)
  (let* ((curr (car *femto-attr-tag-dependencies*))
         (filtered (let loop ((rem curr))
                     (cond ((null? rem) '())
                           ((eq? (caar rem) attr-name) (loop (cdr rem)))
                           (else (cons (car rem) (loop (cdr rem))))))))
    (set-car! *femto-attr-tag-dependencies* (cons (cons attr-name tags) filtered))))

(define (femto-get-cached-attr attr-name node compute-thunk)
  (let* ((table (car *femto-analysis-cache*))
         (node-entry (assq node table)))
    (if node-entry
        (let ((attr-entry (assq attr-name (cdr node-entry))))
          (if attr-entry
              (begin
                (set-car! *femto-cache-stats* (+ (car *femto-cache-stats*) 1))
                (cdr attr-entry))
              (let ((computed-val (compute-thunk)))
                (set-cdr! *femto-cache-stats* (+ (cdr *femto-cache-stats*) 1))
                (set-cdr! node-entry (cons (cons attr-name computed-val) (cdr node-entry)))
                computed-val)))
        (let ((computed-val (compute-thunk)))
          (set-cdr! *femto-cache-stats* (+ (cdr *femto-cache-stats*) 1))
          (set-car! *femto-analysis-cache*
                    (cons (cons node (list (cons attr-name computed-val))) table))
          computed-val))))

(define (femto-cache-invalidate-tags! changed-tags)
  (if (or (eq? changed-tags '*)
          (and (list? changed-tags) (memq '* changed-tags)))
      (set-car! *femto-analysis-cache* '())
      (let ((deps (car *femto-attr-tag-dependencies*)))
        (let loop ((nodes (car *femto-analysis-cache*)) (new-table '()))
          (if (null? nodes)
              (set-car! *femto-analysis-cache* (reverse new-table))
              (let* ((node-entry (car nodes))
                     (node (car node-entry))
                     (attrs (cdr node-entry))
                     (surviving-attrs
                      (filter (lambda (attr-cell)
                                (let* ((attr-name (car attr-cell))
                                       (tag-entry (assq attr-name deps)))
                                  (if (not tag-entry)
                                      #t
                                      (not (nanopass-set-intersects? (cdr tag-entry) changed-tags)))))
                              attrs)))
                (if (null? surviving-attrs)
                    (loop (cdr nodes) new-table)
                    (loop (cdr nodes) (cons (cons node surviving-attrs) new-table)))))))))

(define (femto-cache-invalidate-node! node)
  (let ((table (car *femto-analysis-cache*)))
    (set-car! *femto-analysis-cache*
              (filter (lambda (entry) (not (eq? (car entry) node))) table))))

(define (femto-cache-stats)
  (list (cons 'hits (car *femto-cache-stats*))
        (cons 'misses (cdr *femto-cache-stats*))
        (cons 'entries (length (car *femto-analysis-cache*)))))

(define (femto-cache-hit-rate)
  (let ((hits (car *femto-cache-stats*))
        (misses (cdr *femto-cache-stats*)))
    (let ((total (+ hits misses)))
      (if (= total 0)
          0
          (/ (* hits 100) total)))))

;;; -----------------------------------------------------------------------
;;; Part 14: Hash-Consing Term DAG and Memoized Catamorphism (DSN-33-01 T5.2)
;;; -----------------------------------------------------------------------

;;; 14.1 Hash-Consing Constructor for Immutable S-expression Subterms
(define *nanopass-hash-cons-table* (cons '() '()))

(define (nanopass-hash-cons-reset!)
  (set-car! *nanopass-hash-cons-table* '()))

(define (nanopass-hash-cons a d)
  (let ((key (cons a d))
        (table (car *nanopass-hash-cons-table*)))
    (let ((existing (assoc key table)))
      (if existing
          (cdr existing)
          (let ((new-pair (cons a d)))
            (set-car! *nanopass-hash-cons-table*
                      (cons (cons key new-pair) table))
            new-pair)))))

(define (nanopass-hash-cons-list es)
  (if (null? es)
      '()
      (nanopass-hash-cons (car es) (nanopass-hash-cons-list (cdr es)))))

;;; 14.2 Scoped Term DAG Catamorphism Memoization
(define *nanopass-term-memo* (cons '() '()))
(define *nanopass-term-memo-enabled?* (cons #t '()))
(define *nanopass-term-memo-active?* (cons #f '()))
(define *nanopass-term-memo-stats* (cons 0 0)) ; (cons hits misses)

(define (enable-nanopass-term-memo!)
  (set-car! *nanopass-term-memo-enabled?* #t))

(define (disable-nanopass-term-memo!)
  (set-car! *nanopass-term-memo-enabled?* #f))

(define (nanopass-term-memo-reset!)
  (set-car! *nanopass-term-memo* '())
  (set-car! *nanopass-term-memo-stats* 0)
  (set-cdr! *nanopass-term-memo-stats* 0))

(define (nanopass-term-memo-stats)
  (list (cons 'hits (car *nanopass-term-memo-stats*))
        (cons 'misses (cdr *nanopass-term-memo-stats*))
        (cons 'entries (length (car *nanopass-term-memo*)))))

(define (nanopass-term-memo-hit-rate)
  (let ((hits (car *nanopass-term-memo-stats*))
        (misses (cdr *nanopass-term-memo-stats*)))
    (let ((total (+ hits misses)))
      (if (= total 0)
          0
          (quotient (* hits 100) total)))))

(define (with-nanopass-term-memo thunk)
  (let ((old-memo (car *nanopass-term-memo*))
        (old-active (car *nanopass-term-memo-active?*)))
    (set-car! *nanopass-term-memo* '())
    (set-car! *nanopass-term-memo-active?* #t)
    (let ((res (guard (ex (else
                            (set-car! *nanopass-term-memo* old-memo)
                            (set-car! *nanopass-term-memo-active?* old-active)
                            (raise ex)))
                 (thunk))))
      (set-car! *nanopass-term-memo* old-memo)
      (set-car! *nanopass-term-memo-active?* old-active)
      res)))

(define (nanopass-memoize-step node transform-fn)
  (if (or (not (car *nanopass-term-memo-enabled?*))
          (not (car *nanopass-term-memo-active?*))
          (not (pair? node)))
      (transform-fn node)
      (let ((hit (assq node (car *nanopass-term-memo*))))
        (if hit
            (begin
              (set-car! *nanopass-term-memo-stats* (+ (car *nanopass-term-memo-stats*) 1))
              (cdr hit))
            (begin
              (set-cdr! *nanopass-term-memo-stats* (+ (cdr *nanopass-term-memo-stats*) 1))
              (let ((res (transform-fn node)))
                (set-car! *nanopass-term-memo*
                          (cons (cons node res) (car *nanopass-term-memo*)))
                res))))))

;;; =======================================================================
;;; Part 15: LIR Basic Block Data Dependency DAG & Reaching Store Forwarding (DSN-33-01 T5.3)
;;; =======================================================================

(define (lir-peephole-reg? opnd)
  (and (symbol? opnd)
       (let ((s (symbol->string opnd)))
         (and (> (string-length s) 1)
              (char=? (string-ref s 0) #\%)))))

(define (lir-unconditional-terminator? inst)
  (and (pair? inst)
       (memq (car inst) '(%jump %direct-jump %return))))

(define (lir-label-inst? inst)
  (and (pair? inst)
       (memq (car inst) '(%label %block))))

(define (lir-inst-defines-reg? inst reg)
  (and (pair? inst)
       (let ((op (car inst)))
         (case op
           ((%mov %load %load-byte-zx %pop %code-ref %str-ref %global-ref
             %add %raw-add %sub %raw-sub %imul %raw-mul
             %bit-and %bit-or %bit-xor %shl %shr %sar
             %box-fixnum %unbox-fixnum %neg %inc
             %alloc %alloc-stack)
            (and (pair? (cdr inst)) (equal? (cadr inst) reg)))
           ((%set-boolean)
            (or (and (pair? (cdr inst)) (equal? (cadr inst) reg))
                (eq? reg '%rax)))
           ((%cqo %idiv)
            (memq reg '(%rax %rdx)))
           ((%atomic-cas!)
            (or (and (pair? (cdr inst)) (equal? (cadr inst) reg))
                (eq? reg '%rax)))
           ((%c-call %call-closure %direct-call %dispatch-consumer)
            (memq reg '(%rax %rcx %rdx %rsi %rdi %r8 %r9 %r10 %r11)))
           ((%syscall)
            (memq reg '(%rax %rcx %r11)))
           ((%set-values-count)
            (eq? reg '%rdx))
           ((%global-set!)
            (eq? reg '%r11))
           (else #f)))))

(define (lir-inst-memory-barrier? inst)
  (and (pair? inst)
       (memq (car inst) '(%c-call %call-closure %direct-call %dispatch-consumer
                          %syscall %memory-fence %push %pop %raise
                          %capture-cc %push-handler %pop-handler
                          %store-values-buf))))

(define (lir-inst-terminates-block? inst)
  (and (pair? inst)
       (memq (car inst) '(%jump %direct-jump %jump-cond %jump-if %jump-if-false %jump-if-zero
                          %return %raise %label %block))))

(define (lir-skip-to-next-label insts)
  (cond
    ((null? insts) '())
    ((lir-label-inst? (car insts)) insts)
    (else (lir-skip-to-next-label (cdr insts)))))

;;; Distance-independent Store-Reload Forwarding across instructions in basic block
(define (lir-dag-try-forward-store off src rest)
  (let loop ((cur rest)
             (prefix '()))
    (cond
      ((null? cur) #f)
      (else
       (let* ((inst (car cur))
              (tail (cdr cur)))
         (cond
           ;; 1. Block terminator: stop scanning
           ((lir-inst-terminates-block? inst)
            #f)

           ;; 2. Memory barrier: stop scanning
           ((lir-inst-memory-barrier? inst)
            #f)

           ;; 3. Store instruction:
           ((and (pair? inst) (eq? (car inst) '%store))
            (let ((base (cadr inst))
                  (store-off (caddr inst)))
              (cond
                ;; Indirect store not via %rsp: potential memory alias, stop
                ((not (eq? base '%rsp)) #f)
                ;; Overwriting the same stack slot: stop scanning
                ((equal? store-off off) #f)
                ;; Store to different stack slot: continue scanning
                (else
                 (loop tail (cons inst prefix))))))

           ;; 4. Load from matching stack slot (%load dst %rsp off)
           ;; Safely replace %load with (%mov dst src).
           ;; If dst == src, rule-lir-self-mov-elim will eliminate it monotonically.
           ((and (pair? inst)
                 (eq? (car inst) '%load)
                 (= (length inst) 4)
                 (eq? (caddr inst) '%rsp)
                 (equal? (cadddr inst) off))
            (let ((dst (cadr inst)))
              (append (reverse prefix) (cons (list '%mov dst src) tail))))

           ;; 5. Did inst clobber src register? Stop scanning
           ((lir-inst-defines-reg? inst src)
            #f)

           ;; 6. General instruction not defining src: continue scanning
           (else
            (loop tail (cons inst prefix)))))))))

;;; Extract registers/stack slots used by instruction
(define (lir-inst-extract-uses inst)
  (if (not (pair? inst))
      '()
      (case (car inst)
        ((%store)
         (let ((base (cadr inst)) (val (cadddr inst)))
           (cond
             ((and (eq? base '%rsp) (lir-peephole-reg? val)) (list val))
             ((lir-peephole-reg? base) (if (lir-peephole-reg? val) (list base val) (list base)))
             (else (if (lir-peephole-reg? val) (list val) '())))))
        ((%load)
         (let ((base (caddr inst)) (off (cadddr inst)))
           (if (eq? base '%rsp)
               (list (list 'stack off))
               (if (lir-peephole-reg? base) (list base) '()))))
        ((%mov)
         (let ((src (caddr inst)))
           (if (lir-peephole-reg? src) (list src) '())))
        ((%add %raw-add %sub %raw-sub %imul %raw-mul %bit-and %bit-or %bit-xor %shl %shr %sar)
         (let ((dst (cadr inst)) (src (caddr inst)))
           (if (lir-peephole-reg? src) (list dst src) (list dst))))
        ((%cmp %raw-cmp)
         (let ((op1 (cadr inst)) (op2 (caddr inst)))
           (cond
             ((and (lir-peephole-reg? op1) (lir-peephole-reg? op2)) (list op1 op2))
             ((lir-peephole-reg? op1) (list op1))
             ((lir-peephole-reg? op2) (list op2))
             (else '()))))
        (else '()))))

;;; Extract registers/stack slots defined by instruction
(define (lir-inst-extract-defs inst)
  (if (not (pair? inst))
      '()
      (case (car inst)
        ((%store)
         (let ((base (cadr inst)) (off (caddr inst)))
           (if (eq? base '%rsp)
               (list (list 'stack off))
               '())))
        ((%load %load-byte-zx %pop %code-ref %str-ref %global-ref %set-boolean %alloc %alloc-stack)
         (list (cadr inst)))
        ((%mov)
         (let ((dst (cadr inst)))
           (if (symbol? dst)
               (list dst)
               (if (and (pair? dst) (eq? (car dst) '%stack))
                   (list (list 'stack (cadr dst)))
                   '()))))
        ((%add %raw-add %sub %raw-sub %imul %raw-mul %bit-and %bit-or %bit-xor %shl %shr %sar %neg %inc)
         (list (cadr inst)))
        (else '()))))

;;; Build basic block data dependency DAG: (list 'lir-data-dag insts raw-edges waw-edges)
(define (lir-build-block-data-dag insts)
  (let loop ((cur insts)
             (idx 0)
             (reg-producers '())   ; ((reg . idx) ...)
             (stack-producers '()) ; ((off . idx) ...)
             (raw-edges '())       ; ((producer-idx . consumer-idx) ...)
             (waw-edges '()))      ; ((earlier-idx . later-idx) ...)
    (if (null? cur)
        (list 'lir-data-dag insts (reverse raw-edges) (reverse waw-edges))
        (let* ((inst (car cur))
               (tail (cdr cur)))
          (cond
            ((lir-inst-terminates-block? inst)
             (list 'lir-data-dag insts (reverse raw-edges) (reverse waw-edges)))
            ((lir-inst-memory-barrier? inst)
             (loop tail (+ idx 1) '() '() raw-edges waw-edges))
            (else
             (let* ((uses (lir-inst-extract-uses inst))
                    (defs (lir-inst-extract-defs inst))
                    (new-raw
                     (let u-loop ((us uses) (edges raw-edges))
                       (if (null? us)
                           edges
                           (let* ((u (car us))
                                  (prod (if (pair? u)
                                            (assoc (cadr u) stack-producers)
                                            (assoc u reg-producers))))
                             (if prod
                                 (u-loop (cdr us) (cons (cons (cdr prod) idx) edges))
                                 (u-loop (cdr us) edges))))))
                    (new-waw
                     (let d-loop ((ds defs) (edges waw-edges))
                       (if (null? ds)
                           edges
                           (let* ((d (car ds))
                                  (prod (if (pair? d)
                                            (assoc (cadr d) stack-producers)
                                            (assoc d reg-producers))))
                             (if prod
                                 (d-loop (cdr ds) (cons (cons (cdr prod) idx) edges))
                                 (d-loop (cdr ds) edges))))))
                    (new-reg-prods
                     (let r-up ((ds defs) (prods reg-producers))
                       (if (null? ds)
                           prods
                           (let ((d (car ds)))
                             (if (symbol? d)
                                 (r-up (cdr ds) (cons (cons d idx) (filter (lambda (p) (not (equal? (car p) d))) prods)))
                                 (r-up (cdr ds) prods))))))
                    (new-stack-prods
                     (let s-up ((ds defs) (prods stack-producers))
                       (if (null? ds)
                           prods
                           (let ((d (car ds)))
                             (if (and (pair? d) (eq? (car d) 'stack))
                                 (s-up (cdr ds) (cons (cons (cadr d) idx) (filter (lambda (p) (not (equal? (car p) (cadr d)))) prods)))
                                 (s-up (cdr ds) prods)))))))
               (loop tail (+ idx 1) new-reg-prods new-stack-prods new-raw new-waw))))))))

(define (lir-data-dag-insts dag) (cadr dag))
(define (lir-data-dag-raw-edges dag) (caddr dag))
(define (lir-data-dag-waw-edges dag) (cadddr dag))




