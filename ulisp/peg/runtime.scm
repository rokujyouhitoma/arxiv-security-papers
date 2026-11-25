;;; =======================================================================
;;; Packrat PEG Runtime Engine with Double Continuations (CPS) & Warth Left-Recursion
;;; Conforms to DSN-25 & DSN-33-04 §3.1, Issue #894
;;; Zero external dependencies.
;;; =======================================================================

;;; -----------------------------------------------------------------------
;;; 1. Data Structures: <parse-context> and <memo-entry>
;;; -----------------------------------------------------------------------

(define-record-type <parse-context>
  (%make-parse-context text length max-pos expected memo lr-detected in-progress touched-lr depth max-depth res-val cut?)
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
  (max-depth    parse-ctx-max-depth)
  (res-val      parse-ctx-res-val      parse-ctx-res-val-set!)
  (cut?         parse-ctx-cut?         parse-ctx-cut?-set!))

(define (make-parse-context text . maybe-max-depth)
  (let ((len (string-length text))
        (max-d (if (pair? maybe-max-depth) (car maybe-max-depth) 10000)))
    (%make-parse-context text len 0 '() (make-vector (+ len 1) '()) '() '() '() 0 max-d #f #f)))

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

(define (parse-ctx-memo-ref-rp ctx rule pos)
  (let* ((vec (parse-ctx-memo ctx))
         (bucket (vector-ref vec pos)))
    (cond
      ((assq rule bucket) => cdr)
      (else #f))))

(define (parse-ctx-memo-set-rp! ctx rule pos entry)
  (let* ((vec (parse-ctx-memo ctx))
         (bucket (vector-ref vec pos))
         (slot (assq rule bucket)))
    (if slot
        (set-cdr! slot entry)
        (vector-set! vec pos (cons (cons rule entry) bucket)))))

(define (parse-ctx-memo-ref ctx key)
  (parse-ctx-memo-ref-rp ctx (car key) (cdr key)))

(define (parse-ctx-memo-set! ctx key entry)
  (parse-ctx-memo-set-rp! ctx (car key) (cdr key) entry))

(define (parse-ctx-in-progress-rp? ctx rule pos)
  (let loop ((xs (parse-ctx-in-progress ctx)))
    (cond
      ((null? xs) #f)
      ((and (eq? (caar xs) rule) (= (cdar xs) pos)) #t)
      (else (loop (cdr xs))))))

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
               (loop (cdr ts) (cons (cdar ts) acc))))))
         (match-ranges
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
                 (test (cdr r)))))))
         (ascii-vec (make-vector 128 #f)))
    (let fill ((i 0))
      (if (< i 128)
          (begin
            (vector-set! ascii-vec i (match-ranges (integer->char i)))
            (fill (+ i 1)))))
    (lambda (ch)
      (let ((code (char->integer ch)))
        (if (and (>= code 0) (< code 128))
            (vector-ref ascii-vec code)
            (match-ranges ch))))))

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
(define (peg:seq-list parsers)
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

(define (peg:seq . parsers)
  (peg:seq-list parsers))

;;; Ordered Choice combinator: e1 | e2 | ...
(define (peg:alt-list parsers)
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

(define (peg:alt . parsers)
  (peg:alt-list parsers))

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
      (cond
        ((parse-ctx-in-progress-rp? ctx rule-name pos)
         (let ((key (cons rule-name pos)))
           (parse-ctx-lr-detected-add! ctx key)
           (parse-ctx-touched-lr-add! ctx key)
           (fk)))
        ((parse-ctx-memo-ref-rp ctx rule-name pos)
         => (lambda (entry)
              (if (memo-entry-growing? entry)
                  (parse-ctx-touched-lr-add! ctx (cons rule-name pos)))
              (if (pair? (memo-entry-lr-deps entry))
                  (parse-ctx-touched-lr-merge! ctx (memo-entry-lr-deps entry)))
              (case (memo-entry-status entry)
                ((done)
                 (sk (memo-entry-val entry) (memo-entry-end-pos entry) fk))
                ((fail)
                 (fk)))))
        (else
         (let ((key (cons rule-name pos))
               (outer-touched (parse-ctx-touched-lr ctx)))
           (if (pair? outer-touched)
               (parse-ctx-touched-lr-set! ctx '()))
           (parse-ctx-depth-set! ctx (+ depth 1))
           (parse-ctx-in-progress-add! ctx key)
           (let ((res (vector #f #f #f)))
             (parser-proc
              ctx pos
              (lambda (v next-pos ifk)
                (vector-set! res 0 #t)
                (vector-set! res 1 v)
                (vector-set! res 2 next-pos))
              (lambda ()
                (vector-set! res 0 #f)))
             (parse-ctx-depth-set! ctx depth)
             (parse-ctx-in-progress-delete! ctx key)
             (let ((matched (vector-ref res 0))
                   (res-val (vector-ref res 1))
                   (res-pos (vector-ref res 2)))
               (if (and (pair? (parse-ctx-lr-detected ctx))
                        (parse-ctx-lr-detected? ctx key))
                   (begin
                     (parse-ctx-lr-detected-delete! ctx key)
                     (if matched
                         ;; Seed growth loop for left-recursion
                         (let grow ((curr-val res-val) (curr-pos res-pos))
                           (parse-ctx-memo-set-rp! ctx rule-name pos (make-memo-entry 'done curr-val curr-pos #t '()))
                           (parse-ctx-clear-lr-dependent-memo! ctx pos key)
                           (let ((step (vector #f #f #f)))
                             (parser-proc
                              ctx pos
                              (lambda (v p ifk)
                                (vector-set! step 0 #t)
                                (vector-set! step 1 v)
                                (vector-set! step 2 p))
                              (lambda () (vector-set! step 0 #f)))
                             (if (and (vector-ref step 0) (> (vector-ref step 2) curr-pos))
                                 (grow (vector-ref step 1) (vector-ref step 2))
                                 (let ((ext-deps (%filter-out-key (parse-ctx-touched-lr ctx) key)))
                                   (parse-ctx-memo-set-rp! ctx rule-name pos (make-memo-entry 'done curr-val curr-pos #f ext-deps))
                                   (parse-ctx-touched-lr-set! ctx outer-touched)
                                   (if (pair? ext-deps)
                                       (parse-ctx-touched-lr-merge! ctx ext-deps))
                                   (sk curr-val curr-pos fk)))))
                         (let ((ext-deps (%filter-out-key (parse-ctx-touched-lr ctx) key)))
                           (parse-ctx-memo-set-rp! ctx rule-name pos (make-memo-entry 'fail #f pos #f ext-deps))
                           (parse-ctx-touched-lr-set! ctx outer-touched)
                           (if (pair? ext-deps)
                               (parse-ctx-touched-lr-merge! ctx ext-deps))
                           (fk))))
                   (let* ((cur-touched (parse-ctx-touched-lr ctx))
                          (ext-deps (if (null? cur-touched) '() (%filter-out-key cur-touched key))))
                     (if matched
                         (parse-ctx-memo-set-rp! ctx rule-name pos (make-memo-entry 'done res-val res-pos #f ext-deps))
                         (parse-ctx-memo-set-rp! ctx rule-name pos (make-memo-entry 'fail #f pos #f ext-deps)))
                     (if (or (pair? outer-touched) (pair? cur-touched))
                         (parse-ctx-touched-lr-set! ctx outer-touched))
                     (if (pair? ext-deps)
                         (parse-ctx-touched-lr-merge! ctx ext-deps))
                     (if matched
                         (sk res-val res-pos fk)
                         (fk))))))))))))

;;; Fast Packrat memoization for provably non-left-recursive rules
(define (peg:rule-simple rule-name parser-proc)
  (lambda (ctx pos sk fk)
    (let ((entry (parse-ctx-memo-ref-rp ctx rule-name pos)))
      (if entry
          (case (memo-entry-status entry)
            ((done)
             (sk (memo-entry-val entry) (memo-entry-end-pos entry) fk))
            ((fail)
             (fk)))
          (let ((res (vector #f #f #f)))
            (parser-proc
             ctx pos
             (lambda (v next-pos ifk)
               (vector-set! res 0 #t)
               (vector-set! res 1 v)
               (vector-set! res 2 next-pos))
             (lambda ()
               (vector-set! res 0 #f)))
            (if (vector-ref res 0)
                (let ((v (vector-ref res 1))
                      (np (vector-ref res 2)))
                  (parse-ctx-memo-set-rp! ctx rule-name pos (make-memo-entry 'done v np #f '()))
                  (sk v np fk))
                (begin
                  (parse-ctx-memo-set-rp! ctx rule-name pos (make-memo-entry 'fail #f pos #f '()))
                  (fk))))))))

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
         (res (vector #f #f #f)))
    (parser
     ctx start-pos
     (lambda (val next-pos fk)
       (vector-set! res 0 #t)
       (vector-set! res 1 val)
       (vector-set! res 2 next-pos))
     (lambda ()
       (vector-set! res 0 #f)))
    (if (vector-ref res 0)
        (cons (vector-ref res 1) (vector-ref res 2))
        #f)))

(define (peg-parse parser text)
  (let* ((ctx (make-parse-context text))
         (txt-len (string-length text))
         (res (vector #f #f #f)))
    (parser
     ctx 0
     (lambda (val next-pos fk)
       (if (= next-pos txt-len)
           (begin
             (vector-set! res 0 #t)
             (vector-set! res 1 val)
             (vector-set! res 2 next-pos))
           (fk)))
     (lambda ()
       (vector-set! res 0 #f)))
    (if (vector-ref res 0)
        (vector-ref res 1)
        (let* ((err-pos (parse-ctx-max-pos ctx))
               (lc (calc-line-col text err-pos))
               (exp (parse-ctx-expected ctx)))
          (error "PEGSyntaxError"
                 (list 'line (car lc)
                       'col (cdr lc)
                       'pos err-pos
                       'expected (if (null? exp) '("valid token") exp)))))))

;;; -----------------------------------------------------------------------
;;; 7. Direct-Style Non-CPS Runtime Primitives & Scanners (Issue #948)
;;; Calling convention:
;;;   (fn ctx [extra...] pos) -> next-pos (integer) on success with value in (parse-ctx-res-val ctx),
;;;                              or #f on failure.
;;; Zero closure allocations, zero local set!.
;;; -----------------------------------------------------------------------

(define (peg-ds:lit ctx pos str lit-len first-ch err-label)
  (let ((txt (parse-ctx-text ctx))
        (total-len (parse-ctx-length ctx)))
    (if (and (<= (+ pos lit-len) total-len)
             (or (= lit-len 0)
                 (and (char=? (string-ref txt pos) first-ch)
                      (or (= lit-len 1)
                          (string=? (substring txt pos (+ pos lit-len)) str)))))
        (begin
          (parse-ctx-res-val-set! ctx str)
          (+ pos lit-len))
        (begin
          (parse-ctx-update-max-pos! ctx pos err-label)
          #f))))

(define (peg-ds:lit1 ctx pos ch str err-label)
  (let ((txt (parse-ctx-text ctx))
        (total-len (parse-ctx-length ctx)))
    (if (and (< pos total-len)
             (char=? (string-ref txt pos) ch))
        (begin
          (parse-ctx-res-val-set! ctx str)
          (+ pos 1))
        (begin
          (parse-ctx-update-max-pos! ctx pos err-label)
          #f))))

(define (peg-ds:char-class ctx pos pred err-label)
  (let ((txt (parse-ctx-text ctx))
        (total-len (parse-ctx-length ctx)))
    (if (and (< pos total-len)
             (pred (string-ref txt pos)))
        (begin
          (parse-ctx-res-val-set! ctx (string (string-ref txt pos)))
          (+ pos 1))
        (begin
          (parse-ctx-update-max-pos! ctx pos err-label)
          #f))))

(define (%peg-ds-chars->string-list txt start-pos end-pos)
  (let loop ((k (- end-pos 1)) (acc '()))
    (if (< k start-pos)
        acc
        (loop (- k 1) (cons (string (string-ref txt k)) acc)))))

(define (peg-ds:scan-char-class-plus ctx pos pred err-label)
  (let ((txt (parse-ctx-text ctx))
        (total-len (parse-ctx-length ctx)))
    (if (and (< pos total-len) (pred (string-ref txt pos)))
        (let loop ((i (+ pos 1)))
          (if (and (< i total-len) (pred (string-ref txt i)))
              (loop (+ i 1))
              (begin
                (parse-ctx-res-val-set! ctx (%peg-ds-chars->string-list txt pos i))
                i)))
        (begin
          (parse-ctx-update-max-pos! ctx pos err-label)
          #f))))

(define (peg-ds:scan-char-class-star ctx pos pred)
  (let ((txt (parse-ctx-text ctx))
        (total-len (parse-ctx-length ctx)))
    (let loop ((i pos))
      (if (and (< i total-len) (pred (string-ref txt i)))
          (loop (+ i 1))
          (begin
            (parse-ctx-res-val-set! ctx (%peg-ds-chars->string-list txt pos i))
            i)))))

(define (peg-ds:any-char ctx pos)
  (let ((txt (parse-ctx-text ctx))
        (total-len (parse-ctx-length ctx)))
    (if (< pos total-len)
        (begin
          (parse-ctx-res-val-set! ctx (string (string-ref txt pos)))
          (+ pos 1))
        (begin
          (parse-ctx-update-max-pos! ctx pos "any-char")
          #f))))

(define (peg-ds:line-start ctx pos)
  (if (= pos 0)
      (begin
        (parse-ctx-res-val-set! ctx "")
        pos)
      (let ((prev-ch (string-ref (parse-ctx-text ctx) (- pos 1))))
        (if (or (char=? prev-ch #\newline) (char=? prev-ch #\return))
            (begin
              (parse-ctx-res-val-set! ctx "")
              pos)
            #f))))

(define (peg-ds:cut ctx pos)
  (parse-ctx-cut?-set! ctx #t)
  (parse-ctx-res-val-set! ctx 'cut)
  pos)

(define (peg-ds:escape-pair ctx pos)
  (let ((txt (parse-ctx-text ctx))
        (total-len (parse-ctx-length ctx)))
    (if (and (<= (+ pos 2) total-len)
             (char=? (string-ref txt pos) #\\))
        (begin
          (parse-ctx-res-val-set! ctx (list "\\" (string (string-ref txt (+ pos 1)))))
          (+ pos 2))
        (begin
          (parse-ctx-update-max-pos! ctx pos "'\\'")
          #f))))

;;; Meta-grammar Direct-Style scanners (shared with self-hosting stage1/stage2)

(define (%peg-ds-skip-ws txt total-len pos)
  (let loop ((i pos))
    (if (>= i total-len)
        i
        (let ((ch (string-ref txt i)))
          (cond
            ((or (char=? ch #\space)
                 (char=? ch #\tab)
                 (char=? ch #\newline)
                 (char=? ch #\return))
             (loop (+ i 1)))
            ((char=? ch #\#)
             (let scan-comment ((j (+ i 1)))
               (if (>= j total-len)
                   j
                   (let ((c (string-ref txt j)))
                     (if (or (char=? c #\newline) (char=? c #\return))
                         (loop (+ j 1))
                         (scan-comment (+ j 1)))))))
            (else i))))))

(define (peg-ds:meta-ws ctx pos)
  (let ((next-pos (%peg-ds-skip-ws (parse-ctx-text ctx) (parse-ctx-length ctx) pos)))
    (parse-ctx-res-val-set! ctx "")
    next-pos))

(define (peg-ds:meta-ident ctx pos)
  (let ((txt (parse-ctx-text ctx))
        (total-len (parse-ctx-length ctx)))
    (if (>= pos total-len)
        #f
        (let ((c0 (string-ref txt pos)))
          (if (or (and (char>=? c0 #\a) (char<=? c0 #\z))
                  (and (char>=? c0 #\A) (char<=? c0 #\Z))
                  (char=? c0 #\_))
              (let loop ((i (+ pos 1)))
                (if (and (< i total-len)
                         (let ((ci (string-ref txt i)))
                           (or (and (char>=? ci #\a) (char<=? ci #\z))
                               (and (char>=? ci #\A) (char<=? ci #\Z))
                               (and (char>=? ci #\0) (char<=? ci #\9))
                               (char=? ci #\_))))
                    (loop (+ i 1))
                    (let ((sym (string->symbol (substring txt pos i)))
                          (ws-end (%peg-ds-skip-ws txt total-len i)))
                      (parse-ctx-res-val-set! ctx sym)
                      ws-end)))
              #f)))))

(define (peg-ds:meta-string-lit ctx pos)
  (let ((txt (parse-ctx-text ctx))
        (total-len (parse-ctx-length ctx)))
    (if (>= pos total-len)
        #f
        (let ((c0 (string-ref txt pos)))
          (if (and (not (char=? c0 #\')) (not (char=? c0 #\")))
              #f
              (let* ((is-triple (and (<= (+ pos 3) total-len)
                                     (char=? (string-ref txt (+ pos 1)) c0)
                                     (char=? (string-ref txt (+ pos 2)) c0)))
                     (quote-len (if is-triple 3 1)))
                (let loop ((i (+ pos quote-len)) (chars '()))
                  (cond
                    ((> (+ i quote-len) total-len) #f)
                    ((and is-triple
                          (char=? (string-ref txt i) c0)
                          (char=? (string-ref txt (+ i 1)) c0)
                          (char=? (string-ref txt (+ i 2)) c0))
                     (let ((ws-end (%peg-ds-skip-ws txt total-len (+ i 3))))
                       (parse-ctx-res-val-set! ctx (list->string (reverse chars)))
                       ws-end))
                    ((and (not is-triple) (char=? (string-ref txt i) c0))
                     (let ((ws-end (%peg-ds-skip-ws txt total-len (+ i 1))))
                       (parse-ctx-res-val-set! ctx (list->string (reverse chars)))
                       ws-end))
                    (else
                     (let ((ci (string-ref txt i)))
                       (if (char=? ci #\\)
                           (if (< (+ i 1) total-len)
                               (let ((esc (string-ref txt (+ i 1))))
                                 (loop (+ i 2)
                                       (cons (case esc
                                               ((#\n) #\newline)
                                               ((#\t) #\tab)
                                               ((#\r) #\return)
                                               (else esc))
                                             chars)))
                               #f)
                           (loop (+ i 1) (cons ci chars)))))))))))))

(define (peg-ds:meta-action-block ctx pos)
  (let ((txt (parse-ctx-text ctx))
        (total-len (parse-ctx-length ctx)))
    (if (or (>= pos total-len) (not (char=? (string-ref txt pos) #\{)))
        #f
        (let loop ((i (+ pos 1)) (depth 1) (in-quote #f))
          (cond
            ((>= i total-len) #f)
            (in-quote
             (let ((ch (string-ref txt i)))
               (cond
                 ((char=? ch #\\) (loop (+ i 2) depth in-quote))
                 ((char=? ch in-quote) (loop (+ i 1) depth #f))
                 (else (loop (+ i 1) depth in-quote)))))
            (else
             (let ((ch (string-ref txt i)))
               (cond
                 ((or (char=? ch #\') (char=? ch #\"))
                  (loop (+ i 1) depth ch))
                 ((char=? ch #\{)
                  (loop (+ i 1) (+ depth 1) #f))
                 ((char=? ch #\})
                  (if (= depth 1)
                      (let ((body (substring txt (+ pos 1) i))
                            (ws-end (%peg-ds-skip-ws txt total-len (+ i 1))))
                        (parse-ctx-res-val-set! ctx body)
                        ws-end)
                      (loop (+ i 1) (- depth 1) #f)))
                 (else (loop (+ i 1) depth #f))))))))))

(define (peg-ds:meta-regex-lit ctx pos)
  (let ((txt (parse-ctx-text ctx))
        (total-len (parse-ctx-length ctx)))
    (if (or (>= (+ pos 1) total-len)
            (not (char=? (string-ref txt pos) #\/))
            (let ((c1 (string-ref txt (+ pos 1))))
              (or (char=? c1 #\space) (char=? c1 #\tab)
                  (char=? c1 #\newline) (char=? c1 #\return))))
        #f
        (let loop ((i (+ pos 1)) (chars '()))
          (cond
            ((>= i total-len) #f)
            ((char=? (string-ref txt i) #\\)
             (if (< (+ i 1) total-len)
                 (loop (+ i 2) (cons (string-ref txt (+ i 1)) (cons #\\ chars)))
                 #f))
            ((char=? (string-ref txt i) #\/)
             (let ((pat (list->string (reverse chars)))
                   (ws-end (%peg-ds-skip-ws txt total-len (+ i 1))))
               (parse-ctx-res-val-set! ctx pat)
               ws-end))
            (else (loop (+ i 1) (cons (string-ref txt i) chars))))))))

(define (peg-ds:meta-char-class ctx pos)
  (let ((txt (parse-ctx-text ctx))
        (total-len (parse-ctx-length ctx)))
    (if (or (>= pos total-len) (not (char=? (string-ref txt pos) #\[)))
        #f
        (let* ((is-inv (and (< (+ pos 1) total-len)
                            (char=? (string-ref txt (+ pos 1)) #\^)))
               (start-inner (if is-inv (+ pos 2) (+ pos 1))))
          (let loop ((i start-inner) (chars '()))
            (cond
              ((>= i total-len) #f)
              ((char=? (string-ref txt i) #\\)
               (if (< (+ i 1) total-len)
                   (loop (+ i 2) (cons (string-ref txt (+ i 1)) (cons #\\ chars)))
                   #f))
              ((char=? (string-ref txt i) #\])
               (let ((spec (list->string (reverse chars)))
                     (ws-end (%peg-ds-skip-ws txt total-len (+ i 1))))
                 (parse-ctx-res-val-set! ctx (cons spec is-inv))
                 ws-end))
              (else (loop (+ i 1) (cons (string-ref txt i) chars)))))))))

(define (peg-ds:meta-new-rule-head ctx pos)
  (let ((p1 (peg-ds:meta-ident ctx pos)))
    (if (not p1)
        #f
        (let ((p2 (peg-ds:lit ctx p1 "<-" 2 #\< "'<-'")))
          (if p2
              (let ((p3 (peg-ds:meta-ws ctx p2)))
                (parse-ctx-res-val-set! ctx #t)
                p3)
              (if (peg-ds:line-start ctx pos)
                  (let ((p1b (peg-ds:meta-ident ctx pos)))
                    (if (not p1b)
                        #f
                        (let ((p2b (or (peg-ds:lit1 ctx p1b #\: ":" "':'")
                                       (peg-ds:lit1 ctx p1b #\= "=" "'='"))))
                          (if p2b
                              (let ((p3b (peg-ds:meta-ws ctx p2b)))
                                (parse-ctx-res-val-set! ctx #t)
                                p3b)
                              #f))))
                  #f))))))

(define (peg-ds:meta-opt-lead-pipe ctx pos)
  (let ((txt (parse-ctx-text ctx))
        (total-len (parse-ctx-length ctx)))
    (if (and (< pos total-len)
             (let ((ch (string-ref txt pos)))
               (or (char=? ch #\|) (char=? ch #\/))))
        (%peg-ds-skip-ws txt total-len (+ pos 1))
        pos)))

;;; -----------------------------------------------------------------------
;;; 8. Direct-Style Packrat Memoization, Warth LR & Top-Level Drivers
;;; -----------------------------------------------------------------------

(define (peg-ds:rule-memo ctx rule-name pos body-thunk)
  (let ((depth (parse-ctx-depth ctx)))
    (if (> depth (parse-ctx-max-depth ctx))
        (error "Maximum parsing recursion depth exceeded" (list rule-name pos depth)))
    (let ((entry (parse-ctx-memo-ref-rp ctx rule-name pos)))
      (if entry
          (begin
            (if (and (pair? (memo-entry-lr-deps entry))
                     (pair? (parse-ctx-in-progress ctx)))
                (parse-ctx-touched-lr-merge! ctx (memo-entry-lr-deps entry)))
            (if (eq? (memo-entry-status entry) 'done)
                (begin
                  (parse-ctx-res-val-set! ctx (memo-entry-val entry))
                  (memo-entry-end-pos entry))
                #f))
          (if (null? (parse-ctx-in-progress ctx))
              ;; Fast path: no active LR seed growth
              (begin
                (parse-ctx-depth-set! ctx (+ depth 1))
                (let ((next-pos (body-thunk)))
                  (parse-ctx-depth-set! ctx depth)
                  (if next-pos
                      (let ((v (parse-ctx-res-val ctx)))
                        (parse-ctx-memo-set-rp! ctx rule-name pos (make-memo-entry 'done v next-pos #f '()))
                        next-pos)
                      (begin
                        (parse-ctx-memo-set-rp! ctx rule-name pos (make-memo-entry 'fail #f pos #f '()))
                        #f))))
              ;; Active LR seed path: propagate lr-deps so grow clears dependent memos
              (let ((outer-touched (parse-ctx-touched-lr ctx)))
                (parse-ctx-touched-lr-set! ctx '())
                (parse-ctx-depth-set! ctx (+ depth 1))
                (let ((next-pos (body-thunk))
                      (cur-touched (parse-ctx-touched-lr ctx)))
                  (parse-ctx-depth-set! ctx depth)
                  (if next-pos
                      (let ((v (parse-ctx-res-val ctx)))
                        (parse-ctx-memo-set-rp! ctx rule-name pos (make-memo-entry 'done v next-pos #f cur-touched))
                        (parse-ctx-touched-lr-set! ctx outer-touched)
                        (if (pair? cur-touched)
                            (parse-ctx-touched-lr-merge! ctx cur-touched))
                        (parse-ctx-res-val-set! ctx v)
                        next-pos)
                      (begin
                        (parse-ctx-memo-set-rp! ctx rule-name pos (make-memo-entry 'fail #f pos #f cur-touched))
                        (parse-ctx-touched-lr-set! ctx outer-touched)
                        (if (pair? cur-touched)
                            (parse-ctx-touched-lr-merge! ctx cur-touched))
                        #f)))))))))

(define (peg-ds:rule-lr ctx rule-name pos body-thunk)
  (let ((depth (parse-ctx-depth ctx)))
    (if (> depth (parse-ctx-max-depth ctx))
        (error "Maximum parsing recursion depth exceeded" (list rule-name pos depth)))
    (cond
      ((parse-ctx-in-progress-rp? ctx rule-name pos)
       (let ((key (cons rule-name pos)))
         (parse-ctx-lr-detected-add! ctx key)
         (parse-ctx-touched-lr-add! ctx key)
         #f))
      ((parse-ctx-memo-ref-rp ctx rule-name pos)
       => (lambda (entry)
            (if (memo-entry-growing? entry)
                (parse-ctx-touched-lr-add! ctx (cons rule-name pos)))
            (if (pair? (memo-entry-lr-deps entry))
                (parse-ctx-touched-lr-merge! ctx (memo-entry-lr-deps entry)))
            (if (eq? (memo-entry-status entry) 'done)
                (begin
                  (parse-ctx-res-val-set! ctx (memo-entry-val entry))
                  (memo-entry-end-pos entry))
                #f)))
      (else
       (let ((key (cons rule-name pos))
             (outer-touched (parse-ctx-touched-lr ctx)))
         (if (pair? outer-touched)
             (parse-ctx-touched-lr-set! ctx '()))
         (parse-ctx-depth-set! ctx (+ depth 1))
         (parse-ctx-in-progress-add! ctx key)
         (let* ((res-pos (body-thunk))
                (res-val (if res-pos (parse-ctx-res-val ctx) #f)))
           (parse-ctx-depth-set! ctx depth)
           (parse-ctx-in-progress-delete! ctx key)
           (if (and (pair? (parse-ctx-lr-detected ctx))
                    (parse-ctx-lr-detected? ctx key))
               (begin
                 (parse-ctx-lr-detected-delete! ctx key)
                 (if res-pos
                     (let grow ((curr-val res-val) (curr-pos res-pos))
                       (parse-ctx-memo-set-rp! ctx rule-name pos (make-memo-entry 'done curr-val curr-pos #t '()))
                       (parse-ctx-clear-lr-dependent-memo! ctx pos key)
                       (parse-ctx-depth-set! ctx (+ depth 1))
                       (let ((step-pos (body-thunk)))
                         (parse-ctx-depth-set! ctx depth)
                         (if (and step-pos (> step-pos curr-pos))
                             (grow (parse-ctx-res-val ctx) step-pos)
                             (let ((ext-deps (%filter-out-key (parse-ctx-touched-lr ctx) key)))
                               (parse-ctx-memo-set-rp! ctx rule-name pos (make-memo-entry 'done curr-val curr-pos #f ext-deps))
                               (parse-ctx-touched-lr-set! ctx outer-touched)
                               (if (pair? ext-deps)
                                   (parse-ctx-touched-lr-merge! ctx ext-deps))
                               (parse-ctx-res-val-set! ctx curr-val)
                               curr-pos))))
                     (let ((ext-deps (%filter-out-key (parse-ctx-touched-lr ctx) key)))
                       (parse-ctx-memo-set-rp! ctx rule-name pos (make-memo-entry 'fail #f pos #f ext-deps))
                       (parse-ctx-touched-lr-set! ctx outer-touched)
                       (if (pair? ext-deps)
                           (parse-ctx-touched-lr-merge! ctx ext-deps))
                       #f)))
               (let* ((cur-touched (parse-ctx-touched-lr ctx))
                      (ext-deps (if (null? cur-touched) '() (%filter-out-key cur-touched key))))
                 (if res-pos
                     (parse-ctx-memo-set-rp! ctx rule-name pos (make-memo-entry 'done res-val res-pos #f ext-deps))
                     (parse-ctx-memo-set-rp! ctx rule-name pos (make-memo-entry 'fail #f pos #f ext-deps)))
                 (if (or (pair? outer-touched) (pair? cur-touched))
                     (parse-ctx-touched-lr-set! ctx outer-touched))
                 (if (pair? ext-deps)
                     (parse-ctx-touched-lr-merge! ctx ext-deps))
                 (if res-pos
                     (begin
                       (parse-ctx-res-val-set! ctx res-val)
                       res-pos)
                     #f)))))))))

(define peg-ds:parse-partial
  (case-lambda
    ((entry-fn text)
     (peg-ds:parse-partial entry-fn text 0))
    ((entry-fn text start-pos)
     (let* ((ctx (make-parse-context text))
            (end-pos (entry-fn ctx start-pos)))
       (if end-pos
           (cons (parse-ctx-res-val ctx) end-pos)
           #f)))))

(define (peg-ds:parse entry-fn text)
  (let* ((ctx (make-parse-context text))
         (txt-len (string-length text))
         (end-pos (entry-fn ctx 0)))
    (if (and end-pos (= end-pos txt-len))
        (parse-ctx-res-val ctx)
        (let* ((err-pos (parse-ctx-max-pos ctx))
               (lc (calc-line-col text err-pos))
               (exp (parse-ctx-expected ctx)))
          (error "PEGSyntaxError"
                 (list 'line (car lc)
                       'col (cdr lc)
                       'pos err-pos
                       'expected (if (null? exp) '("valid token") exp)))))))
