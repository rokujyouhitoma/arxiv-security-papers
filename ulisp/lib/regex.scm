;;; =======================================================================
;;; ULisp Standard Library: Scheme Regular Expressions (SRE)
;;; Conforms to R7RS-large Tangerine Edition & SRFI 115 (by Alex Shinn)
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

;; ---------------------------------------------------------------------
;; §1. Records: <regexp> and <regexp-match>
;; ---------------------------------------------------------------------

(define-record-type <regexp>
  (%make-regexp pattern num-submatches named-submatches matcher)
  regexp?
  (pattern regexp-pattern)
  (num-submatches regexp-num-submatches)
  (named-submatches regexp-named-submatches)
  (matcher %regexp-matcher))

(define-record-type <regexp-match>
  (%make-regexp-match string submatches names count)
  regexp-match?
  (string %match-string)
  (submatches %match-submatches)
  (names %match-names)
  (count regexp-match-count))

;; ---------------------------------------------------------------------
;; §2. Character Sets & Classification
;; ---------------------------------------------------------------------

(define (%char-word? c)
  (or (char-alphabetic? c)
      (char-numeric? c)
      (char=? c #\_)))

(define (%char-ascii? c)
  (< (char->integer c) 128))

(define (%char-blank? c)
  (or (char=? c #\space)
      (char=? c #\tab)))

(define (%char-cntrl? c)
  (let ((n (char->integer c)))
    (or (< n 32) (= n 127))))

(define (%char-graph? c)
  (and (not (%char-cntrl? c))
       (not (char-whitespace? c))))

(define (%char-print? c)
  (and (not (%char-cntrl? c))
       (or (char-whitespace? c) (%char-graph? c))))

(define (%char-punct? c)
  (and (%char-graph? c)
       (not (char-alphabetic? c))
       (not (char-numeric? c))))

(define (%char-xdigit? c)
  (or (char-numeric? c)
      (and (char>=? c #\a) (char<=? c #\f))
      (and (char>=? c #\A) (char<=? c #\F))))

;; Named character class lookup: returns predicate (lambda (c) boolean)
(define (%named-char-class-pred name)
  (case name
    ((any) (lambda (c) #t))
    ((nonl) (lambda (c) (not (char=? c #\newline))))
    ((alpha alphabetic) char-alphabetic?)
    ((numeric) char-numeric?)
    ((whitespace) char-whitespace?)
    ((upper upper-case) char-upper-case?)
    ((lower lower-case) char-lower-case?)
    ((ascii) %char-ascii?)
    ((blank) %char-blank?)
    ((cntrl control) %char-cntrl?)
    ((graph graphic) %char-graph?)
    ((print printing) %char-print?)
    ((punct punctuation) %char-punct?)
    ((xdigit hex-digit) %char-xdigit?)
    ((word) %char-word?)
    (else #f)))

;; Compile a character set / range specification into a single char predicate
(define (%compile-cset cset nocase?)
  (cond
    ((char? cset)
     (if nocase?
         (let ((c-ci (char-downcase cset)))
           (lambda (c) (char=? (char-downcase c) c-ci)))
         (lambda (c) (char=? c cset))))
    ((string? cset)
     (let ((len (string-length cset)))
       (if nocase?
           (let loop ((i 0) (chars '()))
             (if (= i len)
                 (let ((c-list chars))
                   (lambda (c)
                     (let ((c-ci (char-downcase c)))
                       (let in-loop ((rest c-list))
                         (and (pair? rest)
                              (or (char=? c-ci (car rest))
                                  (in-loop (cdr rest))))))))
                 (loop (+ i 1) (cons (char-downcase (string-ref cset i)) chars))))
           (let loop ((i 0) (chars '()))
             (if (= i len)
                 (let ((c-list chars))
                   (lambda (c)
                     (let in-loop ((rest c-list))
                       (and (pair? rest)
                            (or (char=? c (car rest))
                                (in-loop (cdr rest)))))))
                 (loop (+ i 1) (cons (string-ref cset i) chars)))))))
    ((symbol? cset)
     (let ((pred (%named-char-class-pred cset)))
       (if pred
           pred
           (error "valid-sre?: unknown character class" cset))))
    ((pair? cset)
     (case (car cset)
       ((/)
        ;; Range: (/ "a" "z") or (/ #\a #\z) or mixed
        (let loop ((args (cdr cset)) (ranges '()))
          (cond
            ((null? args)
             (let ((r-list (reverse ranges)))
               (lambda (c)
                 (let ((ch (if nocase? (char-downcase c) c)))
                   (let in-r ((rs r-list))
                     (and (pair? rs)
                          (let ((r (car rs)))
                            (or (and (char>=? ch (car r)) (char<=? ch (cdr r)))
                                (in-r (cdr rs))))))))))
            ((and (pair? (cdr args)))
             (let ((from (let ((x (car args)))
                           (if (char? x) x (string-ref x 0))))
                   (to (let ((y (cadr args)))
                         (if (char? y) y (string-ref y (- (string-length y) 1))))))
               (let ((f (if nocase? (char-downcase from) from))
                     (t (if nocase? (char-downcase to) to)))
                 (loop (cddr args) (cons (cons f t) ranges)))))
            (else
             (error "cset: malformed range (/ from to ...)" cset)))))
       ((~)
        ;; Complement: (~ cset ...)
        (let ((inner (%compile-cset (cons 'or (cdr cset)) nocase?)))
          (lambda (c) (not (inner c)))))
       ((&)
        ;; Intersection: (& cset ...)
        (let ((preds (map (lambda (cs) (%compile-cset cs nocase?)) (cdr cset))))
          (lambda (c)
            (let in-loop ((ps preds))
              (or (null? ps)
                  (and ((car ps) c)
                       (in-loop (cdr ps))))))))
       ((-)
        ;; Difference: (- cset1 cset2 ...) -> cset1 AND NOT (or cset2 ...)
        (if (null? (cdr cset))
            (lambda (c) #f)
            (let ((first-p (%compile-cset (cadr cset) nocase?))
                  (rest-p (if (null? (cddr cset))
                              (lambda (c) #f)
                              (%compile-cset (cons 'or (cddr cset)) nocase?))))
              (lambda (c)
                (and (first-p c) (not (rest-p c)))))))
       ((or)
        ;; Union: (or cset ...)
        (let ((preds (map (lambda (cs) (%compile-cset cs nocase?)) (cdr cset))))
          (lambda (c)
            (let in-loop ((ps preds))
              (and (pair? ps)
                   (or ((car ps) c)
                       (in-loop (cdr ps))))))))
       ((w/nocase)
        (%compile-cset (cons 'or (cdr cset)) #t))
       ((w/case)
        (%compile-cset (cons 'or (cdr cset)) #f))
       (else
        (error "cset: unrecognized character set operator" (car cset)))))
    (else
     (error "cset: invalid character set specification" cset))))

;; ---------------------------------------------------------------------
;; §3. SRE Syntax Validation & Pre-scan
;; ---------------------------------------------------------------------

(define (valid-sre? sre)
  (cond
    ((char? sre) #t)
    ((string? sre) #t)
    ((symbol? sre)
     (memq sre '(any nonl bos eos bol eol bow eow nwb word
                 alpha alphabetic numeric whitespace upper upper-case
                 lower lower-case ascii blank cntrl control
                 graph graphic print printing punct punctuation
                 xdigit hex-digit)))
    ((pair? sre)
     (case (car sre)
       ((: seq or and)
        (let loop ((rest (cdr sre)))
          (or (null? rest)
              (and (valid-sre? (car rest))
                   (loop (cdr rest))))))
       ((* + ? *? +? ?? word word+)
        (let loop ((rest (cdr sre)))
          (or (null? rest)
              (and (valid-sre? (car rest))
                   (loop (cdr rest))))))
       ((= >=)
        (and (pair? (cdr sre))
             (exact-integer? (cadr sre))
             (>= (cadr sre) 0)
             (let loop ((rest (cddr sre)))
               (or (null? rest)
                   (and (valid-sre? (car rest))
                        (loop (cdr rest)))))))
       ((**)
        (and (pair? (cdr sre))
             (pair? (cddr sre))
             (exact-integer? (cadr sre))
             (exact-integer? (caddr sre))
             (<= (cadr sre) (caddr sre))
             (let loop ((rest (cdddr sre)))
               (or (null? rest)
                   (and (valid-sre? (car rest))
                        (loop (cdr rest)))))))
       ((**?)
        (and (pair? (cdr sre))
             (pair? (cddr sre))
             (exact-integer? (cadr sre))
             (exact-integer? (caddr sre))
             (<= (cadr sre) (caddr sre))
             (let loop ((rest (cdddr sre)))
               (or (null? rest)
                   (and (valid-sre? (car rest))
                        (loop (cdr rest)))))))
       ((submatch)
        (let loop ((rest (cdr sre)))
          (or (null? rest)
              (and (valid-sre? (car rest))
                   (loop (cdr rest))))))
       ((submatch-named)
        (and (pair? (cdr sre))
             (symbol? (cadr sre))
             (let loop ((rest (cddr sre)))
               (or (null? rest)
                   (and (valid-sre? (car rest))
                        (loop (cdr rest)))))))
       ((bos eos bol eol bow eow nwb)
        #t)
       ((/ ~ & -)
        #t)
       ((w/nocase w/case)
        (let loop ((rest (cdr sre)))
          (or (null? rest)
              (and (valid-sre? (car rest))
                   (loop (cdr rest))))))
       (else #f)))
    (else #f)))

;; Count submatches and collect named submatch mappings ((name . index) ...)
(define (%scan-submatches sre)
  (let ((counter (vector 0))
        (named-acc (vector '())))
    (let loop-sub ((cur sre))
      (if (pair? cur)
          (case (car cur)
            ((submatch)
             (let ((idx (+ (vector-ref counter 0) 1)))
               (vector-set! counter 0 idx)
               (for-each loop-sub (cdr cur))))
            ((submatch-named)
             (let ((name (cadr cur))
                   (idx (+ (vector-ref counter 0) 1)))
               (vector-set! counter 0 idx)
               (vector-set! named-acc 0 (cons (cons name idx) (vector-ref named-acc 0)))
               (for-each loop-sub (cddr cur))))
            (else
             (for-each loop-sub (cdr cur))))))
    (cons (vector-ref counter 0) (reverse (vector-ref named-acc 0)))))

;; ---------------------------------------------------------------------
;; §4. Capture Buffer Helpers
;; ---------------------------------------------------------------------

;; Caps format: vector of (cons start-idx end-idx) or #f
(define (%make-caps count)
  (make-vector (+ count 1) #f))

(define (%copy-caps caps)
  (let* ((len (vector-length caps))
         (v (make-vector len #f)))
    (let loop ((i 0))
      (if (= i len)
          v
          (begin
            (vector-set! v i (vector-ref caps i))
            (loop (+ i 1)))))))

(define (%caps-set-start! caps idx pos)
  (let ((old (vector-ref caps idx)))
    (vector-set! caps idx (cons pos (if old (cdr old) #f)))))

(define (%caps-set-end! caps idx pos)
  (let ((old (vector-ref caps idx)))
    (vector-set! caps idx (cons (if old (car old) 0) pos))))

;; ---------------------------------------------------------------------
;; §5. Matcher Combinators (CPS Engine)
;; ---------------------------------------------------------------------
;;
;; Matcher signature:
;;   (lambda (str idx start end caps whole? k-succ k-fail) ...)
;;   k-succ: (lambda (new-idx new-caps new-k-fail) ...)
;;   k-fail: (lambda () ...)

(define (%matcher-char target-c nocase?)
  (let ((c-check (if nocase? (char-downcase target-c) target-c)))
    (lambda (str idx start end caps whole? k-succ k-fail)
      (if (< idx end)
          (let ((c (string-ref str idx)))
            (if (char=? (if nocase? (char-downcase c) c) c-check)
                (k-succ (+ idx 1) caps k-fail)
                (k-fail)))
          (k-fail)))))

(define (%matcher-string target-str nocase?)
  (let ((t-len (string-length target-str)))
    (lambda (str idx start end caps whole? k-succ k-fail)
      (if (<= (+ idx t-len) end)
          (let loop ((i 0))
            (if (= i t-len)
                (k-succ (+ idx t-len) caps k-fail)
                (let ((c1 (string-ref str (+ idx i)))
                      (c2 (string-ref target-str i)))
                  (if (char=? (if nocase? (char-downcase c1) c1)
                              (if nocase? (char-downcase c2) c2))
                      (loop (+ i 1))
                      (k-fail)))))
          (k-fail)))))

(define (%matcher-pred pred)
  (lambda (str idx start end caps whole? k-succ k-fail)
    (if (< idx end)
        (if (pred (string-ref str idx))
            (k-succ (+ idx 1) caps k-fail)
            (k-fail))
        (k-fail))))

(define (%matcher-seq m1 m2)
  (lambda (str idx start end caps whole? k-succ k-fail)
    (m1 str idx start end caps whole?
        (lambda (i1 caps1 k-fail1)
          (m2 str i1 start end caps1 whole? k-succ k-fail1))
        k-fail)))

(define (%matcher-or m1 m2)
  (lambda (str idx start end caps whole? k-succ k-fail)
    (let ((caps-copy (%copy-caps caps)))
      (m1 str idx start end caps whole?
          k-succ
          (lambda ()
            (m2 str idx start end caps-copy whole? k-succ k-fail))))))

(define (%matcher-epsilon)
  (lambda (str idx start end caps whole? k-succ k-fail)
    (k-succ idx caps k-fail)))

;; Greedy repetition: from..to
(define (%matcher-repeat-greedy m from to)
  (lambda (str idx start end caps whole? k-succ k-fail)
    (let loop-rep ((count 0) (cur-idx idx) (cur-caps caps) (cur-k-fail k-fail))
      (if (and to (>= count to))
          (k-succ cur-idx cur-caps cur-k-fail)
          (if (< count from)
              ;; Must match at least `from` times
              (m str cur-idx start end cur-caps whole?
                 (lambda (next-idx next-caps next-fail)
                   (if (= next-idx cur-idx)
                       ;; Zero-width advance: prevent infinite loop
                       (if (>= (+ count 1) from)
                           (k-succ next-idx next-caps next-fail)
                           (next-fail))
                       (loop-rep (+ count 1) next-idx next-caps next-fail)))
                 cur-k-fail)
              ;; >= from: try matching one more greedily; on failure, backtrack to current position
              (let ((saved-caps (%copy-caps cur-caps)))
                (m str cur-idx start end cur-caps whole?
                   (lambda (next-idx next-caps next-fail)
                     (if (= next-idx cur-idx)
                         (k-succ cur-idx saved-caps next-fail)
                         (loop-rep (+ count 1) next-idx next-caps
                              (lambda ()
                                (k-succ cur-idx saved-caps next-fail)))))
                   (lambda ()
                     (k-succ cur-idx saved-caps cur-k-fail)))))))))

;; Non-greedy repetition: from..to
(define (%matcher-repeat-non-greedy m from to)
  (lambda (str idx start end caps whole? k-succ k-fail)
    (let loop-rep ((count 0) (cur-idx idx) (cur-caps caps) (cur-k-fail k-fail))
      (if (< count from)
          ;; Must match at least `from` times
          (m str cur-idx start end cur-caps whole?
             (lambda (next-idx next-caps next-fail)
               (if (= next-idx cur-idx)
                   (if (>= (+ count 1) from)
                       (k-succ next-idx next-caps next-fail)
                       (next-fail))
                   (loop-rep (+ count 1) next-idx next-caps next-fail)))
             cur-k-fail)
          ;; >= from: first try accepting current position; on failure, try extending by matching one more
          (let ((saved-caps (%copy-caps cur-caps)))
            (k-succ cur-idx cur-caps
                    (lambda ()
                      (if (and to (>= count to))
                          (cur-k-fail)
                          (m str cur-idx start end saved-caps whole?
                             (lambda (next-idx next-caps next-fail)
                               (if (= next-idx cur-idx)
                                   (next-fail)
                                   (loop-rep (+ count 1) next-idx next-caps next-fail)))
                             cur-k-fail)))))))))

;; Submatch capture combinator
(define (%matcher-submatch m sub-idx)
  (lambda (str idx start end caps whole? k-succ k-fail)
    (let ((caps-enter (%copy-caps caps)))
      (%caps-set-start! caps-enter sub-idx idx)
      (m str idx start end caps-enter whole?
         (lambda (next-idx next-caps next-fail)
           (let ((caps-exit (%copy-caps next-caps)))
             (%caps-set-end! caps-exit sub-idx next-idx)
             (k-succ next-idx caps-exit next-fail)))
         k-fail))))

;; Boundary assertions
(define (%matcher-bos)
  (lambda (str idx start end caps whole? k-succ k-fail)
    (if (= idx start)
        (k-succ idx caps k-fail)
        (k-fail))))

(define (%matcher-eos)
  (lambda (str idx start end caps whole? k-succ k-fail)
    (if (= idx end)
        (k-succ idx caps k-fail)
        (k-fail))))

(define (%matcher-bol)
  (lambda (str idx start end caps whole? k-succ k-fail)
    (if (or (= idx start)
            (char=? (string-ref str (- idx 1)) #\newline))
        (k-succ idx caps k-fail)
        (k-fail))))

(define (%matcher-eol)
  (lambda (str idx start end caps whole? k-succ k-fail)
    (if (or (= idx end)
            (char=? (string-ref str idx) #\newline))
        (k-succ idx caps k-fail)
        (k-fail))))

(define (%matcher-bow)
  (lambda (str idx start end caps whole? k-succ k-fail)
    (let ((cur-w (and (< idx end) (%char-word? (string-ref str idx))))
          (prev-w (and (> idx start) (%char-word? (string-ref str (- idx 1))))))
      (if (and cur-w (not prev-w))
          (k-succ idx caps k-fail)
          (k-fail)))))

(define (%matcher-eow)
  (lambda (str idx start end caps whole? k-succ k-fail)
    (let ((cur-w (and (< idx end) (%char-word? (string-ref str idx))))
          (prev-w (and (> idx start) (%char-word? (string-ref str (- idx 1))))))
      (if (and (not cur-w) prev-w)
          (k-succ idx caps k-fail)
          (k-fail)))))

(define (%matcher-nwb)
  (lambda (str idx start end caps whole? k-succ k-fail)
    (let ((cur-w (and (< idx end) (%char-word? (string-ref str idx))))
          (prev-w (and (> idx start) (%char-word? (string-ref str (- idx 1))))))
      (if (eq? (and cur-w #t) (and prev-w #t))
          (k-succ idx caps k-fail)
          (k-fail)))))

;; ---------------------------------------------------------------------
;; §6. SRE Compiler
;; ---------------------------------------------------------------------

(define (%compile-sre sre nocase? sub-counter)
  (cond
    ((char? sre)
     (%matcher-char sre nocase?))
    ((string? sre)
     (if (zero? (string-length sre))
         (%matcher-epsilon)
         (%matcher-string sre nocase?)))
    ((symbol? sre)
     (case sre
       ((bos) (%matcher-bos))
       ((eos) (%matcher-eos))
       ((bol) (%matcher-bol))
       ((eol) (%matcher-eol))
       ((bow) (%matcher-bow))
       ((eow) (%matcher-eow))
       ((nwb) (%matcher-nwb))
       ((word) (%matcher-seq (%matcher-bow) (%matcher-eow)))
       (else
        (let ((pred (%named-char-class-pred sre)))
          (if pred
              (%matcher-pred pred)
              (error "compile-sre: unrecognized SRE symbol" sre))))))
    ((pair? sre)
     (let ((op (car sre))
           (args (cdr sre)))
       (case op
         ((: seq)
          (if (null? args)
              (%matcher-epsilon)
              (let loop ((first (%compile-sre (car args) nocase? sub-counter))
                         (rest (cdr args)))
                (if (null? rest)
                    first
                    (loop (%matcher-seq first (%compile-sre (car rest) nocase? sub-counter))
                          (cdr rest))))))
         ((or)
          (if (null? args)
              (lambda (str idx start end caps whole? k-succ k-fail) (k-fail))
              (let loop ((first (%compile-sre (car args) nocase? sub-counter))
                         (rest (cdr args)))
                (if (null? rest)
                    first
                    (loop (%matcher-or first (%compile-sre (car rest) nocase? sub-counter))
                          (cdr rest))))))
         ((*)
          (let ((body (%compile-sre (cons ': args) nocase? sub-counter)))
            (%matcher-repeat-greedy body 0 #f)))
         ((+)
          (let ((body (%compile-sre (cons ': args) nocase? sub-counter)))
            (%matcher-repeat-greedy body 1 #f)))
         ((?)
          (let ((body (%compile-sre (cons ': args) nocase? sub-counter)))
            (%matcher-repeat-greedy body 0 1)))
         ((=)
          (let ((n (car args))
                (body (%compile-sre (cons ': (cdr args)) nocase? sub-counter)))
            (%matcher-repeat-greedy body n n)))
         ((>=)
          (let ((n (car args))
                (body (%compile-sre (cons ': (cdr args)) nocase? sub-counter)))
            (%matcher-repeat-greedy body n #f)))
         ((**)
          (let ((from (car args))
                (to (cadr args))
                (body (%compile-sre (cons ': (cddr args)) nocase? sub-counter)))
            (%matcher-repeat-greedy body from to)))
         ((*?)
          (let ((body (%compile-sre (cons ': args) nocase? sub-counter)))
            (%matcher-repeat-non-greedy body 0 #f)))
         ((+?)
          (let ((body (%compile-sre (cons ': args) nocase? sub-counter)))
            (%matcher-repeat-non-greedy body 1 #f)))
         ((??)
          (let ((body (%compile-sre (cons ': args) nocase? sub-counter)))
            (%matcher-repeat-non-greedy body 0 1)))
         ((**?)
          (let ((from (car args))
                (to (cadr args))
                (body (%compile-sre (cons ': (cddr args)) nocase? sub-counter)))
            (%matcher-repeat-non-greedy body from to)))
         ((submatch)
          (let* ((idx (+ (vector-ref sub-counter 0) 1))
                 (_ (vector-set! sub-counter 0 idx))
                 (body (%compile-sre (cons ': args) nocase? sub-counter)))
            (%matcher-submatch body idx)))
         ((submatch-named)
          (let* ((idx (+ (vector-ref sub-counter 0) 1))
                 (_ (vector-set! sub-counter 0 idx))
                 (body (%compile-sre (cons ': (cdr args)) nocase? sub-counter)))
            (%matcher-submatch body idx)))
         ((bos) (%matcher-bos))
         ((eos) (%matcher-eos))
         ((bol) (%matcher-bol))
         ((eol) (%matcher-eol))
         ((bow) (%matcher-bow))
         ((eow) (%matcher-eow))
         ((nwb) (%matcher-nwb))
         ((word)
          (%compile-sre (list ': 'bow (cons ': args) 'eow) nocase? sub-counter))
         ((word+)
          (%compile-sre (list ': 'bow (list '+ (cons ': args)) 'eow) nocase? sub-counter))
         ((w/nocase)
          (%compile-sre (cons ': args) #t sub-counter))
         ((w/case)
          (%compile-sre (cons ': args) #f sub-counter))
         ((/ ~ & -)
          (%matcher-pred (%compile-cset sre nocase?)))
         (else
          (error "compile-sre: unrecognized SRE operator" op)))))
    (else
     (error "compile-sre: invalid SRE form" sre))))

;; Top-level regexp compiler
(define (regexp sre)
  (if (regexp? sre)
      sre
      (let* ((scan-info (%scan-submatches sre))
             (num-subs (car scan-info))
             (names (cdr scan-info))
             (counter (vector 0))
             (raw-matcher (%compile-sre sre #f counter)))
        ;; Wrap matcher to handle group 0 (entire match capture)
        (let ((wrapped-matcher
               (lambda (str idx start end caps whole? k-succ k-fail)
                 (%caps-set-start! caps 0 idx)
                 (raw-matcher str idx start end caps whole?
                              (lambda (final-idx final-caps final-fail)
                                (%caps-set-end! final-caps 0 final-idx)
                                (if whole?
                                    (if (= final-idx end)
                                        (k-succ final-idx final-caps final-fail)
                                        (final-fail))
                                    (k-succ final-idx final-caps final-fail)))
                              k-fail))))
          (%make-regexp sre num-subs names wrapped-matcher)))))

;; Macro `rx`: (rx sre ...) -> (regexp '(: sre ...))
(define-syntax rx
  (syntax-rules ()
    ((rx sre ...)
     (regexp '(: sre ...)))))

;; ---------------------------------------------------------------------
;; §7. Matching Execution (matches, matches?, search)
;; ---------------------------------------------------------------------

(define (%regexp-matches-internal re str start end)
  (let* ((compiled (regexp re))
         (matcher (%regexp-matcher compiled))
         (num-subs (regexp-num-submatches compiled))
         (names (regexp-named-submatches compiled))
         (caps (%make-caps num-subs))
         (result-box (vector #f)))
    (matcher str start start end caps #t
             (lambda (final-idx final-caps final-fail)
               (vector-set! result-box 0
                            (%make-regexp-match str final-caps names num-subs))
               #t)
             (lambda () #f))
    (vector-ref result-box 0)))

(define regexp-matches
  (case-lambda
    ((re str)
     (%regexp-matches-internal re str 0 (string-length str)))
    ((re str start)
     (%regexp-matches-internal re str start (string-length str)))
    ((re str start end)
     (%regexp-matches-internal re str start end))))

(define regexp-matches?
  (case-lambda
    ((re str)
     (and (regexp-matches re str) #t))
    ((re str start)
     (and (regexp-matches re str start) #t))
    ((re str start end)
     (and (regexp-matches re str start end) #t))))

(define (%regexp-search-internal re str start end)
  (let* ((compiled (regexp re))
         (matcher (%regexp-matcher compiled))
         (num-subs (regexp-num-submatches compiled))
         (names (regexp-named-submatches compiled)))
    (let loop ((pos start))
      (if (> pos end)
          #f
          (let ((caps (%make-caps num-subs))
                (found (vector #f)))
            (matcher str pos start end caps #f
                     (lambda (final-idx final-caps final-fail)
                       (vector-set! found 0
                                    (%make-regexp-match str final-caps names num-subs))
                       #t)
                     (lambda () #f))
            (if (vector-ref found 0)
                (vector-ref found 0)
                (loop (+ pos 1))))))))

(define regexp-search
  (case-lambda
    ((re str)
     (%regexp-search-internal re str 0 (string-length str)))
    ((re str start)
     (%regexp-search-internal re str start (string-length str)))
    ((re str start end)
     (%regexp-search-internal re str start end))))

;; ---------------------------------------------------------------------
;; §8. Match Object Accessors
;; ---------------------------------------------------------------------

(define (%resolve-submatch-index m key)
  (cond
    ((exact-integer? key) key)
    ((symbol? key)
     (let ((entry (assq key (%match-names m))))
       (if entry
           (cdr entry)
           (error "regexp-match: named submatch not found" key))))
    (else
     (error "regexp-match: expected integer index or symbol name" key))))

(define regexp-match-submatch
  (case-lambda
    ((m) (regexp-match-submatch m 0))
    ((m key)
     (let* ((idx (%resolve-submatch-index m key))
            (caps (%match-submatches m)))
       (if (or (< idx 0) (>= idx (vector-length caps)))
           #f
           (let ((span (vector-ref caps idx)))
             (if (and span (car span) (cdr span))
                 (substring (%match-string m) (car span) (cdr span))
                 #f)))))))

(define regexp-match-submatch-start
  (case-lambda
    ((m) (regexp-match-submatch-start m 0))
    ((m key)
     (let* ((idx (%resolve-submatch-index m key))
            (caps (%match-submatches m)))
       (if (or (< idx 0) (>= idx (vector-length caps)))
           #f
           (let ((span (vector-ref caps idx)))
             (and span (car span))))))))

(define regexp-match-submatch-end
  (case-lambda
    ((m) (regexp-match-submatch-end m 0))
    ((m key)
     (let* ((idx (%resolve-submatch-index m key))
            (caps (%match-submatches m)))
       (if (or (< idx 0) (>= idx (vector-length caps)))
           #f
           (let ((span (vector-ref caps idx)))
             (and span (cdr span))))))))

;; ---------------------------------------------------------------------
;; §9. High-Level Text Utilities (fold, extract, split, replace)
;; ---------------------------------------------------------------------

(define (%regexp-fold-internal re kons knil str start end)
  (let ((compiled (regexp re)))
    (let loop ((pos start) (acc knil))
      (if (> pos end)
          acc
          (let ((m (regexp-search compiled str pos end)))
            (if m
                (let* ((m-start (regexp-match-submatch-start m 0))
                       (m-end (regexp-match-submatch-end m 0))
                       (next-acc (kons pos m str acc))
                       (next-pos (if (= m-start m-end)
                                     (+ m-end 1)
                                     m-end)))
                  (loop next-pos next-acc))
                acc))))))

(define regexp-fold
  (case-lambda
    ((re kons knil str)
     (%regexp-fold-internal re kons knil str 0 (string-length str)))
    ((re kons knil str start)
     (%regexp-fold-internal re kons knil str start (string-length str)))
    ((re kons knil str start end)
     (%regexp-fold-internal re kons knil str start end))))

(define (%regexp-extract-internal re str start end)
  (let ((res (%regexp-fold-internal
               re
               (lambda (from m s acc)
                 (cons (regexp-match-submatch m 0) acc))
               '()
               str
               start
               end)))
    (reverse res)))

(define regexp-extract
  (case-lambda
    ((re str)
     (%regexp-extract-internal re str 0 (string-length str)))
    ((re str start)
     (%regexp-extract-internal re str start (string-length str)))
    ((re str start end)
     (%regexp-extract-internal re str start end))))

(define (%regexp-split-internal re str start end)
  (let ((compiled (regexp re)))
    (let loop ((pos start) (acc '()))
      (if (> pos end)
          (reverse acc)
          (let ((m (regexp-search compiled str pos end)))
            (if m
                (let* ((m-start (regexp-match-submatch-start m 0))
                       (m-end (regexp-match-submatch-end m 0))
                       (part (substring str pos m-start))
                       (next-pos (if (= m-start m-end) (+ m-end 1) m-end)))
                  (loop next-pos (cons part acc)))
                (reverse (cons (substring str pos end) acc))))))))

(define regexp-split
  (case-lambda
    ((re str)
     (%regexp-split-internal re str 0 (string-length str)))
    ((re str start)
     (%regexp-split-internal re str start (string-length str)))
    ((re str start end)
     (%regexp-split-internal re str start end))))

(define (%regexp-partition-internal re str start end)
  (let ((compiled (regexp re)))
    (let loop ((pos start) (acc '()))
      (if (> pos end)
          (reverse acc)
          (let ((m (regexp-search compiled str pos end)))
            (if m
                (let* ((m-start (regexp-match-submatch-start m 0))
                       (m-end (regexp-match-submatch-end m 0))
                       (non-matched (substring str pos m-start))
                       (matched (substring str m-start m-end))
                       (next-pos (if (= m-start m-end) (+ m-end 1) m-end)))
                  (loop next-pos (cons matched (cons non-matched acc))))
                (reverse (cons (substring str pos end) acc))))))))

(define regexp-partition
  (case-lambda
    ((re str)
     (%regexp-partition-internal re str 0 (string-length str)))
    ((re str start)
     (%regexp-partition-internal re str start (string-length str)))
    ((re str start end)
     (%regexp-partition-internal re str start end))))


;; Helper to safely concatenate a list of strings without hitting multi-arg apply limits
(define (%string-concat-list lst)
  (let loop ((cur lst) (acc ""))
    (if (null? cur)
        acc
        (loop (cdr cur) (string-append acc (car cur))))))

(define (%format-replacement m subst)
  (cond
    ((string? subst) subst)
    ((procedure? subst) (subst m))
    ((integer? subst) (or (regexp-match-submatch m subst) ""))
    ((symbol? subst) (or (regexp-match-submatch m subst) ""))
    ((pair? subst)
     (%string-concat-list
      (map (lambda (part) (%format-replacement m part)) subst)))
    (else "")))

(define (%regexp-replace-internal re str subst start end)
  (let ((m (regexp-search re str start end)))
    (if m
        (let* ((m-start (regexp-match-submatch-start m 0))
               (m-end (regexp-match-submatch-end m 0))
               (rep (%format-replacement m subst)))
          (string-append (substring str 0 m-start)
                         rep
                         (substring str m-end (string-length str))))
        str)))

(define regexp-replace
  (case-lambda
    ((re str subst)
     (%regexp-replace-internal re str subst 0 (string-length str)))
    ((re str subst start)
     (%regexp-replace-internal re str subst start (string-length str)))
    ((re str subst start end)
     (%regexp-replace-internal re str subst start end))))

(define (%regexp-replace-all-internal re str subst start end)
  (let ((compiled (regexp re)))
    (let loop ((pos start) (last-end 0) (acc '()))
      (if (> pos end)
          (%string-concat-list (reverse (cons (substring str last-end (string-length str)) acc)))
          (let ((m (regexp-search compiled str pos end)))
            (if m
                (let* ((m-start (regexp-match-submatch-start m 0))
                       (m-end (regexp-match-submatch-end m 0))
                       (rep (%format-replacement m subst))
                       (pre (substring str last-end m-start))
                       (next-pos (if (= m-start m-end) (+ m-end 1) m-end)))
                  (loop next-pos m-end (cons rep (cons pre acc))))
                (%string-concat-list (reverse (cons (substring str last-end (string-length str)) acc)))))))))

(define regexp-replace-all
  (case-lambda
    ((re str subst)
     (%regexp-replace-all-internal re str subst 0 (string-length str)))
    ((re str subst start)
     (%regexp-replace-all-internal re str subst start (string-length str)))
    ((re str subst start end)
     (%regexp-replace-all-internal re str subst start end))))
