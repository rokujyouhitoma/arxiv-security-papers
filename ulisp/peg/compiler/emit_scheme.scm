;;; =======================================================================
;;; Direct-Style Static Scheme PEG Parser Generator Backend & Static LR Analysis
;;; Conforms to Issue #948 & DSN-33-22
;;; Zero CPS combinators, zero closure allocations, zero local set!.
;;; =======================================================================

;;; -----------------------------------------------------------------------
;;; 1. Identifier Validation & String Escaping (CWE-94 Guards)
;;; -----------------------------------------------------------------------

(define (%emit-ident-start-char? ch)
  (or (and (char>=? ch #\a) (char<=? ch #\z))
      (and (char>=? ch #\A) (char<=? ch #\Z))
      (char=? ch #\_)))

(define (%emit-ident-cont-char? ch)
  (or (%emit-ident-start-char? ch)
      (and (char>=? ch #\0) (char<=? ch #\9))
      (char=? ch #\-)))

(define (%emit-valid-ident? str)
  (and (string? str)
       (> (string-length str) 0)
       (%emit-ident-start-char? (string-ref str 0))
       (let loop ((i 1) (len (string-length str)))
         (if (>= i len)
             #t
             (if (%emit-ident-cont-char? (string-ref str i))
                 (loop (+ i 1) len)
                 #f)))))

(define (%emit-assert-valid-ident! sym-or-str context-label)
  (let ((s (if (symbol? sym-or-str)
               (symbol->string sym-or-str)
               sym-or-str)))
    (if (%emit-valid-ident? s)
        s
        (error "Invalid identifier for Scheme emission (CWE-94 guard)"
               (list context-label sym-or-str)))))

(define (%emit-fn-start-char? ch)
  (or (%emit-ident-start-char? ch)
      (char=? ch #\%)))

(define (%emit-fn-cont-char? ch)
  (or (%emit-ident-cont-char? ch)
      (char=? ch #\?)
      (char=? ch #\!)))

(define (%emit-valid-fn-ident? str)
  (and (string? str)
       (> (string-length str) 0)
       (%emit-fn-start-char? (string-ref str 0))
       (let loop ((i 1) (len (string-length str)))
         (if (>= i len)
             #t
             (if (%emit-fn-cont-char? (string-ref str i))
                 (loop (+ i 1) len)
                 #f)))))

(define (%emit-assert-valid-fn-ident! sym-or-str context-label)
  (let ((s (if (symbol? sym-or-str)
               (symbol->string sym-or-str)
               sym-or-str)))
    (if (%emit-valid-fn-ident? s)
        s
        (error "Invalid function identifier for Scheme emission (CWE-94 guard)"
               (list context-label sym-or-str)))))

(define (%emit-escape-scheme-char ch)
  (cond
    ((char=? ch #\\) "\\\\")
    ((char=? ch #\") "\\\"")
    ((char=? ch #\newline) "\\n")
    ((char=? ch #\return) "\\r")
    ((char=? ch #\tab) "\\t")
    (else (string ch))))

(define (%emit-escape-scheme-string str)
  (let ((len (string-length str)))
    (let loop ((i 0) (acc '()))
      (if (>= i len)
          (apply string-append (reverse acc))
          (loop (+ i 1) (cons (%emit-escape-scheme-char (string-ref str i)) acc))))))

(define (%emit-quote-string str)
  (string-append "\"" (%emit-escape-scheme-string str) "\""))

(define (%emit-char-literal ch)
  (cond
    ((char=? ch #\newline) "#\\newline")
    ((char=? ch #\return) "#\\return")
    ((char=? ch #\tab) "#\\tab")
    ((char=? ch #\space) "#\\space")
    (else (string-append "#\\" (string ch)))))

(define (%emit-strings-join xs sep)
  (if (null? xs)
      ""
      (let loop ((rest (cdr xs)) (acc (list (car xs))))
        (if (null? rest)
            (apply string-append (reverse acc))
            (loop (cdr rest) (cons (car rest) (cons sep acc)))))))

;;; -----------------------------------------------------------------------
;;; 2. Static Grammar Analysis: Nullability, Left-Corner Graph & Tarjan SCC
;;; -----------------------------------------------------------------------

(define (%emit-regex-nullable? pat)
  (let ((len (string-length pat)))
    (or (string=? pat "(?:\\s+|#[^\\r\\n]*)*")
        (string=? pat "\\s*")
        (and (> len 0)
             (char=? (string-ref pat (- len 1)) #\*)))))

(define (peg-expr-nullable? expr nullable-rules)
  (cond
    ((peg-lit-expr? expr)
     (= (string-length (peg-lit-expr-val expr)) 0))
    ((peg-regex-expr? expr)
     (%emit-regex-nullable? (peg-regex-expr-pattern expr)))
    ((peg-char-class-expr? expr) #f)
    ((peg-any-char-expr? expr) #f)
    ((peg-cut-expr? expr) #t)
    ((peg-line-start-expr? expr) #t)
    ((peg-opt-expr? expr) #t)
    ((peg-pred-expr? expr) #t)
    ((peg-repeat-expr? expr)
     (= (peg-repeat-expr-min-count expr) 0))
    ((peg-gather-expr? expr)
     (not (peg-gather-expr-one-or-more? expr)))
    ((peg-named-expr? expr)
     (peg-expr-nullable? (peg-named-expr-expr expr) nullable-rules))
    ((peg-action-expr? expr)
     (peg-expr-nullable? (peg-action-expr-expr expr) nullable-rules))
    ((peg-rule-ref-expr? expr)
     (if (memq (peg-rule-ref-expr-name expr) nullable-rules) #t #f))
    ((peg-seq-expr? expr)
     (let loop ((elts (peg-seq-expr-elements expr)))
       (cond
         ((null? elts) #t)
         ((peg-expr-nullable? (car elts) nullable-rules) (loop (cdr elts)))
         (else #f))))
    ((peg-choice-expr? expr)
     (let loop ((alts (peg-choice-expr-alternatives expr)))
       (cond
         ((null? alts) #f)
         ((peg-expr-nullable? (car alts) nullable-rules) #t)
         (else (loop (cdr alts))))))
    (else #f)))

(define (peg-compute-nullable-rules grammar)
  (let ((rules (peg-grammar-def-rules grammar)))
    (let fix ((nullable '()))
      (let step ((rs rules) (next-nullable nullable) (changed? #f))
        (if (null? rs)
            (if changed?
                (fix next-nullable)
                next-nullable)
            (let* ((r (car rs))
                   (name (peg-rule-def-name r)))
              (if (and (not (memq name next-nullable))
                       (peg-expr-nullable? (peg-rule-def-expr r) next-nullable))
                  (step (cdr rs) (cons name next-nullable) #t)
                  (step (cdr rs) next-nullable changed?))))))))

(define (%emit-union-syms a b)
  (let loop ((xs b) (acc a))
    (if (null? xs)
        acc
        (if (memq (car xs) acc)
            (loop (cdr xs) acc)
            (loop (cdr xs) (cons (car xs) acc))))))

(define (peg-expr-left-corners expr nullable-rules)
  (cond
    ((peg-rule-ref-expr? expr)
     (list (peg-rule-ref-expr-name expr)))
    ((peg-seq-expr? expr)
     (let loop ((elts (peg-seq-expr-elements expr)) (acc '()))
       (if (null? elts)
           (reverse acc)
           (let* ((e (car elts))
                  (lc (peg-expr-left-corners e nullable-rules))
                  (merged (%emit-union-syms acc lc)))
             (if (peg-expr-nullable? e nullable-rules)
                 (loop (cdr elts) merged)
                 (reverse merged))))))
    ((peg-choice-expr? expr)
     (let loop ((alts (peg-choice-expr-alternatives expr)) (acc '()))
       (if (null? alts)
           acc
           (loop (cdr alts)
                 (%emit-union-syms acc (peg-expr-left-corners (car alts) nullable-rules))))))
    ((peg-repeat-expr? expr)
     (peg-expr-left-corners (peg-repeat-expr-expr expr) nullable-rules))
    ((peg-opt-expr? expr)
     (peg-expr-left-corners (peg-opt-expr-expr expr) nullable-rules))
    ((peg-pred-expr? expr)
     (peg-expr-left-corners (peg-pred-expr-expr expr) nullable-rules))
    ((peg-named-expr? expr)
     (peg-expr-left-corners (peg-named-expr-expr expr) nullable-rules))
    ((peg-action-expr? expr)
     (peg-expr-left-corners (peg-action-expr-expr expr) nullable-rules))
    ((peg-gather-expr? expr)
     (let ((elem-lc (peg-expr-left-corners (peg-gather-expr-elem expr) nullable-rules)))
       (if (peg-expr-nullable? (peg-gather-expr-elem expr) nullable-rules)
           (%emit-union-syms elem-lc (peg-expr-left-corners (peg-gather-expr-sep expr) nullable-rules))
           elem-lc)))
    (else '())))

(define (peg-compute-left-corner-graph grammar nullable-rules)
  (map (lambda (r)
         (cons (peg-rule-def-name r)
               (peg-expr-left-corners (peg-rule-def-expr r) nullable-rules)))
       (peg-grammar-def-rules grammar)))

(define (peg-expr-has-rule-ref? expr)
  (cond
    ((peg-rule-ref-expr? expr) #t)
    ((peg-seq-expr? expr)
     (let loop ((elts (peg-seq-expr-elements expr)))
       (and (pair? elts)
            (or (peg-expr-has-rule-ref? (car elts))
                (loop (cdr elts))))))
    ((peg-choice-expr? expr)
     (let loop ((alts (peg-choice-expr-alternatives expr)))
       (and (pair? alts)
            (or (peg-expr-has-rule-ref? (car alts))
                (loop (cdr alts))))))
    ((peg-repeat-expr? expr)
     (peg-expr-has-rule-ref? (peg-repeat-expr-expr expr)))
    ((peg-opt-expr? expr)
     (peg-expr-has-rule-ref? (peg-opt-expr-expr expr)))
    ((peg-pred-expr? expr)
     (peg-expr-has-rule-ref? (peg-pred-expr-expr expr)))
    ((peg-gather-expr? expr)
     (or (peg-expr-has-rule-ref? (peg-gather-expr-sep expr))
         (peg-expr-has-rule-ref? (peg-gather-expr-elem expr))))
    ((peg-named-expr? expr)
     (peg-expr-has-rule-ref? (peg-named-expr-expr expr)))
    ((peg-action-expr? expr)
     (peg-expr-has-rule-ref? (peg-action-expr-expr expr)))
    (else #f)))

;;; Tarjan's Strongly Connected Components (deterministic, zero local set!)
;;; State vector slots:
;;;   0: next-index (integer)
;;;   1: index-alist ((sym . int) ...)
;;;   2: lowlink-alist ((sym . int) ...)
;;;   3: stack (list of syms)
;;;   4: on-stack (list of syms)
;;;   5: sccs (list of lists of syms)
(define (%tarjan-assoc-set! state slot key val)
  (let* ((alist (vector-ref state slot))
         (pair (assq key alist)))
    (if pair
        (set-cdr! pair val)
        (vector-set! state slot (cons (cons key val) alist)))))

(define (%tarjan-pop-scc! state root)
  (let loop ((stk (vector-ref state 3))
             (on-stk (vector-ref state 4))
             (comp '()))
    (if (null? stk)
        comp
        (let* ((w (car stk))
               (rest-stk (cdr stk))
               (rest-on (let rm ((xs on-stk) (acc '()))
                          (if (null? xs)
                              (reverse acc)
                              (if (eq? (car xs) w)
                                  (rm (cdr xs) acc)
                                  (rm (cdr xs) (cons (car xs) acc))))))
               (next-comp (cons w comp)))
          (if (eq? w root)
              (begin
                (vector-set! state 3 rest-stk)
                (vector-set! state 4 rest-on)
                (vector-set! state 5 (cons next-comp (vector-ref state 5)))
                next-comp)
              (loop rest-stk rest-on next-comp))))))

(define (peg-compute-tarjan-scc rule-names graph)
  (let ((state (vector 0 '() '() '() '() '())))
    (define (strongconnect v)
      (let ((idx (vector-ref state 0)))
        (vector-set! state 0 (+ idx 1))
        (%tarjan-assoc-set! state 1 v idx)
        (%tarjan-assoc-set! state 2 v idx)
        (vector-set! state 3 (cons v (vector-ref state 3)))
        (vector-set! state 4 (cons v (vector-ref state 4)))
        (let ((neighbors (let ((slot (assq v graph)))
                           (if slot (cdr slot) '()))))
          (for-each
           (lambda (w)
             (if (memq w rule-names)
                 (let ((w-idx-slot (assq w (vector-ref state 1))))
                   (if (not w-idx-slot)
                       (begin
                         (strongconnect w)
                         (let ((v-low (cdr (assq v (vector-ref state 2))))
                               (w-low (cdr (assq w (vector-ref state 2)))))
                           (if (< w-low v-low)
                               (%tarjan-assoc-set! state 2 v w-low))))
                       (if (memq w (vector-ref state 4))
                           (let ((v-low (cdr (assq v (vector-ref state 2))))
                                 (w-idx (cdr w-idx-slot)))
                             (if (< w-idx v-low)
                                 (%tarjan-assoc-set! state 2 v w-idx))))))))
           neighbors))
        (let ((v-low (cdr (assq v (vector-ref state 2))))
              (v-idx (cdr (assq v (vector-ref state 1)))))
          (if (= v-low v-idx)
              (%tarjan-pop-scc! state v)))))
    (for-each
     (lambda (r)
       (if (not (assq r (vector-ref state 1)))
           (strongconnect r)))
     rule-names)
    (reverse (vector-ref state 5))))

(define peg-classify-rules
  (case-lambda
    ((grammar)
     (peg-classify-rules grammar '()))
    ((grammar opts)
     (let* ((mode-slot (assq 'memo-mode opts))
            (memo-mode (if mode-slot (cdr mode-slot) 'auto))
            (no-memo-slot (assq 'no-memo opts))
            (no-memo (if no-memo-slot (cdr no-memo-slot) '()))
            (force-memo-slot (assq 'force-memo opts))
            (force-memo (if force-memo-slot (cdr force-memo-slot) '()))
            (force-lr-slot (assq 'force-lr opts))
            (force-lr (if force-lr-slot (cdr force-lr-slot) '()))
            (rules (peg-grammar-def-rules grammar))
            (rule-names (map peg-rule-def-name rules))
            (nullable (peg-compute-nullable-rules grammar))
            (graph (peg-compute-left-corner-graph grammar nullable))
            (sccs (peg-compute-tarjan-scc rule-names graph))
            (lr-rules
             (let loop ((cs sccs) (acc '()))
               (if (null? cs)
                   acc
                   (let ((c (car cs)))
                     (cond
                       ((> (length c) 1)
                        (loop (cdr cs) (append c acc)))
                       ((= (length c) 1)
                        (let* ((v (car c))
                               (edges (let ((s (assq v graph))) (if s (cdr s) '()))))
                          (if (memq v edges)
                              (loop (cdr cs) (cons v acc))
                              (loop (cdr cs) acc))))
                       (else (loop (cdr cs) acc))))))))
       (map (lambda (r)
              (let* ((name (peg-rule-def-name r))
                     (memo? (peg-rule-def-memoize? r))
                     (cls
                      (cond
                        ((or (eq? memo-mode 'none)
                             (not memo?)
                             (memq name no-memo))
                         'bare)
                        ((memq name force-lr)
                         'lr)
                        ((memq name force-memo)
                         'memo)
                        ((memq name lr-rules)
                         'lr)
                        ((eq? memo-mode 'all)
                         'memo)
                        ((peg-expr-has-rule-ref? (peg-rule-def-expr r))
                         'memo)
                        (else
                         'bare))))
                (cons name cls)))
            rules)))))

;;; -----------------------------------------------------------------------
;;; 3. Regex Pattern Analyzer & Character Class Hoisting
;;; -----------------------------------------------------------------------

;;; Parses regex pattern of form [spec]+, [spec]*, or [spec].
;;; Returns (list 'char-class-repeat kind spec inverted?) or #f
;;; where kind is 'plus | 'star | 'one.
(define (%emit-parse-char-class-regex pat)
  (let ((len (string-length pat)))
    (if (and (> len 2) (char=? (string-ref pat 0) #\[))
        (let loop ((i 1))
          (cond
            ((>= i len) #f)
            ((char=? (string-ref pat i) #\\)
             (loop (+ i 2)))
            ((char=? (string-ref pat i) #\])
             (let* ((inv? (char=? (string-ref pat 1) #\^))
                    (spec (if inv? (substring pat 2 i) (substring pat 1 i)))
                    (after (+ i 1)))
               (cond
                 ((= after len) (list 'one spec inv?))
                 ((and (= (+ after 1) len) (char=? (string-ref pat after) #\+))
                  (list 'plus spec inv?))
                 ((and (= (+ after 1) len) (char=? (string-ref pat after) #\*))
                  (list 'star spec inv?))
                 (else #f))))
            (else (loop (+ i 1)))))
        #f)))

(define (%emit-regex-kind pat)
  (cond
    ((or (string=? pat "(?:\\s+|#[^\\r\\n]*)*")
         (string=? pat "\\s*")
         (string=? pat "\\s+"))
     'meta-ws)
    ((string=? pat "[A-Za-z_][A-Za-z0-9_]*")
     'meta-ident)
    ((or (string=? pat "\"(?:[^\"\\\\]|\\\\.)*\"")
         (string=? pat "'(?:[^'\\\\]|\\\\.)*'"))
     'meta-string-lit)
    ((string=? pat "\\/(?![ \\t\\r\\n])((?:[^\\r\\n\\/]|\\\\.)+)\\/")
     'meta-regex-lit)
    ((string=? pat "\\[\\^?(?:\\\\\\]|[^\\]])+\\]")
     'meta-char-class)
    ((string=? pat "\\\\.")
     'escape-pair)
    ((%emit-parse-char-class-regex pat)
     => (lambda (info) (cons 'cc info)))
    ((string=? pat ".")
     'any-char)
    (else
     'literal)))

;;; Hoists all char-class predicates to deterministic top-level vars.
;;; Returns list of entries: (list key var-name spec inverted?)
(define (%emit-collect-char-classes grammar prefix)
  (let ((state (vector '() 0)))
    (define (add-cc! spec inv?)
      (let ((key (cons spec inv?)))
        (let check ((es (vector-ref state 0)))
          (cond
            ((null? es)
             (let* ((idx (vector-ref state 1))
                    (var (string-append "*" prefix "cc-" (number->string idx) "*")))
               (vector-set! state 0 (cons (list key var spec inv?) (vector-ref state 0)))
               (vector-set! state 1 (+ idx 1))))
            ((equal? (caar es) key) #f)
            (else (check (cdr es)))))))
    (define (walk expr)
      (cond
        ((peg-char-class-expr? expr)
         (add-cc! (peg-char-class-expr-spec expr)
                  (peg-char-class-expr-inverted? expr)))
        ((peg-regex-expr? expr)
         (let ((rk (%emit-regex-kind (peg-regex-expr-pattern expr))))
           (if (and (pair? rk) (eq? (car rk) 'cc))
               (add-cc! (caddr rk) (cadddr rk)))))
        ((peg-seq-expr? expr)
         (for-each walk (peg-seq-expr-elements expr)))
        ((peg-choice-expr? expr)
         (for-each walk (peg-choice-expr-alternatives expr)))
        ((peg-repeat-expr? expr)
         (walk (peg-repeat-expr-expr expr)))
        ((peg-opt-expr? expr)
         (walk (peg-opt-expr-expr expr)))
        ((peg-pred-expr? expr)
         (walk (peg-pred-expr-expr expr)))
        ((peg-gather-expr? expr)
         (walk (peg-gather-expr-sep expr))
         (walk (peg-gather-expr-elem expr)))
        ((peg-named-expr? expr)
         (walk (peg-named-expr-expr expr)))
        ((peg-action-expr? expr)
         (walk (peg-action-expr-expr expr)))))
    (for-each (lambda (r) (walk (peg-rule-def-expr r)))
              (peg-grammar-def-rules grammar))
    (reverse (vector-ref state 0))))

(define (%emit-lookup-cc-var cc-table spec inv?)
  (let ((key (cons spec inv?)))
    (let loop ((es cc-table))
      (cond
        ((null? es) (error "Internal error: unhoisted char-class" key))
        ((equal? (caar es) key) (cadar es))
        (else (loop (cdr es)))))))

;;; -----------------------------------------------------------------------
;;; 4. Direct-Style S-Expression Code Emitter
;;; -----------------------------------------------------------------------

(define (%emit-fresh-var! cnt-box stem)
  (let ((n (vector-ref cnt-box 0)))
    (vector-set! cnt-box 0 (+ n 1))
    (string-append stem (number->string n))))

(define (%emit-expr-has-direct-cut? expr)
  (cond
    ((peg-cut-expr? expr) #t)
    ((peg-seq-expr? expr)
     (let loop ((es (peg-seq-expr-elements expr)))
       (and (pair? es)
            (or (%emit-expr-has-direct-cut? (car es))
                (loop (cdr es))))))
    ((peg-choice-expr? expr)
     (let loop ((as (peg-choice-expr-alternatives expr)))
       (and (pair? as)
            (or (%emit-expr-has-direct-cut? (car as))
                (loop (cdr as))))))
    ((peg-repeat-expr? expr)
     (%emit-expr-has-direct-cut? (peg-repeat-expr-expr expr)))
    ((peg-opt-expr? expr)
     (%emit-expr-has-direct-cut? (peg-opt-expr-expr expr)))
    ((peg-named-expr? expr)
     (%emit-expr-has-direct-cut? (peg-named-expr-expr expr)))
    ((peg-action-expr? expr)
     (%emit-expr-has-direct-cut? (peg-action-expr-expr expr)))
    (else #f)))

(define (%emit-lit-call str pos-var)
  (let ((len (string-length str))
        (qstr (%emit-quote-string str))
        (err-q (%emit-quote-string (string-append "'" str "'"))))
    (if (= len 1)
        (string-append "(peg-ds:lit1 ctx " pos-var " "
                       (%emit-char-literal (string-ref str 0)) " "
                       qstr " " err-q ")")
        (let ((first-ch (if (> len 0)
                            (%emit-char-literal (string-ref str 0))
                            "#f")))
          (string-append "(peg-ds:lit ctx " pos-var " " qstr " "
                         (number->string len) " " first-ch " " err-q ")")))))

(define (%emit-regex-call pat pos-var cc-table)
  (let ((rk (%emit-regex-kind pat)))
    (cond
      ((eq? rk 'meta-ws)
       (string-append "(peg-ds:meta-ws ctx " pos-var ")"))
      ((eq? rk 'meta-ident)
       (string-append "(peg-ds:meta-ident ctx " pos-var ")"))
      ((eq? rk 'meta-string-lit)
       (string-append "(peg-ds:meta-string-lit ctx " pos-var ")"))
      ((eq? rk 'meta-regex-lit)
       (string-append "(peg-ds:meta-regex-lit ctx " pos-var ")"))
      ((eq? rk 'meta-char-class)
       (string-append "(peg-ds:meta-char-class ctx " pos-var ")"))
      ((eq? rk 'escape-pair)
       (string-append "(peg-ds:escape-pair ctx " pos-var ")"))
      ((eq? rk 'any-char)
       (string-append "(peg-ds:any-char ctx " pos-var ")"))
      ((and (pair? rk) (eq? (car rk) 'cc))
       (let* ((kind (cadr rk))
              (spec (caddr rk))
              (inv? (cadddr rk))
              (var (%emit-lookup-cc-var cc-table spec inv?))
              (err-q (%emit-quote-string (string-append "[" (if inv? "^" "") spec "]"))))
         (cond
           ((eq? kind 'plus)
            (string-append "(peg-ds:scan-char-class-plus ctx " pos-var " " var " " err-q ")"))
           ((eq? kind 'star)
            (string-append "(peg-ds:scan-char-class-star ctx " pos-var " " var ")"))
           (else
            (string-append "(peg-ds:char-class ctx " pos-var " " var " " err-q ")")))))
      (else
       (%emit-lit-call pat pos-var)))))

(define (%emit-indent-str n)
  (let ((s (make-string n)))
    (let loop ((i 0))
      (if (< i n)
          (begin
            (string-set! s i #\space)
            (loop (+ i 1)))
          s))))

(define (%emit-expr ctx-env expr pos-var indent)
  (let ((prefix (vector-ref ctx-env 0))
        (extra-call (vector-ref ctx-env 1))
        (cc-table (vector-ref ctx-env 2))
        (cnt-box (vector-ref ctx-env 3))
        (pad (%emit-indent-str indent)))
    (cond
      ((peg-lit-expr? expr)
       (%emit-lit-call (peg-lit-expr-val expr) pos-var))

      ((peg-regex-expr? expr)
       (%emit-regex-call (peg-regex-expr-pattern expr) pos-var cc-table))

      ((peg-char-class-expr? expr)
       (let* ((spec (peg-char-class-expr-spec expr))
              (inv? (peg-char-class-expr-inverted? expr))
              (var (%emit-lookup-cc-var cc-table spec inv?))
              (err-q (%emit-quote-string (string-append "[" (if inv? "^" "") spec "]"))))
         (string-append "(peg-ds:char-class ctx " pos-var " " var " " err-q ")")))

      ((peg-any-char-expr? expr)
       (string-append "(peg-ds:any-char ctx " pos-var ")"))

      ((peg-cut-expr? expr)
       (string-append "(peg-ds:cut ctx " pos-var ")"))

      ((peg-line-start-expr? expr)
       (string-append "(peg-ds:line-start ctx " pos-var ")"))

      ((peg-rule-ref-expr? expr)
       (let ((rname (%emit-assert-valid-ident! (peg-rule-ref-expr-name expr) 'rule-ref)))
         (string-append "(" prefix rname " ctx" extra-call " " pos-var ")")))

      ((peg-named-expr? expr)
       (let* ((name-str (%emit-assert-valid-ident! (peg-named-expr-name expr) 'named-expr))
              (p-var (%emit-fresh-var! cnt-box "np_"))
              (inner-code (%emit-expr ctx-env (peg-named-expr-expr expr) pos-var (+ indent 6))))
         (string-append "(let ((" p-var " " inner-code "))\n"
                        pad "  (if " p-var "\n"
                        pad "      (begin\n"
                        pad "        (parse-ctx-res-val-set! ctx (cons '" name-str " (parse-ctx-res-val ctx)))\n"
                        pad "        " p-var ")\n"
                        pad "      #f))")))

      ((peg-action-expr? expr)
       ;; CWE-94: Never emit raw Python action code as executable Scheme; evaluate inner expr directly.
       (%emit-expr ctx-env (peg-action-expr-expr expr) pos-var indent))

      ((peg-opt-expr? expr)
       (let* ((p-var (%emit-fresh-var! cnt-box "opt_"))
              (inner-code (%emit-expr ctx-env (peg-opt-expr-expr expr) pos-var (+ indent 6))))
         (string-append "(let ((" p-var " " inner-code "))\n"
                        pad "  (if " p-var "\n"
                        pad "      " p-var "\n"
                        pad "      (begin (parse-ctx-res-val-set! ctx #f) " pos-var ")))")))

      ((peg-pred-expr? expr)
       (let* ((pos? (peg-pred-expr-positive? expr))
              (p-var (%emit-fresh-var! cnt-box "pred_"))
              (inner-code (%emit-expr ctx-env (peg-pred-expr-expr expr) pos-var (+ indent 6))))
         (if pos?
             (string-append "(let ((" p-var " " inner-code "))\n"
                            pad "  (if " p-var "\n"
                            pad "      (begin (parse-ctx-res-val-set! ctx #t) " pos-var ")\n"
                            pad "      #f))")
             (string-append "(let ((" p-var " " inner-code "))\n"
                            pad "  (if " p-var "\n"
                            pad "      #f\n"
                            pad "      (begin (parse-ctx-res-val-set! ctx #t) " pos-var ")))"))))

      ((peg-seq-expr? expr)
       (let ((elts (peg-seq-expr-elements expr)))
         (cond
           ((null? elts)
            (string-append "(begin (parse-ctx-res-val-set! ctx '()) " pos-var ")"))
           ((null? (cdr elts))
            (let* ((p-var (%emit-fresh-var! cnt-box "s_"))
                   (e-code (%emit-expr ctx-env (car elts) pos-var (+ indent 6))))
              (string-append "(let ((" p-var " " e-code "))\n"
                             pad "  (if " p-var "\n"
                             pad "      (begin (parse-ctx-res-val-set! ctx (list (parse-ctx-res-val ctx))) " p-var ")\n"
                             pad "      #f))")))
           (else
            (let build-seq ((rem elts) (cur-pos pos-var) (val-vars '()) (ind indent))
              (let ((cur-pad (%emit-indent-str ind)))
                (if (null? rem)
                    (string-append "(begin\n"
                                   cur-pad "  (parse-ctx-res-val-set! ctx (list " (%emit-strings-join (reverse val-vars) " ") "))\n"
                                   cur-pad "  " cur-pos ")")
                    (let* ((p-var (%emit-fresh-var! cnt-box "sp_"))
                           (v-var (%emit-fresh-var! cnt-box "sv_"))
                           (e-code (%emit-expr ctx-env (car rem) cur-pos (+ ind 6)))
                           (tail-code (build-seq (cdr rem) p-var (cons v-var val-vars) (+ ind 10))))
                      (string-append "(let ((" p-var " " e-code "))\n"
                                     cur-pad "  (if " p-var "\n"
                                     cur-pad "      (let ((" v-var " (parse-ctx-res-val ctx)))\n"
                                     cur-pad "        " tail-code ")\n"
                                     cur-pad "      #f))")))))))))

      ((peg-choice-expr? expr)
       (let ((alts (peg-choice-expr-alternatives expr)))
         (cond
           ((null? alts) "#f")
           ((null? (cdr alts))
            (%emit-expr ctx-env (car alts) pos-var indent))
           ((not (%emit-expr-has-direct-cut? expr))
            (let ((rendered
                   (map (lambda (a) (%emit-expr ctx-env a pos-var (+ indent 4)))
                        alts)))
              (string-append "(or\n"
                             pad "  "
                             (%emit-strings-join rendered (string-append "\n" pad "  "))
                             ")")))
           (else
            (let ((saved-cut (%emit-fresh-var! cnt-box "scut_")))
              (define (build-alts rem ind)
                (let ((cur-pad (%emit-indent-str ind)))
                  (if (null? rem)
                      (string-append "(begin (parse-ctx-cut?-set! ctx " saved-cut ") #f)")
                      (let* ((p-var (%emit-fresh-var! cnt-box "ap_"))
                             (alt-code (%emit-expr ctx-env (car rem) pos-var (+ ind 6)))
                             (rest-code (build-alts (cdr rem) (+ ind 10))))
                        (string-append "(begin\n"
                                       cur-pad "  (parse-ctx-cut?-set! ctx #f)\n"
                                       cur-pad "  (let ((" p-var " " alt-code "))\n"
                                       cur-pad "    (if " p-var "\n"
                                       cur-pad "        (begin (parse-ctx-cut?-set! ctx " saved-cut ") " p-var ")\n"
                                       cur-pad "        (if (parse-ctx-cut? ctx)\n"
                                       cur-pad "            (begin (parse-ctx-cut?-set! ctx " saved-cut ") #f)\n"
                                       cur-pad "            " rest-code "))))")))))
              (string-append "(let ((" saved-cut " (parse-ctx-cut? ctx)))\n"
                             pad "  " (build-alts alts (+ indent 2)) ")"))))))

      ((peg-repeat-expr? expr)
       (let* ((min-c (peg-repeat-expr-min-count expr))
              (inner (peg-repeat-expr-expr expr))
              (loop-var (%emit-fresh-var! cnt-box "rloop_"))
              (cur-var (%emit-fresh-var! cnt-box "rcur_"))
              (acc-var (%emit-fresh-var! cnt-box "racc_"))
              (next-var (%emit-fresh-var! cnt-box "rnext_")))
         (if (= min-c 1)
             (let* ((p1-var (%emit-fresh-var! cnt-box "rp1_"))
                    (v1-var (%emit-fresh-var! cnt-box "rv1_"))
                    (first-code (%emit-expr ctx-env inner pos-var (+ indent 6)))
                    (loop-code (%emit-expr ctx-env inner cur-var (+ indent 14))))
               (string-append "(let ((" p1-var " " first-code "))\n"
                              pad "  (if " p1-var "\n"
                              pad "      (let ((" v1-var " (parse-ctx-res-val ctx)))\n"
                              pad "        (if (<= " p1-var " " pos-var ")\n"
                              pad "            (begin (parse-ctx-res-val-set! ctx (list " v1-var ")) " p1-var ")\n"
                              pad "            (let " loop-var " ((" cur-var " " p1-var ") (" acc-var " (list " v1-var ")))\n"
                              pad "              (let ((" next-var " " loop-code "))\n"
                              pad "                (if (and " next-var " (> " next-var " " cur-var "))\n"
                              pad "                    (" loop-var " " next-var " (cons (parse-ctx-res-val ctx) " acc-var "))\n"
                              pad "                    (begin (parse-ctx-res-val-set! ctx (reverse " acc-var ")) " cur-var "))))))\n"
                              pad "      #f))"))
             (let ((loop-code (%emit-expr ctx-env inner cur-var (+ indent 6))))
               (string-append "(let " loop-var " ((" cur-var " " pos-var ") (" acc-var " '()))\n"
                              pad "  (let ((" next-var " " loop-code "))\n"
                              pad "    (if (and " next-var " (> " next-var " " cur-var "))\n"
                              pad "        (" loop-var " " next-var " (cons (parse-ctx-res-val ctx) " acc-var "))\n"
                              pad "        (begin (parse-ctx-res-val-set! ctx (reverse " acc-var ")) " cur-var "))))")))))

      ((peg-gather-expr? expr)
       (let* ((one+ (peg-gather-expr-one-or-more? expr))
              (sep (peg-gather-expr-sep expr))
              (elem (peg-gather-expr-elem expr))
              (p1-var (%emit-fresh-var! cnt-box "gp1_"))
              (v1-var (%emit-fresh-var! cnt-box "gv1_"))
              (loop-var (%emit-fresh-var! cnt-box "gloop_"))
              (cur-var (%emit-fresh-var! cnt-box "gcur_"))
              (acc-var (%emit-fresh-var! cnt-box "gacc_"))
              (spos-var (%emit-fresh-var! cnt-box "gsp_"))
              (epos-var (%emit-fresh-var! cnt-box "gep_"))
              (first-code (%emit-expr ctx-env elem pos-var (+ indent 6)))
              (sep-code (%emit-expr ctx-env sep cur-var (+ indent 14)))
              (elem-code (%emit-expr ctx-env elem spos-var (+ indent 18)))
              (fail-branch (if one+
                               "#f"
                               (string-append "(begin (parse-ctx-res-val-set! ctx '()) " pos-var ")"))))
         (string-append "(let ((" p1-var " " first-code "))\n"
                        pad "  (if " p1-var "\n"
                        pad "      (let ((" v1-var " (parse-ctx-res-val ctx)))\n"
                        pad "        (let " loop-var " ((" cur-var " " p1-var ") (" acc-var " (list " v1-var ")))\n"
                        pad "          (let ((" spos-var " " sep-code "))\n"
                        pad "            (if " spos-var "\n"
                        pad "                (let ((" epos-var " " elem-code "))\n"
                        pad "                  (if (and " epos-var " (> " epos-var " " cur-var "))\n"
                        pad "                      (" loop-var " " epos-var " (cons (parse-ctx-res-val ctx) " acc-var "))\n"
                        pad "                      (begin (parse-ctx-res-val-set! ctx (reverse " acc-var ")) " cur-var ")))\n"
                        pad "                (begin (parse-ctx-res-val-set! ctx (reverse " acc-var ")) " cur-var ")))))\n"
                        pad "      " fail-branch "))")))

      (else
       (error "Unknown AST expression node in emit_scheme" expr)))))

(define (%emit-rule-definition rule cls-alist opts ctx-env)
  (let* ((name (peg-rule-def-name rule))
         (name-str (%emit-assert-valid-ident! name 'rule-def))
         (prefix (vector-ref ctx-env 0))
         (extra-call (vector-ref ctx-env 1))
         (cnt-box (vector-ref ctx-env 3))
         (grammar-name (vector-ref ctx-env 4))
         (overrides (let ((s (assq 'overrides opts))) (if s (cdr s) '())))
         (decorators (let ((s (assq 'decorators opts))) (if s (cdr s) '())))
         (ctx-decorators (let ((s (assq 'ctx-decorators opts))) (if s (cdr s) '())))
         (rule-dec-slot (assq 'rule-decorator opts))
         (override-slot (assq name overrides))
         (decorator-slot (assq name decorators))
         (ctx-dec-slot (assq name ctx-decorators))
         (rule-dec-fn (if (and rule-dec-slot
                               (pair? (cdr rule-dec-slot))
                               (memq name (cddr rule-dec-slot)))
                          (cadr rule-dec-slot)
                          #f))
         (cls (let ((s (assq name cls-alist))) (if s (cdr s) 'bare)))
         (meta? (eq? grammar-name 'MetaGrammar))
         (raw-body
          (cond
            (override-slot (cdr override-slot))
            ((and meta? (eq? name 'action_block))
             "(peg-ds:meta-action-block ctx pos)")
            ((and meta? (eq? name 'new_rule_head))
             "(peg-ds:meta-new-rule-head ctx pos)")
            ((and meta? (eq? name 'choice_expr))
             (string-append "(let ((pos (peg-ds:meta-opt-lead-pipe ctx pos)))\n      "
                            (%emit-expr ctx-env (peg-rule-def-expr rule) "pos" 6)
                            ")"))
            (else
             (%emit-expr ctx-env (peg-rule-def-expr rule) "pos" 4))))
         (decorated-body
          (cond
            (ctx-dec-slot
             (let ((dvar (%emit-fresh-var! cnt-box "cdec_"))
                   (dfn (%emit-assert-valid-fn-ident! (cdr ctx-dec-slot) 'ctx-decorator)))
               (string-append "(let ((" dvar " " raw-body "))\n"
                              "      (if " dvar "\n"
                              "          (" dfn " ctx" extra-call " pos " dvar " (parse-ctx-res-val ctx))\n"
                              "          #f))")))
            (rule-dec-fn
             (let ((dvar (%emit-fresh-var! cnt-box "rdec_"))
                   (dfn (%emit-assert-valid-fn-ident! rule-dec-fn 'rule-decorator)))
               (string-append "(let ((" dvar " " raw-body "))\n"
                              "      (if " dvar "\n"
                              "          (" dfn " '" name-str " ctx" extra-call " pos " dvar " (parse-ctx-res-val ctx))\n"
                              "          #f))")))
            (decorator-slot
             (let ((dvar (%emit-fresh-var! cnt-box "dec_"))
                   (dfn (%emit-assert-valid-fn-ident! (cdr decorator-slot) 'decorator)))
               (string-append "(let ((" dvar " " raw-body "))\n"
                              "      (if " dvar "\n"
                              "          (begin\n"
                              "            (parse-ctx-res-val-set! ctx (" dfn " (parse-ctx-res-val ctx)))\n"
                              "            " dvar ")\n"
                              "          #f))")))
            (else raw-body)))
         (wrapped-body
          (cond
            ((eq? cls 'lr)
             (string-append "  (peg-ds:rule-lr ctx '" name-str " pos\n"
                            "    (lambda ()\n      " decorated-body "))"))
            ((eq? cls 'memo)
             (string-append "  (peg-ds:rule-memo ctx '" name-str " pos\n"
                            "    (lambda ()\n      " decorated-body "))"))
            (else
             (string-append "  " decorated-body)))))
    (string-append ";;; Rule: " name-str " [" (symbol->string cls) "]\n"
                   "(define (" prefix name-str " ctx" extra-call " pos)\n"
                   wrapped-body ")\n")))

(define (%emit-peg-grammar->scheme grammar opts)
  (let* ((gname (peg-grammar-def-name grammar))
         (gname-str (%emit-assert-valid-ident! gname 'grammar-name))
         (prefix-raw (let ((s (assq 'prefix opts))) (if s (cdr s) "peg-")))
         (prefix (%emit-assert-valid-ident! prefix-raw 'prefix))
         (rules (peg-grammar-def-rules grammar))
         (first-rule (if (pair? rules)
                         (peg-rule-def-name (car rules))
                         (error "Grammar has no rules defined" gname)))
         (entry-sym (let ((s (assq 'entry opts))) (if (and s (cdr s)) (cdr s) first-rule)))
         (entry-str (%emit-assert-valid-ident! entry-sym 'entry))
         (extra-params (let ((s (assq 'extra-params opts))) (if s (cdr s) '())))
         (extra-param-strs
          (map (lambda (p) (%emit-assert-valid-ident! p 'extra-param))
               extra-params))
         (extra-call (if (null? extra-param-strs)
                         ""
                         (string-append " " (%emit-strings-join extra-param-strs " "))))
         (cls-alist (peg-classify-rules grammar opts))
         (cc-table (%emit-collect-char-classes grammar prefix))
         (ctx-env (vector prefix extra-call cc-table (vector 0) gname))
         (header-lines
          (string-append
           ";;; =======================================================================\n"
           ";;; Auto-generated Direct-Style Static Scheme PEG Parser (Issue #948)\n"
           ";;; Grammar: " gname-str " | Prefix: " prefix " | Entry: " entry-str "\n"
           ";;; Zero CPS combinators, zero closure chains, zero local set!.\n"
           ";;; =======================================================================\n\n"))
         (cc-defs
          (if (null? cc-table)
              ""
              (string-append
               ";;; Hoisted Character Class Predicates\n"
               (%emit-strings-join
                (map (lambda (entry)
                       (let ((var (cadr entry))
                             (spec (caddr entry))
                             (inv? (cadddr entry)))
                         (string-append "(define " var " (make-char-class-pred "
                                        (%emit-quote-string spec) " "
                                        (if inv? "#t" "#f") "))")))
                     cc-table)
                "\n")
               "\n\n")))
         (rule-defs
          (%emit-strings-join
           (map (lambda (r) (%emit-rule-definition r cls-alist opts ctx-env))
                rules)
           "\n"))
         (entry-defs
          (if (null? extra-param-strs)
              (string-append
               "\n;;; Top-Level Direct-Style Parser Entrypoints\n"
               "(define " prefix "parse-partial\n"
               "  (case-lambda\n"
               "    ((text)\n"
               "     (peg-ds:parse-partial " prefix entry-str " text))\n"
               "    ((text pos)\n"
               "     (peg-ds:parse-partial " prefix entry-str " text pos))))\n\n"
               "(define (" prefix "parse text)\n"
               "  (peg-ds:parse " prefix entry-str " text))\n")
              (string-append
               "\n;;; Top-Level Direct-Style Parser Entrypoints\n"
               "(define " prefix "parse-partial\n"
               "  (case-lambda\n"
               "    ((" (%emit-strings-join extra-param-strs " ") " text)\n"
               "     (peg-ds:parse-partial (lambda (ctx pos) (" prefix entry-str " ctx" extra-call " pos)) text))\n"
               "    ((" (%emit-strings-join extra-param-strs " ") " text start-pos)\n"
               "     (peg-ds:parse-partial (lambda (ctx pos) (" prefix entry-str " ctx" extra-call " pos)) text start-pos))))\n\n"
               "(define (" prefix "parse" extra-call " text)\n"
               "  (peg-ds:parse (lambda (ctx pos) (" prefix entry-str " ctx" extra-call " pos)) text))\n"))))
    (string-append header-lines cc-defs rule-defs entry-defs)))

;;; -----------------------------------------------------------------------
;;; 5. Self-Hosting MetaGrammar CST -> <peg-grammar-def> AST Transformer
;;; -----------------------------------------------------------------------

(define (%peg-cst-ident-sym ident-cst)
  (cdr (assq 'name ident-cst)))

(define (%peg-cst-primary->ast p)
  (cond
    ((and (pair? p) (eq? (car p) 'raw))
     (let ((inner (cdr p)))
       (cond
         ((assq 's inner) => (lambda (slot) (make-peg-lit-expr (cdr slot))))
         ((assq 'r inner) => (lambda (slot) (make-peg-regex-expr (cdr slot))))
         ((assq 'raw inner) =>
          (lambda (slot)
            (let ((cc (cdr slot)))
              (make-peg-char-class-expr (car cc) (cdr cc)))))
         (else (error "Unknown raw primary CST" p)))))
    ((and (pair? p) (eq? (car p) 'name))
     (make-peg-rule-ref-expr (%peg-cst-ident-sym (cdr p))))
    ((and (pair? p) (equal? (car p) "."))
     (make-peg-any-char-expr))
    ((and (pair? p) (equal? (car p) "("))
     (%peg-cst-choice->ast (cdr (assq 'ch p))))
    ((and (pair? p) (equal? (car p) "["))
     (make-peg-opt-expr (%peg-cst-choice->ast (cdr (assq 'ch p)))))
    (else (error "Unknown primary CST in peg-meta-cst->ast" p))))

(define (%peg-cst-suffixed->ast s)
  (cond
    ((and (pair? s) (assq 'sep s))
     (let* ((sep-ast (%peg-cst-primary->ast (cdr (assq 'sep s))))
            (elem-ast (%peg-cst-primary->ast (cdr (assq 'elem s))))
            (op-str (cdr (assq 'op s))))
       (make-peg-gather-expr sep-ast elem-ast (string=? op-str "+"))))
    ((and (pair? s) (assq 'expr s))
     (let* ((base-ast (%peg-cst-primary->ast (cdr (assq 'expr s))))
            (op-slot (assq 'op s))
            (op-cst (if op-slot (cdr op-slot) #f))
            (op-str (if (and (pair? op-cst) (assq 'op op-cst))
                        (cdr (assq 'op op-cst))
                        #f)))
       (cond
         ((not op-str) base-ast)
         ((string=? op-str "*") (make-peg-repeat-expr base-ast 0 #f))
         ((string=? op-str "+") (make-peg-repeat-expr base-ast 1 #f))
         ((string=? op-str "?") (make-peg-opt-expr base-ast))
         (else base-ast))))
    (else (%peg-cst-primary->ast s))))

(define (%peg-cst-prefix-item->ast item)
  (cond
    ((and (pair? item) (equal? (car item) "~"))
     (make-peg-cut-expr))
    ((and (pair? item) (equal? (car item) "&"))
     (make-peg-pred-expr (%peg-cst-suffixed->ast (cdr (assq 'expr item))) #t))
    ((and (pair? item) (equal? (car item) "!"))
     (make-peg-pred-expr (%peg-cst-suffixed->ast (cdr (assq 'expr item))) #f))
    ((and (pair? item) (assq 'name item) (assq 'expr item))
     (make-peg-named-expr (%peg-cst-ident-sym (cdr (assq 'name item)))
                          (%peg-cst-suffixed->ast (cdr (assq 'expr item)))))
    (else (%peg-cst-suffixed->ast item))))

(define (%peg-cst-seq->ast seq-cst)
  (let* ((prefixed-list (if (and (pair? seq-cst) (eq? (car seq-cst) 'items))
                            (cdr seq-cst)
                            (cdr (assq 'items seq-cst))))
         (elts (map (lambda (pf) (%peg-cst-prefix-item->ast (cdr (assq 'item pf))))
                    prefixed-list)))
    (if (and (pair? elts) (null? (cdr elts)))
        (car elts)
        (make-peg-seq-expr elts))))

(define (%peg-cst-alt->ast alt-cst)
  (let* ((seq-ast (%peg-cst-seq->ast (cdr (assq 'seq alt-cst))))
         (act (cdr (assq 'act alt-cst))))
    (if act
        (make-peg-action-expr seq-ast act)
        seq-ast)))

(define (%peg-cst-choice->ast ch-cst)
  (let* ((first-ast (%peg-cst-alt->ast (cdr (assq 'first ch-cst))))
         (rest-csts (cdr (assq 'rest ch-cst)))
         (rest-asts (map (lambda (rc) (%peg-cst-alt->ast (cdr (assq 'alt rc))))
                         rest-csts)))
    (if (null? rest-asts)
        first-ast
        (make-peg-choice-expr (cons first-ast rest-asts)))))

(define (%peg-cst-rule->ast r-cst)
  (let* ((rname (%peg-cst-ident-sym (cdr (assq 'name r-cst))))
         (ch-ast (%peg-cst-choice->ast (cdr (assq 'ch r-cst))))
         (act (cdr (assq 'act r-cst)))
         (body (if act (make-peg-action-expr ch-ast act) ch-ast)))
    (make-peg-rule-def rname body #t #f)))

(define (peg-meta-cst->ast cst)
  (let* ((g-slot (assq 'g_decl cst))
         (g-cst (if g-slot (cdr g-slot) #f))
         (gname (if (and (pair? g-cst) (assq 'name g-cst))
                    (%peg-cst-ident-sym (cdr (assq 'name g-cst)))
                    'AnonymousGrammar))
         (h-slot (assq 'h_decl cst))
         (h-cst (if h-slot (cdr h-slot) #f))
         (directives (if (and (pair? h-cst) (assq 'act h-cst))
                         (list (list '@header (cdr (assq 'act h-cst))))
                         '()))
         (rules-csts (cdr (assq 'rules cst)))
         (rules (map %peg-cst-rule->ast rules-csts)))
    (make-peg-grammar-def gname rules directives)))
