;;; =======================================================================
;;; Meta-Grammar Parser for CPython PEG Specifications (PEP 617 / python.gram)
;;; Conforms to DSN-25 Phase 2 & DSN-33-04 §3.2, Issue #894 & Issue #907/#908
;;; Pure Scheme implementation using Packrat PEG combinators. Zero external dependencies.
;;; =======================================================================

;;; -----------------------------------------------------------------------
;;; 1. Lexical Scanners & Helper Combinators
;;; -----------------------------------------------------------------------

;;; Whitespace and comments scanner: skips [ \t\r\n] and # ... to newline
(define (peg:meta-ws)
  (lambda (ctx pos sk fk)
    (let ((txt (parse-ctx-text ctx))
          (total-len (parse-ctx-length ctx)))
      (let loop ((i pos))
        (cond
          ((>= i total-len)
           (sk "" i fk))
          (else
           (let ((ch (string-ref txt i)))
             (cond
               ((or (char=? ch #\space)
                    (char=? ch #\tab)
                    (char=? ch #\newline)
                    (char=? ch #\return))
                (loop (+ i 1)))
               ((char=? ch #\#)
                ;; Comment to end of line
                (let scan-comment ((j (+ i 1)))
                  (if (>= j total-len)
                      (sk "" j fk)
                      (let ((c (string-ref txt j)))
                        (if (or (char=? c #\newline) (char=? c #\return))
                            (loop (+ j 1))
                            (scan-comment (+ j 1)))))))
               (else
                (sk "" i fk))))))))))

(define (peg:lex p)
  (peg:map (lambda (pair) (car pair))
           (peg:seq p (peg:meta-ws))))

;;; Identifier token: [A-Za-z_][A-Za-z0-9_]*
(define (peg:meta-ident)
  (peg:lex
   (lambda (ctx pos sk fk)
     (let ((txt (parse-ctx-text ctx))
           (total-len (parse-ctx-length ctx)))
       (if (>= pos total-len)
           (fk)
           (let ((c0 (string-ref txt pos)))
             (if (or (and (char>=? c0 #\a) (char<=? c0 #\z))
                     (and (char>=? c0 #\A) (char<=? c0 #\Z))
                     (char=? c0 #\_))
                 (let loop ((i (+ pos 1)))
                   (if (>= i total-len)
                       (sk (string->symbol (substring txt pos i)) i fk)
                       (let ((ci (string-ref txt i)))
                         (if (or (and (char>=? ci #\a) (char<=? ci #\z))
                                 (and (char>=? ci #\A) (char<=? ci #\Z))
                                 (and (char>=? ci #\0) (char<=? ci #\9))
                                 (char=? ci #\_))
                             (loop (+ i 1))
                             (sk (string->symbol (substring txt pos i)) i fk)))))
                 (fk))))))))

;;; String Literal Token: '...' or "..." or '''...''' or """..."""
(define (peg:meta-string-lit)
  (peg:lex
   (lambda (ctx pos sk fk)
     (let ((txt (parse-ctx-text ctx))
           (total-len (parse-ctx-length ctx)))
       (if (>= pos total-len)
           (fk)
           (let ((c0 (string-ref txt pos)))
             (if (and (not (char=? c0 #\')) (not (char=? c0 #\")))
                 (fk)
                 ;; Check triple quotes
                 (let* ((is-triple (and (<= (+ pos 3) total-len)
                                        (char=? (string-ref txt (+ pos 1)) c0)
                                        (char=? (string-ref txt (+ pos 2)) c0)))
                        (quote-len (if is-triple 3 1)))
                   (let loop ((i (+ pos quote-len)) (chars '()))
                     (cond
                       ((> (+ i quote-len) total-len)
                        (fk))
                       (is-triple
                        (if (and (char=? (string-ref txt i) c0)
                                 (char=? (string-ref txt (+ i 1)) c0)
                                 (char=? (string-ref txt (+ i 2)) c0))
                            (sk (list->string (reverse chars)) (+ i 3) fk)
                            (let ((ci (string-ref txt i)))
                              (if (char=? ci #\\)
                                  (if (< (+ i 1) total-len)
                                      (let ((esc (string-ref txt (+ i 1))))
                                        (loop (+ i 2) (cons (case esc
                                                              ((#\n) #\newline)
                                                              ((#\t) #\tab)
                                                              ((#\r) #\return)
                                                              (else esc))
                                                            chars)))
                                      (fk))
                                  (loop (+ i 1) (cons ci chars))))))
                       (else
                        (if (char=? (string-ref txt i) c0)
                            (sk (list->string (reverse chars)) (+ i 1) fk)
                            (let ((ci (string-ref txt i)))
                              (if (char=? ci #\\)
                                  (if (< (+ i 1) total-len)
                                      (let ((esc (string-ref txt (+ i 1))))
                                        (loop (+ i 2) (cons (case esc
                                                              ((#\n) #\newline)
                                                              ((#\t) #\tab)
                                                              ((#\r) #\return)
                                                              (else esc))
                                                            chars)))
                                      (fk))
                                  (loop (+ i 1) (cons ci chars))))))))))))))))

;;; Action Block Parser: { ... } handling nested braces and strings
(define (peg:meta-action-block)
  (peg:lex
   (lambda (ctx pos sk fk)
     (let ((txt (parse-ctx-text ctx))
           (total-len (parse-ctx-length ctx)))
       (if (or (>= pos total-len)
               (not (char=? (string-ref txt pos) #\{)))
           (fk)
           (let loop ((i (+ pos 1)) (depth 1) (in-quote #f))
             (cond
               ((>= i total-len)
                (fk))
               (in-quote
                (let ((ch (string-ref txt i)))
                  (cond
                    ((char=? ch #\\)
                     (loop (+ i 2) depth in-quote))
                    ((char=? ch in-quote)
                     (loop (+ i 1) depth #f))
                    (else
                     (loop (+ i 1) depth in-quote)))))
               (else
                (let ((ch (string-ref txt i)))
                  (cond
                    ((or (char=? ch #\') (char=? ch #\"))
                     (loop (+ i 1) depth ch))
                    ((char=? ch #\{)
                     (loop (+ i 1) (+ depth 1) #f))
                    ((char=? ch #\})
                     (if (= depth 1)
                         (sk (substring txt (+ pos 1) i) (+ i 1) fk)
                         (loop (+ i 1) (- depth 1) #f)))
                    (else
                     (loop (+ i 1) depth #f))))))))))))

;;; Regex Token: /pattern/
(define (peg:meta-regex-lit)
  (peg:lex
   (lambda (ctx pos sk fk)
     (let ((txt (parse-ctx-text ctx))
           (total-len (parse-ctx-length ctx)))
       (if (or (>= pos total-len)
               (not (char=? (string-ref txt pos) #\/)))
           (fk)
           (if (or (>= (+ pos 1) total-len)
                   (let ((c1 (string-ref txt (+ pos 1))))
                     (or (char=? c1 #\space) (char=? c1 #\tab)
                         (char=? c1 #\newline) (char=? c1 #\return))))
               (fk)
               (let loop ((i (+ pos 1)) (chars '()))
                 (cond
                   ((>= i total-len) (fk))
                   ((char=? (string-ref txt i) #\\)
                    (if (< (+ i 1) total-len)
                        (loop (+ i 2) (cons (string-ref txt (+ i 1)) (cons #\\ chars)))
                        (fk)))
                   ((char=? (string-ref txt i) #\/)
                    (sk (list->string (reverse chars)) (+ i 1) fk))
                   (else
                    (loop (+ i 1) (cons (string-ref txt i) chars)))))))))))
(define (peg:meta-char-class)
  (peg:lex
   (lambda (ctx pos sk fk)
     (let ((txt (parse-ctx-text ctx))
           (total-len (parse-ctx-length ctx)))
       (if (or (>= pos total-len)
               (not (char=? (string-ref txt pos) #\[)))
           (fk)
           (let* ((is-inv (and (< (+ pos 1) total-len)
                               (char=? (string-ref txt (+ pos 1)) #\^)))
                  (start-inner (if is-inv (+ pos 2) (+ pos 1))))
             (let loop ((i start-inner) (chars '()))
               (cond
                 ((>= i total-len) (fk))
                 ((char=? (string-ref txt i) #\\)
                  (if (< (+ i 1) total-len)
                      (loop (+ i 2) (cons (string-ref txt (+ i 1)) (cons #\\ chars)))
                      (fk)))
                 ((char=? (string-ref txt i) #\])
                  (let ((spec (list->string (reverse chars))))
                    (sk (cons spec is-inv) (+ i 1) fk)))
                 (else
                  (loop (+ i 1) (cons (string-ref txt i) chars)))))))))))

;;; Token helper for fixed strings
(define (tok str)
  (peg:lex (peg:lit str)))

;;; -----------------------------------------------------------------------
;;; 2. Grammar Specification Parser (Mutually Recursive Rules)
;;; -----------------------------------------------------------------------

(define (build-meta-grammar-parser)
  ;; Punctuation
  (define pipe-tok (tok "|"))
  (define colon-tok (tok ":"))
  (define arrow-tok (peg:alt (tok "<-") (tok "=") (tok ":")))
  (define lparen (tok "("))
  (define rparen (tok ")"))
  (define star-tok (tok "*"))
  (define plus-tok (tok "+"))
  (define qmark-tok (tok "?"))
  (define amp-tok (peg:alt (tok "&&") (tok "&")))
  (define not-tok (tok "!"))
  (define tilde-tok (tok "~"))
  (define dot-tok (tok "."))
  (define eq-tok (tok "="))

  (define choice-parser #f)
  ;; Forward reference for choice_expr
  (define (choice-ref ctx pos sk fk)
    (choice-parser ctx pos sk fk))

  ;; Primary expression
  (define primary-parser
    (peg:alt
     ;; Literal
     (peg:map (lambda (s) (make-peg-lit-expr s)) (peg:meta-string-lit))
     ;; Regex /pattern/
     (peg:map (lambda (p) (make-peg-regex-expr p)) (peg:meta-regex-lit))
     ;; Any char '.'
     (peg:map (lambda (_) (make-peg-any-char-expr)) dot-tok)
     ;; Group '(' choice ')'
     (peg:map (lambda (res) (cadr res))
              (peg:seq lparen choice-ref rparen))
     ;; Character class or optional bracket expr
     (peg:map (lambda (res)
                (let ((spec (car res))
                      (inv? (cdr res)))
                  (if inv?
                      (make-peg-char-class-expr spec #t)
                      ;; Check if inner is an optional choice expression
                      (let ((sub-res (peg-parse-partial choice-ref spec)))
                        (if (and sub-res (= (cdr sub-res) (string-length spec)))
                            (make-peg-opt-expr (car sub-res))
                            (make-peg-char-class-expr spec #f))))))
              (peg:meta-char-class))
     ;; Identifier / RuleRef
     (peg:map (lambda (name) (make-peg-rule-ref-expr name)) (peg:meta-ident))))

  ;; Separator gather: primary '.' primary ('+' | '*')
  (define gather-parser
    (peg:map (lambda (res)
               (let ((sep (car res))
                     (elem (caddr res))
                     (op (cadddr res)))
                 (make-peg-gather-expr sep elem (string=? op "+"))))
             (peg:seq primary-parser dot-tok primary-parser (peg:alt plus-tok star-tok))))

  (define primary-or-gather
    (peg:alt gather-parser primary-parser))

  ;; Suffixes: *, +, ?
  (define suffixed-parser
    (peg:map (lambda (res)
               (let ((base (car res))
                     (suff (cadr res)))
                 (cond
                   ((not suff) base)
                   ((string=? suff "*") (make-peg-repeat-expr base 0 #f))
                   ((string=? suff "+") (make-peg-repeat-expr base 1 #f))
                   ((string=? suff "?") (make-peg-opt-expr base))
                   (else base))))
             (peg:seq primary-or-gather (peg:opt (peg:alt star-tok plus-tok qmark-tok)))))

  ;; Prefixes: cut ~, &expr, !expr, name=expr, name:expr
  (define prefix-item
    (peg:alt
     (peg:map (lambda (_) (make-peg-cut-expr)) tilde-tok)
     (peg:map (lambda (res) (make-peg-pred-expr (cadr res) #t))
              (peg:seq amp-tok suffixed-parser))
     (peg:map (lambda (res) (make-peg-pred-expr (cadr res) #f))
              (peg:seq not-tok suffixed-parser))
     ;; Named bind: name '=' suffixed or name ':' suffixed
     (peg:map (lambda (res)
                (let ((var-name (car res))
                      (inner (caddr res)))
                  (make-peg-named-expr var-name inner)))
              (peg:seq (peg:meta-ident) (peg:alt eq-tok colon-tok) suffixed-parser))
     suffixed-parser))

  ;; Guard against consuming the start of a subsequent rule definition
  (define new-rule-head
    (peg:alt
     (peg:seq (peg:meta-ident) (tok "<-"))
     (peg:seq (peg:line-start)
              (peg:meta-ident)
              (peg:opt (peg:meta-char-class))
              (peg:opt (peg:seq lparen (peg:meta-ident) rparen))
              (peg:alt (peg:lit ":") (peg:lit "=")))))

  (define prefix-parser
    (peg:map (lambda (res) (cadr res))
             (peg:seq (peg:not new-rule-head) prefix-item)))

  ;; Sequence element: prefix + optional action
  (define seq-parser
    (peg:map (lambda (res)
               (let ((elts (car res))
                     (act (cadr res)))
                 (let ((base-seq
                        (cond
                          ((null? elts) (make-peg-seq-expr '()))
                          ((null? (cdr elts)) (car elts))
                          (else (make-peg-seq-expr elts)))))
                   (if act
                       (make-peg-action-expr base-seq act)
                       base-seq))))
             (peg:seq (peg:plus prefix-parser) (peg:opt (peg:meta-action-block)))))

  ;; Choice expression: seq ('|' seq)* or seq ('/' seq)*
  (define choice-parser-internal
    (peg:map (lambda (res)
               (let* ((lead-pipe? (car res))
                      (first-seq (cadr res))
                      (rest-seqs (caddr res)))
                 (let ((alts (cons first-seq
                                   (map (lambda (pair) (cadr pair)) rest-seqs))))
                   (cond
                     ((null? alts) (make-peg-choice-expr '()))
                     ((null? (cdr alts)) (car alts))
                     (else (make-peg-choice-expr alts))))))
             (peg:seq (peg:opt pipe-tok)
                      seq-parser
                      (peg:star (peg:seq (peg:alt pipe-tok (tok "/")) seq-parser)))))

  (set! choice-parser choice-parser-internal)

  ;; Rule definition: name [type] (memo): choice_expr
  (define rule-parser
    (peg:map (lambda (res)
               (let* ((name (car res))
                      (arrow (cadr res))
                      (body (caddr res)))
                 (make-peg-rule-def name body #t #f)))
             (peg:seq (peg:meta-ident)
                      arrow-tok
                      choice-parser)))

  ;; Directive: grammar Name or @header { ... } etc.
  (define directive-parser
    (peg:alt
     (peg:map (lambda (res) (list 'grammar (cadr res)))
              (peg:seq (tok "grammar") (peg:meta-ident)))
     (peg:map (lambda (res) (list (car res) (cadr res)))
              (peg:seq (peg:lex (lambda (ctx pos sk fk)
                                  (let ((txt (parse-ctx-text ctx))
                                        (len (parse-ctx-length ctx)))
                                    (if (and (< pos len) (char=? (string-ref txt pos) #\@))
                                        (let loop ((i (+ pos 1)))
                                          (if (or (>= i len)
                                                  (let ((c (string-ref txt i)))
                                                    (not (or (and (char>=? c #\a) (char<=? c #\z))
                                                             (and (char>=? c #\A) (char<=? c #\Z))
                                                             (char=? c #\_)))))
                                              (sk (string->symbol (substring txt pos i)) i fk)
                                              (loop (+ i 1))))
                                        (fk)))))
                       (peg:meta-action-block)))))

  ;; Top-level Grammar definition: (directive | rule)*
  (define grammar-file-parser
    (peg:map (lambda (res)
               (let* ((items (cadr res))
                      (grammar-name 'AnonymousGrammar)
                      (dirs '())
                      (rules '()))
                 (for-each
                  (lambda (item)
                    (cond
                      ((peg-rule-def? item)
                       (set! rules (cons item rules)))
                      ((pair? item)
                       (if (eq? (car item) 'grammar)
                           (set! grammar-name (cadr item))
                           (set! dirs (cons item dirs))))))
                  items)
                 (make-peg-grammar-def grammar-name (reverse rules) (reverse dirs))))
             (peg:seq (peg:meta-ws)
                      (peg:star (peg:alt directive-parser rule-parser)))))

  grammar-file-parser)

(define *meta-grammar-parser* (build-meta-grammar-parser))

(define (parse-peg-grammar text)
  (peg-parse *meta-grammar-parser* text))
