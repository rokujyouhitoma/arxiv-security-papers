;;; =======================================================================
;;; ULisp Compiler: Nanopass Framework Metadata & Reflection Engine
;;; Conforms to DSN-33 Architecture Specification & Keep & Dybvig (2013)
;;; =======================================================================

;;; Global language repository
(define *nanopass-languages* (cons '() '()))
(define *nanopass-nt-index-cache* (cons '() '()))

(define (nanopass-clear-languages!)
  (set-car! *nanopass-languages* '())
  (set-car! *nanopass-nt-index-cache* '()))

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
    (set-car! *nanopass-nt-index-cache* '())
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
             ;; Fast path: compute 1024-bucket hash directly from symbol indices before calling symbol->raw-name
             (h (modulo (+ (symbol->hash-idx var) (* (symbol->hash-idx lang-name) 31)) 1024))
             (bucket (vector-ref *classify-meta-var-cache* h)))
        (let loop ((entries bucket))
          (if (null? entries)
              (let* ((var-str (symbol->raw-name var))
                     (res (nanopass-classify-meta-var-uncached var-str lang))
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

(define (nanopass-build-nt-index nt-prods lang)
  (let ((tag-buckets (make-vector 128 '())))
    (define (add-tag! tag p)
      (let* ((h (modulo (symbol->hash-idx tag) 128))
             (bucket (vector-ref tag-buckets h))
             (slot (assq tag bucket)))
        (if slot
            (set-cdr! slot (cons p (cdr slot)))
            (vector-set! tag-buckets h (cons (list tag p) bucket)))))
    (let loop ((ps nt-prods) (pair-fb-rev '()) (lit-syms '()) (atom-rev '()))
      (if (null? ps)
          (begin
            (let rev-b ((b 0))
              (if (< b 128)
                  (begin
                    (for-each (lambda (entry) (set-cdr! entry (reverse (cdr entry))))
                              (vector-ref tag-buckets b))
                    (rev-b (+ b 1)))))
            (vector tag-buckets (reverse pair-fb-rev) lit-syms (reverse atom-rev)))
          (let ((p (car ps)))
            (cond
              ((pair? p)
               (let ((hd (car p)))
                 (if (and (symbol? hd)
                          (or (eq? hd 'quote)
                              (not (nanopass-classify-meta-var hd lang))))
                     (begin
                       (add-tag! hd p)
                       (loop (cdr ps) pair-fb-rev lit-syms atom-rev))
                     (loop (cdr ps) (cons p pair-fb-rev) lit-syms atom-rev))))
              ((symbol? p)
               (let ((cls (nanopass-classify-meta-var p lang)))
                 (cond
                   ((not cls)
                    (loop (cdr ps) pair-fb-rev (cons p lit-syms) atom-rev))
                   ((eq? (car cls) 'terminal)
                    (let ((tpred (cadr cls)))
                      (cond
                        ((memq tpred '(pair pair?))
                         (loop (cdr ps) (cons p pair-fb-rev) lit-syms atom-rev))
                        ((memq tpred '(symbol symbol? number number? integer integer?
                                       fixnum fixnum? string string? boolean boolean?
                                       char char? null null? constant constant?))
                         (loop (cdr ps) pair-fb-rev lit-syms (cons p atom-rev)))
                        (else
                         (loop (cdr ps) (cons p pair-fb-rev) lit-syms (cons p atom-rev))))))
                   (else
                    (loop (cdr ps) (cons p pair-fb-rev) lit-syms (cons p atom-rev))))))
              (else
               (loop (cdr ps) pair-fb-rev lit-syms (cons p atom-rev)))))))))

(define (nanopass-get-nt-index lang nt-name)
  (let find ((entries (car *nanopass-nt-index-cache*)))
    (if (pair? entries)
        (let ((e (car entries)))
          (if (and (eq? (car e) lang) (eq? (cadr e) nt-name))
              (caddr e)
              (find (cdr entries))))
        (let ((nt-entry (assq nt-name (nanopass-lang-nonterminals lang))))
          (if (not nt-entry)
              #f
              (let ((idx (nanopass-build-nt-index (caddr nt-entry) lang)))
                (set-car! *nanopass-nt-index-cache*
                          (cons (list lang nt-name idx) (car *nanopass-nt-index-cache*)))
                idx))))))

(define (nanopass-match-prod-list ps expr lang curr-nt deep?)
  (if (null? ps)
      #f
      (if (nanopass-production-matches-mode? (car ps) expr lang curr-nt deep?)
          #t
          (nanopass-match-prod-list (cdr ps) expr lang curr-nt deep?))))

(define (nanopass-check-node-mode expr nt-name lang deep?)
  ;; Check if expr is a list starting with an explicitly removed production head
  ;; (Only if it is not re-introduced as an active keyword in this language)
  (if (and (pair? expr)
           (symbol? (car expr))
           (memq (car expr) (nanopass-lang-removed-prods lang))
           (not (memq (car expr) (nanopass-lang-keywords lang))))
      #f
      ;; Check indexed nonterminal productions
      (let ((idx (nanopass-get-nt-index lang nt-name)))
        (if (not idx)
            #f
            (if (pair? expr)
                (let* ((head (car expr))
                       (tag-buckets (vector-ref idx 0))
                       (pair-fallback (vector-ref idx 1))
                       (tag-hit?
                        (if (symbol? head)
                            (let* ((h (modulo (symbol->hash-idx head) 128))
                                   (slot (assq head (vector-ref tag-buckets h))))
                              (if slot
                                  (nanopass-match-prod-list (cdr slot) expr lang nt-name deep?)
                                  #f))
                            #f)))
                  (if tag-hit?
                      #t
                      (nanopass-match-prod-list pair-fallback expr lang nt-name deep?)))
                (let ((lit-syms (vector-ref idx 2))
                      (atom-prods (vector-ref idx 3)))
                  (if (and (symbol? expr) (pair? lit-syms) (memq expr lit-syms))
                      #t
                      (nanopass-match-prod-list atom-prods expr lang nt-name deep?))))))))

(define (nanopass-check-valid-node expr nt-name lang)
  (nanopass-check-node-mode expr nt-name lang #t))

(define (nanopass-check-shallow-node expr nt-name lang)
  (nanopass-check-node-mode expr nt-name lang #f))

(define (nanopass-production-matches-mode? prod expr lang curr-nt deep?)
  (cond
    ((symbol? prod)
     (let ((cls (nanopass-classify-meta-var prod lang)))
       (cond
         ((not cls) (eq? prod expr))
         ((eq? (car cls) 'terminal)
          (nanopass-terminal-matches? (cadr cls) expr))
         ((eq? (car cls) 'nonterminal)
          (if deep?
              (nanopass-check-valid-node expr (cadr cls) lang)
              (if (eq? (cadr cls) curr-nt)
                  #t
                  (nanopass-check-shallow-node expr (cadr cls) lang))))
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
                                 (if deep?
                                     (nanopass-check-valid-node (car expr) (cadr cls) lang)
                                     #t))
                             (nanopass-match-subforms-mode (cdr prod) (cdr expr) lang curr-nt deep?)))
                    ;; Keyword-headed production: (if ...), (cond ...), (let ...), (%program ...), etc.
                    (if (eq? head (car expr))
                        (nanopass-match-subforms-mode (cdr prod) (cdr expr) lang curr-nt deep?)
                        #f))))
             (else #f)))))
    (else (equal? prod expr))))

(define (nanopass-production-matches? prod expr lang curr-nt)
  (nanopass-production-matches-mode? prod expr lang curr-nt #t))

(define (nanopass-production-matches-shallow? prod expr lang curr-nt)
  (nanopass-production-matches-mode? prod expr lang curr-nt #f))

(define (nanopass-match-subforms-mode prod-rest expr-rest lang curr-nt deep?)
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
       ;; Fast shallow path for nonterminal ellipsis (e ...), (a ...), etc.: check proper list spine only.
       (if (and (not deep?)
                (symbol? item-pat)
                (let ((cls (nanopass-classify-meta-var item-pat lang)))
                  (and cls (eq? (car cls) 'nonterminal))))
           (nanopass-proper-list? expr-rest)
           (let loop ((es expr-rest))
             (if (null? es)
                 #t
                 (and (pair? es)
                      (nanopass-match-subpattern-mode item-pat (car es) lang curr-nt deep?)
                      (loop (cdr es))))))))
    ((pair? (car prod-rest))
     (and (pair? expr-rest)
          (nanopass-match-subpattern-mode (car prod-rest) (car expr-rest) lang curr-nt deep?)
          (nanopass-match-subforms-mode (cdr prod-rest) (cdr expr-rest) lang curr-nt deep?)))
    (else
     (and (pair? expr-rest)
          (let* ((p (car prod-rest))
                 (cls (nanopass-classify-meta-var p lang)))
            (if cls
                (if (eq? (car cls) 'terminal)
                    (nanopass-terminal-matches? (cadr cls) (car expr-rest))
                    (if deep?
                        (nanopass-check-valid-node (car expr-rest) (cadr cls) lang)
                        #t))
                (equal? p (car expr-rest))))
          (nanopass-match-subforms-mode (cdr prod-rest) (cdr expr-rest) lang curr-nt deep?)))))

(define (nanopass-match-subforms prod-rest expr-rest lang curr-nt)
  (nanopass-match-subforms-mode prod-rest expr-rest lang curr-nt #t))

(define (nanopass-match-subforms-shallow prod-rest expr-rest lang curr-nt)
  (nanopass-match-subforms-mode prod-rest expr-rest lang curr-nt #f))

(define (nanopass-match-subpattern-mode pat val lang curr-nt deep?)
  (cond
    ((symbol? pat)
     (let ((cls (nanopass-classify-meta-var pat lang)))
       (if cls
           (if (eq? (car cls) 'terminal)
               (nanopass-terminal-matches? (cadr cls) val)
               (if deep?
                   (nanopass-check-valid-node val (cadr cls) lang)
                   #t))
           (equal? pat val))))
    ((pair? pat)
     (if (null? val)
         (or (eq? (car pat) '...)
             (and (pair? (cdr pat)) (eq? (cadr pat) '...)))
         (and (pair? val)
              (nanopass-match-subforms-mode pat val lang curr-nt deep?))))
    (else (equal? pat val))))

(define (nanopass-match-subpattern pat val lang curr-nt)
  (nanopass-match-subpattern-mode pat val lang curr-nt #t))

(define (nanopass-match-subpattern-shallow pat val lang curr-nt)
  (nanopass-match-subpattern-mode pat val lang curr-nt #f))

;;; Parser & Unparser Procs
(define (nanopass-parse-nt lang-name expr nt-name)
  (if (nanopass-ast-valid-nt? lang-name expr nt-name)
      expr
      (error (string-append "nanopass-parse: invalid expression for language "
                            (symbol->raw-name lang-name))
             expr)))

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
  (if (> (cdr *femto-analysis-cache*) 0)
      (begin
        (femto-cache-invalidate-node! old-ir)
        (let ((desc (nanopass-lookup-rule rule-name)))
          (if desc
              (let ((changed-tags (nanopass-combine-sets (rule-writes desc) (rule-eliminates desc))))
                (if (pair? changed-tags)
                    (femto-cache-invalidate-tags! changed-tags)))))))
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
(define (nanopass-match-clause pat raw-expr expected-vars recurse-fn)
  (let ((expr (if (or (ast-has-span? raw-expr) (source-loc? raw-expr))
                  (ast-strip-span raw-expr)
                  raw-expr)))
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
                          (loop (cdr vars) (cons #f vals))))))))))))

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

;;; Global rule repository:
;;;   *nanopass-rule-buckets* : 256-slot vector of ((sym . desc) ...)
;;;   *nanopass-rule-procs*   : alist of ((proc . desc) ...)
;;;   *nanopass-rules*        : (cons (list (cons name desc) ...) '()) in registration order
(define *nanopass-rule-bucket-count* 256)

(define (nanopass-make-rule-buckets)
  (make-vector *nanopass-rule-bucket-count* '()))

(define (nanopass-rule-bucket-idx sym)
  (modulo (symbol->hash-idx sym) *nanopass-rule-bucket-count*))

(define *nanopass-rule-buckets* (nanopass-make-rule-buckets))
(define *nanopass-rule-procs* (cons '() '()))
(define *nanopass-rules* (cons '() '()))

(define (nanopass-clear-rules!)
  (let loop ((i 0))
    (if (< i *nanopass-rule-bucket-count*)
        (begin
          (vector-set! *nanopass-rule-buckets* i '())
          (loop (+ i 1)))))
  (set-car! *nanopass-rule-procs* '())
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
      (let* ((name (rule-name desc))
             (proc (rule-proc desc))
             (b-idx (nanopass-rule-bucket-idx name))
             (bucket (vector-ref *nanopass-rule-buckets* b-idx))
             (filt-bucket (let loop ((rem bucket))
                            (cond ((null? rem) '())
                                  ((eq? (caar rem) name) (loop (cdr rem)))
                                  (else (cons (car rem) (loop (cdr rem))))))))
        (vector-set! *nanopass-rule-buckets* b-idx (cons (cons name desc) filt-bucket))
        (if proc
            (let ((filt-procs (let loop ((rem (car *nanopass-rule-procs*)))
                                (cond ((null? rem) '())
                                      ((or (eq? (caar rem) proc)
                                           (eq? (rule-name (cdar rem)) name))
                                       (loop (cdr rem)))
                                      (else (cons (car rem) (loop (cdr rem))))))))
              (set-car! *nanopass-rule-procs* (cons (cons proc desc) filt-procs))))
        (let ((filt-all (let loop ((rem (car *nanopass-rules*)))
                          (cond ((null? rem) '())
                                ((eq? (caar rem) name) (loop (cdr rem)))
                                (else (cons (car rem) (loop (cdr rem))))))))
          (set-car! *nanopass-rules* (cons (cons name desc) filt-all)))
        name)))

(define (nanopass-lookup-rule-opt name-or-proc)
  (cond
    ((rule-descriptor? name-or-proc)
     name-or-proc)
    ((symbol? name-or-proc)
     (let* ((b-idx (nanopass-rule-bucket-idx name-or-proc))
            (entry (assq name-or-proc (vector-ref *nanopass-rule-buckets* b-idx))))
       (if entry (cdr entry) #f)))
    (else
     (let ((entry (assq name-or-proc (car *nanopass-rule-procs*))))
       (if entry
           (cdr entry)
           (let ((fallback (assq name-or-proc (car *nanopass-rules*))))
             (if fallback (cdr fallback) #f)))))))

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
    (for-each disable-picopass! rules)
    (let ((res (thunk)))
      (set-car! *disabled-picopasses* saved)
      res)))

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
(define (nanopass-find-matching-production-mode ir nt-name lang deep?)
  (let* ((nts (nanopass-lang-nonterminals lang))
         (try-nt
          (lambda (nt-entry)
            (let ((curr-nt (car nt-entry))
                  (prods (caddr nt-entry)))
              (let loop ((ps prods))
                (cond
                  ((null? ps) #f)
                  ((if deep?
                       (nanopass-production-matches? (car ps) ir lang curr-nt)
                       (nanopass-production-matches-shallow? (car ps) ir lang curr-nt))
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

(define (nanopass-find-matching-production ir nt-name lang)
  (nanopass-find-matching-production-mode ir nt-name lang #t))

(define (nanopass-find-matching-production-shallow ir nt-name lang)
  (nanopass-find-matching-production-mode ir nt-name lang #f))

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
                 (let ((sub-match (nanopass-find-matching-production-shallow val 'Def lang)))
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
           (let ((sub-match (nanopass-find-matching-production-shallow ir (cadr cls) lang)))
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
                (if (eq? (car ir) '%cont-fun)
                    (nanopass-fallback-transform-node ir call-recurse)
                    ;; Application / head meta-variable: (e0 e1 ...) or (a0 a ...)
                    (let ((new-head (if (eq? (car cls) 'nonterminal)
                                        (call-recurse (car ir))
                                        (car ir)))
                          (new-tail (nanopass-schema-transform-subforms (cdr prod) (cdr ir) lang curr-nt call-recurse)))
                      (nanopass-cons-sharing ir new-head new-tail)))
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
          ((set! define)
           (let* ((r1 (cdr ir))
                  (r2 (cdr r1))
                  (new-val (call-recurse (car r2)))
                  (new-r2 (nanopass-cons-sharing r2 new-val (cdr r2)))
                  (new-r1 (nanopass-cons-sharing r1 (car r1) new-r2)))
             (nanopass-cons-sharing ir op new-r1)))
          ((%cont-fun)
           (let* ((r1 (cdr ir))
                  (r2 (cdr r1))
                  (new-bodies (nanopass-map-sharing call-recurse (cdr r2)))
                  (new-r2 (nanopass-cons-sharing r2 (car r2) new-bodies))
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
           (let ((sub-match (nanopass-find-matching-production-shallow ir (cadr cls) lang)))
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
  (if (and (not (eq? lang-out '*))
           (or (ast-has-span? ir) (source-loc? ir)))
      (let ((span (ast-source-span ir))
            (inner (ast-strip-span ir)))
        (with-ast-span span
          (lambda ()
            (let ((res (nanopass-catamorphism-step lang-in lang-out nt-name inner recurse-fn extra-args extra-out)))
              (if (ast-has-span? res)
                  res
                  (ast-with-span res span))))))
      ;; Fast path for atomic IR nodes: avoid language lookup and closure allocation
      (if (not (pair? ir))
          (if (eq? lang-out '*)
              (if (and (pair? extra-args) (pair? extra-out))
                  (car (reverse extra-args))
                  #f)
              ir)
          (let ((extra-args (if (pair? extra-args) extra-args '()))
                (extra-out (if (pair? extra-out) extra-out '()))
                (lang (nanopass-lookup-language-opt lang-in)))
        (if (eq? lang-out '*)
            ;; Pure Analyzer mode
            (if (pair? extra-args)
                (let* ((rev-extra (reverse extra-args))
                       (initial-acc (car rev-extra))
                       (prefix (reverse (cdr rev-extra)))
                       (step-acc
                        (lambda (item cur-acc)
                          (nanopass-apply-list recurse-fn (cons item (append prefix (list cur-acc))))))
                       (matched (if lang (nanopass-find-matching-production-shallow ir nt-name lang) #f)))
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
                #f)
            ;; Transform mode: reconstruct AST according to shallow schema while propagating inherited attributes
            (let ((call-recurse
                   (if (null? extra-args)
                       (lambda (node)
                         (nanopass-memoize-step node recurse-fn))
                       (lambda (node)
                         (nanopass-apply-list recurse-fn (cons node extra-args))))))
              (let ((matched (if lang (nanopass-find-matching-production-shallow ir nt-name lang) #f)))
                (if matched
                    (nanopass-schema-transform-node (cdr matched) ir lang (car matched) call-recurse)
                    (nanopass-fallback-transform-node ir call-recurse)))))))))

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
                                   (else (loop (cdr ps) acc))))))
              diff-heads)
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
(define (nanopass-rev-prefix-until list-start stop-cell)
  (let loop ((p list-start) (acc '()))
    (if (or (null? p) (eq? p stop-cell))
        acc
        (loop (cdr p) (cons (car p) acc)))))

(define (nanopass-sliding-window-pass try-match-proc insts)
  (let loop ((rest insts)
             (acc '())
             (changed? #f)
             (step-fuel *nanopass-window-step-limit*))
    (cond
      ((null? rest)
       (if changed?
           (cons (reverse acc) #t)
           (cons insts #f)))
      ((<= step-fuel 0)
       (if changed?
           (cons (append (reverse acc) rest) #t)
           (cons insts #f)))
      (else
       (let ((m (try-match-proc rest)))
         (if (and (pair? m) (car m))
             (let ((new-suffix (cdr m)))
               (if (eq? new-suffix rest)
                   (loop (cdr rest) (if changed? (cons (car rest) acc) acc) changed? step-fuel)
                   (let ((cur-acc (if changed? acc (nanopass-rev-prefix-until insts rest))))
                     (loop new-suffix cur-acc #t (- step-fuel 1)))))
             (loop (cdr rest) (if changed? (cons (car rest) acc) acc) changed? step-fuel)))))))

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
        (if (eq? opt-insts insts)
            f
            (list '%lir-function lbl params frame-size (cons 'body opt-insts))))
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
        (if (eq? opt-insts insts)
            m
            (list '%lir-main frame-size (cons 'body opt-insts))))
      m))

;;; Optimize body instructions inside %asm-function (DSN-33-01 Task 5.3 / Issue #814)
(define (nanopass-optimize-asm-function-body opt-proc f)
  (if (and (pair? f) (eq? (car f) '%asm-function))
      (let* ((lbl (cadr f))
             (frame-size-entry (assq 'frame-size (cddr f)))
             (frame-size (if frame-size-entry (cadr frame-size-entry) 0))
             (body-clause (assq 'body (cddr f)))
             (insts (if body-clause (cdr body-clause) '()))
             (opt-insts (opt-proc insts)))
        (if (eq? opt-insts insts)
            f
            (list '%asm-function lbl (list 'frame-size frame-size) (cons 'body opt-insts))))
      f))

;;; Optimize body instructions inside %asm-main (DSN-33-01 Task 5.3 / Issue #814)
(define (nanopass-optimize-asm-main-body opt-proc m)
  (if (and (pair? m) (eq? (car m) '%asm-main))
      (let* ((frame-size-entry (assq 'frame-size (cdr m)))
             (frame-size (if frame-size-entry (cadr frame-size-entry) 0))
             (body-clause (assq 'body (cdr m)))
             (insts (if body-clause (cdr body-clause) '()))
             (opt-insts (opt-proc insts)))
        (if (eq? opt-insts insts)
            m
            (list '%asm-main (list 'frame-size frame-size) (cons 'body opt-insts))))
      m))

;;; Dual-mode wrapper: handles %lir-program / %asm-program, functions, main, or flat instruction lists
(define (nanopass-wrap-window-rules-input opt-proc ir)
  (cond
    ((and (pair? ir) (eq? (car ir) '%lir-program))
     (let* ((rest (cdr ir))
            (strings-entry (or (assq 'strings rest) '(strings ())))
            (data-entry (assq 'data rest))
            (stackmaps-entry (or (assq 'stackmaps rest) '(stackmaps ())))
            (functions-clause (or (assq '%lir-functions rest) '(%lir-functions)))
            (main-clause (or (assq '%lir-main rest) '(%lir-main (frame-size 0) (body))))
            (raw-funcs (if (and (pair? functions-clause) (eq? (car functions-clause) '%lir-functions))
                           (cdr functions-clause)
                           '()))
            (opt-funcs (map (lambda (f) (nanopass-optimize-function-body opt-proc f)) raw-funcs))
            (opt-main (nanopass-optimize-main-body opt-proc main-clause)))
       (if data-entry
           (list '%lir-program strings-entry data-entry stackmaps-entry (cons '%lir-functions opt-funcs) opt-main)
           (list '%lir-program strings-entry stackmaps-entry (cons '%lir-functions opt-funcs) opt-main))))
    ((and (pair? ir) (eq? (car ir) '%asm-program))
     (let* ((strings (assq 'strings (cdr ir)))
            (data-entry (assq 'data (cdr ir)))
            (stackmaps (assq 'stackmaps (cdr ir)))
            (funcs-entry (assq '%asm-functions (cdr ir)))
            (funcs (if funcs-entry (cdr funcs-entry) '()))
            (main-entry (assq '%asm-main (cdr ir)))
            (opt-funcs (map (lambda (f) (nanopass-optimize-asm-function-body opt-proc f)) funcs))
            (opt-main (if main-entry
                          (nanopass-optimize-asm-main-body opt-proc main-entry)
                          '(%asm-main (frame-size 0) (body ())))))
       (if data-entry
           (list '%asm-program
                 (if strings strings '(strings ()))
                 data-entry
                 (if stackmaps stackmaps '(stackmaps ()))
                 (cons '%asm-functions opt-funcs)
                 opt-main)
           (list '%asm-program
                 (if strings strings '(strings ()))
                 (if stackmaps stackmaps '(stackmaps ()))
                 (cons '%asm-functions opt-funcs)
                 opt-main))))
    ((and (pair? ir) (eq? (car ir) '%lir-function))
     (nanopass-optimize-function-body opt-proc ir))
    ((and (pair? ir) (eq? (car ir) '%asm-function))
     (nanopass-optimize-asm-function-body opt-proc ir))
    ((and (pair? ir) (eq? (car ir) '%lir-main))
     (nanopass-optimize-main-body opt-proc ir))
    ((and (pair? ir) (eq? (car ir) '%asm-main))
     (nanopass-optimize-asm-main-body opt-proc ir))
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

(define *femto-cache-bucket-count* 256)

(define (femto-make-cache-buckets)
  (make-vector *femto-cache-bucket-count* '()))

(define (femto-atom-hash x)
  (cond
    ((symbol? x) (symbol->hash-idx x))
    ((integer? x) (modulo (if (< x 0) (- 0 x) x) 256))
    ((boolean? x) (if x 3 7))
    ((null? x) 11)
    ((pair? x)
     (let ((a (car x)))
       (if (symbol? a) (+ 17 (symbol->hash-idx a)) 29)))
    (else 37)))

(define (femto-node-bucket-idx node)
  (if (pair? node)
      (let* ((a (car node))
             (d (cdr node))
             (h1 (femto-atom-hash a))
             (h2 (if (pair? d) (femto-atom-hash (car d)) 13))
             (h3 (if (and (pair? d) (pair? (cdr d))) (femto-atom-hash (cadr d)) 19)))
        (modulo (+ h1 (+ (* h2 37) (* h3 131))) *femto-cache-bucket-count*))
      (modulo (femto-atom-hash node) *femto-cache-bucket-count*)))

;; *femto-analysis-cache* stores (cons bucket-vector entry-count) for O(1) lookup and stats
(define *femto-analysis-cache* (cons (femto-make-cache-buckets) 0))
(define *femto-cache-stats* (cons 0 0)) ; (cons hits misses)
(define *femto-attr-tag-dependencies* (cons '() '())) ; alist of (attr-name . tag-list)

(define (femto-cache-reset!)
  (let ((tbl (car *femto-analysis-cache*)))
    (let loop ((i 0))
      (if (< i *femto-cache-bucket-count*)
          (begin
            (vector-set! tbl i '())
            (loop (+ i 1))))))
  (set-cdr! *femto-analysis-cache* 0)
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
  (let* ((tbl (car *femto-analysis-cache*))
         (b-idx (femto-node-bucket-idx node))
         (bucket (vector-ref tbl b-idx))
         (node-entry (assq node bucket)))
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
        (let* ((computed-val (compute-thunk))
               (cur-bucket (vector-ref tbl b-idx))
               (cur-entry (assq node cur-bucket)))
          (set-cdr! *femto-cache-stats* (+ (cdr *femto-cache-stats*) 1))
          (if cur-entry
              (set-cdr! cur-entry (cons (cons attr-name computed-val) (cdr cur-entry)))
              (begin
                (vector-set! tbl b-idx (cons (cons node (list (cons attr-name computed-val))) cur-bucket))
                (set-cdr! *femto-analysis-cache* (+ (cdr *femto-analysis-cache*) 1))))
          computed-val))))

(define (femto-filter-bucket-attrs nodes changed-tags deps)
  (let loop ((rem nodes) (acc '()))
    (if (null? rem)
        (reverse acc)
        (let* ((node-entry (car rem))
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
              (loop (cdr rem) acc)
              (loop (cdr rem) (cons (cons node surviving-attrs) acc)))))))

(define (femto-cache-invalidate-tags! changed-tags)
  (let ((tbl (car *femto-analysis-cache*)))
    (if (or (eq? changed-tags '*)
            (and (list? changed-tags) (memq '* changed-tags)))
        (begin
          (let loop ((i 0))
            (if (< i *femto-cache-bucket-count*)
                (begin
                  (vector-set! tbl i '())
                  (loop (+ i 1)))))
          (set-cdr! *femto-analysis-cache* 0))
        (let ((deps (car *femto-attr-tag-dependencies*)))
          (let loop ((i 0) (total 0))
            (if (>= i *femto-cache-bucket-count*)
                (set-cdr! *femto-analysis-cache* total)
                (let ((bucket (vector-ref tbl i)))
                  (if (null? bucket)
                      (loop (+ i 1) total)
                      (let ((new-bucket (femto-filter-bucket-attrs bucket changed-tags deps)))
                        (vector-set! tbl i new-bucket)
                        (loop (+ i 1) (+ total (length new-bucket))))))))))))

(define (femto-cache-invalidate-node! node)
  (let* ((tbl (car *femto-analysis-cache*))
         (b-idx (femto-node-bucket-idx node))
         (bucket (vector-ref tbl b-idx)))
    (if (assq node bucket)
        (begin
          (vector-set! tbl b-idx
                       (filter (lambda (entry) (not (eq? (car entry) node))) bucket))
          (set-cdr! *femto-analysis-cache* (max 0 (- (cdr *femto-analysis-cache*) 1)))))))

(define (femto-cache-stats)
  (list (cons 'hits (car *femto-cache-stats*))
        (cons 'misses (cdr *femto-cache-stats*))
        (cons 'entries (cdr *femto-analysis-cache*))))

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

;;; 14.2 Scoped Term DAG Catamorphism Memoization (256-bucket O(1) hash table)
(define *nanopass-term-memo-bucket-count* 256)
(define *nanopass-term-memo-bucket-limit* 16)

(define (nanopass-make-term-memo-table)
  (make-vector *nanopass-term-memo-bucket-count* '()))

;; *nanopass-term-memo* stores (cons bucket-vector entry-count) for O(1) stats reporting.
(define *nanopass-term-memo* (cons (nanopass-make-term-memo-table) 0))
(define *nanopass-term-memo-enabled?* (cons #t '()))
(define *nanopass-term-memo-active?* (cons #f '()))
(define *nanopass-term-memo-stats* (cons 0 0)) ; (cons hits misses)

(define (nanopass-atom-hash x)
  (cond
    ((symbol? x) (symbol->hash-idx x))
    ((integer? x) (modulo (if (< x 0) (- 0 x) x) 1024))
    ((boolean? x) (if x 3 7))
    ((char? x) (modulo (char->integer x) 1024))
    ((null? x) 11)
    ((pair? x)
     (let ((a (car x)))
       (cond
         ((symbol? a) (+ 17 (symbol->hash-idx a)))
         ((and (pair? a) (symbol? (car a))) (+ 41 (* (symbol->hash-idx (car a)) 7)))
         (else 29))))
    (else 37)))

(define (nanopass-term-memo-bucket-idx node)
  (let* ((a (car node))
         (d (cdr node))
         (h1 (nanopass-atom-hash a))
         (h2 (if (pair? d) (nanopass-atom-hash (car d)) 13))
         (h3 (if (and (pair? d) (pair? (cdr d)))
                 (nanopass-atom-hash (cadr d))
                 19)))
    (modulo (+ h1 (+ (* h2 37) (* h3 131))) *nanopass-term-memo-bucket-count*)))

(define (enable-nanopass-term-memo!)
  (set-car! *nanopass-term-memo-enabled?* #t))

(define (disable-nanopass-term-memo!)
  (set-car! *nanopass-term-memo-enabled?* #f))

(define (nanopass-term-memo-reset!)
  (let ((tbl (car *nanopass-term-memo*)))
    (let loop ((i 0))
      (if (< i *nanopass-term-memo-bucket-count*)
          (begin
            (vector-set! tbl i '())
            (loop (+ i 1))))))
  (set-cdr! *nanopass-term-memo* 0)
  (set-car! *nanopass-term-memo-stats* 0)
  (set-cdr! *nanopass-term-memo-stats* 0))

(define (nanopass-term-memo-stats)
  (list (cons 'hits (car *nanopass-term-memo-stats*))
        (cons 'misses (cdr *nanopass-term-memo-stats*))
        (cons 'entries (cdr *nanopass-term-memo*))))

(define (nanopass-term-memo-hit-rate)
  (let ((hits (car *nanopass-term-memo-stats*))
        (misses (cdr *nanopass-term-memo-stats*)))
    (let ((total (+ hits misses)))
      (if (= total 0)
          0
          (quotient (* hits 100) total)))))

(define (with-nanopass-term-memo thunk)
  (let ((old-memo (car *nanopass-term-memo*))
        (old-count (cdr *nanopass-term-memo*))
        (old-active (car *nanopass-term-memo-active?*)))
    (set-car! *nanopass-term-memo* (nanopass-make-term-memo-table))
    (set-cdr! *nanopass-term-memo* 0)
    (set-car! *nanopass-term-memo-active?* #t)
    (let ((res (guard (ex (else
                            (set-car! *nanopass-term-memo* old-memo)
                            (set-cdr! *nanopass-term-memo* old-count)
                            (set-car! *nanopass-term-memo-active?* old-active)
                            (raise ex)))
                 (thunk))))
      (set-car! *nanopass-term-memo* old-memo)
      (set-cdr! *nanopass-term-memo* old-count)
      (set-car! *nanopass-term-memo-active?* old-active)
      res)))

(define (nanopass-memoize-step node transform-fn)
  (if (or (not (car *nanopass-term-memo-enabled?*))
          (not (car *nanopass-term-memo-active?*))
          (not (pair? node)))
      (transform-fn node)
      (let* ((tbl (car *nanopass-term-memo*))
             (b-idx (nanopass-term-memo-bucket-idx node))
             (bucket (vector-ref tbl b-idx))
             (hit (assq node bucket)))
        (if hit
            (begin
              (set-car! *nanopass-term-memo-stats* (+ (car *nanopass-term-memo-stats*) 1))
              (cdr hit))
            (begin
              (set-cdr! *nanopass-term-memo-stats* (+ (cdr *nanopass-term-memo-stats*) 1))
              (let* ((res (transform-fn node))
                     (cur-bucket (vector-ref tbl b-idx)))
                ;; Bound per-bucket chain depth so worst-case lookup stays O(1) on large ASTs.
                (if (< (length cur-bucket) *nanopass-term-memo-bucket-limit*)
                    (begin
                      (vector-set! tbl b-idx (cons (cons node res) cur-bucket))
                      (set-cdr! *nanopass-term-memo* (+ (cdr *nanopass-term-memo*) 1)))
                    (let loop ((cur cur-bucket) (i 1) (acc '()))
                      (if (or (null? cur) (>= i *nanopass-term-memo-bucket-limit*))
                          (vector-set! tbl b-idx (cons (cons node res) (reverse acc)))
                          (loop (cdr cur) (+ i 1) (cons (car cur) acc)))))
                res))))))

;;; =======================================================================
;;; Part 15: LIR Basic Block Data Dependency DAG & Reaching Store Forwarding (DSN-33-01 T5.3)
;;; =======================================================================

(define (lir-peephole-reg? opnd)
  (and (symbol? opnd)
       (case opnd
         ((%rax %rcx %rdx %rbx %rsp %rbp %rsi %rdi
           %r8 %r9 %r10 %r11 %r12 %r13 %r14 %r15)
          #t)
         (else
          (let ((s (symbol->string opnd)))
            (and (> (string-length s) 1)
                 (char=? (string-ref s 0) #\%)))))))

(define (lir-unconditional-terminator? inst)
  (and (pair? inst)
       (memq (car inst) '(%jump %direct-jump %return))))

(define (lir-label-inst? inst)
  (and (pair? inst)
       (memq (car inst) '(%label %block))))

(define (lir-reg-aliases? r1 r2)
  (or (equal? r1 r2)
      (and (eq? (current-target-arch) 'aarch64)
           (or (and (memq r1 '(%rax %rdi %al)) (memq r2 '(%rax %rdi %al)))
               (and (memq r1 '(%rbx %r12)) (memq r2 '(%rbx %r12)))))))

;;; -----------------------------------------------------------------------
;;; Shared %inline-asm Clause & Constraint Helpers (Issue #838)
;;; -----------------------------------------------------------------------
(define (inline-asm-inst? inst)
  (and (pair? inst) (eq? (car inst) '%inline-asm)))

(define (inline-asm-string-downcase s)
  (let* ((len (string-length s))
         (out (make-string len)))
    (let loop ((i 0))
      (if (< i len)
          (let* ((ch (string-ref s i))
                 (code (char->integer ch)))
            (string-set! out i
                         (if (and (>= code 65) (<= code 90))
                             (integer->char (+ code 32))
                             ch))
            (loop (+ i 1)))
          out))))

(define (inline-asm-parse-uint s)
  (let ((len (string-length s)))
    (if (= len 0)
        #f
        (let loop ((i 0) (acc 0))
          (if (= i len)
              acc
              (let ((c (char->integer (string-ref s i))))
                (if (and (>= c 48) (<= c 57))
                    (loop (+ i 1) (+ (* acc 10) (- c 48)))
                    #f)))))))

(define (inline-asm-normalize-reg-sym s)
  (cond
    ((and (pair? s) (eq? (car s) '%reg))
     (if (and (pair? (cdr s)) (pair? (cddr s)))
         (inline-asm-normalize-reg-sym (caddr s))
         (inline-asm-normalize-reg-sym (cadr s))))
    ((or (symbol? s) (string? s))
     (let* ((raw (inline-asm-string-downcase (if (symbol? s) (symbol->string s) s)))
            (len (string-length raw))
            (clean (if (and (> len 0) (char=? (string-ref raw 0) #\%))
                       (substring raw 1 len)
                       raw)))
       (cond
         ((or (string=? clean "rax") (string=? clean "eax") (string=? clean "ax") (string=? clean "al")) '%rax)
         ((or (string=? clean "rbx") (string=? clean "ebx") (string=? clean "bx") (string=? clean "bl")) '%rbx)
         ((or (string=? clean "rcx") (string=? clean "ecx") (string=? clean "cx") (string=? clean "cl")) '%rcx)
         ((or (string=? clean "rdx") (string=? clean "edx") (string=? clean "dx") (string=? clean "dl")) '%rdx)
         ((or (string=? clean "rsi") (string=? clean "esi") (string=? clean "si") (string=? clean "sil")) '%rsi)
         ((or (string=? clean "rdi") (string=? clean "edi") (string=? clean "di") (string=? clean "dil")) '%rdi)
         ((or (string=? clean "rbp") (string=? clean "ebp") (string=? clean "bp") (string=? clean "bpl")) '%rbp)
         ((or (string=? clean "rsp") (string=? clean "esp") (string=? clean "sp") (string=? clean "spl")) '%rsp)
         ((or (string=? clean "r8")  (string=? clean "r8d")  (string=? clean "r8w")  (string=? clean "r8b"))  '%r8)
         ((or (string=? clean "r9")  (string=? clean "r9d")  (string=? clean "r9w")  (string=? clean "r9b"))  '%r9)
         ((or (string=? clean "r10") (string=? clean "r10d") (string=? clean "r10w") (string=? clean "r10b")) '%r10)
         ((or (string=? clean "r11") (string=? clean "r11d") (string=? clean "r11w") (string=? clean "r11b")) '%r11)
         ((or (string=? clean "r12") (string=? clean "r12d") (string=? clean "r12w") (string=? clean "r12b")) '%r12)
         ((or (string=? clean "r13") (string=? clean "r13d") (string=? clean "r13w") (string=? clean "r13b")) '%r13)
         ((or (string=? clean "r14") (string=? clean "r14d") (string=? clean "r14w") (string=? clean "r14b")) '%r14)
         ((or (string=? clean "r15") (string=? clean "r15d") (string=? clean "r15w") (string=? clean "r15b")) '%r15)
         ((string=? clean "xmm0") '%xmm0) ((string=? clean "xmm1") '%xmm1)
         ((string=? clean "xmm2") '%xmm2) ((string=? clean "xmm3") '%xmm3)
         ((string=? clean "xmm4") '%xmm4) ((string=? clean "xmm5") '%xmm5)
         ((string=? clean "xmm6") '%xmm6) ((string=? clean "xmm7") '%xmm7)
         ((string=? clean "xmm8") '%xmm8) ((string=? clean "xmm9") '%xmm9)
         ((string=? clean "xmm10") '%xmm10) ((string=? clean "xmm11") '%xmm11)
         ((string=? clean "xmm12") '%xmm12) ((string=? clean "xmm13") '%xmm13)
         ((string=? clean "xmm14") '%xmm14) ((string=? clean "xmm15") '%xmm15)
         (else #f))))
    (else #f)))

(define (inline-asm-parse-braced-reg s)
  (let ((len (string-length s)))
    (if (and (>= len 3)
             (char=? (string-ref s 0) #\{)
             (char=? (string-ref s (- len 1)) #\}))
        (inline-asm-normalize-reg-sym (substring s 1 (- len 1)))
        #f)))

(define (inline-asm-parse-short-reg s)
  (cond
    ((string=? s "a") '%rax)
    ((string=? s "b") '%rbx)
    ((string=? s "c") '%rcx)
    ((string=? s "d") '%rdx)
    ((string=? s "S") '%rsi)
    ((string=? s "D") '%rdi)
    (else #f)))

(define (inline-asm-parse-output-constraint cstr)
  (if (not (and (string? cstr) (>= (string-length cstr) 2)))
      #f
      (let* ((c0 (string-ref cstr 0))
             (valid-prefix? (or (char=? c0 #\=) (char=? c0 #\+))))
        (if (not valid-prefix?)
            #f
            (let* ((rw? (char=? c0 #\+))
                   (raw-body (substring cstr 1 (string-length cstr)))
                   (body (if (and (> (string-length raw-body) 0)
                                  (char=? (string-ref raw-body 0) #\&))
                             (substring raw-body 1 (string-length raw-body))
                             raw-body))
                   (short-r (inline-asm-parse-short-reg body))
                   (braced-r (inline-asm-parse-braced-reg body)))
              (cond
                ((or (string=? body "r") (string=? body "q")) (list '=any-reg rw?))
                ((string=? body "m") (list '=mem rw?))
                (short-r (list '=reg short-r rw?))
                (braced-r (list '=reg braced-r rw?))
                (else #f)))))))

(define (inline-asm-parse-input-constraint cstr num-outputs)
  (if (not (and (string? cstr) (>= (string-length cstr) 1)))
      #f
      (let ((short-r (inline-asm-parse-short-reg cstr))
            (braced-r (inline-asm-parse-braced-reg cstr))
            (tied-idx (inline-asm-parse-uint cstr)))
        (cond
          ((or (string=? cstr "r") (string=? cstr "q")
               (string=? cstr "ri") (string=? cstr "ir") (string=? cstr "r,i"))
           '(any-reg))
          ((string=? cstr "m") '(mem))
          ((or (string=? cstr "i") (string=? cstr "n")
               (string=? cstr "I") (string=? cstr "J") (string=? cstr "K"))
           '(imm))
          (short-r (list 'reg short-r))
          (braced-r (list 'reg braced-r))
          ((and tied-idx (< tied-idx num-outputs)) (list 'tied tied-idx))
          (else #f)))))

(define (inline-asm-parse-clobber item)
  (if (not (or (string? item) (symbol? item)))
      #f
      (let ((low (inline-asm-string-downcase (if (symbol? item) (symbol->string item) item))))
        (cond
          ((or (string=? low "cc") (string=? low "flags")) 'cc)
          ((string=? low "memory") 'memory)
          (else (inline-asm-normalize-reg-sym low))))))

(define (inline-asm-normalize-out-entry entry)
  (cond
    ((not (pair? entry)) #f)
    ((and (pair? (cdr entry)) (null? (cddr entry)))
     (list #f (car entry) (cadr entry)))
    ((and (pair? (cdr entry)) (pair? (cddr entry)) (null? (cdddr entry)))
     (list (car entry) (caddr entry) (cadr entry)))
    (else #f)))

(define (inline-asm-normalize-in-entry entry)
  (cond
    ((not (pair? entry)) #f)
    ((and (pair? (cdr entry)) (null? (cddr entry)))
     (list #f (car entry) (cadr entry)))
    ((and (pair? (cdr entry)) (pair? (cddr entry)) (null? (cdddr entry)))
     (list (car entry) (caddr entry) (cadr entry)))
    (else #f)))

(define (inline-asm-extract-clauses inst)
  (let ((template (if (pair? (cdr inst)) (cadr inst) ""))
        (clauses (if (pair? (cdr inst)) (cddr inst) '())))
    (let loop ((cs clauses) (outputs '()) (inputs '()) (clobbers '()) (volatile? #t))
      (if (null? cs)
          (list template outputs inputs clobbers volatile?)
          (let ((c (car cs)))
            (if (not (pair? c))
                (loop (cdr cs) outputs inputs clobbers volatile?)
                (case (car c)
                  ((:outputs)
                   (loop (cdr cs)
                         (if (and (pair? (cdr c)) (list? (cadr c))) (cadr c) outputs)
                         inputs clobbers volatile?))
                  ((:inputs)
                   (loop (cdr cs)
                         outputs
                         (if (and (pair? (cdr c)) (list? (cadr c))) (cadr c) inputs)
                         clobbers volatile?))
                  ((:clobbers)
                   (loop (cdr cs)
                         outputs inputs
                         (if (and (pair? (cdr c)) (list? (cadr c))) (cadr c) clobbers)
                         volatile?))
                  ((:volatile?)
                   (loop (cdr cs)
                         outputs inputs clobbers
                         (if (pair? (cdr c)) (cadr c) volatile?)))
                  (else
                   (loop (cdr cs) outputs inputs clobbers volatile?)))))))))

(define (lir-inline-asm-defines-reg? inst reg)
  (let* ((parsed (inline-asm-extract-clauses inst))
         (outs (cadr parsed))
         (ins (caddr parsed))
         (clobs (cadddr parsed))
         (num-outs (length outs)))
    (or
     (let oloop ((os outs))
       (if (null? os) #f
           (let ((no (inline-asm-normalize-out-entry (car os))))
             (if (not no)
                 (oloop (cdr os))
                 (let ((dst (cadr no))
                       (oc (inline-asm-parse-output-constraint (caddr no))))
                   (if (or (lir-reg-aliases? dst reg)
                           (and (symbol? reg)
                                (let ((nr (inline-asm-normalize-reg-sym dst)))
                                  (and nr (lir-reg-aliases? nr reg))))
                           (and oc (eq? (car oc) '=reg) (lir-reg-aliases? (cadr oc) reg)))
                       #t
                       (oloop (cdr os))))))))
     (let iloop ((is ins))
       (if (null? is) #f
           (let ((ni (inline-asm-normalize-in-entry (car is))))
             (if (not ni)
                 (iloop (cdr is))
                 (let ((ic (inline-asm-parse-input-constraint (caddr ni) num-outs)))
                   (if (and ic (eq? (car ic) 'reg) (lir-reg-aliases? (cadr ic) reg))
                       #t
                       (iloop (cdr is))))))))
     (let cloop ((cs clobs))
       (if (null? cs) #f
           (let ((cp (inline-asm-parse-clobber (car cs))))
             (if (and cp (not (eq? cp 'cc)) (not (eq? cp 'memory)) (lir-reg-aliases? cp reg))
                 #t
                 (cloop (cdr cs)))))))))

(define (lir-inline-asm-memory-barrier? inst)
  (let* ((parsed (inline-asm-extract-clauses inst))
         (outs (cadr parsed))
         (ins (caddr parsed))
         (clobs (cadddr parsed))
         (volatile? (car (cddddr parsed)))
         (num-outs (length outs)))
    (or volatile?
        (let cloop ((cs clobs))
          (cond ((null? cs) #f)
                ((eq? (inline-asm-parse-clobber (car cs)) 'memory) #t)
                (else (cloop (cdr cs)))))
        (let oloop ((os outs))
          (if (null? os) #f
              (let* ((no (inline-asm-normalize-out-entry (car os)))
                     (oc (and no (inline-asm-parse-output-constraint (caddr no)))))
                (if (and oc (eq? (car oc) '=mem)) #t (oloop (cdr os))))))
        (let iloop ((is ins))
          (if (null? is) #f
              (let* ((ni (inline-asm-normalize-in-entry (car is)))
                     (ic (and ni (inline-asm-parse-input-constraint (caddr ni) num-outs))))
                (if (and ic (eq? (car ic) 'mem)) #t (iloop (cdr is)))))))))

(define (inline-asm-canonical-gpr opnd)
  (let ((direct (inline-asm-normalize-reg-sym opnd)))
    (if direct
        direct
        (if (and (pair? opnd) (eq? (car opnd) '%reg) (pair? (cdr opnd)))
            (inline-asm-normalize-reg-sym (cadr opnd))
            #f))))

(define (inline-asm-collect-mem-bases opnd acc)
  (if (and (pair? opnd) (eq? (car opnd) '%mem) (pair? (cdr opnd)))
      (let ((br (inline-asm-canonical-gpr (cadr opnd))))
        (if (and br (not (eq? br '%rsp)) (not (memq br acc)))
            (cons br acc)
            acc))
      acc))

(define (inline-asm-gpr-pool)
  '(%r10 %r11 %rax %rcx %rdx %rsi %rdi %r8 %r9 %rbx %r13 %r14 %rbp %r15 %r12))

(define (inline-asm-first-free-gpr used)
  (let loop ((pool (inline-asm-gpr-pool)))
    (cond
      ((null? pool) #f)
      ((memq (car pool) used) (loop (cdr pool)))
      (else (car pool)))))

(define (inline-asm-dedup-regs regs)
  (let loop ((rs regs) (acc '()))
    (if (null? rs)
        (reverse acc)
        (let ((r (car rs)))
          (if (or (not (symbol? r)) (eq? r '%rsp) (memq r acc))
              (loop (cdr rs) acc)
              (loop (cdr rs) (cons r acc)))))))

;; Allocates physical carrier registers for %inline-asm operands.
;; Returns (list template out-plans in-plans clobbers volatile? used-regs),
;; where each out-plan is (list idx name dst rw? kind carrier raw-cstr)
;; and each in-plan is (list opnd-idx name src kind carrier tied-out-idx raw-cstr).
(define (inline-asm-allocate-plan inst)
  (let* ((parsed (inline-asm-extract-clauses inst))
         (template (car parsed))
         (outs (cadr parsed))
         (ins (caddr parsed))
         (raw-clobs (cadddr parsed))
         (volatile? (car (cddddr parsed)))
         (num-outs (length outs))
         (clobbers
          (let cloop ((cs raw-clobs) (acc '()))
            (if (null? cs)
                (reverse acc)
                (let ((cp (inline-asm-parse-clobber (car cs))))
                  (if cp (cloop (cdr cs) (cons cp acc)) (cloop (cdr cs) acc))))))
         (init-reserved
          (let loop-c ((cs clobbers)
                       (res (let loop-o ((os outs) (acc '()))
                              (if (null? os) acc
                                  (let ((no (inline-asm-normalize-out-entry (car os))))
                                    (if (not no)
                                        (loop-o (cdr os) acc)
                                        (let* ((dst (cadr no))
                                               (oc (inline-asm-parse-output-constraint (caddr no)))
                                               (acc1 (inline-asm-collect-mem-bases dst acc)))
                                          (if (and oc (eq? (car oc) '=reg) (not (memq (cadr oc) acc1)))
                                              (loop-o (cdr os) (cons (cadr oc) acc1))
                                              (loop-o (cdr os) acc1)))))))))
            (if (null? cs)
                (let loop-i ((is ins) (acc res))
                  (if (null? is) acc
                      (let ((ni (inline-asm-normalize-in-entry (car is))))
                        (if (not ni)
                            (loop-i (cdr is) acc)
                            (let* ((src (cadr ni))
                                   (ic (inline-asm-parse-input-constraint (caddr ni) num-outs))
                                   (acc1 (inline-asm-collect-mem-bases src acc)))
                              (if (and ic (eq? (car ic) 'reg) (not (memq (cadr ic) acc1)))
                                  (loop-i (cdr is) (cons (cadr ic) acc1))
                                  (loop-i (cdr is) acc1)))))))
                (let ((c (car cs)))
                  (if (and (symbol? c) (not (eq? c 'cc)) (not (eq? c 'memory)) (not (memq c res)))
                      (loop-c (cdr cs) (cons c res))
                      (loop-c (cdr cs) res))))))
         (out-res
          (let oloop ((os outs) (idx 0) (used init-reserved) (acc '()))
            (if (null? os)
                (cons (reverse acc) used)
                (let* ((no (inline-asm-normalize-out-entry (car os)))
                       (name (and no (car no)))
                       (dst (and no (cadr no)))
                       (cstr (if no (caddr no) "=r"))
                       (oc (inline-asm-parse-output-constraint cstr)))
                  (cond
                    ((not oc)
                     (error "Malformed output constraint in %inline-asm plan:" cstr))
                    ((eq? (car oc) '=reg)
                     (let* ((r (cadr oc))
                            (rw? (caddr oc))
                            (new-used (if (memq r used) used (cons r used))))
                       (oloop (cdr os) (+ idx 1) new-used
                              (cons (list idx name dst rw? 'reg r cstr) acc))))
                    ((eq? (car oc) '=mem)
                     (oloop (cdr os) (+ idx 1) used
                            (cons (list idx name dst (cadr oc) 'mem dst cstr) acc)))
                    (else
                     (let* ((rw? (cadr oc))
                            (r (inline-asm-first-free-gpr used)))
                       (if (not r)
                           (error "Exhausted GPRs allocating %inline-asm output:" inst)
                           (oloop (cdr os) (+ idx 1) (cons r used)
                                  (cons (list idx name dst rw? 'reg r cstr) acc))))))))))
         (out-plans (car out-res))
         (used-after-outs (cdr out-res))
         (in-res
          (let iloop ((is ins) (idx num-outs) (used used-after-outs) (acc '()))
            (if (null? is)
                (cons (reverse acc) used)
                (let* ((ni (inline-asm-normalize-in-entry (car is)))
                       (name (and ni (car ni)))
                       (src (and ni (cadr ni)))
                       (cstr (if ni (caddr ni) "r"))
                       (ic (inline-asm-parse-input-constraint cstr num-outs)))
                  (cond
                    ((not ic)
                     (error "Malformed input constraint in %inline-asm plan:" cstr))
                    ((eq? (car ic) 'reg)
                     (let* ((r (cadr ic))
                            (new-used (if (memq r used) used (cons r used))))
                       (iloop (cdr is) (+ idx 1) new-used
                              (cons (list idx name src 'reg r #f cstr) acc))))
                    ((eq? (car ic) 'mem)
                     (iloop (cdr is) (+ idx 1) used
                            (cons (list idx name src 'mem src #f cstr) acc)))
                    ((eq? (car ic) 'imm)
                     (iloop (cdr is) (+ idx 1) used
                            (cons (list idx name src 'imm src #f cstr) acc)))
                    ((eq? (car ic) 'tied)
                     (let* ((t-idx (cadr ic))
                            (target-out (list-ref out-plans t-idx))
                            (t-kind (list-ref target-out 4))
                            (t-carrier (list-ref target-out 5)))
                       (iloop (cdr is) (+ idx 1) used
                              (cons (list idx name src 'tied
                                          (if (eq? t-kind 'reg) t-carrier (list-ref target-out 2))
                                          t-idx cstr)
                                    acc))))
                    (else
                     (let ((r (inline-asm-first-free-gpr used)))
                       (if (not r)
                           (error "Exhausted GPRs allocating %inline-asm input:" inst)
                           (iloop (cdr is) (+ idx 1) (cons r used)
                                  (cons (list idx name src 'reg r #f cstr) acc))))))))))
         (in-plans (car in-res))
         (all-used (inline-asm-dedup-regs
                    (append
                     (let collect-out ((ops out-plans) (acc '()))
                       (if (null? ops) acc
                           (if (eq? (list-ref (car ops) 4) 'reg)
                               (collect-out (cdr ops) (cons (list-ref (car ops) 5) acc))
                               (collect-out (cdr ops) acc))))
                     (append
                      (let collect-in ((ips in-plans) (acc '()))
                        (if (null? ips) acc
                            (let ((k (list-ref (car ips) 3))
                                  (c (list-ref (car ips) 4)))
                              (if (and (or (eq? k 'reg) (eq? k 'tied))
                                       (inline-asm-normalize-reg-sym c))
                                  (collect-in (cdr ips) (cons c acc))
                                  (collect-in (cdr ips) acc)))))
                      (let collect-clob ((cs clobbers) (acc '()))
                        (if (null? cs) acc
                            (if (and (symbol? (car cs)) (not (eq? (car cs) 'cc)) (not (eq? (car cs) 'memory)))
                                (collect-clob (cdr cs) (cons (car cs) acc))
                                (collect-clob (cdr cs) acc)))))))))
    (list template out-plans in-plans clobbers volatile? all-used)))

(define (inline-asm-reg->sized-str reg mod-ch)
  (let ((nr (inline-asm-normalize-reg-sym reg)))
    (if (not nr)
        (if (symbol? reg) (symbol->string reg) "rax")
        (cond
          ((or (not mod-ch) (char=? mod-ch #\q) (char=? mod-ch #\c) (char=? mod-ch #\n))
           (case nr
             ((%rax) "rax") ((%rbx) "rbx") ((%rcx) "rcx") ((%rdx) "rdx")
             ((%rsi) "rsi") ((%rdi) "rdi") ((%rbp) "rbp") ((%rsp) "rsp")
             ((%r8) "r8")   ((%r9) "r9")   ((%r10) "r10") ((%r11) "r11")
             ((%r12) "r12") ((%r13) "r13") ((%r14) "r14") ((%r15) "r15")
             (else (let ((s (symbol->string nr)))
                     (if (and (> (string-length s) 0) (char=? (string-ref s 0) #\%))
                         (substring s 1 (string-length s))
                         s)))))
          ((char=? mod-ch #\k)
           (case nr
             ((%rax) "eax") ((%rbx) "ebx") ((%rcx) "ecx") ((%rdx) "edx")
             ((%rsi) "esi") ((%rdi) "edi") ((%rbp) "ebp") ((%rsp) "esp")
             ((%r8) "r8d")  ((%r9) "r9d")  ((%r10) "r10d") ((%r11) "r11d")
             ((%r12) "r12d") ((%r13) "r13d") ((%r14) "r14d") ((%r15) "r15d")
             (else "eax")))
          ((char=? mod-ch #\w)
           (case nr
             ((%rax) "ax")  ((%rbx) "bx")  ((%rcx) "cx")  ((%rdx) "dx")
             ((%rsi) "si")  ((%rdi) "di")  ((%rbp) "bp")  ((%rsp) "sp")
             ((%r8) "r8w")  ((%r9) "r9w")  ((%r10) "r10w") ((%r11) "r11w")
             ((%r12) "r12w") ((%r13) "r13w") ((%r14) "r14w") ((%r15) "r15w")
             (else "ax")))
          ((or (char=? mod-ch #\b) (char=? mod-ch #\l))
           (case nr
             ((%rax) "al")  ((%rbx) "bl")  ((%rcx) "cl")  ((%rdx) "dl")
             ((%rsi) "sil") ((%rdi) "dil") ((%rbp) "bpl") ((%rsp) "spl")
             ((%r8) "r8b")  ((%r9) "r9b")  ((%r10) "r10b") ((%r11) "r11b")
             ((%r12) "r12b") ((%r13) "r13b") ((%r14) "r14b") ((%r15) "r15b")
             (else "al")))
          ((char=? mod-ch #\h)
           (case nr
             ((%rax) "ah") ((%rbx) "bh") ((%rcx) "ch") ((%rdx) "dh")
             (else (inline-asm-reg->sized-str nr #\b))))
          (else (inline-asm-reg->sized-str nr #f))))))

(define (inline-asm-format-mem-opnd opnd mod-ch mem-ptr-map idx)
  (let* ((ptr-entry (and mem-ptr-map (assv idx mem-ptr-map)))
         (size-prefix
          (cond
            ((not mod-ch) "")
            ((char=? mod-ch #\b) "byte ptr ")
            ((char=? mod-ch #\l) "byte ptr ")
            ((char=? mod-ch #\w) "word ptr ")
            ((char=? mod-ch #\k) "dword ptr ")
            ((char=? mod-ch #\q) "qword ptr ")
            (else ""))))
    (if ptr-entry
        (string-append size-prefix "[" (inline-asm-reg->sized-str (cdr ptr-entry) #f) "]")
        (let* ((base (if (and (pair? opnd) (eq? (car opnd) '%stack)) '%rsp (cadr opnd)))
               (off (if (and (pair? opnd) (eq? (car opnd) '%stack)) (cadr opnd) (caddr opnd)))
               (base-str (inline-asm-reg->sized-str base #f))
               (off-str (cond
                          ((integer? off)
                           (cond
                             ((= off 0) "")
                             ((> off 0) (string-append " + " (number->string off)))
                             (else (string-append " - " (number->string (- 0 off))))))
                          ((symbol? off) (string-append " + " (symbol->string off)))
                          (else ""))))
          (string-append size-prefix "[" base-str off-str "]")))))

(define (inline-asm-format-operand-by-idx idx mod-ch out-plans in-plans mem-ptr-map)
  (let ((num-outs (length out-plans)))
    (if (< idx num-outs)
        (let* ((op (list-ref out-plans idx))
               (kind (list-ref op 4))
               (carrier (list-ref op 5)))
          (if (eq? kind 'reg)
              (inline-asm-reg->sized-str carrier mod-ch)
              (inline-asm-format-mem-opnd (list-ref op 2) mod-ch mem-ptr-map idx)))
        (let* ((ip (list-ref in-plans (- idx num-outs)))
               (kind (list-ref ip 3))
               (carrier (list-ref ip 4)))
          (case kind
            ((reg) (inline-asm-reg->sized-str carrier mod-ch))
            ((imm) (number->string (if (integer? carrier) carrier 0)))
            ((mem) (inline-asm-format-mem-opnd (list-ref ip 2) mod-ch mem-ptr-map idx))
            ((tied)
             (let ((t-idx (list-ref ip 5)))
               (inline-asm-format-operand-by-idx t-idx mod-ch out-plans in-plans mem-ptr-map)))
            (else "0"))))))

(define (inline-asm-find-named-idx nm out-plans in-plans)
  (let oloop ((ops out-plans))
    (if (not (null? ops))
        (if (eq? (list-ref (car ops) 1) nm)
            (list-ref (car ops) 0)
            (oloop (cdr ops)))
        (let iloop ((ips in-plans))
          (if (null? ips)
              #f
              (if (eq? (list-ref (car ips) 1) nm)
                  (list-ref (car ips) 0)
                  (iloop (cdr ips))))))))

(define (inline-asm-alnum? ch)
  (or (and (char>=? ch #\0) (char<=? ch #\9))
      (and (char>=? ch #\a) (char<=? ch #\z))
      (and (char>=? ch #\A) (char<=? ch #\Z))))

(define (inline-asm-match-reg-token str start)
  (let ((len (string-length str)))
    (let scan ((j start))
      (if (and (< j len) (inline-asm-alnum? (string-ref str j)))
          (scan (+ j 1))
          (if (> j start)
              (let ((tok (substring str start j)))
                (if (inline-asm-normalize-reg-sym tok) tok #f))
              #f)))))

;; Expands %inline-asm template placeholders.
;; mode: 'x86 (%% -> % for literal, %%reg -> reg) or 'c (%% -> %% for literal, %%reg -> reg).
(define (inline-asm-expand-template template out-plans in-plans mode mem-ptr-map)
  (let ((len (string-length template)))
    (let loop ((i 0) (acc '()))
      (if (>= i len)
          (let join ((xs (reverse acc)) (res ""))
            (if (null? xs) res (join (cdr xs) (string-append res (car xs)))))
          (let ((ch (string-ref template i)))
            (if (not (char=? ch #\%))
                (let scan-plain ((j (+ i 1)))
                  (if (and (< j len) (not (char=? (string-ref template j) #\%)))
                      (scan-plain (+ j 1))
                      (loop j (cons (substring template i j) acc))))
                (let ((c1 (if (< (+ i 1) len) (string-ref template (+ i 1)) #\space)))
                  (cond
                    ((char=? c1 #\%)
                     (let ((reg-tok (inline-asm-match-reg-token template (+ i 2))))
                       (if reg-tok
                           (loop (+ (+ i 2) (string-length reg-tok))
                                 (cons (inline-asm-string-downcase reg-tok) acc))
                           (loop (+ i 2)
                                 (cons (if (eq? mode 'c) "%%" "%") acc)))))
                    ((char=? c1 #\[)
                     (let find-close ((j (+ i 2)))
                       (if (or (>= j len) (char=? (string-ref template j) #\]))
                           (let* ((nm-str (if (< (+ i 2) j) (substring template (+ i 2) j) ""))
                                  (idx (inline-asm-find-named-idx (string->symbol nm-str) out-plans in-plans))
                                  (repl (if idx
                                            (inline-asm-format-operand-by-idx idx #f out-plans in-plans mem-ptr-map)
                                            (string-append "%[" nm-str "]"))))
                             (loop (if (< j len) (+ j 1) j) (cons repl acc)))
                           (find-close (+ j 1)))))
                    ((and (char>=? c1 #\0) (char<=? c1 #\9))
                     (let scan-idx ((j (+ i 1)) (idx 0))
                       (if (and (< j len) (char>=? (string-ref template j) #\0) (char<=? (string-ref template j) #\9))
                           (scan-idx (+ j 1) (+ (* idx 10) (- (char->integer (string-ref template j)) 48)))
                           (loop j (cons (inline-asm-format-operand-by-idx idx #f out-plans in-plans mem-ptr-map) acc)))))
                    ((and (< (+ i 2) len)
                          (memv c1 '(#\b #\w #\k #\q #\h #\l #\c #\n))
                          (let ((c2 (string-ref template (+ i 2))))
                            (or (and (char>=? c2 #\0) (char<=? c2 #\9))
                                (char=? c2 #\[))))
                     (if (char=? (string-ref template (+ i 2)) #\[)
                         (let find-close2 ((j (+ i 3)))
                           (if (or (>= j len) (char=? (string-ref template j) #\]))
                               (let* ((nm-str (if (< (+ i 3) j) (substring template (+ i 3) j) ""))
                                      (idx (inline-asm-find-named-idx (string->symbol nm-str) out-plans in-plans))
                                      (repl (if idx
                                                (inline-asm-format-operand-by-idx idx c1 out-plans in-plans mem-ptr-map)
                                                (string-append "%" (string c1) "[" nm-str "]"))))
                                 (loop (if (< j len) (+ j 1) j) (cons repl acc)))
                               (find-close2 (+ j 1))))
                         (let scan-idx2 ((j (+ i 2)) (idx 0))
                           (if (and (< j len) (char>=? (string-ref template j) #\0) (char<=? (string-ref template j) #\9))
                               (scan-idx2 (+ j 1) (+ (* idx 10) (- (char->integer (string-ref template j)) 48)))
                               (loop j (cons (inline-asm-format-operand-by-idx idx c1 out-plans in-plans mem-ptr-map) acc))))))
                    (else
                     (loop (+ i 1) (cons (if (eq? mode 'c) "%%" "%") acc)))))))))))

(define (inline-asm-trim-ws s)
  (let ((len (string-length s)))
    (let left ((i 0))
      (if (and (< i len) (memv (string-ref s i) '(#\space #\tab #\return #\newline)))
          (left (+ i 1))
          (let right ((j len))
            (if (and (> j i) (memv (string-ref s (- j 1)) '(#\space #\tab #\return #\newline)))
                (right (- j 1))
                (substring s i j)))))))

(define (inline-asm-split-lines expanded)
  (let ((len (string-length expanded)))
    (let loop ((i 0) (start 0) (acc '()))
      (if (>= i len)
          (let* ((last-chunk (inline-asm-trim-ws (substring expanded start len)))
                 (final (if (string=? last-chunk "") acc (cons last-chunk acc))))
            (reverse final))
          (let ((ch (string-ref expanded i)))
            (if (or (char=? ch #\newline) (char=? ch #\return) (char=? ch #\;))
                (let ((chunk (inline-asm-trim-ws (substring expanded start i))))
                  (loop (+ i 1) (+ i 1)
                        (if (or (string=? chunk "") (char=? (string-ref chunk 0) #\#))
                            acc
                            (cons chunk acc))))
                (loop (+ i 1) start acc)))))))

(define (lir-inst-defines-reg? inst reg)
  (and (pair? inst)
       (let ((op (car inst)))
         (case op
           ((%mov %load %load-byte-zx %pop %code-ref %str-ref %global-addr %not
             %add %raw-add %sub %raw-sub %imul %raw-mul
             %bit-and %bit-or %bit-xor %shl %shr %sar
             %box-fixnum %unbox-fixnum %neg %inc
             %alloc %alloc-stack %managed-alloc %managed-alloc-stack
             %fmov %fadd %fsub %fmul %fdiv
             %sitofp %fptosi %bitcast-f64-to-i64 %bitcast-i64-to-f64 %unbox-flonum
             %fcmp-ogt %fcmp-oge)
            (and (pair? (cdr inst)) (lir-reg-aliases? (cadr inst) reg)))
           ((%global-ref %setb %setbe %seta %setae)
            (or (and (pair? (cdr inst)) (lir-reg-aliases? (cadr inst) reg))
                (lir-reg-aliases? reg '%r11)))
           ((%fcmp-oeq %fcmp-une)
            (or (and (pair? (cdr inst)) (lir-reg-aliases? (cadr inst) reg))
                (lir-reg-aliases? reg '%r10)
                (lir-reg-aliases? reg '%r11)))
           ((%fcmp-olt %fcmp-ole)
            (or (and (pair? (cdr inst)) (lir-reg-aliases? (cadr inst) reg))
                (lir-reg-aliases? reg '%xmm14)
                (lir-reg-aliases? reg '%xmm15)))
           ((%uitofp)
            (or (and (pair? (cdr inst)) (lir-reg-aliases? (cadr inst) reg))
                (memq reg '(%rcx %r9 %r10 %r11))))
           ((%fptoui)
            (or (and (pair? (cdr inst)) (lir-reg-aliases? (cadr inst) reg))
                (memq reg '(%r10 %r11 %xmm11 %xmm12 %xmm13 %xmm14 %xmm15))))
           ((%fneg)
            (or (and (pair? (cdr inst))
                     (pair? (cddr inst))
                     (lir-reg-aliases? (caddr inst) reg))
                (lir-reg-aliases? reg '%r10)
                (lir-reg-aliases? reg '%r11)))
           ((%load-typed %fpext %fptrunc %trunc %zext %sext %managed-box %managed-unbox)
            (and (pair? (cdr inst))
                 (pair? (cddr inst))
                 (lir-reg-aliases? (caddr inst) reg)))
           ((%add-overflow %sub-overflow %mul-overflow)
            (and (pair? (cdr inst))
                 (or (lir-reg-aliases? (cadr inst) reg)
                     (and (pair? (cddr inst)) (lir-reg-aliases? (caddr inst) reg)))))
           ((%set-boolean)
            (or (and (pair? (cdr inst)) (lir-reg-aliases? (cadr inst) reg))
                (lir-reg-aliases? reg '%rax)))
           ((%cqo %idiv %udiv %urem)
            (or (lir-reg-aliases? reg '%rax)
                (lir-reg-aliases? reg '%rdx)
                (lir-reg-aliases? reg '%r11)
                (and (pair? (cdr inst)) (lir-reg-aliases? (cadr inst) reg))))
           ((%cmp %raw-cmp)
            (lir-reg-aliases? reg '%r11))
           ((%atomic-cas!)
            (or (and (pair? (cdr inst)) (lir-reg-aliases? (cadr inst) reg))
                (lir-reg-aliases? reg '%rax)))
           ((%c-call %call-foreign %call-closure %direct-call %call-indirect %dispatch-consumer)
            (or (memq reg '(%rax %rcx %rdx %rsi %rdi %r8 %r9 %r10 %r11 %al
                            %xmm0 %xmm1 %xmm2 %xmm3 %xmm4 %xmm5 %xmm6 %xmm7
                            %xmm8 %xmm9 %xmm10 %xmm11 %xmm12 %xmm13 %xmm14 %xmm15))
                (and (eq? (current-target-arch) 'aarch64)
                     (or (lir-reg-aliases? reg '%rax) (lir-reg-aliases? reg '%rbx)))))
           ((%syscall)
            (or (memq reg '(%rax %rcx %r11))
                (and (eq? (current-target-arch) 'aarch64) (lir-reg-aliases? reg '%rax))))
           ((%set-values-count)
            (lir-reg-aliases? reg '%rdx))
           ((%global-set!)
            (lir-reg-aliases? reg '%r11))
           ((%inline-asm)
            (lir-inline-asm-defines-reg? inst reg))
           (else #f)))))

(define (lir-inst-memory-barrier? inst)
  (and (pair? inst)
       (or (memq (car inst) '(%c-call %call-foreign %call-closure %direct-call %call-indirect %dispatch-consumer
                              %syscall %memory-fence %managed-safepoint-poll %push %pop %raise
                              %capture-cc %push-handler %pop-handler
                              %store-values-buf))
           (and (eq? (car inst) '%inline-asm)
                (lir-inline-asm-memory-barrier? inst)))))

(define (lir-inst-may-alias-stack-slot? inst off)
  (and (pair? inst)
       (case (car inst)
         ((%store %store-byte)
          (if (and (pair? (cdr inst)) (pair? (cddr inst)))
              (let ((base (cadr inst))
                    (soff (caddr inst)))
                (or (not (eq? base '%rsp))
                    (not (integer? soff))
                    (not (integer? off))
                    (< (abs (- soff off)) 8)))
              #t))
         ((%store-typed)
          (if (and (pair? (cdr inst)) (pair? (cddr inst)) (pair? (cdddr inst)))
              (let ((base (caddr inst))
                    (soff (cadddr inst)))
                (or (not (eq? base '%rsp))
                    (not (integer? soff))
                    (not (integer? off))
                    (< (abs (- soff off)) 8)))
              #t))
         ((%box-flonum %managed-write-barrier %atomic-cas!)
          #t)
         (else #f))))

(define (lir-inst-terminates-block? inst)
  (and (pair? inst)
       (memq (car inst) '(%jump %direct-jump %jump-cond %jump-if %jump-if-false %jump-if-zero
                          %switch %return %raise %label %block))))

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

           ;; 3. Memory store / alias check (includes %store, %store-byte, %store-typed):
           ((lir-inst-may-alias-stack-slot? inst off)
            #f)

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

           ;; 6. General instruction not defining src or aliasing off: continue scanning
           (else
            (loop tail (cons inst prefix)))))))))

;;; Extract registers/stack slots used by instruction
(define (lir-inst-extract-uses inst)
  (if (not (pair? inst))
      '()
      (case (car inst)
        ((%store %store-byte)
         (let ((base (cadr inst)) (val (cadddr inst)))
           (cond
             ((and (eq? base '%rsp) (lir-peephole-reg? val)) (list val))
             ((lir-peephole-reg? base) (if (lir-peephole-reg? val) (list base val) (list base)))
             (else (if (lir-peephole-reg? val) (list val) '())))))
        ((%store-typed)
         (let ((base (caddr inst)) (val (car (cddddr inst))))
           (cond
             ((and (eq? base '%rsp) (lir-peephole-reg? val)) (list val))
             ((lir-peephole-reg? base) (if (lir-peephole-reg? val) (list base val) (list base)))
             (else (if (lir-peephole-reg? val) (list val) '())))))
        ((%load %load-byte-zx)
         (let ((base (caddr inst)) (off (cadddr inst)))
           (if (eq? base '%rsp)
               (list (list 'stack off))
               (if (lir-peephole-reg? base) (list base) '()))))
        ((%load-typed)
         (let ((base (cadddr inst)) (off (car (cddddr inst))))
           (if (eq? base '%rsp)
               (list (list 'stack off))
               (if (lir-peephole-reg? base) (list base) '()))))
        ((%mov %fmov %sitofp %uitofp %fptosi %fptoui %bitcast-f64-to-i64 %bitcast-i64-to-f64 %unbox-flonum)
         (let ((src (caddr inst)))
           (if (lir-peephole-reg? src) (list src) '())))
        ((%fneg %fpext %fptrunc %trunc %zext %sext)
         (let ((src (cadddr inst)))
           (if (lir-peephole-reg? src) (list src) '())))
        ((%add %raw-add %sub %raw-sub %imul %raw-mul %bit-and %bit-or %bit-xor %shl %sar
          %fadd %fsub %fmul %fdiv)
         (let ((dst (cadr inst)) (src (caddr inst)))
           (cond
             ((and (lir-peephole-reg? dst) (lir-peephole-reg? src)) (list dst src))
             ((lir-peephole-reg? dst) (list dst))
             ((lir-peephole-reg? src) (list src))
             (else '()))))
        ((%shr)
         (if (= (length inst) 4)
             (let ((src (caddr inst)) (cnt (cadddr inst)))
               (cond
                 ((and (lir-peephole-reg? src) (lir-peephole-reg? cnt)) (list src cnt))
                 ((lir-peephole-reg? src) (list src))
                 ((lir-peephole-reg? cnt) (list cnt))
                 (else '())))
             (let ((dst (cadr inst)) (cnt (caddr inst)))
               (cond
                 ((and (lir-peephole-reg? dst) (lir-peephole-reg? cnt)) (list dst cnt))
                 ((lir-peephole-reg? dst) (list dst))
                 ((lir-peephole-reg? cnt) (list cnt))
                 (else '())))))
        ((%cmp %raw-cmp %fcmp)
         (let ((op1 (cadr inst)) (op2 (caddr inst)))
           (cond
             ((and (lir-peephole-reg? op1) (lir-peephole-reg? op2)) (list op1 op2))
             ((lir-peephole-reg? op1) (list op1))
             ((lir-peephole-reg? op2) (list op2))
             (else '()))))
        ((%fcmp-oeq %fcmp-une %fcmp-olt %fcmp-ole %fcmp-ogt %fcmp-oge)
         (let ((op1 (caddr inst)) (op2 (cadddr inst)))
           (cond
             ((and (lir-peephole-reg? op1) (lir-peephole-reg? op2)) (list op1 op2))
             ((lir-peephole-reg? op1) (list op1))
             ((lir-peephole-reg? op2) (list op2))
             (else '()))))
        ((%inline-asm)
         (let* ((parsed (inline-asm-extract-clauses inst))
                (ins (caddr parsed)))
           (let loop ((is ins) (acc '()))
             (if (null? is)
                 (reverse acc)
                 (let* ((ni (inline-asm-normalize-in-entry (car is)))
                        (src (and ni (cadr ni))))
                   (cond
                     ((not ni) (loop (cdr is) acc))
                     ((lir-peephole-reg? src) (loop (cdr is) (cons src acc)))
                     ((and (pair? src) (eq? (car src) '%stack)) (loop (cdr is) (cons (list 'stack (cadr src)) acc)))
                     (else (loop (cdr is) acc))))))))
        (else '()))))

;;; Extract registers/stack slots defined by instruction
(define (lir-inst-extract-defs inst)
  (if (not (pair? inst))
      '()
      (case (car inst)
        ((%store %store-byte)
         (let ((base (cadr inst)) (off (caddr inst)))
           (if (eq? base '%rsp)
               (list (list 'stack off))
               '())))
        ((%store-typed)
         (let ((base (caddr inst)) (off (cadddr inst)))
           (if (eq? base '%rsp)
               (list (list 'stack off))
               '())))
        ((%load %load-byte-zx %pop %code-ref %str-ref %global-ref %global-addr %not %set-boolean %alloc %alloc-stack
          %setb %setbe %seta %setae %fmov %sitofp %uitofp %fptosi %fptoui %bitcast-f64-to-i64 %bitcast-i64-to-f64
          %fcmp-oeq %fcmp-une %fcmp-olt %fcmp-ole %fcmp-ogt %fcmp-oge
          %unbox-flonum %fadd %fsub %fmul %fdiv %managed-alloc %managed-alloc-stack)
         (if (lir-peephole-reg? (cadr inst)) (list (cadr inst)) '()))
        ((%load-typed %fneg %fpext %fptrunc %trunc %zext %sext)
         (if (lir-peephole-reg? (caddr inst)) (list (caddr inst)) '()))
        ((%add-overflow %sub-overflow %mul-overflow)
         (list (cadr inst) (caddr inst)))
        ((%udiv %urem)
         (if (= (length inst) 4)
             (list (cadr inst))
             '(%rax %rdx)))
        ((%mov)
         (let ((dst (cadr inst)))
           (if (symbol? dst)
               (list dst)
               (if (and (pair? dst) (eq? (car dst) '%stack))
                   (list (list 'stack (cadr dst)))
                   '()))))
        ((%add %raw-add %sub %raw-sub %imul %raw-mul %bit-and %bit-or %bit-xor %shl %shr %sar %neg %inc)
         (list (cadr inst)))
        ((%inline-asm)
         (let* ((parsed (inline-asm-extract-clauses inst))
                (outs (cadr parsed)))
           (let loop ((os outs) (acc '()))
             (if (null? os)
                 (reverse acc)
                 (let* ((no (inline-asm-normalize-out-entry (car os)))
                        (dst (and no (cadr no))))
                   (cond
                     ((not no) (loop (cdr os) acc))
                     ((symbol? dst) (loop (cdr os) (cons dst acc)))
                     ((and (pair? dst) (eq? (car dst) '%stack)) (loop (cdr os) (cons (list 'stack (cadr dst)) acc)))
                     (else (loop (cdr os) acc))))))))
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

;;; -----------------------------------------------------------------------
;;; Part 17: Pass-Level Analysis Contracts & Cache Registry Hooks (Issue #840)
;;; -----------------------------------------------------------------------

(define *pass-analysis-contracts* (cons '() '()))
(define *pass-proc-analysis-contracts* (cons '() '()))
(define *nanopass-pre-pass-analysis-hook* (cons #f '()))
(define *nanopass-post-pass-analysis-hook* (cons #f '()))

(define (normalize-analysis-spec-list spec)
  (cond
    ((or (not spec) (null? spec)) '())
    ((eq? spec 'all) '(all))
    ((and (pair? spec) (eq? (car spec) 'quote) (pair? (cdr spec)))
     (normalize-analysis-spec-list (cadr spec)))
    ((and (list? spec) (= (length spec) 1) (list? (car spec)))
     (car spec))
    ((list? spec) spec)
    (else (list spec))))

(define (alist-upsert-eq alist key val)
  (let loop ((rem alist) (acc '()) (found? #f))
    (cond
      ((null? rem)
       (let ((rev (reverse acc)))
         (if found? rev (cons (cons key val) rev))))
      ((eq? (caar rem) key)
       (loop (cdr rem) (cons (cons key val) acc) #t))
      (else
       (loop (cdr rem) (cons (car rem) acc) found?)))))

(define (register-pass-analysis-contract! pass-id requires preserves invalidates)
  (let* ((req-list (normalize-analysis-spec-list requires))
         (pres-list (if preserves (normalize-analysis-spec-list preserves) #f))
         (inv-list (normalize-analysis-spec-list invalidates))
         (contract (list pass-id req-list pres-list inv-list)))
    (set-car! *pass-analysis-contracts*
              (alist-upsert-eq (car *pass-analysis-contracts*) pass-id contract))
    contract))

(define (register-pass-proc-analysis-contract! proc pass-id requires preserves invalidates)
  (let ((contract (register-pass-analysis-contract! pass-id requires preserves invalidates)))
    (if (procedure? proc)
        (set-car! *pass-proc-analysis-contracts*
                  (alist-upsert-eq (car *pass-proc-analysis-contracts*) proc contract)))
    contract))

(define (lookup-pass-analysis-contract key)
  (cond
    ((symbol? key)
     (let ((e (assq key (car *pass-analysis-contracts*))))
       (if e (cdr e) #f)))
    ((procedure? key)
     (let ((e (assq key (car *pass-proc-analysis-contracts*))))
       (if e (cdr e) #f)))
    (else #f)))

(define (reset-pass-analysis-contracts!)
  (set-car! *pass-analysis-contracts* '())
  (set-car! *pass-proc-analysis-contracts* '()))

(define (nanopass-invoke-pre-pass-analysis! pass-id ir)
  (let ((hook (car *nanopass-pre-pass-analysis-hook*)))
    (if (and (not (nanopass-in-pipeline-runner?))
             (procedure? hook))
        (hook pass-id ir)
        #f)))

(define (nanopass-invoke-post-pass-analysis! pass-id in-ir out-ir)
  (let ((hook (car *nanopass-post-pass-analysis-hook*)))
    (if (and (not (nanopass-in-pipeline-runner?))
             (procedure? hook))
        (hook pass-id in-ir out-ir)
        #f)))




