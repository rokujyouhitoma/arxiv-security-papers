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
    (nanopass-display-esc)
    (display "[36m----------------------------------------------------------------------")
    (nanopass-display-esc)
    (display "[0m\n")))

;;; Verifier Hooks Configuration & Error Reporting
(define *nanopass-verifier-enabled* (cons #f '()))
(define (nanopass-verifier-enabled?) (car *nanopass-verifier-enabled*))
(define (enable-nanopass-verifier!) (set-car! *nanopass-verifier-enabled* #t))
(define (disable-nanopass-verifier!) (set-car! *nanopass-verifier-enabled* #f))

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
      (let ((lang-entry (assq lang-name (car *nanopass-languages*))))
        (if (not lang-entry)
            #t
            (if (not (nanopass-ast-valid? lang-name val))
                (nanopass-verification-failure pass-name lang-name val phase)
                #t)))))


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
        (let loop-nts ((rest nts))
          (if (null? rest)
              #f
              (let ((e (car rest)))
                (if (and primary-entry (eq? (car e) nt-name))
                    (loop-nts (cdr rest))
                    (let ((m (try-nt e)))
                      (if m m (loop-nts (cdr rest)))))))))))

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
                 (if (null? extra-args)
                     (recurse-fn node)
                     (nanopass-apply-list recurse-fn (cons node extra-args))))))
          (if (not (pair? ir))
              ir
              (let ((matched (if lang (nanopass-find-matching-production ir nt-name lang) #f)))
                (if matched
                    (nanopass-schema-transform-node (cdr matched) ir lang (car matched) call-recurse)
                    (nanopass-fallback-transform-node ir call-recurse))))))))
