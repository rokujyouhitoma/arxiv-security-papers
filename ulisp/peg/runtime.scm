;;; =======================================================================
;;; Packrat PEG Runtime Engine with Double Continuations (CPS) & Warth Left-Recursion
;;; Conforms to DSN-25 & DSN-33-04 §3.1, Issue #894
;;; Zero external dependencies.
;;; =======================================================================

;;; -----------------------------------------------------------------------
;;; 1. Data Structures: <parse-context> and <memo-entry>
;;; -----------------------------------------------------------------------

(define-record-type <parse-context>
  (%make-parse-context text length max-pos expected memo lr-detected in-progress depth max-depth)
  parse-context?
  (text         parse-ctx-text)
  (length       parse-ctx-length)
  (max-pos      parse-ctx-max-pos      parse-ctx-max-pos-set!)
  (expected     parse-ctx-expected     parse-ctx-expected-set!)
  (memo         parse-ctx-memo         parse-ctx-raw-memo-set!)
  (lr-detected  parse-ctx-lr-detected  parse-ctx-lr-detected-set!)
  (in-progress  parse-ctx-in-progress  parse-ctx-in-progress-set!)
  (depth        parse-ctx-depth        parse-ctx-depth-set!)
  (max-depth    parse-ctx-max-depth))

(define (make-parse-context text . maybe-max-depth)
  (let ((len (string-length text))
        (max-d (if (pair? maybe-max-depth) (car maybe-max-depth) 10000)))
    (%make-parse-context text len 0 '() '() '() '() 0 max-d)))

(define-record-type <memo-entry>
  (make-memo-entry status val end-pos)
  memo-entry?
  (status  memo-entry-status  memo-entry-status-set!)
  (val     memo-entry-val     memo-entry-val-set!)
  (end-pos memo-entry-end-pos memo-entry-end-pos-set!))

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
  (let ((memo (parse-ctx-memo ctx)))
    (cond
      ((assoc key memo) => cdr)
      (else #f))))

(define (parse-ctx-memo-set! ctx key entry)
  (let ((memo (parse-ctx-memo ctx)))
    (let ((slot (assoc key memo)))
      (if slot
          (set-cdr! slot entry)
          (parse-ctx-raw-memo-set! ctx (cons (cons key entry) memo))))))

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
  ;; Clear all memo entries starting at >= pos except current-key
  (let ((filtered
         (let loop ((lst (parse-ctx-memo ctx)) (acc '()))
           (if (null? lst)
               acc
               (let* ((entry (car lst))
                      (k (car entry)))
                 ;; k is (rule-name . k-pos)
                 (if (and (pair? k)
                          (>= (cdr k) pos)
                          (not (equal? k current-key)))
                     (loop (cdr lst) acc)
                     (loop (cdr lst) (cons entry acc))))))))
    (parse-ctx-raw-memo-set! ctx filtered)))

;;; -----------------------------------------------------------------------
;;; 3. Character Class Helper
;;; -----------------------------------------------------------------------

(define (make-char-class-pred spec inverted?)
  (let* ((len (string-length spec))
         (ranges
          (let loop ((i 0) (acc '()))
            (cond
              ((>= i len) acc)
              ((and (<= (+ i 2) (- len 1))
                    (char=? (string-ref spec (+ i 1)) #\-))
               (let ((c-start (string-ref spec i))
                     (c-end (string-ref spec (+ i 2))))
                 (loop (+ i 3) (cons (cons c-start c-end) acc))))
              (else
               (loop (+ i 1) (cons (string-ref spec i) acc)))))))
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
  (let ((lit-len (string-length str)))
    (lambda (ctx pos sk fk)
      (let ((txt (parse-ctx-text ctx))
            (total-len (parse-ctx-length ctx)))
        (if (and (<= (+ pos lit-len) total-len)
                 (string=? (substring txt pos (+ pos lit-len)) str))
            (sk str (+ pos lit-len) fk)
            (begin
              (parse-ctx-update-max-pos! ctx pos (string-append "'" str "'"))
              (fk)))))))

;;; Character class match
(define (peg:char-class spec . maybe-inverted)
  (let* ((inverted? (if (pair? maybe-inverted) (car maybe-inverted) #f))
         (pred (make-char-class-pred spec inverted?)))
    (lambda (ctx pos sk fk)
      (let ((txt (parse-ctx-text ctx))
            (total-len (parse-ctx-length ctx)))
        (if (and (< pos total-len)
                 (pred (string-ref txt pos)))
            (sk (string (string-ref txt pos)) (+ pos 1) fk)
            (begin
              (parse-ctx-update-max-pos! ctx pos (string-append "[" spec "]"))
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
           (fk))
          ((parse-ctx-memo-ref ctx key)
           => (lambda (entry)
                (case (memo-entry-status entry)
                  ((done)
                   (sk (memo-entry-val entry) (memo-entry-end-pos entry) fk))
                  ((fail)
                   (fk)))))
          (else
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
                         (parse-ctx-memo-set! ctx key (make-memo-entry 'done curr-val curr-pos))
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
                               (begin
                                 (parse-ctx-memo-set! ctx key (make-memo-entry 'done curr-val curr-pos))
                                 (sk curr-val curr-pos fk)))))
                       (begin
                         (parse-ctx-memo-set! ctx key (make-memo-entry 'fail #f pos))
                         (fk))))
                 (if matched
                     (begin
                       (parse-ctx-memo-set! ctx key (make-memo-entry 'done res-val res-pos))
                       (sk res-val res-pos fk))
                     (begin
                       (parse-ctx-memo-set! ctx key (make-memo-entry 'fail #f pos))
                       (fk)))))))))))

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
