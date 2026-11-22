;;; =======================================================================
;;; Packrat PEG Runtime Engine with Double Continuations (CPS) & Warth Left-Recursion
;;; Conforms to DSN-25 & DSN-33-04 §3.1, Issue #894
;;; Zero external dependencies.
;;; =======================================================================

;;; -----------------------------------------------------------------------
;;; 1. Data Structures: <parse-context> and <memo-entry>
;;; -----------------------------------------------------------------------

(define-record-type <parse-context>
  (%make-parse-context text length max-pos expected memo lr-detected in-progress touched-lr depth max-depth)
  parse-context?
  (text         parse-ctx-text)
  (length       parse-ctx-length)
  (max-pos      parse-ctx-max-pos      parse-ctx-max-pos-set!)
  (expected     parse-ctx-expected     parse-ctx-expected-set!)
  (memo         parse-ctx-memo         parse-ctx-raw-memo-set!)
  (lr-detected  parse-ctx-lr-detected  parse-ctx-lr-detected-set!)
  (in-progress  parse-ctx-in-progress  parse-ctx-in-progress-set!)
  (touched-lr   parse-ctx-touched-lr   parse-ctx-touched-lr-set!)
  (depth        parse-ctx-depth        parse-ctx-depth-set!)
  (max-depth    parse-ctx-max-depth))

(define (make-parse-context text . maybe-max-depth)
  (let ((len (string-length text))
        (max-d (if (pair? maybe-max-depth) (car maybe-max-depth) 10000)))
    (%make-parse-context text len 0 '() (make-vector (+ len 1) '()) '() '() '() 0 max-d)))

(define-record-type <memo-entry>
  (%make-memo-entry status val end-pos growing? lr-deps)
  memo-entry?
  (status   memo-entry-status   memo-entry-status-set!)
  (val      memo-entry-val      memo-entry-val-set!)
  (end-pos  memo-entry-end-pos  memo-entry-end-pos-set!)
  (growing? memo-entry-growing? memo-entry-growing?-set!)
  (lr-deps  memo-entry-lr-deps  memo-entry-lr-deps-set!))

(define (make-memo-entry status val end-pos . rest)
  (let ((g? (if (pair? rest) (car rest) #f))
        (deps (if (and (pair? rest) (pair? (cdr rest))) (cadr rest) '())))
    (%make-memo-entry status val end-pos g? deps)))

;;; -----------------------------------------------------------------------
;;; 2. Context Operations & Memoization Table
;;; -----------------------------------------------------------------------

(define (parse-ctx-update-max-pos! ctx pos expected-tok)
  (let ((curr-max (parse-ctx-max-pos ctx)))
    (cond
      ((> pos curr-max)
       (parse-ctx-max-pos-set! ctx pos)
       (parse-ctx-expected-set! ctx (list expected-tok)))
      ((= pos curr-max)
       (let ((exp (parse-ctx-expected ctx)))
         (if (not (member expected-tok exp))
             (parse-ctx-expected-set! ctx (cons expected-tok exp))))))))

(define (parse-ctx-memo-ref ctx key)
  (let* ((vec (parse-ctx-memo ctx))
         (rule (car key))
         (pos (cdr key))
         (bucket (vector-ref vec pos)))
    (cond
      ((assq rule bucket) => cdr)
      (else #f))))

(define (parse-ctx-memo-set! ctx key entry)
  (let* ((vec (parse-ctx-memo ctx))
         (rule (car key))
         (pos (cdr key))
         (bucket (vector-ref vec pos))
         (slot (assq rule bucket)))
    (if slot
        (set-cdr! slot entry)
        (vector-set! vec pos (cons (cons rule entry) bucket)))))

(define (parse-ctx-touched-lr-add! ctx key)
  (let ((cur (parse-ctx-touched-lr ctx)))
    (if (not (member key cur))
        (parse-ctx-touched-lr-set! ctx (cons key cur)))))

(define (parse-ctx-touched-lr-merge! ctx keys)
  (for-each (lambda (k) (parse-ctx-touched-lr-add! ctx k)) keys))

(define (%filter-out-key lst target-key)
  (let loop ((xs lst) (acc '()))
    (cond
      ((null? xs) acc)
      ((equal? (car xs) target-key) (loop (cdr xs) acc))
      (else (loop (cdr xs) (cons (car xs) acc))))))

(define (parse-ctx-lr-detected? ctx key)
  (member key (parse-ctx-lr-detected ctx)))

(define (parse-ctx-lr-detected-add! ctx key)
  (let ((lr (parse-ctx-lr-detected ctx)))
    (if (not (member key lr))
        (parse-ctx-lr-detected-set! ctx (cons key lr)))))

(define (parse-ctx-lr-detected-delete! ctx key)
  (let loop ((lst (parse-ctx-lr-detected ctx)) (acc '()))
    (cond
      ((null? lst)
       (parse-ctx-lr-detected-set! ctx acc))
      ((equal? (car lst) key)
       (parse-ctx-lr-detected-set! ctx (append acc (cdr lst))))
      (else
       (loop (cdr lst) (cons (car lst) acc))))))

(define (parse-ctx-in-progress? ctx key)
  (member key (parse-ctx-in-progress ctx)))

(define (parse-ctx-in-progress-add! ctx key)
  (let ((inp (parse-ctx-in-progress ctx)))
    (if (not (member key inp))
        (parse-ctx-in-progress-set! ctx (cons key inp)))))

(define (parse-ctx-in-progress-delete! ctx key)
  (let loop ((lst (parse-ctx-in-progress ctx)) (acc '()))
    (cond
      ((null? lst)
       (parse-ctx-in-progress-set! ctx acc))
      ((equal? (car lst) key)
       (parse-ctx-in-progress-set! ctx (append acc (cdr lst))))
      (else
       (loop (cdr lst) (cons (car lst) acc))))))

(define (parse-ctx-clear-lr-dependent-memo! ctx pos current-key)
  ;; Only clear memo entries at pos that actually depended on an active left-recursive seed
  (let* ((vec (parse-ctx-memo ctx))
         (curr-rule (car current-key))
         (bucket (vector-ref vec pos))
         (filtered
          (let loop ((lst bucket) (acc '()))
            (if (null? lst)
                acc
                (let* ((pair (car lst))
                       (rname (car pair))
                       (entry (cdr pair)))
                  (if (and (not (eq? rname curr-rule))
                           (pair? (memo-entry-lr-deps entry)))
                      (loop (cdr lst) acc)
                      (loop (cdr lst) (cons pair acc))))))))
    (vector-set! vec pos filtered)))

;;; -----------------------------------------------------------------------
;;; 3. Character Class Helper
;;; -----------------------------------------------------------------------

(define (%unescape-class-char ch)
  (case ch
    ((#\n) #\newline)
    ((#\t) #\tab)
    ((#\r) #\return)
    ((#\\) #\\)
    ((#\]) #\])
    ((#\-) #\-)
    (else ch)))

(define (%tokenize-char-class-spec spec)
  (let ((len (string-length spec)))
    (let loop ((i 0) (acc '()))
      (cond
        ((>= i len) (reverse acc))
        ((and (char=? (string-ref spec i) #\\) (< (+ i 1) len))
         (loop (+ i 2) (cons (cons 'lit (%unescape-class-char (string-ref spec (+ i 1)))) acc)))
        (else
         (loop (+ i 1) (cons (cons 'raw (string-ref spec i)) acc)))))))

(define (make-char-class-pred spec inverted?)
  (let* ((tokens (%tokenize-char-class-spec spec))
         (ranges
          (let loop ((ts tokens) (acc '()))
            (cond
              ((null? ts) acc)
              ((and (pair? (cdr ts))
                    (pair? (cddr ts))
                    (eq? (caadr ts) 'raw)
                    (char=? (cdadr ts) #\-))
               (let ((c-start (cdar ts))
                     (c-end (cdaddr ts)))
                 (loop (cdddr ts) (cons (cons c-start c-end) acc))))
              (else
               (loop (cdr ts) (cons (cdar ts) acc)))))))
    (lambda (ch)
      (let test ((r ranges))
        (cond
          ((null? r)
           (if inverted? #t #f))
          ((pair? (car r))
           (let ((c-start (caar r))
                 (c-end (cdar r)))
             (if (and (char>=? ch c-start) (char<=? ch c-end))
                 (if inverted? #f #t)
                 (test (cdr r)))))
          ((char=? ch (car r))
           (if inverted? #f #t))
          (else
           (test (cdr r))))))))

;;; -----------------------------------------------------------------------
;;; 4. Double CPS PEG Combinators
;;; Parser signature: (lambda (ctx pos sk fk) ...)
;;;   sk: (lambda (val next-pos fk) ...)
;;;   fk: (lambda () ...)
;;; -----------------------------------------------------------------------

;;; Literal string match
(define (peg:lit str)
  (let ((lit-len (string-length str))
        (err-label (string-append "'" str "'"))
        (first-ch (if (> (string-length str) 0) (string-ref str 0) #f)))
    (lambda (ctx pos sk fk)
      (let ((txt (parse-ctx-text ctx))
            (total-len (parse-ctx-length ctx)))
        (if (and (<= (+ pos lit-len) total-len)
                 (or (= lit-len 0)
                     (and (char=? (string-ref txt pos) first-ch)
                          (or (= lit-len 1)
                              (string=? (substring txt pos (+ pos lit-len)) str)))))
            (sk str (+ pos lit-len) fk)
            (begin
              (parse-ctx-update-max-pos! ctx pos err-label)
              (fk)))))))

;;; Character class match
(define (peg:char-class spec . maybe-inverted)
  (let* ((inverted? (if (pair? maybe-inverted) (car maybe-inverted) #f))
         (pred (make-char-class-pred spec inverted?))
         (err-label (string-append "[" spec "]")))
    (lambda (ctx pos sk fk)
      (let ((txt (parse-ctx-text ctx))
            (total-len (parse-ctx-length ctx)))
        (if (and (< pos total-len)
                 (pred (string-ref txt pos)))
            (sk (string (string-ref txt pos)) (+ pos 1) fk)
            (begin
              (parse-ctx-update-max-pos! ctx pos err-label)
              (fk)))))))

;;; Any character match (.)
(define (peg:any-char)
  (lambda (ctx pos sk fk)
    (let ((txt (parse-ctx-text ctx))
          (total-len (parse-ctx-length ctx)))
      (if (< pos total-len)
          (sk (string (string-ref txt pos)) (+ pos 1) fk)
          (begin
            (parse-ctx-update-max-pos! ctx pos "any-char")
            (fk))))))

;;; Line-start assertion (pos == 0 or preceded by newline)
(define (peg:line-start)
  (lambda (ctx pos sk fk)
    (if (= pos 0)
        (sk "" pos fk)
        (let ((txt (parse-ctx-text ctx)))
          (let ((prev-ch (string-ref txt (- pos 1))))
            (if (or (char=? prev-ch #\newline) (char=? prev-ch #\return))
                (sk "" pos fk)
                (fk)))))))

;;; Cut operator (~) : sets a cut flag to commit current alternative
(define (peg:cut)
  (lambda (ctx pos sk fk)
    ;; Cut always succeeds, but modifies fk to signal commit
    (sk 'cut pos (lambda () (fk)))))

;;; Sequence combinator: e1 e2 ...
(define (peg:seq . parsers)
  (cond
    ((null? parsers)
     (lambda (ctx pos sk fk) (sk '() pos fk)))
    ((null? (cdr parsers))
     (let ((p (car parsers)))
       (lambda (ctx pos sk fk)
         (p ctx pos
            (lambda (v next-pos inner-fk)
              (sk (list v) next-pos inner-fk))
            fk))))
    (else
     (lambda (ctx pos sk fk)
       (let loop ((ps parsers) (curr-pos pos) (vals '()) (curr-fk fk))
         (if (null? ps)
             (sk (reverse vals) curr-pos curr-fk)
             (let ((p (car ps)))
               (p ctx curr-pos
                  (lambda (v next-pos next-fk)
                    (loop (cdr ps) next-pos (cons v vals) next-fk))
                  curr-fk))))))))

;;; Ordered Choice combinator: e1 | e2 | ...
(define (peg:alt . parsers)
  (cond
    ((null? parsers)
     (lambda (ctx pos sk fk) (fk)))
    ((null? (cdr parsers))
     (car parsers))
    (else
     (lambda (ctx pos sk fk)
       (let loop ((ps parsers))
         (if (null? ps)
             (fk)
             (let ((p (car ps)))
               (p ctx pos
                  sk
                  (lambda ()
                    (loop (cdr ps)))))))))))

;;; Repetition: 0 or more (*) with progress guard against infinite loops
(define (peg:star parser)
  (lambda (ctx pos sk fk)
    (let loop ((curr-pos pos) (vals '()) (curr-fk fk))
      (parser ctx curr-pos
              (lambda (v next-pos inner-fk)
                (if (<= next-pos curr-pos)
                    ;; Zero-width match: stop repetition to prevent infinite loop
                    (sk (reverse vals) curr-pos inner-fk)
                    (loop next-pos (cons v vals) inner-fk)))
              (lambda ()
                ;; No more matches: succeed with accumulated values
                (sk (reverse vals) curr-pos curr-fk))))))

;;; Repetition: 1 or more (+)
(define (peg:plus parser)
  (lambda (ctx pos sk fk)
    (parser ctx pos
            (lambda (v1 next-pos1 inner-fk)
              ((peg:star parser) ctx next-pos1
               (lambda (vrest next-pos2 final-fk)
                 (sk (cons v1 vrest) next-pos2 final-fk))
               inner-fk))
            fk)))

;;; Optional: 0 or 1 (?)
(define (peg:opt parser)
  (lambda (ctx pos sk fk)
    (parser ctx pos
            (lambda (v next-pos inner-fk)
              (sk v next-pos inner-fk))
            (lambda ()
              (sk #f pos fk)))))

;;; Syntactic Predicate: Positive Lookahead (&)
(define (peg:and parser)
  (lambda (ctx pos sk fk)
    (parser ctx pos
            (lambda (v next-pos inner-fk)
              (sk #t pos fk))
            fk)))

;;; Syntactic Predicate: Negative Lookahead (!)
(define (peg:not parser)
  (lambda (ctx pos sk fk)
    (parser ctx pos
            (lambda (v next-pos inner-fk)
              (fk))
            (lambda ()
              (sk #t pos fk)))))

;;; Separated List: sep.elem+ or sep.elem*
(define (peg:gather sep elem is-one-or-more?)
  (let ((tail-parser
         (peg:seq sep elem)))
    (if is-one-or-more?
        (lambda (ctx pos sk fk)
          (elem ctx pos
                (lambda (v1 pos1 fk1)
                  (let loop ((curr-pos pos1) (vals (list v1)) (curr-fk fk1))
                    (tail-parser ctx curr-pos
                                 (lambda (pair next-pos next-fk)
                                   (if (<= next-pos curr-pos)
                                       (sk (reverse vals) curr-pos next-fk)
                                       (loop next-pos (cons (cadr pair) vals) next-fk)))
                                 (lambda ()
                                   (sk (reverse vals) curr-pos curr-fk)))))
                fk))
        (lambda (ctx pos sk fk)
          (elem ctx pos
                (lambda (v1 pos1 fk1)
                  (let loop ((curr-pos pos1) (vals (list v1)) (curr-fk fk1))
                    (tail-parser ctx curr-pos
                                 (lambda (pair next-pos next-fk)
                                   (if (<= next-pos curr-pos)
                                       (sk (reverse vals) curr-pos next-fk)
                                       (loop next-pos (cons (cadr pair) vals) next-fk)))
                                 (lambda ()
                                   (sk (reverse vals) curr-pos curr-fk)))))
                (lambda ()
                  (sk '() pos fk)))))))

;;; Semantic Action / Map combinator
(define (peg:map proc parser)
  (lambda (ctx pos sk fk)
    (parser ctx pos
            (lambda (v next-pos inner-fk)
              (sk (proc v) next-pos inner-fk))
            fk)))

;;; Bind named result combinator: returns '(name . val)
(define (peg:bind name parser)
  (lambda (ctx pos sk fk)
    (parser ctx pos
            (lambda (v next-pos inner-fk)
              (sk (cons name v) next-pos inner-fk))
            fk)))

;;; -----------------------------------------------------------------------
;;; 5. Warth Left-Recursion Memoization Engine
;;; -----------------------------------------------------------------------

(define (peg:rule rule-name parser-proc)
  (lambda (ctx pos sk fk)
    (let ((depth (parse-ctx-depth ctx)))
      (if (> depth (parse-ctx-max-depth ctx))
          (error "Maximum parsing recursion depth exceeded" (list rule-name pos depth)))
      (let ((key (cons rule-name pos)))
        (cond
          ((parse-ctx-in-progress? ctx key)
           (parse-ctx-lr-detected-add! ctx key)
           (parse-ctx-touched-lr-add! ctx key)
           (fk))
          ((parse-ctx-memo-ref ctx key)
           => (lambda (entry)
                (if (memo-entry-growing? entry)
                    (parse-ctx-touched-lr-add! ctx key))
                (if (pair? (memo-entry-lr-deps entry))
                    (parse-ctx-touched-lr-merge! ctx (memo-entry-lr-deps entry)))
                (case (memo-entry-status entry)
                  ((done)
                   (sk (memo-entry-val entry) (memo-entry-end-pos entry) fk))
                  ((fail)
                   (fk)))))
          (else
           (let ((outer-touched (parse-ctx-touched-lr ctx)))
             (parse-ctx-touched-lr-set! ctx '())
             (parse-ctx-depth-set! ctx (+ depth 1))
             (parse-ctx-in-progress-add! ctx key)
             (let ((matched #f)
                   (res-val #f)
                   (res-pos #f))
               (parser-proc
                ctx pos
                (lambda (v next-pos ifk)
                  (set! matched #t)
                  (set! res-val v)
                  (set! res-pos next-pos))
                (lambda ()
                  (set! matched #f)))
               (parse-ctx-depth-set! ctx depth)
               (parse-ctx-in-progress-delete! ctx key)
               (if (parse-ctx-lr-detected? ctx key)
                   (begin
                     (parse-ctx-lr-detected-delete! ctx key)
                     (if matched
                         ;; Seed growth loop for left-recursion
                         (let grow ((curr-val res-val) (curr-pos res-pos))
                           (parse-ctx-memo-set! ctx key (make-memo-entry 'done curr-val curr-pos #t '()))
                           (parse-ctx-clear-lr-dependent-memo! ctx pos key)
                           (let ((step-matched #f)
                                 (step-val #f)
                                 (step-pos #f))
                             (parser-proc
                              ctx pos
                              (lambda (v p ifk)
                                (set! step-matched #t)
                                (set! step-val v)
                                (set! step-pos p))
                              (lambda () (set! step-matched #f)))
                             (if (and step-matched (> step-pos curr-pos))
                                 (grow step-val step-pos)
                                 (let ((ext-deps (%filter-out-key (parse-ctx-touched-lr ctx) key)))
                                   (parse-ctx-memo-set! ctx key (make-memo-entry 'done curr-val curr-pos #f ext-deps))
                                   (parse-ctx-touched-lr-set! ctx outer-touched)
                                   (parse-ctx-touched-lr-merge! ctx ext-deps)
                                   (sk curr-val curr-pos fk)))))
                         (let ((ext-deps (%filter-out-key (parse-ctx-touched-lr ctx) key)))
                           (parse-ctx-memo-set! ctx key (make-memo-entry 'fail #f pos #f ext-deps))
                           (parse-ctx-touched-lr-set! ctx outer-touched)
                           (parse-ctx-touched-lr-merge! ctx ext-deps)
                           (fk))))
                   (let ((ext-deps (%filter-out-key (parse-ctx-touched-lr ctx) key)))
                     (if matched
                         (parse-ctx-memo-set! ctx key (make-memo-entry 'done res-val res-pos #f ext-deps))
                         (parse-ctx-memo-set! ctx key (make-memo-entry 'fail #f pos #f ext-deps)))
                     (parse-ctx-touched-lr-set! ctx outer-touched)
                     (parse-ctx-touched-lr-merge! ctx ext-deps)
                     (if matched
                         (sk res-val res-pos fk)
                         (fk))))))))))))

;;; -----------------------------------------------------------------------
;;; 6. Top-Level Parse Execution Drivers
;;; -----------------------------------------------------------------------

(define (calc-line-col text pos)
  (let loop ((i 0) (line 1) (col 1))
    (if (or (>= i pos) (>= i (string-length text)))
        (cons line col)
        (let ((ch (string-ref text i)))
          (if (char=? ch #\newline)
              (loop (+ i 1) (+ line 1) 1)
              (loop (+ i 1) line (+ col 1)))))))

(define (peg-parse-partial parser text . maybe-pos)
  (let* ((start-pos (if (pair? maybe-pos) (car maybe-pos) 0))
         (ctx (make-parse-context text))
         (matched #f)
         (result-val #f)
         (result-pos #f))
    (parser
     ctx start-pos
     (lambda (val next-pos fk)
       (set! matched #t)
       (set! result-val val)
       (set! result-pos next-pos))
     (lambda ()
       (set! matched #f)))
    (if matched
        (cons result-val result-pos)
        #f)))

(define (peg-parse parser text)
  (let* ((ctx (make-parse-context text))
         (txt-len (string-length text))
         (matched #f)
         (result-val #f)
         (result-pos #f))
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
               (lc (calc-line-col text err-pos))
               (exp (parse-ctx-expected ctx)))
          (error "PEGSyntaxError"
                 (list 'line (car lc)
                       'col (cdr lc)
                       'pos err-pos
                       'expected (if (null? exp) '("valid token") exp)))))))
