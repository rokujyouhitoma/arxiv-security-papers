;;; =======================================================================
;;; ULisp Compiler Pass 0: Common Helpers & Primitive Predicates
;;; Conforms to DSN-33 Architecture Specification
;;; =======================================================================

;;; Standard Helper Procedures (Self-hosting primitives)
(define (fixnum->char n) (integer->char n))
(define (char->fixnum c) (char->integer c))
(define (char-numeric? c) (let ((n (char->integer c))) (and (>= n 48) (<= n 57))))
(define (abs x) (if (< x 0) (- 0 x) x))
(define (safe-car x) (if (pair? x) (car x) '()))
(define (safe-cdr x) (if (pair? x) (cdr x) '()))

(define (string-starts-with? s prefix)
  (let ((slen (string-length s))
        (plen (string-length prefix)))
    (if (< slen plen)
        #f
        (let loop ((i 0))
          (if (= i plen)
              #t
              (if (char=? (string-ref s i) (string-ref prefix i))
                  (loop (+ i 1))
                  #f))))))

(define (car* x) (car x))
(define (cadr x) (safe-car (safe-cdr x)))
(define (cddr x) (safe-cdr (safe-cdr x)))
(define (cdar x) (safe-cdr (safe-car x)))
(define (caar x) (safe-car (safe-car x)))
(define (caddr x) (safe-car (safe-cdr (safe-cdr x))))
(define (cdddr x) (safe-cdr (safe-cdr (safe-cdr x))))
(define (cadar x) (safe-car (safe-cdr (safe-car x))))
(define (cadddr x) (safe-car (safe-cdr (safe-cdr (safe-cdr x)))))
(define (cddddr x) (safe-cdr (safe-cdr (safe-cdr (safe-cdr x)))))
(define (caaar x) (safe-car (safe-car (safe-car x))))
(define (cdaar x) (safe-cdr (safe-car (safe-car x))))
(define (caadar x) (safe-car (safe-car (safe-cdr (safe-car x)))))
(define (caadr x) (safe-car (safe-car (safe-cdr x))))
(define (cddar x) (safe-cdr (safe-cdr (safe-car x))))

(define (memq item ls)
  (cond
    ((not (pair? ls)) #f)
    ((eq? (car ls) item) ls)
    (else (memq item (cdr ls)))))

(define (assq item ls)
  (cond
    ((not (pair? ls)) #f)
    ((not (pair? (car ls))) (assq item (cdr ls)))
    ((eq? (caar ls) item) (car ls))
    (else (assq item (cdr ls)))))

(define (string-equal? s1 s2)
  (and (string? s1) (string? s2)
       (not (boolean? s1)) (not (boolean? s2))
       (= (string-length s1) (string-length s2))
       (let loop ((i 0) (len (string-length s1)))
         (if (= i len)
             #t
             (if (char=? (string-ref s1 i) (string-ref s2 i))
                 (loop (+ i 1) len)
                 #f)))))

(define (escape-gas-string s)
  (let* ((len (string-length s))
         (extra (let count-loop ((i 0) (acc 0))
                  (if (< i len)
                      (let ((c (string-ref s i)))
                        (if (or (char=? c #\newline)
                                (or (char=? c #\tab)
                                    (or (char=? c (integer->char 13))
                                        (or (char=? c #\\)
                                            (char=? c #\")))))
                            (count-loop (+ i 1) (+ acc 1))
                            (count-loop (+ i 1) acc)))
                      acc))))
    (if (= extra 0)
        s
        (let ((res (make-string (+ len extra))))
          (let loop ((i 0) (out-idx 0))
            (if (< i len)
                (let ((c (string-ref s i)))
                  (cond
                    ((char=? c #\newline)
                     (string-set! res out-idx #\\)
                     (string-set! res (+ out-idx 1) #\n)
                     (loop (+ i 1) (+ out-idx 2)))
                    ((char=? c #\tab)
                     (string-set! res out-idx #\\)
                     (string-set! res (+ out-idx 1) #\t)
                     (loop (+ i 1) (+ out-idx 2)))
                    ((char=? c (integer->char 13))
                     (string-set! res out-idx #\\)
                     (string-set! res (+ out-idx 1) #\r)
                     (loop (+ i 1) (+ out-idx 2)))
                    ((char=? c #\\)
                     (string-set! res out-idx #\\)
                     (string-set! res (+ out-idx 1) #\\)
                     (loop (+ i 1) (+ out-idx 2)))
                    ((char=? c #\")
                     (string-set! res out-idx #\\)
                     (string-set! res (+ out-idx 1) #\")
                     (loop (+ i 1) (+ out-idx 2)))
                    (else
                     (string-set! res out-idx c)
                     (loop (+ i 1) (+ out-idx 1)))))
                res))))))

(define (equal? a b)
  (cond
    ((eq? a b) #t)
    ((and (number? a) (number? b)) (= a b))
    ((and (string? a) (string? b)) (string-equal? a b))
    ((and (char? a) (char? b)) (char=? a b))
    ((and (pair? a) (pair? b))
     (and (equal? (car a) (car b))
          (equal? (cdr a) (cdr b))))
    (else #f)))

(define (assoc item ls)
  (cond
    ((not (pair? ls)) #f)
    ((not (pair? (car ls))) (assoc item (cdr ls)))
    ((equal? (caar ls) item) (car ls))
    (else (assoc item (cdr ls)))))

(define (length ls)
  (let loop ((l ls) (n 0))
    (if (null? l)
        n
        (loop (cdr l) (+ n 1)))))

(define (reverse ls)
  (let loop ((l ls) (acc '()))
    (if (null? l)
        acc
        (loop (cdr l) (cons (car l) acc)))))

(define (append l1 l2)
  (if (null? l1)
      l2
      (cons (car l1) (append (cdr l1) l2))))

(define (map f ls)
  (let loop ((cur ls) (acc '()))
    (cond
      ((null? cur) (reverse acc))
      ((not (pair? cur)) (reverse acc))
      (else
       (loop (cdr cur) (cons (f (car cur)) acc))))))

(define (for-each proc ls)
  (let loop ((cur ls))
    (if (and (not (null? cur)) (pair? cur))
        (begin
          (proc (car cur))
          (loop (cdr cur))))))

(define (filter pred ls)
  (let loop ((cur ls) (acc '()))
    (cond
      ((null? cur) (reverse acc))
      ((not (pair? cur)) (reverse acc))
      ((pred (car cur)) (loop (cdr cur) (cons (car cur) acc)))
      (else (loop (cdr cur) acc)))))

(define (list-ref ls n)
  (if (<= n 0)
      (car ls)
      (list-ref (cdr ls) (- n 1))))

;;; Compiler Execution Context (cons cells to prevent top-level set! in LIR/AOT)
(define *current-pass* (cons 'none '()))
(define *current-toplevel-name* (cons 'none '()))
(define *current-form* (cons 'none '()))
(define *current-source-file* (cons 'none '()))
(define *current-source-line* (cons 0 '()))
(define *current-source-col* (cons 0 '()))
(define *compiler-in-error* (cons #f '()))
(define *allow-extern-symbols* (cons #f '()))
(define (allow-extern-symbols?) (car *allow-extern-symbols*))
(define (set-allow-extern-symbols! val) (set-car! *allow-extern-symbols* val))

(define *module-mode* (cons #f '()))
(define (module-mode?) (car *module-mode*))
(define (set-module-mode! val) (set-car! *module-mode* val))

(define *current-module-id* (cons #f '()))
(define (current-module-id) (car *current-module-id*))
(define (set-current-module-id! id) (set-car! *current-module-id* id))

(define (current-source-file) (car *current-source-file*))
(define (set-current-source-file! f) (set-car! *current-source-file* f))

(define (current-source-line) (car *current-source-line*))
(define (set-current-source-line! l) (set-car! *current-source-line* l))

(define (current-source-col) (car *current-source-col*))
(define (set-current-source-col! c) (set-car! *current-source-col* c))

(define (source-loc? obj)
  (and (pair? obj)
       (eq? (car obj) '%source-loc)
       (pair? (cdr obj))
       (pair? (cddr obj))
       (pair? (cdddr obj))
       (pair? (cddddr obj))))

(define (source-loc-file loc) (cadr loc))
(define (source-loc-line loc) (caddr loc))
(define (source-loc-col loc) (cadddr loc))
(define (source-loc-form loc) (car (cddddr loc)))

(define (strip-source-loc obj)
  (if (source-loc? obj)
      (source-loc-form obj)
      obj))

;;; Call Stack Tracing Context (Conforms to DSN-33 & Issue #604)
(define *call-stack* (cons '() '()))
(define *call-stack-depth-limit* (cons 32 '()))
(define *debug-traceback-enabled* (cons #f '()))

(define (call-stack-trace-enabled?) (car *debug-traceback-enabled*))
(define (enable-call-stack-trace!) (set-car! *debug-traceback-enabled* #t))
(define (disable-call-stack-trace!) (set-car! *debug-traceback-enabled* #f))

(define (current-call-stack) (car *call-stack*))
(define (call-stack-depth-limit) (car *call-stack-depth-limit*))
(define (set-call-stack-depth-limit! limit) (set-car! *call-stack-depth-limit* limit))
(define (reset-call-stack!) (set-car! *call-stack* '()))

(define (take-prefix ls n)
  (let loop ((cur ls) (k n) (acc '()))
    (if (or (null? cur) (not (pair? cur)) (<= k 0))
        (reverse acc)
        (loop (cdr cur) (- k 1) (cons (car cur) acc)))))

(define (push-call-frame! name form)
  (if (call-stack-trace-enabled?)
      (let* ((cur (car *call-stack*))
             (summary (if (or (null? form) (eq? form 'none)) '() (truncate-expr-for-diagnostics form)))
             (frame (cons name summary))
             (len (length cur))
             (limit (car *call-stack-depth-limit*)))
        (if (>= len limit)
            (set-car! *call-stack* (cons frame (take-prefix cur (- limit 1))))
            (set-car! *call-stack* (cons frame cur))))
      #f))

(define (pop-call-frame!)
  (if (call-stack-trace-enabled?)
      (let ((cur (car *call-stack*)))
        (if (pair? cur)
            (set-car! *call-stack* (cdr cur))
            #f))
      #f))

(define (with-call-frame name form thunk)
  (if (not (call-stack-trace-enabled?))
      (thunk)
      (begin
        (push-call-frame! name form)
        (let ((res (thunk)))
          (pop-call-frame!)
          res))))

(define (capture-call-stack)
  (if (call-stack-trace-enabled?)
      (car *call-stack*)
      '()))

;;; -----------------------------------------------------------------------
;;; Error Object & Condition Helpers (R7RS §6.11 / Issue #604)
;;; -----------------------------------------------------------------------
(define (error-object? obj)
  (and (pair? obj) (eq? (car obj) 'error-object)))

(define (error-object-message obj)
  (if (error-object? obj)
      (cadr obj)
      "unknown error"))

(define (error-object-irritants obj)
  (if (error-object? obj)
      (let filter-tb ((cur (cddr obj)))
        (cond
          ((null? cur) '())
          ((not (pair? cur)) cur)
          ((and (pair? (car cur)) (pair? (car (car cur))) (eq? (car (car cur)) '%traceback))
           (filter-tb (cdr cur)))
          ((and (pair? (car cur)) (eq? (car (car cur)) '%traceback))
           (filter-tb (cdr cur)))
          (else (cons (car cur) (filter-tb (cdr cur))))))
      '()))

(define (error-object-traceback obj)
  (if (error-object? obj)
      (let loop ((cur (cddr obj)))
        (cond
          ((null? cur) '())
          ((not (pair? cur)) '())
          ((and (pair? (car cur)) (eq? (car (car cur)) '%traceback))
           (cdr (car cur)))
          (else (loop (cdr cur)))))
      '()))

(define (make-error-object msg irritants)
  (cons 'error-object (cons msg irritants)))

(define (make-error-object-with-traceback msg irritants tb)
  (cons 'error-object (cons msg (append irritants (list (cons '%traceback tb))))))

(define (display-call-stack-traceback frames)
  (if (null? frames)
      (display "    (no stack frames recorded - run with DEBUG=1 or --debug)\n")
      (let* ((rev-frames (reverse frames)))
        (let loop ((cur rev-frames) (i 1))
          (if (null? cur)
              #t
              (let* ((fr (car cur))
                     (name (car fr))
                     (summary (cdr fr)))
                (display "    [")
                (display i)
                (display "] ")
                (cond
                  ((and (pair? summary) (not (null? summary)))
                   (display "(")
                   (display (if (symbol? name) (symbol->string name) name))
                   (display " ")
                   (write summary)
                   (display ")"))
                  ((symbol? name)
                   (display "(")
                   (display (symbol->string name))
                   (display ")"))
                  (else
                   (write name)))
                (newline)
                (loop (cdr cur) (+ i 1))))))))

(define (string-join-lines lines)
  (let loop ((cur lines) (res ""))
    (if (null? cur)
        res
        (loop (cdr cur) (string-append res (car cur))))))

(define (format-call-stack-traceback frames)
  (if (null? frames)
      "    (no stack frames recorded - run with DEBUG=1 or --debug)\n"
      (let* ((rev-frames (reverse frames)))
        (let loop ((cur rev-frames) (i 1) (acc '()))
          (if (null? cur)
              (string-join-lines (reverse acc))
              (let* ((fr (car cur))
                     (name (car fr))
                     (name-str (if (symbol? name) (symbol->string name) "unknown"))
                     (summary (cdr fr))
                     (summary-str (if (and (pair? summary) (not (null? summary)))
                                      " (...)"
                                      ""))
                     (line (string-append "    [" (number->string i) "] (" name-str summary-str ")\n")))
                (loop (cdr cur) (+ i 1) (cons line acc))))))))

(define (current-pass) (car *current-pass*))
(define (set-current-pass! name) (set-car! *current-pass* name))

(define (current-toplevel-name) (car *current-toplevel-name*))
(define (set-current-toplevel-name! name) (set-car! *current-toplevel-name* name))

(define (current-form) (car *current-form*))
(define (set-current-form! form) (set-car! *current-form* form))

(define (reset-compiler-context!)
  (set-car! *current-pass* 'none)
  (set-car! *current-toplevel-name* 'none)
  (set-car! *current-form* 'none)
  (set-car! *current-source-file* 'none)
  (set-car! *current-source-line* 0)
  (set-car! *current-source-col* 0)
  (set-car! *compiler-in-error* #f)
  (reset-call-stack!))

;;; Safe AST truncation for diagnostics (prevents memory blowup / circular structures)
(define (truncate-expr-for-diagnostics expr)
  (let rec ((e expr) (depth 0))
    (cond
      ((> depth 3) '...)
      ((not (pair? e)) e)
      (else
       (let loop ((cur e) (count 0) (acc '()))
         (cond
           ((null? cur) (reverse acc))
           ((not (pair? cur)) (reverse (cons (cons '... cur) acc)))
           ((>= count 5) (reverse (cons '... acc)))
           (else
            (loop (cdr cur) (+ count 1) (cons (rec (car cur) (+ depth 1)) acc)))))))))

;;; Structured Compiler Diagnostic Report
(define (compiler-diagnostic-report msg irritants)
  (display "\n======================================================================\n")
  (display "[COMPILER ERROR] Compilation aborted in Pass: ")
  (display (current-pass))
  (newline)
  (display "======================================================================\n")
  (if (not (eq? (current-source-file) 'none))
      (begin
        (display "  Source Location   : ")
        (display (current-source-file))
        (display ":")
        (display (current-source-line))
        (if (> (current-source-col) 0)
            (begin
              (display ":")
              (display (current-source-col))))
        (newline)))
  (display "  Message           : ")
  (display msg)
  (newline)
  (display "  Target / Irritant : ")
  (write irritants)
  (newline)
  (display "  Toplevel Form     : ")
  (write (current-toplevel-name))
  (newline)
  (display "  Current Expr      : ")
  (write (truncate-expr-for-diagnostics (current-form)))
  (newline)
  (display "----------------------------------------------------------------------\n")
  (display "  Call Traceback (most recent call last):\n")
  (display-call-stack-traceback (current-call-stack))
  (display "======================================================================\n\n"))

(define (error msg val)
  (if (car *compiler-in-error*)
      (begin
        (display "\n*** [RECURSIVE ERROR] Aborting during error reporting: ")
        (display msg)
        (display " ")
        (write val)
        (newline)
        val)
      (begin
        (set-car! *compiler-in-error* #t)
        (compiler-diagnostic-report msg val)
        (set-car! *compiler-in-error* #f)
        val)))

;;; -----------------------------------------------------------------------
;;; String & Symbol Levenshtein Distance (Wagner-Fischer DP)
;;; Conforms to DSN-33 & Issue #603
;;; -----------------------------------------------------------------------

(define (min2 a b)
  (if (< a b) a b))

(define (min3 a b c)
  (min2 a (min2 b c)))

(define (string-levenshtein-distance s1 s2)
  (let ((len1 (string-length s1))
        (len2 (string-length s2)))
    (cond
      ((= len1 0) len2)
      ((= len2 0) len1)
      ((string-equal? s1 s2) 0)
      ;; Early pruning for large length difference
      ((> (abs (- len1 len2)) 10) (abs (- len1 len2)))
      (else
       (let ((v0 (make-vector (+ len2 1) 0))
             (v1 (make-vector (+ len2 1) 0)))
         (let init-v0 ((j 0))
           (if (<= j len2)
               (begin
                 (vector-set! v0 j j)
                 (init-v0 (+ j 1)))))
         (let loop-i ((i 0))
           (if (< i len1)
               (let ((c1 (string-ref s1 i)))
                 (vector-set! v1 0 (+ i 1))
                 (let loop-j ((j 0))
                   (if (< j len2)
                       (let* ((c2 (string-ref s2 j))
                              (cost (if (char=? c1 c2) 0 1))
                              (del-cost (+ (vector-ref v0 (+ j 1)) 1))
                              (ins-cost (+ (vector-ref v1 j) 1))
                              (sub-cost (+ (vector-ref v0 j) cost))
                              (m (min3 del-cost ins-cost sub-cost)))
                         (vector-set! v1 (+ j 1) m)
                         (loop-j (+ j 1)))))
                 (let copy-loop ((k 0))
                   (if (<= k len2)
                       (begin
                         (vector-set! v0 k (vector-ref v1 k))
                         (copy-loop (+ k 1)))))
                 (loop-i (+ i 1)))
               (vector-ref v0 len2))))))))

(define (symbol-levenshtein-distance sym1 sym2)
  (if (eq? sym1 sym2)
      0
      (string-levenshtein-distance (symbol->string sym1) (symbol->string sym2))))

(define (insert-symbol-match item sorted)
  (cond
    ((null? sorted) (list item))
    ((< (cdr item) (cdr (car sorted))) (cons item sorted))
    (else (cons (car sorted) (insert-symbol-match item (cdr sorted))))))

(define (sort-symbol-matches matches)
  (let loop ((unsorted matches) (sorted '()))
    (if (null? unsorted)
        sorted
        (loop (cdr unsorted) (insert-symbol-match (car unsorted) sorted)))))

(define (take-at-most lst n)
  (cond
    ((or (null? lst) (<= n 0)) '())
    (else (cons (car lst) (take-at-most (cdr lst) (- n 1))))))

(define (find-similar-symbols-dist target candidates max-dist)
  (let* ((target-str (symbol->string target))
         (target-len (string-length target-str)))
    (if (> target-len 64)
        '()
        (let loop ((rest candidates) (matches '()) (seen '()))
          (if (null? rest)
              (let* ((sorted (sort-symbol-matches matches))
                     (top-candidates (take-at-most sorted 3)))
                (let extract ((tc top-candidates) (res '()))
                  (if (null? tc)
                      (reverse res)
                      (extract (cdr tc) (cons (caar tc) res)))))
              (let ((cand (car rest)))
                (if (and (symbol? cand)
                         (not (eq? cand target))
                         (not (memq cand seen)))
                    (let* ((cand-str (symbol->string cand))
                           (cand-len (string-length cand-str)))
                      (if (and (<= cand-len 64)
                               (<= (abs (- target-len cand-len)) max-dist))
                          (let ((dist (string-levenshtein-distance target-str cand-str)))
                            (if (<= dist max-dist)
                                (loop (cdr rest) (cons (cons cand dist) matches) (cons cand seen))
                                (loop (cdr rest) matches (cons cand seen))))
                          (loop (cdr rest) matches (cons cand seen))))
                    (loop (cdr rest) matches seen))))))))

(define (find-similar-symbols target candidates)
  (find-similar-symbols-dist target candidates 2))

;;; -----------------------------------------------------------------------
;;; LIR Environment (env) Diagnostic Formatting
;;; Conforms to DSN-33 & Issue #603
;;; -----------------------------------------------------------------------

(define (format-binding-info info)
  (cond
    ((number? info) (string-append "stack " (number->string info)))
    ((and (pair? info) (eq? (car info) 'reg)) (string-append "reg " (symbol->string (cdr info))))
    ((symbol? info) (string-append "reg " (symbol->string info)))
    ((and (pair? info) (eq? (car info) 'param)) (string-append "param " (number->string (cdr info))))
    ((and (pair? info) (eq? (car info) 'self)) (string-append "self " (number->string (cdr info))))
    (else "val")))

(define (dump-lir-unbound-variable-diagnostic var env)
  (if (not (car *compiler-in-error*))
      (begin
        (set-car! *compiler-in-error* #t)
        (let* ((all-symbols (let loop ((e env) (acc '()))
                              (cond
                                ((null? e) (reverse acc))
                                ((not (pair? e)) (reverse acc))
                                ((and (pair? (car e)) (symbol? (caar e)))
                                 (loop (cdr e) (cons (caar e) acc)))
                                (else (loop (cdr e) acc)))))
               (similar (find-similar-symbols var all-symbols)))
          (display "\n======================================================================\n")
          (display "[LIR COMPILER ERROR] Unbound Variable Resolution Failed\n")
          (display "======================================================================\n")
          (display "  Unbound Symbol   : ")
          (display (symbol->string var))
          (newline)
          (display "  Current Function : ")
          (write (current-toplevel-name))
          (newline)
          (display "  Current Expr     : ")
          (write (truncate-expr-for-diagnostics (current-form)))
          (newline)
          (if (pair? similar)
              (begin
                (display "  Did you mean?    : ")
                (write similar)
                (newline))
              (begin
                (display "  Did you mean?    : (no similar candidates in scope)\n")))
          (display "  Active Local Bindings in 'env' (")
          (display (length all-symbols))
          (display " entries):\n")
          (if (null? env)
              (display "    - (empty environment)\n")
              (let print-env ((e env) (count 0))
                (cond
                  ((null? e) (display ""))
                  ((>= count 20)
                   (display "    - ... (")
                   (display (- (length all-symbols) 20))
                   (display " more bindings omitted)\n"))
                  ((and (pair? e) (pair? (car e)))
                   (let ((entry (car e)))
                     (display "    - ")
                     (display (symbol->string (car entry)))
                     (display " -> ")
                     (display (format-binding-info (cdr entry)))
                     (newline)
                     (print-env (cdr e) (+ count 1))))
                  (else (print-env (cdr e) (+ count 1))))))
          (display "======================================================================\n\n"))
        (set-car! *compiler-in-error* #f))))

;;; -----------------------------------------------------------------------
;;; Power Assert Diagnostics & Formatting Engine
;;; Conforms to DSN-33 & Issue #603
;;; -----------------------------------------------------------------------

(define (datum-repr-length d)
  (cond
    ((symbol? d) (string-length (symbol->string d)))
    ((number? d) (string-length (number->string d)))
    ((boolean? d) 2)
    ((null? d) 2)
    ((char? d) 3)
    ((string? d) (+ (string-length d) 2))
    ((pair? d)
     (let loop ((cur d) (len 2))
       (cond
         ((null? cur) len)
         ((not (pair? cur)) (+ len 3 (datum-repr-length cur)))
         ((null? (cdr cur)) (+ len (datum-repr-length (car cur))))
         (else (loop (cdr cur) (+ len (datum-repr-length (car cur)) 1))))))
    (else 4)))

(define (print-spaces n)
  (let loop ((i 0))
    (if (< i n)
        (begin
          (display " ")
          (loop (+ i 1))))))

(define (compute-expr-columns form base-col)
  (if (and (pair? form) (pair? (cdr form)))
      (let* ((op (car form))
             (op-col (+ base-col 1))
             (args (cdr form)))
        (let loop ((as args)
                   (cur-col (+ op-col (datum-repr-length op) 1))
                   (cols (list op-col)))
          (if (null? as)
              (reverse cols)
              (loop (cdr as)
                    (+ cur-col (datum-repr-length (car as)) 1)
                    (cons cur-col cols)))))
      (list base-col)))

(define (print-pipes-line cols)
  (let loop ((cur-col 0) (remaining cols))
    (if (pair? remaining)
        (let ((target-col (car remaining)))
          (print-spaces (- target-col cur-col))
          (display "|")
          (loop (+ target-col 1) (cdr remaining)))
        (newline))))

(define (format-power-assert-diagram expr-datum sub-evals result)
  (let ((base-col 4))
    (print-spaces base-col)
    (write expr-datum)
    (newline)
    (if (and (pair? expr-datum) (pair? (cdr expr-datum)))
        (let* ((cols (compute-expr-columns expr-datum base-col))
               (items (let loop ((cs (cdr cols)) (es sub-evals) (acc '()))
                        (if (or (null? cs) (null? es))
                            (cons (cons (car cols) result) acc)
                            (loop (cdr cs) (cdr es)
                                  (cons (cons (car cs) (cadar es)) acc))))))
          (print-pipes-line cols)
          (let print-items ((rem items))
            (if (pair? rem)
                (let* ((cur (car rem))
                       (col (car cur))
                       (val (cdr cur))
                       (left-cols (let filter-left ((cs cols) (lacc '()))
                                    (cond
                                      ((null? cs) (reverse lacc))
                                      ((< (car cs) col) (filter-left (cdr cs) (cons (car cs) lacc)))
                                      (else (reverse lacc))))))
                  (let loop-cols ((cur-c 0) (lcs left-cols))
                    (if (pair? lcs)
                        (let ((target-c (car lcs)))
                          (print-spaces (- target-c cur-c))
                          (display "|")
                          (loop-cols (+ target-c 1) (cdr lcs)))
                        (begin
                          (print-spaces (- col cur-c))
                          (write (truncate-expr-for-diagnostics val))
                          (newline))))
                  (print-items (cdr rem))))))
        (begin
          (print-spaces base-col)
          (display "|\n")
          (print-spaces base-col)
          (write (truncate-expr-for-diagnostics result))
          (newline)))))

(define (power-assert-report expr-datum sub-evals result)
  (display "\n======================================================================\n")
  (display "[POWER ASSERT FAILED] Assertion condition evaluated to #f\n")
  (display "======================================================================\n")
  (display "  Expression  : ")
  (write expr-datum)
  (newline)
  (display "  Evaluations :\n")
  (let loop ((items sub-evals))
    (if (pair? items)
        (let ((item (car items)))
          (display "    - ")
          (write (car item))
          (display " => ")
          (write (truncate-expr-for-diagnostics (cadr item)))
          (newline)
          (loop (cdr items)))))
  (display "  Result      : ")
  (write result)
  (newline)
  (display "----------------------------------------------------------------------\n")
  (display "  Diagram     :\n")
  (format-power-assert-diagram expr-datum sub-evals result)
  (display "======================================================================\n\n")
  (error "Power assertion failed" expr-datum))

(define (power-assert-expand form)
  (if (and (pair? form) (pair? (cdr form)))
      (let* ((op (car form))
             (args (cdr form))
             (arg-vars (let loop ((as args) (acc '()))
                         (if (null? as)
                             (reverse acc)
                             (loop (cdr as) (cons (unique-symbol "pa_arg_") acc)))))
             (res-var (unique-symbol "pa_res_"))
             (bindings (let loop ((as args) (vs arg-vars) (acc '()))
                         (if (null? as)
                             (reverse acc)
                             (loop (cdr as) (cdr vs) (cons (list (car vs) (car as)) acc)))))
             (evals-list (cons 'list
                               (let loop ((as args) (vs arg-vars) (acc '()))
                                 (if (null? as)
                                     (reverse acc)
                                     (loop (cdr as) (cdr vs)
                                           (cons (list 'list (list 'quote (car as)) (car vs)) acc)))))))
        (list 'let* bindings
              (list 'let (list (list res-var (cons op arg-vars)))
                    (list 'if (list 'not res-var)
                          (list 'power-assert-report (list 'quote form) evals-list res-var)
                          res-var))))
      (let ((res-var (unique-symbol "pa_res_")))
        (list 'let (list (list res-var form))
              (list 'if (list 'not res-var)
                    (list 'power-assert-report (list 'quote form) (list 'list (list 'list (list 'quote form) res-var)) res-var)
                    res-var)))))

;;; Deterministic symbol counter for unique variable generation
(define *symbol-counter* (cons 0 '()))
(define (unique-symbol prefix)
  (let ((s (string->symbol (string-append prefix (number->string (car *symbol-counter*))))))
    (set-car! *symbol-counter* (+ (car *symbol-counter*) 1))
    s))

;;; Deterministic label counter for assembly and lifted function labels
(define *label-counter* (cons 0 '()))
(define (unique-label prefix)
  (let ((l (string-append "." prefix "_" (number->string (car *label-counter*)))))
    (set-car! *label-counter* (+ (car *label-counter*) 1))
    l))
(define (unique-label-sym prefix)
  (string->symbol (unique-label prefix)))

;;; Set operations for variable scope analysis
(define (set-diff s1 s2)
  (cond
    ((null? s1) '())
    ((null? s2) s1)
    ((eq? s1 s2) '())
    ((memq (car s1) s2) (set-diff (cdr s1) s2))
    (else (cons (car s1) (set-diff (cdr s1) s2)))))

(define (set-union s1 s2)
  (cond
    ((null? s1) s2)
    ((null? s2) s1)
    ((eq? s1 s2) s1)
    ((memq (car s1) s2) (set-union (cdr s1) s2))
    (else (cons (car s1) (set-union (cdr s1) s2)))))

(define (has-symbol? datum)
  (cond
    ((symbol? datum) #t)
    ((pair? datum)
     (or (has-symbol? (car datum))
         (has-symbol? (cdr datum))))
    (else #f)))


;;; Symbol and String intern tables, frame alignment and utilities
;;; Symbol table for interned symbols
(define *symbol-table* (cons '() '()))
(define (reset-symbol-table!)
  (set-car! *symbol-table* '()))

(define (symbol-hash-str str)
  (let ((len (string-length str)))
    (let loop ((i 0) (h 5381))
      (if (= i len)
          (modulo h 16777213)
          (let ((c (char->integer (string-ref str i))))
            (loop (+ i 1)
                  (modulo (+ (* h 33) c) 16777213)))))))

(define (intern-symbol sym)
  (let ((entry (assq sym (car *symbol-table*))))
    (if entry
        (cadr entry)
        (let* ((str (symbol->string sym))
               (h (symbol-hash-str str))
               (id (+ (* h 256) 2)))
          (set-car! *symbol-table* (cons (list sym id str) (car *symbol-table*)))
          id))))

(define (symbol->raw-name sym)
  (let ((entry (assq sym (car *symbol-table*))))
    (if (and entry (pair? (cdr entry)) (pair? (cddr entry)))
        (caddr entry)
        (symbol->string sym))))

(define (get-all-symbols)
  (if (pair? *symbol-table*)
      (reverse (car *symbol-table*))
      '()))

;;; String table for interned string literals
(define *string-counter* (cons 0 '()))
(define *strings* (cons '() '()))
(define (intern-string str)
  (let ((label (string-append ".L_str_" (number->string (car *string-counter*)))))
    (set-car! *string-counter* (+ (car *string-counter*) 1))
    (set-car! *strings* (cons (cons label str) (car *strings*)))
    label))

(define (offset->string offset)
  (if (< offset 0)
      (string-append "- " (number->string (- 0 offset)))
      (string-append "+ " (number->string offset))))

(define (align-frame-shift needed)
  (if (= (modulo needed 16) 8)
      needed
      (+ needed 8)))

(define (expr-has-arithmetic-on-var? expr var)
  (cond
    ((not (pair? expr)) #f)
    ((and (memq (car expr) '(+ - *)) (memq var (cdr expr))) #t)
    (else (or (expr-has-arithmetic-on-var? (car expr) var)
              (expr-has-arithmetic-on-var? (cdr expr) var)))))

(define (expr-has-conditional-or-pred-on-var? expr var)
  (cond
    ((not (pair? expr)) #f)
    ((and (memq (car expr) '(fixnum? integer? number? pair? boolean? null? symbol? string? char?))
          (memq var (cdr expr)))
     #t)
    ((and (eq? (car expr) 'if) (pair? (cdr expr)))
     (or (expr-has-conditional-or-pred-on-var? (cadr expr) var)
         (expr-has-conditional-or-pred-on-var? (caddr expr) var)
         (if (null? (cdddr expr)) #f (expr-has-conditional-or-pred-on-var? (cadddr expr) var))))
    (else (or (expr-has-conditional-or-pred-on-var? (car expr) var)
              (expr-has-conditional-or-pred-on-var? (cdr expr) var)))))

(define (expr-size expr)
  (cond
    ((not (pair? expr)) 1)
    (else (+ 1 (expr-size (car expr)) (expr-size (cdr expr))))))

(define (%program? form)
  (and (pair? form) (eq? (car form) '%program)))

(define (char->mangle-str c)
  (cond
    ((or (and (char>=? c #\a) (char<=? c #\z))
         (and (char>=? c #\A) (char<=? c #\Z))
         (and (char>=? c #\0) (char<=? c #\9)))
     (let ((s (make-string 1))) (string-set! s 0 c) s))
    ((char=? c #\.) ".")
    ((char=? c #\_) "_")
    ((char=? c #\-) "_")
    ((char=? c #\?) "_p")
    ((char=? c #\!) "_excl")
    ((char=? c #\=) "_eq")
    ((char=? c #\<) "_lt")
    ((char=? c #\>) "_gt")
    ((char=? c #\+) "_plus")
    ((char=? c #\*) "_star")
    ((char=? c #\/) "_slash")
    ((char=? c #\%) "_pct")
    ((char=? c #\:) "_col")
    ((char=? c #\@) "_at")
    ((char=? c #\~) "_tilde")
    (else "_")))

(define (sanitize-label-str str)
  (let ((len (string-length str)))
    (let loop ((i 0) (res ""))
      (if (< i len)
          (loop (+ i 1) (string-append res (char->mangle-str (string-ref str i))))
          res))))

(define (mangle-fn-label name)
  (string->symbol (string-append "ulisp_fn_" (sanitize-label-str (symbol->string name)))))

(define (mangle-gvar-label name)
  (string-append "ulisp_gvar_" (sanitize-label-str (symbol->string name))))

(define (mangle-mod-init-label mod-id)
  (string-append "ulisp_mod_init_" (sanitize-label-str (if (symbol? mod-id) (symbol->string mod-id) mod-id))))

(define (make-body-expr bodies)
  (cond
    ((null? bodies) (list 'begin))
    ((null? (cdr bodies)) (car bodies))
    (else (cons 'begin bodies))))

;;; =======================================================================
;;; ULisp Compiler Primitives & Predicate Categorization
;;; =======================================================================

;;; Primitive procedure categorization predicates
(define (zero-arg-prim? op)
  (memq op '(read-char %read-char peek-char %peek-char eof-object flush-output-port ulisp-flush %get-rsp %get-heap-ptr %get-heap-limit-ptr %get-gc-state-ptr %get-stackmap-table %num-args)))

(define (unary-prim? op)
  (memq op '(fxadd1 fxsub1 fixnum->char char->fixnum integer->char char->integer
             integer->symbol symbol->integer
             zero? fixnum? integer? number? exact? exact-integer? inexact? real? rational? complex?
             boolean? char? null? not symbol?
             car cdr pair? procedure? string?
             write-char %write-char write-string %write-string flush-output-port ulisp-flush eof-object?
             make-string string-length
             bytevector? bytevector-length make-bytevector %make-bytevector
             vector? vector-length make-vector %make-vector
             raise %raise
             %set-heap-ptr! %ptr-tag %ptr-untag
             %to-raw %to-fixnum
             %box-fixnum %unbox-fixnum)))

(define (binop-prim? op)
  (memq op '(+ - * = < <= > >= modulo quotient / string-ref cons set-car! set-cdr! eq? eqv? char=? boolean=? symbol=?
             bytevector-u8-ref vector-ref
             %raw-load %ptr-add %ptr-tag-add bitwise-and bitwise-ior bitwise-arithmetic-shift
             %raw-add %raw-sub %raw-mul %raw-cmp)))

(define (triop-prim? op)
  (memq op '(string-set! bytevector-u8-set! vector-set! %raw-store!)))

(define (septop-prim? op)
  (memq op '(%raw-syscall)))

(define (closure-prim? op)
  (memq op '(%make-closure %make-closure-env %closure-ref %closure-set!)))

(define (lir-primitive? op)
  (or (zero-arg-prim? op)
      (unary-prim? op)
      (binop-prim? op)
      (triop-prim? op)
      (septop-prim? op)
      (closure-prim? op)))

(define (pure-prim? op)
  (memq op '(fxadd1 fxsub1 fixnum->char char->fixnum integer->char char->integer
             integer->symbol symbol->integer
             zero? fixnum? integer? number? exact? exact-integer? inexact? real? rational? complex?
             boolean? char? null? not symbol? list?
             car cdr pair? procedure? string? string-length %ptr-add %ptr-tag %ptr-untag %ptr-tag-add
             bytevector? bytevector-length vector? vector-length %num-args
             %to-raw %to-fixnum %box-fixnum %unbox-fixnum
             + - * = < <= > >= modulo quotient / eq? eqv? char=? boolean=? symbol=? cons %closure-ref
             %raw-add %raw-sub %raw-mul %raw-cmp)))

(define (const? x)
  (or (number? x)
      (boolean? x)
      (char? x)
      (null? x)
      (and (pair? x) (eq? (car x) 'quote))))

(define (atomic-expr? expr)
  (or (symbol? expr)
      (const? expr)))

(define (extract-const-val c)
  (if (and (pair? c) (eq? (car c) 'quote))
      (cadr c)
      c))

(define (val->ast-const v)
  (cond
    ((number? v) v)
    ((boolean? v) v)
    ((char? v) v)
    ((null? v) '(quote ()))
    (else (list 'quote v))))

(define (commutative-op? op)
  (memq op '(+ * = eq? eqv? char=? boolean=? symbol=?)))

(define (type-predicate-op? op)
  (memq op '(fixnum? integer? number? exact? exact-integer? inexact? real? rational? complex?
             pair? null? boolean? char? symbol? list? zero? procedure? string?)))

(define (pure-accessor-op? op)
  (memq op '(car cdr)))

(define (pure-expr? expr)
  (cond
    ((atomic-expr? expr) #t)
    ((pair? expr)
     (let ((op (car expr)))
       (case op
         ((quote) #t)
         ((lambda) #t)
         ((if) (and (pure-expr? (cadr expr))
                    (pure-expr? (caddr expr))
                    (if (null? (cdddr expr)) #t (pure-expr? (cadddr expr)))))
         ((begin)
          (let loop ((es (cdr expr)))
            (if (null? es) #t
                (and (pure-expr? (car es)) (loop (cdr es))))))
         ((let)
          (let ((bindings (cadr expr))
                (body (caddr expr)))
            (and (let loop ((bs bindings))
                   (if (null? bs) #t
                       (and (pure-expr? (cadar bs)) (loop (cdr bs)))))
                 (pure-expr? body))))
         ((letrec)
          (let ((bindings (cadr expr))
                (body (caddr expr)))
            (and (let loop ((bs bindings))
                   (if (null? bs) #t
                       (and (pure-expr? (cadar bs)) (loop (cdr bs)))))
                 (pure-expr? body))))
         (else
          (and (pure-prim? op)
               (let loop ((args (cdr expr)))
                 (if (null? args) #t
                     (and (pure-expr? (car args)) (loop (cdr args))))))))))
    (else #f)))

(define (fold-const-op op args)
  (let ((nargs (length args)))
    (cond
      ;; Unary arithmetic / predicates
      ((and (= nargs 1) (const? (car args)))
       (let ((v (extract-const-val (car args))))
         (case op
           ((fxadd1) (if (number? v) (val->ast-const (+ v 1)) #f))
           ((fxsub1) (if (number? v) (val->ast-const (- v 1)) #f))
           ((zero?) (if (number? v) (val->ast-const (= v 0)) #f))
           ((not) (val->ast-const (if (eq? v #f) #t #f)))
           ((null?) (val->ast-const (null? v)))
           ((pair?) (val->ast-const (pair? v)))
           ((number? fixnum? integer? exact? exact-integer? real? rational? complex?)
            (val->ast-const (number? v)))
           ((inexact?) (val->ast-const #f))
           ((boolean?) (val->ast-const (boolean? v)))
           ((char?) (val->ast-const (char? v)))
           ((symbol?) (val->ast-const (symbol? v)))
           ((car) (if (pair? v) (val->ast-const (car v)) #f))
           ((cdr) (if (pair? v) (val->ast-const (cdr v)) #f))
           (else #f))))
      ;; Binary arithmetic / predicates
      ((and (= nargs 2) (const? (car args)) (const? (cadr args)))
       (let ((v1 (extract-const-val (car args)))
             (v2 (extract-const-val (cadr args))))
         (case op
           ((+) (if (and (number? v1) (number? v2)) (val->ast-const (+ v1 v2)) #f))
           ((-) (if (and (number? v1) (number? v2)) (val->ast-const (- v1 v2)) #f))
           ((*) (if (and (number? v1) (number? v2)) (val->ast-const (* v1 v2)) #f))
           ((quotient /)
            (if (and (number? v1) (number? v2) (not (= v2 0)))
                (val->ast-const (quotient v1 v2))
                #f))
           ((modulo)
            (if (and (number? v1) (number? v2) (not (= v2 0)))
                (val->ast-const (modulo v1 v2))
                #f))
           ((=) (if (and (number? v1) (number? v2)) (val->ast-const (= v1 v2)) #f))
           ((<) (if (and (number? v1) (number? v2)) (val->ast-const (< v1 v2)) #f))
           ((<=) (if (and (number? v1) (number? v2)) (val->ast-const (<= v1 v2)) #f))
           ((>) (if (and (number? v1) (number? v2)) (val->ast-const (> v1 v2)) #f))
           ((>=) (if (and (number? v1) (number? v2)) (val->ast-const (>= v1 v2)) #f))
           ((eq? eqv?) (val->ast-const (eq? v1 v2)))
           ((char=?) (if (and (char? v1) (char? v2)) (val->ast-const (char=? v1 v2)) #f))
           ((boolean=?) (if (and (boolean? v1) (boolean? v2)) (val->ast-const (eq? v1 v2)) #f))
           ((symbol=?) (if (and (symbol? v1) (symbol? v2)) (val->ast-const (eq? v1 v2)) #f))
           (else #f))))
      (else #f))))

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
                        (if (or (and (char>=? ch #\0) (char<=? ch #\9)) (char=? ch #\_) (char=? ch #\*))
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
  (let ((nt-table-cell (cons (map (lambda (nt)
                                    (cons (car nt) (cons (cadr nt) (caddr nt))))
                                  parent-nts)
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
                                       (set-car! removed-heads-cell (cons (car c) (car removed-heads-cell))))))
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
          (car removed-heads-cell))))

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
             ((eq? head '%program)
              (and (eq? (car expr) '%program)
                   (pair? (cdr expr))
                   (pair? (cddr expr))))
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
        (reverse acc)
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
  (let loop ((c1 l1) (c2 l2) (acc '()))
    (if (or (null? c1) (null? c2))
        (reverse acc)
        (let ((o (car c1))
              (n (car c2)))
          (loop (cdr c1) (cdr c2)
                (cons (if (equal? o n) o (nanopass-ast-diff o n)) acc))))))

(define (nanopass-ast-diff old-ir new-ir)
  (cond
    ((equal? old-ir new-ir)
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
  (let ((max-depth 8)
        (max-len 16))
    (nanopass-display-esc)
    (display "[36m--- [PASS: ")
    (display pass-name)
    (display "] -----------------------------------------------------")
    (nanopass-display-esc)
    (display "[0m\n")
    (if (equal? old-ir new-ir)
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
  (error "Nanopass Language Invariant Violation" (list pass-name lang-name)))

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

;;; Catamorphism Automatic Traversal Code Synthesizer
;;; Automatically traverses non-matching AST nodes recursively.
;;; Supports both AST transformation (with inherited attributes) and pure analyzer passes (lang-out = '*).
(define (nanopass-catamorphism-step lang-in lang-out nt-name ir recurse-fn extra-args extra-out)
  (let ((extra-args (if (pair? extra-args) extra-args '()))
        (extra-out (if (pair? extra-out) extra-out '())))
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
                      (elements (if (symbol? (car ir)) (cdr ir) ir)))
                 (let loop ((cur elements) (acc initial-acc))
                   (cond
                     ((null? cur) acc)
                     ((not (pair? cur))
                      (nanopass-apply-list recurse-fn (cons cur (append prefix (list acc)))))
                     (else
                      (let* ((item (car cur))
                             (new-acc (nanopass-apply-list recurse-fn (cons item (append prefix (list acc))))))
                        (loop (cdr cur) new-acc))))))
               #f)))
        ;; Transform mode: reconstruct AST while propagating extra inherited attributes
        (let ((call-recurse
               (lambda (node)
                 (if (null? extra-args)
                     (recurse-fn node)
                     (nanopass-apply-list recurse-fn (cons node extra-args))))))
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
                      (list 'if (call-recurse (cadr ir)) (call-recurse (caddr ir)))
                      (list 'if (call-recurse (cadr ir)) (call-recurse (caddr ir)) (call-recurse (cadddr ir)))))
                 ((begin)
                  (cons 'begin (map call-recurse (cdr ir))))
                 ((lambda)
                  ;; Later passes expect a single-expression lambda body.
                  (list 'lambda (cadr ir)
                        (cond ((null? (cddr ir)) (list 'begin))
                              ((null? (cdddr ir)) (call-recurse (caddr ir)))
                              (else (cons 'begin (map call-recurse (cddr ir)))))))
                 ((let)
                  (if (symbol? (cadr ir))
                      (list 'let (cadr ir)
                            (map (lambda (b) (list (car b) (call-recurse (cadr b)))) (caddr ir))
                            (if (null? (cddddr ir))
                                (call-recurse (cadddr ir))
                                (cons 'begin (map call-recurse (cdddr ir)))))
                      (list 'let
                            (map (lambda (b) (list (car b) (call-recurse (cadr b)))) (cadr ir))
                            (if (null? (cdddr ir))
                                (call-recurse (caddr ir))
                                (cons 'begin (map call-recurse (cddr ir)))))))
                 ((letrec)
                  (list 'letrec
                        (map (lambda (b) (list (car b) (call-recurse (cadr b)))) (cadr ir))
                        (if (null? (cdddr ir))
                            (call-recurse (caddr ir))
                            (cons 'begin (map call-recurse (cddr ir))))))
                 ((set!)
                  (list 'set! (cadr ir) (call-recurse (caddr ir))))
                 ((%program)
                  (list '%program
                        (map (lambda (d)
                               (if (and (pair? d) (eq? (car d) 'define))
                                   (list 'define (cadr d) (call-recurse (caddr d)))
                                   (call-recurse d)))
                             (cadr ir))
                        (call-recurse (caddr ir))))
                 (else
                  ;; General function application or compound form
                  (let loop ((cur (cdr ir)) (acc (list (call-recurse op))))
                    (cond
                      ((null? cur) (reverse acc))
                      ((not (pair? cur)) (append (reverse acc) (call-recurse cur)))
                      (else
                       (loop (cdr cur) (cons (call-recurse (car cur)) acc))))))))))))))
;;; =======================================================================
;;; ULisp Compiler: Nanopass Framework Core DSL (define-language / define-pass)
;;; Conforms to DSN-33 Architecture Specification & Keep & Dybvig (2013)
;;; =======================================================================

;;; Helper to parse header of define-pass
;;; (define-pass pass-name : L_in (ir extra_in ...) -> L_out (extra_out ...) body ...)
;;; or (define-pass pass-name : L_in (ir extra_in ...) -> * (extra_out ...) body ...)
;;; or (define-pass pass-name (ir extra_in ...) body ...)
(define (nanopass-parse-pass-header form)
  (let ((name (cadr form))
        (rest (cddr form)))
    (if (and (pair? rest) (eq? (car rest) ':))
        (let* ((l-in (cadr rest))
               (in-args (caddr rest))
               (in-arg-list (if (pair? in-args) in-args (list in-args)))
               (after-arrow (cddddr rest))
               (l-out (car after-arrow))
               (has-extra-out? (and (pair? (cdr after-arrow)) (list? (cadr after-arrow))))
               (extra-out (if has-extra-out? (cadr after-arrow) '()))
               (clauses (if has-extra-out? (cddr after-arrow) (cdr after-arrow))))
          (list name l-in in-arg-list l-out extra-out clauses))
        (let* ((in-args (car rest))
               (in-arg-list (if (pair? in-args) in-args (list in-args)))
               (clauses (cdr rest)))
          (list name 'L_src in-arg-list 'L_core '() clauses)))))

;;; Expand a single rule in a nonterminal transformer
(define (nanopass-expand-rule rule nt-name)
  (let* ((pat (car rule))
         (rest (cdr rule))
         (has-guard? (and (pair? rest)
                          (pair? (car rest))
                          (eq? (car (car rest)) 'guard)))
         (guard-expr (if has-guard? (cadr (car rest)) #t))
         (raw-body (if has-guard?
                       (if (null? (cddr rest)) (cadr rest) (cons 'begin (cdr rest)))
                       (if (null? (cdr rest)) (car rest) (cons 'begin rest))))
         (vars (nanopass-extract-pattern-vars pat))
         (body-expr (nanopass-expand-template raw-body vars)))
    (list pat vars guard-expr body-expr)))

;;; Build cascaded if-expression for nonterminal transformer rules
(define (nanopass-build-rules-cascade rules l-in l-out nt-name in-arg-list extra-out)
  (let* ((ir-var (car in-arg-list))
         (extra-in (cdr in-arg-list)))
    (let loop ((rs rules))
      (if (null? rs)
          (if (null? extra-in)
              (list 'nanopass-catamorphism-step
                    (list 'quote l-in)
                    (list 'quote l-out)
                    (list 'quote nt-name)
                    ir-var
                    nt-name
                    ''()
                    (list 'quote extra-out))
              (list 'nanopass-catamorphism-step
                    (list 'quote l-in)
                    (list 'quote l-out)
                    (list 'quote nt-name)
                    ir-var
                    nt-name
                    (cons 'list extra-in)
                    (list 'quote extra-out)))
          (let* ((r (car rs))
                 (pat (car r))
                 (vars (cadr r))
                 (guard-expr (caddr r))
                 (body-expr (cadddr r))
                 (c-var (unique-symbol "__c_")))
            (list 'let (list (list c-var
                                   (list 'nanopass-try-clause
                                         (list 'quote pat)
                                         (list 'quote vars)
                                         ir-var
                                         nt-name
                                         (list 'lambda vars
                                               (list 'if guard-expr
                                                     (list 'cons #t body-expr)
                                                     #f)))))
                  (list 'if c-var
                        (list 'cdr c-var)
                        (loop (cdr rs)))))))))

;;; Normalize rules whether passed as list of rules or single wrapped list
(define (nanopass-normalize-rules raw-rules)
  (if (and (= (length raw-rules) 1)
           (pair? (car raw-rules))
           (> (length (car raw-rules)) 1)
           (pair? (caar raw-rules))
           (pair? (cadar raw-rules))
           (pair? (cddar raw-rules)))
      (car raw-rules)
      raw-rules))

;;; Parse a nonterminal clause in define-pass
(define (nanopass-parse-nt-clause clause)
  (let ((nt-name (car clause))
        (rest (cdr clause)))
    (if (and (pair? rest) (eq? (car rest) ':))
        ;; (NT : NT_in (ir extra1 ...) -> NT_out (extra_out ...) rules ...)
        ;; or (NT : NT_in (ir extra1 ...) -> * (extra_out ...) rules ...)
        (let* ((nt-in (cadr rest))
               (in-args (caddr rest))
               (in-arg-list (if (pair? in-args) in-args (list in-args)))
               (after-arrow (cddddr rest))
               (nt-out (car after-arrow))
               (has-extra-out? (and (pair? (cdr after-arrow)) (list? (cadr after-arrow))))
               (extra-out (if has-extra-out? (cadr after-arrow) '()))
               (raw-rules (if has-extra-out? (cddr after-arrow) (cdr after-arrow)))
               (rules (nanopass-normalize-rules raw-rules)))
          (list nt-name in-arg-list nt-out extra-out rules))
        ;; Shorthand: (NT (ir extra1 ...) rules ...)
        (let* ((in-args (car rest))
               (in-arg-list (if (pair? in-args) in-args (list in-args)))
               (rules (nanopass-normalize-rules (cdr rest))))
          (list nt-name in-arg-list nt-name '() rules)))))

;;; Expand define-pass AST
(define (nanopass-expand-define-pass-with-trace form force-trace?)
  (let* ((parsed (nanopass-parse-pass-header form))
         (name (car parsed))
         (l-in (cadr parsed))
         (in-arg-list (caddr parsed))
         (l-out (cadddr parsed))
         (extra-out (car (cddddr parsed)))
         (clauses (cadr (cddddr parsed))))
    (let loop ((rest clauses)
               (defs '())
               (nt-procs '())
               (entry-nt #f))
      (if (null? rest)
          (let* ((final-entry (if entry-nt entry-nt 'Expr))
                 (ir-var (car in-arg-list))
                 (res-var (unique-symbol "__res_"))
                 (body-call (cons final-entry in-arg-list)))
            (list 'define (cons name in-arg-list)
                  (list 'letrec
                        (append (reverse defs) (reverse nt-procs))
                        (list 'begin
                              (list 'set-current-pass! (list 'quote name))
                              (list 'if (list 'nanopass-verifier-enabled?)
                                    (list 'nanopass-verify-ast (list 'quote name) (list 'quote l-in) ir-var ''entry)
                                    #f)
                              (list 'with-call-frame (list 'quote name) ir-var
                                    (list 'lambda '()
                                          (list 'let (list (list res-var body-call))
                                                (list 'if (list 'nanopass-verifier-enabled?)
                                                      (list 'nanopass-verify-ast (list 'quote name) (list 'quote l-out) res-var ''exit)
                                                      #f)
                                                (if force-trace?
                                                    (list 'begin
                                                          (list 'nanopass-display-ast-diff (list 'quote name) ir-var res-var)
                                                          res-var)
                                                    (list 'begin
                                                          (list 'if (list 'nanopass-trace-enabled?)
                                                                (list 'nanopass-display-ast-diff (list 'quote name) ir-var res-var)
                                                                #f)
                                                          res-var)))))))))
          (let ((c (car rest)))
            (cond
              ;; (definitions def1 def2 ...)
              ((and (pair? c) (eq? (car c) 'definitions))
               (let ((norm-defs
                      (map (lambda (d)
                             (if (and (pair? d) (eq? (car d) 'define))
                                 (let ((spec (cadr d)))
                                   (if (pair? spec)
                                       (list (car spec) (cons 'lambda (cons (cdr spec) (cddr d))))
                                       (list spec (caddr d))))
                                 d))
                           (cdr c))))
                 (loop (cdr rest) (append (reverse norm-defs) defs) nt-procs entry-nt)))
              ;; (entry EntryNT)
              ((and (pair? c) (eq? (car c) 'entry))
               (loop (cdr rest) defs nt-procs (cadr c)))
              ;; (NT : NT_in (ir extra ...) -> NT_out (extra_out ...) rules ...)
              ;; or (NT (ir extra ...) rules ...)
              ((and (pair? c) (symbol? (car c)))
               (let* ((parsed-nt (nanopass-parse-nt-clause c))
                      (nt-name (car parsed-nt))
                      (nt-in-args (cadr parsed-nt))
                      (nt-out (caddr parsed-nt))
                      (nt-extra-out (cadddr parsed-nt))
                      (raw-rules (car (cddddr parsed-nt)))
                      (expanded-rules (map (lambda (r) (nanopass-expand-rule r nt-name)) raw-rules))
                      (body-expr (nanopass-build-rules-cascade expanded-rules l-in nt-out nt-name nt-in-args (if (pair? nt-extra-out) nt-extra-out extra-out)))
                      (proc-binding (list nt-name (list 'lambda nt-in-args body-expr))))
                 (loop (cdr rest)
                       defs
                       (cons proc-binding nt-procs)
                       (if entry-nt entry-nt nt-name))))
              (else
               (loop (cdr rest) defs nt-procs entry-nt))))))))

(define (nanopass-expand-define-pass form)
  (nanopass-expand-define-pass-with-trace form #f))

(define (nanopass-expand-trace-define-pass form)
  (let ((pass-form (cons 'define-pass (cdr form))))
    (nanopass-expand-define-pass-with-trace pass-form #t)))

;;; Expand define-language AST
(define (nanopass-expand-define-language form)
  (let* ((name (cadr form))
         (clauses (cddr form)))
    (list 'begin
          (list 'define (string->symbol (string-append "__lang_" (symbol->string name)))
                (list 'nanopass-register-language!
                      (list 'nanopass-parse-language-spec
                            (list 'quote name)
                            (list 'quote clauses))))
          (list 'define (string->symbol (string-append "parse-" (symbol->string name)))
                (list 'lambda (list 'expr)
                      (list 'nanopass-parse (list 'quote name) 'expr)))
          (list 'define (string->symbol (string-append "unparse-" (symbol->string name)))
                (list 'lambda (list 'ir)
                      (list 'nanopass-unparse (list 'quote name) 'ir)))
          (list 'define (string->symbol (string-append (symbol->string name) "?"))
                (list 'lambda (list 'expr)
                      (list 'nanopass-ast-valid? (list 'quote name) 'expr))))))

;;; Expand define-parser AST
(define (nanopass-expand-define-parser form)
  (let ((proc-name (cadr form))
        (lang-name (caddr form)))
    (list 'define (list proc-name 'expr)
          (list 'nanopass-parse (list 'quote lang-name) 'expr))))

;;; Expand define-unparser AST
(define (nanopass-expand-define-unparser form)
  (let ((proc-name (cadr form))
        (lang-name (caddr form)))
    (list 'define (list proc-name 'ir)
          (list 'nanopass-unparse (list 'quote lang-name) 'ir))))

;;; -----------------------------------------------------------------------
;;; Host / Interpreter Macros (for ilisp and interactive environments)
;;; -----------------------------------------------------------------------
(define-macro (define-language . args)
  (nanopass-expand-define-language (cons 'define-language args)))

(define-macro (define-pass . args)
  (nanopass-expand-define-pass (cons 'define-pass args)))

(define-macro (trace-define-pass . args)
  (nanopass-expand-trace-define-pass (cons 'trace-define-pass args)))

(define-macro (define-parser . args)
  (nanopass-expand-define-parser (cons 'define-parser args)))

(define-macro (define-unparser . args)
  (nanopass-expand-define-unparser (cons 'define-unparser args)))

(define-macro (in-context . args)
  (if (= (length args) 2)
      (list (car args) (cadr args))
      (list 'nanopass-parse-nt (list 'quote (car args)) (caddr args) (list 'quote (cadr args)))))

(define-macro (nanopass-template . args)
  (nanopass-expand-template (car args) '()))

;;; -----------------------------------------------------------------------
;;; Canonical Compiler Pipeline Languages: L_src and L_core
;;; -----------------------------------------------------------------------

;;; L_src: Source intermediate language containing full high-level syntactic sugar
(define-language L_src
  (terminals
    (symbol (x))
    (constant (c)))
  (Expr (e)
    x
    c
    (quote datum)
    (if e1 e2 e3)
    (if e1 e2)
    (begin e ...)
    (lambda (x ...) e ...)
    (set! x e)
    (let ((x e1) ...) e ...)
    (letrec ((x e1) ...) e ...)
    (let* ((x e1) ...) e ...)
    (do ((x e1 e2) ...) (e_test e_res ...) e_cmd ...)
    (cond (e1 e2) ... (else e_else))
    (case key (dat e ...) ... (else e_else))
    (and e ...)
    (or e ...)
    (list e ...)
    (vector e ...)
    (bytevector e ...)
    (vector-append e ...)
    (bytevector-append e ...)
    (string-append e ...)
    (guard (x c ...) e ...)
    (let-values (((x ...) e1) ...) e ...)
    (let*-values (((x ...) e1) ...) e ...)
    (parameterize ((x e1) ...) e ...)
    (%program defs main)
    (e0 e1 ...)))

;;; L_core: Core intermediate language where all syntactic sugar has been removed
(define-language L_core
  (extends L_src)
  (Expr (e)
    (- (cond (e1 e2) ... (else e_else)))
    (- (case key (dat e ...) ... (else e_else)))
    (- (let* ((x e1) ...) e ...))
    (- (do ((x e1 e2) ...) (e_test e_res ...) e_cmd ...))
    (- (and e ...))
    (- (or e ...))
    (- (list e ...))
    (- (vector e ...))
    (- (bytevector e ...))
    (- (vector-append e ...))
    (- (bytevector-append e ...))
    (- (string-append e ...))
    (- (guard (x c ...) e ...))
    (- (let-values (((x ...) e1) ...) e ...))
    (- (let*-values (((x ...) e1) ...) e ...))
    (- (parameterize ((x e1) ...) e ...))))
;;; =======================================================================
;;; ULisp Compiler: Lightweight IR Verifier & Invariant Pass Checker
;;; Conforms to DSN-33 Architecture Specification & Issue #576
;;; =======================================================================

;;; Verifier Configuration (represented as cons cells to avoid top-level set! in LIR)
;;; Levels: 0 = OFF, 1 = BOUNDARY (LIR only), 2 = STANDARD (all passes), 3 = STRICT/PARANOID
(define *verifier-level* (cons 0 '()))
(define *verifier-enabled* (cons #f '()))
(define *verifier-strict* (cons #f '()))

(define (verifier-level) (car *verifier-level*))
(define (set-verifier-level! lvl)
  (set-car! *verifier-level* lvl)
  (if (> lvl 0)
      (begin
        (set-car! *verifier-enabled* #t)
        (enable-nanopass-verifier!))
      (begin
        (set-car! *verifier-enabled* #f)
        (disable-nanopass-verifier!))))

(define (verifier-enabled?) (> (car *verifier-level*) 0))
(define (enable-verifier!)
  (set-verifier-level! 2))
(define (disable-verifier!)
  (set-verifier-level! 0))
(define (verifier-strict?) (car *verifier-strict*))
(define (set-verifier-strict! flag) (set-car! *verifier-strict* flag))

;;; Dynamic Verifier Context Tracking
(define *verifier-context-stack* (cons '() '()))

(define (current-verifier-context)
  (if (null? (car *verifier-context-stack*))
      '()
      (caar *verifier-context-stack*)))

(define (verifier-push-context! ctx)
  (set-car! *verifier-context-stack* (cons ctx (car *verifier-context-stack*))))

(define (verifier-pop-context!)
  (if (pair? (car *verifier-context-stack*))
      (set-car! *verifier-context-stack* (cdar *verifier-context-stack*))))

(define (with-verifier-context ctx thunk)
  (verifier-push-context! ctx)
  (let ((res (thunk)))
    (verifier-pop-context!)
    res))

;;; Error Reporting Procedure with Contextual Information
;;; NOTE: Fixed arity only. The self-hosted compiler (Pass 060 LVN) does not
;;; support dotted/variadic parameter lists in compiler sources.
(define (verifier-error phase message expr)
  (let* ((ctx (current-verifier-context))
         (fn-entry (and (pair? ctx) (assq 'function ctx)))
         (fn-name (and fn-entry (cdr fn-entry)))
         (blk-entry (and (pair? ctx) (assq 'block ctx)))
         (blk-name (and blk-entry (cdr blk-entry))))
    (display "\n*** [VERIFIER ERROR] Phase: ")
    (display phase)
    (if fn-name
        (begin (display " | Function: ") (display fn-name)))
    (if blk-name
        (begin (display " | Block: ") (display blk-name)))
    (display " - ")
    (display message)
    (display "\n    Expression: ")
    (write expr)
    (newline)
    (if (car *verifier-strict*)
        (error "IR Verifier Invariant Violation" expr)
        #f)))

;;; -----------------------------------------------------------------------
;;; 1. Pass 030 Desugar Output Verifier
;;; -----------------------------------------------------------------------
;;; Invariant: No remaining macro/syntactic sugar keywords:
;;;   cond, case, and, or, let*, named-let, let-values, let*-values,
;;;   guard, parameterize, do, when, unless, define-values

(define *prohibited-desugared-keywords*
  '(cond case and or let* let-values let*-values guard parameterize do when unless define-values))

(define (verify-desugared-ast ast)
  (let loop ((expr ast))
    (cond
      ((not (pair? expr)) #t)
      ((eq? (car expr) 'quote) #t)
      ((memq (car expr) *prohibited-desugared-keywords*)
       (verifier-error 'desugar "Prohibited macro/sugar keyword remaining after desugaring" expr))
      ;; Check for named let: (let <name> ((v e) ...) body)
      ((and (eq? (car expr) 'let)
            (pair? (cdr expr))
            (symbol? (cadr expr)))
       (verifier-error 'desugar "Named-let remaining after desugaring" expr))
      (else
       (let rec ((children (cdr expr)))
         (if (null? children)
             #t
             (and (loop (car children))
                  (rec (cdr children)))))))))

;;; -----------------------------------------------------------------------
;;; 2. Pass 070 ANF Output Verifier
;;; -----------------------------------------------------------------------
;;; Invariant: In all applications, call arguments and primitive operands
;;; must be atomic (symbols or constants), no nested compound expressions.

(define *anf-special-forms*
  '(quote if begin let letrec lambda set! define %program %values %call-with-values %raw-call/cc))

(define (verify-anf-ast ast)
  (if (and (assq 'L_anf (nanopass-get-languages))
           (not (nanopass-ast-valid? 'L_anf ast)))
      (verifier-error 'anf "AST violates L_anf schema invariants" ast)
      (let loop ((expr ast))
        (cond
          ((not (pair? expr)) #t)
          ((eq? (car expr) 'quote) #t)
          ((eq? (car expr) 'if)
           (let ((test (cadr expr))
                 (then (caddr expr))
                 (else-e (if (null? (cdddr expr)) '() (cadddr expr))))
             (if (not (atomic-expr? test))
                 (verifier-error 'anf "If-condition is not atomic in ANF" expr)
                 (and (loop then)
                      (if (null? else-e) #t (loop else-e))))))
          ((eq? (car expr) 'let)
           (let ((bindings (cadr expr))
                 (body (caddr expr)))
             (and (let b-loop ((bs bindings))
                    (if (null? bs)
                        #t
                        (and (loop (cadar bs))
                             (b-loop (cdr bs)))))
                  (loop body))))
          ((eq? (car expr) 'lambda)
           (let ((body (caddr expr)))
             (loop body)))
          ((eq? (car expr) 'begin)
           (let b-loop ((es (cdr expr)))
             (if (null? es)
                 #t
                 (and (loop (car es))
                      (b-loop (cdr es))))))
          ((eq? (car expr) '%program)
           (let ((defs (cadr expr))
                 (main (caddr expr)))
             (and (let d-loop ((ds defs))
                    (if (null? ds)
                        #t
                        (and (loop (car ds))
                             (d-loop (cdr ds)))))
                  (loop main))))
          ((memq (car expr) '(define set!))
           (loop (caddr expr)))
          ((eq? (car expr) '%call-with-values)
           (and (loop (cadr expr))
                (loop (caddr expr))))
          ((eq? (car expr) '%values)
           (let a-loop ((args (cdr expr)))
             (if (null? args)
                 #t
                 (if (not (atomic-expr? (car args)))
                     (verifier-error 'anf "%values operand is not atomic in ANF" (car args))
                     (a-loop (cdr args))))))
          ;; General application: (f a1 a2 ...)
          (else
           (let ((op (car expr))
                 (args (cdr expr)))
             (if (and (not (symbol? op)) (not (atomic-expr? op)))
                 (verifier-error 'anf "Application operator is not atomic in ANF" expr)
                 (let a-loop ((as args))
                   (if (null? as)
                       #t
                       (if (not (atomic-expr? (car as)))
                           (verifier-error 'anf "Application argument is not atomic in ANF" (car as))
                           (a-loop (cdr as))))))))))))

;;; -----------------------------------------------------------------------
;;; 3. Pass 110 Closure Convert Output Verifier
;;; -----------------------------------------------------------------------
;;; Invariant: Top-level program contains %program, closures are represented
;;; with %make-closure or lifted labels. No unlifted lambda abstractions.

(define (verify-closure-ast ast)
  (if (and (assq 'L_lifted (nanopass-get-languages))
           (not (nanopass-ast-valid? 'L_lifted ast)))
      (verifier-error 'closure "AST violates L_lifted schema invariants (unlifted lambda or malformed structure)" ast)
      (let loop ((expr ast))
        (cond
          ((not (pair? expr)) #t)
          ((eq? (car expr) 'quote) #t)
          ((eq? (car expr) 'lambda)
           (verifier-error 'closure "Unlifted lambda remaining after closure conversion" expr))
          ((or (eq? (car expr) '%make-closure)
               (eq? (car expr) '%make-closure-env))
           ;; Format: (%make-closure label free-vars ...) or (%make-closure-env label free-vars ...)
           (let ((label (cadr expr)))
             (if (not (symbol? label))
                 (verifier-error 'closure "%make-closure / %make-closure-env label must be a symbol" expr)
                 (let v-loop ((vars (cddr expr)))
                   (if (null? vars)
                       #t
                       (if (not (atomic-expr? (car vars)))
                           (verifier-error 'closure "%make-closure / %make-closure-env environment variable must be atomic" (car vars))
                           (v-loop (cdr vars))))))))
          (else
           (let rec ((children (cdr expr)))
             (if (null? children)
                 #t
                 (and (loop (car children))
                      (rec (cdr children))))))))))

;;; -----------------------------------------------------------------------
;;; 4. Pass 131 Safepoint / Stackmap Verifier
;;; -----------------------------------------------------------------------
;;; Invariant: Stackmaps list exists, each entry is (label frame-size bitmap),
;;; frame-size is 8-byte aligned positive integer, bitmap is non-negative int.

(define (verify-lir-safepoint lir)
  (if (not (and (pair? lir) (eq? (car lir) '%lir-program)))
      (verifier-error 'safepoint "LIR root tag must be %lir-program" lir)
      (let ((stackmaps-clause (assq 'stackmaps (cddr lir))))
        (if (not stackmaps-clause)
            (verifier-error 'safepoint "Missing stackmaps clause in %lir-program" lir)
            (let ((sms (cadr stackmaps-clause)))
              (let loop ((entries sms))
                (if (null? entries)
                    #t
                    (let ((entry (car entries)))
                      (cond
                        ((not (and (pair? entry) (= (length entry) 3)))
                         (verifier-error 'safepoint "Safepoint entry must be a 3-element tuple (label frame-size bitmap)" entry))
                        ((not (or (symbol? (car entry)) (string? (car entry))))
                         (verifier-error 'safepoint "Safepoint label must be symbol or string" entry))
                        ((not (and (integer? (cadr entry)) (> (cadr entry) 0) (= (modulo (cadr entry) 8) 0)))
                         (verifier-error 'safepoint "Safepoint frame-size must be positive 8-byte aligned integer" entry))
                        ((not (and (integer? (caddr entry)) (>= (caddr entry) 0)))
                         (verifier-error 'safepoint "Safepoint bitmap must be non-negative integer" entry))
                        (else
                         (loop (cdr entries))))))))))))

;;; -----------------------------------------------------------------------
;;; 5. Pass 132 Braun SSA / Block Arguments Verifier
;;; -----------------------------------------------------------------------
;;; Invariant: CFG blocks format (%block label (params ...) insts ...),
;;; jump and cjump instructions have consistent block arguments.

(define (verify-ssa-ast lir)
  (let loop ((node lir))
    (cond
      ((not (pair? node)) #t)
      ((eq? (car node) '%block)
       (let ((label (cadr node))
             (params (caddr node)))
         (cond
           ((not (symbol? label))
            (verifier-error 'ssa "%block label must be a symbol" node))
           ((not (list? params))
            (verifier-error 'ssa "%block parameters must be a list" node))
           (else
            (let p-loop ((ps params))
              (if (null? ps)
                  (let i-loop ((insts (cdddr node)))
                    (if (null? insts)
                        #t
                        (and (loop (car insts))
                             (i-loop (cdr insts)))))
                  (if (not (symbol? (car ps)))
                      (verifier-error 'ssa "%block parameter must be a symbol" (car ps))
                      (p-loop (cdr ps)))))))))
      ((eq? (car node) '%jump)
       (let ((target (cadr node))
             (args (cddr node)))
         (if (not (symbol? target))
             (verifier-error 'ssa "%jump target must be a label symbol" node)
             (let a-loop ((as args))
               (if (null? as)
                   #t
                   (if (not (atomic-expr? (car as)))
                       (verifier-error 'ssa "%jump argument must be atomic" (car as))
                       (a-loop (cdr as))))))))
      (else
       (let rec ((children (cdr node)))
         (if (null? children)
             #t
             (and (loop (car children))
                  (rec (cdr children)))))))))

;;; -----------------------------------------------------------------------
;;; Unified Verifier Dispatcher
;;; -----------------------------------------------------------------------
(define (verify-pass-output phase data)
  (let ((lvl (verifier-level)))
    (if (<= lvl 0)
        #t
        (case phase
          ((desugar 030)
           (if (>= lvl 2) (verify-desugared-ast data) #t))
          ((anf 070)
           (if (>= lvl 2) (verify-anf-ast data) #t))
          ((closure 110)
           (if (>= lvl 2) (verify-closure-ast data) #t))
          ((safepoint 131)
           (if (>= lvl 2) (verify-lir-safepoint data) #t))
          ((ssa 132)
           (if (>= lvl 2) (verify-ssa-ast data) #t))
          ((lir canonical-lir 130)
           ;; Level 1 (Boundary) or higher performs full LIR validation
           (validate-lir data))
          (else #t)))))

(define (nanopass-verify-pass-data pass-name lang-name data phase)
  (and (if (>= (verifier-level) 3)
           (nanopass-verify-ast pass-name lang-name data phase)
           #t)
       (verify-pass-output pass-name data)))
;;; =======================================================================
;;; ULisp Compiler: Unified Pass Manager & Optimization Pipeline Scheduler
;;; Conforms to DSN-33 Architecture Specification & Issue #598
;;; =======================================================================

;;; -----------------------------------------------------------------------
;;; 1. Pass Descriptor Record & Accessors
;;; -----------------------------------------------------------------------
;;; Each pass is represented as a structured 10-element tuple:
;;;   (list 'pass-descriptor id name category opt-level pass-fn verifier-phase in-lang out-lang prerequisites mandatory?)

(define (make-pass-descriptor id name category opt-level pass-fn verifier-phase in-lang out-lang prerequisites mandatory?)
  (list 'pass-descriptor id name category opt-level pass-fn verifier-phase in-lang out-lang prerequisites mandatory?))

(define (pass-descriptor? obj)
  (and (pair? obj) (eq? (car obj) 'pass-descriptor)))

(define (pass-id p) (cadr p))
(define (pass-name p) (caddr p))
(define (pass-category p) (cadddr p))
(define (pass-opt-level p) (car (cddddr p)))
(define (pass-fn p) (cadr (cddddr p)))
(define (pass-verifier-phase p) (caddr (cddddr p)))
(define (pass-in-lang p) (cadddr (cddddr p)))
(define (pass-out-lang p) (car (cddddr (cddddr p))))
(define (pass-prerequisites p) (cadr (cddddr (cddddr p))))
(define (pass-mandatory? p) (caddr (cddddr (cddddr p))))

;;; -----------------------------------------------------------------------
;;; 2. Global Pass Registry
;;; -----------------------------------------------------------------------

(define *pass-registry* (cons '() '()))

(define (pass-registry)
  (car *pass-registry*))

(define (reset-pass-registry!)
  (set-car! *pass-registry* '()))

(define (register-pass! descriptor)
  (let* ((id (pass-id descriptor))
         (current (car *pass-registry*))
         (filtered (let loop ((ps current))
                     (cond
                       ((null? ps) '())
                       ((eq? (pass-id (car ps)) id) (loop (cdr ps)))
                       (else (cons (car ps) (loop (cdr ps))))))))
    (set-car! *pass-registry* (append filtered (list descriptor)))
    id))

(define (lookup-pass id)
  (let loop ((ps (car *pass-registry*)))
    (cond
      ((null? ps)
       (error "lookup-pass: unknown compiler pass" id))
      ((eq? (pass-id (car ps)) id)
       (car ps))
      (else
       (loop (cdr ps))))))

(define (pass-registered? id)
  (let loop ((ps (car *pass-registry*)))
    (cond
      ((null? ps) #f)
      ((eq? (pass-id (car ps)) id) #t)
      (else (loop (cdr ps))))))

;;; -----------------------------------------------------------------------
;;; 3. Pipeline Configuration & Tuning Options
;;; -----------------------------------------------------------------------

(define *pipeline-opt-level* (cons 2 '()))
(define (pipeline-opt-level) (car *pipeline-opt-level*))
(define (set-pipeline-opt-level! lvl) (set-car! *pipeline-opt-level* lvl))

(define *pipeline-time-passes* (cons #f '()))
(define (pipeline-time-passes?) (car *pipeline-time-passes*))
(define (enable-pipeline-time-passes!) (set-car! *pipeline-time-passes* #t))
(define (disable-pipeline-time-passes!) (set-car! *pipeline-time-passes* #f))

(define *pipeline-dump-ir* (cons #f '()))
(define (pipeline-dump-ir) (car *pipeline-dump-ir*))
(define (set-pipeline-dump-ir! target) (set-car! *pipeline-dump-ir* target))

(define *pipeline-print-after-all* (cons #f '()))
(define (pipeline-print-after-all?) (car *pipeline-print-after-all*))
(define (enable-pipeline-print-after-all!) (set-car! *pipeline-print-after-all* #t))
(define (disable-pipeline-print-after-all!) (set-car! *pipeline-print-after-all* #f))

(define *pipeline-disabled-passes* (cons '() '()))
(define (pipeline-disabled-passes) (car *pipeline-disabled-passes*))

(define (disable-pass! id)
  (if (not (memq id (car *pipeline-disabled-passes*)))
      (set-car! *pipeline-disabled-passes* (cons id (car *pipeline-disabled-passes*)))))

(define (enable-pass! id)
  (set-car! *pipeline-disabled-passes*
            (let loop ((ps (car *pipeline-disabled-passes*)))
              (cond
                ((null? ps) '())
                ((eq? (car ps) id) (loop (cdr ps)))
                (else (cons (car ps) (loop (cdr ps))))))))

(define (reset-pipeline-options!)
  (set-car! *pipeline-opt-level* 2)
  (set-car! *pipeline-time-passes* #f)
  (set-car! *pipeline-dump-ir* #f)
  (set-car! *pipeline-print-after-all* #f)
  (set-car! *pipeline-disabled-passes* '()))

;;; -----------------------------------------------------------------------
;;; 4. Dynamic Pipeline Scheduling & Invariant Validation
;;; -----------------------------------------------------------------------

(define (pass-enabled? desc opt-level disabled-list)
  (let ((id (pass-id desc))
        (pass-opt (pass-opt-level desc))
        (mandatory (pass-mandatory? desc)))
    (if mandatory
        (not (memq id disabled-list))
        (and (<= pass-opt opt-level)
             (not (memq id disabled-list))))))

(define (build-pipeline opt-level disabled-list)
  (let ((all (car *pass-registry*)))
    (let loop ((ps all) (res '()))
      (if (null? ps)
          (reverse res)
          (let ((p (car ps)))
            (if (pass-enabled? p opt-level disabled-list)
                (loop (cdr ps) (cons p res))
                (loop (cdr ps) res)))))))

(define (validate-pipeline-prerequisites pass-list)
  (let loop ((ps pass-list) (seen '()))
    (if (null? ps)
        #t
        (let* ((p (car ps))
               (id (pass-id p))
               (prereqs (pass-prerequisites p)))
          (let check-prereqs ((reqs prereqs))
            (if (null? reqs)
                (loop (cdr ps) (cons id seen))
                (let ((req (car reqs)))
                  (if (not (memq req seen))
                      (error "validate-pipeline-prerequisites: missing required prerequisite pass"
                             (list 'pass id 'requires req))
                      (check-prereqs (cdr reqs))))))))))

;;; -----------------------------------------------------------------------
;;; 5. Pass Timing & Profiling Statistics
;;; -----------------------------------------------------------------------

(define *pass-manager-ticks* (cons 0 '()))
(define (current-time-monotonic-ms)
  (set-car! *pass-manager-ticks* (+ (car *pass-manager-ticks*) 1))
  (car *pass-manager-ticks*))

(define *pass-timings* (cons '() '()))

(define (reset-pass-timings!)
  (set-car! *pass-timings* '()))

(define (record-pass-timing! pass-id elapsed-ms)
  (set-car! *pass-timings*
            (append (car *pass-timings*) (list (cons pass-id elapsed-ms)))))

(define (get-pass-timings)
  (car *pass-timings*))

(define (print-pass-timing-report)
  (display "\n======================================================================\n")
  (display "Pass Execution Profiling Report (--time-passes)\n")
  (display "======================================================================\n")
  (let* ((timings (car *pass-timings*))
         (total (let loop ((ts timings) (acc 0))
                  (if (null? ts)
                      acc
                      (loop (cdr ts) (+ acc (cdar ts)))))))
    (let loop ((ts timings))
      (if (pair? ts)
          (let* ((entry (car ts))
                 (pid (car entry))
                 (ms (cdr entry))
                 (pct (if (> total 0) (quotient (* ms 100) total) 0)))
            (display "  ")
            (display pid)
            (display " : ")
            (display ms)
            (display " ticks (")
            (display pct)
            (display "%)\n")
            (loop (cdr ts)))))
    (display "----------------------------------------------------------------------\n")
    (display "  Total passes time : ")
    (display total)
    (display " ticks\n")
    (display "======================================================================\n\n")))

;;; -----------------------------------------------------------------------
;;; 6. IR Dump & Observability
;;; -----------------------------------------------------------------------

(define (dump-pass-ir pass-id stage ast)
  (display "\n----------------------------------------------------------------------\n")
  (display "[PASS MANAGER IR DUMP] ")
  (display pass-id)
  (display " (")
  (display stage)
  (display ")\n")
  (display "----------------------------------------------------------------------\n")
  (write (truncate-expr-for-diagnostics ast))
  (newline)
  (display "======================================================================\n\n"))

;;; -----------------------------------------------------------------------
;;; 7. Pipeline Execution Engine
;;; -----------------------------------------------------------------------

(define (run-single-pass pass-desc input-ast verify-mode trace-mode)
  (let* ((id (pass-id pass-desc))
         (fn (pass-fn pass-desc))
         (vphase (pass-verifier-phase pass-desc)))
    (set-current-pass! id)
    (with-call-frame id input-ast
      (lambda ()
        (let* ((t0 (current-time-monotonic-ms))
               (output-ast (fn input-ast))
               (t1 (current-time-monotonic-ms))
               (d (- t1 t0))
               (elapsed (if (< d 0) 0 d)))
          (if (pipeline-time-passes?)
              (record-pass-timing! id elapsed))
          (if trace-mode
              (nanopass-display-ast-diff id input-ast output-ast))
          (if (or (pipeline-print-after-all?)
                  (eq? (pipeline-dump-ir) id)
                  (eq? (pipeline-dump-ir) 'all))
              (dump-pass-ir id 'output output-ast))
          (if (and verify-mode vphase)
              (verify-pass-output vphase output-ast))
          output-ast)))))

(define (run-pass-pipeline forms verify-mode trace-mode)
  (if (null? (car *pass-registry*))
      (init-default-pass-registry!))
  (if verify-mode
      (begin
        (enable-verifier!)
        (if (eq? verify-mode 'strict)
            (set-verifier-strict! #t))))
  (if trace-mode
      (enable-nanopass-trace!))
  (let* ((opt-level (pipeline-opt-level))
         (disabled (pipeline-disabled-passes))
         (pipeline (build-pipeline opt-level disabled)))
    (validate-pipeline-prerequisites pipeline)
    (reset-pass-timings!)
    (let loop ((ps pipeline) (current-ast forms))
      (if (null? ps)
          (begin
            (if (pipeline-time-passes?)
                (print-pass-timing-report))
            (if verify-mode
                (verify-pass-output 'lir current-ast))
            current-ast)
          (let ((next-ast (run-single-pass (car ps) current-ast verify-mode trace-mode)))
            (loop (cdr ps) next-ast))))))

;;; -----------------------------------------------------------------------
;;; 8. Default Pass Registry Initialization
;;; -----------------------------------------------------------------------

(define (init-default-pass-registry!)
  (reset-pass-registry!)
  ;; Frontend Passes (Opt 0 = Mandatory, Opt 1/2 = Optimization)
  (register-pass!
    (make-pass-descriptor 'pass-010-library "Desugar Libraries and Imports" 'frontend 0
      (lambda (forms) (desugar-libraries-and-imports forms)) #f 'L_src 'L_src '() #t))
  (register-pass!
    (make-pass-descriptor 'pass-015-dsl-expander "DSL Expander" 'frontend 0
      (lambda (forms) (expand-dsl-forms forms)) #f 'L_src 'L_src '(pass-010-library) #t))
  (register-pass!
    (make-pass-descriptor 'pass-020-macro-expander "Hygienic Macro Expander" 'frontend 0
      (lambda (forms) (expand-macros-in-forms forms)) #f 'L_src 'L_src '(pass-015-dsl-expander) #t))
  (register-pass!
    (make-pass-descriptor 'pass-025-top-level "Rewrite Top-Level" 'frontend 0
      (lambda (forms) (rewrite-top-level forms)) #f 'L_src 'L_src '(pass-020-macro-expander) #t))
  (register-pass!
    (make-pass-descriptor 'pass-030-desugar "Core Desugar All" 'frontend 0
      (lambda (forms) (desugar-all forms)) 'desugar 'L_src 'L_core '(pass-025-top-level) #t))
  (register-pass!
    (make-pass-descriptor 'pass-035-scope-resolve "Lexical Scope Resolution and Alpha-Conversion" 'frontend 0
      (lambda (forms) (scope-resolve-all forms)) #f 'L_core 'L_core '(pass-030-desugar) #t))
  (register-pass!
    (make-pass-descriptor 'pass-050-cp0 "CP0 Source Optimization" 'frontend 1
      (lambda (forms) (cp0-optimize forms)) #f 'L_core 'L_core '(pass-030-desugar) #f))
  (register-pass!
    (make-pass-descriptor 'pass-060-lvn "Local Value Numbering" 'frontend 2
      (lambda (forms) (lvn-all forms)) #f 'L_core 'L_core '(pass-030-desugar) #f))
  (register-pass!
    (make-pass-descriptor 'pass-070-anf "A-Normal Form Conversion" 'frontend 0
      (lambda (forms) (anf-all forms)) 'anf 'L_core 'L_anf '(pass-030-desugar) #t))
  (register-pass!
    (make-pass-descriptor 'pass-080-annotator "Abstract Interpretation Annotator" 'frontend 2
      (lambda (forms) (annotate-all forms)) #f 'L_anf 'L_anf '(pass-070-anf) #f))
  (register-pass!
    (make-pass-descriptor 'pass-090-rtyper "Representation Typer & Unboxing" 'frontend 2
      (lambda (forms) (rtyper-all forms)) #f 'L_anf 'L_anf '(pass-070-anf) #f))
  (register-pass!
    (make-pass-descriptor 'pass-100-contify "Contification" 'frontend 2
      (lambda (forms) (contify-all forms)) #f 'L_anf 'L_anf '(pass-070-anf) #f))
  (register-pass!
    (make-pass-descriptor 'pass-110-closure-convert "Closure Conversion" 'frontend 0
      (lambda (forms) (closure-convert forms)) 'closure 'L_anf 'L_lifted '(pass-070-anf) #t))
  (register-pass!
    (make-pass-descriptor 'pass-120-alias-escape "TBAA and Escape Analysis" 'frontend 2
      (lambda (forms) (alias-escape-all forms)) #f 'L_lifted 'L_lifted '(pass-110-closure-convert) #f))
  ;; Middle-End / LIR Passes
  (register-pass!
    (make-pass-descriptor 'pass-130-lir "LIR Lowering and Generation" 'middle 0
      (lambda (forms) (generate-lir forms)) #f 'L_lifted 'L_lir_raw '(pass-110-closure-convert) #t))
  (register-pass!
    (make-pass-descriptor 'pass-128-lir-branch-fusion "LIR Branch Fusion" 'middle 2
      (lambda (lir) (lir-fuse-branches lir)) #f 'L_lir_raw 'L_lir_raw '(pass-130-lir) #f))
  (register-pass!
    (make-pass-descriptor 'pass-133-lir-peephole "LIR Peephole Optimization" 'middle 1
      (lambda (lir) (lir-peephole-optimize lir)) 'lir 'L_lir_raw 'L_lir_canonical '(pass-130-lir) #f))
  #t)
;;; =======================================================================
;;; ULisp Compiler: Generic Dataflow Analysis Framework & Lattice Engine
;;; Conforms to DSN-33 Architecture Specification & Issue #599
;;; Based on Monotone Framework (Kam & Ullman 1977, Kildall 1973)
;;; =======================================================================

;;; -----------------------------------------------------------------------
;;; Part 1: Set Operations & Equality Helpers
;;; -----------------------------------------------------------------------

(define (dataflow-set-equal? s1 s2)
  (and (= (length s1) (length s2))
       (dataflow-set-subset? s1 s2)))

(define (dataflow-set-subset? s1 s2)
  (cond
    ((null? s1) #t)
    ((memq (car s1) s2)
     (dataflow-set-subset? (cdr s1) s2))
    (else #f)))

(define (dataflow-set-intersect s1 s2)
  (cond
    ((null? s1) '())
    ((null? s2) '())
    ((memq (car s1) s2)
     (cons (car s1) (dataflow-set-intersect (cdr s1) s2)))
    (else
     (dataflow-set-intersect (cdr s1) s2))))

;;; -----------------------------------------------------------------------
;;; Part 2: Semi-Lattice Record & Built-in Lattices
;;; -----------------------------------------------------------------------

;;; Lattice record:
;;;   (list 'lattice name bottom top leq? join meet)
(define (make-lattice name bottom top leq? join meet)
  (list 'lattice name bottom top leq? join meet))

(define (lattice? obj)
  (and (pair? obj) (eq? (car obj) 'lattice)))

(define (lattice-name l) (cadr l))
(define (lattice-bottom l) (caddr l))
(define (lattice-top l) (cadddr l))
(define (lattice-leq? l a b) ((car (cddddr l)) a b))
(define (lattice-join l a b) ((cadr (cddddr l)) a b))
(define (lattice-meet l a b) ((caddr (cddddr l)) a b))

;;; Built-in Sentinel symbols
(define *df-bottom* '*df-bottom*)
(define *df-top* '*df-top*)

(define (df-bottom? x) (eq? x *df-bottom*))
(define (df-top? x) (eq? x *df-top*))

;;; 2.1 Boolean Lattice
;;; Bottom = #f, Top = #t
;;; #f <= #f, #f <= #t, #t <= #t
;;; Join = or, Meet = and
(define (make-boolean-lattice name)
  (make-lattice
   name
   #f
   #t
   (lambda (a b)
     (if a (and b #t) #t))
   (lambda (a b)
     (or a b))
   (lambda (a b)
     (and a b))))

;;; 2.2 Flat Lattice (Constants / Single values)
;;; Elements: *df-bottom*, constants c, *df-top*
;;; *df-bottom* <= c <= *df-top*
;;; If c1 != c2, c1 join c2 = *df-top*
(define (make-flat-lattice name eq-fn)
  (make-lattice
   name
   *df-bottom*
   *df-top*
   (lambda (a b)
     (cond
       ((eq? a *df-bottom*) #t)
       ((eq? b *df-top*) #t)
       ((and (not (eq? a *df-top*)) (not (eq? b *df-bottom*)))
        (eq-fn a b))
       (else #f)))
   (lambda (a b)
     (cond
       ((eq? a *df-bottom*) b)
       ((eq? b *df-bottom*) a)
       ((or (eq? a *df-top*) (eq? b *df-top*)) *df-top*)
       ((eq-fn a b) a)
       (else *df-top*)))
   (lambda (a b)
     (cond
       ((eq? a *df-top*) b)
       ((eq? b *df-top*) a)
       ((or (eq? a *df-bottom*) (eq? b *df-bottom*)) *df-bottom*)
       ((eq-fn a b) a)
       (else *df-bottom*)))))

;;; 2.3 Powerset Lattice (Set of symbols / expressions)
;;; Bottom = '(), Top = universe-or-top
;;; Join = set-union, Meet = dataflow-set-intersect
;;; Order: a <= b iff a subseteq b
(define (make-powerset-lattice name universe)
  (make-lattice
   name
   '()
   (if universe universe *df-top*)
   (lambda (a b)
     (cond
       ((eq? b *df-top*) #t)
       ((eq? a *df-top*) (eq? b *df-top*))
       (else (dataflow-set-subset? a b))))
   (lambda (a b)
     (cond
       ((eq? a *df-top*) *df-top*)
       ((eq? b *df-top*) *df-top*)
       (else (set-union a b))))
   (lambda (a b)
     (cond
       ((eq? a *df-top*) b)
       ((eq? b *df-top*) a)
       (else (dataflow-set-intersect a b))))))

;;; 2.4 Map / Environment Lattice (Var -> Value Lattice)
;;; Represents mappings from symbols to elements of an inner lattice.
;;; An environment is an alist: ((var . val) ...)
;;; Unbound variable is treated as (lattice-bottom val-lat).
(define (make-map-lattice name val-lat)
  (let* ((v-bot (lattice-bottom val-lat))
         (lookup-val (lambda (env k)
                       (let ((entry (assq k env)))
                         (if entry (cdr entry) v-bot)))))
    (make-lattice
     name
     '()
     *df-top*
     ;; leq? env1 env2
     (lambda (env1 env2)
       (cond
         ((eq? env2 *df-top*) #t)
         ((eq? env1 *df-top*) (eq? env2 *df-top*))
         (else
          (let loop ((entries env1))
            (if (null? entries)
                #t
                (let* ((k (caar entries))
                       (v1 (cdar entries))
                       (v2 (lookup-val env2 k)))
                  (if (lattice-leq? val-lat v1 v2)
                      (loop (cdr entries))
                      #f)))))))
     ;; join env1 env2
     (lambda (env1 env2)
       (cond
         ((eq? env1 *df-top*) *df-top*)
         ((eq? env2 *df-top*) *df-top*)
         (else
          (let* ((all-keys (set-union (map car* env1) (map car* env2))))
            (let loop ((keys all-keys) (acc '()))
              (if (null? keys)
                  acc
                  (let* ((k (car keys))
                         (v1 (lookup-val env1 k))
                         (v2 (lookup-val env2 k))
                         (v-joined (lattice-join val-lat v1 v2)))
                    ;; If joined value is bottom, omit from map for compactness
                    (if (lattice-leq? val-lat v-joined v-bot)
                        (loop (cdr keys) acc)
                        (loop (cdr keys) (cons (cons k v-joined) acc))))))))))
     ;; meet env1 env2
     (lambda (env1 env2)
       (cond
         ((eq? env1 *df-top*) env2)
         ((eq? env2 *df-top*) env1)
         (else
          (let* ((all-keys (set-union (map car* env1) (map car* env2))))
            (let loop ((keys all-keys) (acc '()))
              (if (null? keys)
                  acc
                  (let* ((k (car keys))
                         (v1 (lookup-val env1 k))
                         (v2 (lookup-val env2 k))
                         (v-met (lattice-meet val-lat v1 v2)))
                    (if (lattice-leq? val-lat v-met v-bot)
                        (loop (cdr keys) acc)
                        (loop (cdr keys) (cons (cons k v-met) acc)))))))))))))

;;; 2.5 Product Lattice (Tuple of two lattices)
(define (make-product-lattice name lat1 lat2)
  (make-lattice
   name
   (cons (lattice-bottom lat1) (lattice-bottom lat2))
   (cons (lattice-top lat1) (lattice-top lat2))
   (lambda (p1 p2)
     (and (lattice-leq? lat1 (car p1) (car p2))
          (lattice-leq? lat2 (cdr p1) (cdr p2))))
   (lambda (p1 p2)
     (cons (lattice-join lat1 (car p1) (car p2))
           (lattice-join lat2 (cdr p1) (cdr p2))))
   (lambda (p1 p2)
     (cons (lattice-meet lat1 (car p1) (car p2))
           (lattice-meet lat2 (cdr p1) (cdr p2))))))

;;; -----------------------------------------------------------------------
;;; Part 3: Dataflow Problem Specification
;;; -----------------------------------------------------------------------

;;; Problem record:
;;;   (list 'dataflow-problem name direction lattice boundary-val init-val transfer-fn)
(define (make-dataflow-problem name direction lattice boundary-val init-val transfer-fn)
  (list 'dataflow-problem name direction lattice boundary-val init-val transfer-fn))

(define (dataflow-problem? obj)
  (and (pair? obj) (eq? (car obj) 'dataflow-problem)))

(define (df-problem-name p) (cadr p))
(define (df-problem-direction p) (caddr p))
(define (df-problem-lattice p) (cadddr p))
(define (df-problem-boundary-val p) (car (cddddr p)))
(define (df-problem-init-val p) (cadr (cddddr p)))
(define (df-problem-transfer-fn p) (caddr (cddddr p)))

;;; -----------------------------------------------------------------------
;;; Part 4: Generic Worklist Fixed-Point Engine
;;; -----------------------------------------------------------------------

;;; Max iteration safety bound to prevent infinite compilation loops
(define *dataflow-max-iterations* (cons 2000 '()))

(define (dataflow-get-max-iterations)
  (car *dataflow-max-iterations*))

(define (dataflow-set-max-iterations! limit)
  (set-car! *dataflow-max-iterations* limit))

;;; Lookup state in alist ((node . state) ...)
(define (df-lookup-state table node default-val)
  (let ((entry (assq node table)))
    (if entry (cdr entry) default-val)))

;;; Update or add state in alist
(define (df-set-state table node new-val)
  (let loop ((entries table) (acc '()))
    (cond
      ((null? entries)
       (cons (cons node new-val) acc))
      ((eq? (caar entries) node)
       (append (cdr entries) (cons (cons node new-val) acc)))
      (else
       (loop (cdr entries) (cons (car entries) acc))))))

;;; Equality of lattice values using leq in both directions
(define (df-lattice-equal? lat a b)
  (and (lattice-leq? lat a b)
       (lattice-leq? lat b a)))

;;; Worklist Solver
;;; Arguments:
;;;   problem:      dataflow-problem
;;;   nodes:        list of node symbols/identifiers
;;;   entry-nodes:  list of entry/source nodes (for forward) or exit nodes (for backward)
;;;   preds-fn:     (lambda (node) -> list of predecessor nodes)
;;;   succs-fn:     (lambda (node) -> list of successor nodes)
;;; Returns:
;;;   Result table: ((node (in . in-val) (out . out-val)) ...)
(define (dataflow-analyze problem nodes entry-nodes preds-fn succs-fn)
  (let* ((lat (df-problem-lattice problem))
         (direction (df-problem-direction problem))
         (forward? (eq? direction 'forward))
         (boundary-val (df-problem-boundary-val problem))
         (init-val (df-problem-init-val problem))
         (transfer-fn (df-problem-transfer-fn problem))
         (max-iters (dataflow-get-max-iterations)))

    ;; Initialize in-table and out-table
    ;; For forward:
    ;;   in-table of entry-nodes = boundary-val, others = init-val
    ;;   out-table of all nodes = init-val
    ;; For backward:
    ;;   out-table of exit-nodes = boundary-val, others = init-val
    ;;   in-table of all nodes = init-val
    (let* ((init-tables
            (let loop ((ns nodes) (in-acc '()) (out-acc '()))
              (if (null? ns)
                  (cons in-acc out-acc)
                  (let* ((n (car ns))
                         (is-boundary? (if (memq n entry-nodes) #t #f)))
                    (if forward?
                        (loop (cdr ns)
                              (cons (cons n (if is-boundary? boundary-val init-val)) in-acc)
                              (cons (cons n init-val) out-acc))
                        (loop (cdr ns)
                              (cons (cons n init-val) in-acc)
                              (cons (cons n (if is-boundary? boundary-val init-val)) out-acc)))))))
           (initial-in-table (car init-tables))
           (initial-out-table (cdr init-tables))
           ;; Worklist initially contains all nodes
           (initial-worklist nodes))

      ;; Worklist iteration loop
      (let solve-loop ((worklist initial-worklist)
                       (in-table initial-in-table)
                       (out-table initial-out-table)
                       (iter-count 0))
        (cond
          ((null? worklist)
           ;; Fixed-point reached: construct result table
           (let loop ((ns nodes) (res '()))
             (if (null? ns)
                 (reverse res)
                 (let* ((n (car ns))
                        (in-v (df-lookup-state in-table n init-val))
                        (out-v (df-lookup-state out-table n init-val)))
                   (loop (cdr ns)
                         (cons (list n (cons 'in in-v) (cons 'out out-v)) res))))))

          ((>= iter-count max-iters)
           ;; Exceeded maximum iterations: log diagnostic and return best-effort
           (let loop ((ns nodes) (res '()))
             (if (null? ns)
                 (reverse res)
                 (let* ((n (car ns))
                        (in-v (df-lookup-state in-table n (lattice-top lat)))
                        (out-v (df-lookup-state out-table n (lattice-top lat))))
                   (loop (cdr ns)
                         (cons (list n (cons 'in in-v) (cons 'out out-v)) res))))))

          (else
           (let* ((n (car worklist))
                  (rest-wl (cdr worklist)))
             (if forward?
                 ;; --- FORWARD ANALYSIS ---
                 (let* ((preds (preds-fn n))
                        ;; in[n] = join_{p in preds} out[p] (or boundary-val if entry)
                        (new-in
                         (if (memq n entry-nodes)
                             (if (null? preds)
                                 boundary-val
                                 (let loop-p ((ps preds) (acc boundary-val))
                                   (if (null? ps) acc
                                       (let ((p-out (df-lookup-state out-table (car ps) init-val)))
                                         (loop-p (cdr ps) (lattice-join lat acc p-out))))))
                             (let loop-p ((ps preds) (acc init-val))
                               (if (null? ps) acc
                                   (let ((p-out (df-lookup-state out-table (car ps) init-val)))
                                     (loop-p (cdr ps) (lattice-join lat acc p-out)))))))
                        ;; out[n] = transfer(n, in[n])
                        (new-out (transfer-fn n new-in))
                        (old-out (df-lookup-state out-table n init-val)))
                   (if (df-lattice-equal? lat old-out new-out)
                       ;; No change in out[n], continue
                       (solve-loop rest-wl
                                   (df-set-state in-table n new-in)
                                   out-table
                                   (+ iter-count 1))
                       ;; out[n] changed: add all successors to worklist
                       (let* ((succs (succs-fn n))
                              (new-wl (let add-loop ((ss succs) (cur-wl rest-wl))
                                        (cond
                                          ((null? ss) cur-wl)
                                          ((memq (car ss) cur-wl) (add-loop (cdr ss) cur-wl))
                                          (else (add-loop (cdr ss) (cons (car ss) cur-wl)))))))
                         (solve-loop new-wl
                                     (df-set-state in-table n new-in)
                                     (df-set-state out-table n new-out)
                                     (+ iter-count 1)))))

                 ;; --- BACKWARD ANALYSIS ---
                 (let* ((succs (succs-fn n))
                        ;; out[n] = join_{s in succs} in[s] (or boundary-val if exit)
                        (new-out
                         (if (memq n entry-nodes)
                             (if (null? succs)
                                 boundary-val
                                 (let loop-s ((ss succs) (acc boundary-val))
                                   (if (null? ss) acc
                                       (let ((s-in (df-lookup-state in-table (car ss) init-val)))
                                         (loop-s (cdr ss) (lattice-join lat acc s-in))))))
                             (let loop-s ((ss succs) (acc init-val))
                               (if (null? ss) acc
                                   (let ((s-in (df-lookup-state in-table (car ss) init-val)))
                                     (loop-s (cdr ss) (lattice-join lat acc s-in)))))))
                        ;; in[n] = transfer(n, out[n])
                        (new-in (transfer-fn n new-out))
                        (old-in (df-lookup-state in-table n init-val)))
                   (if (df-lattice-equal? lat old-in new-in)
                       ;; No change in in[n], continue
                       (solve-loop rest-wl
                                   in-table
                                   (df-set-state out-table n new-out)
                                   (+ iter-count 1))
                       ;; in[n] changed: add all predecessors to worklist
                       (let* ((preds (preds-fn n))
                              (new-wl (let add-loop ((ps preds) (cur-wl rest-wl))
                                        (cond
                                          ((null? ps) cur-wl)
                                          ((memq (car ps) cur-wl) (add-loop (cdr ps) cur-wl))
                                          (else (add-loop (cdr ps) (cons (car ps) cur-wl)))))))
                         (solve-loop new-wl
                                     (df-set-state in-table n new-in)
                                     (df-set-state out-table n new-out)
                                     (+ iter-count 1)))))))))))))

;;; -----------------------------------------------------------------------
;;; Part 5: Result Accessors & Query Helpers
;;; -----------------------------------------------------------------------

(define (dataflow-result-in results node)
  (let ((entry (assq node results)))
    (if entry
        (let ((in-pair (assq 'in (cdr entry))))
          (if in-pair (cdr in-pair) #f))
        #f)))

(define (dataflow-result-out results node)
  (let ((entry (assq node results)))
    (if entry
        (let ((out-pair (assq 'out (cdr entry))))
          (if out-pair (cdr out-pair) #f))
        #f)))

;;; -----------------------------------------------------------------------
;;; Part 6: High-Level Dataflow Problem Builders
;;; -----------------------------------------------------------------------

;;; 6.1 Liveness Analysis Problem (Backward)
;;; Lattice: Powerset of variables
;;; Transfer: In[n] = (Out[n] \ Def[n]) U Use[n]
(define (make-liveness-problem name def-use-table)
  (let ((lat (make-powerset-lattice (string->symbol (string-append (symbol->string name) "-liveness")) #f)))
    (make-dataflow-problem
     name
     'backward
     lat
     '()    ; boundary-val: exit has no live variables
     '()    ; init-val: bottom is empty set
     (lambda (node out-state)
       (let ((du (assq node def-use-table)))
         (if du
             (let* ((defs (cadr du))
                    (uses (caddr du)))
               (set-union (set-diff out-state defs) uses))
             out-state))))))

;;; 6.2 Reaching Definitions Problem (Forward)
;;; Lattice: Powerset of definition IDs
;;; Transfer: Out[n] = Gen[n] U (In[n] \ Kill[n])
(define (make-reaching-defs-problem name gen-kill-table)
  (let ((lat (make-powerset-lattice (string->symbol (string-append (symbol->string name) "-reaching")) #f)))
    (make-dataflow-problem
     name
     'forward
     lat
     '()    ; boundary-val: entry has no definitions
     '()    ; init-val: bottom is empty set
     (lambda (node in-state)
       (let ((gk (assq node gen-kill-table)))
         (if gk
             (let* ((gen (cadr gk))
                    (kill (caddr gk)))
               (set-union gen (set-diff in-state kill)))
             in-state))))))

;;; 6.3 Constant Propagation Problem (Forward)
;;; Lattice: Map from Var -> Flat Lattice
(define (make-constant-propagation-problem name const-transfer-fn)
  (let* ((flat-lat (make-flat-lattice 'const-val equal?))
         (map-lat (make-map-lattice 'const-env flat-lat)))
    (make-dataflow-problem
     name
     'forward
     map-lat
     '()    ; boundary-val: entry environment is empty
     '()    ; init-val: empty
     const-transfer-fn)))
;;; =======================================================================
;;; ULisp Compiler: Unified Lexical Scope & Alpha-Conversion Engine (Pass 035)
;;; Conforms to DSN-33 Architecture Specification & Issue #600
;;; Guarantees Barendregt Variable Convention (globally unique bound variables)
;;; and performs early deterministic detection of unbound variables.
;;; =======================================================================

;;; -----------------------------------------------------------------------
;;; Part 1: Scope Tree Data Structure & Lexical Contour Navigation
;;; -----------------------------------------------------------------------

;;; Scope node representation:
;;;   (list 'scope-node parent kind bindings-cell free-vars-cell children-cell)
;;;
;;; Fields:
;;;   - parent: enclosing scope-node or #f (for root/top-level)
;;;   - kind: symbol ('top-level, 'lambda, 'let, 'letrec, '%cont-fun)
;;;   - bindings-cell: (cons bindings '()) where bindings is ((orig-sym . alpha-sym) ...)
;;;   - free-vars-cell: (cons free-vars '()) where free-vars is (sym ...)
;;;   - children-cell: (cons children '()) where children is (scope-node ...)

(define (make-scope-node parent kind)
  (list 'scope-node parent kind (cons '() '()) (cons '() '()) (cons '() '())))

(define (scope-node? obj)
  (and (pair? obj) (eq? (car obj) 'scope-node)))

(define (scope-node-parent node)
  (cadr node))

(define (scope-node-kind node)
  (caddr node))

(define (scope-node-bindings-cell node)
  (cadddr node))

(define (scope-node-bindings node)
  (car (scope-node-bindings-cell node)))

(define (scope-node-free-vars-cell node)
  (car (cddddr node)))

(define (scope-node-free-vars node)
  (car (scope-node-free-vars-cell node)))

(define (scope-node-children-cell node)
  (cadr (cddddr node)))

(define (scope-node-children node)
  (car (scope-node-children-cell node)))

(define (scope-enter parent kind)
  (let ((child (make-scope-node parent kind)))
    (if (scope-node? parent)
        (let ((cc (scope-node-children-cell parent)))
          (set-car! cc (append (car cc) (list child)))))
    child))

(define (scope-bind! node orig-sym alpha-sym)
  (let ((bc (scope-node-bindings-cell node)))
    (set-car! bc (cons (cons orig-sym alpha-sym) (car bc)))))

(define (scope-lookup-local node orig-sym)
  (let ((entry (assq orig-sym (scope-node-bindings node))))
    (if entry
        (cdr entry)
        #f)))

(define (scope-lookup-lexical node orig-sym)
  (if (not (scope-node? node))
      #f
      (let ((entry (assq orig-sym (scope-node-bindings node))))
        (if entry
            (cons node (cdr entry))
            (scope-lookup-lexical (scope-node-parent node) orig-sym)))))

(define (scope-lookup node orig-sym)
  (let ((res (scope-lookup-lexical node orig-sym)))
    (if res
        (cdr res)
        #f)))

(define (scope-record-free-var! node sym)
  (if (scope-node? node)
      (let ((fc (scope-node-free-vars-cell node)))
        (if (not (memq sym (car fc)))
            (set-car! fc (cons sym (car fc)))))))

;;; -----------------------------------------------------------------------
;;; Part 2: Deterministic Alpha Symbol Generator
;;; -----------------------------------------------------------------------

(define *alpha-symbol-counter* (cons 0 '()))

(define (reset-alpha-symbol-counter!)
  (set-car! *alpha-symbol-counter* 0))

(define (alpha-next-id!)
  (let ((c (car *alpha-symbol-counter*)))
    (set-car! *alpha-symbol-counter* (+ c 1))
    c))

(define (make-alpha-symbol orig-sym)
  (let* ((orig-str (symbol->string orig-sym))
         (id (alpha-next-id!))
         (new-str (string-append orig-str "$" (number->string id))))
    (string->symbol new-str)))

;;; -----------------------------------------------------------------------
;;; Part 3: Known Primitives, Runtime Built-ins & Global Definitions
;;; -----------------------------------------------------------------------

(define *scope-runtime-special-forms*
  '(quote if begin set! lambda let letrec
    %make-closure %make-closure-env %closure-ref %closure-set!
    %cont-fun %cont-call %with-handler %raw-call/cc %call-with-values
    %values %program define define-values define-record-type))

(define (scope-special-form? sym)
  (if (memq sym *scope-runtime-special-forms*) #t #f))

(define *scope-standard-builtins*
  '(+ - * / = < <= > >= modulo quotient remainder abs
    zero? not eq? eqv? equal? pair? null? boolean? char?
    string? vector? bytevector? procedure? symbol? number?
    integer? exact? inexact? real? rational? complex?
    fixnum? exact-integer? list?
    car cdr set-car! set-cdr! caar cadr cdar cddr caaar caadr cadar caddr cdaar cdadr cddar cdddr
    cons list append reverse length memq assq
    make-string string-length string-ref string-set! string-copy string-copy! string-fill! string-append
    string=? string<? string>? string<=? string>=?
    char=? char<? char>? char<=? char>=?
    make-vector vector-length vector-ref vector-set! vector-copy vector-copy! vector-fill! vector-append
    vector->list list->vector string->list list->string
    make-bytevector bytevector-length bytevector-u8-ref bytevector-u8-set! bytevector-copy bytevector-copy! bytevector-append
    write-char read-char peek-char write-string display newline write read error raise
    call-with-values values call/cc dynamic-wind
    open-input-file flush-output-port eof-object eof-object?
    power-assert-report dump-lir-unbound-variable-diagnostic
    %raw-load %raw-store! %raw-syscall %raw-add %raw-sub %raw-mul %raw-cmp
    %ptr-add %ptr-tag %ptr-untag %ptr-tag-add %to-raw %to-fixnum %box-fixnum %unbox-fixnum
    %num-args %get-rsp %get-heap-ptr %get-heap-limit-ptr %get-gc-state-ptr %get-stackmap-table))

(define (scope-primitive-symbol? sym)
  (or (scope-special-form? sym)
      (if (memq sym *scope-standard-builtins*) #t #f)
      (zero-arg-prim? sym)
      (unary-prim? sym)
      (binop-prim? sym)
      (triop-prim? sym)
      (septop-prim? sym)
      (closure-prim? sym)
      (pure-prim? sym)
      ;; Any low-level compiler internal symbol starting with '%' is treated as a runtime builtin
      (let ((s (symbol->string sym)))
        (and (> (string-length s) 0)
             (char=? (string-ref s 0) #\%)))))

(define (collect-top-level-defines defs)
  (let loop ((ds defs) (acc '()))
    (if (null? ds)
        (reverse acc)
        (let ((d (car ds)))
          (cond
            ((and (pair? d) (eq? (car d) 'define) (pair? (cdr d)))
             (let ((spec (cadr d)))
               (if (pair? spec)
                   (loop (cdr ds) (cons (car spec) acc))
                   (loop (cdr ds) (cons spec acc)))))
            ((and (pair? d) (eq? (car d) 'define-values) (pair? (cdr d)))
             (let ((formals (cadr d)))
               (if (list? formals)
                   (loop (cdr ds) (append (reverse formals) acc))
                   (loop (cdr ds) acc))))
            (else
             (loop (cdr ds) acc)))))))

(define (scope-known-global-or-prim? sym globals)
  (or (if (memq sym globals) #t #f)
      (scope-primitive-symbol? sym)))

;;; -----------------------------------------------------------------------
;;; Part 4: Early Unbound Variable Detection
;;; -----------------------------------------------------------------------

(define *scope-unbound-vars* (cons '() '()))
(define *scope-strict-unbound-check* (cons #f '()))

(define (reset-scope-unbound-vars!)
  (set-car! *scope-unbound-vars* '()))

(define (record-scope-unbound-var! var context)
  (if (not (memq var (car *scope-unbound-vars*)))
      (set-car! *scope-unbound-vars* (cons var (car *scope-unbound-vars*)))))

(define (get-scope-unbound-vars)
  (reverse (car *scope-unbound-vars*)))

(define (set-scope-strict-unbound-check! bool)
  (set-car! *scope-strict-unbound-check* bool))

(define (scope-strict-unbound-check?)
  (car *scope-strict-unbound-check*))

;;; -----------------------------------------------------------------------
;;; Part 5: Alpha-Conversion Engine (Barendregt Variable Normalization)
;;; -----------------------------------------------------------------------

(define (alpha-convert-list es scope globals)
  (let loop ((rest es) (acc '()))
    (if (null? rest)
        (reverse acc)
        (loop (cdr rest) (cons (alpha-convert-expr (car rest) scope globals) acc)))))

(define (alpha-convert-expr expr scope globals)
  (cond
    ;; 1. Literal Quote: datum inside (quote ...) is preserved verbatim
    ((and (pair? expr) (eq? (car expr) 'quote))
     expr)

    ;; 2. Atomic Symbol: Variable reference
    ((symbol? expr)
     (let ((alpha-sym (scope-lookup scope expr)))
       (cond
         (alpha-sym
          ;; Propagate free-variable usage up the lexical contour tree
          (let propagate ((curr scope))
            (if (and (scope-node? curr)
                     (not (scope-lookup-local curr expr)))
                (begin
                  (scope-record-free-var! curr expr)
                  (propagate (scope-node-parent curr)))))
          alpha-sym)
         ((scope-known-global-or-prim? expr globals)
          expr)
         (else
          (record-scope-unbound-var! expr scope)
          (if (scope-strict-unbound-check?)
              (error (string-append "Static Scope Error: Unbound variable '" (symbol->string expr) "'") expr)
              expr)))))

    ;; 3. Non-symbol atomics (numbers, booleans, chars, strings, null)
    ((not (pair? expr))
     expr)

    ;; 4. Composite Forms
    (else
     (let ((op (car expr)))
       (case op
         ;; 4.1 Conditional: (if test then [else])
         ((if)
          (let ((test (alpha-convert-expr (cadr expr) scope globals))
                (then (alpha-convert-expr (caddr expr) scope globals))
                (else-expr (if (null? (cdddr expr))
                               #f
                               (alpha-convert-expr (cadddr expr) scope globals))))
            (if (null? (cdddr expr))
                (list 'if test then)
                (list 'if test then else-expr))))

         ;; 4.2 Sequencing: (begin e ...)
         ((begin)
          (cons 'begin (alpha-convert-list (cdr expr) scope globals)))

         ;; 4.3 Assignment: (set! var val)
         ((set!)
          (let* ((var (cadr expr))
                 (val (alpha-convert-expr (caddr expr) scope globals))
                 (alpha-var (scope-lookup scope var)))
            (if alpha-var
                (list 'set! alpha-var val)
                (if (scope-known-global-or-prim? var globals)
                    (list 'set! var val)
                    (begin
                      (record-scope-unbound-var! var scope)
                      (if (scope-strict-unbound-check?)
                          (error (string-append "Static Scope Error: Unbound variable in set! '" (symbol->string var) "'") var)
                          (list 'set! var val)))))))

         ;; 4.4 Abstraction: (lambda (params ...) body)
         ((lambda)
          (let* ((params (cadr expr))
                 (body (caddr expr))
                 (child-scope (scope-enter scope 'lambda))
                 (alpha-params
                  (let loop ((ps params) (acc '()))
                    (if (null? ps)
                        (reverse acc)
                        (let* ((p (car ps))
                               (a-p (make-alpha-symbol p)))
                          (scope-bind! child-scope p a-p)
                          (loop (cdr ps) (cons a-p acc))))))
                 (converted-body (alpha-convert-expr body child-scope globals)))
            (list 'lambda alpha-params converted-body)))

         ;; 4.5 Local Binding: (let ((var expr) ...) body)
         ((let)
          (let* ((bindings (cadr expr))
                 (body (caddr expr))
                 ;; Binding RHS expressions are evaluated in the outer scope
                 (converted-rhs
                  (let loop ((bs bindings) (acc '()))
                    (if (null? bs)
                        (reverse acc)
                        (let* ((b (car bs))
                               (v (cadr b)))
                          (loop (cdr bs) (cons (alpha-convert-expr v scope globals) acc))))))
                 ;; Body is evaluated in the new child scope with alpha variables
                 (child-scope (scope-enter scope 'let))
                 (alpha-vars
                  (let loop ((bs bindings) (acc '()))
                    (if (null? bs)
                        (reverse acc)
                        (let* ((b (car bs))
                               (k (car b))
                               (a-k (make-alpha-symbol k)))
                          (scope-bind! child-scope k a-k)
                          (loop (cdr bs) (cons a-k acc))))))
                 (new-bindings
                  (let loop ((vars alpha-vars) (vals converted-rhs) (acc '()))
                    (if (null? vars)
                        (reverse acc)
                        (loop (cdr vars) (cdr vals) (cons (list (car vars) (car vals)) acc)))))
                 (converted-body (alpha-convert-expr body child-scope globals)))
            (list 'let new-bindings converted-body)))

         ;; 4.6 Recursive Binding: (letrec ((var expr) ...) body)
         ((letrec)
          (let* ((bindings (cadr expr))
                 (body (caddr expr))
                 (child-scope (scope-enter scope 'letrec))
                 ;; All variables are bound in child-scope prior to RHS conversion
                 (alpha-vars
                  (let loop ((bs bindings) (acc '()))
                    (if (null? bs)
                        (reverse acc)
                        (let* ((b (car bs))
                               (k (car b))
                               (a-k (make-alpha-symbol k)))
                          (scope-bind! child-scope k a-k)
                          (loop (cdr bs) (cons a-k acc))))))
                 (converted-rhs
                  (let loop ((bs bindings) (acc '()))
                    (if (null? bs)
                        (reverse acc)
                        (let* ((b (car bs))
                               (v (cadr b)))
                          (loop (cdr bs) (cons (alpha-convert-expr v child-scope globals) acc))))))
                 (new-bindings
                  (let loop ((vars alpha-vars) (vals converted-rhs) (acc '()))
                    (if (null? vars)
                        (reverse acc)
                        (loop (cdr vars) (cdr vals) (cons (list (car vars) (car vals)) acc)))))
                 (converted-body (alpha-convert-expr body child-scope globals)))
            (list 'letrec new-bindings converted-body)))

         ;; 4.7 Continuation Function: (%cont-fun f-name (params ...) f-body in-body)
         ((%cont-fun)
          (let* ((f-name (cadr expr))
                 (params (caddr expr))
                 (f-body (cadddr expr))
                 (in-body (cadr (cdddr expr)))
                 (alpha-f (make-alpha-symbol f-name))
                 ;; f-body scope binds parameters and alpha-f
                 (f-scope (scope-enter scope '%cont-fun))
                 (alpha-params
                  (let loop ((ps params) (acc '()))
                    (if (null? ps)
                        (reverse acc)
                        (let* ((p (car ps))
                               (a-p (make-alpha-symbol p)))
                          (scope-bind! f-scope p a-p)
                          (loop (cdr ps) (cons a-p acc)))))))
            (scope-bind! f-scope f-name alpha-f)
            (let ((new-f-body (alpha-convert-expr f-body f-scope globals))
                  ;; in-body has alpha-f in scope
                  (in-scope (scope-enter scope '%cont-fun)))
              (scope-bind! in-scope f-name alpha-f)
              (let ((new-in-body (alpha-convert-expr in-body in-scope globals)))
                (list '%cont-fun alpha-f alpha-params new-f-body new-in-body)))))

         ;; 4.8 Continuation Call: (%cont-call target es ...)
         ((%cont-call)
          (let ((target (alpha-convert-expr (cadr expr) scope globals))
                (args (alpha-convert-list (cddr expr) scope globals)))
            (cons '%cont-call (cons target args))))

         ;; 4.9 Dynamic Exception Handler: (%with-handler h body)
         ((%with-handler)
          (list '%with-handler
                (alpha-convert-expr (cadr expr) scope globals)
                (alpha-convert-expr (caddr expr) scope globals)))

         ;; 4.10 Call/cc raw: (%raw-call/cc arg)
         ((%raw-call/cc)
          (list '%raw-call/cc (alpha-convert-expr (cadr expr) scope globals)))

         ;; 4.11 Values & Call-with-values
         ((%values)
          (cons '%values (alpha-convert-list (cdr expr) scope globals)))

         ((%call-with-values)
          (list '%call-with-values
                (alpha-convert-expr (cadr expr) scope globals)
                (alpha-convert-expr (caddr expr) scope globals)))

         ;; 4.12 Closures (lowered primitives)
         ((%make-closure)
          (cons '%make-closure (cons (cadr expr) (alpha-convert-list (cddr expr) scope globals))))

         ((%make-closure-env)
          (cons '%make-closure-env (cons (cadr expr) (alpha-convert-list (cddr expr) scope globals))))

         ;; 4.13 Program Container: (%program defs main)
         ((%program)
          (alpha-convert-program-node expr globals))

         ;; 4.14 General Function / Primitive Application: (op arg ...)
         (else
          (let ((conv-op (alpha-convert-expr op scope globals))
                (conv-args (alpha-convert-list (cdr expr) scope globals)))
            (cons conv-op conv-args))))))))

;;; -----------------------------------------------------------------------
;;; Part 6: Program-Level Conversion & Verification
;;; -----------------------------------------------------------------------

(define (alpha-convert-program-node prog-expr base-globals)
  (let* ((defs (cadr prog-expr))
         (main (caddr prog-expr))
         (top-defines (collect-top-level-defines defs))
         (all-globals (append top-defines base-globals))
         (top-scope (make-scope-node #f 'top-level))
         (converted-defs
          (let loop ((ds defs) (acc '()))
            (if (null? ds)
                (reverse acc)
                (let ((d (car ds)))
                  (if (and (pair? d) (eq? (car d) 'define))
                      (let* ((name (cadr d))
                             (val (caddr d))
                             (conv-val (alpha-convert-expr val top-scope all-globals)))
                        (loop (cdr ds) (cons (list 'define name conv-val) acc)))
                      (loop (cdr ds) (cons (alpha-convert-expr d top-scope all-globals) acc)))))))
         (converted-main (alpha-convert-expr main top-scope all-globals)))
    (list '%program converted-defs converted-main)))

(define (alpha-convert-program ast)
  (reset-scope-unbound-vars!)
  (if (and (pair? ast) (eq? (car ast) '%program))
      (alpha-convert-program-node ast '())
      (let* ((top-scope (make-scope-node #f 'top-level)))
        (alpha-convert-expr ast top-scope '()))))

;;; -----------------------------------------------------------------------
;;; Part 7: Public API & Pass 035 Integration Entry Point
;;; -----------------------------------------------------------------------

(define (scope-resolve-all ast)
  (reset-alpha-symbol-counter!)
  (alpha-convert-program ast))

(define (detect-unbound-variables ast)
  (let ((saved-strict (scope-strict-unbound-check?)))
    (set-scope-strict-unbound-check! #f)
    (reset-scope-unbound-vars!)
    (alpha-convert-program ast)
    (let ((unbounds (get-scope-unbound-vars)))
      (set-scope-strict-unbound-check! saved-strict)
      unbounds)))

(define (scope-check-unbound! ast)
  (let ((saved-strict (scope-strict-unbound-check?)))
    (set-scope-strict-unbound-check! #t)
    (reset-scope-unbound-vars!)
    (let ((res (alpha-convert-program ast)))
      (set-scope-strict-unbound-check! saved-strict)
      res)))
;;; =======================================================================
;;; ULisp Compiler: Frontend Intermediate Languages Specification
;;; (L_anf and L_lifted)
;;; Conforms to DSN-33 Architecture Specification & Issue #594
;;; =======================================================================
;;; Formal intermediate language definitions for the late Frontend pipeline
;;; using Nanopass DSL (define-language).
;;; - L_anf: A-Normal Form intermediate language where all function/primitive
;;;          arguments and conditional tests are atomic operands.
;;; - L_lifted: Flat procedure intermediate language where local lambda abstractions
;;;             have been hoisted into top-level %function definitions, and closures
;;;             are explicitly instantiated via %make-closure / %make-closure-env.
;;; =======================================================================

;;; -----------------------------------------------------------------------
;;; L_anf: 3-Address Code / A-Normal Form Language
;;; -----------------------------------------------------------------------
(define-language L_anf
  (entry Program)
  (terminals
    (symbol (x lbl var))
    (constant (c)))
  (Atom (a)
    x
    lbl
    var
    c
    (quote datum)
    (%closure-ref a c)
    (%global-ref x))
  (Def (d)
    (define x e)
    e)
  (Expr (e)
    a
    (if a e1 e2)
    (if a e1)
    (begin e ...)
    (let ((x e1) ...) e ...)
    (letrec ((x e1) ...) e ...)
    (lambda (x ...) e ...)
    (set! x e)
    (%make-closure a1 a ...)
    (%make-closure-env a1 a ...)
    (%closure-ref a c)
    (%closure-set! a1 c a2)
    (%cont-fun x (x ...) e1 e2)
    (%cont-call x a ...)
    (%with-handler a1 a2)
    (%raw-call/cc a)
    (%call-with-values a1 a2)
    (%values a ...)
    (%direct-call a1 a ...)
    (%global-ref x)
    (%global-set! x e)
    (a0 a ...))
  (Program (p)
    (%program (d ...) e)
    e))

;;; -----------------------------------------------------------------------
;;; L_lifted: Lambda-Lifted & Explicit Closure Converted Language
;;; -----------------------------------------------------------------------
(define-language L_lifted
  (extends L_anf)
  (entry Program)
  (FunctionDecl (fn)
    (%function x (x ...) e))
  (Expr (e)
    (- (lambda (x ...) e ...))
    (+ (annotate x e)
       (%stack-cons a1 a2)))
  (Program (p)
    (- (%program (d ...) e))
    (+ (%program (fn ...) e))))
;;; =======================================================================
;;; ULisp Compiler Pass 0a: R7RS define-library & import Desugaring Pass
;;; Conforms to DSN-33 Architecture Specification & Issue #548 (R7RS 5.6)
;;;
;;; Transforms R7RS-small modular library definitions and import sets
;;; into a flat, deterministic sequence of top-level definitions and expressions.
;;; =======================================================================

;;; -----------------------------------------------------------------------
;;; 1. Library Identification & Built-in Predicates
;;; -----------------------------------------------------------------------

(define (define-library-form? form)
  (and (pair? form) (eq? (car form) 'define-library)))

(define (import-form? form)
  (and (pair? form) (eq? (car form) 'import)))

;;; Built-in R7RS standard libraries that are inherently supported by ULisp runtime
(define (builtin-library-name? name)
  (and (pair? name)
       (or (and (eq? (car name) 'scheme)
                (memq (cadr name) '(base write read time file process-context cxr inexact complex char lazy case-lambda eval repl r5rs load)))
           (and (eq? (car name) 'ulisp)
                (memq (cadr name) '(base core native))))))

;;; Convert library name list e.g. (math matrix) to prefix string "math_matrix__"
(define (library-name->prefix-str lib-name)
  (let loop ((rest lib-name) (acc "__lib_"))
    (if (null? rest)
        (string-append acc "_")
        (let* ((elem (car rest))
               (part (cond
                       ((symbol? elem) (symbol->string elem))
                       ((number? elem) (number->string elem))
                       (else "sub"))))
          (loop (cdr rest) (string-append acc part "_"))))))

;;; -----------------------------------------------------------------------
;;; 2. Library Record Representation
;;; -----------------------------------------------------------------------

;;; Record: (list 'library-rec name exports imports body-forms)
(define (make-library-rec name exports imports body-forms)
  (list 'library-rec name exports imports body-forms))

(define (lib-rec? r)
  (and (pair? r) (eq? (car r) 'library-rec)))

(define (lib-rec-name r) (cadr r))
(define (lib-rec-exports r) (caddr r))
(define (lib-rec-imports r) (cadddr r))
(define (lib-rec-body r) (car (cddddr r)))

;;; Parse (export <export-spec> ...)
;;; Each export-spec is <identifier> or (rename <orig> <new>)
;;; Returns list of (cons <internal-name> <exported-public-name>)
(define (parse-export-specs specs)
  (let loop ((rest specs) (acc '()))
    (if (null? rest)
        (reverse acc)
        (let ((spec (car rest)))
          (cond
            ((symbol? spec)
             (loop (cdr rest) (cons (cons spec spec) acc)))
            ((and (pair? spec)
                  (eq? (car spec) 'rename)
                  (pair? (cdr spec))
                  (pair? (cddr spec)))
             (loop (cdr rest) (cons (cons (cadr spec) (caddr spec)) acc)))
            (else
             (loop (cdr rest) acc)))))))

;;; Parse a complete define-library form into a library-rec
(define (parse-define-library-form form)
  (let* ((name (cadr form))
         (decls (cddr form)))
    (let loop ((rest decls)
               (exports '())
               (imports '())
               (body-forms '()))
      (if (null? rest)
          (make-library-rec name (reverse exports) (reverse imports) (reverse body-forms))
          (let ((d (car rest)))
            (cond
              ;; (export spec ...)
              ((and (pair? d) (eq? (car d) 'export))
               (loop (cdr rest)
                     (append (reverse (parse-export-specs (cdr d))) exports)
                     imports
                     body-forms))

              ;; (import iset ...)
              ((and (pair? d) (eq? (car d) 'import))
               (loop (cdr rest)
                     exports
                     (append (reverse (cdr d)) imports)
                     body-forms))

              ;; (begin expr ...)
              ((and (pair? d) (eq? (car d) 'begin))
               (loop (cdr rest)
                     exports
                     imports
                     (append (reverse (cdr d)) body-forms)))

              ;; (include "path" ...)
              ((and (pair? d) (eq? (car d) 'include))
               (let ((included-forms (slurp-included-files (cdr d))))
                 (loop (cdr rest)
                       exports
                       imports
                       (append (reverse included-forms) body-forms))))

              (else
               ;; Skip unrecognized or unsupported declaration silently
               (loop (cdr rest) exports imports body-forms))))))))

;;; -----------------------------------------------------------------------
;;; 2.5 File Inclusion & Path Resolution (R7RS Section 4.1.7 & 5.6.1)
;;; -----------------------------------------------------------------------

(define (include-form? form)
  (and (pair? form)
       (or (eq? (car form) 'include)
           (eq? (car form) 'include-ci))))

(define *include-path-stack* (cons '() '()))

(define (member-string? s ls)
  (cond
    ((null? ls) #f)
    ((not (pair? ls)) #f)
    ((string=? s (car ls)) #t)
    (else (member-string? s (cdr ls)))))

(define (extract-dir-path path)
  (let loop ((i (- (string-length path) 1)))
    (cond
      ((< i 0) "")
      ((char=? (string-ref path i) #\/)
       (substring path 0 (+ i 1)))
      (else (loop (- i 1))))))

(define (path-traversal? p)
  (if (and (> (string-length p) 0) (char=? (string-ref p 0) #\/))
      #t
      (let loop ((i 0))
        (if (>= (+ i 3) (string-length p))
            #f
            (if (and (char=? (string-ref p i) #\.)
                     (char=? (string-ref p (+ i 1)) #\.)
                     (char=? (string-ref p (+ i 2)) #\/))
                #t
                (loop (+ i 1)))))))

(define (find-included-file path)
  (let ((p (open-input-file path)))
    (if p
        (begin (close-input-port p) path)
        (let* ((prefixed (string-append "ulisp/" path))
               (p2 (open-input-file prefixed)))
          (if p2
              (begin (close-input-port p2) prefixed)
              path)))))

(define (resolve-include-path path)
  (if (path-traversal? path)
      (error "include: path traversal outside allowed directory rejected" path)
      (let ((stack (car *include-path-stack*)))
        (if (and (pair? stack) (not (string=? (extract-dir-path (car stack)) "")))
            (let* ((parent-dir (extract-dir-path (car stack)))
                   (relative-path (string-append parent-dir path))
                   (p0 (open-input-file relative-path)))
              (if p0
                  (begin (close-input-port p0) relative-path)
                  (find-included-file path)))
            (find-included-file path)))))

(define (expand-includes-in-forms forms)
  (let loop ((fs forms) (acc '()))
    (if (null? fs)
        (reverse acc)
        (let ((f (car fs)))
          (cond
            ((include-form? f)
             (let ((included (slurp-included-files (cdr f))))
               (loop (append included (cdr fs)) acc)))
            ((and (source-loc? f) (include-form? (source-loc-form f)))
             (let ((included (slurp-included-files (cdr (source-loc-form f)))))
               (loop (append included (cdr fs)) acc)))
            (else
             (loop (cdr fs) (cons f acc))))))))

;;; File inclusion helper: safely read forms from given files
(define (slurp-included-files paths)
  (let loop ((ps paths) (acc '()))
    (if (null? ps)
        (reverse acc)
        (let ((forms (slurp-single-file (car ps))))
          (loop (cdr ps) (append (reverse forms) acc))))))

(define (read-datum-or-source-loc p path line)
  (let ((expr (read p)))
    (if (eof-object? expr)
        expr
        (list '%source-loc path line 1 expr))))

(define (slurp-single-file raw-path)
  (let ((path (resolve-include-path raw-path)))
    (if (member-string? path (car *include-path-stack*))
        (error "include: circular dependency detected" path)
        (let ((p (open-input-file path)))
          (if (not p)
              (error "include: failed to open source file" path)
              (begin
                (set-car! *include-path-stack* (cons path (car *include-path-stack*)))
                (let loop ((acc '()) (line 1))
                  (let ((expr (read-datum-or-source-loc p path line)))
                    (if (eof-object? expr)
                        (begin
                          (close-input-port p)
                          (set-car! *include-path-stack* (cdr (car *include-path-stack*)))
                          (expand-includes-in-forms (reverse acc)))
                        (loop (cons expr acc) (+ line 1)))))))))))

;;; -----------------------------------------------------------------------
;;; 3. Import-Set Resolution & Name Mapping
;;; -----------------------------------------------------------------------

;;; Given an import-set and the library registry alist:
;;; Returns (cons <library-name> <symbol-mapping>)
;;; where symbol-mapping is ((<exported-name> . <local-bound-name>) ...)
(define (resolve-import-set iset lib-registry)
  (cond
    ((null? iset) (cons '() '()))
    ((not (pair? iset)) (cons '() '()))

    ;; (only <import-set> <id> ...)
    ((eq? (car iset) 'only)
     (let* ((sub (resolve-import-set (cadr iset) lib-registry))
            (lib-name (car sub))
            (sub-map (cdr sub))
            (only-ids (cddr iset)))
       (cons lib-name
             (filter (lambda (entry) (memq (car entry) only-ids)) sub-map))))

    ;; (except <import-set> <id> ...)
    ((eq? (car iset) 'except)
     (let* ((sub (resolve-import-set (cadr iset) lib-registry))
            (lib-name (car sub))
            (sub-map (cdr sub))
            (except-ids (cddr iset)))
       (cons lib-name
             (filter (lambda (entry) (not (memq (car entry) except-ids))) sub-map))))

    ;; (prefix <import-set> <prefix-id>)
    ((eq? (car iset) 'prefix)
     (let* ((sub (resolve-import-set (cadr iset) lib-registry))
            (lib-name (car sub))
            (sub-map (cdr sub))
            (pfx-sym (caddr iset))
            (pfx-str (symbol->string pfx-sym)))
       (cons lib-name
             (map (lambda (entry)
                    (let* ((exp-name (car entry))
                           (loc-name (cdr entry))
                           (new-loc (string->symbol (string-append pfx-str (symbol->string loc-name)))))
                      (cons exp-name new-loc)))
                  sub-map))))

    ;; (rename <import-set> (<orig> <new>) ...)
    ((eq? (car iset) 'rename)
     (let* ((sub (resolve-import-set (cadr iset) lib-registry))
            (lib-name (car sub))
            (sub-map (cdr sub))
            (renames (cddr iset)))
       (cons lib-name
             (map (lambda (entry)
                    (let* ((exp-name (car entry))
                           (loc-name (cdr entry))
                           (rn (assoc loc-name renames)))
                      (if rn
                          (cons exp-name (cadr rn))
                          entry)))
                  sub-map))))

    ;; Library name: (ident ...)
    (else
     (let ((lib-name iset))
       (if (builtin-library-name? lib-name)
           (cons lib-name '())
           (let ((entry (assoc lib-name lib-registry)))
             (if entry
                 (let* ((rec (cdr entry))
                        (exports (lib-rec-exports rec))
                        (mapping (map (lambda (e) (cons (cdr e) (cdr e))) exports)))
                   (cons lib-name mapping))
                 ;; Library not found in current compilation unit
                 (cons lib-name '()))))))))

;;; -----------------------------------------------------------------------
;;; 4. Library Alpha-Renaming & Static Flattening
;;; -----------------------------------------------------------------------

;;; Rename symbols in an expression based on a substitution alist: ((orig . new) ...)
(define (alpha-rename-expr expr subst)
  (cond
    ((null? expr) '())
    ((symbol? expr)
     (let ((entry (assq expr subst)))
       (if entry (cdr entry) expr)))
    ((not (pair? expr))
     expr)
    ((eq? (car expr) 'quote)
     expr)
    ((eq? (car expr) 'define-syntax)
     ;; Do not rename the syntax-rules keyword/pattern structure, only the defined macro name
     (if (and (pair? (cdr expr)) (symbol? (cadr expr)))
         (let* ((orig-name (cadr expr))
                (entry (assq orig-name subst))
                (new-name (if entry (cdr entry) orig-name)))
           (cons 'define-syntax (cons new-name (cddr expr))))
         expr))
    ((eq? (car expr) 'define-record-type)
     ;; (define-record-type <name> (<ctor> <ctor-args> ...) <pred> (<f> <getter> [<setter>]) ...)
     (let* ((type-name (cadr expr))
            (ctor-spec (caddr expr))
            (ctor-name (if (pair? ctor-spec) (car ctor-spec) ctor-spec))
            (ctor-args (if (pair? ctor-spec) (cdr ctor-spec) '()))
            (new-ctor-name (let ((e (assq ctor-name subst))) (if e (cdr e) ctor-name)))
            (pred-name (cadddr expr))
            (new-pred-name (let ((e (assq pred-name subst))) (if e (cdr e) pred-name)))
            (field-specs (cddddr expr))
            (new-field-specs
             (map (lambda (spec)
                    (let* ((fname (car spec))
                           (getter (cadr spec))
                           (new-getter (let ((e (assq getter subst))) (if e (cdr e) getter)))
                           (has-setter? (pair? (cddr spec))))
                      (if has-setter?
                          (let* ((setter (caddr spec))
                                 (new-setter (let ((e (assq setter subst))) (if e (cdr e) setter))))
                            (list fname new-getter new-setter))
                          (list fname new-getter))))
                  field-specs)))
       (cons 'define-record-type
             (cons type-name
                   (cons (cons new-ctor-name ctor-args)
                         (cons new-pred-name new-field-specs))))))
    ((eq? (car expr) 'define-values)
     (let* ((formals (cadr expr))
            (body-expr (caddr expr))
            (new-formals (alpha-rename-expr formals subst))
            (new-body (alpha-rename-expr body-expr subst)))
       (list 'define-values new-formals new-body)))
    (else
     (cons (alpha-rename-expr (car expr) subst)
           (alpha-rename-expr (cdr expr) subst)))))

;;; Extract all defined variable/macro names from a body of definitions
(define (extract-defined-names-in-body body-forms)
  (let loop ((rest body-forms) (acc '()))
    (if (null? rest)
        (reverse acc)
        (let ((form (car rest)))
          (cond
            ((and (pair? form) (eq? (car form) 'define) (pair? (cdr form)))
             (let ((def-target (cadr form)))
               (if (pair? def-target)
                   (loop (cdr rest) (cons (car def-target) acc))
                   (loop (cdr rest) (cons def-target acc)))))
            ((and (pair? form) (eq? (car form) 'define-values) (pair? (cdr form)))
             (let ((formals (cadr form)))
               (let formal-loop ((fs formals) (f-acc acc))
                 (cond
                   ((null? fs) (loop (cdr rest) f-acc))
                   ((pair? fs) (formal-loop (cdr fs) (cons (car fs) f-acc)))
                   ((symbol? fs) (loop (cdr rest) (cons fs f-acc)))
                   (else (loop (cdr rest) f-acc))))))
            ((and (pair? form) (eq? (car form) 'define-syntax) (pair? (cdr form)))
             (loop (cdr rest) (cons (cadr form) acc)))
            ((and (pair? form) (eq? (car form) 'define-record-type) (pair? (cdr form)))
             (let* ((ctor-spec (caddr form))
                    (ctor-name (if (pair? ctor-spec) (car ctor-spec) ctor-spec))
                    (pred-name (cadddr form))
                    (field-specs (cddddr form))
                    (acc1 (cons pred-name (cons ctor-name acc))))
               (let field-loop ((specs field-specs) (acc2 acc1))
                 (if (null? specs)
                     (loop (cdr rest) acc2)
                     (let* ((spec (car specs))
                            (getter (cadr spec))
                            (has-setter? (pair? (cddr spec)))
                            (acc3 (cons getter acc2))
                            (acc4 (if has-setter? (cons (caddr spec) acc3) acc3)))
                       (field-loop (cdr specs) acc4))))))
            (else
             (loop (cdr rest) acc)))))))

;;; Flatten a library definition into a sequence of namespaced top-level forms
;;; Returns (values internal-defs export-aliases)
;;; where export-aliases is ((<exported-public-name> . <namespaced-internal-name>) ...)
(define (instantiate-library lib-rec)
  (let* ((lib-name (lib-rec-name lib-rec))
         (prefix-str (library-name->prefix-str lib-name))
         (exports (lib-rec-exports lib-rec)) ; list of (internal-orig . exported-public)
         (body (lib-rec-body lib-rec))
         (defined-names (extract-defined-names-in-body body)))

    ;; Build substitution mapping for ALL defined names:
    ;; orig-name -> <prefix-str>_orig-name
    (let* ((subst
            (map (lambda (name)
                   (cons name (string->symbol (string-append prefix-str (symbol->string name)))))
                 defined-names))
           ;; Transform the body forms with the substitution mapping
           (renamed-body
            (map (lambda (f) (alpha-rename-expr f subst)) body))
           ;; Build export alias mapping: (exported-public . namespaced-internal-name)
           (export-aliases
            (map (lambda (e)
                   (let* ((internal-orig (car e))
                          (exported-public (cdr e))
                          (entry (assq internal-orig subst))
                          (namespaced-name (if entry (cdr entry) internal-orig)))
                     (cons exported-public namespaced-name)))
                 exports)))
      (cons renamed-body export-aliases))))

;;; -----------------------------------------------------------------------
;;; 5. Main Desugaring Entrypoint: desugar-libraries-and-imports
;;; -----------------------------------------------------------------------

;;; Traverses raw top-level forms:
;;; 1. Collects all (define-library ...) declarations into a registry
;;; 2. Instantiates imported libraries on demand, deduplicating them
;;; 3. Emits namespaced definitions and local binding aliases
;;; Returns a flat list of Scheme forms ready for macro expansion (Pass 00b).
(define (desugar-libraries-and-imports forms)
  ;; Pre-Step: Expand all top-level (include ...) forms recursively
  (let ((all-forms (expand-includes-in-forms forms)))
    ;; Step 1: Extract all library definitions into an alist: ((name . lib-rec) ...)
    (let loop-collect ((rest all-forms) (registry '()) (non-lib-forms '()))
      (if (not (null? rest))
          (let ((f (car rest)))
            (if (define-library-form? (strip-source-loc f))
                (let* ((actual-f (strip-source-loc f))
                       (rec (parse-define-library-form actual-f))
                       (name (lib-rec-name rec)))
                  (loop-collect (cdr rest) (cons (cons name rec) registry) non-lib-forms))
                (loop-collect (cdr rest) registry (cons f non-lib-forms))))

        ;; Step 2: Expand all imports and emit flat forms
        (let ((clean-forms (reverse non-lib-forms)))
          (let loop-expand ((fs clean-forms)
                            (instantiated-libs '())
                            (lib-aliases '())
                            (out-forms '()))
            (if (null? fs)
                (reverse out-forms)
                (let ((f (car fs)))
                  (if (import-form? f)
                      ;; Process (import iset ...)
                      (let loop-isets ((isets (cdr f))
                                       (cur-inst instantiated-libs)
                                       (cur-aliases lib-aliases)
                                       (acc-forms out-forms))
                        (if (null? isets)
                            (loop-expand (cdr fs) cur-inst cur-aliases acc-forms)
                            (let* ((iset (car isets))
                                   (res (resolve-import-set iset registry))
                                   (lib-name (car res))
                                   (sym-map (cdr res)))
                              (if (or (null? lib-name) (builtin-library-name? lib-name))
                                  (loop-isets (cdr isets) cur-inst cur-aliases acc-forms)
                                  (let* ((already-inst (assoc lib-name cur-aliases))
                                         (inst-info
                                          (if already-inst
                                              (cons (car already-inst) (cdr already-inst))
                                              (let ((lib-entry (assoc lib-name registry)))
                                                (if lib-entry
                                                    (let* ((rec (cdr lib-entry))
                                                           (inst-res (instantiate-library rec))
                                                           (lib-defs (car inst-res))
                                                           (aliases (cdr inst-res)))
                                                      (cons lib-defs aliases))
                                                    (cons '() '())))))
                                         (new-defs (if already-inst '() (car inst-info)))
                                         (export-aliases (if already-inst (cdr already-inst) (cdr inst-info)))
                                         (updated-aliases (if already-inst
                                                              cur-aliases
                                                              (cons (cons lib-name export-aliases) cur-aliases)))
                                         (updated-inst (if (memq lib-name cur-inst)
                                                           cur-inst
                                                           (cons lib-name cur-inst)))
                                         (alias-bindings
                                          (map (lambda (entry)
                                                 (let* ((exp-name (car entry))
                                                        (loc-name (cdr entry))
                                                        (ea (assq exp-name export-aliases)))
                                                   (if ea
                                                       (list 'define loc-name (cdr ea))
                                                       #f)))
                                               sym-map))
                                         (valid-bindings (filter (lambda (b) (pair? b)) alias-bindings)))
                                    (loop-isets (cdr isets)
                                                updated-inst
                                                updated-aliases
                                                (append (reverse valid-bindings)
                                                        (append (reverse new-defs) acc-forms))))))))
                      ;; Normal non-import form
                      (loop-expand (cdr fs)
                                   instantiated-libs
                                   lib-aliases
                                   (cons f out-forms)))))))))))
;;; =======================================================================
;;; ULisp Compiler Pass 015: Nanopass DSL Procedural Expander
;;; Conforms to DSN-33 Architecture Specification & Issue #587
;;;
;;; Pre-emptively expands Nanopass DSL forms (define-language, define-pass,
;;; define-parser, define-unparser) into canonical Scheme definitions
;;; before syntax-rules macro expansion (Pass 020). Also filters out
;;; host-only define-macro declarations to keep downstream passes pure.
;;; =======================================================================

(define (expand-dsl-forms forms)
  (let loop ((fs forms) (res '()))
    (if (null? fs)
        (reverse res)
        (let ((f (car fs)))
          (cond
            ((and (pair? f) (eq? (car f) '%source-loc))
             (let ((file (cadr f))
                   (line (caddr f))
                   (col (cadddr f))
                   (inner (car (cddddr f))))
               (cond
                 ((and (pair? inner) (memq (car inner) '(define-language define-pass trace-define-pass define-parser define-unparser)))
                  (let ((exp-inner (expand-dsl-forms (list inner))))
                    (loop (append (map (lambda (x) (list '%source-loc file line col x)) exp-inner)
                                  (cdr fs))
                          res)))
                 ((and (pair? inner) (eq? (car inner) 'define-macro))
                  (loop (cdr fs) res))
                 (else
                  (loop (cdr fs) (cons f res))))))
            ((and (pair? f) (eq? (car f) 'begin))
             (loop (append (cdr f) (cdr fs)) res))
            ((and (pair? f) (eq? (car f) 'define-macro))
             ;; Discard host-only macro definitions in compiler pipeline
             (loop (cdr fs) res))
            ((and (pair? f) (eq? (car f) 'define-language))
             (let ((expanded (nanopass-expand-define-language f)))
               (loop (append (if (and (pair? expanded) (eq? (car expanded) 'begin))
                                 (cdr expanded)
                                 (list expanded))
                             (cdr fs))
                     res)))
            ((and (pair? f) (eq? (car f) 'define-pass))
             (let ((expanded (nanopass-expand-define-pass f)))
               (loop (append (if (and (pair? expanded) (eq? (car expanded) 'begin))
                                 (cdr expanded)
                                 (list expanded))
                             (cdr fs))
                     res)))
            ((and (pair? f) (eq? (car f) 'trace-define-pass))
             (let ((expanded (nanopass-expand-trace-define-pass f)))
               (loop (append (if (and (pair? expanded) (eq? (car expanded) 'begin))
                                 (cdr expanded)
                                 (list expanded))
                             (cdr fs))
                     res)))
            ((and (pair? f) (eq? (car f) 'define-parser))
             (let ((expanded (nanopass-expand-define-parser f)))
               (loop (cons expanded (cdr fs)) res)))
            ((and (pair? f) (eq? (car f) 'define-unparser))
             (let ((expanded (nanopass-expand-define-unparser f)))
               (loop (cons expanded (cdr fs)) res)))
            (else
             (loop (cdr fs) (cons f res))))))))
;;; =======================================================================
;;; ULisp Compiler Pass 0b: Hygienic syntax-rules Macro Expander
;;; Conforms to DSN-33 Architecture Specification & Issue #533 (R7RS 4.3)
;;;
;;; Provides self-contained compile-time hygienic macro expansion
;;; without relying on host runtime eval. Fully operational in both host
;;; Scheme (ILisp) and self-hosted native AOT binaries (Stage 1/2/3).
;;; =======================================================================

;;; -----------------------------------------------------------------------
;;; 1. Hygiene & Unique Identifier Generation
;;; -----------------------------------------------------------------------

(define *hygiene-counter* (cons 0 '()))

(define (reset-hygiene-counter!)
  (set-car! *hygiene-counter* 0))

(define (hygiene-gensym sym)
  (let ((cnt (car *hygiene-counter*)))
    (set-car! *hygiene-counter* (+ cnt 1))
    (string->symbol (string-append "__hyg_" (symbol->string sym) "_" (number->string cnt)))))

;;; Built-in core keywords and primitives that must NOT be renamed during hygienic expansion
(define (core-form-or-primitive? sym)
  (memq sym '(if begin lambda let let* letrec quote set! define define-values define-syntax syntax-rules define-record-type
              cond case and or when unless delay delay-force do
              cons car cdr pair? null? list append not eq? eqv? equal?
              list-copy make-list
              vector vector-ref vector-set! vector-length make-vector vector-copy vector-copy! vector-append vector-fill! vector-map vector-for-each vector->list list->vector vector->string vector->string-range
              string string-ref string-set! string-length make-string string-append string-copy string-copy! string-fill! string-map string-for-each substring string=? string<? string>? string<=? string>=? string->symbol symbol->string string->list string->list-range list->string string->vector string->vector-range
              bytevector bytevector-u8-ref bytevector-u8-set! bytevector-length make-bytevector bytevector-copy bytevector-copy! bytevector-append bytevector=?
              + - * = < > <= >= modulo quotient / square remainder gcd gcd-2 lcm lcm-2 expt %math-abs
              zero? fixnum? integer? number? exact? exact-integer? inexact? real? rational? complex?
              boolean? char? symbol? string? list? vector? bytevector?
              write-char %write-char write-string %write-string read-char %read-char peek-char %peek-char eof-object?
              values call-with-values dynamic-wind call/cc call-with-current-continuation
              guard raise %raw-call/cc %with-handler)))

;;; -----------------------------------------------------------------------
;;; 2. Pattern Matching Utilities
;;; -----------------------------------------------------------------------

(define (ellipsis? x)
  (and (symbol? x) (eq? x '...)))

(define (underscore? x)
  (and (symbol? x) (eq? x '_)))

(define (literal? sym literals)
  (and (symbol? sym) (memq sym literals)))

;;; Extract all pattern variables from a pattern
(define (extract-pattern-vars pat literals)
  (cond
    ((null? pat) '())
    ((underscore? pat) '())
    ((ellipsis? pat) '())
    ((symbol? pat)
     (if (literal? pat literals)
         '()
         (list pat)))
    ((pair? pat)
     (append (extract-pattern-vars (car pat) literals)
             (extract-pattern-vars (cdr pat) literals)))
    (else '())))

;;; Compute length of a proper or dotted list
(define (pattern-length p)
  (let loop ((cur p) (len 0))
    (cond
      ((null? cur) len)
      ((pair? cur) (loop (cdr cur) (+ len 1)))
      (else (+ len 1)))))

;;; Match a single element pattern against input
(define (match-element pat input literals env)
  (cond
    ((underscore? pat)
     (cons #t env))
    ((literal? pat literals)
     (if (and (symbol? input) (eq? pat input))
         (cons #t env)
         (cons #f '())))
    ((symbol? pat)
     (cons #t (cons (cons pat input) env)))
    ((pair? pat)
     (if (pair? input)
         (match-pattern-sequence pat input literals env)
         (cons #f '())))
    (else
     (if (equal? pat input)
         (cons #t env)
         (cons #f '())))))

;;; Match a sequence of pattern elements against input list
(define (match-pattern-sequence pat input literals env)
  (cond
    ((and (null? pat) (null? input))
     (cons #t env))
    ((null? pat)
     (cons #f '()))
    ((not (pair? pat))
     ;; Dotted tail match
     (match-element pat input literals env))
    ;; Ellipsis pattern: (elem ... . rest-pat)
    ((and (pair? (cdr pat)) (ellipsis? (cadr pat)))
     (let* ((elem-pat (car pat))
            (rest-pat (cddr pat))
            (elem-vars (extract-pattern-vars elem-pat literals))
            (min-rest-len (length (if (pair? rest-pat) rest-pat '())))
            (input-len (if (list? input) (length input) 0)))
       (if (< input-len min-rest-len)
           (cons #f '())
           (let* ((num-ellipsis (- input-len min-rest-len))
                  ;; Split input into ellipsis items and rest items
                  (ellipsis-items (let take ((n num-ellipsis) (cur input))
                                    (if (<= n 0) '()
                                        (cons (car cur) (take (- n 1) (cdr cur))))))
                  (rest-items (let drop ((n num-ellipsis) (cur input))
                                (if (<= n 0) cur
                                    (drop (- n 1) (cdr cur))))))
             ;; Match each ellipsis item against elem-pat
             (let loop ((items ellipsis-items) (matched-envs '()))
               (if (null? items)
                   ;; Aggregate matched variables into lists
                   (let* ((agg-bindings
                           (map (lambda (var)
                                  (cons var
                                        (map (lambda (sub-env)
                                               (let ((p (assq var sub-env)))
                                                 (if p (cdr p) #f)))
                                             (reverse matched-envs))))
                                elem-vars))
                          (env-with-ellipsis (append agg-bindings env)))
                     ;; Match rest of pattern
                     (match-pattern-sequence rest-pat rest-items literals env-with-ellipsis))
                   (let ((sub-match (match-element elem-pat (car items) literals '())))
                     (if (car sub-match)
                         (loop (cdr items) (cons (cdr sub-match) matched-envs))
                         (cons #f '())))))))))
    ;; Normal element
    ((pair? input)
     (let ((head-match (match-element (car pat) (car input) literals env)))
       (if (car head-match)
           (match-pattern-sequence (cdr pat) (cdr input) literals (cdr head-match))
           (cons #f '()))))
    (else
     (cons #f '()))))

;;; Match an entire macro pattern against input form
;;; Pattern starts with keyword or underscore: (_ a b ...)
(define (match-macro-pattern pat input literals)
  (if (and (pair? pat) (pair? input))
      (match-pattern-sequence (cdr pat) (cdr input) literals '())
      (cons #f '())))

;;; -----------------------------------------------------------------------
;;; 3. Template Expansion and Hygienic Renaming
;;; -----------------------------------------------------------------------

(define (extract-formals formals pat-vars)
  (cond
    ((null? formals) '())
    ((symbol? formals)
     (if (memq formals pat-vars) '() (list formals)))
    ((pair? formals)
     (append (extract-formals (car formals) pat-vars)
             (extract-formals (cdr formals) pat-vars)))
    (else '())))

(define (extract-binding-vars bindings pat-vars)
  (cond
    ((null? bindings) '())
    ((pair? bindings)
     (let ((b (car bindings)))
       (append (if (and (pair? b) (symbol? (car b)) (not (memq (car b) pat-vars)))
                   (list (car b))
                   '())
               (extract-binding-vars (cdr bindings) pat-vars))))
    (else '())))

;;; Collect all variables introduced by binding forms in a template that need renaming (macro-introduced local identifiers)
(define (collect-template-binders tmpl pat-vars literals)
  (cond
    ((not (pair? tmpl)) '())
    ((eq? (car tmpl) 'quote) '())
    ;; (lambda <formals> <body> ...)
    ((and (eq? (car tmpl) 'lambda) (pair? (cdr tmpl)))
     (let ((formals (cadr tmpl))
           (body (cddr tmpl)))
       (append (extract-formals formals pat-vars)
               (collect-template-binders body pat-vars literals))))
    ;; (let ((<var> <init>) ...) <body> ...)
    ;; or named let: (let <name> ((<var> <init>) ...) <body> ...)
    ((and (memq (car tmpl) '(let let* letrec)) (pair? (cdr tmpl)))
     (cond
       ;; named let: (let <name> ((<var> <init>) ...) ...)
       ((and (eq? (car tmpl) 'let) (symbol? (cadr tmpl)) (pair? (cddr tmpl)))
        (let ((name (cadr tmpl))
              (bindings (caddr tmpl))
              (body (cdddr tmpl)))
          (append (if (memq name pat-vars) '() (list name))
                  (append (extract-binding-vars bindings pat-vars)
                          (append (collect-template-binders bindings pat-vars literals)
                                  (collect-template-binders body pat-vars literals))))))
       ;; normal let / let* / letrec: (let ((<var> <init>) ...) ...)
       ((pair? (cdr tmpl))
        (let ((bindings (cadr tmpl))
              (body (cddr tmpl)))
          (append (extract-binding-vars bindings pat-vars)
                  (append (collect-template-binders bindings pat-vars literals)
                          (collect-template-binders body pat-vars literals)))))
       (else '())))
    (else
     (append (collect-template-binders (car tmpl) pat-vars literals)
             (collect-template-binders (cdr tmpl) pat-vars literals)))))

(define (remove-duplicates ls)
  (let loop ((cur ls) (res '()))
    (cond
      ((null? cur) (reverse res))
      ((memq (car cur) res) (loop (cdr cur) res))
      (else (loop (cdr cur) (cons (car cur) res))))))

;;; Expand a template with given pattern environment and renaming map
(define (expand-template tmpl env literals rename-map)
  (cond
    ((null? tmpl) '())
    ((symbol? tmpl)
     (let ((p (assq tmpl env)))
       (if p
           (cdr p)
           (let ((r (assq tmpl rename-map)))
             (if r
                 (cdr r)
                 tmpl)))))
    ((pair? tmpl)
     (cond
       ;; Quote remains untransformed except for variables if not pure
       ((eq? (car tmpl) 'quote)
        tmpl)
       ;; Ellipsis repetition in template: (elem ... . rest)
       ((and (pair? (cdr tmpl)) (ellipsis? (cadr tmpl)))
        (let* ((elem-tmpl (car tmpl))
               (rest-tmpl (cddr tmpl))
               ;; Find variables used in elem-tmpl that are lists in env
               (vars-in-elem (remove-duplicates (extract-pattern-vars elem-tmpl literals)))
               (ellipsis-vars (filter (lambda (v)
                                        (let ((p (assq v env)))
                                          (and p (list? (cdr p)))))
                                      vars-in-elem)))
          (if (null? ellipsis-vars)
              ;; Zero repetitions or non-ellipsis variable
              (expand-template rest-tmpl env literals rename-map)
              (let* ((first-v (car ellipsis-vars))
                     (repeat-count (length (cdr (assq first-v env))))
                     (repeated-elements
                      (let loop ((i 0) (acc '()))
                        (if (>= i repeat-count)
                            (reverse acc)
                            (let* ((sub-env
                                    (map (lambda (v)
                                           (cons v (list-ref (cdr (assq v env)) i)))
                                         ellipsis-vars))
                                   (merged-env (append sub-env env))
                                   (expanded-elem (expand-template elem-tmpl merged-env literals rename-map)))
                              (loop (+ i 1) (cons expanded-elem acc)))))))
                (append repeated-elements (expand-template rest-tmpl env literals rename-map))))))
       (else
        (cons (expand-template (car tmpl) env literals rename-map)
              (expand-template (cdr tmpl) env literals rename-map)))))
    (else tmpl)))

;;; -----------------------------------------------------------------------
;;; 4. syntax-rules Macro Transformer
;;; -----------------------------------------------------------------------

;;; Representation: ('syntax-rules-macro name literals rules)
;;; rule: (pattern template)
(define (syntax-rules-macro? obj)
  (and (pair? obj) (eq? (car obj) 'syntax-rules-macro)))

(define (macro-name m) (cadr m))
(define (macro-literals m) (caddr m))
(define (macro-rules m) (cadddr m))

(define (apply-syntax-rules-macro m input)
  (let ((literals (macro-literals m))
        (rules (macro-rules m)))
    (let loop ((rls rules))
      (if (null? rls)
          (error "apply-syntax-rules-macro: no matching syntax-rules pattern for" input)
          (let* ((rule (car rls))
                 (pat (car rule))
                 (tmpl (cadr rule))
                 (match-res (match-macro-pattern pat input literals)))
            (if (car match-res)
                (let* ((env (cdr match-res))
                       (pat-vars (extract-pattern-vars pat literals))
                       (binders-to-rename (remove-duplicates (collect-template-binders tmpl pat-vars literals)))
                       (rename-map (map (lambda (s) (cons s (hygiene-gensym s))) binders-to-rename)))
                  (expand-template tmpl env literals rename-map))
                (loop (cdr rls))))))))

;;; -----------------------------------------------------------------------
;;; 5. Macro Definition Parsing and Top-level Expansion Pass
;;; -----------------------------------------------------------------------

(define (macro-def? form)
  (and (pair? form)
       (eq? (car form) 'define-syntax)))

(define (parse-syntax-rules-def form)
  ;; (define-syntax <name> (syntax-rules (<literal> ...) (<pattern> <template>) ...))
  (if (and (pair? (cdr form))
           (symbol? (cadr form))
           (pair? (cddr form))
           (pair? (caddr form))
           (eq? (car (caddr form)) 'syntax-rules))
      (let* ((name (cadr form))
             (sr-spec (caddr form))
             (literals (cadr sr-spec))
             (rules (cddr sr-spec)))
        (list 'syntax-rules-macro name literals rules))
      (error "parse-syntax-rules-def: invalid define-syntax syntax" form)))

(define (macro-expand-1 expr macro-table)
  (if (and (pair? expr) (symbol? (car expr)))
      (let ((entry (assq (car expr) macro-table)))
        (if entry
            (let* ((macro-desc (cdr entry))
                   (expanded (apply-syntax-rules-macro macro-desc expr)))
              (cons #t expanded))
            (cons #f expr)))
      (cons #f expr)))

(define (macro-expand-top-expr expr macro-table)
  (let ((res (macro-expand-1 expr macro-table)))
    (if (car res)
        (macro-expand-top-expr (cdr res) macro-table)
        (cdr res))))

(define (safe-macro-expand-list ls macro-table)
  (let loop ((cur ls) (acc (quote ())))
    (cond
      ((null? cur) (reverse acc))
      ((not (pair? cur)) (append (reverse acc) (macro-expand-all cur macro-table)))
      (else
       (loop (cdr cur) (cons (macro-expand-all (car cur) macro-table) acc))))))

;;; Expand case clauses: datum lists (and `else`) are preserved verbatim,
;;; only clause bodies are macro-expanded.
(define (safe-macro-expand-case-clauses clauses macro-table)
  (let loop ((cur clauses) (acc (quote ())))
    (cond
      ((null? cur) (reverse acc))
      ((not (pair? cur)) (append (reverse acc) cur))
      ((pair? (car cur))
       (let ((clause (car cur)))
         (loop (cdr cur)
               (cons (cons (car clause)
                           (safe-macro-expand-list (cdr clause) macro-table))
                     acc))))
      (else
       (loop (cdr cur) (cons (car cur) acc))))))

(define (safe-macro-expand-bindings bs macro-table)
  (let loop ((cur bs) (acc (quote ())))
    (cond
      ((null? cur) (reverse acc))
      ((not (pair? cur)) (append (reverse acc) cur))
      ((pair? (car cur))
       (let* ((b (car cur))
              (var (car b))
              (val-exprs (safe-macro-expand-list (cdr b) macro-table)))
         (loop (cdr cur) (cons (cons var val-exprs) acc))))
      (else
       (loop (cdr cur) (cons (car cur) acc))))))

(define (macro-expand-all expr macro-table)
  (let ((expanded (macro-expand-top-expr expr macro-table)))
    (cond
      ((not (pair? expanded))
       expanded)
      ((eq? (car expanded) (quote quote))
       expanded)
      ((eq? (car expanded) (quote case))
       (if (and (pair? (cdr expanded)) (pair? (cddr expanded)))
           (cons (quote case)
                 (cons (macro-expand-all (cadr expanded) macro-table)
                       (safe-macro-expand-case-clauses (cddr expanded) macro-table)))
           expanded))
      ((eq? (car expanded) (quote lambda))
       (if (and (pair? (cdr expanded)) (pair? (cddr expanded)))
           (cons (quote lambda)
                 (cons (cadr expanded)
                       (safe-macro-expand-list (cddr expanded) macro-table)))
           expanded))
      ((eq? (car expanded) (quote define))
       (if (and (pair? (cdr expanded)) (pair? (cddr expanded)))
           (cons (quote define)
                 (cons (cadr expanded)
                       (safe-macro-expand-list (cddr expanded) macro-table)))
           expanded))
      ((eq? (car expanded) (quote define-record-type))
       expanded)
      ((or (eq? (car expanded) (quote let))
           (eq? (car expanded) (quote let*))
           (eq? (car expanded) (quote letrec)))
       (if (and (pair? (cdr expanded)) (symbol? (cadr expanded)))
           (if (and (pair? (cddr expanded)) (pair? (cdddr expanded)))
               (cons (car expanded)
                     (cons (cadr expanded)
                           (cons (safe-macro-expand-bindings (caddr expanded) macro-table)
                                 (safe-macro-expand-list (cdddr expanded) macro-table))))
               expanded)
           (if (and (pair? (cdr expanded)) (pair? (cddr expanded)))
               (cons (car expanded)
                     (cons (safe-macro-expand-bindings (cadr expanded) macro-table)
                           (safe-macro-expand-list (cddr expanded) macro-table)))
               expanded)))
      (else
       (safe-macro-expand-list expanded macro-table)))))


(define (expand-macros-in-forms forms)
  (let loop ((fs forms) (macro-table '()) (res '()))
    (if (null? fs)
        (reverse res)
        (let ((f (car fs)))
          (cond
            ((source-loc? f)
             (let* ((file (source-loc-file f))
                    (line (source-loc-line f))
                    (col (source-loc-col f))
                    (inner (source-loc-form f)))
               (if (macro-def? inner)
                   (let* ((macro-desc (parse-syntax-rules-def inner))
                          (name (macro-name macro-desc)))
                     (loop (cdr fs) (cons (cons name macro-desc) macro-table) res))
                   (let ((exp-f (macro-expand-all inner macro-table)))
                     (loop (cdr fs) macro-table (cons (list '%source-loc file line col exp-f) res))))))
            ((macro-def? f)
             (let* ((macro-desc (parse-syntax-rules-def f))
                    (name (macro-name macro-desc)))
               (loop (cdr fs) (cons (cons name macro-desc) macro-table) res)))
            (else
             (let ((exp-f (macro-expand-all f macro-table)))
               (loop (cdr fs) macro-table (cons exp-f res)))))))))

;;; =======================================================================
;;; ULisp Compiler Pass 025: Top-Level Definition Lifting & Normalization
;;; Conforms to DSN-33 Architecture Specification & Issue #570
;;; Hoists all top-level (define ...) forms into canonical (%program ...) AST.
;;; =======================================================================

(define (record-type-tag-symbol type-name)
  (string->symbol (string-append "%%record-type-" (symbol->string type-name))))

(define (expand-define-record-type form)
  ;; form: (define-record-type <name> (<ctor> <ctor-args> ...) <pred> <field-spec> ...)
  ;; each field-spec: (<fname> <getter>) or (<fname> <getter> <setter>)
  (let* ((type-name (cadr form))
         (ctor-spec (caddr form))
         (ctor-name (if (pair? ctor-spec) (car ctor-spec) ctor-spec))
         (ctor-args (if (pair? ctor-spec) (cdr ctor-spec) '()))
         (pred-name (cadddr form))
         (field-specs (cddddr form))
         (tag (record-type-tag-symbol type-name))
         (field-names (map car* field-specs)))
    (let* ((ctor-def
            (let ((vec-args
                   (map (lambda (f)
                          (if (memq f ctor-args)
                              f
                              #f))
                        field-names)))
              (list 'define (cons ctor-name ctor-args)
                    (cons 'vector (cons (list 'quote tag) vec-args)))))
           (pred-arg (unique-symbol "rec_"))
           (pred-def
            (list 'define (list pred-name pred-arg)
                  (list 'and
                        (list 'vector? pred-arg)
                        (list '> (list 'vector-length pred-arg) 0)
                        (list 'eq? (list 'vector-ref pred-arg 0) (list 'quote tag))))))
      (let loop ((specs field-specs) (idx 1) (acc (list ctor-def pred-def)))
        (if (null? specs)
            (reverse acc)
            (let* ((spec (car specs))
                   (fname (car spec))
                   (getter (cadr spec))
                   (has-setter? (pair? (cddr spec)))
                   (setter (if has-setter? (caddr spec) #f))
                   (get-arg (unique-symbol "rec_"))
                   (get-def (list 'define (list getter get-arg)
                                  (list 'vector-ref get-arg idx)))
                   (set-defs
                    (if has-setter?
                        (let ((set-arg (unique-symbol "rec_"))
                              (val-arg (unique-symbol "val_")))
                          (list (list 'define (list setter set-arg val-arg)
                                      (list 'vector-set! set-arg idx val-arg))))
                        '())))
              (loop (cdr specs)
                    (+ idx 1)
                    (append (reverse set-defs) (cons get-def acc)))))))))

(define (expand-define-values form)
  (let* ((formals (cadr form))
         (expr (caddr form)))
    (cond
      ((null? formals)
       (let ((dummy (unique-symbol "dummy_vals_")))
         (list (list 'define dummy
                     (list 'call-with-values
                           (list 'lambda '() expr)
                           (list 'lambda '() #f))))))
      ((and (pair? formals) (null? (cdr formals)))
       ;; Single formal: (define-values (x) expr)
       (let ((var (car formals)))
         (list (list 'define var
                     (list 'call-with-values
                           (list 'lambda '() expr)
                           (list 'lambda (list var) var))))))
      ((list? formals)
       ;; Proper list of formals: (define-values (x y ...) expr)
       (let* ((temp (unique-symbol "tmp_vals_"))
              (producer (list 'lambda '() expr))
              (consumer (list 'lambda formals (cons 'vector formals)))
              (temp-def (list 'define temp (list 'call-with-values producer consumer))))
         (let loop ((idx 0) (vars formals) (acc (list temp-def)))
           (if (null? vars)
               (reverse acc)
               (loop (+ idx 1)
                     (cdr vars)
                     (cons (list 'define (car vars)
                                 (list 'vector-ref temp idx))
                           acc))))))
      (else
       (error "define-values: invalid formals" formals)))))

(define (rewrite-top-level forms)
  (let loop ((fs forms) (defs '()) (bodies '()))
    (if (null? fs)
        (if (null? defs)
            (make-body-expr (reverse bodies))
            (let* ((rev-defs (reverse defs))
                   (unique-defs
                    (let dedup ((ds (reverse rev-defs)) (seen '()) (acc '()))
                      (if (null? ds)
                          acc
                          (let* ((d (car ds))
                                 (name (cadr d)))
                            (if (memq name seen)
                                (dedup (cdr ds) seen acc)
                                (dedup (cdr ds) (cons name seen) (cons d acc))))))))
              (list '%program unique-defs (make-body-expr (reverse bodies)))))
        (let ((f (car fs)))
          (if (pair? f)
              (set-current-form! f))
          (cond
            ((and (pair? f) (eq? (car f) '%source-loc))
             (let ((file (cadr f))
                   (line (caddr f))
                   (col (cadddr f))
                   (inner (car (cddddr f))))
               (set-current-source-file! file)
               (set-current-source-line! line)
               (set-current-source-col! col)
               (loop (cons inner (cdr fs)) defs bodies)))
            ((and (pair? f) (eq? (car f) 'begin))
             (loop (append (cdr f) (cdr fs)) defs bodies))
            ;; Skip compiler directives (!... or --...) appearing anywhere at top level
            ((or (and (pair? f)
                      (symbol? (car f))
                      (let ((s (symbol->string (car f))))
                        (or (string-starts-with? s "!")
                            (string-starts-with? s "--"))))
                 (and (symbol? f)
                      (let ((s (symbol->string f)))
                        (or (string-starts-with? s "!")
                            (string-starts-with? s "--")))))
             (loop (cdr fs) defs bodies))
            ((and (pair? f) (eq? (car f) 'define-record-type))
             (set-current-toplevel-name! (cadr f))
             (let ((expanded-defs (expand-define-record-type f)))
               (loop (append expanded-defs (cdr fs)) defs bodies)))
            ((and (pair? f) (eq? (car f) 'define-values))
             (set-current-toplevel-name! 'define-values)
             (let ((expanded-defs (expand-define-values f)))
               (loop (append expanded-defs (cdr fs)) defs bodies)))
            ((and (pair? f) (eq? (car f) 'define))
             (let ((def-spec (cadr f)))
               (if (pair? def-spec)
                   ;; (define (name . params) . body)
                   (let ((name (car def-spec))
                         (params (cdr def-spec))
                         (lbody (cddr f)))
                     (set-current-toplevel-name! name)
                     (loop (cdr fs)
                           (cons (list 'define name (cons 'lambda (cons params lbody))) defs)
                           bodies))
                   ;; (define name val)
                   (let ((name def-spec)
                         (val (caddr f)))
                     (set-current-toplevel-name! name)
                     (loop (cdr fs)
                           (cons (list 'define name val) defs)
                           bodies)))))
            (else
             ;; Normal expression
             (set-current-toplevel-name! '%main)
             (loop (cdr fs) defs (cons f bodies))))))))
;;; =======================================================================
;;; ULisp Compiler Pass 026: Constructor Desugaring Pass
;;; Conforms to DSN-33 Architecture Specification & Nanopass Standard
;;; Desugars composite literal constructors (list, vector, bytevector, string-append)
;;; =======================================================================

(define (desugar-list args)
  (if (null? args)
      ''()
      (cons 'cons (cons (car args) (cons (desugar-list (cdr args)) '())))))

(define (desugar-string-append args)
  (cond
    ((null? args) "")
    ((null? (cdr args)) (car args))
    ((null? (cddr args)) (list 'string-append2 (car args) (cadr args)))
    (else
     ;; Split args into two halves to keep tree depth O(log N)
     (let* ((len (length args))
            (half (quotient len 2)))
       (let loop ((rest args) (i 0) (left '()))
         (if (< i half)
             (loop (cdr rest) (+ i 1) (cons (car rest) left))
             (list 'string-append2
                   (desugar-string-append (reverse left))
                   (desugar-string-append rest))))))))

(define (desugar-bytevector args)
  (let* ((len (length args))
         (bv-sym (unique-symbol "bv_")))
    (let loop ((rest args) (idx 0) (sets '()))
      (if (null? rest)
          (list 'let (list (list bv-sym (list '%make-bytevector len)))
                (cons 'begin (reverse (cons bv-sym sets))))
          (loop (cdr rest)
                (+ idx 1)
                (cons (list 'bytevector-u8-set! bv-sym idx (car rest)) sets))))))

(define (desugar-bytevector-append args)
  (cond
    ((null? args) (list '%make-bytevector 0))
    ((null? (cdr args)) (car args))
    ((null? (cddr args)) (list 'bytevector-append2 (car args) (cadr args)))
    (else
     (let* ((len (length args))
            (half (quotient len 2)))
       (let loop ((rest args) (i 0) (left '()))
         (if (< i half)
             (loop (cdr rest) (+ i 1) (cons (car rest) left))
             (list 'bytevector-append2
                   (desugar-bytevector-append (reverse left))
                   (desugar-bytevector-append rest))))))))

(define (desugar-vector args)
  (let* ((len (length args))
         (vec-sym (unique-symbol "vec_")))
    (let loop ((rest args) (idx 0) (sets '()))
      (if (null? rest)
          (list 'let (list (list vec-sym (list '%make-vector len)))
                (cons 'begin (reverse (cons vec-sym sets))))
          (loop (cdr rest)
                (+ idx 1)
                (cons (list 'vector-set! vec-sym idx (car rest)) sets))))))

(define (desugar-vector-append args)
  (cond
    ((null? args) (list '%make-vector 0))
    ((null? (cdr args)) (car args))
    ((null? (cddr args)) (list 'vector-append2 (car args) (cadr args)))
    (else
     (let* ((len (length args))
            (half (quotient len 2)))
       (let loop ((rest args) (i 0) (left '()))
         (if (< i half)
             (loop (cdr rest) (+ i 1) (cons (car rest) left))
             (list 'vector-append2
                   (desugar-vector-append (reverse left))
                   (desugar-vector-append rest))))))))

;;; -----------------------------------------------------------------------
;;; Nanopass DSL Pass Definition: Desugar Constructors
;;; -----------------------------------------------------------------------
(define-pass desugar-constructors : L_src (ir) -> L_core ()
  (Expr : Expr (ir) -> Expr ()
    ((list . ,args) (desugar-list (map Expr args)))
    ((string-append . ,args) (desugar-string-append (map Expr args)))
    ((vector . ,args) (desugar-vector (map Expr args)))
    ((vector-append . ,args) (desugar-vector-append (map Expr args)))
    ((bytevector . ,args) (desugar-bytevector (map Expr args)))
    ((bytevector-append . ,args) (desugar-bytevector-append (map Expr args)))))
;;; =======================================================================
;;; ULisp Compiler Pass 027: Conditionals Desugaring Pass
;;; Conforms to DSN-33 Architecture Specification & Nanopass Standard
;;; Desugars conditional branching constructs (cond, case, and, or, chain comparisons)
;;; =======================================================================

(define (desugar-cond clauses)
  (if (or (null? clauses) (not (pair? clauses)))
      #f
      (let ((c (car clauses)))
        (cond
          ((not (pair? c))
           (desugar-cond (cdr clauses)))
          ((eq? (car c) 'else)
           (cons 'begin (cdr c)))
          ((and (pair? (cdr c)) (eq? (cadr c) '=>))
           (let ((tmp (unique-symbol "cond_tmp_")))
             (list 'let (list (list tmp (car c)))
                   (list 'if tmp
                         (list (caddr c) tmp)
                         (desugar-cond (cdr clauses))))))
          (else
           (list 'if (car c)
                 (cons 'begin (cdr c))
                 (desugar-cond (cdr clauses))))))))

(define (desugar-case-test k-var datum-list)
  (cond
    ((null? datum-list) #f)
    ((not (pair? datum-list))
     (list 'eqv? k-var (list 'quote datum-list)))
    ((null? (cdr datum-list))
     (list 'eqv? k-var (list 'quote (car datum-list))))
    (else
     (cons 'or (map (lambda (d) (list 'eqv? k-var (list 'quote d))) datum-list)))))

(define (desugar-case key clauses)
  (let ((k-var (unique-symbol "case_key_")))
    (list 'let (list (list k-var key))
          (let loop ((cls clauses))
            (if (or (null? cls) (not (pair? cls)))
                #f
                (let ((c (car cls)))
                  (if (not (pair? c))
                      (loop (cdr cls))
                      (if (eq? (car c) 'else)
                          (cons 'begin (cdr c))
                          (list 'if (desugar-case-test k-var (car c))
                                (cons 'begin (cdr c))
                                (loop (cdr cls)))))))))))

(define (desugar-and args)
  (cond
    ((null? args) #t)
    ((not (pair? args)) args)
    ((null? (cdr args)) (car args))
    (else
     (list 'if (car args) (desugar-and (cdr args)) #f))))

(define (desugar-or args)
  (cond
    ((null? args) #f)
    ((not (pair? args)) args)
    ((null? (cdr args)) (car args))
    (else
     (let ((tmp (unique-symbol "or_tmp_")))
       (list 'let (list (list tmp (car args)))
             (list 'if tmp tmp (desugar-or (cdr args))))))))

(define (desugar-chain-cmp op args)
  (cond
    ((null? args) #t)
    ((not (pair? args)) #t)
    ((null? (cdr args)) #t)
    ((null? (cddr args))
     (cons op (map desugar-all args)))
    (else
     (let* ((vars (map (lambda (a) (unique-symbol "cmp_")) args))
            (bindings (let b-loop ((vs vars) (as args))
                        (if (or (null? vs) (not (pair? vs)))
                            '()
                            (cons (list (car vs) (desugar-all (car as)))
                                  (b-loop (cdr vs) (cdr as))))))
            (pairs (let loop ((vs vars))
                     (if (or (null? (cdr vs)) (not (pair? (cdr vs))))
                         '()
                         (cons (list op (car vs) (cadr vs))
                               (loop (cdr vs)))))))
        (list 'let bindings
              (cons 'and pairs))))))

;;; -----------------------------------------------------------------------
;;; Nanopass DSL Pass Definition: Desugar Conditionals
;;; -----------------------------------------------------------------------
(define-pass desugar-conditionals : L_src (ir) -> L_core ()
  (Expr : Expr (ir) -> Expr ()
    ((cond ,clauses ...) (Expr (desugar-cond clauses)))
    ((cond . ,clauses) (Expr (desugar-cond clauses)))
    ((case ,key ,clauses ...) (Expr (desugar-case key clauses)))
    ((case ,key . ,clauses) (Expr (desugar-case key clauses)))
    ((and ,args ...) (Expr (desugar-and args)))
    ((and . ,args) (Expr (desugar-and args)))
    ((or ,args ...) (Expr (desugar-or args)))
    ((or . ,args) (Expr (desugar-or args)))))
;;; =======================================================================
;;; ULisp Compiler Pass 028: Local Bindings Desugaring Pass
;;; Conforms to DSN-33 Architecture Specification & Nanopass Standard
;;; Desugars local binding constructs (let*, named let) and body sequences
;;; =======================================================================

(define (make-body-expr bodies)
  (cond
    ((null? bodies) (list 'begin))
    ((null? (cdr bodies)) (car bodies))
    (else (cons 'begin bodies))))

(define (desugar-let* bindings bodies)
  (if (null? bindings)
      (make-body-expr bodies)
      (list 'let (list (car bindings))
            (desugar-let* (cdr bindings) bodies))))

(define (desugar-named-let expr)
  (let* ((name (cadr expr))
         (bindings (caddr expr))
         (bodies (cdddr expr))
         (params (map car* bindings))
         (inits (map cadr bindings)))
    (list 'letrec
          (list (list name (cons 'lambda (cons params bodies))))
          (cons name inits))))

(define (desugar-do bindings exit-clause commands)
  (let* ((loop-sym (unique-symbol "do_loop_"))
         (init-bindings
          (map (lambda (b) (list (car b) (cadr b))) bindings))
         (test (car exit-clause))
         (res (cdr exit-clause))
         (then-expr
          (if (null? res)
              #f
              (make-body-expr res)))
         (step-exprs
          (map (lambda (b)
                 (if (pair? (cddr b))
                     (caddr b)
                     (car b)))
               bindings))
         (loop-call (cons loop-sym step-exprs))
         (else-expr
          (make-body-expr (append commands (list loop-call)))))
    (list 'let loop-sym init-bindings
          (list 'if test
                then-expr
                else-expr))))

(define (normalize-define-spec spec bodies)
  (cond
    ((pair? spec)
     (let ((actual-bodies (if (null? bodies) (list #f) bodies)))
       (if (pair? (car spec))
           ;; カリー化短縮構文: (define ((f x) y) ...) -> (define (f x) (lambda (y) ...))
           (normalize-define-spec (car spec) (list (cons 'lambda (cons (cdr spec) actual-bodies))))
           ;; 通常短縮構文: (define (f x ...) ...) -> (define f (lambda (x ...) ...))
           (cons (car spec) (cons 'lambda (cons (cdr spec) actual-bodies))))))
    ((symbol? spec)
     ;; 変数定義: (define x val)
     (cons spec (if (pair? bodies) (car bodies) #f)))
    (else
     (error "Malformed define specification in internal define:" spec))))

(define (desugar-internal-define spec rest-def rest)
  (let* ((norm (normalize-define-spec spec rest-def))
         (name (car norm))
         (val (cdr norm))
         (is-proc? (and (pair? val) (eq? (car val) 'lambda))))
    (if is-proc?
        ;; 連続する手続き定義を単一の letrec 節へ集約（相互再帰対応）
        (let loop ((cur-rest rest)
                   (proc-bindings (list (list name val))))
          (if (and (pair? cur-rest)
                   (pair? (car cur-rest))
                   (eq? (caar cur-rest) 'define)
                   (pair? (cdar cur-rest)))
              (let* ((next-def (car cur-rest))
                     (next-norm (normalize-define-spec (cadr next-def) (cddr next-def)))
                     (next-name (car next-norm))
                     (next-val (cdr next-norm)))
                (if (and (pair? next-val) (eq? (car next-val) 'lambda))
                    (loop (cdr cur-rest) (cons (list next-name next-val) proc-bindings))
                    (list 'letrec (reverse proc-bindings) (if (null? cur-rest) #f (make-body-expr cur-rest)))))
              (list 'letrec (reverse proc-bindings) (if (null? cur-rest) #f (make-body-expr cur-rest)))))
        ;; 通常の変数定義: let で包み、後続の定義・式を body に配置
        (list 'let (list (list name val)) (if (null? rest) #f (make-body-expr rest))))))

;;; -----------------------------------------------------------------------
;;; Nanopass DSL Pass Definition: Desugar Bindings
;;; -----------------------------------------------------------------------
(define-pass desugar-bindings : L_src (ir) -> L_core ()
  (Expr : Expr (ir) -> Expr ()
    ((let* ,bindings . ,bodies) (Expr (desugar-let* bindings bodies)))
    ((let ,name ,bindings . ,bodies) (guard (symbol? name))
     (Expr (desugar-named-let (cons 'let (cons name (cons bindings bodies))))))
    ((let ,bindings ,b1 ,b2 . ,rest) (guard (list? bindings))
     (Expr (list 'let bindings (cons 'begin (cons b1 (cons b2 rest))))))
    ((letrec ,bindings ,b1 ,b2 . ,rest) (guard (list? bindings))
     (Expr (list 'letrec bindings (cons 'begin (cons b1 (cons b2 rest))))))
    ((lambda ,params ,b1 ,b2 . ,rest)
     (Expr (list 'lambda params (cons 'begin (cons b1 (cons b2 rest))))))
    ((do ,bindings ,exit-clause . ,commands)
     (Expr (desugar-do bindings exit-clause commands)))
    ((begin (begin . ,inner) . ,rest)
     (Expr (cons 'begin (append inner rest))))
    ((begin (define ,spec . ,rest-def) . ,rest)
     (Expr (desugar-internal-define spec rest-def rest)))
    ((define ,spec . ,rest-def)
     (Expr (desugar-internal-define spec rest-def '())))))
;;; =======================================================================
;;; ULisp Compiler Pass 029: Dynamic Environment & Multiple Values Desugaring Pass
;;; Conforms to DSN-33 Architecture Specification & Nanopass Standard
;;; Desugars let-values, let*-values, guard, and parameterize constructs
;;; =======================================================================

(define (desugar-guard-clauses var clauses)
  (let loop ((cls clauses))
    (cond
      ((null? cls)
       (list (list 'else (list 'raise var))))
      ((eq? (caar cls) 'else)
       cls)
      (else
       (cons (car cls) (loop (cdr cls)))))))

(define (desugar-guard spec bodies)
  (let ((var (car spec))
        (clauses (cdr spec)))
    (list '%with-handler
          (list 'lambda (list var)
                (cons 'cond (desugar-guard-clauses var clauses)))
          (cons 'lambda (cons '() bodies)))))

(define (desugar-let-values bindings bodies)
  (if (null? bindings)
      (make-body-expr bodies)
      (let ((b (car bindings)))
        (list 'call-with-values
              (list 'lambda '() (cadr b))
              (list 'lambda (car b)
                    (desugar-let-values (cdr bindings) bodies))))))

(define (desugar-let*-values bindings bodies)
  (if (null? bindings)
      (make-body-expr bodies)
      (desugar-let-values (list (car bindings))
                          (list (desugar-let*-values (cdr bindings) bodies)))))

(define (desugar-parameterize bindings bodies)
  (if (null? bindings)
      (make-body-expr bodies)
      (let loop ((rest bindings)
                 (let-bindings '())
                 (save-and-set '())
                 (restore '()))
        (if (null? rest)
            (let* ((before-thunk
                    (list 'lambda '() (cons 'begin (reverse save-and-set))))
                   (after-thunk
                    (list 'lambda '() (cons 'begin (reverse restore))))
                   (exc-sym (unique-symbol "exc_"))
                   (body-expr
                    (list 'guard (list exc-sym (list 'else (cons 'begin (append (reverse restore) (list (list 'raise exc-sym))))))
                          (make-body-expr bodies)))
                   (body-thunk
                    (list 'lambda '() body-expr)))
              (list 'let (reverse let-bindings)
                    (list 'dynamic-wind before-thunk body-thunk after-thunk)))
            (let* ((b (car rest))
                   (param-expr (car b))
                   (val-expr (cadr b))
                   (p-sym (unique-symbol "param_"))
                   (v-sym (unique-symbol "newval_"))
                   (old-sym (unique-symbol "oldcell_")))
              (loop (cdr rest)
                    (cons (list old-sym (list 'cons #f ''()))
                          (cons (list v-sym val-expr)
                                (cons (list p-sym param-expr)
                                      let-bindings)))
                    (cons (list p-sym v-sym)
                          (cons (list 'set-car! old-sym (list p-sym))
                                save-and-set))
                    (cons (list p-sym (list 'car old-sym))
                          restore)))))))

(define (desugar-define-values formals expr rest)
  (if (null? rest)
      (list 'call-with-values
            (list 'lambda '() expr)
            (list 'lambda (if (list? formals) formals (list formals)) #f))
      (list 'let-values
            (list (list formals expr))
            (make-body-expr rest))))

;;; -----------------------------------------------------------------------
;;; Nanopass DSL Pass Definition: Desugar Dynamic
;;; -----------------------------------------------------------------------
(define-pass desugar-dynamic : L_src (ir) -> L_core ()
  (Expr : Expr (ir) -> Expr ()
    ((let-values ,bindings . ,bodies) (Expr (desugar-let-values bindings bodies)))
    ((let*-values ,bindings . ,bodies) (Expr (desugar-let*-values bindings bodies)))
    ((begin (define-values ,formals ,expr) . ,rest)
     (Expr (desugar-define-values formals expr rest)))
    ((define-values ,formals ,expr)
     (Expr (desugar-define-values formals expr '())))
    ((guard ,spec . ,bodies) (Expr (desugar-guard spec bodies)))
    ((parameterize ,bindings . ,bodies) (Expr (desugar-parameterize bindings bodies)))))
;;; =======================================================================
;;; ULisp Compiler Pass 030: Core Syntax Desugaring & Normalization Pass
;;; Conforms to DSN-33 Architecture Specification & Nanopass Framework Standard
;;; Migrated to Nanopass DSL (Phase 1) per Issue #581.
;;; Eliminates manual Catamorphism recursion boilerplate for Core constructs
;;; (if, begin, lambda, let, letrec, quote, set!, %program, applications).
;;; =======================================================================

;;; Helper transformations for composite types and runtime forms
(define (desugar-string-copy args)
  (cond
    ((null? (cdr args))
     (let ((s-sym (unique-symbol "s_")))
       (list 'let (list (list s-sym (car args)))
             (list 'string-copy-range s-sym 0 (list 'string-length s-sym)))))
    ((null? (cddr args))
     (let ((s-sym (unique-symbol "s_")))
       (list 'let (list (list s-sym (car args)))
             (list 'string-copy-range s-sym (cadr args) (list 'string-length s-sym)))))
    (else
     (cons 'string-copy-range args))))

(define (desugar-string-copy! args)
  (if (null? (cdddr args))
      (let ((from-sym (unique-symbol "from_")))
        (list 'let (list (list from-sym (caddr args)))
              (list 'string-copy-range! (car args) (cadr args)
                    from-sym 0 (list 'string-length from-sym))))
      (cons 'string-copy-range! args)))

(define (desugar-string-fill! args)
  (cond
    ((null? (cddr args))
     (let ((s-sym (unique-symbol "s_")))
       (list 'let (list (list s-sym (car args)))
             (list 'string-fill-range! s-sym (cadr args) 0 (list 'string-length s-sym)))))
    ((null? (cdddr args))
     (let ((s-sym (unique-symbol "s_")))
       (list 'let (list (list s-sym (car args)))
             (list 'string-fill-range! s-sym (cadr args) (caddr args) (list 'string-length s-sym)))))
    (else
     (cons 'string-fill-range! args))))

(define (desugar-make-bytevector args)
  (if (null? (cdr args))
      (list '%make-bytevector (car args))
      (list 'make-bytevector-fill (car args) (cadr args))))

(define (desugar-bytevector-copy args)
  (cond
    ((null? (cdr args))
     (let ((bv-sym (unique-symbol "bv_")))
       (list 'let (list (list bv-sym (car args)))
             (list 'bytevector-copy-range bv-sym 0 (list 'bytevector-length bv-sym)))))
    ((null? (cddr args))
     (let ((bv-sym (unique-symbol "bv_")))
       (list 'let (list (list bv-sym (car args)))
             (list 'bytevector-copy-range bv-sym (cadr args) (list 'bytevector-length bv-sym)))))
    (else
     (cons 'bytevector-copy-range args))))

(define (desugar-bytevector-copy! args)
  (if (null? (cdddr args))
      (let ((from-sym (unique-symbol "from_")))
        (list 'let (list (list from-sym (caddr args)))
              (list 'bytevector-copy-range! (car args) (cadr args)
                    from-sym 0 (list 'bytevector-length from-sym))))
      (cons 'bytevector-copy-range! args)))

(define (desugar-string->utf8 args)
  (if (null? (cdr args))
      (let ((str-sym (unique-symbol "str_")))
        (list 'let (list (list str-sym (car args)))
              (list 'string->utf8-range str-sym 0 (list 'string-length str-sym))))
      (cons 'string->utf8-range args)))

(define (desugar-utf8->string args)
  (if (null? (cdr args))
      (let ((bv-sym (unique-symbol "bv_")))
        (list 'let (list (list bv-sym (car args)))
              (list 'utf8->string-range bv-sym 0 (list 'bytevector-length bv-sym))))
      (cons 'utf8->string-range args)))

(define (desugar-make-vector args)
  (if (null? (cdr args))
      (list '%make-vector (car args))
      (list 'make-vector-fill (car args) (cadr args))))

(define (desugar-vector-copy args)
  (cond
    ((null? (cdr args))
     (let ((v-sym (unique-symbol "v_")))
       (list 'let (list (list v-sym (car args)))
             (list 'vector-copy-range v-sym 0 (list 'vector-length v-sym)))))
    ((null? (cddr args))
     (let ((v-sym (unique-symbol "v_")))
       (list 'let (list (list v-sym (car args)))
             (list 'vector-copy-range v-sym (cadr args) (list 'vector-length v-sym)))))
    (else
     (cons 'vector-copy-range args))))

(define (desugar-vector-copy! args)
  (if (null? (cdddr args))
      (let ((from-sym (unique-symbol "from_")))
        (list 'let (list (list from-sym (caddr args)))
              (list 'vector-copy-range! (car args) (cadr args)
                    from-sym 0 (list 'vector-length from-sym))))
      (cons 'vector-copy-range! args)))

(define (desugar-vector-fill! args)
  (cond
    ((null? (cddr args))
     (let ((v-sym (unique-symbol "v_")))
       (list 'let (list (list v-sym (car args)))
             (list 'vector-fill-range! v-sym (cadr args) 0 (list 'vector-length v-sym)))))
    ((null? (cdddr args))
     (let ((v-sym (unique-symbol "v_")))
       (list 'let (list (list v-sym (car args)))
             (list 'vector-fill-range! v-sym (cadr args) (caddr args) (list 'vector-length v-sym)))))
    (else
     (cons 'vector-fill-range! args))))

(define (desugar-vector->list args)
  (cond
    ((null? (cdr args))
     (let ((v-sym (unique-symbol "v_")))
       (list 'let (list (list v-sym (car args)))
             (list 'vector->list-range v-sym 0 (list 'vector-length v-sym)))))
    ((null? (cddr args))
     (let ((v-sym (unique-symbol "v_")))
       (list 'let (list (list v-sym (car args)))
             (list 'vector->list-range v-sym (cadr args) (list 'vector-length v-sym)))))
    (else
     (cons 'vector->list-range args))))

(define (desugar-string->list args)
  (cond
    ((null? (cdr args))
     (let ((s-sym (unique-symbol "str_")))
       (list 'let (list (list s-sym (car args)))
             (list 'string->list-range s-sym 0 (list 'string-length s-sym)))))
    ((null? (cddr args))
     (let ((s-sym (unique-symbol "str_")))
       (list 'let (list (list s-sym (car args)))
             (list 'string->list-range s-sym (cadr args) (list 'string-length s-sym)))))
    (else
     (cons 'string->list-range args))))

(define (desugar-string->vector args)
  (cond
    ((null? (cdr args))
     (let ((s-sym (unique-symbol "str_")))
       (list 'let (list (list s-sym (car args)))
             (list 'string->vector-range s-sym 0 (list 'string-length s-sym)))))
    ((null? (cddr args))
     (let ((s-sym (unique-symbol "str_")))
       (list 'let (list (list s-sym (car args)))
             (list 'string->vector-range s-sym (cadr args) (list 'string-length s-sym)))))
    (else
     (cons 'string->vector-range args))))

(define (desugar-vector->string args)
  (cond
    ((null? (cdr args))
     (let ((v-sym (unique-symbol "v_")))
       (list 'let (list (list v-sym (car args)))
             (list 'vector->string-range v-sym 0 (list 'vector-length v-sym)))))
    ((null? (cddr args))
     (let ((v-sym (unique-symbol "v_")))
       (list 'let (list (list v-sym (car args)))
             (list 'vector->string-range v-sym (cadr args) (list 'vector-length v-sym)))))
    (else
     (cons 'vector->string-range args))))

(define (desugar-make-list args)
  (if (null? (cdr args))
      (list 'make-list-fill (car args) #f)
      (list 'make-list-fill (car args) (cadr args))))

(define (desugar-delay expr)
  (let ((body (if (null? (cddr expr))
                  (cadr expr)
                  (cons 'begin (cdr expr)))))
    (list '%%make-promise ''lazy (list 'lambda '() (list '%%make-promise ''eager body)))))

(define (desugar-delay-force expr)
  (let ((body (if (null? (cddr expr))
                  (cadr expr)
                  (cons 'begin (cdr expr)))))
    (list '%%make-promise ''lazy (list 'lambda '() body))))

(define (desugar-make-parameter args)
  (if (null? (cdr args))
      (list 'make-parameter-1 (car args))
      (list 'make-parameter-2 (car args) (cadr args))))

(define (desugar-values args)
  (cond
    ((null? args) (list '%values))
    ((null? (cdr args)) (car args))
    (else (cons '%values args))))

(define (desugar-error expr)
  (let ((msg (cadr expr))
        (irritants (cddr expr)))
    (list 'raise (cons 'list (cons ''error-object (cons msg irritants))))))

(define (desugar-gcd args)
  (cond
    ((null? args) 0)
    ((null? (cdr args)) (list '%math-abs (car args)))
    ((null? (cddr args)) (list 'gcd-2 (car args) (cadr args)))
    (else
     (let loop ((curr (list 'gcd-2 (car args) (cadr args)))
                (rest (cddr args)))
       (if (null? rest)
           curr
           (loop (list 'gcd-2 curr (car rest)) (cdr rest)))))))

(define (desugar-lcm args)
  (cond
    ((null? args) 1)
    ((null? (cdr args)) (list '%math-abs (car args)))
    ((null? (cddr args)) (list 'lcm-2 (car args) (cadr args)))
    (else
     (let loop ((curr (list 'lcm-2 (car args) (cadr args)))
                (rest (cddr args)))
       (if (null? rest)
           curr
           (loop (list 'lcm-2 curr (car rest)) (cdr rest)))))))

;;; =======================================================================
;;; Canonical Nanopass DSL Pass: desugar-all
;;; Transforms high-level L_src AST into canonical L_core AST
;;; =======================================================================
(define-pass desugar-all : L_src (ir) -> L_core ()
  (Expr : Expr (ir) -> Expr ()
    ;; 1. Conditionals (Pass 027)
    ((cond ,clauses ...) (Expr (desugar-cond clauses)))
    ((cond . ,clauses) (Expr (desugar-cond clauses)))
    ((case ,key ,clauses ...) (Expr (desugar-case key clauses)))
    ((case ,key . ,clauses) (Expr (desugar-case key clauses)))
    ((and ,args ...) (Expr (desugar-and args)))
    ((and . ,args) (Expr (desugar-and args)))
    ((or ,args ...) (Expr (desugar-or args)))
    ((or . ,args) (Expr (desugar-or args)))
    ((char<? . ,args)
     (if (or (null? args) (null? (cdr args)) (null? (cddr args)))
         (cons 'char<? (map Expr args))
         (Expr (desugar-chain-cmp 'char<? args))))
    ((char>? . ,args)
     (if (or (null? args) (null? (cdr args)) (null? (cddr args)))
         (cons 'char>? (map Expr args))
         (Expr (desugar-chain-cmp 'char>? args))))
    ((char<=? . ,args)
     (if (or (null? args) (null? (cdr args)) (null? (cddr args)))
         (cons 'char<=? (map Expr args))
         (Expr (desugar-chain-cmp 'char<=? args))))
    ((char>=? . ,args)
     (if (or (null? args) (null? (cdr args)) (null? (cddr args)))
         (cons 'char>=? (map Expr args))
         (Expr (desugar-chain-cmp 'char>=? args))))
    ((char=? . ,args)
     (if (or (null? args) (null? (cdr args)) (null? (cddr args)))
         (cons 'char=? (map Expr args))
         (Expr (desugar-chain-cmp 'char=? args))))
    ((string<? . ,args)
     (if (or (null? args) (null? (cdr args)) (null? (cddr args)))
         (cons 'string<? (map Expr args))
         (Expr (desugar-chain-cmp 'string<? args))))
    ((string>? . ,args)
     (if (or (null? args) (null? (cdr args)) (null? (cddr args)))
         (cons 'string>? (map Expr args))
         (Expr (desugar-chain-cmp 'string>? args))))
    ((string<=? . ,args)
     (if (or (null? args) (null? (cdr args)) (null? (cddr args)))
         (cons 'string<=? (map Expr args))
         (Expr (desugar-chain-cmp 'string<=? args))))
    ((string>=? . ,args)
     (if (or (null? args) (null? (cdr args)) (null? (cddr args)))
         (cons 'string>=? (map Expr args))
         (Expr (desugar-chain-cmp 'string>=? args))))
    ((string=? . ,args)
     (if (or (null? args) (null? (cdr args)) (null? (cddr args)))
         (cons 'string=? (map Expr args))
         (Expr (desugar-chain-cmp 'string=? args))))

    ;; 2. Local Bindings (Pass 028)
    ((let* ,bindings . ,bodies) (Expr (desugar-let* bindings bodies)))
    ((let ,name ,bindings . ,bodies) (guard (symbol? name))
     (Expr (desugar-named-let (cons 'let (cons name (cons bindings bodies))))))
    ((let ,bindings ,b1 ,b2 . ,rest) (guard (list? bindings))
     (Expr (list 'let bindings (cons 'begin (cons b1 (cons b2 rest))))))
    ((letrec ,bindings ,b1 ,b2 . ,rest) (guard (list? bindings))
     (Expr (list 'letrec bindings (cons 'begin (cons b1 (cons b2 rest))))))
    ((lambda ,params ,b1 ,b2 . ,rest)
     (Expr (list 'lambda params (cons 'begin (cons b1 (cons b2 rest))))))
    ((do ,bindings ,exit-clause . ,commands)
     (Expr (desugar-do bindings exit-clause commands)))
    ((begin (begin . ,inner) . ,rest)
     (Expr (cons 'begin (append inner rest))))
    ((begin (define ,spec . ,rest-def) . ,rest)
     (Expr (desugar-internal-define spec rest-def rest)))
    ((define ,spec . ,rest-def)
     (Expr (desugar-internal-define spec rest-def '())))

    ;; 3. Constructors (Pass 026)
    ((list ,args ...) (Expr (desugar-list args)))
    ((list . ,args) (Expr (desugar-list args)))
    ((string-append ,args ...) (Expr (desugar-string-append args)))
    ((string-append . ,args) (Expr (desugar-string-append args)))
    ((string-copy . ,args) (Expr (desugar-string-copy (map Expr args))))
    ((string-copy! . ,args) (Expr (desugar-string-copy! (map Expr args))))
    ((string-fill! . ,args) (Expr (desugar-string-fill! (map Expr args))))
    ((string->utf8 . ,args) (Expr (desugar-string->utf8 (map Expr args))))
    ((utf8->string . ,args) (Expr (desugar-utf8->string (map Expr args))))
    ((string->list . ,args) (Expr (desugar-string->list (map Expr args))))
    ((string->vector . ,args) (Expr (desugar-string->vector (map Expr args))))
    ((vector ,args ...) (Expr (desugar-vector args)))
    ((vector . ,args) (Expr (desugar-vector args)))
    ((vector-append ,args ...) (Expr (desugar-vector-append args)))
    ((vector-append . ,args) (Expr (desugar-vector-append args)))
    ((make-vector . ,args) (Expr (desugar-make-vector (map Expr args))))
    ((vector-copy . ,args) (Expr (desugar-vector-copy (map Expr args))))
    ((vector-copy! . ,args) (Expr (desugar-vector-copy! (map Expr args))))
    ((vector-fill! . ,args) (Expr (desugar-vector-fill! (map Expr args))))
    ((vector->list . ,args) (Expr (desugar-vector->list (map Expr args))))
    ((vector->string . ,args) (Expr (desugar-vector->string (map Expr args))))
    ((make-list . ,args) (Expr (desugar-make-list (map Expr args))))
    ((bytevector ,args ...) (Expr (desugar-bytevector args)))
    ((bytevector . ,args) (Expr (desugar-bytevector args)))
    ((bytevector-append ,args ...) (Expr (desugar-bytevector-append args)))
    ((bytevector-append . ,args) (Expr (desugar-bytevector-append args)))
    ((make-bytevector . ,args) (Expr (desugar-make-bytevector (map Expr args))))
    ((bytevector-copy . ,args) (Expr (desugar-bytevector-copy (map Expr args))))
    ((bytevector-copy! . ,args) (Expr (desugar-bytevector-copy! (map Expr args))))
    ((gcd . ,args) (Expr (desugar-gcd (map Expr args))))
    ((lcm . ,args) (Expr (desugar-lcm (map Expr args))))

    ;; 4. Dynamic & Multiple Values (Pass 029)
    ((guard ,spec . ,bodies) (Expr (desugar-guard spec bodies)))
    ((let-values ,bindings . ,bodies) (Expr (desugar-let-values bindings bodies)))
    ((let*-values ,bindings . ,bodies) (Expr (desugar-let*-values bindings bodies)))
    ((begin (define-values ,formals ,expr) . ,rest)
     (Expr (desugar-define-values formals expr rest)))
    ((define-values ,formals ,expr)
     (Expr (desugar-define-values formals expr '())))
    ((parameterize ,bindings . ,bodies) (Expr (desugar-parameterize bindings bodies)))
    ((delay ,args ...) (Expr (desugar-delay (cons 'delay args))))
    ((delay . ,args) (Expr (desugar-delay (cons 'delay args))))
    ((delay-force ,args ...) (Expr (desugar-delay-force (cons 'delay-force args))))
    ((delay-force . ,args) (Expr (desugar-delay-force (cons 'delay-force args))))
    ((make-parameter . ,args) (Expr (desugar-make-parameter (map Expr args))))
    ((values . ,args) (Expr (desugar-values (map Expr args))))
    ((%raw-call/cc ,arg) (list '%raw-call/cc (Expr arg)))
    ((call-with-values ,p1 ,p2) (list '%call-with-values (Expr p1) (Expr p2)))
    ((%call-with-values ,p1 ,p2) (list '%call-with-values (Expr p1) (Expr p2)))
    ((error ,args ...) (Expr (desugar-error (cons 'error args))))
    ((error . ,args) (Expr (desugar-error (cons 'error args))))
    ((%with-handler ,h ,b) (list '%with-handler (Expr h) (Expr b)))
    ((with-exception-handler ,h ,b) (list '%with-handler (Expr h) (Expr b)))

    ;; 5. List Accessor Shortcuts
    ((caar ,arg) (Expr (list 'car (list 'car arg))))
    ((cadr ,arg) (Expr (list 'car (list 'cdr arg))))
    ((cdar ,arg) (Expr (list 'cdr (list 'car arg))))
    ((cddr ,arg) (Expr (list 'cdr (list 'cdr arg))))
    ((caddr ,arg) (Expr (list 'car (list 'cdr (list 'cdr arg)))))
    ((cdddr ,arg) (Expr (list 'cdr (list 'cdr (list 'cdr arg)))))
    ((cadddr ,arg) (Expr (list 'car (list 'cdr (list 'cdr (list 'cdr arg))))))))
;;; =======================================================================
;;; ULisp Compiler Pass 2: Static Scope & Free-Variable Analysis Pass
;;; Conforms to DSN-33 Architecture Specification & Nanopass Framework DSL (Phase 3)
;;; Note: Operates strictly on Canonical Core AST produced by Pass 1 (desugar-all)
;;; =======================================================================

;;; -----------------------------------------------------------------------
;;; Nanopass DSL Pass: free-vars-acc
;;; Computes free variables using an accumulator thread across L_core AST.
;;; -----------------------------------------------------------------------
(define-pass free-vars-acc : L_core (ir bound acc) -> * (acc)
  (definitions
    (define (free-vars-list es b cur-acc)
      (if (null? es)
          cur-acc
          (free-vars-list (cdr es) b (free-vars-acc (car es) b cur-acc)))))
  (Expr : Expr (ir bound acc) -> * (acc)
    ((quote ,datum)
     acc)
    (,x (guard (symbol? x))
     (if (or (memq x bound) (memq x acc))
         acc
         (cons x acc)))
    (,c (guard (not (pair? c)))
     acc)
    ((if ,test ,then ,else-expr)
     (free-vars-acc else-expr bound (free-vars-acc then bound (free-vars-acc test bound acc))))
    ((if ,test ,then)
     (free-vars-acc then bound (free-vars-acc test bound acc)))
    ((begin ,es ...)
     (free-vars-list es bound acc))
    ((let ((,x* ,e*) ...) ,body)
     (let* ((b-acc (free-vars-list e* bound acc))
            (new-bound (set-union x* bound)))
       (free-vars-acc body new-bound b-acc)))
    ((letrec ((,x* ,e*) ...) ,body)
     (let* ((new-bound (set-union x* bound))
            (b-acc (free-vars-list e* new-bound acc)))
       (free-vars-acc body new-bound b-acc)))
    ((lambda (,params ...) ,body)
     (free-vars-acc body (set-union params bound) acc))
    ((%make-closure ,tag ,es ...)
     (free-vars-list es bound acc))
    ((%make-closure-env ,tag ,es ...)
     (free-vars-list es bound acc))
    ((%cont-fun ,f-name (,params ...) ,f-body ,in-body)
     (let* ((f-bound (set-union params bound))
            (f-acc (free-vars-acc f-body f-bound acc)))
       (free-vars-acc in-body bound f-acc)))
    ((%cont-call ,target ,es ...)
     (free-vars-list es bound acc))
    ((%with-handler ,h ,body)
     (free-vars-acc body bound (free-vars-acc h bound acc)))
    ((%raw-call/cc ,arg)
     (free-vars-acc arg bound acc))
    ((%call-with-values ,prod ,cons-fn)
     (free-vars-acc cons-fn bound (free-vars-acc prod bound acc)))
    ((%program ,defs ,main)
     (let* ((d-acc (let loop ((ds defs) (cur-acc acc))
                     (if (null? ds) cur-acc
                         (let ((d (car ds)))
                           (loop (cdr ds)
                                 (if (and (pair? d) (eq? (car d) 'define))
                                     (free-vars-acc (caddr d) bound cur-acc)
                                     (free-vars-acc d bound cur-acc))))))))
       (free-vars-acc main bound d-acc)))
    ((%values ,es ...)
     (free-vars-list es bound acc))
    ((,op ,args ...)
     (cond
       ((zero-arg-prim? op)
        acc)
       ((or (unary-prim? op) (or (binop-prim? op) (or (triop-prim? op) (septop-prim? op))))
        (free-vars-list args bound acc))
       (else
        (let ((op-acc (free-vars-acc op bound acc)))
          (free-vars-list args bound op-acc)))))))

(define (free-vars expr bound)
  (reverse (free-vars-acc expr bound '())))

;;; -----------------------------------------------------------------------
;;; Nanopass DSL Pass: analyze-escapes
;;; Checks whether `var` escapes (appears in non-operator position) within `expr`.
;;; -----------------------------------------------------------------------
(define-pass analyze-escapes : L_core (ir var) -> * (escapes?)
  (Expr : Expr (ir var) -> * (escapes?)
    ((quote ,datum) #f)
    (,x (guard (symbol? x))
     (eq? x var))
    (,c (guard (not (pair? c)))
     #f)
    ((if ,test ,then ,else-expr)
     (or (Expr test var) (or (Expr then var) (Expr else-expr var))))
    ((if ,test ,then)
     (or (Expr test var) (Expr then var)))
    ((begin ,es ...)
     (let loop ((rest es))
       (and (pair? rest) (or (Expr (car rest) var) (loop (cdr rest))))))
    ((let ((,x* ,e*) ...) ,body)
     (or (let loop ((rest e*))
           (and (pair? rest) (or (Expr (car rest) var) (loop (cdr rest)))))
         (if (memq var x*) #f (Expr body var))))
    ((letrec ((,x* ,e*) ...) ,body)
     (if (memq var x*)
         #f
         (or (let loop ((rest e*))
               (and (pair? rest) (or (Expr (car rest) var) (loop (cdr rest)))))
             (Expr body var))))
    ((lambda (,params ...) ,body)
     (if (memq var params)
         #f
         (if (memq var (free-vars body params))
             #t
             (Expr body var))))
    ((%make-closure ,tag ,es ...)
     (let loop ((rest es))
       (and (pair? rest) (or (Expr (car rest) var) (loop (cdr rest))))))
    ((%make-closure-env ,tag ,es ...)
     (let loop ((rest es))
       (and (pair? rest) (or (Expr (car rest) var) (loop (cdr rest))))))
    ((%with-handler ,h ,body)
     (or (Expr h var) (Expr body var)))
    ((%raw-call/cc ,arg)
     (Expr arg var))
    ((%call-with-values ,prod ,cons-fn)
     (or (Expr prod var) (Expr cons-fn var)))
    ((%values ,es ...)
     (let loop ((rest es))
       (and (pair? rest) (or (Expr (car rest) var) (loop (cdr rest))))))
    ((%program ,defs ,main)
     (or (let loop ((ds defs))
           (and (pair? ds)
                (or (let ((d (car ds)))
                      (if (and (pair? d) (eq? (car d) 'define))
                          (Expr (caddr d) var)
                          (Expr d var)))
                    (loop (cdr ds)))))
         (Expr main var)))
    ((,op ,args ...)
     (if (eq? op var)
         (let loop ((as args))
           (and (pair? as) (or (Expr (car as) var) (loop (cdr as)))))
         (or (Expr op var)
             (let loop ((as args))
               (and (pair? as) (or (Expr (car as) var) (loop (cdr as))))))))))

(define (escapes? var expr)
  (analyze-escapes expr var))

;;; -----------------------------------------------------------------------
;;; Nanopass DSL Pass: tail-calls-only?
;;; Checks whether all call sites of `var` in `expr` are in tail position.
;;; -----------------------------------------------------------------------
(define-pass tail-calls-only-impl : L_core (ir var tail?) -> * (ok?)
  (definitions
    (define (all-non-tail es v)
      (or (null? es)
          (and (tail-calls-only-impl (car es) v #f)
               (all-non-tail (cdr es) v)))))
  (Expr : Expr (ir var tail?) -> * (ok?)
    ((quote ,datum) #t)
    (,x (guard (symbol? x)) #t)
    (,c (guard (not (pair? c))) #t)
    ((if ,test ,then ,else-expr)
     (and (tail-calls-only-impl test var #f)
          (tail-calls-only-impl then var tail?)
          (tail-calls-only-impl else-expr var tail?)))
    ((if ,test ,then)
     (and (tail-calls-only-impl test var #f)
          (tail-calls-only-impl then var tail?)))
    ((begin ,es ...)
     (let loop ((rest es))
       (cond
         ((null? rest) #t)
         ((null? (cdr rest)) (tail-calls-only-impl (car rest) var tail?))
         (else (and (tail-calls-only-impl (car rest) var #f) (loop (cdr rest)))))))
    ((let ((,x* ,e*) ...) ,body)
     (and (all-non-tail e* var)
          (if (memq var x*) #t (tail-calls-only-impl body var tail?))))
    ((letrec ((,x* ,e*) ...) ,body)
     (if (memq var x*)
         #t
         (and (all-non-tail e* var)
              (tail-calls-only-impl body var tail?))))
    ((lambda (,params ...) ,body)
     (if (memq var params) #t (tail-calls-only-impl body var #t)))
    ((%with-handler ,h ,body)
     (and (tail-calls-only-impl h var #f) (tail-calls-only-impl body var #f)))
    ((%raw-call/cc ,arg)
     (tail-calls-only-impl arg var #f))
    ((%call-with-values ,prod ,cons-fn)
     (and (tail-calls-only-impl prod var #f) (tail-calls-only-impl cons-fn var #f)))
    ((%values ,es ...)
     (all-non-tail es var))
    ((%program ,defs ,main)
     (and (let loop ((ds defs))
            (or (null? ds)
                (let ((d (car ds)))
                  (and (if (and (pair? d) (eq? (car d) 'define))
                           (tail-calls-only-impl (caddr d) var #f)
                           (tail-calls-only-impl d var #f))
                       (loop (cdr ds))))))
          (tail-calls-only-impl main var tail?)))
    ((,op ,args ...)
     (if (eq? op var)
         (and tail? (all-non-tail args var))
         (and (tail-calls-only-impl op var #f) (all-non-tail args var))))))

(define (tail-calls-only? var expr)
  (tail-calls-only-impl expr var #t))

;;; Checks whether a binding `(var val)` in `(letrec ... body)` is contifiable.
(define (contifiable-binding? var val body)
  (and (pair? val)
       (eq? (car val) 'lambda)
       (pair? (cdr val))
       (pair? (cddr val))
       (not (escapes? var body))
       (not (escapes? var (caddr val)))
       (tail-calls-only? var body)
       (tail-calls-only? var (caddr val))))
;;; =======================================================================
;;; ULisp Compiler Pass 3: CP0 Source-Level Optimization Nanopass
;;; Conforms to DSN-33 Architecture Specification
;;; Note: Performs Constant Folding, Dead Branch Pruning, and Dead Let
;;;       Elimination on Canonical Core AST.
;;; =======================================================================

;;; Note: extract-const-val, val->ast-const, pure-expr?, and fold-const-op
;;;       are provided canonically by passes/00_helpers.scm.

;;; Top-level & nested letrec Dead Code Elimination (DCE) based on Reachability Call Graph
(define (dce-letrec bindings body)
  (let* ((rec-vars (map car* bindings))
         (rec-filter (lambda (vars)
                       (filter (lambda (v) (memq v rec-vars)) vars)))
         ;; Map each binding var to its immediate dependencies within rec-vars
         (dep-alist (map (lambda (b)
                           (cons (car b) (rec-filter (free-vars (cadr b) '()))))
                         bindings))
         ;; Root variables:
         ;; 1. Variables in rec-vars that appear free in the body
         (body-roots (rec-filter (free-vars body '())))
         ;; 2. Variables in rec-vars whose initialization is impure (has side effects)
         (impure-roots (let loop ((bs bindings) (acc '()))
                         (cond
                           ((null? bs) acc)
                           ((not (pure-expr? (cadar bs)))
                            (loop (cdr bs) (cons (caar bs) acc)))
                           (else
                            (loop (cdr bs) acc)))))
         (initial-roots (set-union body-roots impure-roots)))
    ;; Transitive closure via worklist
    (let ((reachable
           (let loop ((worklist initial-roots) (visited '()))
             (if (null? worklist)
                 visited
                 (let ((v (car worklist))
                       (rest (cdr worklist)))
                   (if (memq v visited)
                       (loop rest visited)
                       (let* ((v-deps (let ((entry (assq v dep-alist)))
                                        (if entry (cdr entry) '())))
                              (new-worklist (append v-deps rest)))
                         (loop new-worklist (cons v visited)))))))))
      ;; Retain only bindings in reachable set
      (let ((kept-bindings (filter (lambda (b) (memq (car b) reachable)) bindings)))
        (if (null? kept-bindings)
            body
            (list 'letrec kept-bindings body))))))

;;; -----------------------------------------------------------------------
;;; Nanopass DSL Pass: cp0-opt
;;; Bottom-up CP0 optimization: Constant Folding, Branch Pruning, and DCE
;;; -----------------------------------------------------------------------
(define-pass cp0-opt : L_core (ir) -> L_core ()
  (definitions
    (define (flatten-begin-list es)
      (let loop ((rest es) (acc '()))
        (cond
          ((null? rest) (reverse acc))
          ((and (pair? (car rest)) (eq? (caar rest) 'begin))
           (loop (append (cdar rest) (cdr rest)) acc))
          (else (loop (cdr rest) (cons (car rest) acc))))))
    (define (zip-bindings xs es)
      (let loop ((x xs) (e es) (acc '()))
        (if (or (null? x) (null? e))
            (reverse acc)
            (loop (cdr x) (cdr e) (cons (list (car x) (car e)) acc))))))
  (Expr : Expr (ir) -> Expr ()
    ((quote ,datum)
     ir)
    ((if ,test ,then ,else-val)
     (let ((opt-test (Expr test))
           (opt-then (Expr then))
           (opt-else (Expr else-val)))
       (if (const? opt-test)
           (let ((v (extract-const-val opt-test)))
             (if (eq? v #f) opt-else opt-then))
           (list 'if opt-test opt-then opt-else))))
    ((if ,test ,then)
     (let ((opt-test (Expr test))
           (opt-then (Expr then)))
       (if (const? opt-test)
           (let ((v (extract-const-val opt-test)))
             (if (eq? v #f) #f opt-then))
           (list 'if opt-test opt-then #f))))
    ((begin ,es ...)
     (let* ((opt-es (map Expr es))
            (flat (flatten-begin-list opt-es)))
       (cond
         ((null? flat) #f)
         ((null? (cdr flat)) (car flat))
         (else (cons 'begin flat)))))
    ((let ((,x* ,e*) ...) ,body)
     (let* ((opt-e* (map Expr e*))
            (opt-body (Expr body))
            (opt-bindings (zip-bindings x* opt-e*))
            (body-frees (free-vars opt-body '()))
            (kept-bindings
             (filter (lambda (b)
                       (or (not (pure-expr? (cadr b)))
                           (memq (car b) body-frees)))
                     opt-bindings)))
       (if (null? kept-bindings)
           opt-body
           (list 'let kept-bindings opt-body))))
    ((letrec ((,x* ,e*) ...) ,body)
     (let* ((opt-e* (map Expr e*))
            (opt-body (Expr body))
            (opt-bindings (zip-bindings x* opt-e*)))
       (dce-letrec opt-bindings opt-body)))
    ((lambda (,params ...) ,body)
     (list 'lambda params (Expr body)))
    ((%make-closure ,tag ,es ...)
     (cons '%make-closure (cons tag (map Expr es))))
    ((%make-closure-env ,tag ,es ...)
     (cons '%make-closure-env (cons tag (map Expr es))))
    ((%with-handler ,h ,body)
     (list '%with-handler (Expr h) (Expr body)))
    ((%raw-call/cc ,arg)
     (list '%raw-call/cc (Expr arg)))
    ((%call-with-values ,producer ,consumer)
     (let ((p (Expr producer))
           (c (Expr consumer)))
       (cond
         ((and (pair? p) (eq? (car p) 'lambda) (null? (cadr p))
               (pair? (caddr p)) (memq (car (caddr p)) '(%values values))
               (pair? c) (eq? (car c) 'lambda) (list? (cadr c))
               (= (length (cdr (caddr p))) (length (cadr c))))
          (let* ((vals (cdr (caddr p)))
                 (vars (cadr c))
                 (cbody (caddr c))
                 (bindings (zip-bindings vars vals)))
            (Expr (list 'let bindings cbody))))
         ((and (pair? p) (eq? (car p) 'lambda) (null? (cadr p))
               (not (and (pair? (caddr p)) (memq (car (caddr p)) '(%values values))))
               (pair? c) (eq? (car c) 'lambda) (list? (cadr c))
               (= (length (cadr c)) 1))
          (let ((val (caddr p))
                (var (car (cadr c)))
                (cbody (caddr c)))
            (Expr (list 'let (list (list var val)) cbody))))
         (else
          (list '%call-with-values p c)))))
    ((%values ,es ...)
     (cons '%values (map Expr es)))
    ((,op ,args ...)
     (let* ((opt-op (if (symbol? op) op (Expr op)))
            (opt-args (map Expr args)))
       (or (and (symbol? opt-op) (fold-const-op opt-op opt-args))
           (cons opt-op opt-args))))))

(define (cp0-expr expr)
  (cp0-opt expr))

;;; Top-level entrypoint for CP0 optimization
(define (cp0-optimize form)
  (cond
    ((not (pair? form)) form)
    ((eq? (car form) '%program)
     (let ((defs (cadr form))
           (main (caddr form)))
       (list '%program
             (map (lambda (d)
                    (if (and (pair? d) (eq? (car d) 'define))
                        (list 'define (cadr d) (cp0-expr (caddr d)))
                        (cp0-expr d)))
                  defs)
             (cp0-expr main))))
    ((eq? (car form) 'define)
     (list 'define (cadr form) (cp0-expr (caddr form))))
    (else
     (cp0-expr form))))
;;; =======================================================================
;;; ULisp Compiler Pass 3b: Extended Local Value Numbering (LVN) Nanopass
;;; Conforms to DSN-33 Architecture Specification (Section 8.2) & Issue #521
;;;
;;; Features:
;;; 1. Local Value Numbering (LVN) & Scoped Dominance (DVN) environment
;;; 2. Unified Constant Folding, Copy Propagation & Common Subexpression Elimination (CSE)
;;; 3. Immutable Pair Accessor Memoization (car/cdr deduplication & cons reduction)
;;; 4. Type Predicate Folding (fixnum?, pair?, null?, etc. in dominance scopes)
;;; 5. Algebraic Equivalence & Identity Normalization (+, -, *, =, eq?, char=?)
;;; 6. Sound Pair Mutation Invalidation (set-car!, set-cdr!)
;;; =======================================================================

;;; -----------------------------------------------------------------------
;;; 1. LVN Environment Data Structure & Accessors
;;; -----------------------------------------------------------------------
;;; Environment layout: (list var-env tuple-env vn-env next-id)
;;;   var-env:   ((var . vn) ...)
;;;   tuple-env: ((canonical-tuple . vn) ...)
;;;   vn-env:    ((vn . (canonical-expr . info)) ...)
;;;   next-id:   integer (1, 2, 3...)

(define (make-lvn-env)
  (list '() '() '() 1))

(define (lvn-env-vars env) (car env))
(define (lvn-env-tuples env) (cadr env))
(define (lvn-env-vns env) (caddr env))
(define (lvn-env-next-id env) (cadddr env))

(define (lvn-set-vars env vars)
  (list vars (cadr env) (caddr env) (cadddr env)))
(define (lvn-set-tuples env tuples)
  (list (car env) tuples (caddr env) (cadddr env)))
(define (lvn-set-vns env vns)
  (list (car env) (cadr env) vns (cadddr env)))

(define (lvn-alloc-vn env canon-expr info)
  (let* ((id (lvn-env-next-id env))
         (new-vns (cons (cons id (cons canon-expr info)) (lvn-env-vns env)))
         (new-env (list (lvn-env-vars env)
                        (lvn-env-tuples env)
                        new-vns
                        (+ id 1))))
    (cons id new-env)))

(define (tree-contains? tree sym)
  (cond
    ((eq? tree sym) #t)
    ((pair? tree)
     (or (tree-contains? (car tree) sym)
         (tree-contains? (cdr tree) sym)))
    (else #f)))

(define (lvn-bind-var env var vn)
  (let* ((vars (cons (cons var vn) (lvn-env-vars env)))
         (env1 (lvn-set-vars env vars))
         (vn-entry (assq vn (lvn-env-vns env1))))
    ;; If this VN does not have a canonical variable yet (or has a compound expr),
    ;; set its canonical representation to var
    (if (and vn-entry (not (symbol? (cadr vn-entry))))
        (let ((new-vns (cons (cons vn (cons var (cddr vn-entry)))
                             (lvn-env-vns env1))))
          (lvn-set-vns env1 new-vns))
        env1)))

(define (lvn-record-tuple env tuple vn)
  (lvn-set-tuples env (cons (cons tuple vn) (lvn-env-tuples env))))

(define (lvn-lookup-tuple env tuple)
  (let ((entry (assoc tuple (lvn-env-tuples env))))
    (if entry (cdr entry) #f)))

(define (lvn-vn-entry env vn)
  (assq vn (lvn-env-vns env)))

(define (lvn-vn-canon-expr env vn)
  (let ((e (lvn-vn-entry env vn)))
    (if e (cadr e) #f)))

(define (lvn-vn-info env vn)
  (let ((e (lvn-vn-entry env vn)))
    (if e (cddr e) '())))

(define (lvn-vn-is-const? env vn)
  (let ((info (lvn-vn-info env vn)))
    (and (pair? info) (eq? (car info) 'const))))

(define (lvn-vn-const-val env vn)
  (let ((info (lvn-vn-info env vn)))
    (if (and (pair? info) (eq? (car info) 'const))
        (cadr info)
        #f)))

(define (lvn-vn-is-pair? env vn)
  (let ((info (lvn-vn-info env vn)))
    (and (pair? info) (eq? (car info) 'pair))))

(define (lvn-vn-pair-car-vn env vn)
  (let ((info (lvn-vn-info env vn)))
    (if (and (pair? info) (eq? (car info) 'pair))
        (cadr info)
        #f)))

(define (lvn-vn-pair-cdr-vn env vn)
  (let ((info (lvn-vn-info env vn)))
    (if (and (pair? info) (eq? (car info) 'pair))
        (caddr info)
        #f)))

(define (lvn-invalidate-pairs env)
  (let* ((tuples (lvn-env-tuples env))
         (vns (lvn-env-vns env))
         (env1 (lvn-set-tuples env
                 (filter (lambda (entry)
                           (let ((key (car entry)))
                             (not (and (pair? key) (memq (car key) '(car cdr))))))
                         tuples)))
         (env2 (lvn-set-vns env1
                 (map (lambda (entry)
                        (let* ((vn (car entry))
                               (canon (cadr entry))
                               (info (cddr entry)))
                          (if (and (pair? info) (eq? (car info) 'pair))
                              (cons vn (cons canon '(type pair)))
                              entry)))
                      vns))))
    env2))

;;; -----------------------------------------------------------------------
;;; 2. Literal & Variable Value Evaluation
;;; -----------------------------------------------------------------------

(define (lvn-eval-const c env)
  (let* ((v (extract-const-val c))
         (key (list 'const v))
         (existing-vn (lvn-lookup-tuple env key)))
    (if existing-vn
        (list (val->ast-const v) existing-vn env)
        (let* ((alloc-res (lvn-alloc-vn env (val->ast-const v) (list 'const v)))
               (vn (car alloc-res))
               (env1 (cdr alloc-res))
               (env2 (lvn-record-tuple env1 key vn)))
          (list (val->ast-const v) vn env2)))))

(define (lvn-eval-var var env)
  (let ((entry (assq var (lvn-env-vars env))))
    (if entry
        (let* ((vn (cdr entry))
               (is-c (lvn-vn-is-const? env vn)))
          (if is-c
              ;; Constant propagation
              (list (val->ast-const (lvn-vn-const-val env vn)) vn env)
              (let ((canon-var (lvn-vn-canon-expr env vn)))
                ;; Copy propagation if canonical variable is currently in scope
                (if (and (symbol? canon-var)
                         (assq canon-var (lvn-env-vars env)))
                    (list canon-var vn env)
                    (list var vn env)))))
        ;; Unbound parameter / free variable entering scope
        (let* ((alloc-res (lvn-alloc-vn env var '()))
               (vn (car alloc-res))
               (env1 (cdr alloc-res))
               (env2 (lvn-bind-var env1 var vn)))
          (list var vn env2)))))

;;; -----------------------------------------------------------------------
;;; 3. Algebraic Simplification & Identity Normalization
;;; -----------------------------------------------------------------------

(define (lvn-try-algebraic-simplification op opt-args vn-args env)
  (let ((nargs (length opt-args)))
    (cond
      ((= nargs 2)
       (let* ((a1 (car opt-args))
              (a2 (cadr opt-args))
              (vn1 (car vn-args))
              (vn2 (cadr vn-args))
              (is-c1 (lvn-vn-is-const? env vn1))
              (c1 (if is-c1 (lvn-vn-const-val env vn1) #f))
              (is-c2 (lvn-vn-is-const? env vn2))
              (c2 (if is-c2 (lvn-vn-const-val env vn2) #f)))
         (case op
           ((+)
            (cond
              ;; (+ x 0) -> x
              ((and is-c2 (equal? c2 0))
               (list #t a1 vn1 env))
              ;; (+ 0 x) -> x
              ((and is-c1 (equal? c1 0))
               (list #t a2 vn2 env))
              (else (list #f #f #f env))))
           ((*)
            (cond
              ;; (* x 1) -> x
              ((and is-c2 (equal? c2 1))
               (list #t a1 vn1 env))
              ;; (* 1 x) -> x
              ((and is-c1 (equal? c1 1))
               (list #t a2 vn2 env))
              ;; (* x 0) -> 0
              ((and is-c2 (equal? c2 0))
               (let ((zero-res (lvn-eval-const 0 env)))
                 (list #t (car zero-res) (cadr zero-res) (caddr zero-res))))
              ;; (* 0 x) -> 0
              ((and is-c1 (equal? c1 0))
               (let ((zero-res (lvn-eval-const 0 env)))
                 (list #t (car zero-res) (cadr zero-res) (caddr zero-res))))
              (else (list #f #f #f env))))
           ((-)
            (cond
              ;; (- x 0) -> x
              ((and is-c2 (equal? c2 0))
               (list #t a1 vn1 env))
              ;; (- x x) -> 0
              ((= vn1 vn2)
               (let ((zero-res (lvn-eval-const 0 env)))
                 (list #t (car zero-res) (cadr zero-res) (caddr zero-res))))
              (else (list #f #f #f env))))
           ((= eq? eqv? char=? boolean=? symbol=?)
            (cond
              ;; (= x x) -> #t, (eq? x x) -> #t, (eqv? x x) -> #t
              ((= vn1 vn2)
               (let ((true-res (lvn-eval-const #t env)))
                 (list #t (car true-res) (cadr true-res) (caddr true-res))))
              (else (list #f #f #f env))))
           (else (list #f #f #f env)))))
      (else (list #f #f #f env)))))

;;; -----------------------------------------------------------------------
;;; 4. Immutable Pair Accessor Memoization
;;; -----------------------------------------------------------------------

(define (lvn-try-accessor-memoization op opt-args vn-args env)
  (let ((nargs (length opt-args)))
    (if (and (= nargs 1) (pure-accessor-op? op))
        (let* ((arg (car opt-args))
               (vn-p (car vn-args)))
          (cond
            ;; 1. Check if vn-p is known to be constructed by (cons vn-a vn-b)
            ((lvn-vn-is-pair? env vn-p)
             (let* ((target-vn (if (eq? op 'car)
                                   (lvn-vn-pair-car-vn env vn-p)
                                   (lvn-vn-pair-cdr-vn env vn-p)))
                    (canon (lvn-vn-canon-expr env target-vn)))
               (if (and (symbol? canon) (assq canon (lvn-env-vars env)))
                   (list #t canon target-vn env)
                   (if (lvn-vn-is-const? env target-vn)
                       (list #t (val->ast-const (lvn-vn-const-val env target-vn)) target-vn env)
                       (list #t canon target-vn env)))))
            ;; 2. Check if (op vn-p) was already memoized in this basic block / scope
            (else
             (let* ((tuple-key (list op vn-p))
                    (existing-vn (lvn-lookup-tuple env tuple-key)))
               (if existing-vn
                   (let ((canon (lvn-vn-canon-expr env existing-vn)))
                     (if (and (symbol? canon) (assq canon (lvn-env-vars env)))
                         (list #t canon existing-vn env)
                         (if (lvn-vn-is-const? env existing-vn)
                             (list #t (val->ast-const (lvn-vn-const-val env existing-vn)) existing-vn env)
                             (list #t (list op arg) existing-vn env))))
                   ;; Not yet memoized: allocate fresh VN and record (op vn-p)
                   (let* ((alloc-res (lvn-alloc-vn env (list op arg) '()))
                          (new-vn (car alloc-res))
                          (env1 (cdr alloc-res))
                          (env2 (lvn-record-tuple env1 tuple-key new-vn)))
                     (list #t (list op arg) new-vn env2)))))))
        (list #f #f #f env))))

;;; -----------------------------------------------------------------------
;;; 5. Type Predicate Folding
;;; -----------------------------------------------------------------------

(define (lvn-try-predicate-folding op opt-args vn-args env)
  (let ((nargs (length opt-args)))
    (if (and (= nargs 1) (type-predicate-op? op))
        (let* ((arg (car opt-args))
               (vn-x (car vn-args))
               (tuple-key (list op vn-x))
               (existing-vn (lvn-lookup-tuple env tuple-key)))
          (cond
            ;; 1. If (op vn-x) is already recorded as #t in dominance scope
            ((and existing-vn (equal? (lvn-vn-const-val env existing-vn) #t))
             (let ((true-res (lvn-eval-const #t env)))
               (list #t (car true-res) (cadr true-res) (caddr true-res))))
            ;; 2. Check if vn-x has known constant literal
            ((lvn-vn-is-const? env vn-x)
             (let* ((v (lvn-vn-const-val env vn-x))
                    (ans (case op
                           ((fixnum? integer? number?) (number? v))
                           ((pair?) (pair? v))
                           ((null?) (null? v))
                           ((boolean?) (boolean? v))
                           ((char?) (char? v))
                           ((symbol?) (symbol? v))
                           ((zero?) (and (number? v) (= v 0)))
                           (else #f)))
                    (ans-res (lvn-eval-const ans env)))
               (list #t (car ans-res) (cadr ans-res) (caddr ans-res))))
            ;; 3. Check if vn-x has known pair constructor
            ((lvn-vn-is-pair? env vn-x)
             (case op
               ((pair?)
                (let ((t-res (lvn-eval-const #t env)))
                  (list #t (car t-res) (cadr t-res) (caddr t-res))))
               ((null? fixnum? integer? number? boolean? char? symbol?)
                (let ((f-res (lvn-eval-const #f env)))
                  (list #t (car f-res) (cadr f-res) (caddr f-res))))
               (else (list #f #f #f env))))
            ;; 4. Check if producer was arithmetic (produces fixnum)
            ((let ((info (lvn-vn-info env vn-x)))
               (and (pair? info) (eq? (car info) 'type) (eq? (cadr info) 'fixnum)))
             (case op
               ((fixnum? integer? number?)
                (let ((t-res (lvn-eval-const #t env)))
                  (list #t (car t-res) (cadr t-res) (caddr t-res))))
               ((pair? null? boolean? char? symbol?)
                (let ((f-res (lvn-eval-const #f env)))
                  (list #t (car f-res) (cadr f-res) (caddr f-res))))
               (else (list #f #f #f env))))
            (else
             (list #f #f #f env))))
        (list #f #f #f env))))

;;; -----------------------------------------------------------------------
;;; 6. Call & Common Subexpression Elimination (CSE)
;;; -----------------------------------------------------------------------

(define (lvn-eval-call op opt-args vn-args env)
  ;; 1. Check if all args are constants -> Constant Folding via fold-const-op
  (let ((folded (if (let loop ((as opt-args))
                      (if (null? as) #t
                          (and (const? (car as)) (loop (cdr as)))))
                    (fold-const-op op opt-args)
                    #f)))
    (if folded
        (lvn-eval-const folded env)
        ;; 2. Try algebraic identities
        (let ((alg (lvn-try-algebraic-simplification op opt-args vn-args env)))
          (if (car alg)
              (cdr alg)
              ;; 3. Try accessor memoization
              (let ((acc (lvn-try-accessor-memoization op opt-args vn-args env)))
                (if (car acc)
                    (cdr acc)
                    ;; 4. Try type predicate folding
                    (let ((pred (lvn-try-predicate-folding op opt-args vn-args env)))
                      (if (car pred)
                          (cdr pred)
                          ;; 5. General CSE for pure primitives
                          (if (pure-prim? op)
                              (let* ((sorted-vns
                                      (if (and (commutative-op? op) (= (length vn-args) 2))
                                          (if (> (car vn-args) (cadr vn-args))
                                              (list (cadr vn-args) (car vn-args))
                                              vn-args)
                                          vn-args))
                                     (sorted-args
                                      (if (and (commutative-op? op) (= (length vn-args) 2))
                                          (if (> (car vn-args) (cadr vn-args))
                                              (list (cadr opt-args) (car opt-args))
                                              opt-args)
                                          opt-args))
                                     (tuple-key (cons op sorted-vns))
                                     (existing-vn (lvn-lookup-tuple env tuple-key)))
                                (if existing-vn
                                    (let ((canon (lvn-vn-canon-expr env existing-vn)))
                                      (if (and (symbol? canon) (assq canon (lvn-env-vars env)))
                                          (list canon existing-vn env)
                                          (if (lvn-vn-is-const? env existing-vn)
                                              (list (val->ast-const (lvn-vn-const-val env existing-vn)) existing-vn env)
                                              (list (cons op sorted-args) existing-vn env))))
                                    ;; Fresh pure tuple
                                    (let* ((ret-info
                                            (cond
                                              ((eq? op 'cons)
                                               (list 'pair (car sorted-vns) (cadr sorted-vns)))
                                              ((memq op '(+ - * modulo quotient fxadd1 fxsub1))
                                               (list 'type 'fixnum))
                                              (else '())))
                                           (alloc-res (lvn-alloc-vn env (cons op sorted-args) ret-info))
                                           (new-vn (car alloc-res))
                                           (env1 (cdr alloc-res))
                                           (env2 (if (eq? op 'cons)
                                                     env1
                                                     (lvn-record-tuple env1 tuple-key new-vn))))
                                      (list (cons op sorted-args) new-vn env2))))
                              ;; Non-pure or side-effecting call
                              (let* ((env1 (if (memq op '(set-car! set-cdr!))
                                               (lvn-invalidate-pairs env)
                                               env))
                                     (alloc-res (lvn-alloc-vn env1 (cons op opt-args) '()))
                                     (new-vn (car alloc-res))
                                     (env2 (cdr alloc-res)))
                                (list (cons op opt-args) new-vn env2))))))))))))

;;; -----------------------------------------------------------------------
;;; 7. Core Recursive Evaluator (lvn-eval)
;;; -----------------------------------------------------------------------
;;; Returns (list optimized-ast vn updated-env)

(define (lvn-eval expr env)
  (cond
    ((const? expr)
     (lvn-eval-const expr env))
    ((symbol? expr)
     (lvn-eval-var expr env))
    ((pair? expr)
     (let ((op (car expr)))
       (case op
         ((quote)
          (lvn-eval-const expr env))
         ((if)
          (let* ((test-res (lvn-eval (cadr expr) env))
                 (opt-test (car test-res))
                 (vn-test (cadr test-res))
                 (env-test (caddr test-res)))
            (cond
              ;; Constant condition pruning
              ((const? opt-test)
               (if (eq? (extract-const-val opt-test) #f)
                   (if (null? (cdddr expr))
                       (list #f vn-test env-test)
                       (lvn-eval (cadddr expr) env-test))
                   (lvn-eval (caddr expr) env-test)))
              (else
               ;; Branch-specialized dominance environment
               (let* ((then-env
                       (if (and (pair? opt-test) (type-predicate-op? (car opt-test)) (pair? (cdr opt-test)))
                           (let ((arg-entry (assq (cadr opt-test) (lvn-env-vars env-test))))
                             (if arg-entry
                                 (let* ((t-vn (cadr (lvn-eval-const #t env-test)))
                                        (e1 (lvn-record-tuple env-test (list (car opt-test) (cdr arg-entry)) t-vn)))
                                   (if (eq? (car opt-test) 'fixnum?)
                                       (let ((vns (cons (cons (cdr arg-entry) (cons (cadr opt-test) (list 'type 'fixnum)))
                                                        (filter (lambda (e) (not (eq? (car e) (cdr arg-entry))))
                                                                (lvn-env-vns e1)))))
                                         (lvn-set-vns e1 vns))
                                       e1))
                                 env-test))
                           env-test))
                      (then-res (lvn-eval (caddr expr) then-env))
                      (opt-then (car then-res))
                      (else-res (if (null? (cdddr expr))
                                    (list #f (cadr then-res) env-test)
                                    (lvn-eval (cadddr expr) env-test)))
                      (opt-else (car else-res))
                      (alloc-res (lvn-alloc-vn env-test (list 'if opt-test opt-then opt-else) '()))
                      (new-vn (car alloc-res))
                      (new-env (cdr alloc-res)))
                 (list (list 'if opt-test opt-then opt-else) new-vn new-env))))))
         ((let)
          (let ((bindings (cadr expr))
                (body (caddr expr)))
            (cond
              ((null? bindings)
               (lvn-eval body env))
              ((= (length bindings) 1)
               (let* ((var (caar bindings))
                      (val (cadar bindings))
                      (val-res (lvn-eval val env))
                      (opt-val (car val-res))
                      (vn-val (cadr val-res))
                      (env-val (caddr val-res))
                      ;; Bind variable to vn-val
                      (env-body (lvn-bind-var env-val var vn-val))
                      (body-res (lvn-eval body env-body))
                      (opt-body (car body-res))
                      (vn-body (cadr body-res))
                      (orig-vars (lvn-env-vars env-val))
                      ;; Dead let elimination: pure binding whose var is unused in body
                      (dead? (and (atomic-expr? opt-val)
                                  (not (tree-contains? opt-body var)))))
                 (if dead?
                     (list opt-body vn-body (lvn-set-vars (caddr body-res) orig-vars))
                     (list (list 'let (list (list var opt-val)) opt-body)
                           vn-body
                           (lvn-set-vars (caddr body-res) orig-vars)))))
              (else
               ;; Multi-binding let: expand into nested single-binding lets
               (let ((nested-let
                      (let loop ((bs bindings))
                        (if (null? bs)
                            body
                            (list 'let (list (car bs)) (loop (cdr bs)))))))
                 (lvn-eval nested-let env))))))
         ((letrec)
          (let* ((bindings (cadr expr))
                 (body (caddr expr))
                 (opt-bindings
                  (map (lambda (b)
                         (list (car b) (lvn-expr (cadr b) (make-lvn-env))))
                       bindings))
                 (opt-body (lvn-expr body (make-lvn-env))))
            (list (list 'letrec opt-bindings opt-body) 0 env)))
         ((lambda)
          (let* ((params (cadr expr))
                 (body (caddr expr))
                 (child-env (let loop ((ps params) (cur-env (make-lvn-env)))
                              (if (null? ps)
                                  cur-env
                                  (let* ((p (car ps))
                                         (alloc (lvn-alloc-vn cur-env p '()))
                                         (vn (car alloc))
                                         (e1 (cdr alloc))
                                         (e2 (lvn-bind-var e1 p vn)))
                                    (loop (cdr ps) e2)))))
                 (body-res (lvn-eval body child-env))
                 (opt-body (car body-res))
                 (alloc-lam (lvn-alloc-vn env 'lambda-closure '()))
                 (lam-vn (car alloc-lam))
                 (env-lam (cdr alloc-lam)))
            (list (list 'lambda params opt-body) lam-vn env-lam)))
         ((begin)
          (let loop ((es (cdr expr)) (cur-env env) (acc '()))
            (if (null? es)
                (cond
                  ((null? acc) (list #f 0 cur-env))
                  ((null? (cdr acc)) (list (car acc) 0 cur-env))
                  (else (list (cons 'begin acc) 0 cur-env)))
                (let* ((res (lvn-eval (car es) cur-env))
                       (opt-e (car res))
                       (next-env (caddr res)))
                  (loop (cdr es) next-env (append acc (list opt-e)))))))
         ((%make-closure %make-closure-env)
          (let* ((label (cadr expr))
                 (env-args (cddr expr))
                 (evaluated-args
                  (let loop ((as env-args) (cur-env env) (opt-acc '()) (vn-acc '()))
                    (if (null? as)
                        (list (reverse opt-acc) (reverse vn-acc) cur-env)
                        (let ((res (lvn-eval (car as) cur-env)))
                          (loop (cdr as)
                                (caddr res)
                                (cons (car res) opt-acc)
                                (cons (cadr res) vn-acc))))))
                 (opt-env-args (car evaluated-args))
                 (res-env (caddr evaluated-args))
                 (alloc-res (lvn-alloc-vn res-env (car expr) '())))
            (list (cons (car expr) (cons label opt-env-args))
                  (car alloc-res)
                  (cdr alloc-res))))
         (else
          ;; Primitive or function application: (op arg1 arg2 ...)
          (let* ((opt-op (if (symbol? op) op (car (lvn-eval op env))))
                 (args (cdr expr))
                 (evaluated-args
                  (let loop ((as args) (cur-env env) (opt-acc '()) (vn-acc '()))
                    (if (null? as)
                        (list (reverse opt-acc) (reverse vn-acc) cur-env)
                        (let ((res (lvn-eval (car as) cur-env)))
                          (loop (cdr as)
                                (caddr res)
                                (cons (car res) opt-acc)
                                (cons (cadr res) vn-acc))))))
                 (opt-args (car evaluated-args))
                 (vn-args (cadr evaluated-args))
                 (cur-env (caddr evaluated-args)))
            (if (symbol? opt-op)
                (lvn-eval-call opt-op opt-args vn-args cur-env)
                (let* ((call-expr (cons opt-op opt-args))
                       (alloc-res (lvn-alloc-vn cur-env call-expr '())))
                  (list call-expr (car alloc-res) (cdr alloc-res)))))))))
    (else
     (list expr 0 env))))

(define (lvn-expr expr env)
  (car (lvn-eval expr env)))

;;; -----------------------------------------------------------------------
;;; 8. Top-level Pass Entrypoint: lvn-all
;;; -----------------------------------------------------------------------

(define (lvn-all form)
  (cond
    ((not (pair? form)) form)
    ((eq? (car form) '%program)
     (let ((defs (cadr form))
           (main (caddr form)))
       (list '%program
             (map (lambda (d)
                    (if (and (pair? d) (eq? (car d) 'define))
                        (list 'define (cadr d) (lvn-expr (caddr d) (make-lvn-env)))
                        (lvn-expr d (make-lvn-env))))
                  defs)
             (lvn-expr main (make-lvn-env)))))
    ((eq? (car form) 'define)
     (list 'define (cadr form) (lvn-expr (caddr form) (make-lvn-env))))
    (else
     (lvn-expr form (make-lvn-env)))))
;;; =======================================================================
;;; ULisp Compiler Pass 4: ANF (A-Normal Form) Normalization Nanopass
;;; Conforms to DSN-33 Architecture Specification
;;; Note: Normalizes complex expressions so that all function/primitive
;;;       arguments are atomic (symbols or immediate constants).
;;;       Uses a scoped temporary variable pool (%t0..%t8) to eliminate
;;;       string->symbol heap allocation overhead during bootstrap.
;;; =======================================================================

;;; Fixed pool of temporary variables by nesting depth (Zero heap allocation for depth < 64)
(define (%t-var depth)
  (case depth
    ((0) '%t0)   ((1) '%t1)   ((2) '%t2)   ((3) '%t3)
    ((4) '%t4)   ((5) '%t5)   ((6) '%t6)   ((7) '%t7)
    ((8) '%t8)   ((9) '%t9)   ((10) '%t10) ((11) '%t11)
    ((12) '%t12) ((13) '%t13) ((14) '%t14) ((15) '%t15)
    ((16) '%t16) ((17) '%t17) ((18) '%t18) ((19) '%t19)
    ((20) '%t20) ((21) '%t21) ((22) '%t22) ((23) '%t23)
    ((24) '%t24) ((25) '%t25) ((26) '%t26) ((27) '%t27)
    ((28) '%t28) ((29) '%t29) ((30) '%t30) ((31) '%t31)
    ((32) '%t32) ((33) '%t33) ((34) '%t34) ((35) '%t35)
    ((36) '%t36) ((37) '%t37) ((38) '%t38) ((39) '%t39)
    ((40) '%t40) ((41) '%t41) ((42) '%t42) ((43) '%t43)
    ((44) '%t44) ((45) '%t45) ((46) '%t46) ((47) '%t47)
    ((48) '%t48) ((49) '%t49) ((50) '%t50) ((51) '%t51)
    ((52) '%t52) ((53) '%t53) ((54) '%t54) ((55) '%t55)
    ((56) '%t56) ((57) '%t57) ((58) '%t58) ((59) '%t59)
    ((60) '%t60) ((61) '%t61) ((62) '%t62) ((63) '%t63)
    (else (string->symbol (string-append "__anf_t_" (number->string depth))))))

;;; Collects bindings for non-atomic expressions among a list of arguments.
;;; Returns a pair (bindings . atomic-args).
(define (anf-flatten-args args depth)
  (let loop ((rest args) (d depth) (bindings '()) (atom-args '()))
    (if (null? rest)
        (cons (reverse bindings) (reverse atom-args))
        (let ((arg (car rest)))
          (if (atomic-expr? arg)
              (loop (cdr rest) d bindings (cons arg atom-args))
              (let* ((flat-arg (anf-expr-depth arg (+ d 1)))
                     (tmp (%t-var d)))
                (loop (cdr rest)
                      (+ d 1)
                      (cons (list tmp flat-arg) bindings)
                      (cons tmp atom-args))))))))

;;; Wraps an expression with let-bindings if any exist
(define (anf-wrap-bindings bindings body)
  (if (null? bindings)
      body
      (list 'let bindings body)))

;;; Recursively normalizes an arbitrary expression into A-Normal Form with nesting depth tracking
(define (anf-expr-depth expr depth)
  (cond
    ((atomic-expr? expr) expr)
    ((pair? expr)
     (let ((op (car expr)))
       (case op
         ((quote) expr)
         ((if)
          (let ((test (cadr expr))
                (then (caddr expr))
                (else-val (if (null? (cdddr expr)) #f (cadddr expr))))
            (if (atomic-expr? test)
                (list 'if test (anf-expr-depth then depth) (anf-expr-depth else-val depth))
                (let* ((flat-test (anf-expr-depth test (+ depth 1)))
                       (tmp (%t-var depth)))
                  (list 'let (list (list tmp flat-test))
                        (list 'if tmp (anf-expr-depth then depth) (anf-expr-depth else-val depth)))))))
         ((begin)
          (let ((body (cdr expr)))
            (cond
              ((null? body) #f)
              ((null? (cdr body)) (anf-expr-depth (car body) depth))
              (else (cons 'begin (map (lambda (e) (anf-expr-depth e depth)) body))))))
         ((let)
          (let ((bindings (cadr expr))
                (body (caddr expr)))
            (list 'let
                  (map (lambda (b) (list (car b) (anf-expr-depth (cadr b) depth))) bindings)
                  (anf-expr-depth body depth))))
         ((letrec)
          (let ((bindings (cadr expr))
                (body (caddr expr)))
            (list 'letrec
                  (map (lambda (b) (list (car b) (anf-expr-depth (cadr b) depth))) bindings)
                  (anf-expr-depth body depth))))
         ((lambda)
          (let ((params (cadr expr))
                (body (caddr expr)))
            (list 'lambda params (anf-expr-depth body 0))))
         ((%make-closure %make-closure-env)
          (let* ((op-tag (car expr))
                 (label (cadr expr))
                 (env-args (cddr expr))
                 (res (anf-flatten-args env-args depth))
                 (bindings (car res))
                 (atom-env (cdr res)))
            (anf-wrap-bindings bindings (cons op-tag (cons label atom-env)))))
         ((%with-handler %call-with-values %values %raw-call/cc)
          (let* ((res (anf-flatten-args (cdr expr) depth))
                 (bindings (car res))
                 (atom-args (cdr res)))
            (anf-wrap-bindings bindings (cons (car expr) atom-args))))
         (else
          ;; Primitive or function application: (op e1 e2 ...)
          (let* ((args-res (anf-flatten-args (cdr expr) depth))
                 (args-bindings (car args-res))
                 (atom-args (cdr args-res))
                 (flat-op (if (atomic-expr? op) op (anf-expr-depth op (+ depth (length args-bindings)))))
                 (call (cons flat-op atom-args)))
            (anf-wrap-bindings args-bindings call))))))
    (else expr)))

;;; Top-level entrypoint for ANF normalization
(define (anf-all form)
  (let ((res
         (cond
           ((not (pair? form)) form)
           ((eq? (car form) '%program)
            (let ((defs (cadr form))
                  (main (caddr form)))
              (list '%program
                    (map (lambda (d)
                           (if (and (pair? d) (eq? (car d) 'define))
                               (list 'define (cadr d) (anf-expr-depth (caddr d) 0))
                               (anf-expr-depth d 0)))
                         defs)
                    (anf-expr-depth main 0))))
           ((eq? (car form) 'define)
            (list 'define (cadr form) (anf-expr-depth (caddr form) 0)))
           (else
            (anf-expr-depth form 0)))))
    (if (and (verifier-enabled?) (assq 'L_anf (nanopass-get-languages)))
        (if (not (nanopass-ast-valid? 'L_anf res))
            (verifier-error 'anf "Pass 070 output violates L_anf schema invariants" res)))
    res))
;;; =======================================================================
;;; ULisp Compiler Pass 4b: S-Annotator (Abstract Interpretation Type Inference)
;;; Conforms to DSN-33 Architecture Specification & Issue #517
;;; Note: Performs abstract interpretation on ANF-normalized Scheme AST.
;;;       Infers types and range intervals using a monotone lattice (LUB),
;;;       populates type annotations, and supports R-Scheme type checking.
;;; =======================================================================

;;; -----------------------------------------------------------------------
;;; 1. Type Lattice Constructors & Predicates
;;; -----------------------------------------------------------------------

(define (type-bot) 'bot)
(define (type-top) 'top)
(define (type-fixnum) 'fixnum)
(define (type-fixnum-range min-val max-val) (list 'fixnum min-val max-val))
(define (type-boolean) 'boolean)
(define (type-pair car-t cdr-t) (list 'pair car-t cdr-t))
(define (type-null) 'null)
(define (type-string) 'string)
(define (type-symbol) 'symbol)
(define (type-char) 'char)
(define (type-closure id arg-types ret-type) (list 'closure id arg-types ret-type))

(define (type-bot? t) (eq? t 'bot))
(define (type-top? t) (eq? t 'top))
(define (type-fixnum? t)
  (or (eq? t 'fixnum)
      (and (pair? t) (eq? (car t) 'fixnum))))
(define (type-has-range? t)
  (and (pair? t) (eq? (car t) 'fixnum) (= (length t) 3)))
(define (type-range-min t) (cadr t))
(define (type-range-max t) (caddr t))

(define (type-boolean? t) (eq? t 'boolean))
(define (type-pair? t) (and (pair? t) (eq? (car t) 'pair)))
(define (type-pair-car t) (if (type-pair? t) (cadr t) (type-top)))
(define (type-pair-cdr t) (if (type-pair? t) (caddr t) (type-top)))

(define (type-null? t) (eq? t 'null))
(define (type-string? t) (eq? t 'string))
(define (type-symbol? t) (eq? t 'symbol))
(define (type-char? t) (eq? t 'char))
(define (type-closure? t) (and (pair? t) (eq? (car t) 'closure)))

(define (temp-var? sym)
  (and (symbol? sym)
       (let ((str (symbol->string sym)))
         (and (> (string-length str) 1)
              (char=? (string-ref str 0) #\%)
              (char=? (string-ref str 1) #\t)))))

;;; -----------------------------------------------------------------------
;;; 2. Lattice Join (Least Upper Bound: LUB, \sqcup) & Meet (GLB, \sqcap)
;;; -----------------------------------------------------------------------

(define (type-equal? t1 t2)
  (cond
    ((and (symbol? t1) (symbol? t2)) (eq? t1 t2))
    ((and (number? t1) (number? t2)) (= t1 t2))
    ((and (boolean? t1) (boolean? t2)) (eq? t1 t2))
    ((and (null? t1) (null? t2)) #t)
    ((and (pair? t1) (pair? t2))
     (and (type-equal? (car t1) (car t2))
          (type-equal? (cdr t1) (cdr t2))))
    (else (eq? t1 t2))))

(define (type-lub t1 t2)
  (cond
    ((type-bot? t1) t2)
    ((type-bot? t2) t1)
    ((type-top? t1) (type-top))
    ((type-top? t2) (type-top))
    ((type-equal? t1 t2) t1)
    ;; Range & Fixnum unification
    ((and (type-fixnum? t1) (type-fixnum? t2))
     (if (and (type-has-range? t1) (type-has-range? t2))
         (let ((min1 (type-range-min t1))
               (max1 (type-range-max t1))
               (min2 (type-range-min t2))
               (max2 (type-range-max t2)))
           (type-fixnum-range (if (< min1 min2) min1 min2)
                              (if (> max1 max2) max1 max2)))
         (type-fixnum)))
    ;; Pair unification
    ((and (type-pair? t1) (type-pair? t2))
     (type-pair (type-lub (type-pair-car t1) (type-pair-car t2))
                (type-lub (type-pair-cdr t1) (type-pair-cdr t2))))
    ;; List-like: Pair and Null join to Pair(top, top) or Top
    ((and (or (type-pair? t1) (type-null? t1))
          (or (type-pair? t2) (type-null? t2)))
     (type-top))
    ;; Disjoint types join to Top (dynamic / any)
    (else (type-top))))

(define (type-meet t1 t2)
  (cond
    ((type-bot? t1) (type-bot))
    ((type-bot? t2) (type-bot))
    ((type-top? t1) t2)
    ((type-top? t2) t1)
    ((type-equal? t1 t2) t1)
    ;; Range & Fixnum meet
    ((and (type-fixnum? t1) (type-fixnum? t2))
     (cond
       ((and (type-has-range? t1) (type-has-range? t2))
        (let* ((min1 (type-range-min t1))
               (max1 (type-range-max t1))
               (min2 (type-range-min t2))
               (max2 (type-range-max t2))
               (new-min (if (> min1 min2) min1 min2))
               (new-max (if (< max1 max2) max1 max2)))
          (if (> new-min new-max)
              (type-bot)
              (type-fixnum-range new-min new-max))))
       ((type-has-range? t1) t1)
       ((type-has-range? t2) t2)
       (else (type-fixnum))))
    ;; Pair meet
    ((and (type-pair? t1) (type-pair? t2))
     (let ((car-m (type-meet (type-pair-car t1) (type-pair-car t2)))
           (cdr-m (type-meet (type-pair-cdr t1) (type-pair-cdr t2))))
       (if (or (type-bot? car-m) (type-bot? cdr-m))
           (type-bot)
           (type-pair car-m cdr-m))))
    ;; Disjoint types meet to Bottom
    (else (type-bot))))

;;; -----------------------------------------------------------------------
;;; 3. Type Environment Management & Predicate Extraction
;;; -----------------------------------------------------------------------

(define (type-env-lookup var env)
  (let ((entry (assq var env)))
    (if entry
        (cdr entry)
        (type-top))))

(define (type-env-lookup-fact var env)
  (let loop ((rest env))
    (cond
      ((null? rest) #f)
      ((and (pair? (car rest))
            (pair? (caar rest))
            (eq? (car (caar rest)) '%fact)
            (eq? (cdr (caar rest)) var))
       (cdar rest))
      (else (loop (cdr rest))))))

(define (type-env-extend var type env)
  (cons (cons var type) env))

(define (type-env-extend-with-fact var type fact env)
  (cons (cons (cons '%fact var) fact)
        (cons (cons var type) env)))

(define (type-env-extend-multi vars types env)
  (if (or (null? vars) (null? types))
      env
      (cons (cons (car vars) (car types))
            (type-env-extend-multi (cdr vars) (cdr types) env))))

(define (type-env-merge env1 env2)
  (let loop ((rest env1) (acc '()))
    (if (null? rest)
        acc
        (let* ((var (caar rest))
               (t1 (type-env-lookup var env1))
               (t2 (type-env-lookup var env2)))
          (loop (cdr rest) (cons (cons var (type-lub t1 t2)) acc))))))

(define (predicate-op? op)
  (memq op '(fixnum? integer? number? pair? boolean? null? symbol? string? char? procedure? zero? = < <= > >= not)))

(define (extract-predicate-narrowing test env)
  (cond
    ;; Variable lookup: check if variable was bound to a predicate fact in ANF let
    ((symbol? test)
     (let ((fact (type-env-lookup-fact test env)))
       (if fact
           (extract-predicate-narrowing fact env)
           (cons #f #f))))
    ((not (pair? test))
     (cons #f #f))
    (else
     (let ((op (car test)))
       (cond
         ((memq op '(fixnum? integer? number?))
          (if (and (pair? (cdr test)) (symbol? (cadr test)))
              (let ((var (cadr test)))
                (cons (cons var (type-fixnum))
                      (cons var (if (type-fixnum? (type-env-lookup var env)) (type-bot) (type-env-lookup var env)))))
              (cons #f #f)))
         ((eq? op 'pair?)
          (if (and (pair? (cdr test)) (symbol? (cadr test)))
              (let ((var (cadr test)))
                (cons (cons var (type-pair (type-top) (type-top)))
                      (cons var (if (type-pair? (type-env-lookup var env)) (type-bot) (type-env-lookup var env)))))
              (cons #f #f)))
         ((eq? op 'boolean?)
          (if (and (pair? (cdr test)) (symbol? (cadr test)))
              (let ((var (cadr test)))
                (cons (cons var (type-boolean))
                      (cons var (if (type-boolean? (type-env-lookup var env)) (type-bot) (type-env-lookup var env)))))
              (cons #f #f)))
         ((eq? op 'null?)
          (if (and (pair? (cdr test)) (symbol? (cadr test)))
              (let ((var (cadr test)))
                (cons (cons var (type-null))
                      (cons var (if (type-null? (type-env-lookup var env)) (type-bot) (type-env-lookup var env)))))
              (cons #f #f)))
         ((eq? op 'symbol?)
          (if (and (pair? (cdr test)) (symbol? (cadr test)))
              (let ((var (cadr test)))
                (cons (cons var (type-symbol))
                      (cons var (if (type-symbol? (type-env-lookup var env)) (type-bot) (type-env-lookup var env)))))
              (cons #f #f)))
         ((eq? op 'string?)
          (if (and (pair? (cdr test)) (symbol? (cadr test)))
              (let ((var (cadr test)))
                (cons (cons var (type-string))
                      (cons var (if (type-string? (type-env-lookup var env)) (type-bot) (type-env-lookup var env)))))
              (cons #f #f)))
         ((eq? op 'char?)
          (if (and (pair? (cdr test)) (symbol? (cadr test)))
              (let ((var (cadr test)))
                (cons (cons var (type-char))
                      (cons var (if (type-char? (type-env-lookup var env)) (type-bot) (type-env-lookup var env)))))
              (cons #f #f)))
         ((eq? op 'procedure?)
          (if (and (pair? (cdr test)) (symbol? (cadr test)))
              (let ((var (cadr test)))
                (cons (cons var (type-closure 'any '() (type-top)))
                      (cons var (type-env-lookup var env))))
              (cons #f #f)))
         ((eq? op 'zero?)
          (if (and (pair? (cdr test)) (symbol? (cadr test)))
              (let ((var (cadr test)))
                (cons (cons var (type-fixnum-range 0 0))
                      (cons var (type-env-lookup var env))))
              (cons #f #f)))
         ((eq? op '=)
          (cond
            ((and (pair? (cdr test)) (pair? (cddr test))
                  (symbol? (cadr test)) (number? (caddr test)))
             (let ((var (cadr test)) (n (caddr test)))
               (cons (cons var (type-fixnum-range n n))
                     (cons var (type-env-lookup var env)))))
            ((and (pair? (cdr test)) (pair? (cddr test))
                  (number? (cadr test)) (symbol? (caddr test)))
             (let ((var (caddr test)) (n (cadr test)))
               (cons (cons var (type-fixnum-range n n))
                     (cons var (type-env-lookup var env)))))
            (else (cons #f #f))))
         ((eq? op 'not)
          (if (pair? (cdr test))
              (let ((sub (extract-predicate-narrowing (cadr test) env)))
                (cons (cdr sub) (car sub)))
              (cons #f #f)))
         (else (cons #f #f)))))))

(define (narrow-var-in-branch var test branch-then? env)
  (let* ((narrowing (extract-predicate-narrowing test env))
         (info (if branch-then? (car narrowing) (cdr narrowing))))
    (if (and (pair? info) (eq? (car info) var))
        (type-meet (type-env-lookup var env) (cdr info))
        (type-env-lookup var env))))

;;; Global Type Tables for Whole-Program Traceability
(define *global-type-env* (cons '() '()))
(define *expr-type-table* (cons '() '()))

(define (reset-type-annotations!)
  (set-car! *global-type-env* '())
  (set-car! *expr-type-table* '()))

(define (record-var-type! var type)
  (set-car! *global-type-env* (cons (cons var type) (car *global-type-env*))))

(define (get-var-type var)
  (type-env-lookup var (car *global-type-env*)))

(define (record-expr-type! expr-id type)
  (set-car! *expr-type-table* (cons (cons expr-id type) (car *expr-type-table*))))

(define (get-expr-type expr-id)
  (type-env-lookup expr-id (car *expr-type-table*)))

;;; -----------------------------------------------------------------------
;;; 4. Abstract Evaluation Engine for ANF Expressions
;;; -----------------------------------------------------------------------

;;; Arithmetic abstract transfer functions
(define (abstract-eval-arith op t1 t2)
  (if (and (type-fixnum? t1) (type-fixnum? t2))
      (if (and (type-has-range? t1) (type-has-range? t2))
          (let ((min1 (type-range-min t1))
                (max1 (type-range-max t1))
                (min2 (type-range-min t2))
                (max2 (type-range-max t2)))
            (case op
              ((+) (type-fixnum-range (+ min1 min2) (+ max1 max2)))
              ((-) (type-fixnum-range (- min1 max2) (- max1 min2)))
              ((*) (type-fixnum))
              (else (type-fixnum))))
          (type-fixnum))
      (type-fixnum)))

;;; Primitive procedure abstract evaluation
(define (abstract-eval-prim op arg-types)
  (cond
    ;; Arithmetic
    ((memq op '(+ - * modulo quotient / bitwise-and bitwise-ior bitwise-arithmetic-shift))
     (let ((t1 (if (pair? arg-types) (car arg-types) (type-top)))
           (t2 (if (and (pair? arg-types) (pair? (cdr arg-types))) (cadr arg-types) (type-top))))
       (abstract-eval-arith op t1 t2)))
    ((memq op '(fxadd1 fxsub1 %to-raw %to-fixnum))
     (type-fixnum))
    ;; Predicates -> Boolean
    ((memq op '(= < <= > >= eq? eqv? char=? boolean=? symbol=? zero? fixnum? integer? number? exact? exact-integer? inexact? real? rational? complex? boolean? char? null? not symbol? pair? procedure? string? list? eof-object?))
     (type-boolean))
    ;; Data structure primitives
    ((eq? op 'cons)
     (let ((t1 (if (pair? arg-types) (car arg-types) (type-top)))
           (t2 (if (and (pair? arg-types) (pair? (cdr arg-types))) (cadr arg-types) (type-top))))
       (type-pair t1 t2)))
    ((eq? op 'car)
     (let ((t (if (pair? arg-types) (car arg-types) (type-top))))
       (type-pair-car t)))
    ((eq? op 'cdr)
     (let ((t (if (pair? arg-types) (car arg-types) (type-top))))
       (type-pair-cdr t)))
    ((memq op '(string-length bytevector-length bytevector-u8-ref vector-length %num-args))
     (type-fixnum))
    ((memq op '(bytevector? vector?))
     (type-boolean))
    ((memq op '(make-string string-ref))
     (if (eq? op 'make-string) (type-string) (type-char)))
    ((memq op '(%get-rsp %get-heap-ptr %get-gc-state-ptr %raw-load %ptr-add %ptr-tag-add))
     (type-fixnum))
    (else (type-top))))

;;; Abstract evaluation of arbitrary ANF expression
(define (abstract-eval-expr expr env)
  (cond
    ;; Integer literal
    ((number? expr)
     (type-fixnum-range expr expr))
    ;; Boolean literal
    ((boolean? expr)
     (type-boolean))
    ;; Char literal
    ((char? expr)
     (type-char))
    ;; String literal
    ((string? expr)
     (type-string))
    ;; Null literal
    ((null? expr)
     (type-null))
    ;; Symbol lookup
    ((symbol? expr)
     (type-env-lookup expr env))
    ;; Quoted constant
    ((and (pair? expr) (eq? (car expr) 'quote))
     (let ((datum (cadr expr)))
       (cond
         ((number? datum) (type-fixnum-range datum datum))
         ((boolean? datum) (type-boolean))
         ((char? datum) (type-char))
         ((string? datum) (type-string))
         ((null? datum) (type-null))
         ((symbol? datum) (type-symbol))
         ((pair? datum) (type-pair (type-top) (type-top)))
         (else (type-top)))))
    ;; Compound ANF forms
    ((pair? expr)
     (let ((op (car expr)))
       (case op
         ;; Conditional branching with flow-sensitive narrowing
         ((if)
          (let* ((test-expr (cadr expr))
                 (narrowing (extract-predicate-narrowing test-expr env))
                 (then-narrow (car narrowing))
                 (else-narrow (cdr narrowing))
                 (then-env (if (pair? then-narrow)
                               (let* ((var (car then-narrow))
                                      (curr-t (type-env-lookup var env))
                                      (new-t (type-meet curr-t (cdr then-narrow))))
                                 (type-env-extend var new-t env))
                               env))
                 (else-env (if (pair? else-narrow)
                               (let* ((var (car else-narrow))
                                      (curr-t (type-env-lookup var env))
                                      (new-t (type-meet curr-t (cdr else-narrow))))
                                 (type-env-extend var new-t env))
                               env))
                 (then-t (abstract-eval-expr (caddr expr) then-env))
                 (else-t (if (null? (cdddr expr))
                             (type-boolean)
                             (abstract-eval-expr (cadddr expr) else-env))))
            (type-lub then-t else-t)))
         ;; Sequential execution
         ((begin)
          (let loop ((rest (cdr expr)) (last-t (type-top)))
            (if (null? rest)
                last-t
                (loop (cdr rest) (abstract-eval-expr (car rest) env)))))
         ;; Local let bindings
         ((let)
          (if (symbol? (cadr expr))
              ;; Named let (loop): Fixpoint iteration
              (abstract-eval-named-let (cadr expr) (caddr expr) (cdddr expr) env)
              ;; Standard let
              (let* ((bindings (cadr expr))
                     (body (cddr expr))
                     (new-env (let bind-loop ((bs bindings) (e env))
                                (if (null? bs)
                                    e
                                    (let* ((b (car bs))
                                           (var (car b))
                                           (rhs (cadr b))
                                           (val-t (abstract-eval-expr rhs env))
                                           (fact (if (and (pair? rhs) (predicate-op? (car rhs)))
                                                     rhs
                                                     #f)))
                                      (if (not (temp-var? var))
                                          (record-var-type! var val-t))
                                      (bind-loop (cdr bs)
                                                 (if fact
                                                     (type-env-extend-with-fact var val-t fact e)
                                                     (type-env-extend var val-t e))))))))
                (let body-loop ((rest body) (last-t (type-top)))
                  (if (null? rest)
                      last-t
                      (body-loop (cdr rest) (abstract-eval-expr (car rest) new-env)))))))
         ;; Mutual recursion (letrec)
         ((letrec)
          (let* ((bindings (cadr expr))
                 (body-expr (if (null? (cddr expr)) #f (caddr expr))))
            (if (and (= (length bindings) 1)
                     (let* ((b (car bindings))
                            (val (cadr b)))
                       (and (pair? val) (eq? (car val) 'lambda)))
                     (pair? body-expr)
                     (eq? (car body-expr) (caar bindings))
                     (let check-nums ((is (cdr body-expr)))
                       (if (null? is) #t
                           (if (number? (car is))
                               (check-nums (cdr is))
                               #f))))
                ;; Desugared named-let loop
                (let* ((b (car bindings))
                       (fn-name (car b))
                       (fn-val (cadr b))
                       (params (cadr fn-val))
                       (lbodies (cddr fn-val))
                       (inits (cdr body-expr))
                       (named-bindings (let make-bs ((ps params) (is inits) (acc '()))
                                         (if (or (null? ps) (null? is))
                                             (reverse acc)
                                             (make-bs (cdr ps) (cdr is) (cons (list (car ps) (car is)) acc))))))
                  (abstract-eval-named-let fn-name named-bindings lbodies env))
                ;; General letrec
                (let* ((body (cddr expr))
                       (new-env (let bind-loop ((bs bindings) (e env))
                                  (if (null? bs)
                                      e
                                      (let ((var (caar bs)))
                                        (bind-loop (cdr bs) (type-env-extend var (type-top) e)))))))
                  (let body-loop ((rest body) (last-t (type-top)))
                    (if (null? rest)
                        last-t
                        (body-loop (cdr rest) (abstract-eval-expr (car rest) new-env))))))))
         ;; Lambda abstraction
         ((lambda)
          (let ((params (cadr expr)))
            (type-closure (unique-label-sym "lam") params (type-top))))
         ((%with-handler %call-with-values %values %raw-call/cc)
          (type-top))
         ;; Procedure call or primitive
         (else
          (let ((arg-types (map (lambda (a) (abstract-eval-expr a env)) (cdr expr))))
            (if (or (unary-prim? op) (binop-prim? op) (triop-prim? op) (zero-arg-prim? op) (septop-prim? op))
                (abstract-eval-prim op arg-types)
                (let ((fn-t (abstract-eval-expr op env)))
                  (if (type-closure? fn-t)
                      (cadddr fn-t)
                      (type-top)))))))))
    (else (type-top))))

;;; -----------------------------------------------------------------------
;;; 5. Named-let & Loop Fixpoint Iteration
;;; -----------------------------------------------------------------------

(define (abstract-eval-named-let loop-name bindings body env)
  (let* ((vars (map car* bindings))
         (init-types (map (lambda (b) (abstract-eval-expr (cadr b) env)) bindings)))
    ;; Iterative fixpoint loop up to 5 steps
    (let fixpoint-loop ((step 0)
                        (current-arg-types init-types)
                        (current-ret-type (type-bot)))
      (let* ((loop-closure (type-closure loop-name vars current-ret-type))
             (loop-env (type-env-extend loop-name loop-closure
                                        (type-env-extend-multi vars current-arg-types env)))
             ;; Evaluate body expressions under loop-env
             (body-type (let eval-body ((rest body) (last-t (type-bot)))
                          (if (null? rest)
                              last-t
                              (eval-body (cdr rest) (abstract-eval-expr (car rest) loop-env)))))
             (next-ret-type (type-lub current-ret-type body-type)))
        (if (or (>= step 4)
                (type-equal? next-ret-type current-ret-type))
            ;; Fixpoint reached or widened
            (begin
              (let rec-rec ((vs vars) (ts current-arg-types))
                (if (and (pair? vs) (pair? ts))
                    (begin
                      (record-var-type! (car vs) (car ts))
                      (rec-rec (cdr vs) (cdr ts)))))
              (if (type-bot? next-ret-type) (type-top) next-ret-type))
            ;; Continue fixpoint iteration
            (fixpoint-loop (+ step 1) current-arg-types next-ret-type))))))

;;; -----------------------------------------------------------------------
;;; 6. Whole-Form Annotation Driver Pass
;;; -----------------------------------------------------------------------

(define (annotate-form form)
  (cond
    ((and (pair? form) (eq? (car form) 'define))
     (let ((head (cadr form))
           (body (cddr form)))
       (if (pair? head)
           ;; (define (name args...) body...)
           (let* ((fn-name (car head))
                  (params (cdr head))
                  (param-types (map (lambda (p) (type-top)) params))
                  (fn-env (type-env-extend-multi params param-types '()))
                  (ret-type (let eval-b ((rest body) (last-t (type-top)))
                              (if (null? rest)
                                  last-t
                                  (eval-b (cdr rest) (abstract-eval-expr (car rest) fn-env))))))
             (record-var-type! fn-name (type-closure fn-name params ret-type))
             form)
           ;; (define name val)
           (let* ((var head)
                  (val-t (abstract-eval-expr (car body) '())))
             (record-var-type! var val-t)
             form))))
    (else
     (abstract-eval-expr form '())
     form)))

(define (annotate-all form-or-forms)
  (reset-type-annotations!)
  (cond
    ((null? form-or-forms) '())
    ((not (pair? form-or-forms))
     (abstract-eval-expr form-or-forms '())
     form-or-forms)
    ((eq? (car form-or-forms) '%program)
     (let ((defs (cadr form-or-forms))
           (main (caddr form-or-forms)))
       (let rec ((ds defs))
         (if (pair? ds)
             (begin
               (annotate-form (car ds))
               (rec (cdr ds)))))
       (abstract-eval-expr main '())
       form-or-forms))
    ((eq? (car form-or-forms) 'define)
     (annotate-form form-or-forms))
    ((eq? (car form-or-forms) 'letrec)
     (let ((bindings (cadr form-or-forms))
           (body (cddr form-or-forms)))
       (if (= (length bindings) 1)
           (abstract-eval-expr form-or-forms '())
           (let rec ((bs bindings))
             (if (pair? bs)
                 (let* ((b (car bs))
                        (var (car b))
                        (val (cadr b)))
                   (if (and (pair? val) (eq? (car val) 'lambda))
                       (let* ((params (cadr val))
                              (param-types (map (lambda (p) (type-top)) params)))
                         (record-var-type! var (type-closure var params (type-top))))
                       (record-var-type! var (type-top)))
                   (rec (cdr bs))))))
       form-or-forms))
    (else
     (abstract-eval-expr form-or-forms '())
     form-or-forms)))
;;; =======================================================================
;;; ULisp Compiler Pass 5b: S-RTyper (Representation Typer & Unboxing Lowering)
;;; Conforms to DSN-33 Architecture Specification & Issue #518
;;; Note: Lowers high-level abstract types (inferred by S-Annotator Pass 4b)
;;;       to concrete hardware representations (%raw-i64, untagged registers).
;;;       Eliminates sar/sal tagging overhead in pure arithmetic loops and
;;;       inserts explicit boxing/unboxing boundaries at Scheme dynamic edges.
;;; =======================================================================

(define *unboxed-functions* (cons '() '()))
(define *rtyper-facts* (cons '() '()))

(define (reset-rtyper!)
  (set-car! *unboxed-functions* '())
  (set-car! *rtyper-facts* '()))

(define (record-rtyper-fact! var fact)
  (set-car! *rtyper-facts* (cons (cons var fact) (car *rtyper-facts*))))

(define (get-rtyper-fact var)
  (let ((e (assq var (car *rtyper-facts*))))
    (if e (cdr e) #f)))

(define (record-unboxed-fn! name)
  (set-car! *unboxed-functions* (cons name (car *unboxed-functions*))))

(define (unboxed-fn? name)
  (memq name (car *unboxed-functions*)))

(define (raw-var? var raw-env)
  (memq var raw-env))

(define (fixnum-test-var test)
  (cond
    ((symbol? test)
     (let ((fact (get-rtyper-fact test)))
       (if fact (fixnum-test-var fact) #f)))
    ((and (pair? test) (memq (car test) '(fixnum? integer? number?)) (pair? (cdr test)) (symbol? (cadr test)))
     (cadr test))
    (else #f)))

(define (fold-type-pred op arg)
  (case op
    ((fixnum? integer? number?)
     (cond ((integer? arg) #t)
           ((or (string? arg) (boolean? arg) (null? arg) (pair? arg)) #f)
           (else 'unknown)))
    ((string?)
     (cond ((string? arg) #t)
           ((or (integer? arg) (boolean? arg) (null? arg) (pair? arg)) #f)
           (else 'unknown)))
    ((boolean?)
     (cond ((boolean? arg) #t)
           ((or (integer? arg) (string? arg) (null? arg) (pair? arg)) #f)
           (else 'unknown)))
    ((null?)
     (cond ((null? arg) #t)
           ((or (integer? arg) (string? arg) (boolean? arg) (pair? arg)) #f)
           (else 'unknown)))
    ((pair?)
     (cond ((pair? arg) #t)
           ((or (integer? arg) (string? arg) (boolean? arg) (null? arg)) #f)
           (else 'unknown)))
    ((zero?)
     (cond ((integer? arg) (if (= arg 0) #t #f))
           (else 'unknown)))
    (else 'unknown)))

(define (specialize-var-in-body body var val)
  (cond
    ((eq? body var) val)
    ((not (pair? body)) body)
    ((eq? (car body) 'quote) body)
    ;; Type predicate test on var
    ((and (memq (car body) '(fixnum? integer? number? string? boolean? null? pair? zero?))
          (pair? (cdr body))
          (eq? (cadr body) var))
     (let ((folded (fold-type-pred (car body) val)))
       (if (eq? folded 'unknown)
           (list (car body) (specialize-var-in-body (cadr body) var val))
           folded)))
    ;; Conditional branch pruning
    ((eq? (car body) 'if)
     (let* ((test (specialize-var-in-body (cadr body) var val))
            (then (specialize-var-in-body (caddr body) var val))
            (else-part (if (null? (cdddr body)) #f (specialize-var-in-body (cadddr body) var val))))
       (cond
         ((eq? test #t) then)
         ((eq? test #f) else-part)
         (else (list 'if test then else-part)))))
    (else
     (cons (specialize-var-in-body (car body) var val)
           (specialize-var-in-body (cdr body) var val)))))

(define (all-fixnum-params? params)
  (let loop ((ps params))
    (if (null? ps)
        #t
        (let ((t (get-var-type (car ps))))
          (if (and t (type-fixnum? t))
              (loop (cdr ps))
              #f)))))

;;; Fast O(1) detection of pure tail-recursive loops (maximum depth 30)
(define (pure-tail-loop? fn-name lbody)
  (let loop-chk ((e lbody) (depth 0))
    (cond
      ((> depth 30) #f)
      ((not (pair? e)) #f)
      ((eq? (car e) fn-name) #t)
      ((eq? (car e) 'let)
       (loop-chk (caddr e) (+ depth 1)))
      ((eq? (car e) 'if)
       (let ((test (cadr e))
             (then (caddr e))
             (else-opt (if (null? (cdddr e)) '() (cadddr e))))
         (and (not (and (pair? test) (eq? (car test) fn-name)))
              (or (loop-chk then (+ depth 1))
                  (if (null? else-opt) #f (loop-chk else-opt (+ depth 1)))))))
      (else #f))))

;;; Traverses loop body to box any raw loop-variable returned at loop exit boundaries
(define (box-raw-exit expr raw-vars fn-name)
  (cond
    ((not (pair? expr))
     (if (and (symbol? expr) (memq expr raw-vars))
         (list '%box-fixnum expr)
         expr))
    ((eq? (car expr) fn-name)
     ;; Tail-recursive loop jump: keep unboxed raw integers
     expr)
    ((eq? (car expr) '%box-fixnum)
     expr)
    ((memq (car expr) '(%raw-add %raw-sub %raw-mul))
     (list '%box-fixnum expr))
    ((eq? (car expr) 'if)
     (let ((test (cadr expr))
           (then (caddr expr))
           (else-part (if (null? (cdddr expr)) '() (cadddr expr))))
       (list 'if test
             (box-raw-exit then raw-vars fn-name)
             (if (null? else-part) '() (box-raw-exit else-part raw-vars fn-name)))))
    ((eq? (car expr) 'let)
     (let ((bindings (cadr expr))
           (body (caddr expr)))
       (list 'let bindings (box-raw-exit body raw-vars fn-name))))
    ((eq? (car expr) 'begin)
     (let ((stmts (cdr expr)))
       (let loop ((rest stmts) (acc '()))
         (if (null? (cdr rest))
             (cons 'begin (append (reverse acc) (list (box-raw-exit (car rest) raw-vars fn-name))))
             (loop (cdr rest) (cons (car rest) acc))))))
    (else
     expr)))

;;; Lowers binary arithmetic operators to raw integer primitives when operands are raw
(define (rtyper-binop op e1 e2 raw-env)
  (cond
    ((memq op '(+ - *))
     (let ((raw1? (or (integer? e1) (and (symbol? e1) (raw-var? e1 raw-env))))
           (raw2? (or (integer? e2) (and (symbol? e2) (raw-var? e2 raw-env)))))
       (if (and raw1? raw2?)
           (case op
             ((+) (list '%raw-add e1 e2))
             ((-) (list '%raw-sub e1 e2))
             ((*) (list '%raw-mul e1 e2)))
           (list op e1 e2))))
    ((memq op '(= < <= > >=))
     (let ((raw1? (and (symbol? e1) (raw-var? e1 raw-env)))
           (raw2? (and (symbol? e2) (raw-var? e2 raw-env))))
       (cond
         ((and raw1? (integer? e2))
          (list op e1 (list '%unbox-fixnum e2)))
         ((and (integer? e1) raw2?)
          (list op (list '%unbox-fixnum e1) e2))
         (else
          (list op e1 e2)))))
    (else
     (list op e1 e2))))

;;; Recursively rewrites ANF AST to Typed LIR representation
(define (rtyper-expr-scoped expr raw-env unboxed-fns)
    (cond
      ((not (pair? expr)) expr)
    (else
     (let ((op (car expr)))
       (cond
         ((eq? op 'quote) expr)
         ((eq? op 'if)
          (let* ((test (cadr expr))
                 (then (caddr expr))
                 (else-expr (if (null? (cdddr expr)) '() (cadddr expr)))
                 (fvar (fixnum-test-var test)))
            (if (and fvar (not (raw-var? fvar raw-env)) (expr-has-arithmetic-on-var? then fvar))
                ;; Flow-sensitive narrowing: fvar is proven to be Fixnum in then-branch!
                ;; Unbox fvar at the then-branch boundary and lower internal arithmetic to raw ops.
                (let* ((then-raw-env (cons fvar raw-env))
                       (lowered-then (rtyper-expr-scoped then then-raw-env unboxed-fns))
                       (boxed-then (if (and (pair? lowered-then)
                                            (memq (car lowered-then) '(%raw-add %raw-sub %raw-mul)))
                                       (list '%box-fixnum lowered-then)
                                       (box-raw-exit lowered-then (list fvar) '%no-fn)))
                       (unboxed-then (list 'let (list (list fvar (list '%unbox-fixnum fvar))) boxed-then))
                       (r-test (rtyper-expr-scoped test raw-env unboxed-fns))
                       (r-else (if (null? else-expr) '() (rtyper-expr-scoped else-expr raw-env unboxed-fns))))
                  (if (null? r-else)
                      (list 'if r-test unboxed-then)
                      (list 'if r-test unboxed-then r-else)))
                ;; Standard if
                (let ((r-test (rtyper-expr-scoped test raw-env unboxed-fns))
                      (r-then (rtyper-expr-scoped then raw-env unboxed-fns))
                      (r-else (if (null? else-expr) '() (rtyper-expr-scoped else-expr raw-env unboxed-fns))))
                  (if (null? r-else)
                      (list 'if r-test r-then)
                      (list 'if r-test r-then r-else))))))
         ((eq? op 'begin)
          (cons 'begin (map (lambda (e) (rtyper-expr-scoped e raw-env unboxed-fns)) (cdr expr))))
         ((memq op '(let letrec))
          (let* ((bindings (cadr expr))
                 (body (caddr expr)))
            (cond
              ;; Path Splitting (合流点メッセージ分割 / Chambers & Ungar 1989):
              ;; When single binding is (v (if cond e1 e2)) and body has conditional/pred on v:
              ((and (eq? op 'let)
                    (= (length bindings) 1)
                    (pair? (cadar bindings))
                    (eq? (car (cadar bindings)) 'if)
                    (<= (expr-size body) 40)
                    (let ((var (caar bindings)))
                      (expr-has-conditional-or-pred-on-var? body var)))
               (let* ((b (car bindings))
                      (var (car b))
                      (if-expr (cadr b))
                      (cond-part (cadr if-expr))
                      (e1 (caddr if-expr))
                      (e2 (if (null? (cdddr if-expr)) #f (cadddr if-expr)))
                      ;; Specialize body along both paths
                      (spec-then (specialize-var-in-body body var e1))
                      (spec-else (specialize-var-in-body body var e2))
                      (split-then (rtyper-expr-scoped (list 'let (list (list var e1)) spec-then) raw-env unboxed-fns))
                      (split-else (rtyper-expr-scoped (list 'let (list (list var e2)) spec-else) raw-env unboxed-fns)))
                 (list 'if (rtyper-expr-scoped cond-part raw-env unboxed-fns) split-then split-else)))
              ((and (= (length bindings) 1)
                    (let* ((b (car bindings))
                           (val (cadr b)))
                      (and (pair? val)
                           (eq? (car val) 'lambda)
                           (pair? (cadr val))
                           (all-fixnum-params? (cadr val))
                           (pure-tail-loop? (car b) (caddr val)))))
               ;; Named-let loop with 100% fixnum parameters and pure tail-recursion:
               ;; Lower all loop variables to raw %raw-i64 hardware representation.
               ;; Lexically scope fn-name to its definition body and continuation.
               (let* ((b (car bindings))
                      (fn-name (car b))
                      (fn-val (cadr b))
                      (params (cadr fn-val))
                      (lbody (caddr fn-val))
                      (loop-raw-env (append params raw-env))
                      (inner-unboxed-fns (cons fn-name unboxed-fns)))
                 (record-unboxed-fn! fn-name)
                 (let* ((typed-lbody (rtyper-expr-scoped lbody loop-raw-env inner-unboxed-fns))
                        (boxed-lbody (box-raw-exit typed-lbody params fn-name))
                        (new-fn-val (list 'lambda params boxed-lbody))
                        (new-body (rtyper-expr-scoped body raw-env inner-unboxed-fns)))
                   (list op (list (list fn-name new-fn-val)) new-body))))
              (else
               ;; Standard let bindings: propagate raw variables and record facts
               (let* ((new-bindings
                       (map (lambda (b)
                              (let ((v (car b)) (rhs (cadr b)))
                                (if (and (pair? rhs) (memq (car rhs) '(fixnum? integer? number?))
                                         (pair? (cdr rhs)) (symbol? (cadr rhs)))
                                    (record-rtyper-fact! v (cadr rhs)))
                                (list v (rtyper-expr-scoped rhs raw-env unboxed-fns))))
                            bindings))
                      ;; Extend raw-env with newly bound variables that hold raw values
                      (extended-raw-env
                       (let loop ((bs new-bindings) (acc raw-env))
                         (if (null? bs) acc
                             (let* ((b (car bs))
                                    (var (car b))
                                    (val (cadr b)))
                               (if (and (pair? val)
                                        (memq (car val) '(%raw-add %raw-sub %raw-mul %unbox-fixnum)))
                                   (loop (cdr bs) (cons var acc))
                                   (loop (cdr bs) acc))))))
                      (new-body (rtyper-expr-scoped body extended-raw-env unboxed-fns)))
                 (list op new-bindings new-body))))))
         ((eq? op '-)
          (if (null? (cddr expr))
              (list '- (rtyper-expr-scoped (cadr expr) raw-env unboxed-fns))
              (rtyper-binop op (rtyper-expr-scoped (cadr expr) raw-env unboxed-fns) (rtyper-expr-scoped (caddr expr) raw-env unboxed-fns) raw-env)))
         ((binop-prim? op)
          (rtyper-binop op (rtyper-expr-scoped (cadr expr) raw-env unboxed-fns) (rtyper-expr-scoped (caddr expr) raw-env unboxed-fns) raw-env))
         ((memq op unboxed-fns)
          ;; Boundary call into an unboxed loop: unbox non-raw arguments at entry
          (let ((args (cdr expr)))
            (cons op
                  (map (lambda (arg)
                         (if (and (symbol? arg) (raw-var? arg raw-env))
                             arg
                             (list '%unbox-fixnum (rtyper-expr-scoped arg raw-env unboxed-fns))))
                       args))))
         (else
          ;; General procedure call or syntax
          (cons op (map (lambda (e) (rtyper-expr-scoped e raw-env unboxed-fns)) (cdr expr)))))))))


(define (rtyper-expr expr raw-env)
  (rtyper-expr-scoped expr raw-env '()))

;;; Pass 5b Entrypoint: Transforms S-Annotated AST into Lowered Typed AST
(define (rtyper-all form-or-forms)
  (reset-rtyper!)
  (cond
    ((null? form-or-forms) '())
    ((not (pair? form-or-forms)) form-or-forms)
    ((eq? (car form-or-forms) '%program)
     (let ((defs (cadr form-or-forms))
           (main (caddr form-or-forms)))
       (list '%program
             (map (lambda (d)
                    (if (and (pair? d) (eq? (car d) 'define))
                        (list 'define (cadr d) (rtyper-expr-scoped (caddr d) '() '()))
                        (rtyper-expr-scoped d '() '())))
                  defs)
             (rtyper-expr-scoped main '() '()))))
    ((eq? (car form-or-forms) 'define)
     (let ((head (cadr form-or-forms))
           (body (cddr form-or-forms)))
       (cons 'define
             (cons head
                   (map (lambda (e) (rtyper-expr-scoped e '() '())) body)))))
    (else
     (rtyper-expr-scoped form-or-forms '() '()))))
;;; =======================================================================
;;; ULisp Compiler Pass 4c: Contification & Local Closure Elimination Nanopass
;;; Conforms to DSN-33 Architecture Specification & Issue #522
;;; Note: Identifies local functions whose call sites are dominated by a
;;;       common continuation context and transforms them into local control
;;;       flow (%cont-fun / %cont-call), eliminating flat closure allocation
;;;       and indirect calls completely.
;;; =======================================================================

;;; -----------------------------------------------------------------------
;;; Nanopass DSL Pass: contify-subst
;;; Substitutes call sites of `var` into `(%cont-call var . args)` within `expr`.
;;; -----------------------------------------------------------------------
(define-pass contify-subst : L_core (ir var) -> L_core ()
  (Expr : Expr (ir var) -> Expr ()
    ((quote ,datum)
     ir)
    ((lambda (,params ...) ,body)
     ir) ; Do not cross lambda boundaries into separate procedure CFGs
    ((let ((,x* ,e*) ...) ,body)
     (let ((opt-bindings (let loop ((xs x*) (es e*) (acc '()))
                           (if (or (null? xs) (null? es))
                               (reverse acc)
                               (loop (cdr xs) (cdr es) (cons (list (car xs) (Expr (car es) var)) acc))))))
       (if (memq var x*)
           (list 'let opt-bindings body) ; shadowed
           (list 'let opt-bindings (Expr body var)))))
    ((letrec ((,x* ,e*) ...) ,body)
     (if (memq var x*)
         ir ; shadowed
         (let ((opt-bindings (let loop ((xs x*) (es e*) (acc '()))
                               (if (or (null? xs) (null? es))
                                   (reverse acc)
                                   (loop (cdr xs) (cdr es) (cons (list (car xs) (Expr (car es) var)) acc))))))
           (list 'letrec opt-bindings (Expr body var)))))
    ((%cont-fun ,f-name (,params ...) ,f-body ,in-body)
     (if (eq? f-name var)
         ir ; shadowed
         (list '%cont-fun f-name params
               (Expr f-body var)
               (Expr in-body var))))
    ((%cont-call ,target ,es ...)
     (cons '%cont-call (cons target (map (lambda (e) (Expr e var)) es))))
    ((,op ,args ...)
     (if (eq? op var)
         (cons '%cont-call (cons var (map (lambda (e) (Expr e var)) args)))
         (cons (Expr op var) (map (lambda (e) (Expr e var)) args))))))

(define (contify-calls var expr)
  (contify-subst expr var))

;;; Recursively transforms an expression, converting eligible letrec bindings into %cont-fun.
(define (contify-expr expr)
  (cond
    ((not (pair? expr)) expr)
    (else
     (let ((op (car expr)))
       (case op
         ((quote) expr)
         ((if)
          (list 'if
                (contify-expr (cadr expr))
                (contify-expr (caddr expr))
                (if (null? (cdddr expr)) #f (contify-expr (cadddr expr)))))
         ((begin)
          (cons 'begin (map contify-expr (cdr expr))))
         ((let)
          (let ((bindings (cadr expr))
                (body (caddr expr)))
            (list 'let
                  (map (lambda (b) (list (car b) (contify-expr (cadr b)))) bindings)
                  (contify-expr body))))
         ((letrec)
          (let* ((bindings (cadr expr))
                 (body (caddr expr)))
            (contify-letrec bindings body)))
         ((lambda)
          (let ((params (cadr expr))
                (body (caddr expr)))
            (list 'lambda params (contify-expr body))))
         ((%cont-fun)
          (list '%cont-fun
                (cadr expr)
                (caddr expr)
                (contify-expr (cadddr expr))
                (contify-expr (cadr (cdddr expr)))))
         ((%cont-call)
          (cons '%cont-call
                (cons (cadr expr)
                      (map contify-expr (cddr expr)))))
         (else
          (map contify-expr expr)))))))

(define (occurs-in? var expr)
  (cond
    ((symbol? expr) (eq? expr var))
    ((not (pair? expr)) #f)
    (else
     (or (occurs-in? var (car expr))
         (occurs-in? var (cdr expr))))))

(define (occurs-in-other-bindings? var bindings)
  (let loop ((bs bindings))
    (if (null? bs)
        #f
        (let ((b (car bs)))
          (if (eq? (car b) var)
              (loop (cdr bs))
              (if (occurs-in? var (cadr b))
                  #t
                  (loop (cdr bs))))))))

(define (has-call? var expr)
  (cond
    ((not (pair? expr)) #f)
    (else
     (if (eq? (car expr) var)
         #t
         (let loop ((es expr))
           (and (pair? es)
                (or (has-call? var (car es))
                    (loop (cdr es)))))))))

;;; Processes a letrec form, lifting contifiable local bindings into %cont-fun wrappers.
(define (contify-letrec bindings orig-body)
  (if (= (length bindings) 1)
      (let* ((b (car bindings))
             (var (car b))
             (val (cadr b)))
        (if (and (has-call? var orig-body)
                 (contifiable-binding? var val orig-body))
            (let* ((params (cadr val))
                   (lbody (caddr val))
                   (opt-lbody (contify-calls var lbody))
                   (opt-body (contify-calls var orig-body)))
              (list '%cont-fun var params
                    (contify-expr opt-lbody)
                    (contify-expr opt-body)))
            (list 'letrec
                  (list (list var (contify-expr val)))
                  (contify-expr orig-body))))
      ;; Multi-binding letrec (top-level procedures or mutual recursion):
      ;; Preserve letrec structure to maintain inter-procedure references,
      ;; while recursively contifying local loops inside each procedure body.
      (list 'letrec
            (map (lambda (b) (list (car b) (contify-expr (cadr b)))) bindings)
            (contify-expr orig-body))))

;;; Pass 4c Entrypoint: Contification & local closure elimination across all expressions.
(define (contify-all form)
  (cond
    ((not (pair? form)) form)
    ((eq? (car form) '%program)
     (let ((defs (cadr form))
           (main (caddr form)))
       (list '%program
             (map (lambda (d)
                    (if (and (pair? d) (eq? (car d) 'define))
                        (list 'define (cadr d) (contify-expr (caddr d)))
                        (contify-expr d)))
                  defs)
             (contify-expr main))))
    (else
     (contify-expr form))))
;;; =======================================================================
;;; ULisp Compiler Pass 3: Explicit Closure Conversion Nanopass
;;; Conforms to DSN-33 Architecture Specification
;;; Note: Lifts nested lambdas to flat %function definitions, transforms
;;;       closure instantiation to %make-closure, free variable accesses
;;;       to %closure-ref, and mutual recursion (letrec) to %closure-set!.
;;; =======================================================================

;;; Boxed global accumulator for lambda-lifted procedure definitions
(define *lifted-functions* (cons '() '()))

(define (reset-lifted-functions!)
  (set-car! *lifted-functions* '()))

(define (add-lifted-function! fn)
  (set-car! *lifted-functions* (cons fn (car *lifted-functions*))))

;;; Top-level functions & variables registry for %direct-call optimization
(define *top-level-fns* (cons '() '()))   ; ((name . label) ...)
(define *top-level-vars* (cons '() '()))  ; (name ...)

(define (reset-top-level-env!)
  (set-car! *top-level-fns* '())
  (set-car! *top-level-vars* '()))

(define (free-vars-with-globals expr bound)
  (let ((top-bound (append (map car* (car *top-level-fns*)) (car *top-level-vars*))))
    (free-vars expr (set-union bound top-bound))))

;;; Variable environment lookup (linear alist, latest bindings shadow older ones)
(define (lookup-var var var-map)
  (let ((entry (assq var var-map)))
    (cond
      (entry (cdr entry))
      ((assq var (car *top-level-fns*))
       ;; Top-level function referenced as first-class value: instantiate static closure
       (list '%make-closure-env (cdr (assq var (car *top-level-fns*)))))
      ((memq var (car *top-level-vars*))
       ;; Top-level global variable reference
       (list '%global-ref var))
      ((lir-primitive? var)
       var)
      ((allow-extern-symbols?)
       ;; External reference fallback: treat as external global variable
       (list '%global-ref var))
      (else var))))

;;; Forward declarations / helpers for mutual recursion in closure conversion
(define (convert-expr expr var-map)
  (cond
    ((symbol? expr)
     (lookup-var expr var-map))
    ((not (pair? expr))
     expr)
    (else
     (let ((op (car expr)))
       (case op
         ((quote)
          expr)
         ((if)
          (let ((test (convert-expr (cadr expr) var-map))
                (then (convert-expr (caddr expr) var-map))
                (else-expr (if (null? (cdddr expr))
                               #f
                               (convert-expr (cadddr expr) var-map))))
            (list 'if test then else-expr)))
         ((begin)
          (cons 'begin (map (lambda (e) (convert-expr e var-map)) (cdr expr))))
         ((let)
          (let* ((bindings (cadr expr))
                 (body (caddr expr))
                 (new-bindings
                  (map (lambda (b)
                         (list (car b) (convert-expr (cadr b) var-map)))
                       bindings))
                 ;; Shadow let-bound variables in body by pushing identity mappings
                 (body-var-map
                  (let loop ((bs bindings) (acc var-map))
                    (if (null? bs) acc
                        (let ((v (caar bs)))
                          (loop (cdr bs) (cons (cons v v) acc))))))
                 (new-body (convert-expr body body-var-map)))
            (list 'let new-bindings new-body)))
         ((letrec)
          (convert-letrec (cadr expr) (caddr expr) var-map))
         ((%cont-fun)
          (let* ((f-name (cadr expr))
                 (params (caddr expr))
                 (f-body (cadddr expr))
                 (in-body (cadr (cdddr expr)))
                 (lbody-map
                  (let loop ((ps params) (acc var-map))
                    (if (null? ps) acc
                        (loop (cdr ps) (cons (cons (car ps) (car ps)) acc)))))
                 (new-f-body (convert-expr f-body lbody-map))
                 (new-in-body (convert-expr in-body var-map)))
            (list '%cont-fun f-name params new-f-body new-in-body)))
         ((%cont-call)
          (cons '%cont-call
                (cons (cadr expr)
                      (map (lambda (e) (convert-expr e var-map)) (cddr expr)))))
         ((%with-handler)
          (list '%with-handler
                (convert-expr (cadr expr) var-map)
                (convert-expr (caddr expr) var-map)))
         ((%raw-call/cc)
          (list '%raw-call/cc
                (convert-expr (cadr expr) var-map)))
         ((%call-with-values)
          (list '%call-with-values
                (convert-expr (cadr expr) var-map)
                (convert-expr (caddr expr) var-map)))
         ((%values)
          (cons '%values
                (map (lambda (e) (convert-expr e var-map)) (cdr expr))))
         ((%make-closure %make-closure-env)
          (cons op (cons (cadr expr) (map (lambda (e) (convert-expr e var-map)) (cddr expr)))))
         ((lambda)
          (convert-lambda #f (cadr expr) (caddr expr) var-map))
         (else
          (if (and (symbol? op)
                   (not (assq op var-map))
                   (not (lir-primitive? op)))
              (cond
                ((assq op (car *top-level-fns*))
                 (let ((label (cdr (assq op (car *top-level-fns*))))
                       (args (map (lambda (e) (convert-expr e var-map)) (cdr expr))))
                   (cons '%direct-call (cons label args))))
                ((allow-extern-symbols?)
                 (let ((label (mangle-fn-label op))
                       (args (map (lambda (e) (convert-expr e var-map)) (cdr expr))))
                   (cons '%direct-call (cons label args))))
                (else
                 (cons (convert-expr op var-map)
                       (map (lambda (e) (convert-expr e var-map)) (cdr expr)))))
              (cons (convert-expr op var-map)
                    (map (lambda (e) (convert-expr e var-map)) (cdr expr))))))))))

;;; Convert a lambda expression, lift it as a top-level %function, and return %make-closure
(define (convert-lambda self-name params body var-map)
  (let* ((bound-vars (if self-name (cons self-name params) params))
         (frees (free-vars-with-globals body bound-vars))
         (label (unique-label-sym "L_lambda"))
         ;; Build callee inner var-map:
         ;; 1. Params shadow outer bindings (map to themselves)
         (env-p (let loop ((ps params) (acc '()))
                  (if (null? ps) acc
                      (loop (cdr ps) (cons (cons (car ps) (car ps)) acc)))))
         ;; 2. Self name (if recursive) maps to %self
         (env-s (if self-name
                    (cons (cons self-name '%self) env-p)
                    env-p))
         ;; 3. Free variables map to (%closure-ref %self idx)
         (inner-var-map
          (let loop ((fs frees) (idx 1) (acc env-s))
            (if (null? fs)
                acc
                (let ((fv (car fs)))
                  (loop (cdr fs) (+ idx 1)
                        (cons (cons fv (list '%closure-ref '%self idx)) acc))))))
         (new-body (convert-expr body inner-var-map))
         (fn-def (list '%function label params new-body)))
    (add-lifted-function! fn-def)
    ;; Instantiation expression: (%make-closure-env 'label captured-args...)
    (let ((captured-args
           (map (lambda (fv) (convert-expr fv var-map)) frees)))
      (cons '%make-closure-env (cons label captured-args)))))

;;; Convert letrec expression into let + %make-closure + backpatching %closure-set!
(define (convert-letrec bindings body var-map)
  (let* ((rec-vars (map car* bindings))
         ;; Shadow rec-vars in outer-var-map by binding them to themselves
         (outer-var-map
          (let loop ((rvs rec-vars) (acc var-map))
            (if (null? rvs) acc
                (loop (cdr rvs) (cons (cons (car rvs) (car rvs)) acc)))))
         (processed-bindings
          (map (lambda (b)
                 (let ((var (car b))
                       (val (cadr b)))
                   (if (and (pair? val) (eq? (car val) 'lambda))
                       (let* ((params (cadr val))
                              (lbody (caddr val))
                              (bound (cons var params))
                              (frees (free-vars-with-globals lbody bound))
                              (label (unique-label-sym "L_lambda"))
                              ;; Callee inner environment:
                              ;; Params map to themselves
                              (env-p (let loop ((ps params) (acc '()))
                                       (if (null? ps) acc
                                           (loop (cdr ps) (cons (cons (car ps) (car ps)) acc)))))
                              ;; Self-name maps to %self
                              (env-s (cons (cons var '%self) env-p))
                              ;; Free variables map to (%closure-ref %self idx)
                              (inner-var-map
                               (let loop ((fs frees) (idx 1) (acc env-s))
                                 (if (null? fs) acc
                                     (let ((fv (car fs)))
                                       (loop (cdr fs) (+ idx 1)
                                             (cons (cons fv (list '%closure-ref '%self idx)) acc))))))
                              (new-lbody (convert-expr lbody inner-var-map))
                              (fn-def (list '%function label params new-lbody)))
                         (add-lifted-function! fn-def)
                         (let ((init-args
                                (map (lambda (fv)
                                       (if (memq fv rec-vars)
                                           #f
                                           (convert-expr fv outer-var-map)))
                                     frees)))
                           (list var
                                 (cons '%make-closure-env (cons label init-args))
                                 frees)))
                       (list var (convert-expr val outer-var-map) '()))))
               bindings))
         (let-bindings
          (map (lambda (pb) (list (car pb) (cadr pb))) processed-bindings))
         (backpatches
          (let loop-b ((pbs processed-bindings) (acc '()))
            (if (null? pbs)
                (reverse acc)
                (let* ((pb (car pbs))
                       (var (car pb))
                       (frees (caddr pb))
                       (patches
                        (let loop-f ((fs frees) (idx 1) (p-acc '()))
                          (if (null? fs)
                              (reverse p-acc)
                              (let ((fv (car fs)))
                                (if (memq fv rec-vars)
                                    (loop-f (cdr fs) (+ idx 1)
                                            (cons (list '%closure-set! var idx fv) p-acc))
                                    (loop-f (cdr fs) (+ idx 1) p-acc)))))))
                  (loop-b (cdr pbs) (append (reverse patches) acc))))))
         (new-body (convert-expr body outer-var-map)))
    (if (null? backpatches)
        (list 'let let-bindings new-body)
        (list 'let let-bindings
              (cons 'begin (append backpatches (list new-body)))))))

;;; Pass 5 Entrypoint: Takes Canonical Core AST or (%program defs main-expr), returns (%program functions main-expr)
(define (closure-convert ast)
  (reset-lifted-functions!)
  (reset-top-level-env!)
  (let ((res
         (if (and (pair? ast) (eq? (car ast) '%program))
             (let* ((defs (cadr ast))
                    (main-expr (caddr ast)))
               ;; 1. Scan defs and populate *top-level-fns* and *top-level-vars*
               (let loop ((ds defs))
                 (if (pair? ds)
                     (begin
                       (let ((d (car ds)))
                         (if (and (pair? d) (eq? (car d) 'define))
                             (let ((name (cadr d))
                                   (val (caddr d)))
                               (if (and (pair? val) (eq? (car val) 'lambda))
                                   (if (not (assq name (car *top-level-fns*)))
                                       (let ((label (mangle-fn-label name)))
                                         (set-car! *top-level-fns* (cons (cons name label) (car *top-level-fns*)))))
                                   (if (not (memq name (car *top-level-vars*)))
                                       (set-car! *top-level-vars* (cons name (car *top-level-vars*))))))))
                       (loop (cdr ds)))))
               ;; 2. Convert each top-level function and add to lifted-functions
               (let loop ((ds defs))
                 (if (pair? ds)
                     (begin
                       (let ((d (car ds)))
                         (if (and (pair? d) (eq? (car d) 'define))
                             (let ((name (cadr d))
                                   (val (caddr d)))
                               (if (and (pair? val) (eq? (car val) 'lambda))
                                   (let* ((label (cdr (assq name (car *top-level-fns*))))
                                          (params (cadr val))
                                          (lbody (caddr val))
                                          (inner-map (map (lambda (p) (cons p p)) params))
                                          (new-body (convert-expr lbody inner-map))
                                          (fn-def (list '%function label params new-body)))
                                     (add-lifted-function! fn-def))))))
                       (loop (cdr ds)))))
               ;; 3. Convert variable inits and main-expr
               (let* ((inits (let loop ((ds defs) (acc '()))
                               (if (null? ds)
                                   (reverse acc)
                                   (let ((d (car ds)))
                                     (if (and (pair? d) (eq? (car d) 'define) (not (assq (cadr d) (car *top-level-fns*))))
                                         (loop (cdr ds) (cons (list '%global-set! (cadr d) (convert-expr (caddr d) '())) acc))
                                         (loop (cdr ds) acc))))))
                      (conv-main (convert-expr main-expr '()))
                      (final-main (if (null? inits) conv-main (cons 'begin (append inits (list conv-main))))))
                 (list '%program (reverse (car *lifted-functions*)) final-main)))
             (let ((main-expr (convert-expr ast '())))
               (list '%program (reverse (car *lifted-functions*)) main-expr)))))
    (if (and (verifier-enabled?) (assq 'L_lifted (nanopass-get-languages)))
        (if (not (nanopass-ast-valid? 'L_lifted res))
            (verifier-error 'closure "Pass 110 output violates L_lifted schema invariants" res)))
    res))
;;; =======================================================================
;;; ULisp Compiler Pass 6b: TBAA & Escape Analysis Nanopass
;;; Conforms to DSN-33 Section 8.5 & Issue #525
;;; Based on Cornell CS 6120 (Lesson 10 Alias Analysis) & Bacon's Unified Theory
;;;
;;; Features:
;;; 1. Type-Based Alias Analysis (TBAA): Proves non-interference between
;;;    disjoint Scheme type heaps (Pair, Closure, Vector, Raw memory).
;;;    Enables Redundant Load Elimination (RLE) across stores of disjoint types.
;;; 2. Flow-Sensitive Escape Analysis: Identifies local non-escaping `cons`
;;;    and `%make-closure` instances and promotes them to stack-allocated objects
;;;    (`%stack-cons`, `%make-stack-closure`), completely bypassing heap bump allocation.
;;; =======================================================================

;;; -----------------------------------------------------------------------
;;; Part 1: Type-Based Alias Analysis (TBAA) & Redundant Load Elimination
;;; -----------------------------------------------------------------------

;;; Returns the TBAA type class of a memory expression
;;; Returns 'pair, 'closure, 'vector, 'raw, or 'unknown
(define (tbaa-type-class expr)
  (if (not (pair? expr))
      'unknown
      (case (car expr)
        ((annotate) (tbaa-type-class (caddr expr)))
        ((car cdr set-car! set-cdr!) 'pair)
        ((%closure-ref %closure-set!) 'closure)
        ((vector-ref vector-set!) 'vector)
        ((bytevector-u8-ref bytevector-u8-set!) 'bytevector)
        ((%raw-load %raw-store!) 'raw)
        (else 'unknown))))

;;; Predicate: Are two memory operations provably disjoint by type?
(define (tbaa-disjoint? t1 t2)
  (cond
    ((or (eq? t1 'unknown) (eq? t2 'unknown)) #f)
    ((eq? t1 t2) #f)
    (else #t)))

;;; Invalidate cached loads affected by a store expression
;;; If store is of type 'T, all cached loads of type 'T (or unknown) are invalidated,
;;; but cached loads of disjoint types are PRESERVED!
(define (tbaa-invalidate-loads store-expr avail-loads)
  (let ((st-type (tbaa-type-class store-expr)))
    (if (eq? st-type 'unknown)
        ;; Unknown store (e.g. arbitrary function call): conservative purge
        '()
        ;; Disjoint type store: retain all loads whose type class is disjoint
        (let loop ((loads avail-loads) (acc '()))
          (if (null? loads)
              (reverse acc)
              (let* ((entry (car loads))
                     (load-type (cadr entry)))
                (if (tbaa-disjoint? st-type load-type)
                    (loop (cdr loads) (cons entry acc))
                    (loop (cdr loads) acc))))))))

;;; Search for an available load matching (op target index/offset)
;;; Entry format: (load-expr type-class var-name)
(define (tbaa-find-load op-expr avail-loads)
  (let loop ((loads avail-loads))
    (if (null? loads)
        #f
        (let ((entry (car loads)))
          (if (equal? (car entry) op-expr)
              (caddr entry)
              (loop (cdr loads)))))))

;;; -----------------------------------------------------------------------
;;; Part 2: Flow-Sensitive Escape Analysis (Monotone Framework)
;;; -----------------------------------------------------------------------

(define *stack-alloc-attr* (string->symbol ":stack-alloc"))

;;; Lattice for escape analysis: Powerset of escaped variable symbols
(define *escape-lattice* (make-powerset-lattice 'escape-analysis #f))
(define (escape-lattice) *escape-lattice*)

;;; Collect all variables that escape a given expression context
;;; An object escapes if:
;;; - It is returned from the function (in tail position)
;;; - It is passed as an argument to an external call (non-primitive / escaping op)
;;; - It is stored into another escaping data structure or global
;;; Employs the Monotone Framework Lattice Join to ensure set deduplication and monotonicity.
(define (collect-escaped-vars expr is-tail)
  (let ((lat (escape-lattice)))
    (cond
      ((symbol? expr)
       (if is-tail (list expr) (lattice-bottom lat)))
      ((not (pair? expr))
       (lattice-bottom lat))
      (else
       (let ((op (car expr)))
         (case op
           ((quote) (lattice-bottom lat))
           ((annotate)
            (collect-escaped-vars (caddr expr) is-tail))
           ((if)
            (let ((test-esc (collect-escaped-vars (cadr expr) #f))
                  (then-esc (collect-escaped-vars (caddr expr) is-tail))
                  (else-esc (if (null? (cdddr expr))
                                (lattice-bottom lat)
                                (collect-escaped-vars (cadddr expr) is-tail))))
              (lattice-join lat test-esc (lattice-join lat then-esc else-esc))))
           ((begin)
            (let loop ((es (cdr expr)) (acc (lattice-bottom lat)))
              (if (null? es)
                  acc
                  (let ((tail? (and is-tail (null? (cdr es)))))
                    (loop (cdr es)
                          (lattice-join lat acc (collect-escaped-vars (car es) tail?)))))))
         ((let)
          (let* ((bindings (cadr expr))
                 (body (caddr expr))
                 (b-escs
                  (let loop ((bs bindings) (acc (lattice-bottom lat)))
                    (if (null? bs) acc
                        (loop (cdr bs)
                              (lattice-join lat acc (collect-escaped-vars (cadar bs) #f))))))
                 (body-escs (collect-escaped-vars body is-tail)))
            (lattice-join lat b-escs body-escs)))
         ;; Safe local destructors: car, cdr, %closure-ref, null?, pair? do NOT cause target to escape
         ((car cdr null? pair? not zero? fixnum? integer? string? boolean?)
          (collect-escaped-vars (cadr expr) #f))
         ((%closure-ref %global-ref)
          (lattice-bottom lat))
         ((%direct-call)
          (let loop ((args (cddr expr)) (acc (lattice-bottom lat)))
            (if (null? args) acc
                (let ((arg (car args)))
                  (loop (cdr args)
                        (if (symbol? arg)
                            (lattice-join lat (list arg) acc)
                            (lattice-join lat (collect-escaped-vars arg #f) acc)))))))
         ((%global-set!)
          (let ((stored-val (caddr expr)))
            (if (symbol? stored-val)
                (list stored-val)
                (collect-escaped-vars stored-val #f))))
         ;; Mutations: if storing a value into a heap object, the stored value escapes!
         ((set-car! set-cdr!)
          (let ((stored-val (caddr expr)))
            (if (symbol? stored-val)
                (lattice-join lat (list stored-val) (collect-escaped-vars (cadr expr) #f))
                (collect-escaped-vars stored-val #f))))
         ((vector-set!)
          (let ((stored-val (cadddr expr)))
            (if (symbol? stored-val)
                (lattice-join lat (list stored-val)
                              (lattice-join lat (collect-escaped-vars (cadr expr) #f)
                                            (collect-escaped-vars (caddr expr) #f)))
                (lattice-join lat (collect-escaped-vars (cadr expr) #f)
                              (lattice-join lat (collect-escaped-vars (caddr expr) #f)
                                            (collect-escaped-vars stored-val #f))))))
         ;; Standard function call or primitive: all arguments escape unless known safe
         (else
          (let ((args-esc
                 (let loop ((args (cdr expr)) (acc (lattice-bottom lat)))
                   (if (null? args) acc
                       (let ((arg (car args)))
                         (loop (cdr args)
                               (if (symbol? arg)
                                   (lattice-join lat (list arg) acc)
                                   (lattice-join lat (collect-escaped-vars arg #f) acc))))))))
            (if (symbol? op)
                args-esc
                (lattice-join lat (collect-escaped-vars op #f) args-esc))))))))))

;;; -----------------------------------------------------------------------
;;; Part 3: AST Transformation (Stack Promotion & Redundant Load Elimination)
;;; -----------------------------------------------------------------------

(define (alias-escape-transform-expr expr escaped-set avail-loads)
  (cond
    ((not (pair? expr)) expr)
    (else
     (let ((op (car expr)))
       (case op
         ((quote) expr)
         ((annotate)
          (list 'annotate (cadr expr)
                (alias-escape-transform-expr (caddr expr) escaped-set avail-loads)))

         ;; TBAA Load: (car p), (cdr p), (%closure-ref c i)
         ((car cdr %closure-ref)
          (let ((cached-var (tbaa-find-load expr avail-loads)))
            (if cached-var
                cached-var
                (cons op (map (lambda (e) (alias-escape-transform-expr e escaped-set avail-loads))
                              (cdr expr))))))

         ;; TBAA Store: invalidates only non-disjoint types
         ((set-car! set-cdr! %closure-set! vector-set! bytevector-u8-set! %raw-store!)
          (cons op (map (lambda (e) (alias-escape-transform-expr e escaped-set avail-loads))
                        (cdr expr))))

         ((%direct-call)
          (cons '%direct-call
                (cons (cadr expr)
                      (map (lambda (e) (alias-escape-transform-expr e escaped-set avail-loads))
                           (cddr expr)))))

         ((%global-ref)
          expr)

         ((%global-set!)
          (list '%global-set! (cadr expr)
                (alias-escape-transform-expr (caddr expr) escaped-set avail-loads)))

         ((if)
          (let* ((test (alias-escape-transform-expr (cadr expr) escaped-set avail-loads))
                 (then (alias-escape-transform-expr (caddr expr) escaped-set avail-loads))
                 (else-part (if (null? (cdddr expr))
                                #f
                                (alias-escape-transform-expr (cadddr expr) escaped-set avail-loads))))
            (list 'if test then else-part)))

         ((begin)
          (let loop ((es (cdr expr)) (cur-loads avail-loads) (acc '()))
            (if (null? es)
                (cons 'begin (reverse acc))
                (let* ((e (car es))
                       (transformed (alias-escape-transform-expr e escaped-set cur-loads))
                       (next-loads
                        (if (and (pair? e) (memq (car e) '(set-car! set-cdr! %closure-set! vector-set! bytevector-u8-set! %raw-store!)))
                            (tbaa-invalidate-loads e cur-loads)
                            cur-loads)))
                  (loop (cdr es) next-loads (cons transformed acc))))))

         ((let)
          (let* ((bindings (cadr expr))
                 (body (caddr expr))
                 ;; Process bindings and detect Stack Allocations
                 (trans-bindings
                  (map
                   (lambda (b)
                     (let* ((var (car b))
                            (val (cadr b))
                            (escapes? (memq var escaped-set)))
                       (cond
                         ;; Non-escaping pair: promote to %stack-cons
                         ((and (not escapes?) (pair? val) (eq? (car val) 'cons))
                          (list var (cons '%stack-cons
                                          (map (lambda (e) (alias-escape-transform-expr e escaped-set avail-loads))
                                               (cdr val)))))
                         ;; Non-escaping %make-closure-env: promote to (annotate #:stack-alloc (%make-closure-env ...))
                         ((and (not escapes?) (pair? val) (eq? (car val) '%make-closure-env))
                          (list var (list 'annotate *stack-alloc-attr*
                                          (cons '%make-closure-env
                                                (map (lambda (e) (alias-escape-transform-expr e escaped-set avail-loads))
                                                     (cdr val))))))
                         ;; Non-escaping closure: promote to %make-stack-closure
                         ((and (not escapes?) (pair? val) (eq? (car val) '%make-closure))
                          (list var (cons '%make-stack-closure
                                          (map (lambda (e) (alias-escape-transform-expr e escaped-set avail-loads))
                                               (cdr val)))))
                         (else
                          (list var (alias-escape-transform-expr val escaped-set avail-loads))))))
                   bindings))
                 ;; Record available loads from bindings
                 (new-avail-loads
                  (let loop ((bs trans-bindings) (cur-loads avail-loads))
                    (if (null? bs) cur-loads
                        (let* ((b (car bs))
                               (v (car b))
                               (raw-rhs (cadr b))
                               (rhs (if (and (pair? raw-rhs) (eq? (car raw-rhs) 'annotate))
                                        (caddr raw-rhs)
                                        raw-rhs)))
                          (if (and (pair? rhs) (memq (car rhs) '(car cdr %closure-ref)))
                              (let ((tc (tbaa-type-class rhs)))
                                (loop (cdr bs) (cons (list rhs tc v) cur-loads)))
                              (loop (cdr bs) cur-loads))))))
                 (new-body (alias-escape-transform-expr body escaped-set new-avail-loads)))
            (list 'let trans-bindings new-body)))

         ((%cont-fun)
          (let* ((f-name (cadr expr))
                 (params (caddr expr))
                 (f-body (cadddr expr))
                 (in-body (cadr (cdddr expr)))
                 (f-esc (collect-escaped-vars f-body #t))
                 (new-f-body (alias-escape-transform-expr f-body f-esc avail-loads))
                 (new-in-body (alias-escape-transform-expr in-body escaped-set avail-loads)))
            (list '%cont-fun f-name params new-f-body new-in-body)))

         (else
          (cons (alias-escape-transform-expr op escaped-set avail-loads)
                (map (lambda (e) (alias-escape-transform-expr e escaped-set avail-loads))
                     (cdr expr)))))))))

;;; Optimize a single procedure or top-level expression
(define (alias-escape-optimize-function fn-def)
  (let* ((label (cadr fn-def))
         (params (caddr fn-def))
         (body (cadddr fn-def))
         (escaped-set (collect-escaped-vars body #t))
         (optimized-body (alias-escape-transform-expr body escaped-set '())))
    (list '%function label params optimized-body)))

;;; Pass 6b Main Entrypoint
;;; Input: (%program functions main-expr)
;;; Output: (%program optimized-functions optimized-main-expr)
(define (alias-escape-all program)
  (if (and (pair? program) (eq? (car program) '%program))
      (let* ((functions (cadr program))
             (main-expr (caddr program))
             (opt-functions (map alias-escape-optimize-function functions))
             (main-esc (collect-escaped-vars main-expr #t))
             (opt-main (alias-escape-transform-expr main-expr main-esc '())))
        (list '%program opt-functions opt-main))
      ;; Fallback if single expression
      (let ((esc (collect-escaped-vars program #t)))
        (alias-escape-transform-expr program esc '()))))
;;; =======================================================================
;;; ULisp Compiler: Canonical LIR Language Specification (L_lir_canonical)
;;; Conforms to DSN-33 Architecture Specification & Issue #593
;;; =======================================================================
;;; Formal intermediate language definition for Canonical LIR using Nanopass
;;; DSL (define-language). Serves as the declarative contract between the
;;; mid-level optimization/flattening passes and low-level code generation backends.
;;; =======================================================================

(define-language L_lir_canonical
  (entry Program)
  (terminals
    (symbol (x lbl var cond_op sp_lbl))
    (integer (n offset shift frame_size bytes tag si cnt bitmap))
    (string (str fn_name)))
  (Register (reg)
    %rax %rbx %rcx %rdx %rsi %rdi %rbp %rsp
    %r8  %r9  %r10 %r11 %r12 %r13 %r14 %r15 %al
    (%reg x))
  (StackSlot (stk)
    (%stack offset))
  (MemRef (mem)
    (%mem reg offset)
    (%mem reg reg))
  (LValue (lval)
    reg
    stk
    mem)
  (Operand (opnd)
    lval
    n
    lbl)
  (Inst (inst)
    ;; Control Flow
    (%label lbl)
    (%block lbl (x ...) inst ...)
    (%jump lbl)
    (%jump lbl (opnd ...))
    (%jump-if-false reg lbl)
    (%jump-if-false reg lbl (opnd ...))
    (%jump-if reg lbl1 (opnd1 ...) lbl2 (opnd2 ...))
    (%jump-cond cond_op lbl)
    (%jump-cond str lbl)
    (%jump-if-zero lbl)
    (%direct-jump lbl)
    (%return)
    (%return opnd)

    ;; Calls & ABI
    (%c-call fn_name shift)
    (%call-closure shift)
    (%call-closure shift sp_lbl)
    (%direct-call lbl shift)
    (%direct-call lbl shift sp_lbl)
    (%dispatch-consumer si1 si2 shift)

    ;; Memory & Data Transfer
    (%mov lval opnd)
    (%load reg1 reg2 offset)
    (%store reg1 offset opnd)
    (%load-byte-zx reg1 reg2 offset)
    (%store-byte reg1 offset opnd)
    (%push reg)
    (%pop reg)
    (%code-ref reg lbl)
    (%str-ref reg lbl)
    (%global-ref reg var)
    (%global-set! var reg)

    ;; Arithmetic / Logic / Primitives
    (%add opnd1 opnd2)
    (%raw-add opnd1 opnd2)
    (%sub opnd1 opnd2)
    (%raw-sub opnd1 opnd2)
    (%imul opnd1 opnd2)
    (%raw-mul opnd1 opnd2)
    (%neg opnd)
    (%inc opnd)
    (%cqo)
    (%idiv opnd)
    (%shl opnd shift)
    (%shr opnd shift)
    (%sar opnd shift)
    (%bit-and opnd1 opnd2)
    (%bit-or opnd1 opnd2)
    (%bit-xor opnd1 opnd2)
    (%cmp opnd1 opnd2)
    (%raw-cmp opnd1 opnd2)
    (%set-boolean opnd cond_op)
    (%box-fixnum opnd1 opnd2)
    (%unbox-fixnum opnd1 opnd2)
    (%syscall)

    ;; Runtime / GC / CC / Values
    (%alloc opnd bytes tag)
    (%alloc opnd bytes tag si)
    (%alloc-stack opnd offset tag)
    (%capture-cc lbl si)
    (%push-handler lbl si1 si2)
    (%pop-handler si)
    (%raise)
    (%set-values-count cnt)
    (%store-values-buf si cnt))
  (StringEntry (se)
    (lbl str))
  (SafepointEntry (sm)
    (lbl frame_size bitmap))
  (FunctionDecl (f)
    (%lir-function lbl (params (x ...)) (frame-size frame_size) (body inst ...)))
  (MainDecl (m)
    (%lir-main (frame-size frame_size) (body inst ...)))
  (Program (p)
    (%lir-program (strings (se ...)) (stackmaps (sm ...)) (%lir-functions f ...) m)))
;;; =======================================================================
;;; ULisp Compiler: Canonical LIR Specification Verifier & Boundary Validator
;;; Conforms to DSN-33 Architecture Specification & Issue #589
;;; =======================================================================

(define *canonical-lir-registers*
  '(%rax %rbx %rcx %rdx %rsi %rdi %rbp %rsp
    %r8  %r9  %r10 %r11 %r12 %r13 %r14 %r15 %al))

(define (lir-symbol-starts-with-percent? sym)
  (and (symbol? sym)
       (let ((str (symbol->string sym)))
         (and (> (string-length str) 1)
              (char=? (string-ref str 0) #\%)))))

(define (lir-valid-register? reg)
  (cond
    ((memq reg *canonical-lir-registers*) #t)
    ((and (pair? reg) (eq? (car reg) '%reg) (pair? (cdr reg))
          (memq (cadr reg) *canonical-lir-registers*)) #t)
    (else #f)))

(define (lir-valid-lvalue? opnd)
  (cond
    ((lir-valid-register? opnd) #t)
    ((and (pair? opnd) (eq? (car opnd) '%stack) (pair? (cdr opnd))
          (integer? (cadr opnd))) #t)
    ((and (pair? opnd) (eq? (car opnd) '%mem) (pair? (cdr opnd)) (pair? (cddr opnd)))
     (and (lir-valid-register? (cadr opnd))
          (or (integer? (caddr opnd)) (lir-valid-register? (caddr opnd)))))
    ((and (symbol? opnd) (not (lir-symbol-starts-with-percent? opnd))) #t)
    (else #f)))

(define (lir-valid-operand? opnd)
  (cond
    ((lir-valid-register? opnd) #t)
    ((integer? opnd) #t)
    ((and (symbol? opnd) (not (lir-symbol-starts-with-percent? opnd))) #t)
    ((and (pair? opnd) (eq? (car opnd) '%stack) (pair? (cdr opnd))
          (integer? (cadr opnd))) #t)
    ((and (pair? opnd) (eq? (car opnd) '%mem) (pair? (cdr opnd)) (pair? (cddr opnd)))
     (and (lir-valid-register? (cadr opnd))
          (or (integer? (caddr opnd)) (lir-valid-register? (caddr opnd)))))
    (else #f)))

(define (lir-atomic-operand? opnd)
  (or (integer? opnd)
      (and (symbol? opnd) (not (lir-symbol-starts-with-percent? opnd)))
      (lir-valid-register? opnd)
      (and (pair? opnd) (eq? (car opnd) '%stack) (pair? (cdr opnd)) (integer? (cadr opnd)))))

(define (lir-report-error msg expr)
  (verifier-error 'canonical-lir msg expr))

;;; -----------------------------------------------------------------------
;;; Instruction-Level Validation
;;; -----------------------------------------------------------------------
(define (lir-valid-inst? inst)
  (if (not (pair? inst))
      (lir-report-error "Instruction must be a non-empty pair" inst)
      (let ((op (car inst)))
        (case op
          ;; Control Flow
          ((%label)
           (if (and (= (length inst) 2) (symbol? (cadr inst)))
               #t
               (lir-report-error "%label must have exactly 1 symbol operand" inst)))

          ((%block)
           (if (and (>= (length inst) 3)
                    (symbol? (cadr inst))
                    (list? (caddr inst)))
               (let p-loop ((ps (caddr inst)))
                 (if (null? ps)
                     (let b-loop ((body (cdddr inst)))
                       (if (null? body)
                           #t
                           (and (lir-valid-inst? (car body))
                                (b-loop (cdr body)))))
                     (if (symbol? (car ps))
                         (p-loop (cdr ps))
                         (lir-report-error "%block parameter must be a symbol" (car ps)))))
               (lir-report-error "%block must be (%block <label-sym> (<param-syms>...) <insts>...)" inst)))

          ((%jump)
           (cond
             ((= (length inst) 2)
              (if (symbol? (cadr inst)) #t
                  (lir-report-error "%jump target must be a label symbol" inst)))
             ((= (length inst) 3)
              (if (and (symbol? (cadr inst)) (list? (caddr inst)))
                  (let a-loop ((as (caddr inst)))
                    (if (null? as) #t
                        (if (lir-atomic-operand? (car as))
                            (a-loop (cdr as))
                            (lir-report-error "%jump argument must be an atomic operand" (car as)))))
                  (lir-report-error "%jump format must be (%jump <lbl> (<args>...))" inst)))
             (else
              (lir-report-error "Invalid %jump arity" inst))))

          ((%jump-if-false)
           (cond
             ((= (length inst) 3)
              (if (and (lir-valid-register? (cadr inst)) (symbol? (caddr inst))) #t
                  (lir-report-error "%jump-if-false must have register and label symbol" inst)))
             ((= (length inst) 4)
              (if (and (lir-valid-register? (cadr inst))
                       (symbol? (caddr inst))
                       (list? (cadddr inst)))
                  (let a-loop ((as (cadddr inst)))
                    (if (null? as) #t
                        (if (lir-atomic-operand? (car as))
                            (a-loop (cdr as))
                            (lir-report-error "%jump-if-false argument must be atomic" (car as)))))
                  (lir-report-error "%jump-if-false format must be (%jump-if-false <reg> <lbl> (<args>...))" inst)))
             (else
              (lir-report-error "Invalid %jump-if-false arity" inst))))

          ((%jump-if)
           ;; Format: (%jump-if <reg> <then-lbl> (<then-args>...) <else-lbl> (<else-args>...))
           (if (and (= (length inst) 6)
                    (lir-valid-register? (cadr inst))
                    (symbol? (caddr inst))
                    (list? (cadddr inst))
                    (symbol? (car (cddddr inst)))
                    (list? (cadr (cddddr inst))))
               (and (let a-loop ((as (cadddr inst)))
                      (if (null? as) #t
                          (if (lir-atomic-operand? (car as))
                              (a-loop (cdr as))
                              (lir-report-error "%jump-if then-argument must be atomic" (car as)))))
                    (let b-loop ((as (cadr (cddddr inst))))
                      (if (null? as) #t
                          (if (lir-atomic-operand? (car as))
                              (b-loop (cdr as))
                              (lir-report-error "%jump-if else-argument must be atomic" (car as))))))
               (lir-report-error "%jump-if format must be (%jump-if <reg> <t_lbl> (<ta>...) <e_lbl> (<ea>...))" inst)))

          ((%jump-cond)
           (if (and (= (length inst) 3)
                    (or (symbol? (cadr inst)) (string? (cadr inst)))
                    (symbol? (caddr inst)))
               #t
               (lir-report-error "%jump-cond format must be (%jump-cond <cond-op> <lbl>)" inst)))

          ((%jump-if-zero)
           (if (and (= (length inst) 2) (symbol? (cadr inst)))
               #t
               (lir-report-error "%jump-if-zero format must be (%jump-if-zero <lbl>)" inst)))

          ((%direct-jump)
           (if (and (= (length inst) 2) (symbol? (cadr inst)))
               #t
               (lir-report-error "%direct-jump format must be (%direct-jump <lbl>)" inst)))

          ((%return)
           (if (or (= (length inst) 1)
                   (and (= (length inst) 2) (lir-valid-operand? (cadr inst))))
               #t
               (lir-report-error "Invalid %return instruction format" inst)))

          ;; Calls & ABI
          ((%c-call)
           (if (and (= (length inst) 3)
                    (or (symbol? (cadr inst)) (string? (cadr inst)))
                    (integer? (caddr inst)))
               #t
               (lir-report-error "%c-call format must be (%c-call <fn-name> <shift>)" inst)))

          ((%call-closure)
           (if (or (and (= (length inst) 2) (integer? (cadr inst)))
                   (and (= (length inst) 3) (integer? (cadr inst)) (or (symbol? (caddr inst)) (not (caddr inst)))))
               #t
               (lir-report-error "%call-closure format must be (%call-closure <shift> [<safepoint>])" inst)))

          ((%direct-call)
           (if (or (and (= (length inst) 3) (symbol? (cadr inst)) (integer? (caddr inst)))
                   (and (= (length inst) 4) (symbol? (cadr inst)) (integer? (caddr inst))
                        (or (symbol? (cadddr inst)) (not (cadddr inst)))))
               #t
               (lir-report-error "%direct-call format must be (%direct-call <lbl> <shift> [<safepoint>])" inst)))

          ((%dispatch-consumer)
           (if (and (= (length inst) 4)
                    (integer? (cadr inst))
                    (integer? (caddr inst))
                    (integer? (cadddr inst)))
               #t
               (lir-report-error "%dispatch-consumer format must be (%dispatch-consumer <c-si> <a-si> <shift>)" inst)))

          ;; Memory & Data Transfer
          ((%mov)
           (if (and (= (length inst) 3)
                    (lir-valid-lvalue? (cadr inst))
                    (lir-valid-operand? (caddr inst)))
               #t
               (lir-report-error "%mov format must be (%mov <dst> <src>)" inst)))

          ((%load)
           (if (and (= (length inst) 4)
                    (lir-valid-register? (cadr inst))
                    (lir-valid-register? (caddr inst))
                    (or (integer? (cadddr inst)) (lir-valid-register? (cadddr inst))))
               #t
               (lir-report-error "%load format must be (%load <dst-reg> <base-reg> <offset>)" inst)))

          ((%store)
           (if (and (= (length inst) 4)
                    (lir-valid-register? (cadr inst))
                    (or (integer? (caddr inst)) (lir-valid-register? (caddr inst)))
                    (lir-valid-operand? (cadddr inst)))
               #t
               (lir-report-error "%store format must be (%store <base-reg> <offset> <src>)" inst)))

          ((%load-byte-zx)
           (if (and (= (length inst) 4)
                    (lir-valid-register? (cadr inst))
                    (lir-valid-register? (caddr inst))
                    (integer? (cadddr inst)))
               #t
               (lir-report-error "%load-byte-zx format must be (%load-byte-zx <dst> <base> <offset>)" inst)))

          ((%store-byte)
           (if (and (= (length inst) 4)
                    (lir-valid-register? (cadr inst))
                    (integer? (caddr inst))
                    (or (lir-valid-register? (cadddr inst)) (integer? (cadddr inst))))
               #t
               (lir-report-error "%store-byte format must be (%store-byte <base> <offset> <src>)" inst)))

          ((%push)
           (if (and (= (length inst) 2) (lir-valid-register? (cadr inst)))
               #t
               (lir-report-error "%push format must be (%push <reg>)" inst)))

          ((%pop)
           (if (and (= (length inst) 2) (lir-valid-register? (cadr inst)))
               #t
               (lir-report-error "%pop format must be (%pop <reg>)" inst)))

          ((%code-ref)
           (if (and (= (length inst) 3)
                    (lir-valid-register? (cadr inst))
                    (symbol? (caddr inst)))
               #t
               (lir-report-error "%code-ref format must be (%code-ref <dst> <lbl>)" inst)))

          ((%str-ref)
           (if (and (= (length inst) 3)
                    (lir-valid-register? (cadr inst))
                    (symbol? (caddr inst)))
               #t
               (lir-report-error "%str-ref format must be (%str-ref <dst> <lbl>)" inst)))

          ((%global-ref)
           (if (and (= (length inst) 3)
                    (lir-valid-register? (cadr inst))
                    (symbol? (caddr inst)))
               #t
               (lir-report-error "%global-ref format must be (%global-ref <reg> <var-sym>)" inst)))

          ((%global-set!)
           (if (and (= (length inst) 3)
                    (symbol? (cadr inst))
                    (lir-valid-register? (caddr inst)))
               #t
               (lir-report-error "%global-set! format must be (%global-set! <var-sym> <reg>)" inst)))

          ;; Arithmetic / Logic / Primitives
          ((%add %raw-add %sub %raw-sub %imul %raw-mul %bit-and %bit-or %bit-xor %cmp %raw-cmp)
           (if (and (= (length inst) 3)
                    (lir-valid-operand? (cadr inst))
                    (lir-valid-operand? (caddr inst)))
               #t
               (lir-report-error (string-append (symbol->string op) " must have exactly 2 valid operands") inst)))

          ((%neg %inc)
           (if (and (= (length inst) 2) (lir-valid-operand? (cadr inst)))
               #t
               (lir-report-error (string-append (symbol->string op) " must have 1 operand") inst)))

          ((%shl %shr %sar)
           (if (and (= (length inst) 3)
                    (lir-valid-operand? (cadr inst))
                    (integer? (caddr inst)))
               #t
               (lir-report-error (string-append (symbol->string op) " shift count must be an integer") inst)))

          ((%cqo %syscall %raise)
           (if (= (length inst) 1)
               #t
               (lir-report-error (string-append (symbol->string op) " takes zero operands") inst)))

          ((%idiv)
           (if (and (= (length inst) 2) (lir-valid-operand? (cadr inst)))
               #t
               (lir-report-error "%idiv takes 1 operand" inst)))

          ((%set-boolean)
           (if (and (= (length inst) 3)
                    (lir-valid-operand? (cadr inst))
                    (or (symbol? (caddr inst)) (string? (caddr inst))))
               #t
               (lir-report-error "%set-boolean format must be (%set-boolean <dst> <cc>)" inst)))

          ((%box-fixnum %unbox-fixnum)
           (if (and (= (length inst) 3)
                    (lir-valid-operand? (cadr inst))
                    (lir-valid-operand? (caddr inst)))
               #t
               (lir-report-error (string-append (symbol->string op) " format must be (op <dst> <src>)") inst)))

          ;; Runtime / GC / CC / Values
          ((%alloc)
           (if (and (or (= (length inst) 4) (= (length inst) 5))
                    (lir-valid-operand? (cadr inst))
                    (integer? (caddr inst))
                    (integer? (cadddr inst)))
               #t
               (lir-report-error "%alloc format must be (%alloc <dst> <bytes> <tag> [<si>])" inst)))

          ((%alloc-stack)
           (if (and (= (length inst) 4)
                    (lir-valid-operand? (cadr inst))
                    (integer? (caddr inst))
                    (integer? (cadddr inst)))
               #t
               (lir-report-error "%alloc-stack format must be (%alloc-stack <dst> <offset> <tag>)" inst)))

          ((%capture-cc)
           (if (and (= (length inst) 3)
                    (symbol? (cadr inst))
                    (integer? (caddr inst)))
               #t
               (lir-report-error "%capture-cc format must be (%capture-cc <ret-lbl> <k-si>)" inst)))

          ((%push-handler)
           (if (and (= (length inst) 4)
                    (symbol? (cadr inst))
                    (integer? (caddr inst))
                    (integer? (cadddr inst)))
               #t
               (lir-report-error "%push-handler format must be (%push-handler <catch-lbl> <f-si> <h-si>)" inst)))

          ((%pop-handler)
           (if (and (= (length inst) 2) (integer? (cadr inst)))
               #t
               (lir-report-error "%pop-handler format must be (%pop-handler <f-si>)" inst)))

          ((%set-values-count)
           (if (and (= (length inst) 2) (integer? (cadr inst)))
               #t
               (lir-report-error "%set-values-count takes 1 integer operand" inst)))

          ((%store-values-buf)
           (if (and (= (length inst) 3) (integer? (cadr inst)) (integer? (caddr inst)))
               #t
               (lir-report-error "%store-values-buf takes base-si and count integers" inst)))

          (else
           (lir-report-error (string-append "Unknown Canonical LIR opcode: "
                                            (if (symbol? op) (symbol->string op) "?"))
                             inst))))))

;;; -----------------------------------------------------------------------
;;; Lightweight Symbol Hash Set & Hash Table for O(1) Fast CFG Verification
;;; -----------------------------------------------------------------------
;;; NOTE (self-hosting constraints): this file is compiled by the ulisp
;;; compiler itself during bootstrap, so it must avoid variadic parameter
;;; lists, internal defines, `max`, and the 2-argument form of `make-vector`.
(define (lir-max2 a b) (if (> a b) a b))

(define (lir-symbol-hash-str str)
  (let ((len (string-length str)))
    (let loop ((i 0) (h 5381))
      (if (= i len)
          (modulo h 16777213)
          (let ((c (char->integer (string-ref str i))))
            (loop (+ i 1)
                  (modulo (+ (* h 33) c) 16777213)))))))

(define (lir-make-bucket-vector size)
  (let* ((n (lir-max2 16 size))
         (v (make-vector n)))
    (let loop ((i 0))
      (if (= i n)
          v
          (begin
            (vector-set! v i '())
            (loop (+ i 1)))))))

(define (make-symbol-hash-set size)
  (lir-make-bucket-vector size))

(define (symbol-hash-bucket-index sym size)
  (let ((str (if (symbol? sym) (symbol->string sym) "")))
    (modulo (lir-symbol-hash-str str) size)))

(define (symbol-hash-set-add! set sym)
  (let* ((idx (symbol-hash-bucket-index sym (vector-length set)))
         (bucket (vector-ref set idx)))
    (if (memq sym bucket)
        #f
        (begin
          (vector-set! set idx (cons sym bucket))
          #t))))

(define (symbol-hash-set-contains? set sym)
  (let* ((idx (symbol-hash-bucket-index sym (vector-length set)))
         (bucket (vector-ref set idx)))
    (if (memq sym bucket) #t #f)))

(define (make-symbol-hash-table size)
  (lir-make-bucket-vector size))

(define (symbol-hash-table-put! tbl sym val)
  (let* ((idx (symbol-hash-bucket-index sym (vector-length tbl)))
         (bucket (vector-ref tbl idx))
         (entry (assq sym bucket)))
    (if entry
        (set-cdr! entry val)
        (vector-set! tbl idx (cons (cons sym val) bucket)))))

(define (symbol-hash-table-ref tbl sym default)
  (let* ((idx (symbol-hash-bucket-index sym (vector-length tbl)))
         (bucket (vector-ref tbl idx))
         (entry (assq sym bucket)))
    (if entry (cdr entry) default)))

;;; -----------------------------------------------------------------------
;;; Single-Pass Instruction Verification and CFG Target Resolution (O(N))
;;; -----------------------------------------------------------------------
;;; state = (label-set block-arity-tbl pending-jumps-cell fn-name)

(define (lir-sp-push-jump! pending entry)
  (set-car! pending (cons entry (car pending))))

(define (lir-sp-queue-jump! inst pending)
  (case (car inst)
    ((%jump)
     (let ((args (if (pair? (cddr inst)) (caddr inst) '())))
       (lir-sp-push-jump! pending (list '%jump (cadr inst) (length args) inst))))
    ((%jump-if-false)
     (let ((args (if (pair? (cdddr inst)) (cadddr inst) '())))
       (lir-sp-push-jump! pending (list '%jump-if-false (caddr inst)
                                        (if (pair? args) (length args) #f) inst))))
    ((%jump-if)
     (let ((then-args (cadddr inst))
           (else-args (cadr (cddddr inst))))
       (lir-sp-push-jump! pending (list '%jump-if (caddr inst)
                                        (if (pair? then-args) (length then-args) #f)
                                        inst
                                        (car (cddddr inst))
                                        (if (pair? else-args) (length else-args) #f)))))
    ((%jump-cond)
     (lir-sp-push-jump! pending (list '%jump-cond (caddr inst) #f inst)))
    ((%jump-if-zero)
     (lir-sp-push-jump! pending (list '%jump-if-zero (cadr inst) #f inst)))
    ((%direct-jump)
     (lir-sp-push-jump! pending (list '%direct-jump (cadr inst) #f inst)))
    (else #t)))

(define (lir-sp-check-block-params params)
  (if (null? params)
      #t
      (if (symbol? (car params))
          (lir-sp-check-block-params (cdr params))
          (lir-report-error "%block parameter must be a symbol" (car params)))))

;; Step 1: single traversal validating syntax, collecting labels & arities,
;; and queuing jump targets for post-pass resolution.
(define (lir-sp-scan insts label-set arity-tbl pending fn-name)
  (if (null? insts)
      #t
      (let ((inst (car insts)))
        (cond
          ((not (pair? inst))
           (lir-report-error "Instruction must be a non-empty pair" inst))
          ((eq? (car inst) '%label)
           (cond
             ((not (and (= (length inst) 2) (symbol? (cadr inst))))
              (lir-report-error "%label must have exactly 1 symbol operand" inst))
             ((not (symbol-hash-set-add! label-set (cadr inst)))
              (lir-report-error "Duplicate label definition within function" (cadr inst)))
             (else
              (lir-sp-scan (cdr insts) label-set arity-tbl pending fn-name))))
          ((eq? (car inst) '%block)
           (cond
             ((not (and (>= (length inst) 3) (symbol? (cadr inst)) (list? (caddr inst))))
              (lir-report-error "%block must be (%block <label-sym> (<param-syms>...) <insts>...)" inst))
             ((not (symbol-hash-set-add! label-set (cadr inst)))
              (lir-report-error "Duplicate block label definition within function" (cadr inst)))
             ((not (lir-sp-check-block-params (caddr inst))) #f)
             (else
              (let ((lbl (cadr inst)))
                (symbol-hash-table-put! arity-tbl lbl (length (caddr inst)))
                (and (with-verifier-context
                      (list (cons 'phase 'canonical-lir) (cons 'function fn-name) (cons 'block lbl))
                      (lambda () (lir-sp-scan (cdddr inst) label-set arity-tbl pending fn-name)))
                     (lir-sp-scan (cdr insts) label-set arity-tbl pending fn-name))))))
          ((not (lir-valid-inst? inst)) #f)
          (else
           (lir-sp-queue-jump! inst pending)
           (lir-sp-scan (cdr insts) label-set arity-tbl pending fn-name))))))

(define (lir-sp-target-known? target label-set known-fn-set)
  (or (symbol-hash-set-contains? label-set target)
      (symbol-hash-set-contains? known-fn-set target)))

(define (lir-sp-arity-mismatch? target argc arity-tbl)
  (and argc
       (let ((expected (symbol-hash-table-ref arity-tbl target #f)))
         (and expected (not (= argc expected))))))

;; Step 2: post-pass target resolution in O(1) per jump.
(define (lir-sp-resolve jumps label-set known-fn-set arity-tbl)
  (if (null? jumps)
      #t
      (let* ((j (car jumps))
             (kind (car j))
             (target (cadr j))
             (argc (caddr j))
             (inst (cadddr j)))
        (cond
          ((not (lir-sp-target-known? target label-set known-fn-set))
           (cond
             ((eq? kind '%jump)
              (lir-report-error "Undefined jump target label" target))
             ((eq? kind '%jump-if-false)
              (lir-report-error "Undefined jump target in %jump-if-false" target))
             ((eq? kind '%jump-if)
              (lir-report-error "Undefined then-target in %jump-if" target))
             (else
              (lir-report-error "Undefined jump condition target" target))))
          ((lir-sp-arity-mismatch? target argc arity-tbl)
           (cond
             ((eq? kind '%jump-if-false)
              (lir-report-error "%jump-if-false argument count mismatch with %block" inst))
             ((eq? kind '%jump-if)
              (lir-report-error "%jump-if then-argument count mismatch with %block" inst))
             (else
              (lir-report-error "Jump argument count does not match %block parameter count" inst))))
          ((eq? kind '%jump-if)
           (let ((else-target (car (cddddr j)))
                 (else-argc (cadr (cddddr j))))
             (cond
               ((not (lir-sp-target-known? else-target label-set known-fn-set))
                (lir-report-error "Undefined else-target in %jump-if" else-target))
               ((lir-sp-arity-mismatch? else-target else-argc arity-tbl)
                (lir-report-error "%jump-if else-argument count mismatch with %block" inst))
               (else
                (lir-sp-resolve (cdr jumps) label-set known-fn-set arity-tbl)))))
          (else
           (lir-sp-resolve (cdr jumps) label-set known-fn-set arity-tbl))))))

(define (lir-verify-insts-single-pass insts known-fn-set fn-name)
  (let ((label-set (make-symbol-hash-set 128))
        (arity-tbl (make-symbol-hash-table 128))
        (pending (cons '() '())))
    (and (lir-sp-scan insts label-set arity-tbl pending fn-name)
         (lir-sp-resolve (reverse (car pending)) label-set known-fn-set arity-tbl))))

;;; Backward-compatibility wrappers for tests and legacy callers
(define (lir-collect-labels-and-params insts)
  (let loop ((is insts) (labels '()) (block-params '()))
    (if (null? is)
        (cons labels block-params)
        (let ((inst (car is)))
          (cond
            ((and (pair? inst) (eq? (car inst) '%label))
             (let ((lbl (cadr inst)))
               (if (memq lbl labels)
                   (begin
                     (lir-report-error "Duplicate label definition within function" lbl)
                     #f)
                   (loop (cdr is) (cons lbl labels) block-params))))
            ((and (pair? inst) (eq? (car inst) '%block))
             (let ((lbl (cadr inst))
                   (params (caddr inst))
                   (sub-insts (cdddr inst)))
               (if (memq lbl labels)
                   (begin
                     (lir-report-error "Duplicate block label definition within function" lbl)
                     #f)
                   (let ((sub-res (lir-collect-labels-and-params sub-insts)))
                     (if (not sub-res)
                         #f
                         (loop (cdr is)
                               (cons lbl (append (car sub-res) labels))
                               (cons (cons lbl (length params))
                                     (append (cdr sub-res) block-params))))))))
            (else
             (loop (cdr is) labels block-params)))))))

(define (lir-verify-cfg-targets insts defined-labels block-params known-fn-labels)
  (let ((label-set (make-symbol-hash-set (lir-max2 16 (* 2 (length defined-labels)))))
        (known-set (make-symbol-hash-set (lir-max2 16 (* 2 (length known-fn-labels)))))
        (arity-tbl (make-symbol-hash-table (lir-max2 16 (* 2 (length block-params))))))
    (for-each (lambda (l) (symbol-hash-set-add! label-set l)) defined-labels)
    (for-each (lambda (k) (symbol-hash-set-add! known-set k)) known-fn-labels)
    (for-each (lambda (bp) (symbol-hash-table-put! arity-tbl (car bp) (cdr bp))) block-params)
    (let loop ((is insts))
      (if (null? is) #t
          (let ((inst (car is)))
            (cond
              ((not (pair? inst)) (loop (cdr is)))
              ((eq? (car inst) '%block)
               (and (loop (cdddr inst))
                    (loop (cdr is))))
              ((eq? (car inst) '%jump)
               (let* ((target (cadr inst))
                      (args (if (pair? (cddr inst)) (caddr inst) '()))
                      (expected-arity (symbol-hash-table-ref arity-tbl target #f)))
                 (cond
                   ((and (not (symbol-hash-set-contains? label-set target))
                         (not (symbol-hash-set-contains? known-set target)))
                    (lir-report-error "Undefined jump target label" target))
                   ((and expected-arity (not (= (length args) expected-arity)))
                    (lir-report-error "Jump argument count does not match %block parameter count" inst))
                   (else
                    (loop (cdr is))))))
              ((eq? (car inst) '%jump-if-false)
               (let* ((target (caddr inst))
                      (args (if (pair? (cdddr inst)) (cadddr inst) '()))
                      (expected-arity (symbol-hash-table-ref arity-tbl target #f)))
                 (cond
                   ((and (not (symbol-hash-set-contains? label-set target))
                         (not (symbol-hash-set-contains? known-set target)))
                    (lir-report-error "Undefined jump target in %jump-if-false" target))
                   ((and expected-arity (pair? args) (not (= (length args) expected-arity)))
                    (lir-report-error "%jump-if-false argument count mismatch with %block" inst))
                   (else
                    (loop (cdr is))))))
              ((eq? (car inst) '%jump-if)
               (let* ((then-target (caddr inst))
                      (then-args (cadddr inst))
                      (else-target (car (cddddr inst)))
                      (else-args (cadr (cddddr inst)))
                      (then-expected (symbol-hash-table-ref arity-tbl then-target #f))
                      (else-expected (symbol-hash-table-ref arity-tbl else-target #f)))
                 (cond
                   ((and (not (symbol-hash-set-contains? label-set then-target))
                         (not (symbol-hash-set-contains? known-set then-target)))
                    (lir-report-error "Undefined then-target in %jump-if" then-target))
                   ((and (not (symbol-hash-set-contains? label-set else-target))
                         (not (symbol-hash-set-contains? known-set else-target)))
                    (lir-report-error "Undefined else-target in %jump-if" else-target))
                   ((and then-expected (pair? then-args) (not (= (length then-args) then-expected)))
                    (lir-report-error "%jump-if then-argument count mismatch with %block" inst))
                   ((and else-expected (pair? else-args) (not (= (length else-args) else-expected)))
                    (lir-report-error "%jump-if else-argument count mismatch with %block" inst))
                   (else
                    (loop (cdr is))))))
              ((or (eq? (car inst) '%jump-cond)
                   (eq? (car inst) '%jump-if-zero))
               (let ((target (if (eq? (car inst) '%jump-cond) (caddr inst) (cadr inst))))
                 (if (and (not (symbol-hash-set-contains? label-set target))
                          (not (symbol-hash-set-contains? known-set target)))
                     (lir-report-error "Undefined jump condition target" target)
                     (loop (cdr is)))))
              (else
               (loop (cdr is)))))))))

(define (lir-verify-insts-and-cfg insts known-fn-labels)
  (let ((known-set (make-symbol-hash-set (lir-max2 16 (* 2 (length known-fn-labels))))))
    (for-each (lambda (k) (symbol-hash-set-add! known-set k)) known-fn-labels)
    (lir-verify-insts-single-pass insts known-set '%unnamed-fn)))

;;; -----------------------------------------------------------------------
;;; Function-Level and Program-Level Validation
;;; -----------------------------------------------------------------------
(define (lir-valid-function? fn known-fn-set)
  (cond
    ((not (and (pair? fn) (eq? (car fn) '%lir-function)))
     (lir-report-error "Function node must start with %lir-function" fn))
    ((not (symbol? (cadr fn)))
     (lir-report-error "%lir-function name must be a symbol" fn))
    (else
     (let ((fn-name (cadr fn))
           (params-clause (assq 'params (cddr fn)))
           (frame-clause (assq 'frame-size (cddr fn)))
           (body-clause (assq 'body (cddr fn))))
       (with-verifier-context (list (cons 'phase 'canonical-lir) (cons 'function fn-name))
         (lambda ()
           (cond
             ((not (and params-clause (list? (cadr params-clause))))
              (lir-report-error "%lir-function must have valid (params (...)) clause" fn))
             ((not (and frame-clause (integer? (cadr frame-clause))
                        (>= (cadr frame-clause) 0)
                        (= (modulo (cadr frame-clause) 8) 0)))
              (lir-report-error "%lir-function frame-size must be a non-negative multiple of 8" fn))
             ((not (and body-clause (list? (cdr body-clause))))
              (lir-report-error "%lir-function must have valid (body <insts>...) clause" fn))
             (else
              (lir-verify-insts-single-pass (cdr body-clause) known-fn-set fn-name)))))))))

(define (lir-valid-main? main-clause known-fn-set)
  (cond
    ((not (and (pair? main-clause) (eq? (car main-clause) '%lir-main)))
     (lir-report-error "%lir-main node must start with %lir-main" main-clause))
    (else
     (let ((frame-clause (assq 'frame-size (cdr main-clause)))
           (body-clause (assq 'body (cdr main-clause))))
       (with-verifier-context (list (cons 'phase 'canonical-lir) (cons 'function '%lir-main))
         (lambda ()
           (cond
             ((not (and frame-clause (integer? (cadr frame-clause))
                        (>= (cadr frame-clause) 0)
                        (= (modulo (cadr frame-clause) 8) 0)))
              (lir-report-error "%lir-main frame-size must be a non-negative multiple of 8" main-clause))
             ((not (and body-clause (list? (cdr body-clause))))
              (lir-report-error "%lir-main must have valid (body <insts>...) clause" main-clause))
             (else
              (lir-verify-insts-single-pass (cdr body-clause) known-fn-set '%lir-main)))))))))

;;; -----------------------------------------------------------------------
;;; Public API: validate-lir / verify-lir
;;; -----------------------------------------------------------------------
(define (validate-lir prog)
  (cond
    ((not (and (pair? prog) (eq? (car prog) '%lir-program)))
     (lir-report-error "Root of LIR AST must be %lir-program" prog))
    (else
     (let* ((strings-clause (assq 'strings (cdr prog)))
            (stackmaps-clause (assq 'stackmaps (cdr prog)))
            (funcs-clause (assq '%lir-functions (cdr prog)))
            (main-clause (assq '%lir-main (cdr prog))))
       (cond
         ((not strings-clause)
          (lir-report-error "%lir-program missing (strings ...) clause" prog))
         ((not stackmaps-clause)
          (lir-report-error "%lir-program missing (stackmaps ...) clause" prog))
         ((not funcs-clause)
          (lir-report-error "%lir-program missing (%lir-functions ...) clause" prog))
         ((not main-clause)
          (lir-report-error "%lir-program missing (%lir-main ...) clause" prog))
         (else
          (let* ((funcs (cdr funcs-clause))
                 (known-fn-set (make-symbol-hash-set (lir-max2 32 (* 2 (length funcs))))))
            ;; Populate known function labels in O(1)
            (let extract ((fs funcs))
              (if (null? fs)
                  #t
                  (begin
                    (if (and (pair? (car fs)) (pair? (cdar fs)) (symbol? (cadar fs)))
                        (symbol-hash-set-add! known-fn-set (cadar fs)))
                    (extract (cdr fs)))))
            (and (verify-lir-safepoint prog)
                 (let f-loop ((fs funcs))
                   (if (null? fs) #t
                       (and (lir-valid-function? (car fs) known-fn-set)
                            (f-loop (cdr fs)))))
                 (lir-valid-main? main-clause known-fn-set)
                 (if (and (>= (verifier-level) 3)
                          (assq 'L_lir_canonical (nanopass-get-languages)))
                     (if (not (nanopass-ast-valid? 'L_lir_canonical prog))
                         (lir-report-error "Program violates L_lir_canonical schema invariants" prog)
                         #t)
                     #t)))))))))

(define (verify-lir prog)
  (if (not (verifier-enabled?))
      #t
      (validate-lir prog)))
;;; =======================================================================
;;; ULisp Compiler Pass 123: LIR Closures & Stack Allocation Pass
;;; Conforms to DSN-33 Architecture Specification & Issue #583
;;; =======================================================================
;;; Lowers closure allocation (heap and stack) and stack pairs into LIR instructions.
;;; =======================================================================

(define (lir-compile-make-closure expr si env)
  (let* ((label-arg (cadr expr))
         (label-sym (if (and (pair? label-arg) (eq? (car label-arg) 'quote))
                        (cadr label-arg)
                        label-arg))
         (args (cddr expr))
         (num-args (length args))
         (closure-size (* (+ num-args 1) 8))
         (aligned-size (if (= (modulo closure-size 16) 0) closure-size (+ closure-size 8))))
    ;; 1. Evaluate arguments sequentially and place into temporary stack slots
    (let loop ((as args) (curr-si si))
      (if (not (null? as))
          (begin
            (track-lir-si! curr-si)
            (lir-compile-expr (car as) curr-si env #f)
            (emit-lir! (list '%store '%rsp curr-si '%rax))
            (loop (cdr as) (- curr-si 8)))))
    ;; 2. Allocate closure on heap (%alloc puts tagged pointer into %r10)
    (let ((lowest-si (- si (* num-args 8))))
      (emit-lir! (list '%alloc '%r10 (+ aligned-size 8) 9 lowest-si)))
    ;; 3. Write 8-byte prefix header to [%r10 - 9]
    (let* ((hdr-val (+ (+ (* aligned-size 65536) (* (+ num-args 1) 256)) 2))
           (hdr-fixnum (* hdr-val 4)))
      (emit-lir! (list '%mov '%rdx hdr-fixnum))
      (emit-lir! '(%store %r10 -9 %rdx)))
    ;; 4. Write code pointer to [%r10 - 1]
    (emit-lir! (list '%code-ref '%rax label-sym))
    (emit-lir! '(%store %r10 -1 %rax))
    ;; 5. Copy captured arguments from stack to heap [%r10 - 1 + 8 * i]
    (let loop ((i 1) (curr-si si))
      (if (<= i num-args)
          (begin
            (emit-lir! (list '%load '%rax '%rsp curr-si))
            (emit-lir! (list '%store '%r10 (+ -1 (* i 8)) '%rax))
            (loop (+ i 1) (- curr-si 8)))))
    (emit-lir! '(%mov %rax %r10))))

(define (stack-alloc-attr? attr)
  (or (eq? attr '#:stack-alloc)
      (eq? attr 'stack-alloc)
      (and (symbol? attr)
           (let ((s (symbol->string attr)))
             (or (string=? s ":stack-alloc")
                 (string=? s "#:stack-alloc"))))))

(define (stack-alloc-bytes val)
  (cond
    ((not (pair? val)) 0)
    ((eq? (car val) '%stack-cons) 24)
    ((and (eq? (car val) 'annotate)
          (pair? (cdr val))
          (stack-alloc-attr? (cadr val))
          (pair? (cddr val))
          (pair? (caddr val)))
     (let ((inner (caddr val)))
       (cond
         ((memq (car inner) '(%make-closure-env %make-closure))
          (let* ((num-args (length (cddr inner)))
                 (closure-size (* (+ num-args 1) 8))
                 (aligned-size (if (= (modulo closure-size 16) 0) closure-size (+ closure-size 8))))
            (+ aligned-size 8)))
         ((eq? (car inner) 'cons) 24)
         (else 0))))
    ((eq? (car val) '%make-stack-closure)
     (let* ((num-args (length (cddr val)))
            (closure-size (* (+ num-args 1) 8))
            (aligned-size (if (= (modulo closure-size 16) 0) closure-size (+ closure-size 8))))
       (+ aligned-size 8)))
    (else 0)))

(define (get-stack-vars env)
  (let ((entry (assq '%stack-vars env)))
    (if entry (cdr entry) '())))

(define (set-stack-vars svars env)
  (cons (cons '%stack-vars svars) env))

(define (lir-compile-stack-cons expr si env)
  (let* ((e1 (cadr expr))
         (e2 (caddr expr))
         (base-si (- si 24))
         (tmp1 (- base-si 8))
         (tmp2 (- base-si 16)))
    ;; 1. Evaluate arguments onto temporary stack slots below base-si
    (track-lir-si! tmp1)
    (lir-compile-expr e1 tmp1 env #f)
    (emit-lir! (list '%store '%rsp tmp1 '%rax))
    (track-lir-si! tmp2)
    (lir-compile-expr e2 tmp2 env #f)
    ;; 2. Allocate 24 bytes (header + car + cdr) directly on current stack frame
    (track-lir-si! base-si)
    (emit-lir! '(%mov %rdx 4196356))
    (emit-lir! (list '%store '%rsp base-si '%rdx))
    (emit-lir! (list '%load '%rdx '%rsp tmp1))
    (emit-lir! (list '%store '%rsp (+ base-si 8) '%rdx))
    (emit-lir! (list '%store '%rsp (+ base-si 16) '%rax))
    ;; 3. Return stack-allocated tagged pair pointer (offset +8 from base-si, tag 1)
    (emit-lir! (list '%alloc-stack '%rax (+ base-si 8) 1))))

(define (lir-compile-make-stack-closure expr si env)
  (let* ((label-arg (cadr expr))
         (label-sym (if (and (pair? label-arg) (eq? (car label-arg) 'quote))
                        (cadr label-arg)
                        label-arg))
         (args (cddr expr))
         (num-args (length args))
         (closure-size (* (+ num-args 1) 8))
         (aligned-size (if (= (modulo closure-size 16) 0) closure-size (+ closure-size 8)))
         (total-bytes (+ aligned-size 8))
         (base-si (- si total-bytes))
         (temp-base (- base-si 8)))
    ;; 1. Evaluate arguments sequentially and place into temporary stack slots below temp-base
    (let loop ((as args) (curr-si temp-base))
      (if (not (null? as))
          (begin
            (track-lir-si! curr-si)
            (lir-compile-expr (car as) curr-si env #f)
            (emit-lir! (list '%store '%rsp curr-si '%rax))
            (loop (cdr as) (- curr-si 8)))))
    ;; 2. Format header and store onto stack frame
    (track-lir-si! base-si)
    (let* ((hdr-val (+ (+ (* aligned-size 65536) (* (+ num-args 1) 256)) 2))
           (hdr-fixnum (* hdr-val 4)))
      (emit-lir! (list '%mov '%rdx hdr-fixnum))
      (emit-lir! (list '%store '%rsp base-si '%rdx)))
    (emit-lir! (list '%code-ref '%rax label-sym))
    (emit-lir! (list '%store '%rsp (+ base-si 8) '%rax))
    ;; 3. Copy captured arguments from temporary slots to stack closure slots
    (let loop ((i 1) (curr-si temp-base))
      (if (<= i num-args)
          (begin
            (emit-lir! (list '%load '%rax '%rsp curr-si))
            (emit-lir! (list '%store '%rsp (+ (+ base-si 8) (* i 8)) '%rax))
            (loop (+ i 1) (- curr-si 8)))))
    ;; 4. Tag closure pointer with 0x01 (offset +8 from header)
    (emit-lir! (list '%alloc-stack '%rax (+ base-si 8) 1))))
;;; =======================================================================
;;; ULisp Compiler Pass 124: LIR Procedure Invocations & Call ABI Pass
;;; Conforms to DSN-33 Architecture Specification & Issue #583
;;; =======================================================================
;;; Lowers general closure calls and direct static-label calls into LIR instructions,
;;; handling argument stack evaluation, frame shift alignment, Tail Call Optimization (TCO),
;;; and exact GC safepoint registration.
;;; =======================================================================

(define (lir-compile-call proc args si env tail?)
  (let* ((num-args (length args))
         (cur-params-entry (assq '%num-params env))
         (cur-num-params (if cur-params-entry (cdr cur-params-entry) #f))
         (stack-vars (get-stack-vars env))
         (is-stack-closure? (and (symbol? proc) (memq proc stack-vars)))
         (can-tco? (and tail?
                        (not is-stack-closure?)
                        (if cur-num-params (= cur-num-params num-args) #f)))
         (frame-shift (align-frame-shift (if (= num-args 0)
                                             (- 0 si)
                                             (- (* 8 (- num-args 1)) si))))
         (aligned-si (if (= num-args 0)
                         (- 0 frame-shift)
                         (- (* 8 (- num-args 1)) frame-shift))))
    ;; 1. Evaluate arguments sequentially and place into temporary stack slots
    (let loop ((as args) (curr-si aligned-si))
      (if (not (null? as))
          (begin
            (track-lir-si! curr-si)
            (lir-compile-expr (car as) curr-si env #f)
            (emit-lir! (list '%store '%rsp curr-si '%rax))
            (loop (cdr as) (- curr-si 8)))))

    (let ((end-args-si (- aligned-si (* num-args 8))))
      (track-lir-si! end-args-si)
      ;; 2. Evaluate procedure expression -> RAX
      (lir-compile-expr proc end-args-si env #f)
      (emit-lir! '(%mov %r10 %rax))

      (if can-tco?
          ;; --- TAIL CALL OPTIMIZATION (TCO) ---
          (begin
            (let loop ((i 0))
              (if (< i num-args)
                  (let ((temp-offset (- aligned-si (* i 8)))
                        (param-offset (* 8 (- num-args i))))
                    (emit-lir! (list '%load '%rdx '%rsp temp-offset))
                    (emit-lir! (list '%store '%rsp param-offset '%rdx))
                    (loop (+ i 1)))))
            (emit-lir! '(%load %rdx %r10 -1))
            (emit-lir! (list '%mov '%rax (* num-args 4)))
            (emit-lir! '(%jump %rdx)))

          ;; --- NON-TAIL CALL ---
          (let* ((bitmap (compute-stackmap-bitmap frame-shift aligned-si args env))
                 (safepoint-lbl (new-safepoint-label!)))
            (record-safepoint! safepoint-lbl frame-shift bitmap)
            (emit-lir! (list '%mov '%rax (* num-args 4)))
            (emit-lir! (list '%call-closure frame-shift safepoint-lbl)))))))

(define (lir-compile-direct-call label args si env tail?)
  (let* ((num-args (length args))
         (cur-params-entry (assq '%num-params env))
         (cur-num-params (if cur-params-entry (cdr cur-params-entry) #f))
         (can-tco? (and tail? (if cur-num-params (= cur-num-params num-args) #f)))
         (frame-shift (align-frame-shift (if (= num-args 0)
                                             (- 0 si)
                                             (- (* 8 (- num-args 1)) si))))
         (aligned-si (if (= num-args 0)
                         (- 0 frame-shift)
                         (- (* 8 (- num-args 1)) frame-shift))))
    ;; 1. Evaluate arguments sequentially and place into temporary stack slots
    (let loop ((as args) (curr-si aligned-si))
      (if (not (null? as))
          (begin
            (track-lir-si! curr-si)
            (lir-compile-expr (car as) curr-si env #f)
            (emit-lir! (list '%store '%rsp curr-si '%rax))
            (loop (cdr as) (- curr-si 8)))))

    (if can-tco?
        ;; --- TAIL CALL OPTIMIZATION (TCO) via Direct Jump ---
        (begin
          (let loop ((i 0))
            (if (< i num-args)
                (let ((temp-offset (- aligned-si (* i 8)))
                      (param-offset (* 8 (- num-args i))))
                  (emit-lir! (list '%load '%rdx '%rsp temp-offset))
                  (emit-lir! (list '%store '%rsp param-offset '%rdx))
                  (loop (+ i 1)))))
          (emit-lir! (list '%mov '%rax (* num-args 4)))
          (emit-lir! (list '%direct-jump label)))

        ;; --- NON-TAIL DIRECT CALL ---
        (let* ((bitmap (compute-stackmap-bitmap frame-shift aligned-si args env))
               (safepoint-lbl (new-safepoint-label!)))
          (record-safepoint! safepoint-lbl frame-shift bitmap)
          (emit-lir! (list '%mov '%rax (* num-args 4)))
          (emit-lir! (list '%direct-call label frame-shift safepoint-lbl))))))
;;; =======================================================================
;;; ULisp Compiler Pass 125: LIR Continuation Transfer & Loop In-Place Shuffle Pass
;;; Conforms to DSN-33 Architecture Specification & Issue #583
;;; =======================================================================
;;; Lowers continuation functions (%cont-fun) and continuation calls (%cont-call)
;;; into Block Arguments SSA jumps (%jump, %block), in-place register shuffle loops,
;;; and rotated do-while loops with condition flag fusion.
;;; =======================================================================

(define (expr-references-var? expr var)
  (cond
    ((eq? expr var) #t)
    ((pair? expr)
     (or (expr-references-var? (car expr) var)
         (expr-references-var? (cdr expr) var)))
    (else #f)))

(define (expr-free-references-var? expr var)
  (cond
    ((eq? expr var) #t)
    ((not (pair? expr)) #f)
    (else
     (let ((op (car expr)))
       (case op
         ((quote) #f)
         ((let letrec)
          (let* ((bindings (cadr expr))
                 (body (caddr expr))
                 (shadowed? (assq var bindings)))
            (or (let loop ((bs bindings))
                  (and (pair? bs)
                       (or (expr-free-references-var? (cadar bs) var)
                           (loop (cdr bs)))))
                (if shadowed?
                    #f
                    (expr-free-references-var? body var)))))
         ((lambda)
          (let ((params (cadr expr))
                (body (caddr expr)))
            (if (memq var params)
                #f
                (expr-free-references-var? body var))))
         ((%cont-fun)
          (let ((f-name (cadr expr))
                (params (caddr expr))
                (f-body (cadddr expr))
                (in-body (cadr (cdddr expr))))
            (or (if (memq var params) #f (expr-free-references-var? f-body var))
                (expr-free-references-var? in-body var))))
         (else
          (or (expr-free-references-var? (car expr) var)
              (expr-free-references-var? (cdr expr) var))))))))

(define (extract-in-place-const op e)
  (let* ((raw-c (if (integer? (cadr e)) (cadr e) (caddr e)))
         (is-raw? (memq op '(%raw-add %raw-sub))))
    (if is-raw? raw-c (* raw-c 4))))

(define (cont-target-all-regs? target-info)
  (let* ((p-bindings (caddr target-info))
         (num-args (length p-bindings)))
    (and (> num-args 0)
         (let check-regs ((pbs p-bindings))
           (if (null? pbs) #t
               (let ((info (cdar pbs)))
                 (and (or (and (pair? info) (eq? (car info) 'reg))
                          (memq info '(%rbx %r13 %r14 %r15)))
                      (check-regs (cdr pbs)))))))))

(define (emit-in-place-jump! entry-lbl regs)
  (if entry-lbl
      (emit-lir! (list '%jump entry-lbl regs))))

(define (lir-compile-in-place-cont-call f-name exprs target-info si env)
  (let* ((entry-lbl (cadr target-info))
         (p-bindings (caddr target-info))
         (num-args (length exprs))
         (p-names (map car* p-bindings))
         (p-regs (map (lambda (pb)
                        (let ((info (cdr pb)))
                          (if (pair? info) (cdr info) info)))
                      p-bindings)))
    (cond
      ;; === 2-Argument Hot Loop In-Place Shuffle ===
      ((= num-args 2)
       (let* ((p0 (car p-names))
              (p1 (cadr p-names))
              (r0 (car p-regs))
              (r1 (cadr p-regs))
              (e0 (car exprs))
              (e1 (cadr exprs))
              ;; Check if e0 references p1
              (e0-refs-p1? (expr-references-var? e0 p1))
              ;; Check if e1 references p0
              (e1-refs-p0? (expr-references-var? e1 p0)))
         (cond
           ;; Case 1: Swap (loop p1 p0)
           ((and (eq? e0 p1) (eq? e1 p0))
            (emit-lir! (list '%mov '%r10 r0))
            (emit-lir! (list '%mov r0 r1))
            (emit-lir! (list '%mov r1 '%r10))
            (emit-in-place-jump! entry-lbl (list r0 r1)))

           ;; Case 1b: Identity on one variable
           ((and (eq? e1 p1) (not e0-refs-p1?))
            (cond
              ((and (pair? e0)
                    (memq (car e0) '(+ %raw-add))
                    (or (and (eq? (cadr e0) p0) (integer? (caddr e0)))
                        (and (integer? (cadr e0)) (eq? (caddr e0) p0))))
               (let ((c (extract-in-place-const (car e0) e0)))
                 (emit-lir! (list '%add r0 c))))
              ((and (pair? e0)
                    (memq (car e0) '(- %raw-sub))
                    (eq? (cadr e0) p0)
                    (integer? (caddr e0)))
               (let ((c (extract-in-place-const (car e0) e0)))
                 (emit-lir! (list '%sub r0 c))))
              (else
               (lir-compile-expr e0 si env #f)
               (if (not (eq? r0 '%rax))
                   (emit-lir! (list '%mov r0 '%rax)))))
            (emit-in-place-jump! entry-lbl (list r0 r1)))

           ((and (eq? e0 p0) (not e1-refs-p0?))
            (cond
              ((and (pair? e1)
                    (memq (car e1) '(+ %raw-add))
                    (or (and (eq? (cadr e1) p1) (integer? (caddr e1)))
                        (and (integer? (cadr e1)) (eq? (caddr e1) p1))))
               (let ((c (extract-in-place-const (car e1) e1)))
                 (emit-lir! (list '%add r1 c))))
              ((and (pair? e1)
                    (memq (car e1) '(- %raw-sub))
                    (eq? (cadr e1) p1)
                    (integer? (caddr e1)))
               (let ((c (extract-in-place-const (car e1) e1)))
                 (emit-lir! (list '%sub r1 c))))
              (else
               (lir-compile-expr e1 si env #f)
               (if (not (eq? r1 '%rax))
                   (emit-lir! (list '%mov r1 '%rax)))))
            (emit-in-place-jump! entry-lbl (list r0 r1)))

           ;; Case 2: DAG dependency (e1 depends on p0, e0 does NOT depend on p1)
           ;; e.g. e0 = (+ i 1), e1 = (+ acc i). Evaluate e1 into r1 first, then e0 into r0!
           ((and e1-refs-p0? (not e0-refs-p1?))
            ;; Fast path: e1 is (%raw-add i acc) or (+ acc i) -> direct in-place add!
            (cond
              ((and (pair? e1)
                    (memq (car e1) '(+ %raw-add))
                    (or (and (eq? (cadr e1) p0) (eq? (caddr e1) p1))
                        (and (eq? (cadr e1) p1) (eq? (caddr e1) p0))))
               (emit-lir! (list '%add r1 r0)))
              ((and (pair? e1)
                    (memq (car e1) '(- %raw-sub))
                    (eq? (cadr e1) p1)
                    (eq? (caddr e1) p0))
               (emit-lir! (list '%sub r1 r0)))
              (else
               (lir-compile-expr e1 si env #f)
               (if (not (eq? r1 '%rax))
                   (emit-lir! (list '%mov r1 '%rax)))))
            ;; Now evaluate e0 into r0 in-place!
            (cond
              ((and (pair? e0)
                    (memq (car e0) '(+ %raw-add))
                    (or (and (eq? (cadr e0) p0) (integer? (caddr e0)))
                        (and (integer? (cadr e0)) (eq? (caddr e0) p0))))
               (let ((c (extract-in-place-const (car e0) e0)))
                 (emit-lir! (list '%add r0 c))))
              ((and (pair? e0)
                    (memq (car e0) '(- %raw-sub))
                    (eq? (cadr e0) p0)
                    (integer? (caddr e0)))
               (let ((c (extract-in-place-const (car e0) e0)))
                 (emit-lir! (list '%sub r0 c))))
              (else
               (lir-compile-expr e0 si env #f)
               (if (not (eq? r0 '%rax))
                   (emit-lir! (list '%mov r0 '%rax)))))
            (emit-in-place-jump! entry-lbl (list r0 r1)))

           ;; Case 3: DAG dependency (e0 depends on p1, e1 does NOT depend on p0)
           ;; Evaluate e0 into r0 first, then e1 into r1!
           ((and e0-refs-p1? (not e1-refs-p0?))
            (cond
              ((and (pair? e0)
                    (memq (car e0) '(+ %raw-add))
                    (or (and (eq? (cadr e0) p0) (eq? (caddr e0) p1))
                        (and (eq? (cadr e0) p1) (eq? (caddr e0) p0))))
               (emit-lir! (list '%add r0 r1)))
              (else
               (lir-compile-expr e0 si env #f)
               (if (not (eq? r0 '%rax))
                   (emit-lir! (list '%mov r0 '%rax)))))
            ;; Now evaluate e1 into r1 in-place!
            (cond
              ((and (pair? e1)
                    (memq (car e1) '(+ %raw-add))
                    (or (and (eq? (cadr e1) p1) (integer? (caddr e1)))
                        (and (integer? (cadr e1)) (eq? (caddr e1) p1))))
               (let ((c (extract-in-place-const (car e1) e1)))
                 (emit-lir! (list '%add r1 c))))
              ((and (pair? e1)
                    (memq (car e1) '(- %raw-sub))
                    (eq? (cadr e1) p1)
                    (integer? (caddr e1)))
               (let ((c (extract-in-place-const (car e1) e1)))
                 (emit-lir! (list '%sub r1 c))))
              (else
               (lir-compile-expr e1 si env #f)
               (if (not (eq? r1 '%rax))
                   (emit-lir! (list '%mov r1 '%rax)))))
            (emit-in-place-jump! entry-lbl (list r0 r1)))

           ;; Case 4: General 2-argument parallel update: preserve e0 on stack slot si across e1 evaluation
           (else
            (track-lir-si! si)
            (lir-compile-expr e0 si env #f)
            (emit-lir! (list '%store '%rsp si '%rax))
            (lir-compile-expr e1 (- si 8) env #f)
            (if (not (eq? r1 '%rax))
                (emit-lir! (list '%mov r1 '%rax)))
            (emit-lir! (list '%load r0 '%rsp si))
            (emit-in-place-jump! entry-lbl (list r0 r1))))))

      ;; === 1-Argument In-Place Update ===
      ((= num-args 1)
       (let ((r0 (car p-regs))
             (p0 (car p-names))
             (e0 (car exprs)))
         (cond
           ((and (pair? e0)
                 (memq (car e0) '(+ %raw-add))
                 (or (and (eq? (cadr e0) p0) (integer? (caddr e0)))
                     (and (integer? (cadr e0)) (eq? (caddr e0) p0))))
            (let ((c (extract-in-place-const (car e0) e0)))
              (emit-lir! (list '%add r0 c))))
           ((and (pair? e0)
                 (memq (car e0) '(- %raw-sub))
                 (eq? (cadr e0) p0)
                 (integer? (caddr e0)))
            (let ((c (extract-in-place-const (car e0) e0)))
              (emit-lir! (list '%sub r0 c))))
           (else
            (lir-compile-expr e0 si env #f)
            (if (not (eq? r0 '%rax))
                (emit-lir! (list '%mov r0 '%rax)))))
         (emit-in-place-jump! entry-lbl (list r0))))

      ;; === Fallback for >= 3 arguments using stack-free %cont-call ===
      (else
       (let loop ((es exprs) (curr-si si) (temp-sis '()))
         (if (pair? es)
             (begin
               (track-lir-si! curr-si)
               (lir-compile-expr (car es) curr-si env #f)
               (emit-lir! (list '%store '%rsp curr-si '%rax))
               (loop (cdr es) (- curr-si 8) (cons curr-si temp-sis)))
             (begin
               (let xfer ((ts (reverse temp-sis)) (pbs p-bindings))
                 (if (and (pair? ts) (pair? pbs))
                     (let ((t-si (car ts))
                           (p-info (cdar pbs)))
                       (cond
                         ((and (pair? p-info) (eq? (car p-info) 'reg))
                          (emit-lir! (list '%load (cdr p-info) '%rsp t-si)))
                         ((memq p-info '(%rax %rbx %rcx %rdx %rsi %rdi %rbp %rsp %r8 %r9 %r10 %r11 %r12 %r13 %r14 %r15))
                          (emit-lir! (list '%load p-info '%rsp t-si)))
                         (else
                          (emit-lir! (list '%load '%rdx '%rsp t-si))
                          (emit-lir! (list '%store '%rsp p-info '%rdx))))
                       (xfer (cdr ts) (cdr pbs)))))
               (emit-in-place-jump! entry-lbl
                                (map (lambda (pb)
                                       (let ((p-info (cdr pb)))
                                         (cond
                                           ((and (pair? p-info) (eq? (car p-info) 'reg))
                                            (cdr p-info))
                                           ((memq p-info '(%rax %rbx %rcx %rdx %rsi %rdi %rbp %rsp %r8 %r9 %r10 %r11 %r12 %r13 %r14 %r15))
                                            p-info)
                                           (else
                                            (list '%stack p-info)))))
                                     p-bindings)))))))))

(define (cont-recurse-tail? f-name expr)
  (cond
    ((not (pair? expr)) #f)
    ((eq? (car expr) '%cont-call)
     (eq? (cadr expr) f-name))
    ((eq? (car expr) 'let)
     (cont-recurse-tail? f-name (caddr expr)))
    (else #f)))

(define (cont-loop-rotation-candidate? f-name f-body)
  (cond
     ;; Pattern A: (let ((var (cmp-op lhs rhs))) (if var then-exit else-recurse))
    ((and (pair? f-body)
          (eq? (car f-body) 'let)
          (= (length (cadr f-body)) 1))
     (let* ((b (car (cadr f-body)))
            (var (car b))
            (val (cadr b))
            (inner (caddr f-body)))
       (if (and (pair? val)
                (memq (car val) '(= < <= > >= eq?))
                (= (length val) 3)
                (pair? inner)
                (eq? (car inner) 'if)
                (eq? (cadr inner) var)
                (not (expr-free-references-var? (caddr inner) var))
                (not (expr-free-references-var? (cdddr inner) var))
                (not (occurs-in? '%cont-call (caddr inner)))
                (pair? (cdddr inner))
                (cont-recurse-tail? f-name (car (cdddr inner))))
           (list val (caddr inner) (car (cdddr inner)))
           #f)))
    ;; Pattern B: (if (cmp-op lhs rhs) then-exit else-recurse)
    ((and (pair? f-body)
          (eq? (car f-body) 'if)
          (pair? (cadr f-body))
          (memq (car (cadr f-body)) '(= < <= > >= eq?))
          (= (length (cadr f-body)) 3))
     (let ((val (cadr f-body))
           (then-exit (caddr f-body))
           (else-recurse (if (pair? (cdddr f-body)) (car (cdddr f-body)) #f)))
       (if (and else-recurse
                (not (occurs-in? '%cont-call then-exit))
                (cont-recurse-tail? f-name else-recurse))
           (list val then-exit else-recurse)
           #f)))
    (else #f)))

(define (cont-body-has-external-call? expr f-name)
  (cond
    ((null? expr) #f)
    ((not (pair? expr)) #f)
    (else
     (let ((op (car expr)))
       (case op
         ((quote) #f)
         ((%cont-call)
          (if (eq? (cadr expr) f-name)
              (let loop ((args (cddr expr)))
                (and (pair? args)
                     (or (cont-body-has-external-call? (car args) f-name)
                         (loop (cdr args)))))
              #t))
         ((%direct-call %call %closure-call %c-call %syscall %raw-call/cc %make-closure %make-closure-env)
          #t)
         ((if)
          (or (cont-body-has-external-call? (cadr expr) f-name)
              (cont-body-has-external-call? (caddr expr) f-name)
              (if (null? (cdddr expr)) #f (cont-body-has-external-call? (cadddr expr) f-name))))
         ((begin)
          (let loop ((es (cdr expr)))
            (and (pair? es)
                 (or (cont-body-has-external-call? (car es) f-name)
                     (loop (cdr es))))))
         ((let letrec)
          (let* ((bindings (cadr expr))
                 (body (caddr expr))
                 (b-calls (let loop ((bs bindings))
                            (and (pair? bs)
                                 (or (cont-body-has-external-call? (cadar bs) f-name)
                                     (loop (cdr bs)))))))
            (or b-calls (cont-body-has-external-call? body f-name))))
         ((%cont-fun)
          (or (cont-body-has-external-call? (cadddr expr) f-name)
              (cont-body-has-external-call? (cadr (cdddr expr)) f-name)))
         ((%box-fixnum %unbox-fixnum %raw-add %raw-sub %raw-mul %raw-div %raw-cmp
           %bitwise-and %bitwise-ior %shift-left %shift-right %store %load
           + - * / = < <= > >= eq? null? zero? pair? not)
          (let loop ((args (cdr expr)))
            (and (pair? args)
                 (or (cont-body-has-external-call? (car args) f-name)
                     (loop (cdr args))))))
         (else
          (if (symbol? op)
              #t
              (or (cont-body-has-external-call? (car expr) f-name)
                  (cont-body-has-external-call? (cdr expr) f-name)))))))))

(define (lir-compile-cont-fun f-name params f-body in-body si env tail?)
  (let* ((entry-lbl (unique-label-sym "L_cont_entry_"))
         (exit-lbl  (unique-label-sym "L_cont_exit_"))
         (num-params (length params))
         ;; Allocate callee-saved registers (%rbx, %r13, %r14) for leaf loops with <= 3 parameters
         (use-reg-alloc? (and (<= num-params 3)
                              (not (cont-body-has-external-call? f-body f-name))))
         (rot-cand (and use-reg-alloc? (cont-loop-rotation-candidate? f-name f-body)))
         (callee-saved-regs '(%rbx %r13 %r14)))
    (cond
      ;; === Path 1: Rotated Do-While Loop (Loop Rotation / Inversion) ===
      (rot-cand
       (let* ((assigned-regs
               (let loop ((i 0) (acc '()))
                 (if (< i num-params)
                     (loop (+ i 1) (cons (list-ref callee-saved-regs i) acc))
                     (reverse acc))))
              (saved-slots
               (let loop ((rs assigned-regs) (curr-si si) (acc '()))
                 (if (null? rs)
                     acc
                     (begin
                       (track-lir-si! curr-si)
                       (emit-lir! (list '%store '%rsp curr-si (car rs)))
                       (loop (cdr rs) (- curr-si 8) (cons (cons (car rs) curr-si) acc))))))
              (p-bindings
               (let loop ((ps params) (rs assigned-regs) (acc '()))
                 (if (null? ps)
                     (reverse acc)
                     (loop (cdr ps) (cdr rs)
                           (cons (cons (car ps) (cons 'reg (car rs))) acc)))))
              (raw-vars (if (unboxed-fn? f-name)
                            (append params (get-raw-vars env))
                            (get-raw-vars env)))
              (body-env (set-raw-vars raw-vars (append p-bindings env)))
              (next-si (- si (* num-params 8)))
              (cmp-expr (car rot-cand))
              (then-exit (cadr rot-cand))
              (else-recurse (caddr rot-cand))
              (body-lbl (unique-label-sym "L_loop_body_"))
              (done-lbl (unique-label-sym "L_loop_done_"))
              ;; Note: in rot-env, target entry-lbl is #f so in-place update omits terminal %jump!
              (rot-cont-info (list '%cont-target #f p-bindings))
              (rot-env (cons (cons f-name rot-cont-info) body-env))
              ;; In init-env, initial call jumps to entry-lbl
              (init-cont-info (list '%cont-target entry-lbl p-bindings))
              (init-env (cons (cons f-name init-cont-info) body-env)))
         ;; 1. Compile in-body first: evaluates initial args into registers and jumps to entry-lbl
         (lir-compile-expr in-body next-si init-env tail?)
         (emit-lir! (list '%jump exit-lbl))

         ;; 2. Loop entry with guard check: if condition true, jump to done-lbl!
         (emit-lir! (list '%block entry-lbl assigned-regs))
         (lir-compile-fused-cmp-cond (car cmp-expr) (cadr cmp-expr) (caddr cmp-expr)
                                     done-lbl lir-cmp-true-cc next-si rot-env)

         ;; 3. Loop body: in-place update args, then backward conditional branch!
         (emit-lir! (list '%block body-lbl '()))
         (lir-compile-expr else-recurse next-si rot-env #f)
         (lir-compile-fused-cmp-cond (car cmp-expr) (cadr cmp-expr) (caddr cmp-expr)
                                     body-lbl lir-cmp-false-cc next-si rot-env)

         ;; 4. Loop exit / termination
         (emit-lir! (list '%block done-lbl '()))
         (lir-compile-expr then-exit next-si rot-env tail?)
         (emit-lir! (list '%label exit-lbl))
         ;; 5. Restore saved callee-saved registers upon exiting the loop
         (for-each
          (lambda (entry)
            (let ((reg (car entry))
                  (slot (cdr entry)))
              (emit-lir! (list '%load reg '%rsp slot))))
          (reverse saved-slots))))

      ;; === Path 2: Standard Leaf Loop Register Allocation ===
      (use-reg-alloc?
       (let* ((assigned-regs
               (let loop ((i 0) (acc '()))
                 (if (< i num-params)
                     (loop (+ i 1) (cons (list-ref callee-saved-regs i) acc))
                     (reverse acc))))
              ;; 1. Save original callee-saved registers to frame stack slots
              (saved-slots
               (let loop ((rs assigned-regs) (curr-si si) (acc '()))
                 (if (null? rs)
                     acc
                     (begin
                       (track-lir-si! curr-si)
                       (emit-lir! (list '%store '%rsp curr-si (car rs)))
                       (loop (cdr rs) (- curr-si 8) (cons (cons (car rs) curr-si) acc))))))
              (p-bindings
               (let loop ((ps params) (rs assigned-regs) (acc '()))
                 (if (null? ps)
                     (reverse acc)
                     (loop (cdr ps) (cdr rs)
                           (cons (cons (car ps) (cons 'reg (car rs))) acc)))))
              (raw-vars (if (unboxed-fn? f-name)
                            (append params (get-raw-vars env))
                            (get-raw-vars env)))
              (body-env (set-raw-vars raw-vars (append p-bindings env)))
              (next-si (- si (* num-params 8)))
              ;; Record contification target info in env
              (cont-info (list '%cont-target entry-lbl p-bindings))
              (full-env (cons (cons f-name cont-info) body-env)))
         ;; Compile in-body first (evaluates initial call into registers and jumps to entry-lbl)
         (lir-compile-expr in-body next-si full-env tail?)
         (emit-lir! (list '%jump exit-lbl))
         ;; Continuation function body entry: emitted as %block with register block arguments!
         (emit-lir! (list '%block entry-lbl assigned-regs))
         (lir-compile-expr f-body next-si full-env tail?)
         (emit-lir! (list '%label exit-lbl))
         ;; Restore saved callee-saved registers upon exiting the loop
         (for-each
          (lambda (entry)
            (let ((reg (car entry))
                  (slot (cdr entry)))
              (emit-lir! (list '%load reg '%rsp slot))))
          (reverse saved-slots))))

      ;; === Path 3: Stack-based Fallback Path (> 3 params or non-leaf) ===
      (else
        (let* ((param-slots
                (let loop ((ps params) (curr-si si) (acc-slots '()) (acc-env env))
                  (if (null? ps)
                      (cons (reverse acc-slots) acc-env)
                      (begin
                        (track-lir-si! curr-si)
                        (loop (cdr ps)
                              (- curr-si 8)
                              (cons (cons (car ps) curr-si) acc-slots)
                              (cons (cons (car ps) curr-si) acc-env))))))
               (p-offsets (car param-slots))
               (raw-vars (if (unboxed-fn? f-name)
                             (append params (get-raw-vars env))
                             (get-raw-vars env)))
               (body-env (set-raw-vars raw-vars (cdr param-slots)))
               (next-si (- si (* (length params) 8)))
               ;; Record contification target info in env
               (cont-info (list '%cont-target entry-lbl p-offsets))
               (full-env (cons (cons f-name cont-info) body-env)))
          ;; Compile in-body first
          (lir-compile-expr in-body next-si full-env tail?)
          (emit-lir! (list '%jump exit-lbl))
          ;; Continuation function body entry: emitted as %block with block arguments!
          (emit-lir! (list '%block entry-lbl (map (lambda (po) (list '%stack (cdr po))) p-offsets)))
          (lir-compile-expr f-body next-si full-env tail?)
          (emit-lir! (list '%label exit-lbl)))))))

(define (lir-compile-cont-call f-name args si env)
  (let ((binding (assq f-name env)))
    (if (not (and binding (pair? (cdr binding)) (eq? (cadr binding) '%cont-target)))
        (error "Unresolved %cont-call target:" f-name)
        (let* ((target-info (cdr binding))
               (entry-lbl (cadr target-info))
               (p-bindings (caddr target-info))
               (num-args (length args))
               (all-reg-targets? (cont-target-all-regs? target-info)))
          (if (not (= num-args (length p-bindings)))
              (error "Arity mismatch in %cont-call:" f-name)
              (cond
                ;; === In-Place / Register-Only Transfer Path ===
                (all-reg-targets?
                 (lir-compile-in-place-cont-call f-name args target-info si env))

                (else
                 ;; === General Transfer Path (sequential stack evaluation) ===
                 (let eval-loop ((as args) (curr-si si) (temp-sis '()))
                   (if (pair? as)
                       (begin
                         (track-lir-si! curr-si)
                         (lir-compile-expr (car as) curr-si env #f)
                         (emit-lir! (list '%store '%rsp curr-si '%rax))
                         (eval-loop (cdr as) (- curr-si 8) (cons curr-si temp-sis)))
                       (begin
                         ;; Transfer temporary values to parameter slots or registers
                         (let xfer-loop ((ts (reverse temp-sis)) (pbs p-bindings))
                           (if (and (pair? ts) (pair? pbs))
                               (let ((t-si (car ts))
                                     (p-info (cdar pbs)))
                                 (cond
                                   ((and (pair? p-info) (eq? (car p-info) 'reg))
                                    (emit-lir! (list '%load (cdr p-info) '%rsp t-si)))
                                   ((memq p-info '(%rax %rbx %rcx %rdx %rsi %rdi %rbp %rsp %r8 %r9 %r10 %r11 %r12 %r13 %r14 %r15))
                                    (emit-lir! (list '%load p-info '%rsp t-si)))
                                   (else
                                    (emit-lir! (list '%load '%rdx '%rsp t-si))
                                    (emit-lir! (list '%store '%rsp p-info '%rdx))))
                                 (xfer-loop (cdr ts) (cdr pbs)))))
                         ;; Directly jump to continuation target with block arguments!
                         (emit-lir! (list '%jump entry-lbl
                                          (map (lambda (pb)
                                                 (let ((p-info (cdr pb)))
                                                   (cond
                                                     ((and (pair? p-info) (eq? (car p-info) 'reg))
                                                      (cdr p-info))
                                                     ((memq p-info '(%rax %rbx %rcx %rdx %rsi %rdi %rbp %rsp %r8 %r9 %r10 %r11 %r12 %r13 %r14 %r15))
                                                      p-info)
                                                     (else
                                                      (list '%stack p-info)))))
                                               p-bindings)))))))))))))
;;; =======================================================================
;;; ULisp Compiler Pass 126: LIR Control Flow & Join Path Splitting Pass
;;; Conforms to DSN-33 Architecture Specification & Issue #583
;;; =======================================================================
;;; Lowers high-level control structures (let, if, begin) into LIR blocks,
;;; performing Join Node Path Splitting and ANF Condition/Branch Flag Fusion.
;;; =======================================================================

(define (lir-compile-let bindings body si env tail?)
  (cond
    ;; In-place Tail Loop Argument Shuffle: (let ((t0 e0) (t1 e1) ...) (%cont-call loop t0 t1 ...))
    ((and (pair? body)
          (eq? (car body) '%cont-call)
          (let* ((f-name (cadr body))
                 (call-args (cddr body))
                 (binding-vars (map car* bindings))
                 (b-entry (assq f-name env)))
            (and (equal? call-args binding-vars)
                 b-entry
                 (pair? (cdr b-entry))
                 (eq? (cadr b-entry) '%cont-target)
                 (cont-target-all-regs? (cdr b-entry)))))
     (let* ((f-name (cadr body))
            (target-info (cdr (assq f-name env)))
            (exprs (map cadr bindings)))
       (lir-compile-in-place-cont-call f-name exprs target-info si env)))

    ;; Flag / Branch Fusion on ANF: (let ((var (cmp-or-pred-expr ...))) (if var then-e else-e))
    ((and (= (length bindings) 1)
          (let* ((b (car bindings))
                 (var (car b))
                 (val (cadr b)))
            (and (pair? val)
                 (memq (car val) '(= < <= > >= eq? null? zero? pair? not))
                 (pair? body)
                 (eq? (car body) 'if)
                 (eq? (cadr body) var)
                 (not (expr-free-references-var? (caddr body) var))
                 (not (expr-free-references-var? (cdddr body) var)))))
     (let* ((b (car bindings))
            (val (cadr b))
            (then-e (caddr body))
            (else-opt (cdddr body)))
       (lir-compile-if val then-e else-opt si env tail?)))

    ;; Path Splitting on join nodes: (let ((var (if cond then-e else-e))) body)
    ((and (= (length bindings) 1)
          (let* ((b (car bindings))
                 (val (cadr b)))
            (and (pair? val)
                 (eq? (car val) 'if)
                 (<= (expr-size body) 40)
                 (let ((var (car b)))
                   (expr-has-conditional-or-pred-on-var? body var)))))
     (let* ((b (car bindings))
            (var (car b))
            (if-expr (cadr b))
            (cond-part (cadr if-expr))
            (then-e (caddr if-expr))
            (else-e (if (null? (cdddr if-expr)) #f (cadddr if-expr))))
       (lir-compile-if cond-part
                       (list 'let (list (list var then-e)) body)
                       (list (list 'let (list (list var else-e)) body))
                       si env tail?)))
    (else
     (let loop ((bs bindings)
                (curr-si si)
                (new-env env))
       (if (null? bs)
           (lir-compile-expr body curr-si new-env tail?)
           (let* ((b (car bs))
                  (var (car b))
                  (val (cadr b))
                  (rvars (get-raw-vars new-env))
                  (is-raw (raw-expr? val rvars))
                  (next-rvars (if is-raw (cons var rvars) rvars))
                  (extra-bytes (stack-alloc-bytes val))
                  (svars (get-stack-vars new-env))
                  (next-svars (if (> extra-bytes 0) (cons var svars) svars))
                  (next-si (if (> extra-bytes 0)
                               (- curr-si (+ 8 extra-bytes))
                               (- curr-si 8))))
             (track-lir-si! curr-si)
             (if (> extra-bytes 0)
                 (track-lir-si! next-si))
             (lir-compile-expr val curr-si env #f)
             (emit-lir! (list '%store '%rsp curr-si '%rax))
             (loop (cdr bs)
                   next-si
                   (cons (cons var curr-si)
                         (set-stack-vars next-svars (set-raw-vars next-rvars new-env))))))))))

(define (lir-compile-if test then else-opt si env tail?)
  (let ((else-label (unique-label-sym "L_else"))
        (end-label (unique-label-sym "L_end")))
    (cond
      ;; 1. Branch Fusion: binary comparisons (=, <, <=, >, >=, eq?)
      ((and (pair? test) (memq (car test) '(= < <= > >= eq?)) (= (length test) 3))
       (lir-compile-fused-cmp (car test) (cadr test) (caddr test) else-label si env))

      ;; 2. Branch Fusion: null?
      ((and (pair? test) (eq? (car test) 'null?) (= (length test) 2))
       (lir-compile-expr (cadr test) si env #f)
       (emit-lir! (list '%cmp '%rax 63))
       (emit-lir! (list '%jump-cond "jne" else-label)))

      ;; 3. Branch Fusion: zero?
      ((and (pair? test) (eq? (car test) 'zero?) (= (length test) 2))
       (let ((r (env-reg-var? (cadr test) env)))
         (if r
             (emit-lir! (list '%cmp r 0))
             (begin
               (lir-compile-expr (cadr test) si env #f)
               (emit-lir! (list '%cmp '%rax 0))))
         (emit-lir! (list '%jump-cond "jne" else-label))))

      ;; 4. Branch Fusion: pair?
      ((and (pair? test) (eq? (car test) 'pair?) (= (length test) 2))
       (lir-compile-expr (cadr test) si env #f)
       (emit-lir! '(%bit-and %rax 3))
       (emit-lir! (list '%cmp '%rax 1))
       (emit-lir! (list '%jump-cond "jne" else-label)))

      ;; 5. Branch Fusion: not
      ((and (pair? test) (eq? (car test) 'not) (= (length test) 2))
       (lir-compile-expr (cadr test) si env #f)
       (emit-lir! (list '%cmp '%rax 47))
       (emit-lir! (list '%jump-cond "jne" else-label)))

      ;; 6. Standard boolean expression fallback
      (else
       (lir-compile-expr test si env #f)
       (emit-lir! (list '%jump-if-false '%rax else-label))))

    (lir-compile-expr then si env tail?)
    (emit-lir! (list '%jump end-label (list '%rax)))
    (emit-lir! (list '%block else-label '()))
    (if (null? else-opt)
        (emit-lir! '(%mov %rax 47))
        (lir-compile-expr (car else-opt) si env tail?))
    (emit-lir! (list '%block end-label (list '%rax)))))

(define (lir-compile-begin exprs si env tail?)
  (if (null? exprs)
      (emit-lir! '(%mov %rax 63))
      (let loop ((es exprs))
        (if (null? (cdr es))
            (lir-compile-expr (car es) si env tail?)
            (begin
              (lir-compile-expr (car es) si env #f)
              (loop (cdr es)))))))
;;; =======================================================================
;;; ULisp Compiler Pass 127: LIR Runtime & Advanced Features Pass
;;; Conforms to DSN-33 Architecture Specification & Issue #583
;;; =======================================================================
;;; Lowers runtime advanced operations into LIR instructions:
;;; - Structured exception handling (%with-handler, %push-handler, %pop-handler)
;;; - Multiple values production (%values, %set-values-count, %store-values-buf)
;;; - Multiple values consumption (%call-with-values, %dispatch-consumer)
;;; - First-class continuations (%raw-call/cc, %capture-cc)
;;; =======================================================================

(define (lir-compile-with-handler handler-expr thunk-expr si env tail?)
  (let* ((exit-lbl (unique-label-sym "L_handler_exit_"))
         (catch-lbl (unique-label-sym "L_handler_catch_"))
         (handler-si si)
         (thunk-si (- si 8))
         (frame-si (- si 48))
         (call-si (- frame-si 8)))
    (track-lir-si! handler-si)
    (track-lir-si! thunk-si)
    (track-lir-si! frame-si)
    (track-lir-si! call-si)
    ;; 1. Evaluate handler closure and store at handler-si
    (lir-compile-expr handler-expr handler-si env #f)
    (emit-lir! (list '%store '%rsp handler-si '%rax))
    ;; 2. Evaluate thunk closure and store at thunk-si
    (lir-compile-expr thunk-expr thunk-si env #f)
    (emit-lir! (list '%store '%rsp thunk-si '%rax))
    ;; 3. Push handler frame: %push-handler catch-lbl frame-si handler-si
    (emit-lir! (list '%push-handler catch-lbl frame-si handler-si))
    ;; 4. Call thunk closure with 0 arguments
    (emit-lir! (list '%load '%rax '%rsp thunk-si))
    (emit-lir! '(%mov %r10 %rax))
    (let* ((frame-shift (align-frame-shift (- 0 call-si)))
           (safepoint-lbl (new-safepoint-label!))
           (bitmap (compute-stackmap-bitmap frame-shift call-si '() env)))
      (record-safepoint! safepoint-lbl frame-shift bitmap)
      (emit-lir! (list '%mov '%rax 0))
      (emit-lir! (list '%call-closure frame-shift safepoint-lbl)))
    ;; 5. Normal return from thunk: Pop handler frame and jump to exit
    (emit-lir! (list '%pop-handler frame-si))
    (emit-lir! (list '%jump exit-lbl))
    ;; 6. Exception catch entry: control arrives here on %raise
    (emit-lir! (list '%label catch-lbl))
    (let* ((frame-shift (align-frame-shift (- 0 call-si)))
           (aligned-si (- 0 frame-shift)))
      (track-lir-si! aligned-si)
      (emit-lir! (list '%store '%rsp aligned-si '%rdi))
      (emit-lir! '(%mov %r10 %rax))
      (let* ((safepoint-lbl (new-safepoint-label!))
             (bitmap (compute-stackmap-bitmap frame-shift aligned-si (list '%rdi) env)))
        (record-safepoint! safepoint-lbl frame-shift bitmap)
        (emit-lir! (list '%mov '%rax 4))
        (emit-lir! (list '%call-closure frame-shift safepoint-lbl))))
    ;; 7. Exit label
    (emit-lir! (list '%label exit-lbl))))

(define (lir-compile-values args si env)
  (let ((count (length args)))
    (cond
      ((= count 0)
       (emit-lir! (list '%set-values-count 0))
       (emit-lir! '(%mov %rax 63)))
      ((= count 1)
       (lir-compile-expr (car args) si env #f)
       (emit-lir! (list '%set-values-count 1)))
      (else
       ;; Evaluate each argument and save on stack
       (let loop ((as args) (curr-si si))
         (if (not (null? as))
             (begin
               (track-lir-si! curr-si)
               (lir-compile-expr (car as) curr-si env #f)
               (emit-lir! (list '%store '%rsp curr-si '%rax))
               (loop (cdr as) (- curr-si 8)))))
       (emit-lir! (list '%store-values-buf si count))
       (emit-lir! (list '%set-values-count count))
       ;; Load first argument to RAX
       (emit-lir! (list '%load '%rax '%rsp si))
       ;; Load second argument to RDX
       (emit-lir! (list '%load '%rdx '%rsp (- si 8)))))))

(define (lir-compile-call-with-values producer-expr consumer-expr si env tail?)
  (let* ((consumer-si si)
         (producer-si (- si 8))
         (call-si (- producer-si 8)))
    (track-lir-si! consumer-si)
    (track-lir-si! producer-si)
    (track-lir-si! call-si)
    ;; 1. Evaluate consumer closure and store at consumer-si
    (lir-compile-expr consumer-expr consumer-si env #f)
    (emit-lir! (list '%store '%rsp consumer-si '%rax))
    ;; 2. Evaluate producer closure and store at producer-si
    (lir-compile-expr producer-expr producer-si env #f)
    (emit-lir! (list '%store '%rsp producer-si '%rax))
    ;; 3. Call producer with 0 arguments (initialize default count to 1)
    (emit-lir! (list '%set-values-count 1))
    (emit-lir! (list '%load '%rax '%rsp producer-si))
    (emit-lir! '(%mov %r10 %rax))
    (let* ((frame-shift (align-frame-shift (- 0 call-si)))
           (safepoint-lbl (new-safepoint-label!))
           (bitmap (compute-stackmap-bitmap frame-shift call-si '() env)))
      (record-safepoint! safepoint-lbl frame-shift bitmap)
      (emit-lir! (list '%mov '%rax 0))
      (emit-lir! (list '%call-closure frame-shift safepoint-lbl)))
    ;; 4. Dispatch to consumer based on ulisp_values_count
    (let* ((frame-shift (align-frame-shift (- 0 call-si)))
           (aligned-si (- 0 frame-shift)))
      (track-lir-si! aligned-si)
      (track-lir-si! (- aligned-si 32))
      (emit-lir! (list '%dispatch-consumer consumer-si aligned-si frame-shift)))))

(define (lir-compile-raw-call-cc proc-expr si env tail?)
  (let* ((proc-si si)
         (k-si (- si 8))
         (call-si (- k-si 8))
         (ret-lbl (unique-label-sym "L_callcc_ret_")))
    (track-lir-si! proc-si)
    (track-lir-si! k-si)
    (track-lir-si! call-si)
    ;; 1. Evaluate proc-expr and store at proc-si
    (lir-compile-expr proc-expr proc-si env #f)
    (emit-lir! (list '%store '%rsp proc-si '%rax))
    ;; 2. Capture continuation: creates continuation object in %rax and stores to k-si
    (emit-lir! (list '%capture-cc ret-lbl k-si))
    ;; 3. Call proc with 1 argument (k)
    (emit-lir! (list '%load '%rax '%rsp k-si))
    (emit-lir! (list '%load '%r10 '%rsp proc-si))
    (let* ((frame-shift (align-frame-shift (- 0 call-si)))
           (aligned-si (- 0 frame-shift)))
      (track-lir-si! aligned-si)
      (emit-lir! (list '%store '%rsp aligned-si '%rax))
      (let* ((safepoint-lbl (new-safepoint-label!))
             (bitmap (compute-stackmap-bitmap frame-shift call-si '() env)))
        (record-safepoint! safepoint-lbl frame-shift bitmap)
        (emit-lir! (list '%mov '%rax 4))
        (emit-lir! (list '%call-closure frame-shift safepoint-lbl))))
    ;; 4. Return label: both normal return and (k val) jump here!
    (emit-lir! (list '%block ret-lbl '()))))
;;; =======================================================================
;;; ULisp Compiler Pass 128: LIR Branch & Comparison Flag Fusion
;;; Conforms to DSN-33 Architecture Specification & Issues #571, #595
;;; Fuses relational comparisons directly into conditional jumps (%jump-cond)
;;; eliminating intermediate boolean instantiation.
;;; =======================================================================

(define (lir-cmp-false-cc op)
  (case op
    ((= eq?) "jne")
    ((<)     "jge")
    ((<=)    "jg")
    ((>)     "jle")
    ((>=)    "jl")
    (else    "jne")))

(define (lir-cmp-true-cc op)
  (case op
    ((= eq?) "je")
    ((<)     "jl")
    ((<=)    "jle")
    ((>)     "jg")
    ((>=)    "jge")
    (else    "je")))

(define (lir-invert-cond-op op)
  (cond
    ((or (equal? op "je") (eq? op 'je) (eq? op 'equal) (eq? op 'zero)) "jne")
    ((or (equal? op "jne") (eq? op 'jne) (eq? op 'not-equal) (eq? op 'not-zero)) "je")
    ((or (equal? op "jl") (eq? op 'jl) (eq? op 'less)) "jge")
    ((or (equal? op "jle") (eq? op 'jle) (eq? op 'less-equal)) "jg")
    ((or (equal? op "jg") (eq? op 'jg) (eq? op 'greater)) "jle")
    ((or (equal? op "jge") (eq? op 'jge) (eq? op 'greater-equal)) "jl")
    (else "jne")))

(define (extract-fused-cmp-int e)
  (cond
    ((integer? e) (* e 4))
    ((and (pair? e) (eq? (car e) '%unbox-fixnum) (integer? (cadr e))) (cadr e))
    (else #f)))

(define (lir-compile-fused-cmp-cond op e1 e2 target-label jmp-cc-fn si env)
  (let* ((jmp-op (jmp-cc-fn op))
         (r1 (env-reg-var? e1 env))
         (r2 (env-reg-var? e2 env))
         (c1 (extract-fused-cmp-int e1))
         (c2 (extract-fused-cmp-int e2)))
    (cond
      ;; 1. e1 is reg, e2 is integer constant -> direct cmp reg, c2
      ((and r1 c2)
       (emit-lir! (list '%cmp r1 c2))
       (emit-lir! (list '%jump-cond jmp-op target-label)))

      ;; 2. e2 is reg, e1 is integer constant -> reverse comparison
      ((and r2 c1)
       (let ((rev-op (case op
                       ((= eq?) '=)
                       ((<)     '>)
                       ((<=)    '>=)
                       ((>)     '<)
                       ((>=)    '<=)
                       (else    op))))
         (emit-lir! (list '%cmp r2 c1))
         (emit-lir! (list '%jump-cond (jmp-cc-fn rev-op) target-label))))

      ;; 3. Both are register variables -> cmp r1, r2
      ((and r1 r2)
       (emit-lir! (list '%cmp r1 r2))
       (emit-lir! (list '%jump-cond jmp-op target-label)))

      ;; 4. e1 is reg, e2 is expr -> evaluate e2 to rax, then cmp r1, rax
      (r1
       (lir-compile-expr e2 si env #f)
       (emit-lir! (list '%cmp r1 '%rax))
       (emit-lir! (list '%jump-cond jmp-op target-label)))

      ;; 5. e2 is reg, e1 is expr -> evaluate e1 to rax, then cmp rax, r2
      (r2
       (lir-compile-expr e1 si env #f)
       (emit-lir! (list '%cmp '%rax r2))
       (emit-lir! (list '%jump-cond jmp-op target-label)))

      ;; 6. General fallback: evaluate e1 to stack, evaluate e2 to rax, then cmp (stack si), rax
      (else
       (track-lir-si! si)
       (lir-compile-operand-for-op op e1 si env)
       (emit-lir! (list '%store '%rsp si '%rax))
       (track-lir-si! (- si 8))
       (lir-compile-operand-for-op op e2 (- si 8) env)
       (emit-lir! (list '%cmp (list '%stack si) '%rax))
       (emit-lir! (list '%jump-cond jmp-op target-label))))))

(define (lir-compile-fused-cmp op e1 e2 else-label si env)
  (lir-compile-fused-cmp-cond op e1 e2 else-label lir-cmp-false-cc si env))

;;; -----------------------------------------------------------------------
;;; Linear LIR Branch Fusion Transformer
;;; -----------------------------------------------------------------------

(define (optimize-branch-fusion insts)
  (let loop ((rest insts) (acc '()))
    (cond
      ((null? rest)
       (reverse acc))

      ;; Pattern 1: (%cmp opnd1 opnd2) followed by (%set-boolean reg cond) and (%jump-if-false reg lbl)
      ;; -> (%cmp opnd1 opnd2) followed by (%jump-cond (invert-cc cond) lbl)
      ((and (pair? rest)
            (pair? (cdr rest))
            (pair? (cddr rest))
            (pair? (car rest))
            (memq (caar rest) '(%cmp %raw-cmp))
            (pair? (cadr rest))
            (eq? (car (cadr rest)) '%set-boolean)
            (pair? (caddr rest))
            (eq? (car (caddr rest)) '%jump-if-false)
            (equal? (cadr (cadr rest)) (cadr (caddr rest))))
       (let* ((cmp-inst (car rest))
              (set-b (cadr rest))
              (jmp-inst (caddr rest))
              (cond-op (caddr set-b))
              (target-lbl (caddr jmp-inst))
              (fused-jmp (list '%jump-cond (lir-invert-cond-op cond-op) target-lbl)))
         (loop (cdddr rest) (cons fused-jmp (cons cmp-inst acc)))))

      ;; Pattern 2: (%set-boolean reg cond) followed by (%jump-if-false reg lbl)
      ;; -> (%jump-cond (invert-cc cond) lbl)
      ((and (pair? rest)
            (pair? (cdr rest))
            (pair? (car rest))
            (eq? (caar rest) '%set-boolean)
            (pair? (cadr rest))
            (eq? (car (cadr rest)) '%jump-if-false)
            (equal? (cadar rest) (cadr (cadr rest))))
       (let* ((set-b (car rest))
              (jmp-inst (cadr rest))
              (cond-op (caddr set-b))
              (target-lbl (caddr jmp-inst))
              (fused-jmp (list '%jump-cond (lir-invert-cond-op cond-op) target-lbl)))
         (loop (cddr rest) (cons fused-jmp acc))))

      ;; Pattern 3: (%cmp reg const) followed by (%jump-if-false reg2 lbl)
      ((and (pair? rest)
            (pair? (cdr rest))
            (pair? (car rest))
            (memq (caar rest) '(%cmp %raw-cmp))
            (pair? (cadr rest))
            (eq? (car (cadr rest)) '%jump-if-false))
       (let* ((cmp-inst (car rest))
              (jmp-inst (cadr rest))
              (target-lbl (caddr jmp-inst))
              (fused-jmp (list '%jump-cond "jne" target-lbl)))
         (loop (cddr rest) (cons fused-jmp (cons cmp-inst acc)))))

      (else
       (loop (cdr rest) (cons (car rest) acc))))))

;;; -----------------------------------------------------------------------
;;; Nanopass DSL Pass: lir-fuse-branches
;;; -----------------------------------------------------------------------

(define-pass lir-fuse-branches : L_lir_canonical (ir) -> L_lir_canonical ()
  (entry Program)
  (Program : Program (p) -> Program ()
    ((%lir-program (strings ,se) (stackmaps ,sm) (%lir-functions ,f ...) ,m)
     (list '%lir-program
           (list 'strings se)
           (list 'stackmaps sm)
           (cons '%lir-functions (map FunctionDecl f))
           (MainDecl m))))
  (FunctionDecl : FunctionDecl (f) -> FunctionDecl ()
    ((%lir-function ,lbl (params (,x ...)) (frame-size ,frame_size) (body ,inst ...))
     (list '%lir-function
           lbl
           (list 'params x)
           (list 'frame-size frame_size)
           (cons 'body (optimize-branch-fusion inst)))))
  (MainDecl : MainDecl (m) -> MainDecl ()
    ((%lir-main (frame-size ,frame_size) (body ,inst ...))
     (list '%lir-main
           (list 'frame-size frame_size)
           (cons 'body (optimize-branch-fusion inst))))))
;;; =======================================================================
;;; ULisp Compiler Pass 129: LIR Primitive Instruction Selection
;;; =======================================================================
;;; Extracts primitive operator compilation (zero-arg, unary, binary,
;;; ternary, and raw syscall) out of the monolithic 130_lir.scm pass.
;;; =======================================================================

(define (lir-compile-zero-arg op si env)
  (let ((frame-shift (align-frame-shift (- si))))
    (case op
      ((%get-rsp)
       (emit-lir! '(%mov %rax %rsp)))
      ((%get-heap-ptr)
       (emit-lir! '(%mov %rax %r12)))
      ((%get-gc-state-ptr)
       (emit-lir! (list '%code-ref '%rax "ulisp_gc_state")))
      ((%get-heap-limit-ptr)
       (emit-lir! (list '%code-ref '%rax "ulisp_heap_limit")))
      ((%get-stackmap-table)
       (emit-lir! (list '%code-ref '%rax "__ulisp_stackmap_table")))
      ((eof-object)
       (emit-lir! '(%mov %rax 79)))
      ((%num-args)
       (emit-lir! '(%load %rax %rsp -16)))
      ((read-char %read-char)
       (emit-lir! (list '%c-call "ulisp_read_char" frame-shift)))
      ((peek-char %peek-char)
       (emit-lir! (list '%c-call "ulisp_peek_char" frame-shift)))
      ((flush-output-port ulisp-flush)
       (emit-lir! (list '%c-call "ulisp_flush" frame-shift))))))

(define (lir-compile-unary op arg si env)
  (lir-compile-expr arg si env #f)
  (case op
    ((-)
     (emit-lir! '(%neg %rax)))
    ((fxadd1)
     (emit-lir! '(%add %rax 4)))
    ((fxsub1)
     (emit-lir! '(%sub %rax 4)))
    ((fixnum->char integer->char)
     (emit-lir! '(%shl %rax 6))
     (emit-lir! '(%bit-or %rax 14)))
    ((char->fixnum char->integer)
     (emit-lir! '(%sar %rax 6)))
    ((integer->symbol)
     (emit-lir! '(%shl %rax 6))
     (emit-lir! '(%bit-or %rax 2)))
    ((symbol->integer)
     (emit-lir! '(%sar %rax 6)))
    ((zero?)
     (emit-lir! '(%cmp %rax 0))
     (emit-lir! '(%set-boolean %rax "sete")))
    ((fixnum? integer? number? exact? exact-integer? real? rational? complex?)
     (emit-lir! '(%bit-and %rax 3))
     (emit-lir! '(%cmp %rax 0))
     (emit-lir! '(%set-boolean %rax "sete")))
    ((inexact?)
     (emit-lir! '(%mov %rax 47)))
    ((boolean?)
     (emit-lir! '(%mov %rdx %rax))
     (emit-lir! '(%bit-xor %rdx 47))
     (emit-lir! '(%bit-and %rdx -65))
     (emit-lir! '(%cmp %rdx 0))
     (emit-lir! '(%set-boolean %rax "sete")))
    ((char?)
     (emit-lir! '(%bit-and %rax 255))
     (emit-lir! '(%cmp %rax 14))
     (emit-lir! '(%set-boolean %rax "sete")))
    ((null?)
     (emit-lir! '(%cmp %rax 63))
     (emit-lir! '(%set-boolean %rax "sete")))
    ((not)
     (emit-lir! '(%cmp %rax 47))
     (emit-lir! '(%set-boolean %rax "sete")))
    ((symbol?)
     (emit-lir! '(%bit-and %rax 255))
     (emit-lir! '(%cmp %rax 2))
     (emit-lir! '(%set-boolean %rax "sete")))
    ((car)
     (emit-lir! '(%load %rax %rax -1)))
    ((cdr)
     (emit-lir! '(%load %rax %rax 7)))
    ((pair? procedure?)
     (emit-lir! '(%bit-and %rax 3))
     (emit-lir! '(%cmp %rax 1))
     (emit-lir! '(%set-boolean %rax "sete")))
    ((string?)
     (emit-lir! '(%bit-and %rax 7))
     (emit-lir! '(%cmp %rax 3))
     (emit-lir! '(%set-boolean %rax "sete")))
    ((bytevector?)
     (emit-lir! '(%bit-and %rax 7))
     (emit-lir! '(%cmp %rax 7))
     (emit-lir! '(%set-boolean %rax "sete")))
    ((vector?)
     (emit-lir! '(%bit-and %rax 7))
     (emit-lir! '(%cmp %rax 5))
     (emit-lir! '(%set-boolean %rax "sete")))
    ((write-char %write-char)
     (let ((frame-shift (align-frame-shift (- si))))
       (emit-lir! '(%mov %rdi %rax))
       (emit-lir! (list '%c-call "ulisp_write_char" frame-shift))))
    ((write-string %write-string)
     (let ((frame-shift (align-frame-shift (- si))))
       (emit-lir! '(%mov %rdi %rax))
       (emit-lir! (list '%c-call "ulisp_write_string" frame-shift))))
    ((flush-output-port ulisp-flush)
     (let ((frame-shift (align-frame-shift (- si))))
       (emit-lir! (list '%c-call "ulisp_flush" frame-shift))))
    ((raise %raise)
     (emit-lir! '(%raise)))
    ((eof-object?)
     (emit-lir! '(%cmp %rax 79))
     (emit-lir! '(%set-boolean %rax "sete")))
    ((%set-heap-ptr!)
     (emit-lir! '(%mov %r12 %rax)))
    ((%ptr-tag)
     (emit-lir! '(%bit-and %rax 7))
     (emit-lir! '(%shl %rax 2)))
    ((%ptr-untag)
     (emit-lir! '(%bit-and %rax -8)))
    ((%to-raw)
     (emit-lir! '(%sar %rax 2)))
    ((%to-fixnum)
     (emit-lir! '(%shl %rax 2)))
    ((%box-fixnum)
     (emit-lir! '(%box-fixnum %rax %rax)))
    ((%unbox-fixnum)
     (emit-lir! '(%unbox-fixnum %rax %rax)))
    ((make-string)
     (emit-lir! '(%sar %rax 2))
     (emit-lir! '(%mov %rcx %rax))
     (emit-lir! '(%add %rax 8))
     (emit-lir! '(%bit-and %rax -8))
     (emit-lir! '(%mov %rdx %rax))
     (emit-lir! '(%shl %rdx 16))
     (emit-lir! '(%bit-or %rdx 3))
     (emit-lir! '(%shl %rdx 2))
     (emit-lir! '(%store %r12 0 %rdx))
     (emit-lir! '(%mov %rdx %r12))
     (emit-lir! '(%add %rdx 8))
     (emit-lir! '(%add %rax 8))
     (emit-lir! '(%add %r12 %rax))
     (emit-lir! '(%store-byte %rdx %rcx 0))
     (emit-lir! '(%add %rdx 3))
     (emit-lir! '(%mov %rax %rdx)))
    ((string-length)
     (let ((l-loop (unique-label-sym "strlen_loop"))
           (l-done (unique-label-sym "strlen_done")))
       (emit-lir! '(%mov %rdx %rax))
       (emit-lir! '(%sub %rdx 3))
       (emit-lir! '(%mov %rax 0))
       (emit-lir! (list '%label l-loop))
       (emit-lir! '(%load-byte-zx %rcx %rdx %rax))
       (emit-lir! '(%cmp %rcx 0))
       (emit-lir! (list '%jump-if-zero l-done))
       (emit-lir! '(%inc %rax))
       (emit-lir! (list '%jump l-loop))
       (emit-lir! (list '%label l-done))
       (emit-lir! '(%shl %rax 2))))
    ((bytevector-length)
     (emit-lir! '(%sub %rax 7))
     (emit-lir! '(%load %rax %rax 0)))
    ((make-bytevector %make-bytevector)
     (let ((l-loop (unique-label-sym "bv_zero_loop"))
           (l-done (unique-label-sym "bv_zero_done")))
       (emit-lir! '(%sar %rax 2))
       (emit-lir! '(%mov %rcx %rax))
       (emit-lir! '(%add %rax 15))
       (emit-lir! '(%bit-and %rax -8))
       (emit-lir! '(%mov %rdx %rax))
       (emit-lir! '(%shl %rdx 16))
       (emit-lir! '(%bit-or %rdx 4))
       (emit-lir! '(%shl %rdx 2))
       (emit-lir! '(%store %r12 0 %rdx))
       (emit-lir! '(%mov %rdx %rcx))
       (emit-lir! '(%shl %rdx 2))
       (emit-lir! '(%store %r12 8 %rdx))
       (emit-lir! '(%mov %r10 0))
       (emit-lir! '(%mov %rdx %rax))
       (emit-lir! (list '%label l-loop))
       (emit-lir! (list '%cmp '%rdx 8))
       (emit-lir! (list '%jump-if-zero l-done))
       (emit-lir! '(%store %r12 %rdx %r10))
       (emit-lir! '(%sub %rdx 8))
       (emit-lir! (list '%jump l-loop))
       (emit-lir! (list '%label l-done))
       (emit-lir! '(%mov %rcx %r12))
       (emit-lir! '(%add %rcx 15))
       (emit-lir! '(%add %rax 8))
       (emit-lir! '(%add %r12 %rax))
       (emit-lir! '(%mov %rax %rcx))))
    ((vector-length)
     (emit-lir! '(%sub %rax 5))
     (emit-lir! '(%load %rax %rax 0)))
    ((make-vector %make-vector)
     (let ((l-loop (unique-label-sym "vec_init_loop"))
           (l-done (unique-label-sym "vec_init_done")))
       (emit-lir! '(%sar %rax 2))
       (emit-lir! '(%mov %rcx %rax))
       (emit-lir! '(%shl %rax 3))
       (emit-lir! '(%add %rax 8))
       (emit-lir! '(%mov %rdx %rax))
       (emit-lir! '(%shl %rdx 16))
       (emit-lir! '(%bit-or %rdx 5))
       (emit-lir! '(%shl %rdx 2))
       (emit-lir! '(%store %r12 0 %rdx))
       (emit-lir! '(%mov %rdx %rcx))
       (emit-lir! '(%shl %rdx 2))
       (emit-lir! '(%store %r12 8 %rdx))
       (emit-lir! '(%mov %r10 47))
       (emit-lir! '(%mov %rdx %rax))
       (emit-lir! (list '%label l-loop))
       (emit-lir! (list '%cmp '%rdx 8))
       (emit-lir! (list '%jump-if-zero l-done))
       (emit-lir! '(%store %r12 %rdx %r10))
       (emit-lir! '(%sub %rdx 8))
       (emit-lir! (list '%jump l-loop))
       (emit-lir! (list '%label l-done))
       (emit-lir! '(%mov %rcx %r12))
       (emit-lir! '(%add %rcx 13))
       (emit-lir! '(%add %rax 8))
       (emit-lir! '(%add %r12 %rax))
       (emit-lir! '(%mov %rax %rcx))))))

(define (lir-compile-operand-for-op op e si env)
  (if (and (integer? e) (memq op '(%raw-add %raw-sub %raw-mul %raw-cmp)))
      (emit-lir! (list '%mov '%rax e))
      (lir-compile-expr e si env #f)))

(define (env-reg-var? e env)
  (and (symbol? e)
       (let ((b (assq e env)))
         (and b
              (let ((info (cdr b)))
                (cond
                  ((and (pair? info) (eq? (car info) 'reg)) (cdr info))
                  ((memq info '(%rax %rbx %rcx %rdx %rsi %rdi %rbp %rsp %r8 %r9 %r10 %r11 %r12 %r13 %r14 %r15)) info)
                  (else #f)))))))

(define (lir-compile-binop op e1 e2 si env)
  (let ((r1 (env-reg-var? e1 env))
        (r2 (env-reg-var? e2 env)))
    (cond
      ;; Fast path: op is + and e2 is a register variable
      ((and (eq? op '+) r2)
       (lir-compile-operand-for-op op e1 si env)
       (emit-lir! (list '%add '%rax r2)))
      ;; Fast path: op is + and e1 is a register variable
      ((and (eq? op '+) r1)
       (lir-compile-operand-for-op op e2 si env)
       (emit-lir! (list '%add '%rax r1)))
      ;; Fast path: op is - and e2 is a register variable
      ((and (eq? op '-) r2)
       (lir-compile-operand-for-op op e1 si env)
       (emit-lir! (list '%sub '%rax r2)))
      ;; Fast path: op is * and e2 is a register variable
      ((and (eq? op '*) r2)
       (lir-compile-operand-for-op op e1 si env)
       (emit-lir! '(%sar %rax 2))
       (emit-lir! (list '%imul '%rax r2)))
      ;; Fast path: op is = and e1 is a register variable
      ((and (eq? op '=) r1)
       (lir-compile-operand-for-op op e2 si env)
       (emit-lir! (list '%cmp r1 '%rax))
       (emit-lir! '(%set-boolean %rax "sete")))
      ;; Fast path: op is = and e2 is a register variable
      ((and (eq? op '=) r2)
       (lir-compile-operand-for-op op e1 si env)
       (emit-lir! (list '%cmp '%rax r2))
       (emit-lir! '(%set-boolean %rax "sete")))
      (else
       ;; Standard stack-based path
       (track-lir-si! si)
       (lir-compile-operand-for-op op e1 si env)
       (emit-lir! (list '%store '%rsp si '%rax))
       (track-lir-si! (- si 8))
       (lir-compile-operand-for-op op e2 (- si 8) env)
       (case op
         ((+)
          (emit-lir! (list '%add '%rax (list '%stack si))))
         ((-)
          (emit-lir! (list '%mov '%rdx (list '%stack si)))
          (emit-lir! '(%sub %rdx %rax))
          (emit-lir! '(%mov %rax %rdx)))
         ((*)
          (emit-lir! '(%sar %rax 2))
          (emit-lir! (list '%imul '%rax (list '%stack si))))
         ((%raw-add)
          (emit-lir! (list '%raw-add '%rax (list '%stack si))))
         ((%raw-sub)
          (emit-lir! (list '%mov '%rdx (list '%stack si)))
          (emit-lir! '(%raw-sub %rdx %rax))
          (emit-lir! '(%mov %rax %rdx)))
         ((%raw-mul)
          (emit-lir! (list '%raw-mul '%rax (list '%stack si))))
         ((%raw-cmp)
          (emit-lir! (list '%raw-cmp (list '%stack si) '%rax)))
         ((modulo)
          (emit-lir! '(%mov %rcx %rax))
          (emit-lir! (list '%load '%rax '%rsp si))
          (emit-lir! '(%sar %rax 2))
          (emit-lir! '(%sar %rcx 2))
          (emit-lir! '(%cqo))
          (emit-lir! '(%idiv %rcx))
          (emit-lir! '(%mov %rax %rdx))
          (emit-lir! '(%shl %rax 2)))
         ((quotient /)
          (emit-lir! '(%mov %rcx %rax))
          (emit-lir! (list '%load '%rax '%rsp si))
          (emit-lir! '(%sar %rax 2))
          (emit-lir! '(%sar %rcx 2))
          (emit-lir! '(%cqo))
          (emit-lir! '(%idiv %rcx))
          (emit-lir! '(%shl %rax 2)))
         ((string-ref)
          (emit-lir! '(%sar %rax 2))
          (emit-lir! (list '%load '%rdx '%rsp si))
          (emit-lir! '(%sub %rdx 3))
          (emit-lir! (list '%load-byte-zx '%rax '%rdx '%rax))
          (emit-lir! '(%shl %rax 8))
          (emit-lir! '(%bit-or %rax 14)))
         ((bytevector-u8-ref)
          (emit-lir! '(%sar %rax 2))
          (emit-lir! (list '%load '%rdx '%rsp si))
          (emit-lir! '(%sub %rdx 7))
          (emit-lir! '(%add %rdx 8))
          (emit-lir! (list '%load-byte-zx '%rax '%rdx '%rax))
          (emit-lir! '(%shl %rax 2)))
         ((vector-ref)
          (emit-lir! '(%sar %rax 2))
          (emit-lir! '(%shl %rax 3))
          (emit-lir! (list '%load '%rdx '%rsp si))
          (emit-lir! '(%sub %rdx 5))
          (emit-lir! '(%add %rdx 8))
          (emit-lir! (list '%load '%rax '%rdx '%rax)))
         ((=)
          (emit-lir! (list '%cmp (list '%stack si) '%rax))
          (emit-lir! '(%set-boolean %rax "sete")))
         ((<)
          (emit-lir! (list '%cmp (list '%stack si) '%rax))
          (emit-lir! '(%set-boolean %rax "setl")))
         ((<=)
          (emit-lir! (list '%cmp (list '%stack si) '%rax))
          (emit-lir! '(%set-boolean %rax "setle")))
         ((>)
          (emit-lir! (list '%cmp (list '%stack si) '%rax))
          (emit-lir! '(%set-boolean %rax "setg")))
         ((>=)
          (emit-lir! (list '%cmp (list '%stack si) '%rax))
          (emit-lir! '(%set-boolean %rax "setge")))
         ((bitwise-and)
          (emit-lir! (list '%bit-and '%rax (list '%stack si))))
         ((bitwise-ior)
          (emit-lir! (list '%bit-or '%rax (list '%stack si))))
         ((%raw-load)
          (emit-lir! '(%sar %rax 2))
          (emit-lir! (list '%load '%rdx '%rsp si))
          (emit-lir! '(%add %rdx %rax))
          (emit-lir! '(%load %rax %rdx 0)))
         ((%ptr-add %ptr-tag-add)
          (emit-lir! '(%sar %rax 2))
          (emit-lir! (list '%add '%rax (list '%stack si))))
         ((cons)
          (emit-lir! (list '%store '%rsp (- si 8) '%rax))
          (emit-lir! (list '%alloc '%rax 24 9 (- si 8)))
          (emit-lir! '(%mov %rdx 4196356))
          (emit-lir! '(%store %rax -9 %rdx))
          (emit-lir! (list '%load '%rdx '%rsp si))
          (emit-lir! '(%store %rax -1 %rdx))
          (emit-lir! (list '%load '%rdx '%rsp (- si 8)))
          (emit-lir! '(%store %rax 7 %rdx)))
         ((set-car!)
          (emit-lir! (list '%load '%rdx '%rsp si))
          (emit-lir! '(%store %rdx -1 %rax))
          (emit-lir! '(%mov %rax 63)))
         ((set-cdr!)
          (emit-lir! (list '%load '%rdx '%rsp si))
          (emit-lir! '(%store %rdx 7 %rax))
          (emit-lir! '(%mov %rax 63)))
         ((eq? eqv? char=? boolean=? symbol=?)
          (emit-lir! (list '%cmp (list '%stack si) '%rax))
          (emit-lir! '(%set-boolean %rax "sete"))))))))

(define (lir-compile-triop op e1 e2 e3 si env)
  (track-lir-si! si)
  (lir-compile-expr e1 si env #f)
  (emit-lir! (list '%store '%rsp si '%rax))
  (track-lir-si! (- si 8))
  (lir-compile-expr e2 (- si 8) env #f)
  (emit-lir! (list '%store '%rsp (- si 8) '%rax))
  (track-lir-si! (- si 16))
  (lir-compile-expr e3 (- si 16) env #f)
  (case op
    ((string-set!)
     (emit-lir! '(%shr %rax 8))
     (emit-lir! (list '%load '%rdx '%rsp si))
     (emit-lir! '(%sub %rdx 3))
     (emit-lir! (list '%load '%rcx '%rsp (- si 8)))
     (emit-lir! '(%sar %rcx 2))
     (emit-lir! '(%store-byte %rdx %rcx %al))
     (emit-lir! '(%mov %rax 63)))
    ((bytevector-u8-set!)
     (emit-lir! '(%sar %rax 2))
     (emit-lir! (list '%load '%rdx '%rsp si))
     (emit-lir! '(%sub %rdx 7))
     (emit-lir! '(%add %rdx 8))
     (emit-lir! (list '%load '%rcx '%rsp (- si 8)))
     (emit-lir! '(%sar %rcx 2))
     (emit-lir! '(%store-byte %rdx %rcx %al))
     (emit-lir! '(%mov %rax 63)))
    ((vector-set!)
     (emit-lir! '(%mov %r10 %rax))
     (emit-lir! (list '%load '%rdx '%rsp si))
     (emit-lir! '(%sub %rdx 5))
     (emit-lir! '(%add %rdx 8))
     (emit-lir! (list '%load '%rcx '%rsp (- si 8)))
     (emit-lir! '(%sar %rcx 2))
     (emit-lir! '(%shl %rcx 3))
     (emit-lir! '(%store %rdx %rcx %r10))
     (emit-lir! '(%mov %rax 63)))
    ((%raw-store!)
     (emit-lir! '(%mov %r10 %rax))
     (emit-lir! (list '%load '%rcx '%rsp (- si 8)))
     (emit-lir! '(%sar %rcx 2))
     (emit-lir! (list '%load '%rdx '%rsp si))
     (emit-lir! '(%add %rdx %rcx))
     (emit-lir! '(%store %rdx 0 %r10))
     (emit-lir! '(%mov %rax 63)))))

(define (lir-compile-raw-syscall args si env)
  (let ((num (car args))
        (a1 (car (cdr args)))
        (a2 (car (cdr (cdr args))))
        (a3 (car (cdr (cdr (cdr args)))))
        (a4 (car (cdr (cdr (cdr (cdr args))))))
        (a5 (car (cdr (cdr (cdr (cdr (cdr args)))))))
        (a6 (car (cdr (cdr (cdr (cdr (cdr (cdr args)))))))))
    (track-lir-si! si)
    (lir-compile-expr num si env #f)
    (emit-lir! (list '%store '%rsp si '%rax))
    (track-lir-si! (- si 8))
    (lir-compile-expr a1 (- si 8) env #f)
    (emit-lir! (list '%store '%rsp (- si 8) '%rax))
    (track-lir-si! (- si 16))
    (lir-compile-expr a2 (- si 16) env #f)
    (emit-lir! (list '%store '%rsp (- si 16) '%rax))
    (track-lir-si! (- si 24))
    (lir-compile-expr a3 (- si 24) env #f)
    (emit-lir! (list '%store '%rsp (- si 24) '%rax))
    (track-lir-si! (- si 32))
    (lir-compile-expr a4 (- si 32) env #f)
    (emit-lir! (list '%store '%rsp (- si 32) '%rax))
    (track-lir-si! (- si 40))
    (lir-compile-expr a5 (- si 40) env #f)
    (emit-lir! (list '%store '%rsp (- si 40) '%rax))
    (track-lir-si! (- si 48))
    (lir-compile-expr a6 (- si 48) env #f)
    (emit-lir! (list '%store '%rsp (- si 48) '%rax))
    (emit-lir! (list '%load '%rax '%rsp si))
    (emit-lir! (list '%load '%rdi '%rsp (- si 8)))
    (emit-lir! (list '%load '%rsi '%rsp (- si 16)))
    (emit-lir! (list '%load '%rdx '%rsp (- si 24)))
    (emit-lir! (list '%load '%r10 '%rsp (- si 32)))
    (emit-lir! (list '%load '%r8 '%rsp (- si 40)))
    (emit-lir! (list '%load '%r9 '%rsp (- si 48)))
    (emit-lir! '(%syscall))))
;;; =======================================================================
;;; ULisp Compiler Pass 130: Low-Level Intermediate Representation (LIR)
;;; Conforms to DSN-33 Architecture Specification & Issue #583
;;; =======================================================================
;;; Core LIR Orchestrator:
;;; - Accumulator and stack tracking state (*lir-instructions*, *lir-min-si*)
;;; - Environment and raw-variable tracking (get-raw-vars, set-raw-vars, raw-expr?)
;;; - Immediate and variable resolution (immediate?, lir-immediate, lir-compile-variable)
;;; - Expression compiler dispatcher (lir-compile-expr) orchestrating modular sub-passes:
;;;     * Pass 123: LIR Closures & Stack Allocation (passes/123_lir_closures.scm)
;;;     * Pass 124: LIR Procedure Invocations & Call ABI (passes/124_lir_call_abi.scm)
;;;     * Pass 125: LIR Continuation Transfer & Loop In-Place Shuffle (passes/125_lir_continuation.scm)
;;;     * Pass 126: LIR Control Flow & Join Path Splitting (passes/126_lir_control.scm)
;;;     * Pass 127: LIR Runtime & Advanced Features (passes/127_lir_runtime.scm)
;;;     * Pass 128: LIR Branch & Comparison Flag Fusion (passes/128_lir_branch_fusion.scm)
;;;     * Pass 129: LIR Primitive Instruction Selection (passes/129_lir_primitives.scm)
;;; - Function and Program level compilation entrypoints (lir-compile-function, generate-lir)
;;; =======================================================================

;;; Boxed accumulators for LIR instructions and stack tracking
(define *lir-instructions* (cons '() '()))
(define *lir-min-si* (cons 0 '()))
(define *stack-alloc-attr* (string->symbol ":stack-alloc"))
(define (stack-alloc-attr? attr)
  (or (eq? attr *stack-alloc-attr*)
      (eq? attr 'stack-alloc)
      (and (symbol? attr)
           (let ((s (symbol->string attr)))
             (or (string=? s ":stack-alloc")
                 (string=? s "#:stack-alloc"))))))
(define (get-raw-vars env)
  (let ((entry (assq '%raw-vars env)))
    (if entry (cdr entry) '())))

(define (set-raw-vars rvars env)
  (cons (cons '%raw-vars rvars) env))

(define (raw-expr? expr raw-env)
  (cond
    ((not (pair? expr))
     (and (symbol? expr) (memq expr raw-env)))
    ((memq (car expr) '(%raw-add %raw-sub %raw-mul %raw-cmp %raw-load %raw-syscall %to-raw %unbox-fixnum))
     #t)
    (else #f)))

(define (reset-lir!)
  (set-car! *lir-instructions* '())
  (set-car! *lir-min-si* 0))

(define (emit-lir! inst)
  (set-car! *lir-instructions* (cons inst (car *lir-instructions*))))

(define (track-lir-si! si)
  (if (< si (car *lir-min-si*))
      (set-car! *lir-min-si* si)))

(define (immediate? expr)
  (or (integer? expr)
      (boolean? expr)
      (char? expr)
      (null? expr)
      (string? expr)))

(define (lir-immediate expr)
  (cond
    ((integer? expr)
     (* expr 4))
    ((boolean? expr)
     (if expr 111 47))   ; 0x6F: #t, 0x2F: #f
    ((char? expr)
     (+ (* (char->integer expr) 256) 14))
    ((null? expr)
     63)                 ; 0x3F: '()
    ((string? expr)
     (let ((label (intern-string expr)))
       (list '%string-ref label)))))

(define (lir-compile-variable var env)
  (let ((binding (assq var env)))
    (if (not binding)
        (if (allow-extern-symbols?)
            (emit-lir! (list '%global-ref '%rax var))
            (begin
              (dump-lir-unbound-variable-diagnostic var env)
              (error (string-append "Unbound variable in LIR: " (symbol->string var)) var)))
        (let ((info (cdr binding)))
          (cond
            ((number? info)
             (emit-lir! (list '%load '%rax '%rsp info)))
            ((and (pair? info) (eq? (car info) 'reg))
             (let ((reg (cdr info)))
               (if (not (eq? reg '%rax))
                   (emit-lir! (list '%mov '%rax reg)))))
            ((and (symbol? info) (memq info '(%rax %rbx %rcx %rdx %rsi %rdi %rbp %rsp %r8 %r9 %r10 %r11 %r12 %r13 %r14 %r15)))
             (if (not (eq? info '%rax))
                 (emit-lir! (list '%mov '%rax info))))
            ((and (pair? info) (eq? (car info) 'param))
             (emit-lir! (list '%load '%rax '%rsp (cdr info))))
            ((and (pair? info) (eq? (car info) 'self))
             (emit-lir! (list '%load '%rax '%rsp (cdr info))))
            (else
             (error "Invalid binding format in LIR:" binding)))))))

(define (lir-compile-expr expr si env tail?)
  (if (pair? expr)
      (set-current-form! expr))
  (cond
    ((immediate? expr)
     (let ((val (lir-immediate expr)))
       (if (and (pair? val) (eq? (car val) '%string-ref))
           (emit-lir! (list '%str-ref '%rax (cadr val)))
           (emit-lir! (list '%mov '%rax val)))))
    ((symbol? expr)
     (lir-compile-variable expr env))
    ((pair? expr)
     (let ((op (car expr)))
       (cond
         ((zero-arg-prim? op)
          (lir-compile-zero-arg op si env))
         ((eq? op '-)
          (if (null? (cddr expr))
              (lir-compile-unary '- (cadr expr) si env)
              (lir-compile-binop '- (cadr expr) (caddr expr) si env)))
         ((unary-prim? op)
          (lir-compile-unary op (cadr expr) si env))
         ((memq op '(%make-closure %make-closure-env))
          (lir-compile-make-closure expr si env))
         ((eq? op '%make-stack-closure)
          (lir-compile-make-stack-closure expr si env))
         ((eq? op '%stack-cons)
          (lir-compile-stack-cons expr si env))
         ((eq? op 'annotate)
          (let ((attr (cadr expr))
                (inner (caddr expr)))
            (cond
              ((stack-alloc-attr? attr)
               (cond
                 ((and (pair? inner) (memq (car inner) '(%make-closure %make-closure-env)))
                  (lir-compile-make-stack-closure inner si env))
                 ((and (pair? inner) (eq? (car inner) 'cons))
                  (lir-compile-stack-cons inner si env))
                 (else
                  (lir-compile-expr inner si env tail?))))
              (else
               (lir-compile-expr inner si env tail?)))))
         ((eq? op '%closure-ref)
          (let* ((idx (caddr expr))
                 (offset (- (* idx 8) 1)))
            (lir-compile-expr (cadr expr) si env #f)
            (emit-lir! (list '%load '%rax '%rax offset))))
         ((eq? op '%closure-set!)
          (let* ((c-expr (cadr expr))
                 (idx (caddr expr))
                 (val-expr (cadddr expr))
                 (offset (- (* idx 8) 1)))
            (track-lir-si! si)
            (lir-compile-expr c-expr si env #f)
            (emit-lir! (list '%store '%rsp si '%rax))
            (track-lir-si! (- si 8))
            (lir-compile-expr val-expr (- si 8) env #f)
            (emit-lir! (list '%load '%rdx '%rsp si))
            (emit-lir! (list '%store '%rdx offset '%rax))
            (emit-lir! '(%mov %rax 63))))
         ((binop-prim? op)
          (lir-compile-binop op (cadr expr) (caddr expr) si env))
         ((triop-prim? op)
          (lir-compile-triop op (cadr expr) (caddr expr) (cadddr expr) si env))
         ((septop-prim? op)
          (lir-compile-raw-syscall (cdr expr) si env))
         ((eq? op '%cont-fun)
          (lir-compile-cont-fun (cadr expr) (caddr expr) (cadddr expr) (cadr (cdddr expr)) si env tail?))
         ((eq? op '%cont-call)
          (lir-compile-cont-call (cadr expr) (cddr expr) si env))
         ((eq? op '%with-handler)
          (lir-compile-with-handler (cadr expr) (caddr expr) si env tail?))
         ((eq? op '%raw-call/cc)
          (lir-compile-raw-call-cc (cadr expr) si env tail?))
         ((eq? op '%values)
          (lir-compile-values (cdr expr) si env))
         ((eq? op '%call-with-values)
          (lir-compile-call-with-values (cadr expr) (caddr expr) si env tail?))
         ((eq? op 'let)
          (lir-compile-let (cadr expr) (caddr expr) si env tail?))
         ((eq? op 'if)
          (lir-compile-if (cadr expr) (caddr expr) (cdddr expr) si env tail?))
         ((eq? op 'begin)
          (lir-compile-begin (cdr expr) si env tail?))
         ((eq? op 'quote)
          (let ((datum (cadr expr)))
            (cond
              ((symbol? datum)
               (let ((id (intern-symbol datum)))
                 (emit-lir! (list '%mov '%rax id))))
              ((immediate? datum)
               (let ((val (lir-immediate datum)))
                 (if (and (pair? val) (eq? (car val) '%string-ref))
                     (emit-lir! (list '%str-ref '%rax (cadr val)))
                     (emit-lir! (list '%mov '%rax val)))))
              ((pair? datum)
               (lir-compile-expr (list 'cons
                                       (list 'quote (car datum))
                                       (list 'quote (cdr datum)))
                                 si env #f))
              (else
               (error "Invalid quoted datum in LIR:" datum)))))
         ((eq? op '%direct-call)
          (lir-compile-direct-call (cadr expr) (cddr expr) si env tail?))
         ((eq? op '%global-ref)
          (emit-lir! (list '%global-ref '%rax (cadr expr))))
         ((eq? op '%global-set!)
          (track-lir-si! si)
          (lir-compile-expr (caddr expr) si env #f)
          (emit-lir! (list '%global-set! (cadr expr) '%rax)))
         (else
          ;; General procedure call
          (lir-compile-call op (cdr expr) si env tail?)))))
    (else
     (error "Invalid syntax in LIR compiler:" expr))))

;;; Compile a single lifted %function to LIR representation
(define (lir-compile-function fn)
  (let* ((label (cadr fn))
         (params (caddr fn))
         (body (cadddr fn))
         (num-params (length params))
         (initial-raw-vars (if (unboxed-fn? label) params '())))
    (set-current-toplevel-name! label)
    (with-call-frame label fn
      (lambda ()
        (reset-lir!)
        ;; Build callee env:
        ;; %self at [rsp - 8]
        ;; params at [rsp + 8 * (num-params - i)]
        (let* ((self-env (list (cons '%self (cons 'self -8))))
               (param-env
                (let loop ((ps params) (i 0) (acc '()))
                  (if (null? ps) acc
                      (let ((offset (* 8 (- num-params i))))
                        (loop (cdr ps) (+ i 1)
                              (cons (cons (car ps) (cons 'param offset)) acc))))))
               (callee-env (cons (cons '%num-params num-params)
                                 (cons (cons '%raw-vars initial-raw-vars)
                                       (cons (cons '%stack-vars '())
                                             (append self-env param-env)))))
               (callee-si -24))
          (track-lir-si! -8)
          (track-lir-si! -16)
          (track-lir-si! callee-si)
          (emit-lir! '(%store %rsp -16 %rax))
          (lir-compile-expr body callee-si callee-env #t)
          (emit-lir! '(%return))
          (let* ((needed-frame (- 0 (car *lir-min-si*)))
                 (frame-size (align-frame-shift needed-frame))
                 (insts (reverse (car *lir-instructions*))))
            (list '%lir-function
                  label
                  (list 'params params)
                  (list 'frame-size frame-size)
                  (cons 'body insts))))))))

;;; Pass 6 Entrypoint: Transforms Pass 5 %program AST into %lir-program
(define (generate-lir prog)
  (reset-safepoints!)
  (reset-symbol-table!)
  (let ((funcs (cadr prog))
        (main-expr (caddr prog)))
    (set-current-toplevel-name! '%main)
    (reset-lir!)
    (track-lir-si! -8)
    (lir-compile-expr main-expr -8 (list (cons '%raw-vars '()) (cons '%stack-vars '())) #f)
    (emit-lir! '(%return))
    (let* ((main-insts (reverse (car *lir-instructions*)))
           (main-frame (align-frame-shift (- 0 (car *lir-min-si*))))
           (lir-main (list '%lir-main
                           (list 'frame-size main-frame)
                           (cons 'body main-insts)))
           (lir-funcs (map lir-compile-function funcs))
           (safepoints (reverse (car *lir-safepoints*))))
      (list '%lir-program
            (list 'strings (car *strings*))
            (list 'stackmaps safepoints)
            (cons '%lir-functions lir-funcs)
            lir-main))))
;;; =======================================================================
;;; ULisp Compiler Pass 131: GC Safepoint & Stackmap Bitmaps
;;; =======================================================================

(define *lir-safepoints* (cons '() '()))
(define *safepoint-counter* (cons 0 '()))

(define (reset-safepoints!)
  (set-car! *lir-safepoints* '())
  (set-car! *safepoint-counter* 0))

(define (new-safepoint-label!)
  (let* ((cnt (+ (car *safepoint-counter*) 1))
         (lbl-str (string-append "__safepoint_" (number->string cnt))))
    (set-car! *safepoint-counter* cnt)
    lbl-str))

(define (record-safepoint! lbl frame-size bitmap)
  (set-car! *lir-safepoints*
            (cons (list lbl frame-size bitmap) (car *lir-safepoints*))))

(define (power-of-2 k)
  (let loop ((i 0) (acc 1))
    (if (< i k)
        (loop (+ i 1) (* acc 2))
        acc)))


(define (compute-stackmap-bitmap frame-shift aligned-si args env)
  (let* ((slot-count (quotient frame-shift 8))
         (rvars (get-raw-vars env)))
    (let loop ((k 0) (bitmap 0))
      (if (or (>= k slot-count) (>= k 60))
          bitmap
          (let* ((slot-offset (- (* k 8) frame-shift))
                 (is-ptr
                  (if (= slot-offset -8)
                      #t
                      (let ((arg-res
                             (let check-arg ((cur-args args) (i 0))
                               (if (null? cur-args)
                                   #f
                                   (let ((arg-si (- aligned-si (* i 8))))
                                     (if (= slot-offset arg-si)
                                         (cons #t (not (raw-expr? (car cur-args) rvars)))
                                         (check-arg (cdr cur-args) (+ i 1))))))))
                        (if arg-res
                            (cdr arg-res)
                            (let ((var-res
                                   (let check-var ((e env))
                                     (if (null? e)
                                         #f
                                         (let ((entry (car e)))
                                           (if (and (pair? entry)
                                                    (not (eq? (car entry) '%num-params))
                                                    (not (eq? (car entry) '%raw-vars)))
                                               (let ((v (car entry))
                                                     (info (cdr entry)))
                                                 (if (and (number? info) (= info slot-offset))
                                                     (cons #t (not (memq v rvars)))
                                                     (if (and (pair? info) (eq? (car info) 'param) (= (cdr info) slot-offset))
                                                         (cons #t (not (memq v rvars)))
                                                         (check-var (cdr e)))))
                                               (check-var (cdr e))))))))
                              (if var-res
                                  (cdr var-res)
                                  #f)))))))
            (loop (+ k 1)
                  (if is-ptr (+ bitmap (power-of-2 k)) bitmap)))))))

;;; =======================================================================
;;; ULisp Compiler Pass 132: Braun et al. (2013) SSA & Block Arguments Engine
;;; =======================================================================

;;; Conforms to DSN-33 Section 8.1 & Issue #523
;;; =======================================================================

(define (make-braun-cfg)
  (list (cons 'blocks '())            ; (label . (insts ...))
        (cons 'order '())             ; (lbl1 lbl2 ...)
        (cons 'preds '())             ; (label . (pred1 pred2 ...))
        (cons 'sealed '())            ; (lbl1 lbl2 ...)
        (cons 'params '())            ; (label . (p1 p2 ...))
        (cons 'defs '())              ; ((var . lbl) . val)
        (cons 'incomplete '())        ; (label . ((param . var) ...))
        (cons 'incoming '())          ; ((param . pred) . val)
        (cons 'replacements '())      ; (param . canonical-val)
        (cons 'terminators '())       ; (label . terminator-inst)
        (cons 'current-block #f)))

(define (braun-cfg-ref cfg key)
  (let ((entry (assq key cfg)))
    (if entry (cdr entry) '())))

(define (braun-cfg-set! cfg key val)
  (let ((entry (assq key cfg)))
    (if entry
        (set-cdr! entry val)
        (error "Unknown Braun CFG key:" key))))

(define (braun-new-block! cfg label)
  (let ((order (braun-cfg-ref cfg 'order))
        (blocks (braun-cfg-ref cfg 'blocks))
        (preds (braun-cfg-ref cfg 'preds))
        (params (braun-cfg-ref cfg 'params))
        (incomplete (braun-cfg-ref cfg 'incomplete))
        (terms (braun-cfg-ref cfg 'terminators)))
    (braun-cfg-set! cfg 'order (append order (list label)))
    (braun-cfg-set! cfg 'blocks (cons (cons label '()) blocks))
    (braun-cfg-set! cfg 'preds (cons (cons label '()) preds))
    (braun-cfg-set! cfg 'params (cons (cons label '()) params))
    (braun-cfg-set! cfg 'incomplete (cons (cons label '()) incomplete))
    (braun-cfg-set! cfg 'terminators (cons (cons label #f) terms))
    (braun-cfg-set! cfg 'current-block label)
    label))

(define (braun-add-edge! cfg from-lbl to-lbl)
  (let* ((preds (braun-cfg-ref cfg 'preds))
         (entry (assq to-lbl preds)))
    (if entry
        (if (not (memq from-lbl (cdr entry)))
            (set-cdr! entry (append (cdr entry) (list from-lbl))))
        (braun-cfg-set! cfg 'preds (cons (list to-lbl from-lbl) preds)))))

(define (braun-get-preds cfg block-lbl)
  (let ((entry (assq block-lbl (braun-cfg-ref cfg 'preds))))
    (if entry (cdr entry) '())))

(define (braun-get-params cfg block-lbl)
  (let ((entry (assq block-lbl (braun-cfg-ref cfg 'params))))
    (if entry (cdr entry) '())))

(define (braun-add-param! cfg block-lbl param)
  (let* ((params (braun-cfg-ref cfg 'params))
         (entry (assq block-lbl params)))
    (if entry
        (if (not (memq param (cdr entry)))
            (set-cdr! entry (append (cdr entry) (list param))))
        (braun-cfg-set! cfg 'params (cons (list block-lbl param) params)))))

(define (braun-write-variable! cfg var block-lbl val)
  (let* ((defs (braun-cfg-ref cfg 'defs))
         (key (cons var block-lbl))
         (entry (assoc key defs)))
    (if entry
        (set-cdr! entry val)
        (braun-cfg-set! cfg 'defs (cons (cons key val) defs)))))

(define (braun-resolve-val cfg val)
  (let* ((reps (braun-cfg-ref cfg 'replacements))
         (entry (assq val reps)))
    (if entry
        (braun-resolve-val cfg (cdr entry))
        val)))

(define (braun-set-incoming! cfg param pred val)
  (let* ((inc (braun-cfg-ref cfg 'incoming))
         (key (cons param pred))
         (entry (assoc key inc)))
    (if entry
        (set-cdr! entry val)
        (braun-cfg-set! cfg 'incoming (cons (cons key val) inc)))))

(define (braun-get-incoming cfg param pred)
  (let* ((inc (braun-cfg-ref cfg 'incoming))
         (key (cons param pred))
         (entry (assoc key inc)))
    (if entry (cdr entry) #f)))

(define (braun-try-remove-trivial! cfg block-lbl param)
  (let* ((preds (braun-get-preds cfg block-lbl)))
    (let loop ((ps preds) (same #f) (trivial? #t))
      (if (null? ps)
          (if trivial?
              (let ((replacement (if same same param)))
                (if (not (equal? replacement param))
                    (begin
                      (let ((reps (braun-cfg-ref cfg 'replacements)))
                        (braun-cfg-set! cfg 'replacements (cons (cons param replacement) reps)))
                      (let* ((params (braun-cfg-ref cfg 'params))
                             (p-entry (assq block-lbl params)))
                        (if p-entry
                            (set-cdr! p-entry (filter (lambda (p) (not (eq? p param))) (cdr p-entry)))))
                      replacement)
                    param))
              param)
          (let* ((pred (car ps))
                 (op (braun-resolve-val cfg (braun-get-incoming cfg param pred))))
            (cond
              ((or (equal? op param) (equal? op same))
               (loop (cdr ps) same trivial?))
              ((eq? same #f)
               (loop (cdr ps) op trivial?))
              (else
               (loop '() same #f))))))))

(define (braun-add-arguments! cfg block-lbl param var)
  (let ((preds (braun-get-preds cfg block-lbl)))
    (for-each
     (lambda (pred)
       (let ((val (braun-read-variable cfg var pred)))
         (braun-set-incoming! cfg param pred val)))
     preds)
    (braun-try-remove-trivial! cfg block-lbl param)))

(define (braun-read-variable-recursive cfg var block-lbl)
  (let* ((sealed (braun-cfg-ref cfg 'sealed))
         (is-sealed? (memq block-lbl sealed)))
    (if (not is-sealed?)
        ;; Incomplete CFG: block not sealed yet
        (let ((param (unique-label-sym (string-append "ba_" (symbol->string var) "_"))))
          (braun-add-param! cfg block-lbl param)
          (let* ((incomp (braun-cfg-ref cfg 'incomplete))
                 (entry (assq block-lbl incomp)))
            (if entry
                (set-cdr! entry (cons (cons param var) (cdr entry)))
                (braun-cfg-set! cfg 'incomplete (cons (list block-lbl (cons param var)) incomp))))
          (braun-write-variable! cfg var block-lbl param)
          param)
        ;; Sealed block
        (let ((preds (braun-get-preds cfg block-lbl)))
          (cond
            ((null? preds)
             var)
            ((null? (cdr preds))
             ;; Single predecessor optimization: no block argument needed!
             (let ((val (braun-read-variable cfg var (car preds))))
               (braun-write-variable! cfg var block-lbl val)
               val))
            (else
             ;; Multiple predecessors: create block argument
             (let ((param (unique-label-sym (string-append "ba_" (symbol->string var) "_"))))
               (braun-add-param! cfg block-lbl param)
               (braun-write-variable! cfg var block-lbl param)
               (let ((resolved (braun-add-arguments! cfg block-lbl param var)))
                 (braun-write-variable! cfg var block-lbl resolved)
                 resolved))))))))

(define (braun-read-variable cfg var block-lbl)
  (let* ((defs (braun-cfg-ref cfg 'defs))
         (key (cons var block-lbl))
         (entry (assoc key defs)))
    (if entry
        (braun-resolve-val cfg (cdr entry))
        (braun-read-variable-recursive cfg var block-lbl))))

(define (braun-seal-block! cfg block-lbl)
  (let ((sealed (braun-cfg-ref cfg 'sealed)))
    (if (not (memq block-lbl sealed))
        (begin
          (braun-cfg-set! cfg 'sealed (cons block-lbl sealed))
          (let* ((incomp-entry (assq block-lbl (braun-cfg-ref cfg 'incomplete)))
                 (incomps (if incomp-entry (cdr incomp-entry) '())))
            (if incomp-entry (set-cdr! incomp-entry '()))
            (for-each
             (lambda (pair)
               (let ((param (car pair))
                     (var (cdr pair)))
                 (braun-add-arguments! cfg block-lbl param var)))
             (reverse incomps)))))))

(define (braun-emit-inst! cfg block-lbl inst)
  (let* ((blocks (braun-cfg-ref cfg 'blocks))
         (entry (assq block-lbl blocks)))
    (if entry
        (set-cdr! entry (append (cdr entry) (list inst)))
        (braun-cfg-set! cfg 'blocks (cons (list block-lbl inst) blocks)))))

(define (braun-get-insts cfg block-lbl)
  (let ((entry (assq block-lbl (braun-cfg-ref cfg 'blocks))))
    (if entry (cdr entry) '())))

(define (braun-set-terminator! cfg block-lbl term)
  (let* ((terms (braun-cfg-ref cfg 'terminators))
         (entry (assq block-lbl terms)))
    (if entry
        (set-cdr! entry term)
        (braun-cfg-set! cfg 'terminators (cons (cons block-lbl term) terms)))))

(define (braun-get-terminator cfg block-lbl)
  (let ((entry (assq block-lbl (braun-cfg-ref cfg 'terminators))))
    (if entry (cdr entry) #f)))

;;; Path Splitting & Join Block Bypass for Braun SSA CFG (Chambers & Ungar 1989)
(define (braun-cfg-path-split! cfg)
  (let ((order (braun-cfg-ref cfg 'order)))
    (for-each
     (lambda (join-lbl)
       (let ((term (braun-get-terminator cfg join-lbl)))
         (if (and term (or (eq? (car term) '%jump-if) (eq? (car term) '%jump-if-false)))
             (let* ((cond-var (cadr term))
                    (then-target (if (eq? (car term) '%jump-if) (caddr term) #f))
                    (else-target (if (eq? (car term) '%jump-if) (cadddr term) (caddr term)))
                    (preds (braun-get-preds cfg join-lbl)))
               (for-each
                (lambda (pred-lbl)
                  (let* ((inc-val (braun-resolve-val cfg (braun-get-incoming cfg cond-var pred-lbl)))
                         (pred-term (braun-get-terminator cfg pred-lbl)))
                    (if (and inc-val pred-term (eq? (car pred-term) '%jump) (eq? (cadr pred-term) join-lbl))
                        ;; Check if incoming condition value is statically truthy or falsy
                        (let ((is-false? (or (eq? inc-val #f) (equal? inc-val 47))))
                          (cond
                            ((and is-false? else-target)
                             ;; Bypass join-lbl directly to else-target from pred-lbl
                             (let ((join-insts (braun-get-insts cfg join-lbl)))
                               (for-each (lambda (inst) (braun-emit-inst! cfg pred-lbl inst)) join-insts)
                               (braun-set-terminator! cfg pred-lbl (list '%jump else-target))
                               (braun-add-edge! cfg pred-lbl else-target)))
                            ((and (not is-false?) then-target)
                             ;; Bypass join-lbl directly to then-target from pred-lbl
                             (let ((join-insts (braun-get-insts cfg join-lbl)))
                               (for-each (lambda (inst) (braun-emit-inst! cfg pred-lbl inst)) join-insts)
                               (braun-set-terminator! cfg pred-lbl (list '%jump then-target))
                               (braun-add-edge! cfg pred-lbl then-target))))))))
                preds)))))
     order)
    cfg))

;;; Converts a Braun CFG into structured Block Arguments LIR
(define (braun-cfg->lir cfg)
  (let ((order (braun-cfg-ref cfg 'order)))
    (map
     (lambda (lbl)
       (let* ((params (braun-get-params cfg lbl))
              (raw-insts (braun-get-insts cfg lbl))
              ;; Resolve any variables in instructions
              (insts
               (map (lambda (inst)
                      (map (lambda (elem) (braun-resolve-val cfg elem)) inst))
                    raw-insts))
              (term (braun-get-terminator cfg lbl))
              (term-inst
               (cond
                 ((not term) '())
                 ((eq? (car term) '%jump)
                  (let* ((target (cadr term))
                         (target-params (braun-get-params cfg target))
                         (args (map (lambda (p)
                                      (braun-resolve-val cfg (braun-get-incoming cfg p lbl)))
                                    target-params)))
                    (list (list '%jump target args))))
                 ((eq? (car term) '%jump-if-false)
                  (let* ((cond-var (braun-resolve-val cfg (cadr term)))
                         (else-lbl (caddr term))
                         (else-params (braun-get-params cfg else-lbl))
                         (else-args (map (lambda (p)
                                           (braun-resolve-val cfg (braun-get-incoming cfg p lbl)))
                                         else-params)))
                    (list (list '%jump-if-false cond-var else-lbl else-args))))
                 ((eq? (car term) '%jump-if)
                  (let* ((cond-var (braun-resolve-val cfg (cadr term)))
                         (then-lbl (caddr term))
                         (else-lbl (cadddr term))
                         (then-params (braun-get-params cfg then-lbl))
                         (then-args (map (lambda (p)
                                           (braun-resolve-val cfg (braun-get-incoming cfg p lbl)))
                                         then-params))
                         (else-params (braun-get-params cfg else-lbl))
                         (else-args (map (lambda (p)
                                           (braun-resolve-val cfg (braun-get-incoming cfg p lbl)))
                                         else-params)))
                    (list (list '%jump-if cond-var then-lbl then-args else-lbl else-args))))
                 ((eq? (car term) '%return)
                  (let ((val (if (pair? (cdr term))
                                 (braun-resolve-val cfg (cadr term))
                                 '%rax)))
                    (list (list '%return val))))
                 (else (list term))))
              (block-body (append insts term-inst)))
         (cons '%block (cons lbl (cons params block-body)))))
     order)))
;;; =======================================================================
;;; ULisp Compiler Pass 133: LIR Peephole Optimization & Dead Code Elimination
;;; Conforms to DSN-33 Architecture Specification & Issue #595
;;; Implements sliding-window local simplifications and unreachable code pruning.
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

(define (lir-peephole-step-window insts)
  (let loop ((rest insts) (acc '()))
    (cond
      ((null? rest)
       (reverse acc))

      ;; -----------------------------------------------------------------
      ;; Rule 1: Redundant Self-Move Elimination
      ;; (%mov reg reg) -> ()
      ;; -----------------------------------------------------------------
      ((and (pair? (car rest))
            (let ((i (car rest)))
              (and (eq? (car i) '%mov)
                   (= (length i) 3)
                   (equal? (cadr i) (caddr i)))))
       (loop (cdr rest) acc))

      ;; -----------------------------------------------------------------
      ;; Rule 2: Round-Trip Register Move Elimination
      ;; (%mov r1 r2) followed immediately by (%mov r2 r1) -> (%mov r1 r2)
      ;; -----------------------------------------------------------------
      ((and (pair? (cdr rest))
            (pair? (car rest))
            (pair? (cadr rest))
            (let ((i1 (car rest))
                  (i2 (cadr rest)))
              (and (eq? (car i1) '%mov)
                   (eq? (car i2) '%mov)
                   (= (length i1) 3)
                   (= (length i2) 3)
                   (equal? (cadr i1) (caddr i2))
                   (equal? (caddr i1) (cadr i2))
                   (lir-peephole-reg? (cadr i1))
                   (lir-peephole-reg? (caddr i1)))))
       ;; Keep only the first mov (%mov r1 r2) and skip the second
       (loop (cddr rest) (cons (car rest) acc)))

      ;; -----------------------------------------------------------------
      ;; Rule 3: Redundant Jump to Next Immediate Label
      ;; (%jump L1) followed immediately by (%label L1) -> (%label L1)
      ;; -----------------------------------------------------------------
      ((and (pair? (cdr rest))
            (pair? (car rest))
            (pair? (cadr rest))
            (memq (caar rest) '(%jump %direct-jump))
            (eq? (caadr rest) '%label)
            (eq? (cadr (car rest)) (cadr (cadr rest))))
       ;; Drop jump, keep label
       (loop (cdr rest) acc))

      ;; -----------------------------------------------------------------
      ;; Rule 4: Identity Arithmetic Simplification
      ;; (%add reg 0) / (%raw-add reg 0) -> ()
      ;; (%sub reg 0) / (%raw-sub reg 0) -> ()
      ;; -----------------------------------------------------------------
      ((and (pair? (car rest))
            (let ((i (car rest)))
              (and (memq (car i) '(%add %raw-add %sub %raw-sub))
                   (= (length i) 3)
                   (eqv? (caddr i) 0))))
       (loop (cdr rest) acc))

      ;; -----------------------------------------------------------------
      ;; Rule 5: Identity Multiplication Simplification
      ;; (%imul reg 1) / (%raw-mul reg 1) -> ()
      ;; -----------------------------------------------------------------
      ((and (pair? (car rest))
            (let ((i (car rest)))
              (and (memq (car i) '(%imul %raw-mul))
                   (= (length i) 3)
                   (eqv? (caddr i) 1))))
       (loop (cdr rest) acc))

      ;; -----------------------------------------------------------------
      ;; Rule 6: Unreachable Code Elimination (Dead Code Elimination)
      ;; (%jump L1) / (%return) followed by non-label instructions up to next label
      ;; -----------------------------------------------------------------
      ((and (lir-unconditional-terminator? (car rest))
            (pair? (cdr rest))
            (not (lir-label-inst? (cadr rest))))
       ;; Drop instructions between unconditional terminator and next label/block
       (let skip ((tail (cdr rest)))
         (cond
           ((null? tail)
            (loop '() (cons (car rest) acc)))
           ((lir-label-inst? (car tail))
            (loop tail (cons (car rest) acc)))
           (else
            (skip (cdr tail))))))

      ;; Fallthrough: Keep instruction unchanged
      (else
       (loop (cdr rest) (cons (car rest) acc))))))

(define (optimize-peephole-fixpoint insts)
  (let loop ((cur insts) (iterations 10))
    (if (<= iterations 0)
        cur
        (let ((next (lir-peephole-step-window cur)))
          (if (equal? cur next)
              cur
              (loop next (- iterations 1)))))))

;;; -----------------------------------------------------------------------
;;; Nanopass DSL Pass: lir-peephole-optimize
;;; -----------------------------------------------------------------------

(define-pass lir-peephole-optimize : L_lir_canonical (ir) -> L_lir_canonical ()
  (entry Program)
  (Program : Program (p) -> Program ()
    ((%lir-program (strings ,se) (stackmaps ,sm) (%lir-functions ,f ...) ,m)
     (list '%lir-program
           (list 'strings se)
           (list 'stackmaps sm)
           (cons '%lir-functions (map FunctionDecl f))
           (MainDecl m))))
  (FunctionDecl : FunctionDecl (f) -> FunctionDecl ()
    ((%lir-function ,lbl (params (,x ...)) (frame-size ,frame_size) (body ,inst ...))
     (list '%lir-function
           lbl
           (list 'params x)
           (list 'frame-size frame_size)
           (cons 'body (optimize-peephole-fixpoint inst)))))
  (MainDecl : MainDecl (m) -> MainDecl ()
    ((%lir-main (frame-size ,frame_size) (body ,inst ...))
     (list '%lir-main
           (list 'frame-size frame_size)
           (cons 'body (optimize-peephole-fixpoint inst))))))
;;; =======================================================================
;;; ULisp Compiler: Backend Architecture Intermediate Languages
;;; Conforms to DSN-33 Architecture Specification & Issue #596
;;; =======================================================================
;;; Formal intermediate language definition for Target Machine Assembly (L_asm_x86)
;;; using Nanopass DSL (define-language). Serves as the declarative contract
;;; between instruction selection (LIR -> L_asm) and code emission (L_asm -> text).
;;; =======================================================================

(define-language L_asm_x86
  (entry Program)
  (terminals
    (symbol (lbl var op cc align))
    (integer (n disp imm scale bitmap frame_size bytes))
    (string (str)))
  (Register (reg)
    rax rbx rcx rdx rsi rdi rbp rsp
    r8  r9  r10 r11 r12 r13 r14 r15 al
    (%reg var))
  (Memory (mem)
    (%disp disp reg)
    (%index reg reg scale disp)
    (%mem reg disp))
  (Operand (opnd)
    reg
    mem
    (%imm imm)
    imm
    lbl)
  (Inst (inst)
    (%label lbl)
    (%p2align align)
    (%align align)
    (%raw-asm str)
    (mov opnd1 opnd2)
    (movzx opnd1 opnd2)
    (lea opnd1 opnd2)
    (add opnd1 opnd2)
    (sub opnd1 opnd2)
    (imul opnd1 opnd2)
    (and opnd1 opnd2)
    (or opnd1 opnd2)
    (xor opnd1 opnd2)
    (shl opnd1 opnd2)
    (shr opnd1 opnd2)
    (sar opnd1 opnd2)
    (neg opnd)
    (not opnd)
    (cmp opnd1 opnd2)
    (test opnd1 opnd2)
    (set cc opnd)
    (jmp lbl)
    (jcc cc lbl)
    (call opnd)
    (ret)
    (push opnd)
    (pop opnd)
    (cqo)
    (idiv opnd)
    (inc opnd)
    (syscall)
    (cld)
    (rep-movsb))
  (StringEntry (se)
    (lbl str))
  (SafepointEntry (sm)
    (lbl frame_size bitmap))
  (FunctionDecl (f)
    (%asm-function lbl (frame-size n) (body inst ...)))
  (MainDecl (m)
    (%asm-main (frame-size n) (body inst ...)))
  (Program (p)
    (%asm-program (strings (se ...)) (stackmaps (sm ...)) (%asm-functions f ...) m)))
;;; =======================================================================
;;; ULisp Compiler Pass 140: Native x86-64 Backend Code Generator
;;; Conforms to DSN-33 Architecture Specification & Issue #596
;;; Implements 2-stage backend: Instruction Selection (LIR -> L_asm_x86)
;;; and Assembly Code Emission (L_asm_x86 -> GNU x86-64 Intel Syntax).
;;; =======================================================================

(define (emit line)
  (write-string line)
  (write-char #\newline))

(define (backend-append-2 l1 l2)
  (if (null? l1)
      l2
      (cons (car l1) (backend-append-2 (cdr l1) l2))))

(define (backend-concat lists)
  (let loop ((rest lists))
    (cond
      ((null? rest) '())
      ((null? (cdr rest)) (car rest))
      (else (backend-append-2 (car rest) (loop (cdr rest)))))))

(define (reg->str reg)
  (case reg
    ((%rax rax) "rax")
    ((%rbx rbx) "rbx")
    ((%rcx rcx) "rcx")
    ((%rdx rdx) "rdx")
    ((%rsi rsi) "rsi")
    ((%rdi rdi) "rdi")
    ((%rbp rbp) "rbp")
    ((%rsp rsp) "rsp")
    ((%r8  r8)  "r8")
    ((%r9  r9)  "r9")
    ((%r10 r10) "r10")
    ((%r11 r11) "r11")
    ((%r12 r12) "r12")
    ((%r13 r13) "r13")
    ((%r14 r14) "r14")
    ((%r15 r15) "r15")
    ((%al  al)  "al")
    (else (if (symbol? reg) (symbol->string reg) reg))))

(define (mem-op->str base offset)
  (let ((base-str (reg->str base)))
    (if (symbol? offset)
        (string-append "[" base-str " + " (reg->str offset) "]")
        (string-append "[" base-str " " (offset->string offset) "]"))))

(define (operand->str opnd)
  (cond
    ((symbol? opnd)
     (reg->str opnd))
    ((integer? opnd)
     (number->string opnd))
    ((pair? opnd)
     (let ((tag (car opnd)))
       (case tag
         ((%reg)
          (reg->str (cadr opnd)))
         ((%stack)
          (string-append "[rsp " (offset->string (cadr opnd)) "]"))
         ((%disp)
          (if (symbol? (cadr opnd))
              (string-append "[" (reg->str (caddr opnd)) " + " (reg->str (cadr opnd)) "]")
              (string-append "[" (reg->str (caddr opnd)) " " (offset->string (cadr opnd)) "]")))
         ((%imm)
          (number->string (cadr opnd)))
         ((%mem)
          (mem-op->str (cadr opnd) (caddr opnd)))
         (else
          (error "Unknown operand in x86-64 backend:" opnd)))))
    (else
     (error "Invalid operand type in x86-64 backend:" opnd))))

(define (asm-opnd->str opnd)
  (operand->str opnd))

;;; Block Arguments tracking and parallel copy for SSA LIR
(define *x86-block-params* (cons '() '()))
(define *backend-gc-mode* (cons 'all '()))
(define *alloc-counter* (cons 0 '()))

(define (new-alloc-id!)
  (let ((cnt (+ (car *alloc-counter*) 1)))
    (set-car! *alloc-counter* cnt)
    cnt))

(define (reset-x86-block-params!)
  (set-car! *x86-block-params* '()))

(define (record-x86-block-params! lbl params)
  (let ((entry (assq lbl (car *x86-block-params*))))
    (if entry
        (set-cdr! entry params)
        (set-car! *x86-block-params* (cons (cons lbl params) (car *x86-block-params*))))))

(define (get-x86-block-params lbl)
  (let ((entry (assq lbl (car *x86-block-params*))))
    (if entry (cdr entry) '())))

(define (scan-x86-blocks! insts)
  (reset-x86-block-params!)
  (for-each
   (lambda (inst)
     (if (and (pair? inst) (eq? (car inst) '%block))
         (let ((lbl (cadr inst))
               (params (caddr inst)))
           (record-x86-block-params! lbl params))))
   insts))

(define (x86-param-location idx param)
  (cond
    ((memq param '(%rax %rbx %rcx %rdx %rsi %rdi %rbp %rsp %r8 %r9 %r10 %r11 %r12 %r13 %r14 %r15
                   rax rbx rcx rdx rsi rdi rbp rsp r8 r9 r10 r11 r12 r13 r14 r15))
     param)
    ((and (pair? param) (eq? (car param) '%reg))
     (cadr param))
    ((and (pair? param) (eq? (car param) '%stack)) param)
    (else
     (list '%stack (* -8 (+ idx 2))))))

(define (select-x86-parallel-copy target-lbl args)
  (let ((params (get-x86-block-params target-lbl)))
    (let loop ((ps params) (as args) (i 0) (acc '()))
      (if (and (pair? ps) (pair? as))
          (let* ((param (car ps))
                 (arg (car as))
                 (loc (x86-param-location i param)))
            (cond
              ((equal? loc arg)
               (loop (cdr ps) (cdr as) (+ i 1) acc))
              ((or (eq? loc '%rax) (eq? loc 'rax))
               (loop (cdr ps) (cdr as) (+ i 1)
                     (cons (list 'mov 'rax (lower-lir-opnd arg)) acc)))
              ((and (pair? loc) (eq? (car loc) '%stack))
               (let ((stk-disp (list '%disp (cadr loc) 'rsp)))
                 (cond
                   ((pair? arg)
                    (loop (cdr ps) (cdr as) (+ i 1)
                          (cons (list 'mov stk-disp 'r10)
                                (cons (list 'mov 'r10 (lower-lir-opnd arg)) acc))))
                   ((integer? arg)
                    (loop (cdr ps) (cdr as) (+ i 1)
                          (cons (list '%raw-asm (string-append "    mov qword ptr " (operand->str loc) ", " (number->string arg))) acc)))
                   (else
                    (loop (cdr ps) (cdr as) (+ i 1)
                          (cons (list 'mov stk-disp (lower-lir-opnd arg)) acc))))))
              (else
               (loop (cdr ps) (cdr as) (+ i 1)
                     (cons (list 'mov (lower-lir-opnd loc) (lower-lir-opnd arg)) acc)))))
          (reverse acc)))))

(define (emit-x86-parallel-copy target-lbl args)
  (for-each emit-x86-asm-inst (select-x86-parallel-copy target-lbl args)))

;;; -----------------------------------------------------------------------
;;; Stage 1: Instruction Selection (LIR -> L_asm_x86 AST)
;;; -----------------------------------------------------------------------

(define (lower-lir-reg r)
  (case r
    ((%rax) 'rax) ((%rbx) 'rbx) ((%rcx) 'rcx) ((%rdx) 'rdx)
    ((%rsi) 'rsi) ((%rdi) 'rdi) ((%rbp) 'rbp) ((%rsp) 'rsp)
    ((%r8)  'r8)  ((%r9)  'r9)  ((%r10) 'r10) ((%r11) 'r11)
    ((%r12) 'r12) ((%r13) 'r13) ((%r14) 'r14) ((%r15) 'r15)
    ((%al)  'al)
    (else r)))

(define (lower-lir-opnd opnd)
  (cond
    ((symbol? opnd)
     (lower-lir-reg opnd))
    ((integer? opnd)
     (list '%imm opnd))
    ((pair? opnd)
     (let ((tag (car opnd)))
       (case tag
         ((%reg)
          (lower-lir-reg (cadr opnd)))
         ((%stack)
          (list '%disp (cadr opnd) 'rsp))
         ((%disp)
          opnd)
         ((%imm)
          opnd)
         ((%mem)
          (list '%disp (caddr opnd) (lower-lir-reg (cadr opnd))))
         (else
          opnd))))
    (else opnd)))

(define (canonical-x86-cc cond-op)
  (cond
    ((string? cond-op) (string->symbol cond-op))
    ((eq? cond-op 'equal) 'je)
    ((eq? cond-op 'not-equal) 'jne)
    ((eq? cond-op 'less) 'jl)
    ((eq? cond-op 'less-equal) 'jle)
    ((eq? cond-op 'greater) 'jg)
    ((eq? cond-op 'greater-equal) 'jge)
    ((eq? cond-op 'zero) 'je)
    ((eq? cond-op 'not-zero) 'jne)
    ((symbol? cond-op) cond-op)
    (else 'je)))

(define (lower-lir-instruction inst)
  (let ((op (car inst)))
    (case op
      ((%label)
       (let ((lbl (cadr inst)))
         (list (list '%p2align 4)
               (list '%label lbl))))

      ((%block)
       (let ((lbl (cadr inst))
             (params (caddr inst))
             (body (cdddr inst)))
         (record-x86-block-params! lbl params)
         (let loop ((rest body) (acc (list (list '%label lbl) (list '%p2align 4))))
           (if (null? rest)
               (reverse acc)
               (let ((lowered (lower-lir-instruction (car rest))))
                 (loop (cdr rest) (append (reverse lowered) acc)))))))

      ((%jump)
       (let* ((lbl (cadr inst))
              (args (if (pair? (cddr inst)) (caddr inst) '())))
         (append (select-x86-parallel-copy lbl args)
                 (list (list 'jmp (lower-lir-opnd lbl))))))

      ((%jump-if-false)
       (let* ((reg (cadr inst))
              (lbl (caddr inst))
              (args (if (pair? (cdddr inst)) (cadddr inst) '())))
         (if (null? args)
             (list (list 'cmp (lower-lir-opnd reg) (list '%imm 47))
                   (list 'jcc 'je lbl))
             (let ((cont-lbl (unique-label-sym "L_cont_")))
               (backend-concat
                (list (list (list 'cmp (lower-lir-opnd reg) (list '%imm 47))
                            (list 'jcc 'jne cont-lbl))
                      (select-x86-parallel-copy lbl args)
                      (list (list 'jmp (lower-lir-opnd lbl))
                            (list '%label cont-lbl))))))))

      ((%jump-cond)
       (let* ((cond-op (cadr inst))
              (lbl (caddr inst)))
         (list (list 'jcc (canonical-x86-cc cond-op) lbl))))

      ((%jump-if)
       (let* ((reg (cadr inst))
              (then-lbl (caddr inst))
              (then-args (cadddr inst))
              (rest-else (cdr (cdddr inst)))
              (else-lbl (car rest-else))
              (else-args (cadr rest-else))
              (else-tramline (unique-label-sym "L_else_tramline_")))
         (backend-concat
          (list (list (list 'cmp (lower-lir-opnd reg) (list '%imm 47))
                      (list 'jcc 'je else-tramline))
                (if (pair? then-args) (select-x86-parallel-copy then-lbl then-args) '())
                (list (list 'jmp (lower-lir-opnd then-lbl))
                      (list '%label else-tramline))
                (if (pair? else-args) (select-x86-parallel-copy else-lbl else-args) '())
                (list (list 'jmp (lower-lir-opnd else-lbl)))))))

      ((%jump-if-zero)
       (let ((lbl (cadr inst)))
         (list (list 'jcc 'je lbl))))

      ((%return)
       (list (list 'ret)))

      ((%push)
       (let ((src (cadr inst)))
         (list (list 'push (lower-lir-opnd src)))))

      ((%pop)
       (let ((dst (cadr inst)))
         (list (list 'pop (lower-lir-opnd dst)))))

      ((%syscall)
       (list (list 'syscall)))

      ((%mov)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (list (list 'mov (lower-lir-opnd dst) (lower-lir-opnd src)))))

      ((%load)
       (let ((dst (cadr inst))
             (base (caddr inst))
             (offset (cadddr inst)))
         (list (list 'mov (lower-lir-opnd dst) (list '%disp offset (lower-lir-reg base))))))

      ((%store)
       (let ((base (cadr inst))
             (offset (caddr inst))
             (src (cadddr inst)))
         (if (integer? src)
             (list (list '%raw-asm (string-append "    mov qword ptr " (mem-op->str base offset) ", " (number->string src))))
             (list (list 'mov (list '%disp offset (lower-lir-reg base)) (lower-lir-opnd src))))))

      ((%store-byte)
       (let ((base (cadr inst))
             (offset (caddr inst))
             (src (cadddr inst)))
         (let ((src-str (if (number? src) (number->string src) (reg->str src))))
           (list (list '%raw-asm (string-append "    mov byte ptr " (mem-op->str base offset) ", " src-str))))))

      ((%load-byte-zx)
       (let ((dst (cadr inst))
             (base (caddr inst))
             (offset (cadddr inst)))
         (list (list '%raw-asm (string-append "    movzx " (reg->str dst) ", byte ptr " (mem-op->str base offset))))))

      ((%add %raw-add)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (list (list 'add (lower-lir-opnd dst) (lower-lir-opnd src)))))

      ((%sub %raw-sub)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (list (list 'sub (lower-lir-opnd dst) (lower-lir-opnd src)))))

      ((%neg)
       (let ((dst (cadr inst)))
         (list (list 'neg (lower-lir-opnd dst)))))

      ((%imul %raw-mul)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (list (list 'imul (lower-lir-opnd dst) (lower-lir-opnd src)))))

      ((%box-fixnum)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (if (equal? dst src)
             (list (list 'shl (lower-lir-opnd dst) 2))
             (list (list 'mov (lower-lir-opnd dst) (lower-lir-opnd src))
                   (list 'shl (lower-lir-opnd dst) 2)))))

      ((%unbox-fixnum)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (if (equal? dst src)
             (list (list 'sar (lower-lir-opnd dst) 2))
             (list (list 'mov (lower-lir-opnd dst) (lower-lir-opnd src))
                   (list 'sar (lower-lir-opnd dst) 2)))))

      ((%cqo)
       (list (list 'cqo)))

      ((%idiv)
       (let ((src (cadr inst)))
         (list (list 'idiv (lower-lir-opnd src)))))

      ((%inc)
       (let ((dst (cadr inst)))
         (list (list 'inc (lower-lir-opnd dst)))))

      ((%shl)
       (let ((dst (cadr inst))
             (count (caddr inst)))
         (list (list 'shl (lower-lir-opnd dst) count))))

      ((%shr)
       (let ((dst (cadr inst))
             (count (caddr inst)))
         (list (list 'shr (lower-lir-opnd dst) count))))

      ((%sar)
       (let ((dst (cadr inst))
             (count (caddr inst)))
         (list (list 'sar (lower-lir-opnd dst) count))))

      ((%bit-and)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (list (list 'and (lower-lir-opnd dst) (lower-lir-opnd src)))))

      ((%bit-or)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (list (list 'or (lower-lir-opnd dst) (lower-lir-opnd src)))))

      ((%bit-xor)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (list (list 'xor (lower-lir-opnd dst) (lower-lir-opnd src)))))

      ((%cmp %raw-cmp)
       (let ((s1 (cadr inst))
             (s2 (caddr inst)))
         (list (list 'cmp (lower-lir-opnd s1) (lower-lir-opnd s2)))))

      ((%set-boolean)
       (let ((cc (caddr inst)))
         (list (list '%raw-asm (string-append "    " cc " al"))
               (list '%raw-asm "    movzx eax, al")
               (list '%raw-asm "    shl rax, 6")
               (list '%raw-asm "    add rax, 0x2F"))))

      ((%alloc)
       (let* ((dst (cadr inst))
              (bytes (caddr inst))
              (tag (cadddr inst))
              (si (if (pair? (cddddr inst)) (car (cddddr inst)) -128))
              (pos-si (if (< si 0) (- 0 si) si))
              (shift (let* ((needed (+ pos-si 96))
                            (rem (modulo needed 16)))
                       (if (= rem 0) needed (+ needed (- 16 rem))))))
         (cond
           ((eq? (car *backend-gc-mode*) 'none)
            (list (list '%raw-asm (string-append "    lea " (operand->str dst) ", [r12 + " (number->string tag) "]"))
                  (list '%raw-asm (string-append "    add r12, " (number->string bytes)))
                  (list '%raw-asm "    cmp r12, [rip + ulisp_heap_limit]")
                  (list '%raw-asm "    ja ulisp_oom_panic")))
           ((eq? (car *backend-gc-mode*) 'stress)
            (list (list '%raw-asm (string-append "    sub rsp, " (number->string shift)))
                  (list '%raw-asm "    call ulisp_alloc_slow_trampoline")
                  (list '%raw-asm (string-append "    add rsp, " (number->string shift)))
                  (list '%raw-asm (string-append "    lea " (operand->str dst) ", [r12 + " (number->string tag) "]"))
                  (list '%raw-asm (string-append "    add r12, " (number->string bytes)))
                  (list '%raw-asm "    cmp r12, [rip + ulisp_heap_limit]")
                  (list '%raw-asm "    ja ulisp_oom_panic")))
           (else
            (let ((lbl-fast (string-append ".L_alloc_fast_" (number->string (new-alloc-id!))))
                  (lbl-slow (string-append ".L_alloc_slow_" (number->string (car *alloc-counter*)))))
              (list (list '%raw-asm "    cmp byte ptr [rip + ulisp_gc_stress_mode], 0")
                    (list '%raw-asm (string-append "    jne " lbl-slow))
                    (list '%raw-asm (string-append "    lea r11, [r12 + " (number->string bytes) "]"))
                    (list '%raw-asm "    cmp r11, [rip + ulisp_heap_limit]")
                    (list '%raw-asm (string-append "    jbe " lbl-fast))
                    (list '%raw-asm (string-append lbl-slow ":"))
                    (list '%raw-asm (string-append "    sub rsp, " (number->string shift)))
                    (list '%raw-asm "    call ulisp_alloc_slow_trampoline")
                    (list '%raw-asm (string-append "    add rsp, " (number->string shift)))
                    (list '%raw-asm (string-append lbl-fast ":"))
                    (list '%raw-asm (string-append "    lea " (operand->str dst) ", [r12 + " (number->string tag) "]"))
                    (list '%raw-asm (string-append "    add r12, " (number->string bytes)))
                    (list '%raw-asm "    cmp r12, [rip + ulisp_heap_limit]")
                    (list '%raw-asm "    ja ulisp_oom_panic")))))))

      ((%alloc-stack)
       (let ((dst (cadr inst))
             (offset (caddr inst))
             (tag (cadddr inst)))
         (let ((disp (+ offset tag)))
           (if (>= disp 0)
               (list (list '%raw-asm (string-append "    lea " (operand->str dst) ", [rsp + " (number->string disp) "]")))
               (list (list '%raw-asm (string-append "    lea " (operand->str dst) ", [rsp - " (number->string (- 0 disp)) "]")))))))

      ((%code-ref)
       (let ((dst (cadr inst))
             (lbl (caddr inst)))
         (let ((lbl-str (if (symbol? lbl) (symbol->string lbl) lbl)))
           (list (list '%raw-asm (string-append "    lea " (operand->str dst) ", [rip + " lbl-str "]"))))))

      ((%str-ref)
       (let ((dst (cadr inst))
             (lbl (caddr inst)))
         (let ((lbl-str (if (symbol? lbl) (symbol->string lbl) lbl)))
           (list (list '%raw-asm (string-append "    lea " (operand->str dst) ", [rip + " lbl-str "]"))
                 (list '%raw-asm (string-append "    add " (operand->str dst) ", 3"))))))

      ((%c-call)
       (let ((func (cadr inst))
             (frame-shift (caddr inst)))
         (let ((fname (if (symbol? func) (symbol->raw-name func) func)))
           (list (list '%raw-asm (string-append "    sub rsp, " (number->string frame-shift)))
                 (list '%raw-asm (string-append "    call " fname))
                 (list '%raw-asm (string-append "    add rsp, " (number->string frame-shift)))))))

      ((%call-closure)
       (let ((frame-shift (cadr inst))
             (safepoint (if (pair? (cddr inst)) (caddr inst) #f)))
         (backend-concat
          (list (if (> frame-shift 0)
                    (list (list '%raw-asm (string-append "    sub rsp, " (number->string frame-shift))))
                    '())
                (list (list '%raw-asm "    mov rdx, [r10 - 1]")
                      (list '%raw-asm "    call rdx"))
                (if safepoint
                    (list (list '%raw-asm (string-append (if (symbol? safepoint) (symbol->string safepoint) safepoint) ":")))
                    '())
                (if (> frame-shift 0)
                    (list (list '%raw-asm (string-append "    add rsp, " (number->string frame-shift))))
                    '())))))

      ((%direct-call)
       (let ((label (cadr inst))
             (frame-shift (caddr inst))
             (safepoint (if (pair? (cdddr inst)) (cadddr inst) #f)))
         (let ((lbl-str (if (symbol? label) (symbol->string label) label)))
           (backend-concat
            (list (if (> frame-shift 0)
                      (list (list '%raw-asm (string-append "    sub rsp, " (number->string frame-shift))))
                      '())
                  (list (list '%raw-asm "    xor r10, r10")
                        (list '%raw-asm (string-append "    call " lbl-str)))
                  (if safepoint
                      (list (list '%raw-asm (string-append (if (symbol? safepoint) (symbol->string safepoint) safepoint) ":")))
                      '())
                  (if (> frame-shift 0)
                      (list (list '%raw-asm (string-append "    add rsp, " (number->string frame-shift))))
                      '()))))))

      ((%direct-jump)
       (let ((label (cadr inst)))
         (list (list '%raw-asm "    xor r10, r10")
               (list '%raw-asm (string-append "    jmp " (if (symbol? label) (symbol->string label) label))))))

      ((%global-ref)
       (let ((reg (cadr inst))
             (var (caddr inst)))
         (let ((g-lbl (string-append "ulisp_gvar_" (sanitize-label-str (symbol->string var)))))
           (list (list '%raw-asm (string-append "    lea r11, [rip + " g-lbl "]"))
                 (list '%raw-asm (string-append "    mov " (reg->str reg) ", [r11]"))))))

      ((%global-set!)
       (let ((var (cadr inst))
             (reg (caddr inst)))
         (let ((g-lbl (string-append "ulisp_gvar_" (sanitize-label-str (symbol->string var)))))
           (list (list '%raw-asm (string-append "    lea r11, [rip + " g-lbl "]"))
                 (list '%raw-asm (string-append "    mov [r11], " (reg->str reg)))))))

      ((%push-handler)
       (let ((catch-lbl (cadr inst))
             (frame-si (caddr inst))
             (handler-si (cadddr inst)))
         (let ((lbl-str (if (symbol? catch-lbl) (symbol->string catch-lbl) catch-lbl)))
           (list (list '%raw-asm (string-append "    lea rax, [rip + " lbl-str "]"))
                 (list '%raw-asm (string-append "    mov [rsp " (offset->string (+ frame-si 24)) "], rax"))
                 (list '%raw-asm "    lea rdx, [rip + ulisp_handler_chain]")
                 (list '%raw-asm "    mov rcx, [rdx]")
                 (list '%raw-asm (string-append "    mov [rsp " (offset->string frame-si) "], rcx"))
                 (list '%raw-asm (string-append "    mov [rsp " (offset->string (+ frame-si 8)) "], rsp"))
                 (list '%raw-asm (string-append "    mov [rsp " (offset->string (+ frame-si 16)) "], rbp"))
                 (list '%raw-asm (string-append "    mov rax, [rsp " (offset->string handler-si) "]"))
                 (list '%raw-asm (string-append "    mov [rsp " (offset->string (+ frame-si 32)) "], rax"))
                 (list '%raw-asm (string-append "    lea rax, [rsp " (offset->string frame-si) "]"))
                 (list '%raw-asm "    mov [rdx], rax")))))

      ((%pop-handler)
       (let ((frame-si (cadr inst)))
         (list (list '%raw-asm "    lea rdx, [rip + ulisp_handler_chain]")
               (list '%raw-asm (string-append "    mov rcx, [rsp " (offset->string frame-si) "]"))
               (list '%raw-asm "    mov [rdx], rcx"))))

      ((%raise)
       (list (list '%raw-asm "    lea rdx, [rip + ulisp_handler_chain]")
             (list '%raw-asm "    mov rbx, [rdx]")
             (list '%raw-asm "    test rbx, rbx")
             (list '%raw-asm "    jz .L_unhandled_exn")
             (list '%raw-asm "    mov rcx, [rbx]")
             (list '%raw-asm "    mov [rdx], rcx")
             (list '%raw-asm "    mov rdi, rax")
             (list '%raw-asm "    mov rsp, [rbx + 8]")
             (list '%raw-asm "    mov rbp, [rbx + 16]")
             (list '%raw-asm "    mov r10, [rbx + 24]")
             (list '%raw-asm "    mov rax, [rbx + 32]")
             (list '%raw-asm "    jmp r10")))

      ((%set-values-count)
       (let ((cnt (cadr inst)))
         (list (list '%raw-asm "    lea rdx, [rip + ulisp_values_count]")
               (list '%raw-asm (string-append "    mov qword ptr [rdx], " (number->string cnt))))))

      ((%store-values-buf)
       (let ((base-si (cadr inst))
             (count (caddr inst)))
         (let loop ((i 0) (acc (list (list '%raw-asm "    lea rbx, [rip + ulisp_values_buf]"))))
           (if (< i count)
               (let ((offset (+ base-si (* -8 i)))
                     (buf-disp (* 8 i)))
                 (loop (+ i 1)
                       (cons (list '%raw-asm (string-append "    mov [rbx + " (number->string buf-disp) "], rax"))
                             (cons (list '%raw-asm (string-append "    mov rax, [rsp " (offset->string offset) "]"))
                                   acc))))
               (reverse acc)))))

      ((%dispatch-consumer)
       (let* ((consumer-si (cadr inst))
              (aligned-si (caddr inst))
              (frame-shift (cadddr inst))
              (exit-lbl (unique-label-sym "L_cwv_exit_"))
              (call-0-lbl (unique-label-sym "L_cwv_call_0_"))
              (call-1-lbl (unique-label-sym "L_cwv_call_1_"))
              (call-2-lbl (unique-label-sym "L_cwv_call_2_"))
              (call-3-lbl (unique-label-sym "L_cwv_call_3_"))
              (call-4-lbl (unique-label-sym "L_cwv_call_4_"))
              (exit-str (symbol->string exit-lbl)))
         (let ((sub-shift (if (> frame-shift 0) (list (list '%raw-asm (string-append "    sub rsp, " (number->string frame-shift)))) '()))
               (add-shift (if (> frame-shift 0) (list (list '%raw-asm (string-append "    add rsp, " (number->string frame-shift)))) '())))
           (backend-concat
            (list
             (list (list '%raw-asm "    lea rdx, [rip + ulisp_values_count]")
                  (list '%raw-asm "    mov rcx, [rdx]")
                  (list '%raw-asm "    mov qword ptr [rdx], 1")
                  (list '%raw-asm (string-append "    mov r10, [rsp " (offset->string consumer-si) "]"))
                  (list '%raw-asm "    lea rbx, [rip + ulisp_values_buf]")
                  (list '%raw-asm "    cmp rcx, 1")
                  (list '%raw-asm (string-append "    je " (symbol->string call-1-lbl)))
                  (list '%raw-asm "    cmp rcx, 2")
                  (list '%raw-asm (string-append "    je " (symbol->string call-2-lbl)))
                  (list '%raw-asm "    cmp rcx, 0")
                  (list '%raw-asm (string-append "    je " (symbol->string call-0-lbl)))
                  (list '%raw-asm "    cmp rcx, 3")
                  (list '%raw-asm (string-append "    je " (symbol->string call-3-lbl)))
                  (list '%raw-asm "    cmp rcx, 4")
                  (list '%raw-asm (string-append "    je " (symbol->string call-4-lbl)))
                  ;; 0 args
                  (list '%raw-asm (string-append (symbol->string call-0-lbl) ":")))
            sub-shift
            (list (list '%raw-asm "    mov rdx, [r10 - 1]")
                  (list '%raw-asm "    mov rax, 0")
                  (list '%raw-asm "    call rdx"))
            add-shift
            (list (list '%raw-asm (string-append "    jmp " exit-str))
                  ;; 1 arg
                  (list '%raw-asm (string-append (symbol->string call-1-lbl) ":"))
                  (list '%raw-asm (string-append "    mov [rsp " (offset->string aligned-si) "], rax")))
            sub-shift
            (list (list '%raw-asm "    mov rdx, [r10 - 1]")
                  (list '%raw-asm "    mov rax, 4")
                  (list '%raw-asm "    call rdx"))
            add-shift
            (list (list '%raw-asm (string-append "    jmp " exit-str))
                  ;; 2 args
                  (list '%raw-asm (string-append (symbol->string call-2-lbl) ":"))
                  (list '%raw-asm "    mov rax, [rbx]")
                  (list '%raw-asm (string-append "    mov [rsp " (offset->string (+ aligned-si 8)) "], rax"))
                  (list '%raw-asm "    mov rax, [rbx + 8]")
                  (list '%raw-asm (string-append "    mov [rsp " (offset->string aligned-si) "], rax")))
            sub-shift
            (list (list '%raw-asm "    mov rdx, [r10 - 1]")
                  (list '%raw-asm "    mov rax, 8")
                  (list '%raw-asm "    call rdx"))
            add-shift
            (list (list '%raw-asm (string-append "    jmp " exit-str))
                  ;; 3 args
                  (list '%raw-asm (string-append (symbol->string call-3-lbl) ":"))
                  (list '%raw-asm "    mov rax, [rbx]")
                  (list '%raw-asm (string-append "    mov [rsp " (offset->string (+ aligned-si 16)) "], rax"))
                  (list '%raw-asm "    mov rax, [rbx + 8]")
                  (list '%raw-asm (string-append "    mov [rsp " (offset->string (+ aligned-si 8)) "], rax"))
                  (list '%raw-asm "    mov rax, [rbx + 16]")
                  (list '%raw-asm (string-append "    mov [rsp " (offset->string aligned-si) "], rax")))
            sub-shift
            (list (list '%raw-asm "    mov rdx, [r10 - 1]")
                  (list '%raw-asm "    mov rax, 12")
                  (list '%raw-asm "    call rdx"))
            add-shift
            (list (list '%raw-asm (string-append "    jmp " exit-str))
                  ;; 4 args
                  (list '%raw-asm (string-append (symbol->string call-4-lbl) ":"))
                  (list '%raw-asm "    mov rax, [rbx]")
                  (list '%raw-asm (string-append "    mov [rsp " (offset->string (+ aligned-si 24)) "], rax"))
                  (list '%raw-asm "    mov rax, [rbx + 8]")
                  (list '%raw-asm (string-append "    mov [rsp " (offset->string (+ aligned-si 16)) "], rax"))
                  (list '%raw-asm "    mov rax, [rbx + 16]")
                  (list '%raw-asm (string-append "    mov [rsp " (offset->string (+ aligned-si 8)) "], rax"))
                  (list '%raw-asm "    mov rax, [rbx + 24]")
                  (list '%raw-asm (string-append "    mov [rsp " (offset->string aligned-si) "], rax")))
            sub-shift
            (list (list '%raw-asm "    mov rdx, [r10 - 1]")
                  (list '%raw-asm "    mov rax, 16")
                  (list '%raw-asm "    call rdx"))
            add-shift
            (list (list '%raw-asm (string-append "    jmp " exit-str))
                  (list '%raw-asm (string-append exit-str ":"))))))))

      ((%capture-cc)
       (let* ((ret-lbl (cadr inst))
              (k-si (caddr inst))
              (lbl-str (if (symbol? ret-lbl) (symbol->string ret-lbl) ret-lbl)))
         (list (list '%raw-asm "    lea rcx, [rip + ulisp_stack_base]")
               (list '%raw-asm "    mov rcx, [rcx]")
               (list '%raw-asm "    sub rcx, rsp")
               (list '%raw-asm "    test rcx, rcx")
               (list '%raw-asm "    jle .L_cap_fallback_size")
               (list '%raw-asm "    cmp rcx, 8388608")
               (list '%raw-asm "    jbe .L_cap_size_ok")
               (list '%raw-asm ".L_cap_fallback_size:")
               (list '%raw-asm "    mov rcx, 65536")
               (list '%raw-asm ".L_cap_size_ok:")
               (list '%raw-asm "    mov r8, rcx")
               (list '%raw-asm "    add r8, 111")
               (list '%raw-asm "    and r8, -16")
               (list '%raw-asm "    mov rax, r12")
               (list '%raw-asm "    add r12, r8")
               (list '%raw-asm "    lea r9, [rip + ulisp_continuation_invoke]")
               (list '%raw-asm "    mov [rax], r9")
               (list '%raw-asm "    mov [rax + 8], rcx")
               (list '%raw-asm "    mov [rax + 16], rsp")
               (list '%raw-asm "    mov [rax + 24], rbp")
               (list '%raw-asm "    mov [rax + 32], rbx")
               (list '%raw-asm "    mov [rax + 40], r12")
               (list '%raw-asm "    mov [rax + 48], r13")
               (list '%raw-asm "    mov [rax + 56], r14")
               (list '%raw-asm "    mov [rax + 64], r15")
               (list '%raw-asm (string-append "    lea r9, [rip + " lbl-str "]"))
               (list '%raw-asm "    mov [rax + 72], r9")
               (list '%raw-asm "    lea r9, [rip + ulisp_handler_chain]")
               (list '%raw-asm "    mov r8, [r9]")
               (list '%raw-asm "    mov [rax + 80], r8")
               (list '%raw-asm "    lea rdx, [rax + 1]")
               (list '%raw-asm (string-append "    mov [rsp " (offset->string k-si) "], rdx"))
               (list '%raw-asm "    lea rdi, [rax + 96]")
               (list '%raw-asm "    mov rsi, rsp")
               (list '%raw-asm "    cld")
               (list '%raw-asm "    rep movsb")
               (list '%raw-asm "    mov rax, rdx"))))

      (else
       (error (string-append "Unknown LIR opcode in x86-64 backend: "
                             (if (symbol? (car inst)) (symbol->string (car inst)) "?"))
              inst)))))

(define (select-instructions-function fn)
  (let* ((label (cadr fn))
         (label-str (if (symbol? label) (symbol->string label) label))
         (is-exported? (and (>= (string-length label-str) 9)
                            (string=? (substring label-str 0 9) "ulisp_fn_")))
         (frame-size-entry (assq 'frame-size (cddr fn)))
         (frame-size (if frame-size-entry (cadr frame-size-entry) 0))
         (body (cdr (assq 'body (cddr fn)))))
    (scan-x86-blocks! body)
    (let* ((init-acc (list (list 'mov (list '%disp -8 'rsp) 'r10)
                           (list '%label label)
                           (list '%p2align 4)))
           (base-acc (if is-exported?
                         (append init-acc
                                 (list (list '%raw-asm (string-append "    .type " label-str ", @function"))
                                       (list '%raw-asm (string-append "    .weak " label-str))
                                       (list '%raw-asm (string-append "    .globl " label-str))))
                         init-acc)))
      (let loop ((rest body) (acc base-acc))
        (if (null? rest)
            (list '%asm-function label (list 'frame-size frame-size) (cons 'body (reverse acc)))
            (let ((lowered (lower-lir-instruction (car rest))))
              (loop (cdr rest) (append (reverse lowered) acc))))))))

(define (select-instructions-main main-clause)
  (let* ((frame-size-entry (assq 'frame-size (cdr main-clause)))
         (frame-size (if frame-size-entry (cadr frame-size-entry) 0))
         (main-body (cdr (assq 'body (cdr main-clause)))))
    (scan-x86-blocks! main-body)
    (let loop ((rest main-body) (acc '()))
      (if (null? rest)
          (list '%asm-main
                (list 'frame-size frame-size)
                (cons 'body (append (reverse acc)
                                    (if (module-mode?)
                                        (list (list 'add 'rsp 8)
                                              (list 'ret))
                                        (list (list 'add 'rsp 8)
                                              (list 'pop 'r12)
                                              (list 'ret))))))
          (let ((inst (car rest)))
            (if (eq? (car inst) '%return)
                (loop (cdr rest) acc)
                (let ((lowered (lower-lir-instruction inst)))
                  (loop (cdr rest) (append (reverse lowered) acc)))))))))

(define (select-instructions-x86 prog)
  (let* ((strings (assq 'strings (cdr prog)))
         (stackmaps (assq 'stackmaps (cdr prog)))
         (funcs-clause (assq '%lir-functions (cdr prog)))
         (funcs (if funcs-clause (cdr funcs-clause) '()))
         (main-clause (assq '%lir-main (cdr prog))))
    (list '%asm-program
          (if strings strings '(strings ()))
          (if stackmaps stackmaps '(stackmaps ()))
          (cons '%asm-functions (map select-instructions-function funcs))
          (select-instructions-main main-clause))))

;;; -----------------------------------------------------------------------
;;; Stage 2: Code Emission (L_asm_x86 AST -> GNU x86-64 Intel Syntax)
;;; -----------------------------------------------------------------------

(define (emit-x86-asm-inst inst)
  (let ((op (car inst)))
    (case op
      ((%label)
       (let ((lbl (cadr inst)))
         (emit (string-append (if (symbol? lbl) (symbol->string lbl) lbl) ":"))))
      ((%p2align)
       (emit (string-append "    .p2align " (number->string (cadr inst)))))
      ((%align)
       (emit (string-append "    .align " (number->string (cadr inst)))))
      ((%raw-asm)
       (emit (cadr inst)))
      ((mov)
       (emit (string-append "    mov " (asm-opnd->str (cadr inst)) ", " (asm-opnd->str (caddr inst)))))
      ((movzx)
       (emit (string-append "    movzx " (asm-opnd->str (cadr inst)) ", " (asm-opnd->str (caddr inst)))))
      ((lea)
       (emit (string-append "    lea " (asm-opnd->str (cadr inst)) ", " (asm-opnd->str (caddr inst)))))
      ((add)
       (emit (string-append "    add " (asm-opnd->str (cadr inst)) ", " (asm-opnd->str (caddr inst)))))
      ((sub)
       (emit (string-append "    sub " (asm-opnd->str (cadr inst)) ", " (asm-opnd->str (caddr inst)))))
      ((imul)
       (emit (string-append "    imul " (asm-opnd->str (cadr inst)) ", " (asm-opnd->str (caddr inst)))))
      ((and)
       (emit (string-append "    and " (asm-opnd->str (cadr inst)) ", " (asm-opnd->str (caddr inst)))))
      ((or)
       (emit (string-append "    or " (asm-opnd->str (cadr inst)) ", " (asm-opnd->str (caddr inst)))))
      ((xor)
       (emit (string-append "    xor " (asm-opnd->str (cadr inst)) ", " (asm-opnd->str (caddr inst)))))
      ((shl)
       (emit (string-append "    shl " (asm-opnd->str (cadr inst)) ", " (number->string (caddr inst)))))
      ((shr)
       (emit (string-append "    shr " (asm-opnd->str (cadr inst)) ", " (number->string (caddr inst)))))
      ((sar)
       (emit (string-append "    sar " (asm-opnd->str (cadr inst)) ", " (number->string (caddr inst)))))
      ((neg)
       (emit (string-append "    neg " (asm-opnd->str (cadr inst)))))
      ((not)
       (emit (string-append "    not " (asm-opnd->str (cadr inst)))))
      ((cmp)
       (emit (string-append "    cmp " (asm-opnd->str (cadr inst)) ", " (asm-opnd->str (caddr inst)))))
      ((test)
       (emit (string-append "    test " (asm-opnd->str (cadr inst)) ", " (asm-opnd->str (caddr inst)))))
      ((set)
       (let ((cc (cadr inst))
             (dst (caddr inst)))
         (let ((cc-str (cond
                         ((string? cc) cc)
                         ((eq? cc 'e) "e")
                         ((eq? cc 'ne) "ne")
                         ((eq? cc 'l) "l")
                         ((eq? cc 'le) "le")
                         ((eq? cc 'g) "g")
                         ((eq? cc 'ge) "ge")
                         ((eq? cc 'sete) "e")
                         ((eq? cc 'setne) "ne")
                         ((eq? cc 'setl) "l")
                         ((eq? cc 'setle) "le")
                         ((eq? cc 'setg) "g")
                         ((eq? cc 'setge) "ge")
                         ((symbol? cc)
                          (let ((s (symbol->raw-name cc)))
                            (if (string=? s "?") "e" s)))
                         (else "e"))))
           (emit (string-append "    set" cc-str " " (asm-opnd->str dst))))))
      ((jmp)
       (emit (string-append "    jmp " (asm-opnd->str (cadr inst)))))
      ((jcc)
       (let ((cc (cadr inst))
             (lbl (caddr inst)))
         (let ((cc-str (cond
                         ((string? cc) cc)
                         ((eq? cc 'je) "je")
                         ((eq? cc 'jne) "jne")
                         ((eq? cc 'jl) "jl")
                         ((eq? cc 'jle) "jle")
                         ((eq? cc 'jg) "jg")
                         ((eq? cc 'jge) "jge")
                         ((symbol? cc)
                          (let ((s (symbol->raw-name cc)))
                            (if (string=? s "?") "je" s)))
                         (else "je"))))
           (emit (string-append "    " cc-str " " (asm-opnd->str lbl))))))
      ((call)
       (emit (string-append "    call " (asm-opnd->str (cadr inst)))))
      ((ret)
       (emit "    ret"))
      ((push)
       (emit (string-append "    push " (asm-opnd->str (cadr inst)))))
      ((pop)
       (emit (string-append "    pop " (asm-opnd->str (cadr inst)))))
      ((cqo)
       (emit "    cqo"))
      ((idiv)
       (emit (string-append "    idiv " (asm-opnd->str (cadr inst)))))
      ((inc)
       (emit (string-append "    inc " (asm-opnd->str (cadr inst)))))
      ((syscall)
       (emit "    syscall"))
      ((cld)
       (emit "    cld"))
      ((rep-movsb)
       (emit "    rep movsb"))
      (else
       (error "Unknown x86 assembly instruction:" inst)))))

(define (emit-lir-instruction inst)
  (for-each emit-x86-asm-inst (lower-lir-instruction inst)))

(define (emit-x86-function fn)
  (let* ((label (cadr fn))
         (label-str (if (symbol? label) (symbol->string label) label))
         (body (cdr (assq 'body (cddr fn)))))
    (scan-x86-blocks! body)
    (emit "    .p2align 4")
    (emit (string-append label-str ":"))
    (emit "    mov [rsp - 8], r10")
    (for-each emit-lir-instruction body)))

(define (emit-x86-asm-function fn)
  (let* ((body-entry (assq 'body (cddr fn)))
         (body (if body-entry (cdr body-entry) '())))
    (for-each emit-x86-asm-inst body)))

(define (emit-x86-asm-program asm-prog gc-mode)
  (let* ((funcs-clause (assq '%asm-functions (cdr asm-prog)))
         (funcs (if funcs-clause (cdr funcs-clause) '()))
         (main-clause (assq '%asm-main (cdr asm-prog)))
         (main-body (cdr (assq 'body (cdr main-clause)))))
    (emit "    .intel_syntax noprefix")
    (emit "    .text")
    (if (not (module-mode?))
        (begin
          (emit "    .globl _start")
          (emit "    .weak _start")
          (emit "    .type _start, @function")
          (emit "    .p2align 4")
          (emit "_start:")
    (emit "    mov r14, [rsp]")                ; argc
    (emit "    cmp r14, 1")
    (emit "    jle .L_start_no_args")
    (emit "    mov rdi, [rsp + 16]")           ; argv[1]
    (emit "    xor rsi, rsi")                  ; O_RDONLY = 0
    (emit "    xor rdx, rdx")
    (emit "    mov rax, 2")                    ; sys_open
    (emit "    syscall")
    (emit "    test rax, rax")
    (emit "    js .L_start_no_args")
    (emit "    mov rdi, rax")
    (emit "    xor rsi, rsi")                  ; stdin (0)
    (emit "    mov rax, 33")                   ; sys_dup2
    (emit "    syscall")
    (emit ".L_start_no_args:")
    (emit "    mov rbp, rsp")
    (emit "    and rsp, -16")
    ;; Scan env var ULISP_QUIET
    (emit "    mov rcx, [rbp]")                 ; argc
    (emit "    lea rdx, [rbp + 16]")            ; &argv[0]
    (emit "    lea rdx, [rdx + rcx*8]")         ; past argv NULL -> envp
    (emit ".L_quiet_scan_loop:")
    (emit "    mov rsi, [rdx]")
    (emit "    test rsi, rsi")
    (emit "    jz .L_quiet_scan_done")
    (emit "    add rdx, 8")
    ;; Check prefix "ULISP_QUIET=" (12 chars: 8 bytes + 4 bytes)
    (emit "    mov rax, [rsi]")
    (emit "    mov r8, [rip + .L_str_env_quiet]")
    (emit "    cmp rax, r8")
    (emit "    jne .L_quiet_scan_loop")
    (emit "    mov eax, [rsi + 8]")
    (emit "    mov r8d, [rip + .L_str_env_quiet + 8]")
    (emit "    cmp eax, r8d")
    (emit "    jne .L_quiet_scan_loop")
    ;; Matched "ULISP_QUIET="
    (emit "    cmp byte ptr [rsi + 12], 0")
    (emit "    je .L_quiet_scan_loop")
    (emit "    cmp byte ptr [rsi + 12], '0'")
    (emit "    je .L_quiet_scan_loop")
    (emit "    lea rax, [rip + ulisp_quiet_mode]")
    (emit "    mov byte ptr [rax], 1")
    (emit ".L_quiet_scan_done:")
    (cond
      ((eq? gc-mode 'none)
       (emit "    mov rax, 9")                     ; sys_mmap
       (emit "    xor rdi, rdi")                   ; addr = NULL
       (emit "    mov rsi, 12884901888")           ; 12GB heap (0x300000000)
       (emit "    mov rdx, 3")                     ; PROT_READ|PROT_WRITE
       (emit "    mov r10, 34")                    ; MAP_PRIVATE|MAP_ANONYMOUS
       (emit "    mov r8, -1")                     ; fd = -1
       (emit "    xor r9, r9")                     ; offset = 0
       (emit "    syscall")
       (emit "    test rax, rax")
       (emit "    js .L_start_exit")
       (emit "    mov rdi, rax")                   ; rdi = heap_base
       (emit "    mov rcx, rax")
       (emit "    mov rdx, 12884901888")
       (emit "    add rcx, rdx")
       (emit "    lea rdx, [rip + ulisp_heap_limit]")
       (emit "    mov [rdx], rcx"))
      ((or (eq? gc-mode 'dual-space) (eq? gc-mode 'stress))
       (emit "    mov rax, 9")                     ; sys_mmap
       (emit "    xor rdi, rdi")                   ; addr = NULL
       (emit "    mov rsi, 134217728")             ; 128MB (2 x 64MB)
       (emit "    mov rdx, 3")                     ; PROT_READ|PROT_WRITE
       (emit "    mov r10, 34")                    ; MAP_PRIVATE|MAP_ANONYMOUS
       (emit "    mov r8, -1")                     ; fd = -1
       (emit "    xor r9, r9")                     ; offset = 0
       (emit "    syscall")
       (emit "    test rax, rax")
       (emit "    js .L_start_exit")
       (emit "    lea rbx, [rip + ulisp_gc_state]")
       (emit "    mov [rbx + 0], rax")             ; from
       (emit "    mov rdi, rax")                   ; rdi = from
       (emit "    lea rcx, [rax + 67108864]")
       (emit "    mov [rbx + 8], rcx")             ; to
       (emit "    mov qword ptr [rbx + 16], 67108864") ; size = 64MB
       (emit "    mov [rbx + 24], rbp")            ; bottom
       (emit "    mov qword ptr [rbx + 32], 0")    ; count = 0
       (emit "    mov [rbx + 40], rcx")            ; free_ptr = to
       (emit "    mov qword ptr [rbx + 88], 0")    ; gen_mode = 0 (0: dual-space, 1: generational)
       (emit "    mov qword ptr [rbx + 112], 4")   ; profile_id = 4 (stress)
       (emit "    mov qword ptr [rbx + 128], 1")   ; stress_mode = 1
       (emit "    lea rdx, [rip + ulisp_heap_limit]")
       (emit "    mov [rdx], rcx"))
      (else
       ;; Generational Collector initialization (Pass 141)
       (emit "    mov rax, 9")                     ; sys_mmap
       (emit "    xor rdi, rdi")                   ; addr = NULL
       (emit "    mov rsi, 2147483648")            ; 2GB total address space reservation
       (emit "    mov rdx, 3")                     ; PROT_READ|PROT_WRITE
       (emit "    mov r10, 34")                    ; MAP_PRIVATE|MAP_ANONYMOUS
       (emit "    mov r8, -1")                     ; fd = -1
       (emit "    xor r9, r9")                     ; offset = 0
       (emit "    syscall")
       (emit "    test rax, rax")
       (emit "    js .L_start_exit")
       (emit "    lea rbx, [rip + ulisp_gc_state]")
       (emit "    mov [rbx + 0], rax")             ; save mmap base address before env scan
       ;; Scan env var ULISP_GC_PROFILE (Pass 141 Profile Detection)
       (emit "    mov rcx, [rbp]")                 ; argc
       (emit "    lea rdx, [rbp + 16]")            ; &argv[0]
       (emit "    lea rdx, [rdx + rcx*8]")         ; past argv NULL -> envp
       (emit "    xor r10, r10")                   ; r10 = profile_id (0: standard, 1: compiler, 2: server, 4: stress)
       (emit ".L_env_scan_loop:")
       (emit "    mov rsi, [rdx]")
       (emit "    test rsi, rsi")
       (emit "    jz .L_env_scan_done")
       (emit "    add rdx, 8")
       ;; Check prefix "ULISP_GC_PROFILE=" (17 chars)
       (emit "    mov rax, [rsi]")
       (emit "    mov r8, 0x435f5053494c55")       ; "ULISP_C" (reversed little-endian prefix)
       (emit "    mov r8, [rip + .L_str_env_prefix]")
       (emit "    cmp rax, r8")
       (emit "    jne .L_env_scan_loop")
       (emit "    mov rax, [rsi + 8]")
       (emit "    mov r8, [rip + .L_str_env_prefix + 8]")
       (emit "    cmp rax, r8")
       (emit "    jne .L_env_scan_loop")
       (emit "    mov al, [rsi + 16]")
       (emit "    cmp al, 61")                     ; '='
       (emit "    jne .L_env_scan_loop")
       ;; Match profile value
       (emit "    mov al, [rsi + 17]")
       (emit "    cmp al, 'c'")                    ; compiler
       (emit "    je .L_env_set_compiler")
       (emit "    cmp al, 'C'")
       (emit "    je .L_env_set_compiler")
       (emit "    cmp al, 's'")                    ; server
       (emit "    je .L_env_set_server")
       (emit "    cmp al, 'S'")
       (emit "    je .L_env_set_server")
       (emit "    cmp al, 'd'")                    ; default / standard
       (emit "    je .L_env_set_standard")
       (emit "    cmp al, 'D'")
       (emit "    je .L_env_set_standard")
       (emit "    jmp .L_env_scan_loop")
       (emit ".L_env_set_compiler:")
       (emit "    mov r10, 1")
       (emit "    jmp .L_env_scan_done")
       (emit ".L_env_set_server:")
       (emit "    mov r10, 2")
       (emit "    jmp .L_env_scan_done")
       (emit ".L_env_set_standard:")
       (emit "    mov r10, 0")
       (emit "    jmp .L_env_scan_done")
       (emit ".L_env_scan_done:")
       (cond
         ((eq? gc-mode 'compiler)
          (emit "    test r10, r10")
          (emit "    jnz .L_profile_decided")
          (emit "    mov r10, 1")                  ; compile-time default: compiler
          (emit ".L_profile_decided:"))
         ((eq? gc-mode 'server)
          (emit "    test r10, r10")
          (emit "    jnz .L_profile_decided")
          (emit "    mov r10, 2")                  ; compile-time default: server
          (emit ".L_profile_decided:"))
         (else
          (emit ".L_profile_decided:")))
       (emit "    cmp r10, 4")
       (emit "    je .L_profile_stress")
       (emit "    cmp r10, 1")
       (emit "    je .L_profile_compiler")
       (emit "    cmp r10, 2")
       (emit "    je .L_profile_server")
       ;; Standard Profile (4MB Nursery, 64MB Mature, 1GB Max)
       (emit "    mov r12, 4194304")               ; nursery_size = 4MB
       (emit "    mov r13, 67108864")              ; mature_size = 64MB
       (emit "    mov rsi, 138444800")             ; total_mmap = ~132MB
       (emit "    mov r8, 1073741824")             ; max_mature = 1GB
       (emit "    xor r10, r10")                   ; profile_id = 0
       (emit "    jmp .L_profile_setup")
       ;; Stress Profile (Dual-Space Semi-Space 64MB + 64MB = 128MB)
       (emit ".L_profile_stress:")
       (emit "    mov r12, 67108864")              ; size = 64MB
       (emit "    mov rsi, 134217728")             ; total = 128MB
       (emit "    jmp .L_gc_state_stress_setup")
       ;; Compiler Profile (256MB Nursery, 256MB Mature, 4GB Max)
       (emit ".L_profile_compiler:")
       (emit "    mov r12, 268435456")             ; nursery_size = 256MB
       (emit "    mov r13, 268435456")             ; mature_size = 256MB
       (emit "    mov rsi, 805371904")             ; total_mmap = ~805MB
       (emit "    mov r8, 4294967296")             ; max_mature = 4GB
       (emit "    mov r10, 1")                     ; profile_id = 1
       (emit "    jmp .L_profile_setup")
       ;; Server Profile (16MB Nursery, 256MB Mature, 4GB Max)
       (emit ".L_profile_server:")
       (emit "    mov r12, 16777216")              ; nursery_size = 16MB
       (emit "    mov r13, 268435456")             ; mature_size = 256MB
       (emit "    mov rsi, 553713664")             ; total_mmap = ~553MB
       (emit "    mov r8, 4294967296")             ; max_mature = 4GB
       (emit "    mov r10, 2")                     ; profile_id = 2
       (emit ".L_profile_setup:")
       (emit "    mov rax, [rbx + 0]")             ; restore mmap base address
       (emit "    mov [rbx + 8], r12")             ; nursery_size
       (emit "    lea rdx, [rax + r12]")
       (emit "    mov [rbx + 16], rdx")            ; mature_base
       (emit "    lea rcx, [rdx + r13]")
       (emit "    mov [rbx + 24], rcx")            ; mature_to
       (emit "    mov [rbx + 32], r13")            ; mature_size
       (emit "    mov [rbx + 40], rdx")            ; mature_free = mature_from
       (emit "    mov [rbx + 48], rbp")            ; stack_bottom
       (emit "    mov qword ptr [rbx + 56], 0")    ; minor_count = 0
       (emit "    mov qword ptr [rbx + 64], 0")    ; major_count = 0
       (emit "    lea r9, [rcx + r13]")
       (emit "    mov [rbx + 72], r9")             ; remset_ptr
       (emit "    mov qword ptr [rbx + 80], 0")    ; remset_count = 0
       (emit "    mov qword ptr [rbx + 88], 1")    ; gen_mode = 1
       (emit "    mov [rbx + 96], r8")             ; max_size
       (emit "    mov qword ptr [rbx + 104], 0")   ; growth_count = 0
       (emit "    mov [rbx + 112], r10")           ; profile_id (0: standard, 1: compiler, 2: server)
       (emit "    mov rdi, rax")                   ; rdi = nursery_base
       (emit "    lea rcx, [rax + r12]")
       (emit "    lea rdx, [rip + ulisp_heap_limit]")
       (emit "    mov [rdx], rcx")                 ; limit = nursery_base + nursery_size
       (emit "    jmp .L_gc_state_setup_done")
       (emit ".L_gc_state_stress_setup:")
       (emit "    mov rax, [rbx + 0]")             ; restore mmap base address
       (emit "    mov rdi, rax")                   ; rdi = from
       (emit "    lea rcx, [rax + 67108864]")
       (emit "    mov [rbx + 8], rcx")             ; to
       (emit "    mov qword ptr [rbx + 16], 67108864") ; size = 64MB
       (emit "    mov [rbx + 24], rbp")            ; bottom
       (emit "    mov qword ptr [rbx + 32], 0")    ; count = 0
       (emit "    mov [rbx + 40], rcx")            ; free_ptr = to
       (emit "    mov qword ptr [rbx + 88], 0")    ; gen_mode = 0
       (emit "    mov qword ptr [rbx + 112], 4")   ; profile_id = 4
       (emit "    mov qword ptr [rbx + 128], 1")   ; stress_mode = 1
       (emit "    lea rdx, [rip + ulisp_heap_limit]")
       (emit "    mov [rdx], rcx")                 ; limit = from + 64MB
       (emit ".L_gc_state_setup_done:")))
    (emit "    call scheme_entry")
    (emit "    mov r15, rax")
    (emit "    cmp r14, 1")
    (emit "    jg .L_start_exit")
    (emit "    lea rax, [rip + ulisp_quiet_mode]")
    (emit "    cmp byte ptr [rax], 0")
    (emit "    jne .L_start_exit")
    (emit "    mov rdi, r15")
    (emit "    call ulisp_print_value")
    (emit "    mov dil, 10")
    (emit "    call ulisp_emit_byte")
    (emit ".L_start_exit:")
    (emit "    call ulisp_flush")
    (emit "    xor rdi, rdi")
    (emit "    mov rax, 60")
    (emit "    syscall")
    (emit "")))
    (if (module-mode?)
        (let ((init-lbl (if (current-module-id)
                            (mangle-mod-init-label (current-module-id))
                            "ulisp_stdlib_init")))
          (emit (string-append "    .globl " init-lbl))
          (emit (string-append "    .type " init-lbl ", @function"))
          (emit "    .p2align 4")
          (emit (string-append init-lbl ":"))
          (if (current-module-id)
              (begin
                (emit "    .section .init_array, \"aw\"")
                (emit "    .p2align 3")
                (emit (string-append "    .quad " init-lbl))
                (emit "    .text"))))
        (begin
          (emit "    .globl scheme_entry")
          (emit "    .type scheme_entry, @function")
          (emit "    .p2align 4")
          (emit "scheme_entry:")))
    (if (module-mode?)
        (begin
          (emit "    sub rsp, 8")
          (emit "    lea rax, [rip + ulisp_stack_base]")
          (emit "    mov rcx, [rax]")
          (emit "    test rcx, rcx")
          (emit "    jnz .L_stack_base_init_done")
          (emit "    mov [rax], rsp")
          (emit ".L_stack_base_init_done:"))
        (begin
          (emit "    push r12")
          (emit "    sub rsp, 8")
          (emit "    lea rax, [rip + ulisp_stack_base]")
          (emit "    mov rcx, [rax]")
          (emit "    test rcx, rcx")
          (emit "    jnz .L_stack_base_init_done")
          (emit "    mov [rax], rsp")
          (emit ".L_stack_base_init_done:")
          (emit "    mov r12, rdi")))
    (if (not (module-mode?))
        (begin
          (emit "    .weak ulisp_stdlib_init")
          (emit "    lea rax, [rip + ulisp_stdlib_init]")
          (emit "    test rax, rax")
          (emit "    jz .L_skip_stdlib_init")
          (emit "    call ulisp_stdlib_init")
          (emit ".L_skip_stdlib_init:")
          (emit "    .weak __init_array_start")
          (emit "    .weak __init_array_end")
          (emit "    lea rbx, [rip + __init_array_start]")
          (emit "    lea r13, [rip + __init_array_end]")
          (emit "    cmp rbx, r13")
          (emit "    jae .L_init_array_done")
          (emit ".L_init_array_loop:")
          (emit "    mov rax, [rbx]")
          (emit "    test rax, rax")
          (emit "    jz .L_skip_init_entry")
          (emit "    push rbx")
          (emit "    push r13")
          (emit "    call rax")
          (emit "    pop r13")
          (emit "    pop rbx")
          (emit ".L_skip_init_entry:")
          (emit "    add rbx, 8")
          (emit "    cmp rbx, r13")
          (emit "    jb .L_init_array_loop")
          (emit ".L_init_array_done:")))
    ;; Emit main body instructions
    (for-each emit-x86-asm-inst main-body)
    ;; Emit all lifted procedure definitions in sequence
    (for-each emit-x86-asm-function funcs)
    ;; Emit freestanding zero-libc runtime routines
    (emit-freestanding-runtime)
    (emit-oom-panic)
    ;; Emit GC routines unless disabled
    (cond
      ((eq? gc-mode 'none) #f)
      (else
       (emit-gc-collector)))
    ;; Emit stackmap metadata table in .rodata section
    (let* ((stackmaps-clause (assq 'stackmaps (cdr asm-prog)))
           (safepoints (if stackmaps-clause (cadr stackmaps-clause) '())))
      (emit "    .section .rodata")
      (emit "    .p2align 3")
      (emit "    .globl __ulisp_stackmap_table")
      (emit "    .weak __ulisp_stackmap_table")
      (emit "__ulisp_stackmap_table:")
      (emit (string-append "    .quad " (number->string (length safepoints))))
      (for-each (lambda (sp)
                  (let ((lbl (car sp))
                        (frame-size (cadr sp))
                        (bitmap (caddr sp)))
                    (emit (string-append "    .quad " (if (symbol? lbl) (symbol->string lbl) lbl)))
                    (emit (string-append "    .quad " (number->string frame-size)))
                    (emit (string-append "    .quad " (number->string bitmap)))))
                safepoints))
    ;; Emit globals metadata table in ulisp_globals_sec section (automatically concatenated by linker across split modules)
    (let ((gvs (car *top-level-vars*)))
      (emit "    .section ulisp_globals_sec, \"a\"")
      (emit "    .p2align 3")
      (for-each (lambda (v)
                  (let ((g-lbl (string-append "ulisp_gvar_" (sanitize-label-str (symbol->string v)))))
                    (emit (string-append "    .quad " g-lbl))))
                gvs))
    ;; Emit symbols metadata table in .rodata section
    (let ((syms (get-all-symbols)))
      (emit "    .section .rodata")
      (emit "    .align 8")
      (emit "    .globl __ulisp_symbol_table")
      (emit "    .weak __ulisp_symbol_table")
      (emit "__ulisp_symbol_table:")
      (emit (string-append "    .quad " (number->string (length syms))))
      (let loop ((ss syms) (idx 0))
        (if (not (null? ss))
            (let* ((entry (car ss))
                   (id (cadr entry))
                   (sym-lbl (string-append ".L_sym_name_" (number->string idx))))
              (emit (string-append "    .quad " (number->string id)))
              (emit (string-append "    .quad " sym-lbl))
              (loop (cdr ss) (+ idx 1)))))
      (let loop ((ss syms) (idx 0))
        (if (not (null? ss))
            (let* ((entry (car ss))
                   (str (caddr entry))
                   (sym-lbl (string-append ".L_sym_name_" (number->string idx))))
              (emit "    .p2align 3")
              (emit (string-append sym-lbl ":"))
              (emit (string-append "    .asciz \"" (escape-gas-string str) "\""))
              (loop (cdr ss) (+ idx 1))))))
    (emit "    .section .rodata")
    (emit "    .align 8")
    (emit ".L_str_env_prefix:")
    (emit "    .ascii \"ULISP_GC_PROFILE=\"")
    (emit "    .align 8")
    (emit ".L_str_env_quiet:")
    (emit "    .ascii \"ULISP_QUIET=\"")
    (emit "    .section .data")
    (if (not (null? (car *strings*)))
        (let loop ((ss (reverse (car *strings*))))
          (if (not (null? ss))
              (let ((entry (car ss)))
                (emit "    .p2align 3")
                (emit (string-append (car entry) ":"))
                (emit (string-append "    .asciz \"" (escape-gas-string (cdr entry)) "\""))
                (loop (cdr ss))))))
    (emit "    .bss")
    (emit "    .align 8")
    (emit "    .globl ulisp_heap_limit")
    (emit "    .weak ulisp_heap_limit")
    (emit "ulisp_heap_limit:")
    (emit "    .quad 0")
    (emit "    .align 8")
    (emit "    .globl ulisp_stack_base")
    (emit "    .weak ulisp_stack_base")
    (emit "ulisp_stack_base:")
    (emit "    .quad 0")
    (emit "    .align 8")
    (emit "    .globl ulisp_handler_chain")
    (emit "    .weak ulisp_handler_chain")
    (emit "ulisp_handler_chain:")
    (emit "    .quad 0")
    (emit "    .align 8")
    (emit "    .globl ulisp_values_count")
    (emit "    .weak ulisp_values_count")
    (emit "ulisp_values_count:")
    (emit "    .quad 0")
    (emit "    .align 8")
    (emit "    .globl ulisp_values_buf")
    (emit "    .weak ulisp_values_buf")
    (emit "ulisp_values_buf:")
    (emit "    .zero 512")
    (let loop ((gvs (car *top-level-vars*)))
      (if (pair? gvs)
          (let ((v (car gvs)))
            (let ((g-lbl (string-append "ulisp_gvar_" (sanitize-label-str (symbol->string v)))))
              (emit "    .align 8")
              (emit (string-append "    .globl " g-lbl))
              (emit (string-append "    .weak " g-lbl))
              (emit (string-append g-lbl ":"))
              (emit "    .quad 0")
              (loop (cdr gvs))))))
    (emit "    .data")
    (let loop ((gfs (car *top-level-fns*)))
      (if (pair? gfs)
          (let* ((entry (car gfs))
                 (fn-name (car entry))
                 (fn-lbl (cdr entry))
                 (fn-lbl-str (if (symbol? fn-lbl) (symbol->string fn-lbl) fn-lbl))
                 (g-lbl (string-append "ulisp_gvar_" (sanitize-label-str (symbol->string fn-name))))
                 (sc-lbl (string-append ".L_static_closure_" (sanitize-label-str (symbol->string fn-name)))))
            (emit "    .align 16")
            (emit (string-append sc-lbl ":"))
            (emit "    .quad 4195336")
            (emit (string-append "    .quad " fn-lbl-str))
            (emit "    .quad 0")
            (emit "    .align 8")
            (emit (string-append "    .globl " g-lbl))
            (emit (string-append "    .weak " g-lbl))
            (emit (string-append g-lbl ":"))
            (emit (string-append "    .quad " sc-lbl " + 9"))
            (loop (cdr gfs)))))
    (emit "    .align 8")
    (emit "    .globl ulisp_quiet_mode")
    (emit "    .weak ulisp_quiet_mode")
    (emit "    .type ulisp_quiet_mode, @object")
    (emit "ulisp_quiet_mode:")
    (emit "    .byte 0")
    (emit "    .align 8")
    (emit "    .globl ulisp_gc_stress_mode")
    (emit "    .weak ulisp_gc_stress_mode")
    (emit "    .type ulisp_gc_stress_mode, @object")
    (emit "ulisp_gc_stress_mode:")
    (emit "    .byte 0")
    (emit "    .align 8")
    (emit "    .globl ulisp_gc_state")
    (emit "    .weak ulisp_gc_state")
    (emit "ulisp_gc_state:")
    (emit "    .space 256")
    (emit "    .globl ulisp_peek_buf")
    (emit "    .weak ulisp_peek_buf")
    (emit "ulisp_peek_buf:")
    (emit "    .byte 0")
    (emit "    .globl ulisp_has_peek")
    (emit "    .weak ulisp_has_peek")
    (emit "ulisp_has_peek:")
    (emit "    .byte 0")
    (emit "    .align 8")
    (emit "    .globl ulisp_out_buf_len")
    (emit "    .weak ulisp_out_buf_len")
    (emit "ulisp_out_buf_len:")
    (emit "    .quad 0")
    (emit "    .globl ulisp_out_buf")
    (emit "    .weak ulisp_out_buf")
    (emit "ulisp_out_buf:")
    (emit "    .space 4096")
    (emit "    .globl ulisp_io_buf")
    (emit "    .weak ulisp_io_buf")
    (emit "ulisp_io_buf:")
    (emit "    .space 32")
    (emit "    .section .note.GNU-stack,\"\",@progbits")))

;;; -----------------------------------------------------------------------
;;; Pass 140 Entrypoint: Pipeline from LIR to Optimized x86 Assembly
;;; -----------------------------------------------------------------------

(define (emit-x86-64 prog gc-mode)
  (set-car! *backend-gc-mode* gc-mode)
  (set-car! *alloc-counter* 0)
  (let* ((asm-ast (select-instructions-x86 prog))
         (asm-opt (optimize-x86-peephole asm-ast)))
    (emit-x86-asm-program asm-opt gc-mode)
    asm-opt))
;;; =======================================================================
;;; ULisp Compiler Pass 141: Native x86-64 Garbage Collector Code Generator
;;; Conforms to DSN-33 Architecture Specification & Issue #569
;;; Emits inline copying/mark-sweep GC collector and OOM panic routines.
;;; =======================================================================

(define (emit-oom-panic)
  (emit "    .globl ulisp_oom_panic")
  (emit "    .weak ulisp_oom_panic")
  (emit "    .type ulisp_oom_panic, @function")
  (emit "    .p2align 4")
  (emit "ulisp_oom_panic:")
  (emit "    lea rsi, [rip + .L_str_oom_panic]")
  (emit "    mov rdx, 46")                      ; string length
  (emit "    mov rax, 1")                       ; sys_write
  (emit "    mov rdi, 2")                       ; stderr
  (emit "    syscall")
  (emit "    mov rax, 60")                      ; sys_exit
  (emit "    mov rdi, 1")                       ; exit code 1
  (emit "    syscall")
  (emit ".L_str_oom_panic:")
  (emit "    .asciz \"Fatal Error: ULisp Heap Limit Exhausted (OOM)\\n\"")
  (emit "    .p2align 3"))

(define (emit-gc-collector)
  (emit "    .globl ulisp_alloc_slow_trampoline")
  (emit "    .weak ulisp_alloc_slow_trampoline")
  (emit "    .type ulisp_alloc_slow_trampoline, @function")
  (emit "    .p2align 4")
  (emit "ulisp_alloc_slow_trampoline:")
  ;; Caller already shifted rsp by shift (16-byte aligned).
  ;; The call pushed an 8-byte return address, so rsp is (16k + 8).
  ;; Subtract 88 bytes: (16k + 8 - 88) = 16(k - 5), perfectly 16-byte aligned.
  (emit "    sub rsp, 88")
  (emit "    mov [rsp + 0], rax")
  (emit "    mov [rsp + 8], rcx")
  (emit "    mov [rsp + 16], rdx")
  (emit "    mov [rsp + 24], rsi")
  (emit "    mov [rsp + 32], rdi")
  (emit "    mov [rsp + 40], r8")
  (emit "    mov [rsp + 48], r9")
  (emit "    mov [rsp + 56], r10")
  (emit "    mov [rsp + 64], r11")
  (emit "    mov qword ptr [rsp + 72], 0")
  (emit "    mov qword ptr [rsp + 80], 0")
  (emit "    mov rdi, rsp")
  (emit "    call ulisp_gc_collect")
  (emit "    mov rax, [rsp + 0]")
  (emit "    mov rcx, [rsp + 8]")
  (emit "    mov rdx, [rsp + 16]")
  (emit "    mov rsi, [rsp + 24]")
  (emit "    mov rdi, [rsp + 32]")
  (emit "    mov r8,  [rsp + 40]")
  (emit "    mov r9,  [rsp + 48]")
  (emit "    mov r10, [rsp + 56]")
  (emit "    mov r11, [rsp + 64]")
  (emit "    add rsp, 88")
  (emit "    ret")
  (emit "")

  (emit "    .globl ulisp_gc_collect")
  (emit "    .weak ulisp_gc_collect")
  (emit "    .type ulisp_gc_collect, @function")
  (emit "    .p2align 4")
  (emit "ulisp_gc_collect:")
  (emit "    push rbx")
  (emit "    push rbp")
  (emit "    push r13")
  (emit "    push r14")
  (emit "    push r15")
  (emit "    sub rsp, 8")
  (emit "    mov [rsp], rdi")                   ; preserve deepest_sp (Issue #568)
  (emit "    lea r11, [rip + ulisp_gc_state]")
  (emit "    mov rax, [r11 + 88]")              ; gen_mode
  (emit "    cmp rax, 1")
  (emit "    je .L_gc_minor_start")
  ;; --- Dual-Space GC ---
  (emit ".L_gc_dual_start:")
  (emit "    mov rax, [r11 + 8]")               ; to
  (emit "    mov [r11 + 40], rax")              ; free_ptr = to
  (emit "    mov rbx, rax")                     ; scan_start = to
  (emit "    mov rsi, [r11 + 24]")              ; bottom
  (emit "    test rsi, rsi")
  (emit "    jnz .L_gc_dual_has_bottom")
  (emit "    lea rax, [rip + ulisp_stack_base]")
  (emit "    mov rsi, [rax]")
  (emit "    test rsi, rsi")
  (emit "    jnz .L_gc_dual_has_bottom")
  (emit "    mov rsi, rdi")
  (emit ".L_gc_dual_has_bottom:")
  (emit "    mov rdx, rdi")                     ; curr_sp = deepest_sp
  (emit "    lea rax, [rip + __ulisp_stackmap_table]")
  (emit "    mov rcx, [rax]")                   ; safepoints count
  (emit "    test rcx, rcx")
  (emit "    jz .L_gc_dual_conserv_loop")
  (emit ".L_gc_dual_sm_walk:")
  (emit "    cmp rdx, rsi")
  (emit "    jae .L_gc_dual_sm_done")
  (emit "    mov r8, [rdx]")
  (emit "    xor r9, r9")
  (emit ".L_gc_dual_sm_search:")
  (emit "    cmp r9, rcx")
  (emit "    jae .L_gc_dual_sm_not_found")
  (emit "    imul r11, r9, 24")
  (emit "    mov r10, [rax + 8 + r11]")
  (emit "    cmp r10, r8")
  (emit "    je .L_gc_dual_sm_found")
  (emit "    inc r9")
  (emit "    jmp .L_gc_dual_sm_search")
  (emit ".L_gc_dual_sm_found:")
  (emit "    imul r11, r9, 24")
  (emit "    mov r10, [rax + 16 + r11]")      ; frame_size
  (emit "    mov rbp, [rax + 24 + r11]")      ; bitmap
  (emit "    lea r13, [rdx + 8]")               ; frame_base
  (emit "    mov r14, r10")
  (emit "    shr r14, 3")
  (emit "    xor r15, r15")
  (emit ".L_gc_dual_sm_slot_loop:")
  (emit "    cmp r15, r14")
  (emit "    jae .L_gc_dual_sm_frame_done")
  (emit "    cmp r15, 60")
  (emit "    jae .L_gc_dual_sm_slot_copy")
  (emit "    bt rbp, r15")
  (emit "    jnc .L_gc_dual_sm_slot_next")
  (emit ".L_gc_dual_sm_slot_copy:")
  (emit "    lea rcx, [r13 + r15*8]")
  (emit "    mov rdi, [rcx]")
  (emit "    push rdx")
  (emit "    push rcx")
  (emit "    push rax")
  (emit "    push r11")
  (emit "    call .L_gc_copy_if_heap_dual")
  (emit "    pop r11")
  (emit "    mov r11, rax")
  (emit "    pop rax")
  (emit "    pop rcx")
  (emit "    pop rdx")
  (emit "    mov [rcx], r11")
  (emit ".L_gc_dual_sm_slot_next:")
  (emit "    inc r15")
  (emit "    jmp .L_gc_dual_sm_slot_loop")
  (emit ".L_gc_dual_sm_frame_done:")
  (emit "    add rdx, 8")
  (emit "    add rdx, r10")
  (emit "    lea rax, [rip + __ulisp_stackmap_table]")
  (emit "    mov rcx, [rax]")
  (emit "    jmp .L_gc_dual_sm_walk")
  (emit ".L_gc_dual_sm_not_found:")
  (emit "    mov rdi, [rdx]")
  (emit "    push rdx")
  (emit "    push rsi")
  (emit "    push rax")
  (emit "    push rcx")
  (emit "    push r11")
  (emit "    call .L_gc_copy_if_heap_dual")
  (emit "    pop r11")
  (emit "    mov r11, rax")
  (emit "    pop rcx")
  (emit "    pop rax")
  (emit "    pop rsi")
  (emit "    pop rdx")
  (emit "    mov [rdx], r11")
  (emit "    add rdx, 8")
  (emit "    jmp .L_gc_dual_sm_walk")
  (emit ".L_gc_dual_sm_done:")
  (emit "    mov rdx, [rsp]")                   ; restore rdx = deepest_sp (Issue #568)
  (emit ".L_gc_dual_conserv_loop:")
  (emit "    cmp rdx, rsi")
  (emit "    jae .L_gc_dual_scan_globals")
  (emit "    mov rdi, [rdx]")
  (emit "    push rdx")
  (emit "    push rsi")
  (emit "    push r11")
  (emit "    call .L_gc_copy_if_heap_dual")
  (emit "    pop r11")
  (emit "    pop rsi")
  (emit "    pop rdx")
  (emit "    cmp rax, [rdx]")
  (emit "    je .L_gc_dual_conserv_no_rescue")
  (emit "    lea r11, [rip + ulisp_gc_state]")
  (emit "    add qword ptr [r11 + 120], 2")     ; increment rescued unmapped pointer count
  (emit ".L_gc_dual_conserv_no_rescue:")
  (emit "    mov [rdx], rax")
  (emit "    add rdx, 8")
  (emit "    jmp .L_gc_dual_conserv_loop")
  ;; Scan globals across all linked modules
  (emit ".L_gc_dual_scan_globals:")
  (emit "    lea r8, [rip + __start_ulisp_globals_sec]")
  (emit "    lea r9, [rip + __stop_ulisp_globals_sec]")
  (emit ".L_gc_dual_globals_loop:")
  (emit "    cmp r8, r9")
  (emit "    jae .L_gc_dual_cheney")
  (emit "    mov r10, [r8]")
  (emit "    mov rdi, [r10]")
  (emit "    push r8")
  (emit "    push r9")
  (emit "    push r10")
  (emit "    push r11")
  (emit "    call .L_gc_copy_if_heap_dual")
  (emit "    pop r11")
  (emit "    mov r11, rax")
  (emit "    pop r10")
  (emit "    pop r9")
  (emit "    pop r8")
  (emit "    mov [r10], r11")
  (emit "    add r8, 8")
  (emit "    jmp .L_gc_dual_globals_loop")
  ;; Cheney scan To-space
  (emit ".L_gc_dual_cheney:")
  (emit ".L_gc_dual_cheney_loop:")
  (emit "    lea r11, [rip + ulisp_gc_state]")
  (emit "    cmp rbx, [r11 + 40]")
  (emit "    jae .L_gc_dual_finish")
  (emit "    mov r10, [rbx]")
  (emit "    mov rax, r10")
  (emit "    shr rax, 2")
  (emit "    mov rdx, rax")
  (emit "    and rdx, 255")                     ; type
  (emit "    mov r13, rax")
  (emit "    shr r13, 16")
  (emit "    add r13, 8")                       ; total_bytes
  (emit "    lea r14, [rbx + 8]")
  (emit "    cmp rdx, 1")                       ; Type 1: Pair
  (emit "    jne .L_gc_dual_check_closure")
  (emit "    mov rdi, [r14]")
  (emit "    push rbx")
  (emit "    push r11")
  (emit "    push r13")
  (emit "    push r14")
  (emit "    call .L_gc_copy_if_heap_dual")
  (emit "    pop r14")
  (emit "    pop r13")
  (emit "    pop r11")
  (emit "    pop rbx")
  (emit "    mov [r14], rax")
  (emit "    mov rdi, [r14 + 8]")
  (emit "    push rbx")
  (emit "    push r11")
  (emit "    push r13")
  (emit "    push r14")
  (emit "    call .L_gc_copy_if_heap_dual")
  (emit "    pop r14")
  (emit "    pop r13")
  (emit "    pop r11")
  (emit "    pop rbx")
  (emit "    mov [r14 + 8], rax")
  (emit "    jmp .L_gc_dual_cheney_next")
  (emit ".L_gc_dual_check_closure:")
  (emit "    cmp rdx, 2")
  (emit "    jne .L_gc_dual_check_vector")
  (emit "    mov rax, r10")
  (emit "    shr rax, 2")
  (emit "    shr rax, 8")
  (emit "    and rax, 255")
  (emit "    cmp rax, 1")
  (emit "    jle .L_gc_dual_cheney_next")
  (emit "    mov r15, 1")
  (emit ".L_gc_dual_closure_fields:")
  (emit "    cmp r15, rax")
  (emit "    jae .L_gc_dual_cheney_next")
  (emit "    mov rdi, [r14 + r15*8]")
  (emit "    push rax")
  (emit "    push rbx")
  (emit "    push r11")
  (emit "    push r13")
  (emit "    push r14")
  (emit "    push r15")
  (emit "    call .L_gc_copy_if_heap_dual")
  (emit "    pop r15")
  (emit "    pop r14")
  (emit "    pop r13")
  (emit "    pop r11")
  (emit "    mov r11, rax")
  (emit "    pop rbx")
  (emit "    pop rax")
  (emit "    mov [r14 + r15*8], r11")
  (emit "    inc r15")
  (emit "    jmp .L_gc_dual_closure_fields")
  (emit ".L_gc_dual_check_vector:")
  (emit "    cmp rdx, 5")
  (emit "    jne .L_gc_dual_cheney_next")
  (emit "    mov rax, [r14]")
  (emit "    shr rax, 2")
  (emit "    test rax, rax")
  (emit "    jle .L_gc_dual_cheney_next")
  (emit "    xor r15, r15")
  (emit ".L_gc_dual_vector_elems:")
  (emit "    cmp r15, rax")
  (emit "    jae .L_gc_dual_cheney_next")
  (emit "    mov rdi, [r14 + 8 + r15*8]")
  (emit "    push rax")
  (emit "    push rbx")
  (emit "    push r11")
  (emit "    push r13")
  (emit "    push r14")
  (emit "    push r15")
  (emit "    call .L_gc_copy_if_heap_dual")
  (emit "    pop r15")
  (emit "    pop r14")
  (emit "    pop r13")
  (emit "    pop r11")
  (emit "    mov r11, rax")
  (emit "    pop rbx")
  (emit "    pop rax")
  (emit "    mov [r14 + 8 + r15*8], r11")
  (emit "    inc r15")
  (emit "    jmp .L_gc_dual_vector_elems")
  (emit ".L_gc_dual_cheney_next:")
  (emit "    add rbx, r13")
  (emit "    jmp .L_gc_dual_cheney_loop")
  (emit ".L_gc_dual_finish:")
  (emit "    lea r11, [rip + ulisp_gc_state]")
  (emit "    mov rax, [r11 + 0]")
  (emit "    mov rcx, [r11 + 8]")
  (emit "    mov [r11 + 0], rcx")
  (emit "    mov [r11 + 8], rax")
  (emit "    inc qword ptr [r11 + 32]")
  (emit "    mov r12, [r11 + 40]")              ; r12 = free_ptr
  (emit "    mov rax, [r11 + 0]")
  (emit "    add rax, [r11 + 16]")
  (emit "    lea rdx, [rip + ulisp_heap_limit]")
  (emit "    mov [rdx], rax")
  (emit "    jmp .L_gc_exit")

  ;; --- Generational Minor GC ---
  (emit ".L_gc_minor_start:")
  (emit "    lea r11, [rip + ulisp_gc_state]")
  (emit "    mov rbx, [r11 + 40]")              ; scan_start = mature_free
  (emit "    mov rsi, [r11 + 48]")              ; bottom
  (emit "    test rsi, rsi")
  (emit "    jnz .L_gc_minor_has_bottom")
  (emit "    lea rax, [rip + ulisp_stack_base]")
  (emit "    mov rsi, [rax]")
  (emit "    test rsi, rsi")
  (emit "    jnz .L_gc_minor_has_bottom")
  (emit "    mov rsi, rdi")
  (emit ".L_gc_minor_has_bottom:")
  (emit "    mov rdx, rdi")
  (emit "    lea rax, [rip + __ulisp_stackmap_table]")
  (emit "    mov rcx, [rax]")
  (emit "    test rcx, rcx")
  (emit "    jz .L_gc_minor_conserv_loop")
  (emit ".L_gc_minor_sm_walk:")
  (emit "    cmp rdx, rsi")
  (emit "    jae .L_gc_minor_sm_done")
  (emit "    mov r8, [rdx]")
  (emit "    xor r9, r9")
  (emit ".L_gc_minor_sm_search:")
  (emit "    cmp r9, rcx")
  (emit "    jae .L_gc_minor_sm_not_found")
  (emit "    imul r11, r9, 24")
  (emit "    mov r10, [rax + 8 + r11]")
  (emit "    cmp r10, r8")
  (emit "    je .L_gc_minor_sm_found")
  (emit "    inc r9")
  (emit "    jmp .L_gc_minor_sm_search")
  (emit ".L_gc_minor_sm_found:")
  (emit "    imul r11, r9, 24")
  (emit "    mov r10, [rax + 16 + r11]")
  (emit "    mov rbp, [rax + 24 + r11]")
  (emit "    lea r13, [rdx + 8]")
  (emit "    mov r14, r10")
  (emit "    shr r14, 3")
  (emit "    xor r15, r15")
  (emit ".L_gc_minor_sm_slot_loop:")
  (emit "    cmp r15, r14")
  (emit "    jae .L_gc_minor_sm_frame_done")
  (emit "    cmp r15, 60")
  (emit "    jae .L_gc_minor_sm_slot_copy")
  (emit "    bt rbp, r15")
  (emit "    jnc .L_gc_minor_sm_slot_next")
  (emit ".L_gc_minor_sm_slot_copy:")
  (emit "    lea rcx, [r13 + r15*8]")
  (emit "    mov rdi, [rcx]")
  (emit "    push rdx")
  (emit "    push rcx")
  (emit "    push rax")
  (emit "    push r11")
  (emit "    call .L_gc_promote_if_nursery")
  (emit "    pop r11")
  (emit "    mov r11, rax")
  (emit "    pop rax")
  (emit "    pop rcx")
  (emit "    pop rdx")
  (emit "    mov [rcx], r11")
  (emit ".L_gc_minor_sm_slot_next:")
  (emit "    inc r15")
  (emit "    jmp .L_gc_minor_sm_slot_loop")
  (emit ".L_gc_minor_sm_frame_done:")
  (emit "    add rdx, 8")
  (emit "    add rdx, r10")
  (emit "    lea rax, [rip + __ulisp_stackmap_table]")
  (emit "    mov rcx, [rax]")
  (emit "    jmp .L_gc_minor_sm_walk")
  (emit ".L_gc_minor_sm_not_found:")
  (emit "    mov rdi, [rdx]")
  (emit "    push rdx")
  (emit "    push rsi")
  (emit "    push rax")
  (emit "    push rcx")
  (emit "    push r11")
  (emit "    call .L_gc_promote_if_nursery")
  (emit "    pop r11")
  (emit "    mov r11, rax")
  (emit "    pop rcx")
  (emit "    pop rax")
  (emit "    pop rsi")
  (emit "    pop rdx")
  (emit "    mov [rdx], r11")
  (emit "    add rdx, 8")
  (emit "    jmp .L_gc_minor_sm_walk")
  (emit ".L_gc_minor_sm_done:")
  (emit "    mov rdx, [rsp]")                   ; restore rdx = deepest_sp (Issue #568)
  (emit ".L_gc_minor_conserv_loop:")
  (emit "    cmp rdx, rsi")
  (emit "    jae .L_gc_minor_scan_globals")
  (emit "    mov rdi, [rdx]")
  (emit "    push rdx")
  (emit "    push rsi")
  (emit "    push r11")
  (emit "    call .L_gc_promote_if_nursery")
  (emit "    pop r11")
  (emit "    pop rsi")
  (emit "    pop rdx")
  (emit "    cmp rax, [rdx]")
  (emit "    je .L_gc_minor_conserv_no_rescue")
  (emit "    lea r11, [rip + ulisp_gc_state]")
  (emit "    add qword ptr [r11 + 120], 2")     ; increment rescued unmapped pointer count
  (emit ".L_gc_minor_conserv_no_rescue:")
  (emit "    mov [rdx], rax")
  (emit "    add rdx, 8")
  (emit "    jmp .L_gc_minor_conserv_loop")
  ;; Scan globals across all linked modules
  (emit ".L_gc_minor_scan_globals:")
  (emit "    lea r8, [rip + __start_ulisp_globals_sec]")
  (emit "    lea r9, [rip + __stop_ulisp_globals_sec]")
  (emit ".L_gc_minor_globals_loop:")
  (emit "    cmp r8, r9")
  (emit "    jae .L_gc_minor_scan_remset")
  (emit "    mov r10, [r8]")
  (emit "    mov rdi, [r10]")
  (emit "    push r8")
  (emit "    push r9")
  (emit "    push r10")
  (emit "    push r11")
  (emit "    call .L_gc_promote_if_nursery")
  (emit "    pop r11")
  (emit "    mov r11, rax")
  (emit "    pop r10")
  (emit "    pop r9")
  (emit "    pop r8")
  (emit "    mov [r10], r11")
  (emit "    add r8, 8")
  (emit "    jmp .L_gc_minor_globals_loop")
  ;; Scan remset
  (emit ".L_gc_minor_scan_remset:")
  (emit "    lea r11, [rip + ulisp_gc_state]")
  (emit "    mov r8, [r11 + 72]")
  (emit "    mov rcx, [r11 + 80]")
  (emit "    test r8, r8")
  (emit "    jz .L_gc_minor_cheney")
  (emit "    test rcx, rcx")
  (emit "    jz .L_gc_minor_cheney")
  (emit "    xor r9, r9")
  (emit ".L_gc_minor_remset_loop:")
  (emit "    cmp r9, rcx")
  (emit "    jae .L_gc_minor_cheney")
  (emit "    mov r10, [r8 + r9*8]")
  (emit "    mov rdi, [r10]")
  (emit "    push r8")
  (emit "    push rcx")
  (emit "    push r9")
  (emit "    push r10")
  (emit "    push r11")
  (emit "    call .L_gc_promote_if_nursery")
  (emit "    pop r11")
  (emit "    mov r11, rax")
  (emit "    pop r10")
  (emit "    pop r9")
  (emit "    pop rcx")
  (emit "    pop r8")
  (emit "    mov [r10], r11")
  (emit "    inc r9")
  (emit "    jmp .L_gc_minor_remset_loop")
  ;; Cheney scan mature space
  (emit ".L_gc_minor_cheney:")
  (emit ".L_gc_minor_cheney_loop:")
  (emit "    lea r11, [rip + ulisp_gc_state]")
  (emit "    cmp rbx, [r11 + 40]")
  (emit "    jae .L_gc_minor_finish")
  (emit "    mov r10, [rbx]")
  (emit "    mov rax, r10")
  (emit "    shr rax, 2")
  (emit "    mov rdx, rax")
  (emit "    and rdx, 255")
  (emit "    mov r13, rax")
  (emit "    shr r13, 16")
  (emit "    add r13, 8")
  (emit "    lea r14, [rbx + 8]")
  (emit "    cmp rdx, 1")
  (emit "    jne .L_gc_minor_check_closure")
  (emit "    mov rdi, [r14]")
  (emit "    push rbx")
  (emit "    push r11")
  (emit "    push r13")
  (emit "    push r14")
  (emit "    call .L_gc_promote_if_nursery")
  (emit "    pop r14")
  (emit "    pop r13")
  (emit "    pop r11")
  (emit "    pop rbx")
  (emit "    mov [r14], rax")
  (emit "    mov rdi, [r14 + 8]")
  (emit "    push rbx")
  (emit "    push r11")
  (emit "    push r13")
  (emit "    push r14")
  (emit "    call .L_gc_promote_if_nursery")
  (emit "    pop r14")
  (emit "    pop r13")
  (emit "    pop r11")
  (emit "    pop rbx")
  (emit "    mov [r14 + 8], rax")
  (emit "    jmp .L_gc_minor_cheney_next")
  (emit ".L_gc_minor_check_closure:")
  (emit "    cmp rdx, 2")
  (emit "    jne .L_gc_minor_check_vector")
  (emit "    mov rax, r10")
  (emit "    shr rax, 2")
  (emit "    shr rax, 8")
  (emit "    and rax, 255")
  (emit "    cmp rax, 1")
  (emit "    jle .L_gc_minor_cheney_next")
  (emit "    mov r15, 1")
  (emit ".L_gc_minor_closure_fields:")
  (emit "    cmp r15, rax")
  (emit "    jae .L_gc_minor_cheney_next")
  (emit "    mov rdi, [r14 + r15*8]")
  (emit "    push rax")
  (emit "    push rbx")
  (emit "    push r11")
  (emit "    push r13")
  (emit "    push r14")
  (emit "    push r15")
  (emit "    call .L_gc_promote_if_nursery")
  (emit "    pop r15")
  (emit "    pop r14")
  (emit "    pop r13")
  (emit "    pop r11")
  (emit "    mov r11, rax")
  (emit "    pop rbx")
  (emit "    pop rax")
  (emit "    mov [r14 + r15*8], r11")
  (emit "    inc r15")
  (emit "    jmp .L_gc_minor_closure_fields")
  (emit ".L_gc_minor_check_vector:")
  (emit "    cmp rdx, 5")
  (emit "    jne .L_gc_minor_cheney_next")
  (emit "    mov rax, [r14]")
  (emit "    shr rax, 2")
  (emit "    test rax, rax")
  (emit "    jle .L_gc_minor_cheney_next")
  (emit "    xor r15, r15")
  (emit ".L_gc_minor_vector_elems:")
  (emit "    cmp r15, rax")
  (emit "    jae .L_gc_minor_cheney_next")
  (emit "    mov rdi, [r14 + 8 + r15*8]")
  (emit "    push rax")
  (emit "    push rbx")
  (emit "    push r11")
  (emit "    push r13")
  (emit "    push r14")
  (emit "    push r15")
  (emit "    call .L_gc_promote_if_nursery")
  (emit "    pop r15")
  (emit "    pop r14")
  (emit "    pop r13")
  (emit "    pop r11")
  (emit "    mov r11, rax")
  (emit "    pop rbx")
  (emit "    pop rax")
  (emit "    mov [r14 + 8 + r15*8], r11")
  (emit "    inc r15")
  (emit "    jmp .L_gc_minor_vector_elems")
  (emit ".L_gc_minor_cheney_next:")
  (emit "    add rbx, r13")
  (emit "    jmp .L_gc_minor_cheney_loop")
  (emit ".L_gc_minor_finish:")
  (emit "    lea r11, [rip + ulisp_gc_state]")
  ;; Issue #566: Check mature occupancy & dynamic growth
  (emit "    mov rax, [r11 + 40]")              ; mature_free
  (emit "    sub rax, [r11 + 16]")              ; mature_from (rax = used)
  (emit "    imul rax, 10")
  (emit "    mov rdx, [r11 + 32]")              ; mature_size
  (emit "    imul rdx, 7")
  (emit "    cmp rax, rdx")
  (emit "    jbe .L_gc_minor_growth_done")      ; used * 10 <= size * 7, no growth
  (emit "    mov rsi, [r11 + 32]")              ; old_size
  (emit "    mov rdx, rsi")
  (emit "    shl rdx, 1")                       ; new_size = old_size * 2
  (emit "    mov r8, [r11 + 96]")               ; max_size
  (emit "    test r8, r8")
  (emit "    jz .L_gc_minor_do_mremap")
  (emit "    cmp rdx, r8")
  (emit "    jbe .L_gc_minor_do_mremap")
  (emit "    mov rdx, r8")                      ; cap at max_size
  (emit ".L_gc_minor_do_mremap:")
  (emit "    cmp rdx, rsi")
  (emit "    jbe .L_gc_minor_growth_done")
  (emit "    mov rdi, [r11 + 16]")              ; mature_from
  (emit "    push r11")
  (emit "    push rdx")
  (emit "    push rsi")
  (emit "    mov rax, 25")                      ; sys_mremap
  (emit "    xor r10, r10")                     ; flags = 0 (in-place)
  (emit "    xor r8, r8")
  (emit "    xor r9, r9")
  (emit "    syscall")
  (emit "    pop rsi")
  (emit "    pop rdx")
  (emit "    pop r11")
  (emit "    cmp rax, [r11 + 16]")
  (emit "    je .L_gc_minor_mremap_ok")
  ;; In-place failed, try MREMAP_MAYMOVE (flags = 1)
  (emit "    mov rdi, [r11 + 16]")
  (emit "    push r11")
  (emit "    push rdx")
  (emit "    push rsi")
  (emit "    mov rax, 25")
  (emit "    mov r10, 1")                       ; MREMAP_MAYMOVE = 1
  (emit "    xor r8, r8")
  (emit "    xor r9, r9")
  (emit "    syscall")
  (emit "    pop rsi")
  (emit "    pop rdx")
  (emit "    pop r11")
  (emit "    cmp rax, -4096")
  (emit "    jae .L_gc_minor_growth_done")      ; syscall error
  (emit "    cmp rax, [r11 + 16]")
  (emit "    je .L_gc_minor_mremap_ok")
  (emit "    mov rcx, [r11 + 16]")
  (emit "    mov [r11 + 16], rax")              ; update mature_from
  (emit "    sub rax, rcx")                     ; diff = new - old
  (emit "    add [r11 + 40], rax")              ; mature_free += diff
  (emit ".L_gc_minor_mremap_ok:")
  (emit "    mov [r11 + 32], rdx")              ; mature_size = new_size
  (emit "    inc qword ptr [r11 + 104]")        ; growth_count++
  (emit ".L_gc_minor_growth_done:")
  (emit "    mov r12, [r11 + 0]")              ; r12 = nursery_base
  (emit "    mov rax, r12")
  (emit "    add rax, [r11 + 8]")
  (emit "    lea rdx, [rip + ulisp_heap_limit]")
  (emit "    mov [rdx], rax")
  (emit "    mov qword ptr [r11 + 80], 0")
  (emit "    inc qword ptr [r11 + 56]")
  (emit ".L_gc_exit:")
  (emit "    add rsp, 8")
  (emit "    pop r15")
  (emit "    pop r14")
  (emit "    pop r13")
  (emit "    pop rbp")
  (emit "    pop rbx")
  (emit "    ret")

  ;; --- Helpers ---
  (emit ".L_gc_copy_if_heap_dual:")
  (emit "    mov rax, rdi")
  (emit "    and rax, 7")
  (emit "    cmp rax, 1")
  (emit "    je .L_gc_dual_tag_ok")
  (emit "    cmp rax, 3")
  (emit "    je .L_gc_dual_tag_ok")
  (emit "    cmp rax, 5")
  (emit "    je .L_gc_dual_tag_ok")
  (emit "    cmp rax, 7")
  (emit "    je .L_gc_dual_tag_ok")
  (emit "    mov rax, rdi")
  (emit "    ret")
  (emit ".L_gc_dual_tag_ok:")
  (emit "    mov r8, rdi")
  (emit "    and r8, -8")
  (emit "    lea r11, [rip + ulisp_gc_state]")
  (emit "    mov r9, [r11 + 0]")
  (emit "    mov r10, [r11 + 16]")
  (emit "    cmp r8, r9")
  (emit "    jb .L_gc_ret_dual_orig")
  (emit "    add r10, r9")
  (emit "    cmp r8, r10")
  (emit "    jae .L_gc_ret_dual_orig")
  (emit "    mov r10, [r8 - 8]")
  (emit "    mov rax, r10")
  (emit "    and rax, 7")
  (emit "    test rax, rax")
  (emit "    jz .L_gc_do_copy_dual")
  (emit "    mov rax, r10")
  (emit "    and rax, -8")
  (emit "    mov r9, [r11 + 8]")
  (emit "    cmp rax, r9")
  (emit "    jb .L_gc_do_copy_dual")
  (emit "    cmp rax, [r11 + 40]")
  (emit "    jae .L_gc_do_copy_dual")
  (emit "    mov rax, r10")
  (emit "    ret")
  (emit ".L_gc_do_copy_dual:")
  (emit "    mov r9, [r11 + 40]")
  (emit "    mov rax, r10")
  (emit "    shr rax, 2")
  (emit "    shr rax, 16")
  (emit "    add rax, 8")
  (emit "    xor rcx, rcx")
  (emit ".L_gc_dual_copy_loop:")
  (emit "    cmp rcx, rax")
  (emit "    jae .L_gc_dual_copy_done")
  (emit "    mov r10, [r8 - 8 + rcx]")
  (emit "    mov [r9 + rcx], r10")
  (emit "    add rcx, 8")
  (emit "    jmp .L_gc_dual_copy_loop")
  (emit ".L_gc_dual_copy_done:")
  (emit "    lea r10, [r9 + 8]")
  (emit "    mov rcx, rdi")
  (emit "    and rcx, 7")
  (emit "    or r10, rcx")
  (emit "    mov [r8 - 8], r10")
  (emit "    add r9, rax")
  (emit "    mov [r11 + 40], r9")
  (emit "    mov rax, r10")
  (emit "    ret")
  (emit ".L_gc_ret_dual_orig:")
  (emit "    mov rax, rdi")
  (emit "    ret")

  (emit ".L_gc_promote_if_nursery:")
  (emit "    mov rax, rdi")
  (emit "    and rax, 7")
  (emit "    cmp rax, 1")
  (emit "    je .L_gc_nursery_tag_ok")
  (emit "    cmp rax, 3")
  (emit "    je .L_gc_nursery_tag_ok")
  (emit "    cmp rax, 5")
  (emit "    je .L_gc_nursery_tag_ok")
  (emit "    cmp rax, 7")
  (emit "    je .L_gc_nursery_tag_ok")
  (emit "    mov rax, rdi")
  (emit "    ret")
  (emit ".L_gc_nursery_tag_ok:")
  (emit "    mov r8, rdi")
  (emit "    and r8, -8")
  (emit "    lea r11, [rip + ulisp_gc_state]")
  (emit "    mov r9, [r11 + 0]")
  (emit "    mov r10, [r11 + 8]")
  (emit "    cmp r8, r9")
  (emit "    jb .L_gc_ret_nursery_orig")
  (emit "    add r10, r9")
  (emit "    cmp r8, r10")
  (emit "    jae .L_gc_ret_nursery_orig")
  (emit "    mov r10, [r8 - 8]")
  (emit "    mov rax, r10")
  (emit "    and rax, 7")
  (emit "    test rax, rax")
  (emit "    jz .L_gc_do_promote")
  (emit "    mov rax, r10")
  (emit "    and rax, -8")
  (emit "    mov r9, [r11 + 16]")
  (emit "    cmp rax, r9")
  (emit "    jb .L_gc_do_promote")
  (emit "    add r9, [r11 + 32]")
  (emit "    cmp rax, r9")
  (emit "    jae .L_gc_do_promote")
  (emit "    mov rax, r10")
  (emit "    ret")
  (emit ".L_gc_do_promote:")
  (emit "    mov r9, [r11 + 40]")
  (emit "    mov rax, r10")
  (emit "    shr rax, 2")
  (emit "    shr rax, 16")
  (emit "    add rax, 8")
  (emit "    xor rcx, rcx")
  (emit ".L_gc_promote_loop:")
  (emit "    cmp rcx, rax")
  (emit "    jae .L_gc_promote_done")
  (emit "    mov r10, [r8 - 8 + rcx]")
  (emit "    mov [r9 + rcx], r10")
  (emit "    add rcx, 8")
  (emit "    jmp .L_gc_promote_loop")
  (emit ".L_gc_promote_done:")
  (emit "    lea r10, [r9 + 8]")
  (emit "    mov rcx, rdi")
  (emit "    and rcx, 7")
  (emit "    or r10, rcx")
  (emit "    mov [r8 - 8], r10")
  (emit "    add r9, rax")
  (emit "    mov [r11 + 40], r9")
  (emit "    mov rax, r10")
  (emit "    ret")
  (emit ".L_gc_ret_nursery_orig:")
  (emit "    mov rax, rdi")
  (emit "    ret"))

;;; =======================================================================
;;; ULisp Compiler Pass 142: Native x86-64 Freestanding Runtime Generator
;;; Conforms to DSN-33 Architecture Specification & Issue #569
;;; Emits low-level I/O and runtime primitives for bare-metal/libc-free environments.
;;; =======================================================================

(define (emit-freestanding-runtime)
  ;; 1. I/O primitives: ulisp_read_char, ulisp_peek_char, ulisp_write_char
  (emit "    .globl ulisp_read_char")
  (emit "    .weak ulisp_read_char")
  (emit "    .type ulisp_read_char, @function")
  (emit "    .p2align 4")
  (emit "ulisp_read_char:")
  (emit "    lea rdx, [rip + ulisp_has_peek]")
  (emit "    cmp byte ptr [rdx], 0")
  (emit "    je .L_read_direct")
  (emit "    mov byte ptr [rdx], 0")
  (emit "    lea rdx, [rip + ulisp_peek_buf]")
  (emit "    movzx rax, byte ptr [rdx]")
  (emit "    shl rax, 8")
  (emit "    or rax, 14")              ; CHAR_TAG
  (emit "    ret")
  (emit ".L_read_direct:")
  (emit "    xor rax, rax")            ; sys_read
  (emit "    xor rdi, rdi")            ; stdin
  (emit "    lea rsi, [rip + ulisp_io_buf]")
  (emit "    mov rdx, 1")
  (emit "    syscall")
  (emit "    test rax, rax")
  (emit "    jle .L_read_eof")
  (emit "    lea rdx, [rip + ulisp_io_buf]")
  (emit "    movzx rax, byte ptr [rdx]")
  (emit "    shl rax, 8")
  (emit "    or rax, 14")
  (emit "    ret")
  (emit ".L_read_eof:")
  (emit "    mov rax, 79")             ; EOF_OBJECT
  (emit "    ret")
  (emit "")
  (emit "    .globl ulisp_peek_char")
  (emit "    .weak ulisp_peek_char")
  (emit "    .type ulisp_peek_char, @function")
  (emit "    .p2align 4")
  (emit "ulisp_peek_char:")
  (emit "    lea rdx, [rip + ulisp_has_peek]")
  (emit "    cmp byte ptr [rdx], 0")
  (emit "    jne .L_peek_buf_ready")
  (emit "    xor rax, rax")            ; sys_read
  (emit "    xor rdi, rdi")            ; stdin
  (emit "    lea rsi, [rip + ulisp_peek_buf]")
  (emit "    mov rdx, 1")
  (emit "    syscall")
  (emit "    test rax, rax")
  (emit "    jle .L_peek_eof")
  (emit "    lea rdx, [rip + ulisp_has_peek]")
  (emit "    mov byte ptr [rdx], 1")
  (emit ".L_peek_buf_ready:")
  (emit "    lea rdx, [rip + ulisp_peek_buf]")
  (emit "    movzx rax, byte ptr [rdx]")
  (emit "    shl rax, 8")
  (emit "    or rax, 14")
  (emit "    ret")
  (emit ".L_peek_eof:")
  (emit "    mov rax, 79")
  (emit "    ret")
  (emit "")
  (emit "    .globl ulisp_flush")
  (emit "    .weak ulisp_flush")
  (emit "    .type ulisp_flush, @function")
  (emit "    .p2align 4")
  (emit "ulisp_flush:")
  (emit "    lea rcx, [rip + ulisp_out_buf_len]")
  (emit "    mov rdx, [rcx]")
  (emit "    test rdx, rdx")
  (emit "    jle .L_flush_done")
  (emit "    mov qword ptr [rcx], 0")
  (emit "    mov rax, 1")              ; sys_write
  (emit "    mov rdi, 1")              ; stdout
  (emit "    lea rsi, [rip + ulisp_out_buf]")
  (emit "    syscall")
  (emit ".L_flush_done:")
  (emit "    mov rax, 111")            ; #t (0x6F)
  (emit "    ret")
  (emit "")
  (emit "    .globl ulisp_emit_byte")
  (emit "    .weak ulisp_emit_byte")
  (emit "    .type ulisp_emit_byte, @function")
  (emit "    .p2align 4")
  (emit "ulisp_emit_byte:")
  (emit "    lea rcx, [rip + ulisp_out_buf_len]")
  (emit "    mov rdx, [rcx]")
  (emit "    lea rsi, [rip + ulisp_out_buf]")
  (emit "    mov byte ptr [rsi + rdx], dil")
  (emit "    inc rdx")
  (emit "    mov [rcx], rdx")
  (emit "    cmp rdx, 4096")
  (emit "    jl .L_emit_byte_ret")
  (emit "    sub rsp, 8")
  (emit "    call ulisp_flush")
  (emit "    add rsp, 8")
  (emit ".L_emit_byte_ret:")
  (emit "    mov rax, 111")
  (emit "    ret")
  (emit "")
  (emit "    .globl ulisp_write_char")
  (emit "    .weak ulisp_write_char")
  (emit "    .type ulisp_write_char, @function")
  (emit "    .p2align 4")
  (emit "ulisp_write_char:")
  (emit "    sar rdi, 8")
  (emit "    jmp ulisp_emit_byte")
  (emit "")
  (emit "    .globl ulisp_emit_str")
  (emit "    .weak ulisp_emit_str")
  (emit "    .type ulisp_emit_str, @function")
  (emit "    .p2align 4")
  (emit "ulisp_emit_str:")
  (emit "    push rbx")
  (emit "    sub rsp, 8")
  (emit "    mov rbx, rdi")
  (emit ".L_strlen_loop:")
  (emit "    movzx rdi, byte ptr [rbx]")
  (emit "    test dil, dil")
  (emit "    jz .L_strlen_done")
  (emit "    call ulisp_emit_byte")
  (emit "    inc rbx")
  (emit "    jmp .L_strlen_loop")
  (emit ".L_strlen_done:")
  (emit "    add rsp, 8")
  (emit "    pop rbx")
  (emit "    mov rax, 111")
  (emit "    ret")
  (emit "")
  (emit "    .globl ulisp_write_string")
  (emit "    .weak ulisp_write_string")
  (emit "    .type ulisp_write_string, @function")
  (emit "    .p2align 4")
  (emit "ulisp_write_string:")
  (emit "    sub rdi, 3")              ; untag string (tag 3)
  (emit "    jmp ulisp_emit_str")
  (emit "")
  ;; 3. Scheme Value Printer: ulisp_print_value
  (emit "    .globl ulisp_print_value")
  (emit "    .weak ulisp_print_value")
  (emit "    .type ulisp_print_value, @function")
  (emit "    .p2align 4")
  (emit "ulisp_print_value:")
  (emit "    push rbx")
  (emit "    push r12")
  (emit "    push r13")
  (emit "    mov rbx, rdi")
  (emit "    test rbx, 3")
  (emit "    jnz .L_pv_not_fixnum")
  (emit "    sar rbx, 2")
  (emit "    mov rdi, rbx")
  (emit "    call ulisp_print_fixnum")
  (emit "    jmp .L_pv_done")
  (emit ".L_pv_not_fixnum:")
  (emit "    cmp rbx, 47")              ; #f
  (emit "    jne .L_pv_not_false")
  (emit "    lea rdi, [rip + .L_str_false]")
  (emit "    call ulisp_emit_str")
  (emit "    jmp .L_pv_done")
  (emit ".L_pv_not_false:")
  (emit "    cmp rbx, 111")             ; #t
  (emit "    jne .L_pv_not_true")
  (emit "    lea rdi, [rip + .L_str_true]")
  (emit "    call ulisp_emit_str")
  (emit "    jmp .L_pv_done")
  (emit ".L_pv_not_true:")
  (emit "    cmp rbx, 63")              ; ()
  (emit "    jne .L_pv_not_nil")
  (emit "    lea rdi, [rip + .L_str_nil]")
  (emit "    call ulisp_emit_str")
  (emit "    jmp .L_pv_done")
  (emit ".L_pv_not_nil:")
  (emit "    cmp rbx, 79")              ; eof
  (emit "    jne .L_pv_not_eof")
  (emit "    lea rdi, [rip + .L_str_eof]")
  (emit "    call ulisp_emit_str")
  (emit "    jmp .L_pv_done")
  (emit ".L_pv_not_eof:")
  (emit "    mov rax, rbx")
  (emit "    and rax, 255")
  (emit "    cmp rax, 14")              ; char tag
  (emit "    jne .L_pv_not_char")
  (emit "    mov rdi, rbx")
  (emit "    sar rdi, 8")
  (emit "    call ulisp_print_char")
  (emit "    jmp .L_pv_done")
  (emit ".L_pv_not_char:")
  (emit "    mov rax, rbx")
  (emit "    and rax, 7")
  (emit "    cmp rax, 3")              ; string tag
  (emit "    jne .L_pv_not_string")
  (emit "    mov rdi, 34")             ; '\"'
  (emit "    call ulisp_emit_byte")
  (emit "    mov rdi, rbx")
  (emit "    sub rdi, 3")
  (emit "    call ulisp_emit_str")
  (emit "    mov rdi, 34")
  (emit "    call ulisp_emit_byte")
  (emit "    jmp .L_pv_done")
  (emit ".L_pv_not_string:")
  (emit "    cmp rax, 7")              ; bytevector tag
  (emit "    jne .L_pv_not_bytevector")
  (emit "    mov rdi, rbx")
  (emit "    call ulisp_print_bytevector")
  (emit "    jmp .L_pv_done")
  (emit ".L_pv_not_bytevector:")
  (emit "    cmp rax, 5")              ; vector tag
  (emit "    jne .L_pv_not_vector")
  (emit "    mov rdi, rbx")
  (emit "    call ulisp_print_vector")
  (emit "    jmp .L_pv_done")
  (emit ".L_pv_not_vector:")
  (emit "    cmp rax, 1")              ; pair tag
  (emit "    jne .L_pv_not_pair")
  (emit "    mov rdi, rbx")
  (emit "    call ulisp_print_pair")
  (emit "    jmp .L_pv_done")
  (emit ".L_pv_not_pair:")
  (emit "    mov rax, rbx")
  (emit "    and rax, 255")
  (emit "    cmp rax, 2")              ; symbol tag
  (emit "    jne .L_pv_unknown")
  (emit "    mov rdi, rbx")
  (emit "    call ulisp_print_symbol")
  (emit "    jmp .L_pv_done")
  (emit ".L_pv_unknown:")
  (emit "    lea rdi, [rip + .L_str_unknown]")
  (emit "    call ulisp_emit_str")
  (emit ".L_pv_done:")
  (emit "    pop r13")
  (emit "    pop r12")
  (emit "    pop rbx")
  (emit "    ret")
  (emit "")
  (emit "    .globl ulisp_find_symbol_str")
  (emit "    .weak ulisp_find_symbol_str")
  (emit "    .type ulisp_find_symbol_str, @function")
  (emit "    .p2align 4")
  (emit "ulisp_find_symbol_str:")
  (emit "    push rbx")
  (emit "    push r12")
  (emit "    push r13")
  (emit "    mov rbx, rdi")              ; rbx = target symbol id
  (emit "    lea r12, [rip + __ulisp_symbol_table]")
  (emit "    mov r13, [r12]")            ; count
  (emit "    test r13, r13")
  (emit "    jz .L_fss_not_found")
  (emit "    xor rcx, rcx")              ; index
  (emit ".L_fss_loop:")
  (emit "    cmp rcx, r13")
  (emit "    jge .L_fss_not_found")
  (emit "    mov rax, rcx")
  (emit "    shl rax, 4")
  (emit "    cmp rbx, [r12 + 8 + rax]")
  (emit "    je .L_fss_found")
  (emit "    inc rcx")
  (emit "    jmp .L_fss_loop")
  (emit ".L_fss_found:")
  (emit "    mov rax, [r12 + 16 + rax]") ; pointer to asciz string
  (emit "    pop r13")
  (emit "    pop r12")
  (emit "    pop rbx")
  (emit "    ret")
  (emit ".L_fss_not_found:")
  (emit "    xor rax, rax")
  (emit "    pop r13")
  (emit "    pop r12")
  (emit "    pop rbx")
  (emit "    ret")
  (emit "")
  (emit "    .globl ulisp_print_symbol")
  (emit "    .weak ulisp_print_symbol")
  (emit "    .type ulisp_print_symbol, @function")
  (emit "    .p2align 4")
  (emit "ulisp_print_symbol:")
  (emit "    push rbx")
  (emit "    mov rbx, rdi")
  (emit "    call ulisp_find_symbol_str")
  (emit "    test rax, rax")
  (emit "    jz .L_ps_fallback")
  (emit "    mov rdi, rax")
  (emit "    call ulisp_emit_str")
  (emit "    pop rbx")
  (emit "    ret")
  (emit ".L_ps_fallback:")
  (emit "    lea rdi, [rip + .L_str_symbol]")
  (emit "    call ulisp_emit_str")
  (emit "    pop rbx")
  (emit "    ret")
  (emit "")
  (emit "    .p2align 4")
  (emit "ulisp_print_fixnum:")
  (emit "    push rbx")
  (emit "    push r12")
  (emit "    mov rbx, rdi")
  (emit "    test rbx, rbx")
  (emit "    jnz .L_pn_not_zero")
  (emit "    mov rdi, 48")             ; '0'
  (emit "    call ulisp_emit_byte")
  (emit "    pop r12")
  (emit "    pop rbx")
  (emit "    ret")
  (emit ".L_pn_not_zero:")
  (emit "    jns .L_pn_pos")
  (emit "    mov rdi, 45")             ; '-'
  (emit "    call ulisp_emit_byte")
  (emit "    neg rbx")
  (emit ".L_pn_pos:")
  (emit "    sub rsp, 32")
  (emit "    xor r12, r12")
  (emit "    mov rax, rbx")
  (emit "    mov rcx, 10")
  (emit ".L_pn_loop:")
  (emit "    test rax, rax")
  (emit "    jz .L_pn_emit_digits")
  (emit "    xor rdx, rdx")
  (emit "    div rcx")
  (emit "    add dl, 48")
  (emit "    mov [rsp + r12], dl")
  (emit "    inc r12")
  (emit "    jmp .L_pn_loop")
  (emit ".L_pn_emit_digits:")
  (emit "    test r12, r12")
  (emit "    jz .L_pn_fin")
  (emit "    dec r12")
  (emit "    movzx rdi, byte ptr [rsp + r12]")
  (emit "    call ulisp_emit_byte")
  (emit "    jmp .L_pn_emit_digits")
  (emit ".L_pn_fin:")
  (emit "    add rsp, 32")
  (emit "    pop r12")
  (emit "    pop rbx")
  (emit "    ret")
  (emit "")
  (emit "    .p2align 4")
  (emit "ulisp_print_char:")
  (emit "    push rbx")
  (emit "    mov rbx, rdi")
  (emit "    lea rdi, [rip + .L_str_char_prefix]")
  (emit "    call ulisp_emit_str")
  (emit "    cmp rbx, 10")
  (emit "    jne .L_pc_not_nl")
  (emit "    lea rdi, [rip + .L_str_newline]")
  (emit "    call ulisp_emit_str")
  (emit "    pop rbx")
  (emit "    ret")
  (emit ".L_pc_not_nl:")
  (emit "    cmp rbx, 32")
  (emit "    jne .L_pc_not_sp")
  (emit "    lea rdi, [rip + .L_str_space]")
  (emit "    call ulisp_emit_str")
  (emit "    pop rbx")
  (emit "    ret")
  (emit ".L_pc_not_sp:")
  (emit "    cmp rbx, 9")
  (emit "    jne .L_pc_raw")
  (emit "    lea rdi, [rip + .L_str_tab]")
  (emit "    call ulisp_emit_str")
  (emit "    pop rbx")
  (emit "    ret")
  (emit ".L_pc_raw:")
  (emit "    mov rdi, rbx")
  (emit "    call ulisp_emit_byte")
  (emit "    pop rbx")
  (emit "    ret")
  (emit "")
  (emit "    .p2align 4")
  (emit "ulisp_print_pair:")
  (emit "    push rbx")
  (emit "    push r12")
  (emit "    mov rbx, rdi")
  (emit "    mov rdi, 40")             ; '('
  (emit "    call ulisp_emit_byte")
  (emit "    mov r12, 1")
  (emit ".L_pair_loop:")
  (emit "    test r12, r12")
  (emit "    jnz .L_pair_no_space")
  (emit "    mov rdi, 32")             ; ' '
  (emit "    call ulisp_emit_byte")
  (emit ".L_pair_no_space:")
  (emit "    xor r12, r12")
  (emit "    mov rdi, [rbx - 1]")      ; car
  (emit "    call ulisp_print_value")
  (emit "    mov rbx, [rbx + 7]")      ; cdr
  (emit "    cmp rbx, 63")             ; EMPTY_LIST
  (emit "    je .L_pair_done")
  (emit "    mov rax, rbx")
  (emit "    and rax, 7")
  (emit "    cmp rax, 1")              ; PAIR_TAG
  (emit "    je .L_pair_loop")
  (emit "    lea rdi, [rip + .L_str_dot]")
  (emit "    call ulisp_emit_str")
  (emit "    mov rdi, rbx")
  (emit "    call ulisp_print_value")
  (emit ".L_pair_done:")
  (emit "    mov rdi, 41")             ; ')'
  (emit "    call ulisp_emit_byte")
  (emit "    pop r12")
  (emit "    pop rbx")
  (emit "    ret")
  (emit "")
  (emit "    .p2align 4")
  (emit "ulisp_print_bytevector:")
  (emit "    push rbx")
  (emit "    push r12")
  (emit "    push r13")
  (emit "    mov rbx, rdi")            ; tagged bytevector (tag 7)
  (emit "    lea rdi, [rip + .L_str_u8_prefix]")
  (emit "    call ulisp_emit_str")
  (emit "    mov r12, [rbx - 7]")      ; len (fixnum)
  (emit "    sar r12, 2")              ; raw len
  (emit "    xor r13, r13")            ; index = 0
  (emit ".L_pbv_loop:")
  (emit "    cmp r13, r12")
  (emit "    jge .L_pbv_done")
  (emit "    test r13, r13")
  (emit "    jz .L_pbv_elem")
  (emit "    mov dil, 32")             ; ' '
  (emit "    call ulisp_emit_byte")
  (emit ".L_pbv_elem:")
  (emit "    movzx rdi, byte ptr [rbx - 7 + 8 + r13]")
  (emit "    call ulisp_print_fixnum")
  (emit "    inc r13")
  (emit "    jmp .L_pbv_loop")
  (emit ".L_pbv_done:")
  (emit "    mov dil, 41")             ; ')'
  (emit "    call ulisp_emit_byte")
  (emit "    pop r13")
  (emit "    pop r12")
  (emit "    pop rbx")
  (emit "    ret")
  (emit "")
  (emit "    .p2align 4")
  (emit "ulisp_print_vector:")
  (emit "    push rbx")
  (emit "    push r12")
  (emit "    push r13")
  (emit "    mov rbx, rdi")            ; tagged vector (tag 5)
  (emit "    lea rdi, [rip + .L_str_vec_prefix]")
  (emit "    call ulisp_emit_str")
  (emit "    mov r12, [rbx - 5]")      ; len (fixnum)
  (emit "    sar r12, 2")              ; raw len
  (emit "    xor r13, r13")            ; index = 0
  (emit ".L_pvec_loop:")
  (emit "    cmp r13, r12")
  (emit "    jge .L_pvec_done")
  (emit "    test r13, r13")
  (emit "    jz .L_pvec_elem")
  (emit "    mov dil, 32")             ; ' '
  (emit "    call ulisp_emit_byte")
  (emit ".L_pvec_elem:")
  (emit "    mov rdi, [rbx - 5 + 8 + r13*8]")
  (emit "    call ulisp_print_value")
  (emit "    inc r13")
  (emit "    jmp .L_pvec_loop")
  (emit ".L_pvec_done:")
  (emit "    mov dil, 41")             ; ')'
  (emit "    call ulisp_emit_byte")
  (emit "    pop r13")
  (emit "    pop r12")
  (emit "    pop rbx")
  (emit "    ret")
  (emit "")
  (emit "    .p2align 4")
  (emit ".L_unhandled_exn:")
  (emit "    mov rdi, rax")
  (emit "    call ulisp_unhandled_exception")
  (emit "")
  (emit "    .p2align 4")
  (emit "ulisp_streq:")
  (emit ".L_streq_loop:")
  (emit "    mov al, [rdi]")
  (emit "    mov dl, [rsi]")
  (emit "    cmp al, dl")
  (emit "    jne .L_streq_no")
  (emit "    test al, al")
  (emit "    jz .L_streq_yes")
  (emit "    inc rdi")
  (emit "    inc rsi")
  (emit "    jmp .L_streq_loop")
  (emit ".L_streq_yes:")
  (emit "    mov rax, 1")
  (emit "    ret")
  (emit ".L_streq_no:")
  (emit "    xor rax, rax")
  (emit "    ret")
  (emit "")
  (emit "    .globl ulisp_is_error_symbol")
  (emit "    .weak ulisp_is_error_symbol")
  (emit "    .type ulisp_is_error_symbol, @function")
  (emit "    .p2align 4")
  (emit "ulisp_is_error_symbol:")
  (emit "    push rbx")
  (emit "    push r12")
  (emit "    sub rsp, 8")
  (emit "    call ulisp_find_symbol_str")
  (emit "    test rax, rax")
  (emit "    jz .L_ies_no")
  (emit "    mov r12, rax")
  (emit "    lea rdi, [rip + .L_str_sym_error_object]")
  (emit "    mov rsi, r12")
  (emit "    call ulisp_streq")
  (emit "    test rax, rax")
  (emit "    jnz .L_ies_yes")
  (emit "    lea rdi, [rip + .L_str_sym_error]")
  (emit "    mov rsi, r12")
  (emit "    call ulisp_streq")
  (emit "    test rax, rax")
  (emit "    jnz .L_ies_yes")
  (emit ".L_ies_no:")
  (emit "    xor rax, rax")
  (emit "    add rsp, 8")
  (emit "    pop r12")
  (emit "    pop rbx")
  (emit "    ret")
  (emit ".L_ies_yes:")
  (emit "    mov rax, 1")
  (emit "    add rsp, 8")
  (emit "    pop r12")
  (emit "    pop rbx")
  (emit "    ret")
  (emit "")
  (emit "    .globl ulisp_unhandled_exception")
  (emit "    .weak ulisp_unhandled_exception")
  (emit "    .type ulisp_unhandled_exception, @function")
  (emit "    .p2align 4")
  (emit "ulisp_unhandled_exception:")
  (emit "    push rbx")
  (emit "    push r12")
  (emit "    push r13")
  (emit "    push r14")
  (emit "    sub rsp, 8")
  (emit "    mov rbx, rdi")             ; exception object
  (emit "    mov rax, rbx")
  (emit "    and rax, 7")
  (emit "    cmp rax, 1")
  (emit "    jne .L_ue_generic")
  (emit "    mov rdi, [rbx - 1]")       ; car
  (emit "    mov rax, rdi")
  (emit "    and rax, 255")
  (emit "    cmp rax, 2")
  (emit "    jne .L_ue_generic")
  (emit "    call ulisp_is_error_symbol")
  (emit "    test rax, rax")
  (emit "    jz .L_ue_generic")
  (emit "    mov r12, [rbx + 7]")       ; cdr
  (emit "    mov rax, r12")
  (emit "    and rax, 7")
  (emit "    cmp rax, 1")
  (emit "    jne .L_ue_generic")
  (emit "    mov r13, [r12 - 1]")       ; msg = car(cdr)
  (emit "    mov r14, [r12 + 7]")       ; irritants = cdr(cdr)
  (emit "    lea rdi, [rip + .L_str_err_prefix]")
  (emit "    call ulisp_emit_str")
  (emit "    mov rax, r13")
  (emit "    and rax, 7")
  (emit "    cmp rax, 3")               ; STRING_TAG
  (emit "    jne .L_ue_msg_value")
  (emit "    mov rdi, r13")
  (emit "    sub rdi, 3")
  (emit "    call ulisp_emit_str")
  (emit "    jmp .L_ue_msg_done")
  (emit ".L_ue_msg_value:")
  (emit "    mov rdi, r13")
  (emit "    call ulisp_print_value")
  (emit ".L_ue_msg_done:")
  (emit "    mov dil, 10")
  (emit "    call ulisp_emit_byte")
  (emit "    cmp r14, 63")
  (emit "    je .L_ue_exit")
  (emit "    lea rdi, [rip + .L_str_irritants_prefix]")
  (emit "    call ulisp_emit_str")
  (emit ".L_ue_irritants_loop:")
  (emit "    mov rax, r14")
  (emit "    and rax, 7")
  (emit "    cmp rax, 1")
  (emit "    jne .L_ue_irritants_tail")
  (emit "    mov rdi, [r14 - 1]")       ; car
  (emit "    call ulisp_print_value")
  (emit "    mov r14, [r14 + 7]")       ; cdr
  (emit "    cmp r14, 63")
  (emit "    je .L_ue_irritants_done")
  (emit "    mov dil, 32")              ; ' '
  (emit "    call ulisp_emit_byte")
  (emit "    jmp .L_ue_irritants_loop")
  (emit ".L_ue_irritants_tail:")
  (emit "    lea rdi, [rip + .L_str_dot]")
  (emit "    call ulisp_emit_str")
  (emit "    mov rdi, r14")
  (emit "    call ulisp_print_value")
  (emit ".L_ue_irritants_done:")
  (emit "    mov dil, 10")
  (emit "    call ulisp_emit_byte")
  (emit "    jmp .L_ue_exit")
  (emit ".L_ue_generic:")
  (emit "    lea rdi, [rip + .L_str_unhandled_exn]")
  (emit "    call ulisp_emit_str")
  (emit "    mov rdi, rbx")
  (emit "    call ulisp_print_value")
  (emit "    mov dil, 10")
  (emit "    call ulisp_emit_byte")
  (emit ".L_ue_exit:")
  (emit "    call ulisp_flush")
  (emit "    add rsp, 8")
  (emit "    pop r14")
  (emit "    pop r13")
  (emit "    pop r12")
  (emit "    pop rbx")
  (emit "    mov rdi, 1")
  (emit "    mov rax, 60")
  (emit "    syscall")
  (emit "")
  (emit "    .globl ulisp_continuation_invoke")
  (emit "    .weak ulisp_continuation_invoke")
  (emit "    .type ulisp_continuation_invoke, @function")
  (emit "    .p2align 4")
  (emit "ulisp_continuation_invoke:")
  (emit "    mov rax, [rsp + 8]")
  (emit "    mov rcx, [r10 - 1 + 8]")
  (emit "    mov r8,  [r10 - 1 + 16]")
  (emit "    mov rbp, [r10 - 1 + 24]")
  (emit "    mov rbx, [r10 - 1 + 32]")
  (emit "    mov r13, [r10 - 1 + 48]")
  (emit "    mov r14, [r10 - 1 + 56]")
  (emit "    mov r15, [r10 - 1 + 64]")
  (emit "    mov r11, [r10 - 1 + 72]")
  (emit "    mov r9,  [r10 - 1 + 80]")
  (emit "    lea rdx, [rip + ulisp_handler_chain]")
  (emit "    mov [rdx], r9")
  (emit "    test rcx, rcx")
  (emit "    jle 1f")
  (emit "    cmp rcx, 8388608")
  (emit "    jbe 2f")
  (emit "1:")
  (emit "    mov rcx, 65536")
  (emit "2:")
  (emit "    lea rsi, [r10 - 1 + 96]")
  (emit "    mov rdi, r8")
  (emit "    cld")
  (emit "    rep movsb")
  (emit "    mov rsp, r8")
  (emit "    jmp r11")
  (emit "")
  (emit ".L_str_unhandled_exn: .asciz \"*** ERROR: unhandled exception: \"")
  (emit ".L_str_err_prefix: .asciz \"*** ERROR: \"")
  (emit ".L_str_irritants_prefix: .asciz \"    Irritants: \"")
  (emit ".L_str_sym_error_object: .asciz \"error-object\"")
  (emit ".L_str_sym_error: .asciz \"error\"")
  (emit ".L_str_false: .asciz \"#f\"")
  (emit ".L_str_true: .asciz \"#t\"")
  (emit ".L_str_nil: .asciz \"()\"")
  (emit ".L_str_eof: .asciz \"#<eof>\"")
  (emit ".L_str_char_prefix: .asciz \"#\\\\\"")
  (emit ".L_str_newline: .asciz \"newline\"")
  (emit ".L_str_space: .asciz \"space\"")
  (emit ".L_str_tab: .asciz \"tab\"")
  (emit ".L_str_dot: .asciz \" . \"")
  (emit ".L_str_symbol: .asciz \"#<symbol>\"")
  (emit ".L_str_unknown: .asciz \"#<unknown>\"")
  (emit ".L_str_u8_prefix: .asciz \"#u8(\"")
  (emit ".L_str_vec_prefix: .asciz \"#(\"")
  (emit ""))
;;; =======================================================================
;;; ULisp Compiler Pass 143: Native x86-64 Machine Peephole Optimization
;;; Conforms to DSN-33 Architecture Specification & Issue #596
;;; Implements sliding-window local simplifications on L_asm_x86 AST.
;;; =======================================================================

(define (x86-asm-reg? opnd)
  (or (and (symbol? opnd)
           (memq opnd '(rax rbx rcx rdx rsi rdi rbp rsp
                        r8  r9  r10 r11 r12 r13 r14 r15 al)))
      (and (pair? opnd)
           (eq? (car opnd) '%reg))))

(define (x86-asm-zero-imm? opnd)
  (or (eqv? opnd 0)
      (and (pair? opnd)
           (eq? (car opnd) '%imm)
           (eqv? (cadr opnd) 0))))

(define (x86-asm-unconditional-terminator? inst)
  (and (pair? inst)
       (memq (car inst) '(jmp ret))))

(define (x86-asm-label-inst? inst)
  (and (pair? inst)
       (eq? (car inst) '%label)))

(define (x86-peephole-step-window insts)
  (let loop ((rest insts) (acc '()))
    (cond
      ((null? rest)
       (reverse acc))

      ;; -----------------------------------------------------------------
      ;; Rule 1: Redundant Self-Move Elimination
      ;; (mov r r) -> ()
      ;; -----------------------------------------------------------------
      ((and (pair? (car rest))
            (let ((i (car rest)))
              (and (eq? (car i) 'mov)
                   (= (length i) 3)
                   (x86-asm-reg? (cadr i))
                   (equal? (cadr i) (caddr i)))))
       (loop (cdr rest) acc))

      ;; -----------------------------------------------------------------
      ;; Rule 2: Round-Trip Register Move Elimination
      ;; (mov r1 r2) followed immediately by (mov r2 r1) -> (mov r1 r2)
      ;; -----------------------------------------------------------------
      ((and (pair? (cdr rest))
            (pair? (car rest))
            (pair? (cadr rest))
            (let ((i1 (car rest))
                  (i2 (cadr rest)))
              (and (eq? (car i1) 'mov)
                   (eq? (car i2) 'mov)
                   (= (length i1) 3)
                   (= (length i2) 3)
                   (equal? (cadr i1) (caddr i2))
                   (equal? (caddr i1) (cadr i2))
                   (x86-asm-reg? (cadr i1))
                   (x86-asm-reg? (caddr i1)))))
       (loop (cddr rest) (cons (car rest) acc)))

      ;; -----------------------------------------------------------------
      ;; Rule 3: Zero-idiom XOR Optimization
      ;; (mov reg 0) / (mov reg (%imm 0)) -> (xor reg reg)
      ;; -----------------------------------------------------------------
      ((and (pair? (car rest))
            (let ((i (car rest)))
              (and (eq? (car i) 'mov)
                   (= (length i) 3)
                   (x86-asm-reg? (cadr i))
                   (x86-asm-zero-imm? (caddr i)))))
       (let ((reg (cadr (car rest))))
         (loop (cdr rest) (cons (list 'xor reg reg) acc))))

      ;; -----------------------------------------------------------------
      ;; Rule 4: Redundant Jump to Next Immediate Label
      ;; (jmp L1) followed immediately by (%label L1) -> (%label L1)
      ;; -----------------------------------------------------------------
      ((and (pair? (cdr rest))
            (pair? (car rest))
            (pair? (cadr rest))
            (eq? (car (car rest)) 'jmp)
            (eq? (car (cadr rest)) '%label)
            (equal? (cadr (car rest)) (cadr (cadr rest))))
       (loop (cdr rest) acc))

      ;; -----------------------------------------------------------------
      ;; Rule 5: Unreachable Code Elimination (Dead Code Elimination)
      ;; (jmp L) or (ret) followed by non-label instructions up to next label
      ;; -----------------------------------------------------------------
      ((and (x86-asm-unconditional-terminator? (car rest))
            (pair? (cdr rest))
            (not (x86-asm-label-inst? (cadr rest))))
       (let skip ((tail (cdr rest)))
         (cond
           ((null? tail)
            (loop '() (cons (car rest) acc)))
           ((x86-asm-label-inst? (car tail))
            (loop tail (cons (car rest) acc)))
           (else
            (skip (cdr tail))))))

      ;; Fallthrough: Keep instruction unchanged
      (else
       (loop (cdr rest) (cons (car rest) acc))))))

(define (optimize-x86-peephole-insts insts)
  (let loop ((cur insts) (iterations 10))
    (if (<= iterations 0)
        cur
        (let ((next (x86-peephole-step-window cur)))
          (if (equal? cur next)
              cur
              (loop next (- iterations 1)))))))

(define (optimize-x86-peephole-function fn)
  (let* ((lbl (cadr fn))
         (frame-size-entry (assq 'frame-size (cddr fn)))
         (frame-size (if frame-size-entry (cadr frame-size-entry) 0))
         (body-entry (assq 'body (cddr fn)))
         (body (if body-entry (cdr body-entry) '()))
         (opt-body (optimize-x86-peephole-insts body)))
    (list '%asm-function
          lbl
          (list 'frame-size frame-size)
          (cons 'body opt-body))))

(define (optimize-x86-peephole-main m)
  (let* ((frame-size-entry (assq 'frame-size (cdr m)))
         (frame-size (if frame-size-entry (cadr frame-size-entry) 0))
         (body-entry (assq 'body (cdr m)))
         (body (if body-entry (cdr body-entry) '()))
         (opt-body (optimize-x86-peephole-insts body)))
    (list '%asm-main
          (list 'frame-size frame-size)
          (cons 'body opt-body))))

(define (optimize-x86-peephole prog)
  (let* ((strings (assq 'strings (cdr prog)))
         (stackmaps (assq 'stackmaps (cdr prog)))
         (funcs-entry (assq '%asm-functions (cdr prog)))
         (funcs (if funcs-entry (cdr funcs-entry) '()))
         (main-entry (assq '%asm-main (cdr prog))))
    (list '%asm-program
          (if strings strings '(strings ()))
          (if stackmaps stackmaps '(stackmaps ()))
          (cons '%asm-functions (map optimize-x86-peephole-function funcs))
          (if main-entry
              (optimize-x86-peephole-main main-entry)
              '(%asm-main (frame-size 0) (body ()))))))
;;; =======================================================================
;;; ULisp Compiler Pass 7: Native AArch64 (ARM64) Backend Code Generator
;;; Conforms to DSN-33 Architecture Specification & Issue #503
;;; Consumes Pass 6 %lir-program and emits pure GNU AArch64 assembly.
;;; =======================================================================

(define (arm-reg->str reg)
  (case reg
    ((%rax) "x0")
    ((%rdx) "x1")
    ((%rcx) "x2")
    ((%rbx) "x3")
    ((%rdi) "x0")
    ((%rsi) "x1")
    ((%r10) "x10")
    ((%r12) "x19")
    ((%rsp) "sp")
    ((%al)  "w0")
    (else (symbol->string reg))))

(define (arm-w-reg->str reg)
  (case reg
    ((%rax x0) "w0")
    ((%rdx x1) "w1")
    ((%rcx x2) "w2")
    ((%rbx x3) "w3")
    ((%r10 x10) "w10")
    ((%r12 x19) "w19")
    ((%al)  "w0")
    (else
     (let ((s (if (symbol? reg) (symbol->string reg) reg)))
       (if (and (> (string-length s) 1) (char=? (string-ref s 0) #\x))
           (string-append "w" (substring s 1 (string-length s)))
           s)))))

(define (arm-mem-op->str base offset)
  (let ((base-str (arm-reg->str base)))
    (if (symbol? offset)
        (string-append "[" base-str ", " (arm-reg->str offset) "]")
        (string-append "[" base-str ", #" (number->string offset) "]"))))

(define (arm-operand->str opnd)
  (cond
    ((symbol? opnd)
     (arm-reg->str opnd))
    ((integer? opnd)
     (string-append "#" (number->string opnd)))
    ((pair? opnd)
     (let ((tag (car opnd)))
       (case tag
         ((%stack)
          (string-append "[sp, #" (number->string (cadr opnd)) "]"))
         ((%mem)
          (arm-mem-op->str (cadr opnd) (caddr opnd)))
         (else
          (error "Unknown operand in AArch64 backend:" opnd)))))
    (else
     (error "Invalid operand type in AArch64 backend:" opnd))))

(define (arm-condition-code set-inst)
  (cond
    ((string=? set-inst "sete")  "eq")
    ((string=? set-inst "setl")  "lt")
    ((string=? set-inst "setle") "le")
    ((string=? set-inst "setg")  "gt")
    ((string=? set-inst "setge") "ge")
    ((string=? set-inst "setne") "ne")
    (else (error "Unknown set-cc in AArch64 backend:" set-inst))))

(define (emit-arm-boolean-from-set set-inst)
  (let ((cond (arm-condition-code set-inst)))
    (emit (string-append "    cset x0, " cond))
    (emit "    lsl x0, x0, 6")
    (emit "    add x0, x0, 0x2F")))

;;; Block Arguments tracking and parallel copy for SSA LIR (AArch64)
(define *arm-block-params* (cons '() '()))

(define (reset-arm-block-params!)
  (set-car! *arm-block-params* '()))

(define (record-arm-block-params! lbl params)
  (let ((entry (assq lbl (car *arm-block-params*))))
    (if entry
        (set-cdr! entry params)
        (set-car! *arm-block-params* (cons (cons lbl params) (car *arm-block-params*))))))

(define (get-arm-block-params lbl)
  (let ((entry (assq lbl (car *arm-block-params*))))
    (if entry (cdr entry) '())))

(define (scan-arm-blocks! insts)
  (reset-arm-block-params!)
  (for-each
   (lambda (inst)
     (if (and (pair? inst) (eq? (car inst) '%block))
         (record-arm-block-params! (cadr inst) (caddr inst))))
   insts))

(define (arm-param-location idx param)
  (cond
    ((or (eq? param '%rax) (eq? param 'x0)) 'x0)
    ((and (pair? param) (eq? (car param) '%stack)) param)
    (else
     (list '%stack (* -8 (+ idx 2))))))

(define (emit-arm-parallel-copy target-lbl args)
  (let ((params (get-arm-block-params target-lbl)))
    (let loop ((ps params) (as args) (i 0))
      (if (and (pair? ps) (pair? as))
          (let* ((param (car ps))
                 (arg (car as))
                 (loc (arm-param-location i param)))
            (cond
              ((equal? loc arg) #f)
              ((or (eq? loc 'x0) (eq? loc '%rax))
               (if (integer? arg)
                   (emit (string-append "    mov x0, #" (number->string arg)))
                   (emit (string-append "    mov x0, " (arm-operand->str arg)))))
              ((and (pair? loc) (eq? (car loc) '%stack))
               (let ((offset (cadr loc)))
                 (cond
                   ((integer? arg)
                    (emit (string-append "    mov x1, #" (number->string arg)))
                    (emit (string-append "    str x1, [sp, #" (number->string offset) "]")))
                   ((pair? arg)
                    (emit (string-append "    ldr x1, " (arm-operand->str arg)))
                    (emit (string-append "    str x1, [sp, #" (number->string offset) "]")))
                   (else
                    (emit (string-append "    str " (arm-reg->str arg) ", [sp, #" (number->string offset) "]"))))))
              (else
               (emit (string-append "    mov " (arm-reg->str loc) ", " (arm-operand->str arg)))))
            (loop (cdr ps) (cdr as) (+ i 1)))))))

;;; Emits a single LIR instruction to AArch64 assembly
(define (emit-arm-lir-instruction inst)
  (let ((op (car inst)))
    (case op
      ((%label)
       (let ((lbl (cadr inst)))
         (emit "    .p2align 4")
         (emit (string-append (if (symbol? lbl) (symbol->string lbl) lbl) ":"))))

      ((%block)
       (let ((lbl (cadr inst))
             (params (caddr inst))
             (body (cdddr inst)))
         (record-arm-block-params! lbl params)
         (emit "    .p2align 4")
         (emit (string-append (if (symbol? lbl) (symbol->string lbl) lbl) ":"))
         (for-each emit-arm-lir-instruction body)))

      ((%jump)
       (let* ((lbl (cadr inst))
              (args (if (pair? (cddr inst)) (caddr inst) '())))
         (if (pair? args)
             (emit-arm-parallel-copy lbl args))
         (if (and (symbol? lbl)
                  (memq lbl '(%rax %rdx %rcx %rbx %r10 %r12 x0 x1 x2 x3 x10 x19)))
             (emit (string-append "    br " (arm-reg->str lbl)))
             (emit (string-append "    b " (if (symbol? lbl) (symbol->string lbl) lbl))))))

      ((%jump-if-false)
       (let* ((reg (cadr inst))
              (lbl (caddr inst))
              (args (if (pair? (cdddr inst)) (cadddr inst) '())))
         (if (null? args)
             (begin
               (emit (string-append "    cmp " (arm-reg->str reg) ", #0x2F"))
               (emit (string-append "    b.eq " (if (symbol? lbl) (symbol->string lbl) lbl))))
             (let ((cont-lbl (unique-label-sym "L_cont_")))
               (emit (string-append "    cmp " (arm-reg->str reg) ", #0x2F"))
               (emit (string-append "    b.ne " (symbol->string cont-lbl)))
               (emit-arm-parallel-copy lbl args)
               (emit (string-append "    b " (if (symbol? lbl) (symbol->string lbl) lbl)))
               (emit (string-append (symbol->string cont-lbl) ":"))))))

      ((%jump-if)
       (let* ((reg (cadr inst))
              (then-lbl (caddr inst))
              (then-args (cadddr inst))
              (rest-else (cdr (cdddr inst)))
              (else-lbl (car rest-else))
              (else-args (cadr rest-else))
              (else-tramline (unique-label-sym "L_else_tramline_")))
         (emit (string-append "    cmp " (arm-reg->str reg) ", #0x2F"))
         (emit (string-append "    b.eq " (symbol->string else-tramline)))
         (if (pair? then-args)
             (emit-arm-parallel-copy then-lbl then-args))
         (emit (string-append "    b " (if (symbol? then-lbl) (symbol->string then-lbl) then-lbl)))
         (emit (string-append (symbol->string else-tramline) ":"))
         (if (pair? else-args)
             (emit-arm-parallel-copy else-lbl else-args))
         (emit (string-append "    b " (if (symbol? else-lbl) (symbol->string else-lbl) else-lbl)))))

      ((%jump-if-zero)
       (let ((lbl (cadr inst)))
         (emit (string-append "    b.eq " (if (symbol? lbl) (symbol->string lbl) lbl)))))

      ((%return)
       (emit "    ret"))

      ((%mov)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (cond
           ((integer? src)
            (if (and (>= src -65535) (<= src 65535))
                (emit (string-append "    mov " (arm-reg->str dst) ", #" (number->string src)))
                (emit (string-append "    ldr " (arm-reg->str dst) ", =" (number->string src)))))
           ((pair? src)
            (emit (string-append "    ldr " (arm-reg->str dst) ", " (arm-operand->str src))))
           (else
            (emit (string-append "    mov " (arm-reg->str dst) ", " (arm-reg->str src)))))))

      ((%load)
       (let ((dst (cadr inst))
             (base (caddr inst))
             (offset (cadddr inst)))
         (emit (string-append "    ldr " (arm-reg->str dst) ", " (arm-mem-op->str base offset)))))

      ((%store)
       (let ((base (cadr inst))
             (offset (caddr inst))
             (src (cadddr inst)))
         (emit (string-append "    str " (arm-reg->str src) ", " (arm-mem-op->str base offset)))))

      ((%store-byte)
       (let ((base (cadr inst))
             (offset (caddr inst))
             (src (cadddr inst)))
         (cond
           ((and (number? src) (= src 0))
            (emit (string-append "    strb wzr, " (arm-mem-op->str base offset))))
           ((number? src)
            (emit (string-append "    mov w9, #" (number->string src)))
            (emit (string-append "    strb w9, " (arm-mem-op->str base offset))))
           (else
            (emit (string-append "    strb " (arm-w-reg->str src) ", " (arm-mem-op->str base offset)))))))

      ((%load-byte-zx)
       (let ((dst (cadr inst))
             (base (caddr inst))
             (offset (cadddr inst)))
         (emit (string-append "    ldrb " (arm-w-reg->str dst) ", " (arm-mem-op->str base offset)))))

      ((%add %raw-add)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (if (number? src)
             (if (and (>= src 0) (<= src 4095))
                 (emit (string-append "    add " (arm-reg->str dst) ", " (arm-reg->str dst) ", #" (number->string src)))
                 (begin
                   (emit (string-append "    ldr x9, =" (number->string src)))
                   (emit (string-append "    add " (arm-reg->str dst) ", " (arm-reg->str dst) ", x9"))))
             (emit (string-append "    add " (arm-reg->str dst) ", " (arm-reg->str dst) ", " (arm-operand->str src))))))

      ((%sub %raw-sub)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (if (number? src)
             (if (and (>= src 0) (<= src 4095))
                 (emit (string-append "    sub " (arm-reg->str dst) ", " (arm-reg->str dst) ", #" (number->string src)))
                 (begin
                   (emit (string-append "    ldr x9, =" (number->string src)))
                   (emit (string-append "    sub " (arm-reg->str dst) ", " (arm-reg->str dst) ", x9"))))
             (emit (string-append "    sub " (arm-reg->str dst) ", " (arm-reg->str dst) ", " (arm-operand->str src))))))

      ((%neg)
       (let ((dst (cadr inst)))
         (emit (string-append "    neg " (arm-reg->str dst) ", " (arm-reg->str dst)))))

      ((%imul %raw-mul)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (cond
           ((pair? src)
            (emit (string-append "    ldr x9, " (arm-operand->str src)))
            (emit (string-append "    mul " (arm-reg->str dst) ", " (arm-reg->str dst) ", x9")))
           ((number? src)
            (emit (string-append "    ldr x9, =" (number->string src)))
            (emit (string-append "    mul " (arm-reg->str dst) ", " (arm-reg->str dst) ", x9")))
           (else
            (emit (string-append "    mul " (arm-reg->str dst) ", " (arm-reg->str dst) ", " (arm-reg->str src)))))))

      ((%box-fixnum)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (emit (string-append "    lsl " (arm-reg->str dst) ", " (arm-reg->str src) ", #2"))))

      ((%unbox-fixnum)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (emit (string-append "    asr " (arm-reg->str dst) ", " (arm-reg->str src) ", #2"))))

      ((%cqo)
       ;; In AArch64, 64-bit sdiv does not require cqo sign extension; no-op.
       #f)

      ((%idiv)
       (let ((src (cadr inst)))
         (let ((src-str (arm-operand->str src)))
           (emit (string-append "    sdiv x9, x0, " src-str))
           (emit (string-append "    msub x1, x9, " src-str ", x0"))
           (emit "    mov x0, x9"))))

      ((%inc)
       (let ((dst (cadr inst)))
         (emit (string-append "    add " (arm-reg->str dst) ", " (arm-reg->str dst) ", #1"))))

      ((%shl)
       (let ((dst (cadr inst))
             (count (caddr inst)))
         (emit (string-append "    lsl " (arm-reg->str dst) ", " (arm-reg->str dst) ", #" (number->string count)))))

      ((%shr)
       (let ((dst (cadr inst))
             (count (caddr inst)))
         (emit (string-append "    lsr " (arm-reg->str dst) ", " (arm-reg->str dst) ", #" (number->string count)))))

      ((%sar)
       (let ((dst (cadr inst))
             (count (caddr inst)))
         (emit (string-append "    asr " (arm-reg->str dst) ", " (arm-reg->str dst) ", #" (number->string count)))))

      ((%bit-and)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (if (number? src)
             (begin
               (emit (string-append "    ldr x9, =" (number->string src)))
               (emit (string-append "    and " (arm-reg->str dst) ", " (arm-reg->str dst) ", x9")))
             (emit (string-append "    and " (arm-reg->str dst) ", " (arm-reg->str dst) ", " (arm-reg->str src))))))

      ((%bit-or)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (if (number? src)
             (begin
               (emit (string-append "    ldr x9, =" (number->string src)))
               (emit (string-append "    orr " (arm-reg->str dst) ", " (arm-reg->str dst) ", x9")))
             (emit (string-append "    orr " (arm-reg->str dst) ", " (arm-reg->str dst) ", " (arm-reg->str src))))))

      ((%bit-xor)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (if (number? src)
             (begin
               (emit (string-append "    ldr x9, =" (number->string src)))
               (emit (string-append "    eor " (arm-reg->str dst) ", " (arm-reg->str dst) ", x9")))
             (emit (string-append "    eor " (arm-reg->str dst) ", " (arm-reg->str dst) ", " (arm-reg->str src))))))

      ((%cmp %raw-cmp)
       (let ((s1 (cadr inst))
             (s2 (caddr inst)))
         (if (number? s2)
             (if (and (>= s2 0) (<= s2 4095))
                 (emit (string-append "    cmp " (arm-reg->str s1) ", #" (number->string s2)))
                 (begin
                   (emit (string-append "    ldr x9, =" (number->string s2)))
                   (emit (string-append "    cmp " (arm-reg->str s1) ", x9"))))
             (emit (string-append "    cmp " (arm-reg->str s1) ", " (arm-operand->str s2))))))

      ((%set-boolean)
       (let ((cc (caddr inst)))
         (emit-arm-boolean-from-set cc)))

      ((%alloc)
       (let ((dst (cadr inst))
             (bytes (caddr inst))
             (tag (cadddr inst)))
         (if (= tag 0)
             (emit (string-append "    mov " (arm-reg->str dst) ", x19"))
             (emit (string-append "    add " (arm-reg->str dst) ", x19, #" (number->string tag))))
         (emit (string-append "    add x19, x19, #" (number->string bytes)))))

      ((%alloc-stack)
       (let ((dst (cadr inst))
             (offset (caddr inst))
             (tag (cadddr inst)))
         (let ((disp (+ offset tag)))
           (if (>= disp 0)
               (emit (string-append "    add " (arm-reg->str dst) ", sp, #" (number->string disp)))
               (emit (string-append "    sub " (arm-reg->str dst) ", sp, #" (number->string (- 0 disp))))))))

      ((%code-ref)
       (let ((dst (cadr inst))
             (lbl (caddr inst)))
         (let ((lbl-str (if (symbol? lbl) (symbol->string lbl) lbl))
               (dst-str (arm-reg->str dst)))
           (emit (string-append "    adrp " dst-str ", " lbl-str))
           (emit (string-append "    add " dst-str ", " dst-str ", :lo12:" lbl-str)))))

      ((%str-ref)
       (let ((dst (cadr inst))
             (lbl (caddr inst)))
         (let ((lbl-str (if (symbol? lbl) (symbol->string lbl) lbl))
               (dst-str (arm-reg->str dst)))
           (emit (string-append "    adrp " dst-str ", " lbl-str))
           (emit (string-append "    add " dst-str ", " dst-str ", :lo12:" lbl-str))
           (emit (string-append "    add " dst-str ", " dst-str ", #3")))))

      ((%c-call)
       (let* ((func (cadr inst))
              (frame-shift (caddr inst))
              (total-shift (+ frame-shift 8)))
         (emit (string-append "    sub sp, sp, #" (number->string total-shift)))
         (emit "    str x30, [sp]")
         (emit (string-append "    bl " (if (symbol? func) (symbol->raw-name func) func)))
         (emit "    ldr x30, [sp]")
         (emit (string-append "    add sp, sp, #" (number->string total-shift)))))

      ((%call-closure)
       (let* ((frame-shift (cadr inst))
              (safepoint (if (pair? (cddr inst)) (caddr inst) #f))
              (total-shift (+ frame-shift 8)))
         (emit (string-append "    sub sp, sp, #" (number->string total-shift)))
         (emit "    str x30, [sp]")
         (emit "    ldr x1, [x10, #-1]")
         (emit "    blr x1")
         (if safepoint
             (emit (string-append (if (symbol? safepoint) (symbol->string safepoint) safepoint) ":")))
         (emit "    ldr x30, [sp]")
         (emit (string-append "    add sp, sp, #" (number->string total-shift)))))

      ((%direct-call)
       (let* ((label (cadr inst))
              (lbl-str (if (symbol? label) (symbol->string label) label))
              (frame-shift (caddr inst))
              (safepoint (if (pair? (cdddr inst)) (cadddr inst) #f))
              (total-shift (+ frame-shift 8)))
         (emit (string-append "    sub sp, sp, #" (number->string total-shift)))
         (emit "    str x30, [sp]")
         (emit "    mov x10, #0")
         (emit (string-append "    bl " lbl-str))
         (if safepoint
             (emit (string-append (if (symbol? safepoint) (symbol->string safepoint) safepoint) ":")))
         (emit "    ldr x30, [sp]")
         (emit (string-append "    add sp, sp, #" (number->string total-shift)))))

      ((%direct-jump)
       (let* ((label (cadr inst))
              (lbl-str (if (symbol? label) (symbol->string label) label)))
         (emit "    mov x10, #0")
         (emit (string-append "    b " lbl-str))))

      ((%global-ref)
       (let ((reg (cadr inst))
             (var (caddr inst)))
         (let ((g-lbl (string-append "ulisp_gvar_" (sanitize-label-str (symbol->string var)))))
           (emit (string-append "    adrp x9, " g-lbl))
           (emit (string-append "    add x9, x9, :lo12:" g-lbl))
           (emit (string-append "    ldr " (arm-reg->str reg) ", [x9]")))))

      ((%global-set!)
       (let ((var (cadr inst))
             (reg (caddr inst)))
         (let ((g-lbl (string-append "ulisp_gvar_" (sanitize-label-str (symbol->string var)))))
           (emit (string-append "    adrp x9, " g-lbl))
           (emit (string-append "    add x9, x9, :lo12:" g-lbl))
           (emit (string-append "    str " (arm-reg->str reg) ", [x9]")))))

      ((%push-handler)
       (let ((catch-lbl (cadr inst))
             (frame-si (caddr inst))
             (handler-si (cadddr inst)))
         (let ((lbl-str (if (symbol? catch-lbl) (symbol->string catch-lbl) catch-lbl)))
           (emit (string-append "    adrp x9, " lbl-str))
           (emit (string-append "    add x9, x9, :lo12:" lbl-str))
           (emit (string-append "    str x9, " (arm-mem-op->str '%rsp (+ frame-si 24))))
           (emit "    adrp x1, ulisp_handler_chain")
           (emit "    add x1, x1, :lo12:ulisp_handler_chain")
           (emit "    ldr x2, [x1]")
           (emit (string-append "    str x2, " (arm-mem-op->str '%rsp frame-si)))
           (emit "    mov x9, sp")
           (emit (string-append "    str x9, " (arm-mem-op->str '%rsp (+ frame-si 8))))
           (emit (string-append "    str x29, " (arm-mem-op->str '%rsp (+ frame-si 16))))
           (emit (string-append "    ldr x9, " (arm-mem-op->str '%rsp handler-si)))
           (emit (string-append "    str x9, " (arm-mem-op->str '%rsp (+ frame-si 32))))
           (emit (string-append "    sub x9, sp, #" (number->string (- 0 frame-si))))
           (emit "    str x9, [x1]"))))

      ((%pop-handler)
       (let ((frame-si (cadr inst)))
         (emit "    adrp x1, ulisp_handler_chain")
         (emit "    add x1, x1, :lo12:ulisp_handler_chain")
         (emit (string-append "    ldr x2, " (arm-mem-op->str '%rsp frame-si)))
         (emit "    str x2, [x1]")))

      ((%raise)
       (emit "    adrp x1, ulisp_handler_chain")
       (emit "    add x1, x1, :lo12:ulisp_handler_chain")
       (emit "    ldr x3, [x1]")
       (emit "    cbz x3, .L_arm_unhandled_exn")
       (emit "    ldr x2, [x3]")
       (emit "    str x2, [x1]")
       (emit "    ldr x9, [x3, #8]")
       (emit "    mov sp, x9")
       (emit "    ldr x29, [x3, #16]")
       (emit "    ldr x10, [x3, #24]")
       (emit "    ldr x1, [x3, #32]")
       (emit "    mov x10, x1")
       (emit "    br x10"))

      ((%set-values-count)
       (let ((cnt (cadr inst)))
         (emit "    adrp x1, ulisp_values_count")
         (emit "    add x1, x1, :lo12:ulisp_values_count")
         (emit (string-append "    mov x2, #" (number->string cnt)))
         (emit "    str x2, [x1]")))

      ((%store-values-buf)
       (let ((base-si (cadr inst))
             (count (caddr inst)))
         (emit "    adrp x1, ulisp_values_buf")
         (emit "    add x1, x1, :lo12:ulisp_values_buf")
         (let loop ((i 0))
           (if (< i count)
               (let ((offset (+ base-si (* -8 i)))
                     (buf-disp (* 8 i)))
                 (emit (string-append "    ldr x0, " (arm-mem-op->str '%rsp offset)))
                 (emit (string-append "    str x0, [x1, #" (number->string buf-disp) "]"))
                 (loop (+ i 1)))))))

      ((%dispatch-consumer)
       (let* ((consumer-si (cadr inst))
              (aligned-si (caddr inst))
              (frame-shift (cadddr inst))
              (total-shift (+ frame-shift 8))
              (exit-lbl (unique-label-sym "L_arm_cwv_exit_"))
              (call-0-lbl (unique-label-sym "L_arm_cwv_call_0_"))
              (call-1-lbl (unique-label-sym "L_arm_cwv_call_1_"))
              (call-2-lbl (unique-label-sym "L_arm_cwv_call_2_"))
              (call-3-lbl (unique-label-sym "L_arm_cwv_call_3_"))
              (call-4-lbl (unique-label-sym "L_arm_cwv_call_4_"))
              (exit-str (symbol->string exit-lbl)))
         (emit "    adrp x1, ulisp_values_count")
         (emit "    add x1, x1, :lo12:ulisp_values_count")
         (emit "    ldr x2, [x1]")
         (emit "    mov x3, #1")
         (emit "    str x3, [x1]")
         (emit (string-append "    ldr x10, " (arm-mem-op->str '%rsp consumer-si)))
         (emit "    adrp x3, ulisp_values_buf")
         (emit "    add x3, x3, :lo12:ulisp_values_buf")
         (emit "    cmp x2, #1")
         (emit (string-append "    b.eq " (symbol->string call-1-lbl)))
         (emit "    cmp x2, #2")
         (emit (string-append "    b.eq " (symbol->string call-2-lbl)))
         (emit (string-append "    cbz x2, " (symbol->string call-0-lbl)))
         (emit "    cmp x2, #3")
         (emit (string-append "    b.eq " (symbol->string call-3-lbl)))
         (emit "    cmp x2, #4")
         (emit (string-append "    b.eq " (symbol->string call-4-lbl)))
         ;; 0 args
         (emit (string-append (symbol->string call-0-lbl) ":"))
         (emit (string-append "    sub sp, sp, #" (number->string total-shift)))
         (emit "    str x30, [sp]")
         (emit "    ldr x1, [x10, #-1]")
         (emit "    blr x1")
         (emit "    ldr x30, [sp]")
         (emit (string-append "    add sp, sp, #" (number->string total-shift)))
         (emit (string-append "    b " exit-str))
         ;; 1 arg (x0 has the value)
         (emit (string-append (symbol->string call-1-lbl) ":"))
         (emit (string-append "    str x0, " (arm-mem-op->str '%rsp aligned-si)))
         (emit (string-append "    sub sp, sp, #" (number->string total-shift)))
         (emit "    str x30, [sp]")
         (emit "    ldr x1, [x10, #-1]")
         (emit "    blr x1")
         (emit "    ldr x30, [sp]")
         (emit (string-append "    add sp, sp, #" (number->string total-shift)))
         (emit (string-append "    b " exit-str))
         ;; 2 args
         (emit (string-append (symbol->string call-2-lbl) ":"))
         (emit "    ldr x0, [x3]")
         (emit (string-append "    str x0, " (arm-mem-op->str '%rsp (+ aligned-si 8))))
         (emit "    ldr x0, [x3, #8]")
         (emit (string-append "    str x0, " (arm-mem-op->str '%rsp aligned-si)))
         (emit (string-append "    sub sp, sp, #" (number->string total-shift)))
         (emit "    str x30, [sp]")
         (emit "    ldr x1, [x10, #-1]")
         (emit "    blr x1")
         (emit "    ldr x30, [sp]")
         (emit (string-append "    add sp, sp, #" (number->string total-shift)))
         (emit (string-append "    b " exit-str))
         ;; 3 args
         (emit (string-append (symbol->string call-3-lbl) ":"))
         (emit "    ldr x0, [x3]")
         (emit (string-append "    str x0, " (arm-mem-op->str '%rsp (+ aligned-si 16))))
         (emit "    ldr x0, [x3, #8]")
         (emit (string-append "    str x0, " (arm-mem-op->str '%rsp (+ aligned-si 8))))
         (emit "    ldr x0, [x3, #16]")
         (emit (string-append "    str x0, " (arm-mem-op->str '%rsp aligned-si)))
         (emit (string-append "    sub sp, sp, #" (number->string total-shift)))
         (emit "    str x30, [sp]")
         (emit "    ldr x1, [x10, #-1]")
         (emit "    blr x1")
         (emit "    ldr x30, [sp]")
         (emit (string-append "    add sp, sp, #" (number->string total-shift)))
         (emit (string-append "    b " exit-str))
         ;; 4 args
         (emit (string-append (symbol->string call-4-lbl) ":"))
         (emit "    ldr x0, [x3]")
         (emit (string-append "    str x0, " (arm-mem-op->str '%rsp (+ aligned-si 24))))
         (emit "    ldr x0, [x3, #8]")
         (emit (string-append "    str x0, " (arm-mem-op->str '%rsp (+ aligned-si 16))))
         (emit "    ldr x0, [x3, #16]")
         (emit (string-append "    str x0, " (arm-mem-op->str '%rsp (+ aligned-si 8))))
         (emit "    ldr x0, [x3, #24]")
         (emit (string-append "    str x0, " (arm-mem-op->str '%rsp aligned-si)))
         (emit (string-append "    sub sp, sp, #" (number->string total-shift)))
         (emit "    str x30, [sp]")
         (emit "    ldr x1, [x10, #-1]")
         (emit "    blr x1")
         (emit "    ldr x30, [sp]")
         (emit (string-append "    add sp, sp, #" (number->string total-shift)))
         (emit (string-append "    b " exit-str))
         (emit (string-append exit-str ":"))))

      ((%capture-cc)
       (let* ((ret-lbl (cadr inst))
              (k-si (caddr inst))
              (lbl-str (if (symbol? ret-lbl) (symbol->string ret-lbl) ret-lbl))
              (loop-lbl (unique-label-sym "L_arm_copy_")))
         (emit "    adrp x2, ulisp_stack_base")
         (emit "    ldr x2, [x2, :lo12:ulisp_stack_base]")
         (emit "    mov x3, sp")
         (emit "    sub x2, x2, x3")
         (emit "    add x4, x2, #111")
         (emit "    and x4, x4, #~15")
         (emit "    mov x0, x19")
         (emit "    add x19, x19, x4")
         (emit "    adrp x5, ulisp_continuation_invoke")
         (emit "    add x5, x5, :lo12:ulisp_continuation_invoke")
         (emit "    str x5, [x0]")
         (emit "    str x2, [x0, #8]")
         (emit "    str x3, [x0, #16]")
         (emit "    str x29, [x0, #24]")
         (emit (string-append "    adrp x5, " lbl-str))
         (emit (string-append "    add x5, x5, :lo12:" lbl-str))
         (emit "    str x5, [x0, #72]")
         (emit "    adrp x5, ulisp_handler_chain")
         (emit "    ldr x6, [x5, :lo12:ulisp_handler_chain]")
         (emit "    str x6, [x0, #80]")
         (emit "    add x1, x0, #96")
         (emit "    mov x7, x3")
         (emit "    mov x8, x2")
         (emit (string-append (symbol->string loop-lbl) ":"))
         (emit "    cbz x8, 1f")
         (emit "    ldrb w9, [x7], #1")
         (emit "    strb w9, [x1], #1")
         (emit "    sub x8, x8, #1")
         (emit (string-append "    b " (symbol->string loop-lbl)))
         (emit "1:")
         (emit "    orr x0, x0, #1")
         (emit (string-append "    str x0, " (arm-mem-op->str '%rsp k-si)))))

      (else
       (error "Unknown LIR opcode in AArch64 backend:" inst)))))

;;; Emits assembly for a single %lir-function
(define (emit-arm-function fn)
  (let* ((label (cadr fn))
         (label-str (if (symbol? label) (symbol->string label) label))
         (body (cdr (assq 'body (cddr fn)))))
    (scan-arm-blocks! body)
    (emit "    .p2align 4")
    (emit (string-append label-str ":"))
    ;; Callee prologue: self closure pointer was in x10
    ;; Store self closure pointer at [sp, #-8]
    (emit "    str x10, [sp, #-8]")
    (for-each emit-arm-lir-instruction body)))

;;; Pass 7 Entrypoint: Takes %lir-program and emits complete GNU AArch64 assembly
(define (emit-aarch64 prog gc-mode)
  (let* ((funcs-clause (assq '%lir-functions (cdr prog)))
         (funcs (if funcs-clause (cdr funcs-clause) '()))
         (main-clause (assq '%lir-main (cdr prog)))
         (main-body (cdr (assq 'body (cdr main-clause)))))
    (emit "    .text")
    (emit "    .globl scheme_entry")
    (emit "    .type scheme_entry, @function")
    (emit "    .p2align 4")
    (emit "scheme_entry:")
    (emit "    stp x29, x30, [sp, #-32]!")
    (emit "    mov x29, sp")
    (emit "    str x19, [sp, #16]")
    (emit "    adrp x2, ulisp_stack_base")
    (emit "    ldr x3, [x2, :lo12:ulisp_stack_base]")
    (emit "    cbnz x3, 1f")
    (emit "    mov x3, sp")
    (emit "    str x3, [x2, :lo12:ulisp_stack_base]")
    (emit "1:")
    (emit "    mov x19, x0")          ; x0 contains heap_base from C runtime
    (scan-arm-blocks! main-body)
    (for-each (lambda (inst)
                (if (not (eq? (car inst) '%return))
                    (emit-arm-lir-instruction inst)))
              main-body)
    (emit "    ldr x19, [sp, #16]")
    (emit "    ldp x29, x30, [sp], #32")
    (emit "    ret")
    ;; Emit all lifted procedure definitions in sequence
    (for-each emit-arm-function funcs)
    ;; Emit stackmap metadata table in .rodata section
    (let* ((stackmaps-clause (assq 'stackmaps (cdr prog)))
           (safepoints (if stackmaps-clause (cadr stackmaps-clause) '())))
      (emit "    .section .rodata")
      (emit "    .p2align 3")
      (emit "    .globl __ulisp_stackmap_table")
      (emit "__ulisp_stackmap_table:")
      (emit (string-append "    .xword " (number->string (length safepoints))))
      (for-each (lambda (sp)
                  (let ((lbl (car sp))
                        (frame-size (cadr sp))
                        (bitmap (caddr sp)))
                    (emit (string-append "    .xword " (if (symbol? lbl) (symbol->string lbl) lbl)))
                    (emit (string-append "    .xword " (number->string frame-size)))
                    (emit (string-append "    .xword " (number->string bitmap)))))
                safepoints))
    ;; Emit all string literals in .rodata section
    (if (not (null? (car *strings*)))
        (let loop ((ss (reverse (car *strings*))))
          (if (not (null? ss))
              (let ((entry (car ss)))
                (emit "    .p2align 3")
                (emit (string-append (car entry) ":"))
                (emit (string-append "    .asciz \"" (escape-gas-string (cdr entry)) "\""))
                (loop (cdr ss))))))
    (emit "    .p2align 2")
    (emit ".L_arm_unhandled_exn:")
    (emit "    mov x0, #1")
    (emit "    mov x8, #93")               ; sys_exit on aarch64
    (emit "    svc #0")
    (emit "    .p2align 2")
    (emit "    .globl ulisp_continuation_invoke")
    (emit "    .type ulisp_continuation_invoke, @function")
    (emit "ulisp_continuation_invoke:")
    (emit "    ldr x0, [sp, #8]")
    (emit "    sub x10, x10, #1")
    (emit "    ldr x2, [x10, #8]")
    (emit "    ldr x3, [x10, #16]")
    (emit "    ldr x29, [x10, #24]")
    (emit "    ldr x30, [x10, #72]")
    (emit "    ldr x6,  [x10, #80]")
    (emit "    adrp x5, ulisp_handler_chain")
    (emit "    str x6, [x5, :lo12:ulisp_handler_chain]")
    (emit "    add x1, x10, #96")
    (emit "    mov x7, x3")
    (emit "    mov x8, x2")
    (emit "2:")
    (emit "    cbz x8, 3f")
    (emit "    ldrb w9, [x1], #1")
    (emit "    strb w9, [x7], #1")
    (emit "    sub x8, x8, #1")
    (emit "    b 2b")
    (emit "3:")
    (emit "    mov sp, x3")
    (emit "    br x30")
    (emit "    .bss")
    (emit "    .align 3")
    (emit "    .globl ulisp_stack_base")
    (emit "ulisp_stack_base:")
    (emit "    .xword 0")
    (emit "    .align 3")
    (emit "    .globl ulisp_handler_chain")
    (emit "ulisp_handler_chain:")
    (emit "    .xword 0")
    (emit "    .align 3")
    (emit "    .globl ulisp_values_count")
    (emit "ulisp_values_count:")
    (emit "    .xword 0")
    (emit "    .align 3")
    (emit "    .globl ulisp_values_buf")
    (emit "ulisp_values_buf:")
    (emit "    .zero 512")
    (let loop ((gvs (car *top-level-vars*)))
      (if (pair? gvs)
          (let ((v (car gvs)))
            (let ((g-lbl (string-append "ulisp_gvar_" (sanitize-label-str (symbol->string v)))))
              (emit "    .align 3")
              (emit (string-append "    .globl " g-lbl))
              (emit (string-append "    .weak " g-lbl))
              (emit (string-append g-lbl ":"))
              (emit "    .xword 0")
              (loop (cdr gvs))))))
    (emit "    .section .note.GNU-stack,\"\",@progbits")))
;;; =======================================================================
;;; ULisp Compiler Pass 7b: Portable C / WebAssembly Backend Code Generator
;;; Conforms to DSN-33 Architecture Specification & Issue #504
;;; Consumes Pass 6 %lir-program and emits ANSI C99 source code.
;;; =======================================================================

(define (c-target-directive? form)
  (and (pair? form)
       (eq? (car form) '!target)
       (pair? (cdr form))
       (eq? (cadr form) 'c)))

(define (c-sanitize-label lbl)
  (let* ((str (if (symbol? lbl) (symbol->string lbl) lbl))
         (clean (sanitize-label-str str))
         (len (string-length clean)))
    (if (and (> len 0) (char=? (string-ref clean 0) #\.))
        (let ((res (make-string (+ len 5))))
          (string-set! res 0 #\u)
          (string-set! res 1 #\l)
          (string-set! res 2 #\i)
          (string-set! res 3 #\s)
          (string-set! res 4 #\p)
          (string-set! res 5 #\_)
          (let loop ((i 1))
            (if (< i len)
                (let ((c (string-ref clean i)))
                  (string-set! res (+ i 5) (if (char=? c #\.) #\_ c))
                  (loop (+ i 1)))
                res)))
        clean)))

(define (c-reg->str reg)
  (case reg
    ((%rax) "reg_rax")
    ((%rbx) "reg_rbx")
    ((%rcx) "reg_rcx")
    ((%rdx) "reg_rdx")
    ((%rsi) "reg_rsi")
    ((%rdi) "reg_rdi")
    ((%r10) "reg_r10")
    ((%r12) "reg_r12")
    ((%r13) "reg_r13")
    ((%r14) "reg_r14")
    ((%r15) "reg_r15")
    ((%rsp) "reg_rsp")
    ((%al)  "((uint8_t)reg_rax)")
    (else (c-sanitize-label reg))))

(define (c-base-ptr-str base)
  (case base
    ((%rsp) "reg_rsp")
    ((%r12) "reg_r12")
    (else (string-append "((char *)(uintptr_t)" (c-reg->str base) ")"))))

(define (c-mem-ref base offset)
  (let ((base-str (c-base-ptr-str base))
        (off-str (if (number? offset) (number->string offset) (c-reg->str offset))))
    (string-append "(*(uint64_t *)(" base-str " + (" off-str ")))")))

(define (c-mem-byte-ref base offset)
  (let ((base-str (c-base-ptr-str base))
        (off-str (if (number? offset) (number->string offset) (c-reg->str offset))))
    (string-append "(*(uint8_t *)(" base-str " + (" off-str ")))")))

(define (c-operand->str opnd)
  (cond
    ((symbol? opnd)
     (c-reg->str opnd))
    ((integer? opnd)
     (number->string opnd))
    ((pair? opnd)
     (let ((tag (car opnd)))
       (case tag
         ((%reg)
          (c-reg->str (cadr opnd)))
         ((%stack)
          (c-mem-ref '%rsp (cadr opnd)))
         ((%mem)
          (c-mem-ref (cadr opnd) (caddr opnd)))
         (else
          (error "Unknown operand in C backend:" opnd)))))
    (else
     (error "Invalid operand type in C backend:" opnd))))

;;; Block Arguments tracking and parallel copy for SSA LIR (C Backend)
(define *c-block-params* (cons '() '()))

(define (reset-c-block-params!)
  (set-car! *c-block-params* '()))

(define (record-c-block-params! lbl params)
  (let ((entry (assq lbl (car *c-block-params*))))
    (if entry
        (set-cdr! entry params)
        (set-car! *c-block-params* (cons (cons lbl params) (car *c-block-params*))))))

(define (get-c-block-params lbl)
  (let ((entry (assq lbl (car *c-block-params*))))
    (if entry (cdr entry) '())))

(define (scan-c-blocks! insts)
  (reset-c-block-params!)
  (for-each
   (lambda (inst)
     (if (and (pair? inst) (eq? (car inst) '%block))
         (record-c-block-params! (cadr inst) (caddr inst))))
   insts))

(define (c-param-location idx param)
  (cond
    ((memq param '(%rax %rbx %rcx %rdx %rsi %rdi %rbp %rsp %r8 %r9 %r10 %r11 %r12 %r13 %r14 %r15))
     param)
    ((and (pair? param) (eq? (car param) '%reg))
     (cadr param))
    ((and (pair? param) (eq? (car param) '%stack)) param)
    (else
     (list '%stack (* -8 (+ idx 2))))))

(define (emit-c-parallel-copy target-lbl args)
  (let ((params (get-c-block-params target-lbl)))
    (let loop ((ps params) (as args) (i 0))
      (if (and (pair? ps) (pair? as))
          (let* ((param (car ps))
                 (arg (car as))
                 (loc (c-param-location i param)))
            (cond
              ((equal? loc arg) #f)
              ((eq? loc '%rax)
               (emit (string-append "    reg_rax = " (c-operand->str arg) ";")))
              (else
               (emit (string-append "    " (c-operand->str loc) " = " (c-operand->str arg) ";"))))
            (loop (cdr ps) (cdr as) (+ i 1)))))))

;;; Emits a single LIR instruction to ANSI C statement
(define (emit-c-instruction inst)
  (let ((op (car inst)))
    (case op
      ((%label)
       (let ((lbl (cadr inst)))
         (emit (string-append (c-sanitize-label lbl) ":;"))))

      ((%block)
       (let ((lbl (cadr inst))
             (params (caddr inst))
             (body (cdddr inst)))
         (record-c-block-params! lbl params)
         (emit (string-append (c-sanitize-label lbl) ":;"))
         (for-each emit-c-instruction body)))

      ((%jump)
       (let* ((lbl (cadr inst))
              (args (if (pair? (cddr inst)) (caddr inst) '())))
         (if (pair? args)
             (emit-c-parallel-copy lbl args))
         (if (or (eq? lbl '%rdx) (eq? lbl '%rax) (eq? lbl '%rcx))
             (emit (string-append "    ((void (*)(void))(uintptr_t)" (c-reg->str lbl) ")(); return;"))
             (emit (string-append "    goto " (c-sanitize-label lbl) ";")))))

      ((%jump-if-false)
       (let* ((reg (cadr inst))
              (lbl (caddr inst))
              (args (if (pair? (cdddr inst)) (cadddr inst) '())))
         (if (null? args)
             (emit (string-append "    if (" (c-reg->str reg) " == 0x2F) goto " (c-sanitize-label lbl) ";"))
             (begin
               (emit (string-append "    if (" (c-reg->str reg) " == 0x2F) {"))
               (emit-c-parallel-copy lbl args)
               (emit (string-append "        goto " (c-sanitize-label lbl) ";"))
               (emit "    }")))))

      ((%jump-cond)
       (let* ((raw-cc (cadr inst))
              (cc (if (symbol? raw-cc) (symbol->string raw-cc) raw-cc))
              (lbl (caddr inst))
              (cond-expr
               (cond
                 ((string=? cc "jne") "cmp_s1 != cmp_s2")
                 ((string=? cc "je")  "cmp_s1 == cmp_s2")
                 ((string=? cc "jge") "(int64_t)cmp_s1 >= (int64_t)cmp_s2")
                 ((string=? cc "jg")  "(int64_t)cmp_s1 > (int64_t)cmp_s2")
                 ((string=? cc "jle") "(int64_t)cmp_s1 <= (int64_t)cmp_s2")
                 ((string=? cc "jl")  "(int64_t)cmp_s1 < (int64_t)cmp_s2")
                 (else (error "Unknown jump-cond in C backend:" cc)))))
         (emit (string-append "    if (" cond-expr ") goto " (c-sanitize-label lbl) ";"))))

      ((%jump-if)
       (let* ((reg (cadr inst))
              (then-lbl (caddr inst))
              (then-args (cadddr inst))
              (rest-else (cdr (cdddr inst)))
              (else-lbl (car rest-else))
              (else-args (cadr rest-else)))
         (emit (string-append "    if (" (c-reg->str reg) " != 0x2F) {"))
         (if (pair? then-args)
             (emit-c-parallel-copy then-lbl then-args))
         (emit (string-append "        goto " (c-sanitize-label then-lbl) ";"))
         (emit "    } else {")
         (if (pair? else-args)
             (emit-c-parallel-copy else-lbl else-args))
         (emit (string-append "        goto " (c-sanitize-label else-lbl) ";"))
         (emit "    }")))

      ((%jump-if-zero)
       (let ((lbl (cadr inst)))
         (emit (string-append "    if (cmp_s1 == cmp_s2) goto " (c-sanitize-label lbl) ";"))))

      ((%return)
       (emit "    return;"))

      ((%push)
       (let ((src (cadr inst)))
         (emit (string-append "    reg_rsp -= 8; *(uint64_t *)reg_rsp = " (c-operand->str src) ";"))))

      ((%pop)
       (let ((dst (cadr inst)))
         (emit (string-append "    " (c-operand->str dst) " = *(uint64_t *)reg_rsp; reg_rsp += 8;"))))

      ((%mov)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (cond
           ((eq? dst '%r12)
            (emit (string-append "    reg_r12 = (char *)(uintptr_t)(" (c-operand->str src) ");")))
           ((eq? dst '%rsp)
            (emit (string-append "    reg_rsp = (char *)(uintptr_t)(" (c-operand->str src) ");")))
           ((eq? src '%r12)
            (emit (string-append "    " (c-operand->str dst) " = (uint64_t)(uintptr_t)reg_r12;")))
           ((eq? src '%rsp)
            (emit (string-append "    " (c-operand->str dst) " = (uint64_t)(uintptr_t)reg_rsp;")))
           (else
            (emit (string-append "    " (c-operand->str dst) " = " (c-operand->str src) ";"))))))

      ((%load)
       (let ((dst (cadr inst))
             (base (caddr inst))
             (offset (cadddr inst)))
         (emit (string-append "    " (c-reg->str dst) " = " (c-mem-ref base offset) ";"))))

      ((%store)
       (let ((base (cadr inst))
             (offset (caddr inst))
             (src (cadddr inst)))
         (emit (string-append "    " (c-mem-ref base offset) " = " (c-operand->str src) ";"))))

      ((%store-byte)
       (let ((base (cadr inst))
             (offset (caddr inst))
             (src (cadddr inst)))
         (let ((src-str (if (number? src) (number->string src) (c-reg->str src))))
           (emit (string-append "    " (c-mem-byte-ref base offset) " = (uint8_t)(" src-str ");")))))

      ((%load-byte-zx)
       (let ((dst (cadr inst))
             (base (caddr inst))
             (offset (cadddr inst)))
         (emit (string-append "    " (c-reg->str dst) " = (uint64_t)(" (c-mem-byte-ref base offset) ");"))))

      ((%add)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (if (eq? dst '%r12)
             (emit (string-append "    reg_r12 += " (c-operand->str src) ";"))
             (emit (string-append "    " (c-operand->str dst) " += " (c-operand->str src) ";")))))

      ((%raw-add)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (emit (string-append "    " (c-operand->str dst) " += " (c-operand->str src) ";"))))

      ((%sub)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (emit (string-append "    " (c-operand->str dst) " -= " (c-operand->str src) ";"))))

      ((%raw-sub)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (emit (string-append "    " (c-operand->str dst) " -= " (c-operand->str src) ";"))))

      ((%neg)
       (let ((dst (cadr inst)))
         (emit (string-append "    " (c-operand->str dst) " = (uint64_t)(-(int64_t)" (c-operand->str dst) ");"))))

      ((%imul)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (emit (string-append "    " (c-operand->str dst) " = (uint64_t)((int64_t)" (c-operand->str dst) " * (int64_t)" (c-operand->str src) ");"))))

      ((%raw-mul)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (emit (string-append "    " (c-operand->str dst) " = (uint64_t)((int64_t)" (c-operand->str dst) " * (int64_t)" (c-operand->str src) ");"))))

      ((%box-fixnum)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (emit (string-append "    " (c-operand->str dst) " = ((uint64_t)" (c-operand->str src) ") << 2;"))))

      ((%unbox-fixnum)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (emit (string-append "    " (c-operand->str dst) " = (uint64_t)(((int64_t)" (c-operand->str src) ") >> 2);"))))

      ((%cqo)
       (emit "    /* cqo */"))

      ((%idiv)
       (let ((src (cadr inst)))
         (emit (string-append "    reg_rdx = (uint64_t)((int64_t)reg_rax % (int64_t)" (c-operand->str src) ");"))
         (emit (string-append "    reg_rax = (uint64_t)((int64_t)reg_rax / (int64_t)" (c-operand->str src) ");"))))

      ((%inc)
       (let ((dst (cadr inst)))
         (emit (string-append "    " (c-operand->str dst) "++;"))))

      ((%shl)
       (let ((dst (cadr inst))
             (count (caddr inst)))
         (emit (string-append "    " (c-operand->str dst) " <<= " (number->string count) ";"))))

      ((%shr)
       (let ((dst (cadr inst))
             (count (caddr inst)))
         (emit (string-append "    " (c-operand->str dst) " >>= " (number->string count) ";"))))

      ((%sar)
       (let ((dst (cadr inst))
             (count (caddr inst)))
         (emit (string-append "    " (c-operand->str dst) " = (uint64_t)(((int64_t)" (c-operand->str dst) ") >> " (number->string count) ");"))))

      ((%bit-and)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (emit (string-append "    " (c-operand->str dst) " &= " (c-operand->str src) ";"))))

      ((%bit-or)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (emit (string-append "    " (c-operand->str dst) " |= " (c-operand->str src) ";"))))

      ((%bit-xor)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (emit (string-append "    " (c-operand->str dst) " ^= " (c-operand->str src) ";"))))

      ((%cmp %raw-cmp)
       (let ((s1 (cadr inst))
             (s2 (caddr inst)))
         (emit (string-append "    cmp_s1 = " (c-operand->str s1) "; cmp_s2 = " (c-operand->str s2) ";"))))

      ((%set-boolean)
       (let ((dst (cadr inst))
             (cc (caddr inst)))
         (cond
           ((string=? cc "sete")
            (emit (string-append "    " (c-reg->str dst) " = (cmp_s1 == cmp_s2) ? 0x6F : 0x2F;")))
           ((string=? cc "setne")
            (emit (string-append "    " (c-reg->str dst) " = (cmp_s1 != cmp_s2) ? 0x6F : 0x2F;")))
           ((string=? cc "setl")
            (emit (string-append "    " (c-reg->str dst) " = ((int64_t)cmp_s1 < (int64_t)cmp_s2) ? 0x6F : 0x2F;")))
           ((string=? cc "setle")
            (emit (string-append "    " (c-reg->str dst) " = ((int64_t)cmp_s1 <= (int64_t)cmp_s2) ? 0x6F : 0x2F;")))
           ((string=? cc "setg")
            (emit (string-append "    " (c-reg->str dst) " = ((int64_t)cmp_s1 > (int64_t)cmp_s2) ? 0x6F : 0x2F;")))
           ((string=? cc "setge")
            (emit (string-append "    " (c-reg->str dst) " = ((int64_t)cmp_s1 >= (int64_t)cmp_s2) ? 0x6F : 0x2F;")))
           (else
            (error "Unknown condition code in C backend:" cc)))))

      ((%alloc)
       (let* ((dst (cadr inst))
              (bytes (caddr inst))
              (tag (cadddr inst))
              (si (if (pair? (cddddr inst)) (car (cddddr inst)) -128))
              (pos-si (if (< si 0) (- 0 si) si)))
         (emit (string-append "    " (c-operand->str dst) " = ulisp_alloc(" (number->string bytes) ", " (number->string tag) ", " (number->string pos-si) ");"))))

      ((%alloc-stack)
       (let ((dst (cadr inst))
             (offset (caddr inst))
             (tag (cadddr inst)))
         (emit (string-append "    " (c-operand->str dst) " = ((uint64_t)(uintptr_t)(reg_rsp + (" (number->string offset) "))) + " (number->string tag) ";"))))

      ((%code-ref)
       (let ((dst (cadr inst))
             (lbl (caddr inst)))
         (emit (string-append "    " (c-operand->str dst) " = (uint64_t)(uintptr_t)" (c-sanitize-label lbl) ";"))))

      ((%str-ref)
       (let ((dst (cadr inst))
             (lbl (caddr inst)))
         (emit (string-append "    " (c-operand->str dst) " = ((uint64_t)(uintptr_t)" (c-sanitize-label lbl) ") + 3;"))))

      ((%c-call)
       (let* ((func (cadr inst))
              (frame-shift (caddr inst))
              (fname (if (symbol? func) (symbol->raw-name func) func)))
         (cond
           ((or (eq? func 'ulisp_read_char) (string=? fname "ulisp_read_char"))
            (if (> frame-shift 0) (emit (string-append "    reg_rsp -= " (number->string frame-shift) ";")))
            (emit "    reg_rax = ulisp_read_char();")
            (if (> frame-shift 0) (emit (string-append "    reg_rsp += " (number->string frame-shift) ";"))))
           ((or (eq? func 'ulisp_peek_char) (string=? fname "ulisp_peek_char"))
            (if (> frame-shift 0) (emit (string-append "    reg_rsp -= " (number->string frame-shift) ";")))
            (emit "    reg_rax = ulisp_peek_char();")
            (if (> frame-shift 0) (emit (string-append "    reg_rsp += " (number->string frame-shift) ";"))))
           ((or (eq? func 'ulisp_write_char) (string=? fname "ulisp_write_char"))
            (if (> frame-shift 0) (emit (string-append "    reg_rsp -= " (number->string frame-shift) ";")))
            (emit "    reg_rax = ulisp_write_char(reg_rdi);")
            (if (> frame-shift 0) (emit (string-append "    reg_rsp += " (number->string frame-shift) ";"))))
           ((or (eq? func 'ulisp_write_string) (string=? fname "ulisp_write_string"))
            (if (> frame-shift 0) (emit (string-append "    reg_rsp -= " (number->string frame-shift) ";")))
            (emit "    reg_rax = ulisp_write_string(reg_rdi);")
            (if (> frame-shift 0) (emit (string-append "    reg_rsp += " (number->string frame-shift) ";"))))
           (else
            (if (> frame-shift 0) (emit (string-append "    reg_rsp -= " (number->string frame-shift) ";")))
            (emit (string-append "    reg_rax = " fname "();"))
            (if (> frame-shift 0) (emit (string-append "    reg_rsp += " (number->string frame-shift) ";")))))))

      ((%call-closure)
       (let ((frame-shift (cadr inst)))
         (emit "    reg_rdx = *(uint64_t *)((char *)(uintptr_t)reg_r10 - 1);")
         (emit (string-append "    reg_rsp -= " (number->string (+ frame-shift 8)) ";"))
         (emit "    ((void (*)(void))(uintptr_t)reg_rdx)();")
         (emit (string-append "    reg_rsp += " (number->string (+ frame-shift 8)) ";"))))

      ((%direct-call)
       (let ((label (cadr inst))
             (frame-shift (caddr inst)))
         (let ((fn-name (c-sanitize-label label)))
           (emit "    reg_r10 = 0;")
           (emit (string-append "    reg_rsp -= " (number->string (+ frame-shift 8)) ";"))
           (emit (string-append "    " fn-name "();"))
           (emit (string-append "    reg_rsp += " (number->string (+ frame-shift 8)) ";")))))

      ((%direct-jump)
       (let ((label (cadr inst)))
         (let ((fn-name (c-sanitize-label label)))
           (emit "    reg_r10 = 0;")
           (emit (string-append "    " fn-name "(); return;")))))

      ((%global-ref)
       (let ((reg (cadr inst))
             (var (caddr inst)))
         (let ((g-lbl (string-append "ulisp_gvar_" (c-sanitize-label var))))
           (emit (string-append "    " (c-reg->str reg) " = " g-lbl ";")))))

      ((%global-set!)
       (let ((var (cadr inst))
             (reg (caddr inst)))
         (let ((g-lbl (string-append "ulisp_gvar_" (c-sanitize-label var))))
           (emit (string-append "    " g-lbl " = " (c-reg->str reg) ";")))))

      ((%push-handler)
       (let ((catch-lbl (cadr inst))
             (frame-si (caddr inst))
             (handler-si (cadddr inst)))
         (let ((lbl-str (c-sanitize-label catch-lbl)))
           (emit (string-append "    *(void **)(reg_rsp + (" (number->string frame-si) ")) = ulisp_handler_chain;"))
           (emit (string-append "    *(char **)(reg_rsp + (" (number->string (+ frame-si 8)) ")) = reg_rsp;"))
            (emit (string-append "    *(void **)(reg_rsp + (" (number->string (+ frame-si 24)) ")) = &&" lbl-str ";"))
           (emit (string-append "    *(uint64_t *)(reg_rsp + (" (number->string (+ frame-si 32)) ")) = *(uint64_t *)(reg_rsp + (" (number->string handler-si) "));"))
           (emit (string-append "    ulisp_handler_chain = (void *)(reg_rsp + (" (number->string frame-si) "));")))))

      ((%pop-handler)
       (let ((frame-si (cadr inst)))
         (emit (string-append "    ulisp_handler_chain = *(void **)(reg_rsp + (" (number->string frame-si) "));"))))

      ((%raise)
        (emit "    if (!ulisp_handler_chain) { ulisp_unhandled_exception(reg_rax); }")
        (emit "    reg_rdi = reg_rax;")
        (emit "    reg_rsp = *(char **)((char *)ulisp_handler_chain + 8);")
        (emit "    void *catch_target = *(void **)((char *)ulisp_handler_chain + 24);")
        (emit "    reg_rax = *(uint64_t *)((char *)ulisp_handler_chain + 32);")
        (emit "    ulisp_handler_chain = *(void **)ulisp_handler_chain;")
        (emit "    reg_r10 = reg_rax;")
        (emit "    goto *catch_target;"))
      ((%set-values-count)
       (let ((cnt (cadr inst)))
         (emit (string-append "    ulisp_values_count = " (number->string cnt) ";"))))

      ((%store-values-buf)
       (let ((base-si (cadr inst))
             (count (caddr inst)))
         (let loop ((i 0))
           (if (< i count)
               (let ((offset (+ base-si (* -8 i))))
                 (emit (string-append "    ulisp_values_buf[" (number->string i) "] = *(uint64_t *)(reg_rsp + (" (number->string offset) "));"))
                 (loop (+ i 1)))))))

      ((%dispatch-consumer)
       (let ((consumer-si (cadr inst))
             (aligned-si (caddr inst))
             (frame-shift (cadddr inst)))
         (emit (string-append "    reg_r10 = *(uint64_t *)(reg_rsp + (" (number->string consumer-si) "));"))
         (emit "    reg_rdx = *(uint64_t *)((char *)(uintptr_t)reg_r10 - 1);")
         (emit "    switch (ulisp_values_count) {")
         (emit "        case 0:")
         (emit (string-append "            reg_rsp -= " (number->string (+ frame-shift 8)) ";"))
         (emit "            ((void (*)(void))(uintptr_t)reg_rdx)();")
         (emit (string-append "            reg_rsp += " (number->string (+ frame-shift 8)) ";"))
         (emit "            break;")
         (emit "        case 1:")
         (emit (string-append "            *(uint64_t *)(reg_rsp + (" (number->string aligned-si) ")) = reg_rax;"))
         (emit (string-append "            reg_rsp -= " (number->string (+ frame-shift 8)) ";"))
         (emit "            ((void (*)(void))(uintptr_t)reg_rdx)();")
         (emit (string-append "            reg_rsp += " (number->string (+ frame-shift 8)) ";"))
         (emit "            break;")
         (emit "        case 2:")
         (emit (string-append "            *(uint64_t *)(reg_rsp + (" (number->string aligned-si) ")) = ulisp_values_buf[0];"))
         (emit (string-append "            *(uint64_t *)(reg_rsp + (" (number->string (- aligned-si 8)) ")) = ulisp_values_buf[1];"))
         (emit (string-append "            reg_rsp -= " (number->string (+ frame-shift 8)) ";"))
         (emit "            ((void (*)(void))(uintptr_t)reg_rdx)();")
         (emit (string-append "            reg_rsp += " (number->string (+ frame-shift 8)) ";"))
         (emit "            break;")
         (emit "        case 3:")
         (emit (string-append "            *(uint64_t *)(reg_rsp + (" (number->string aligned-si) ")) = ulisp_values_buf[0];"))
         (emit (string-append "            *(uint64_t *)(reg_rsp + (" (number->string (- aligned-si 8)) ")) = ulisp_values_buf[1];"))
         (emit (string-append "            *(uint64_t *)(reg_rsp + (" (number->string (- aligned-si 16)) ")) = ulisp_values_buf[2];"))
         (emit (string-append "            reg_rsp -= " (number->string (+ frame-shift 8)) ";"))
         (emit "            ((void (*)(void))(uintptr_t)reg_rdx)();")
         (emit (string-append "            reg_rsp += " (number->string (+ frame-shift 8)) ";"))
         (emit "            break;")
         (emit "        default:")
         (emit "            for (int vi = 0; vi < (int)ulisp_values_count; vi++) {")
         (emit (string-append "                *(uint64_t *)(reg_rsp + (" (number->string aligned-si) " - vi*8)) = ulisp_values_buf[vi];"))
         (emit "            }")
         (emit (string-append "            reg_rsp -= " (number->string (+ frame-shift 8)) ";"))
         (emit "            ((void (*)(void))(uintptr_t)reg_rdx)();")
         (emit (string-append "            reg_rsp += " (number->string (+ frame-shift 8)) ";"))
         (emit "            break;")
         (emit "    }")
         (emit "    ulisp_values_count = 1;")))

      ((%capture-cc)
       (let* ((ret-lbl (cadr inst))
              (k-si (caddr inst))
              (lbl-str (c-sanitize-label ret-lbl)))
         (emit "    {")
         (emit "        uint64_t size = (uint64_t)((stack_mem + sizeof(stack_mem)) - reg_rsp);")
         (emit "        uint64_t alloc_size = (size + 111) & ~15ULL;")
         (let ((pos-k-si (if (< k-si 0) (- 0 k-si) k-si)))
           (emit (string-append "        char *obj = (char *)(uintptr_t)ulisp_alloc(alloc_size, 0, " (number->string pos-k-si) ");")))
         (emit "        *(uint64_t *)obj = (uint64_t)(uintptr_t)ulisp_continuation_invoke;")
         (emit "        *(uint64_t *)(obj + 8) = size;")
         (emit "        *(uint64_t *)(obj + 16) = (uint64_t)(uintptr_t)reg_rsp;")
         (emit "        *(void **)(obj + 80) = ulisp_handler_chain;")
         (emit "        memcpy(obj + 96, reg_rsp, size);")
         (emit (string-append "        if (setjmp(*(jmp_buf *)(obj + 24)) != 0) goto " lbl-str ";"))
         (emit "        reg_rax = (uint64_t)(uintptr_t)obj | 1;")
         (emit (string-append "        *(uint64_t *)(reg_rsp + (" (number->string k-si) ")) = reg_rax;"))
         (emit "    }")))

      (else
       (error "Unknown LIR opcode in C backend:" inst)))))

;;; Emits C code for a single %lir-function
(define (emit-c-function fn)
  (let* ((label (cadr fn))
         (label-str (c-sanitize-label label))
         (body (cdr (assq 'body (cddr fn)))))
    (scan-c-blocks! body)
    (emit (string-append "static void " label-str "(void) ULISP_UNUSED;"))
    (emit (string-append "static void " label-str "(void) {"))
    (emit "    *(uint64_t *)(reg_rsp - 8) = reg_r10;")
    (for-each emit-c-instruction body)
    (emit "}")
    (emit "")))

;;; Pass 7b Entrypoint: Takes %lir-program and emits complete ANSI C99 source
(define (emit-c prog gc-mode)
  (let* ((funcs-clause (assq '%lir-functions (cdr prog)))
         (funcs (if funcs-clause (cdr funcs-clause) '()))
         (main-clause (assq '%lir-main (cdr prog)))
         (main-body (cdr (assq 'body (cdr main-clause)))))
    (emit "/* Generated by ULisp Portable C / WebAssembly Backend */")
    (emit "#ifndef _GNU_SOURCE")
    (emit "#define _GNU_SOURCE")
    (emit "#endif")
    (emit "#include <stdint.h>")
    (emit "#include <stdio.h>")
    (emit "#include <stdlib.h>")
    (emit "#include <string.h>")
    (emit "#include <setjmp.h>")
    (emit "#include <signal.h>")
    (emit "#include <sys/mman.h>")
    (emit "#include <fcntl.h>")
    (emit "#include <unistd.h>")
    (emit "")
    (emit "#ifndef MAP_ANONYMOUS")
    (emit "#if defined(MAP_ANON)")
    (emit "#define MAP_ANONYMOUS MAP_ANON")
    (emit "#else")
    (emit "#define MAP_ANONYMOUS 0x20")
    (emit "#endif")
    (emit "#endif")
    (emit "")
    (emit "#if defined(__GNUC__) || defined(__clang__)")
    (emit "#define ULISP_UNUSED __attribute__((unused))")
    (emit "#pragma GCC diagnostic ignored \"-Wunused-label\"")
    (emit "#else")
    (emit "#define ULISP_UNUSED")
    (emit "#endif")
    (emit "")
    (emit "/* --- Pure Scheme Pre-Scheme Runtime C Representation --- */")
    (emit "#define FIXNUM_MASK     0x03")
    (emit "#define FIXNUM_TAG      0x00")
    (emit "#define FIXNUM_SHIFT    2")
    (emit "#define PAIR_MASK       0x07")
    (emit "#define PAIR_TAG        0x01")
    (emit "#define STRING_MASK     0x07")
    (emit "#define STRING_TAG      0x03")
    (emit "#define VECTOR_MASK     0x07")
    (emit "#define VECTOR_TAG      0x05")
    (emit "#define BYTEVECTOR_MASK 0x07")
    (emit "#define BYTEVECTOR_TAG  0x07")
    (emit "#define CHAR_MASK       0xFF")
    (emit "#define CHAR_TAG        0x0E")
    (emit "#define CHAR_SHIFT      8")
    (emit "#define SYMBOL_MASK     0xFF")
    (emit "#define SYMBOL_TAG      0x02")
    (emit "#define SYMBOL_SHIFT    8")
    (emit "#define BOOL_FALSE      0x2F")
    (emit "#define BOOL_TRUE       0x6F")
    (emit "#define EMPTY_LIST      0x3F")
    (emit "#define EOF_OBJECT      0x4F")
    (emit "#define HEAP_SIZE       (16384ULL * 1024 * 1024)")
    (emit "struct UlispSymbolEntry { uint64_t id; const char *name; };")
    (let ((syms (get-all-symbols)))
      (emit "static const struct UlispSymbolEntry ulisp_symbol_table[] = {")
      (for-each (lambda (entry)
                  (let ((id (cadr entry))
                        (str (caddr entry)))
                    (emit (string-append "    { " (number->string id) "ULL, \"" (escape-gas-string str) "\" },"))))
                syms)
      (emit "};")
      (emit (string-append "static const uint64_t ulisp_symbol_count = " (number->string (length syms)) ";")))
    (emit "")
    (emit "static void ulisp_unhandled_exception(uint64_t exn) ULISP_UNUSED;")
    (emit "static uint64_t ulisp_gc_state[32] ULISP_UNUSED;")
    (emit "uint64_t __ulisp_stackmap_table[1] = {0};")
    (emit "")
    (if (eq? gc-mode 'stress)
        (emit "static int g_gc_stress_mode = 1;")
        (emit "static int g_gc_stress_mode = 0;"))
    (emit "static char *from_space ULISP_UNUSED = NULL;")
    (emit "static char *to_space ULISP_UNUSED = NULL;")
    (emit "static uint64_t semi_space_size ULISP_UNUSED = 0;")
    (emit "static uint64_t to_space_free ULISP_UNUSED = 0;")
    (emit "")
    (emit "static uint64_t copy_if_heap(uint64_t val) ULISP_UNUSED;")
    (emit "static void ulisp_gc_collect(uint64_t active_si) ULISP_UNUSED;")
    (emit "static uint64_t ulisp_alloc(uint64_t bytes, uint64_t tag, uint64_t active_si) ULISP_UNUSED;")
    (emit "")
    (emit "static int ulisp_gc_grow_mature(void) ULISP_UNUSED;")
    (emit "static int ulisp_gc_grow_mature(void) {")
    (emit "    if (ulisp_gc_state[11] != 1) return 0;")
    (emit "    uint64_t m_from = ulisp_gc_state[2];")
    (emit "    uint64_t m_size = ulisp_gc_state[4];")
    (emit "    uint64_t m_free = ulisp_gc_state[5];")
    (emit "    uint64_t max_size = ulisp_gc_state[12];")
    (emit "    if (max_size == 0) max_size = HEAP_SIZE;")
    (emit "    uint64_t used = m_free - m_from;")
    (emit "    if (used * 10 <= m_size * 7) return 0;")
    (emit "    uint64_t new_size = m_size * 2;")
    (emit "    if (new_size > max_size) new_size = max_size;")
    (emit "    if (new_size <= m_size) return 0;")
    (emit "#if defined(__linux__) && defined(MREMAP_MAYMOVE)")
    (emit "    void *new_addr = mremap((void *)m_from, (size_t)m_size, (size_t)new_size, 0);")
    (emit "    if (new_addr != MAP_FAILED && new_addr == (void *)m_from) {")
    (emit "        ulisp_gc_state[4] = new_size;")
    (emit "        ulisp_gc_state[13]++;")
    (emit "        return 1;")
    (emit "    }")
    (emit "    new_addr = mremap((void *)m_from, (size_t)m_size, (size_t)new_size, MREMAP_MAYMOVE);")
    (emit "    if (new_addr != MAP_FAILED) {")
    (emit "        if (new_addr != (void *)m_from) {")
    (emit "            int64_t diff = (char *)new_addr - (char *)m_from;")
    (emit "            ulisp_gc_state[2] = (uint64_t)new_addr;")
    (emit "            ulisp_gc_state[5] += diff;")
    (emit "        }")
    (emit "        ulisp_gc_state[4] = new_size;")
    (emit "        ulisp_gc_state[13]++;")
    (emit "        return 1;")
    (emit "    }")
    (emit "#endif")
    (emit "    return 0;")
    (emit "}")
    (emit "")
    (emit "static void ulisp_oom_exit(void) ULISP_UNUSED;")
    (emit "static void ulisp_oom_exit(void) {")
    (emit "    fprintf(stderr, \"Fatal Error: ULisp Heap Limit Exhausted (OOM)\\n\");")
    (emit "    exit(1);")
    (emit "}")
    (emit "")
    (emit "static void ulisp_gc_write_barrier(uint64_t mature_obj_addr, uint64_t val) ULISP_UNUSED;")
    (emit "static void ulisp_gc_write_barrier(uint64_t mature_obj_addr, uint64_t val) {")
    (emit "    if (ulisp_gc_state[11] == 1) {")
    (emit "        uint64_t n_base = ulisp_gc_state[0];")
    (emit "        uint64_t n_size = ulisp_gc_state[1];")
    (emit "        uint64_t val_addr = val & ~7ULL;")
    (emit "        if (val_addr >= n_base && val_addr < (n_base + n_size)) {")
    (emit "            uint64_t *remset = (uint64_t *)ulisp_gc_state[9];")
    (emit "            uint64_t count = ulisp_gc_state[10];")
    (emit "            if (remset && count < 4096) {")
    (emit "                remset[count] = mature_obj_addr;")
    (emit "                ulisp_gc_state[10] = count + 1;")
    (emit "            }")
    (emit "        }")
    (emit "    }")
    (emit "}")
    (emit "")
    (emit "static uint64_t ulisp_read_char(void) ULISP_UNUSED;")
    (emit "static uint64_t ulisp_read_char(void) {")
    (emit "    int c = getchar();")
    (emit "    if (c == EOF) return EOF_OBJECT;")
    (emit "    return ((uint64_t)c << CHAR_SHIFT) | CHAR_TAG;")
    (emit "}")
    (emit "")
    (emit "static uint64_t ulisp_peek_char(void) ULISP_UNUSED;")
    (emit "static uint64_t ulisp_peek_char(void) {")
    (emit "    int c = getchar();")
    (emit "    if (c == EOF) return EOF_OBJECT;")
    (emit "    ungetc(c, stdin);")
    (emit "    return ((uint64_t)c << CHAR_SHIFT) | CHAR_TAG;")
    (emit "}")
    (emit "")
    (emit "static uint64_t ulisp_write_char(uint64_t val) ULISP_UNUSED;")
    (emit "static uint64_t ulisp_write_char(uint64_t val) {")
    (emit "    char c = (char)(val >> CHAR_SHIFT);")
    (emit "    putchar(c);")
    (emit "    return BOOL_TRUE;")
    (emit "}")
    (emit "")
    (emit "static uint64_t ulisp_flush(void) ULISP_UNUSED;")
    (emit "static uint64_t ulisp_flush(void) {")
    (emit "    fflush(stdout);")
    (emit "    return BOOL_TRUE;")
    (emit "}")
    (emit "")
    (emit "static uint64_t ulisp_emit_str(const char *s) ULISP_UNUSED;")
    (emit "static uint64_t ulisp_emit_str(const char *s) {")
    (emit "    if (s) fputs(s, stdout);")
    (emit "    return BOOL_TRUE;")
    (emit "}")
    (emit "")
    (emit "static uint64_t ulisp_write_string(uint64_t val) ULISP_UNUSED;")
    (emit "static uint64_t ulisp_write_string(uint64_t val) {")
    (emit "    const char *s = (const char *)(val - STRING_TAG);")
    (emit "    if (s) fputs(s, stdout);")
    (emit "    return BOOL_TRUE;")
    (emit "}")
    (emit "")
    (emit "static void print_scheme_value_raw(uint64_t val) ULISP_UNUSED;")
    (emit "static void print_pair_elements(uint64_t p) ULISP_UNUSED;")
    (emit "static void print_pair_elements(uint64_t p) {")
    (emit "    int first = 1;")
    (emit "    while ((p & PAIR_MASK) == PAIR_TAG) {")
    (emit "        uint64_t *ptr = (uint64_t *)(p - 1);")
    (emit "        if (!first) printf(\" \");")
    (emit "        first = 0;")
    (emit "        print_scheme_value_raw(ptr[0]);")
    (emit "        p = ptr[1];")
    (emit "    }")
    (emit "    if (p != EMPTY_LIST) {")
    (emit "        printf(\" . \");")
    (emit "        print_scheme_value_raw(p);")
    (emit "    }")
    (emit "}")
    (emit "")
    (emit "static void print_scheme_value_raw(uint64_t val) {")
    (emit "    if ((val & FIXNUM_MASK) == FIXNUM_TAG) {")
    (emit "        printf(\"%ld\", ((int64_t)val) >> FIXNUM_SHIFT);")
    (emit "    } else if (val == BOOL_FALSE) {")
    (emit "        printf(\"#f\");")
    (emit "    } else if (val == BOOL_TRUE) {")
    (emit "        printf(\"#t\");")
    (emit "    } else if (val == EMPTY_LIST) {")
    (emit "        printf(\"()\");")
    (emit "    } else if (val == EOF_OBJECT) {")
    (emit "        printf(\"#<eof>\");")
    (emit "    } else if ((val & CHAR_MASK) == CHAR_TAG) {")
    (emit "        char c = (char)(val >> CHAR_SHIFT);")
    (emit "        switch (c) {")
    (emit "            case '\\n': printf(\"#\\\\newline\"); break;")
    (emit "            case ' ':  printf(\"#\\\\space\"); break;")
    (emit "            case '\\t': printf(\"#\\\\tab\"); break;")
    (emit "            default:   printf(\"#\\\\%c\", c); break;")
    (emit "        }")
    (emit "    } else if ((val & PAIR_MASK) == PAIR_TAG) {")
    (emit "        printf(\"(\");")
    (emit "        print_pair_elements(val);")
    (emit "        printf(\")\");")
    (emit "    } else if ((val & STRING_MASK) == STRING_TAG) {")
    (emit "        printf(\"\\\"%s\\\"\", (const char *)(val - STRING_TAG));")
    (emit "    } else if ((val & VECTOR_MASK) == VECTOR_TAG) {")
    (emit "        uint64_t *base = (uint64_t *)(val - VECTOR_TAG);")
    (emit "        uint64_t len = base[0] >> 2;")
    (emit "        printf(\"#(\");")
    (emit "        for (uint64_t i = 0; i < len; i++) {")
    (emit "            if (i > 0) printf(\" \");")
    (emit "            print_scheme_value_raw(base[1 + i]);")
    (emit "        }")
    (emit "        printf(\")\");")
    (emit "    } else if ((val & BYTEVECTOR_MASK) == BYTEVECTOR_TAG) {")
    (emit "        uint64_t *base = (uint64_t *)(val - BYTEVECTOR_TAG);")
    (emit "        uint64_t len = base[0] >> 2;")
    (emit "        const uint8_t *bytes = (const uint8_t *)(base + 1);")
    (emit "        printf(\"#u8(\");")
    (emit "        for (uint64_t i = 0; i < len; i++) {")
    (emit "            if (i > 0) printf(\" \");")
    (emit "            printf(\"%u\", bytes[i]);")
    (emit "        }")
    (emit "        printf(\")\");")
    (emit "    } else if ((val & SYMBOL_MASK) == SYMBOL_TAG) {")
    (emit "        const char *sym_name = NULL;")
    (emit "        for (uint64_t i = 0; i < ulisp_symbol_count; i++) {")
    (emit "            if (ulisp_symbol_table[i].id == val) { sym_name = ulisp_symbol_table[i].name; break; }")
    (emit "        }")
    (emit "        if (sym_name) {")
    (emit "            printf(\"%s\", sym_name);")
    (emit "        } else {")
    (emit "            printf(\"#<symbol-%ld>\", val >> SYMBOL_SHIFT);")
    (emit "        }")
    (emit "    } else {")
    (emit "        printf(\"#<unknown: 0x%lx>\", val);")
    (emit "    }")
    (emit "}")
    (emit "")
    (emit "static void print_scheme_value(uint64_t val) ULISP_UNUSED;")
    (emit "static void print_scheme_value(uint64_t val) {")
    (emit "    print_scheme_value_raw(val);")
    (emit "    printf(\"\\n\");")
    (emit "}")
    (emit "")
    (emit "static void ulisp_unhandled_exception(uint64_t exn) {")
    (emit "    if ((exn & PAIR_MASK) == PAIR_TAG) {")
    (emit "        uint64_t *pair = (uint64_t *)(exn - PAIR_TAG);")
    (emit "        uint64_t car_val = pair[0];")
    (emit "        if ((car_val & SYMBOL_MASK) == SYMBOL_TAG) {")
    (emit "            const char *sym_name = NULL;")
    (emit "            for (uint64_t i = 0; i < ulisp_symbol_count; i++) {")
    (emit "                if (ulisp_symbol_table[i].id == car_val) { sym_name = ulisp_symbol_table[i].name; break; }")
    (emit "            }")
    (emit "            if (sym_name && (strcmp(sym_name, \"error-object\") == 0 || strcmp(sym_name, \"error\") == 0)) {")
    (emit "                uint64_t cdr_val = pair[1];")
    (emit "                if ((cdr_val & PAIR_MASK) == PAIR_TAG) {")
    (emit "                    uint64_t *cdr_pair = (uint64_t *)(cdr_val - PAIR_TAG);")
    (emit "                    uint64_t msg = cdr_pair[0];")
    (emit "                    uint64_t irritants = cdr_pair[1];")
    (emit "                    fprintf(stderr, \"*** ERROR: \");")
    (emit "                    if ((msg & STRING_MASK) == STRING_TAG) {")
    (emit "                        uint64_t *str_base = (uint64_t *)(msg - STRING_TAG);")
    (emit "                        uint64_t len = str_base[0] >> 2;")
    (emit "                        const char *chars = (const char *)(str_base + 1);")
    (emit "                        fwrite(chars, 1, len, stderr);")
    (emit "                    } else {")
    (emit "                        print_scheme_value_raw(msg);")
    (emit "                    }")
    (emit "                    fprintf(stderr, \"\\n\");")
    (emit "                    if (irritants != EMPTY_LIST) {")
    (emit "                        fprintf(stderr, \"    Irritants: \");")
    (emit "                        uint64_t cur = irritants;")
    (emit "                        while ((cur & PAIR_MASK) == PAIR_TAG) {")
    (emit "                            uint64_t *p = (uint64_t *)(cur - PAIR_TAG);")
    (emit "                            print_scheme_value_raw(p[0]);")
    (emit "                            cur = p[1];")
    (emit "                            if (cur != EMPTY_LIST) fprintf(stderr, \" \");")
    (emit "                        }")
    (emit "                        if (cur != EMPTY_LIST) {")
    (emit "                            fprintf(stderr, \" . \");")
    (emit "                            print_scheme_value_raw(cur);")
    (emit "                        }")
    (emit "                        fprintf(stderr, \"\\n\");")
    (emit "                    }")
    (emit "                    exit(1);")
    (emit "                }")
    (emit "            }")
    (emit "        }")
    (emit "    }")
    (emit "    fprintf(stderr, \"*** ERROR: unhandled exception: \");")
    (emit "    print_scheme_value(exn);")
    (emit "    exit(1);")
    (emit "}")
    (emit "")
    (emit "static void crash_handler(int sig, siginfo_t *info, void *ucontext) ULISP_UNUSED;")
    (emit "static void crash_handler(int sig, siginfo_t *info, void *ucontext) {")
    (emit "    (void)info; (void)ucontext;")
    (emit "    fprintf(stderr, \"*** CRASH: signal %d ***\\n\", sig);")
    (emit "    exit(128 + sig);")
    (emit "}")
    (emit "")
    (emit "static uint64_t reg_rax ULISP_UNUSED;")
    (emit "static uint64_t reg_rbx ULISP_UNUSED;")
    (emit "static uint64_t reg_rcx ULISP_UNUSED;")
    (emit "static uint64_t reg_rdx ULISP_UNUSED;")
    (emit "static uint64_t reg_rsi ULISP_UNUSED;")
    (emit "static uint64_t reg_rdi ULISP_UNUSED;")
    (emit "static uint64_t reg_r10 ULISP_UNUSED;")
    (emit "static char *reg_r12 ULISP_UNUSED;")
    (emit "static uint64_t reg_r13 ULISP_UNUSED;")
    (emit "static uint64_t reg_r14 ULISP_UNUSED;")
    (emit "static uint64_t reg_r15 ULISP_UNUSED;")
    (emit "static char *reg_rsp ULISP_UNUSED;")
    (emit "static uint64_t cmp_s1 ULISP_UNUSED;")
    (emit "static uint64_t cmp_s2 ULISP_UNUSED;")
    (emit "static char stack_mem[64 * 1024 * 1024] ULISP_UNUSED;")
    (emit "static void *ulisp_handler_chain ULISP_UNUSED = NULL;")
    (emit "static uint64_t ulisp_values_count ULISP_UNUSED = 1;")
    (emit "static uint64_t ulisp_values_buf[64] ULISP_UNUSED = {0};")
    (let loop ((gvs (car *top-level-vars*)))
      (if (pair? gvs)
          (let* ((v (car gvs))
                 (g-lbl (string-append "ulisp_gvar_" (c-sanitize-label v))))
            (emit (string-append "static uint64_t " g-lbl " ULISP_UNUSED = 63;"))
            (loop (cdr gvs)))))
    (emit "")
    (emit "static uint64_t copy_if_heap(uint64_t val) {")
    (emit "    uint64_t tag = val & 7ULL;")
    (emit "    if (tag != 1 && tag != 3 && tag != 5 && tag != 7) {")
    (emit "        return val;")
    (emit "    }")
    (emit "    uint64_t untagged = val & ~7ULL;")
    (emit "    if (!from_space || untagged < (uint64_t)(uintptr_t)from_space ||")
    (emit "        untagged >= (uint64_t)(uintptr_t)reg_r12) {")
    (emit "        return val;")
    (emit "    }")
    (emit "    if (untagged < 8 || (untagged - 8) < (uint64_t)(uintptr_t)from_space) {")
    (emit "        return val;")
    (emit "    }")
    (emit "    if (((untagged - 8) & 7ULL) != 0) {")
    (emit "        return val;")
    (emit "    }")
    (emit "    char *orig_obj = (char *)(uintptr_t)untagged;")
    (emit "    uint64_t header = *(uint64_t *)(orig_obj - 8);")
    (emit "    uint64_t f_tag = header & 7ULL;")
    (emit "    if (f_tag == 1 || f_tag == 3 || f_tag == 5 || f_tag == 7) {")
    (emit "        if ((header & ~7ULL) >= 8) {")
    (emit "            uint64_t f_addr = (header & ~7ULL) - 8;")
    (emit "            if (f_addr >= (uint64_t)(uintptr_t)to_space &&")
    (emit "                f_addr < (uint64_t)(uintptr_t)to_space_free) {")
    (emit "                return ((uint64_t)(uintptr_t)(f_addr + 8)) | tag;")
    (emit "            }")
    (emit "        }")
    (emit "    }")
    (emit "    if ((header & 3ULL) != 0) {")
    (emit "        return val;")
    (emit "    }")
    (emit "    uint64_t type = (header >> 2) & 0xFF;")
    (emit "    if ((type < 1 || type > 7) && !(type == 0 && ((header >> 10) & 0xFF) >= 1)) {")
    (emit "        return val;")
    (emit "    }")
    (emit "    uint64_t total_bytes = ((header >> 2) >> 16) + 8;")
    (emit "    if (total_bytes < 16 || total_bytes > 100000000 || (total_bytes & 7ULL) != 0) {")
    (emit "        return val;")
    (emit "    }")
    (emit "    if ((uint64_t)(uintptr_t)(orig_obj - 8 + total_bytes) > (uint64_t)(uintptr_t)reg_r12) {")
    (emit "        return val;")
    (emit "    }")
    (emit "    char *dest = (char *)(uintptr_t)to_space_free;")
    (emit "    memcpy(dest, orig_obj - 8, total_bytes);")
    (emit "    uint64_t forwarded_val = ((uint64_t)(uintptr_t)(dest + 8)) | tag;")
    (emit "    *(uint64_t *)(orig_obj - 8) = forwarded_val;")
    (emit "    to_space_free += total_bytes;")
    (emit "    return forwarded_val;")
    (emit "}")
    (emit "")
    (emit "static void ulisp_gc_collect(uint64_t active_si) {")
    (emit "    if (!from_space || !to_space) return;")
    (emit "    to_space_free = (uint64_t)(uintptr_t)to_space;")
    (emit "    uint64_t scan_ptr = to_space_free;")
    (emit "    reg_rax = copy_if_heap(reg_rax);")
    (emit "    reg_rbx = copy_if_heap(reg_rbx);")
    (emit "    reg_rcx = copy_if_heap(reg_rcx);")
    (emit "    reg_rdx = copy_if_heap(reg_rdx);")
    (emit "    reg_rsi = copy_if_heap(reg_rsi);")
    (emit "    reg_rdi = copy_if_heap(reg_rdi);")
    (emit "    reg_r10 = copy_if_heap(reg_r10);")
    (emit "    reg_r13 = copy_if_heap(reg_r13);")
    (emit "    reg_r14 = copy_if_heap(reg_r14);")
    (emit "    reg_r15 = copy_if_heap(reg_r15);")
    (emit "    char *stack_bottom = stack_mem + sizeof(stack_mem) - 1024;")
    (emit "    char *sp_start = reg_rsp - (active_si + 16);")
    (emit "    if (sp_start < stack_mem) sp_start = stack_mem;")
    (emit "    sp_start = (char *)((uintptr_t)sp_start & ~7ULL);")
    (emit "    for (char *sp = sp_start; sp < stack_bottom; sp += 8) {")
    (emit "        uint64_t val = *(uint64_t *)sp;")
    (emit "        *(uint64_t *)sp = copy_if_heap(val);")
    (emit "    }")
    (emit "    for (uint64_t vi = 0; vi < ulisp_values_count && vi < 64; vi++) {")
    (emit "        ulisp_values_buf[vi] = copy_if_heap(ulisp_values_buf[vi]);")
    (emit "    }")
    (let loop ((gvs (car *top-level-vars*)))
      (if (pair? gvs)
          (let* ((v (car gvs))
                 (g-lbl (string-append "ulisp_gvar_" (c-sanitize-label v))))
            (emit (string-append "    " g-lbl " = copy_if_heap(" g-lbl ");"))
            (loop (cdr gvs)))))
    (emit "    while (scan_ptr < to_space_free) {")
    (emit "        uint64_t *hdr_ptr = (uint64_t *)(uintptr_t)scan_ptr;")
    (emit "        uint64_t header = *hdr_ptr;")
    (emit "        uint64_t type = (header >> 2) & 0xFF;")
    (emit "        uint64_t total_bytes = ((header >> 2) >> 16) + 8;")
    (emit "        if (total_bytes < 16) total_bytes = 16;")
    (emit "        if ((total_bytes & 7) != 0) {")
    (emit "            total_bytes = (total_bytes + 7) & ~7ULL;")
    (emit "        }")
    (emit "        char *fields = (char *)(hdr_ptr + 1);")
    (emit "        if (type == 1) {")
    (emit "            uint64_t *pcar = (uint64_t *)fields;")
    (emit "            uint64_t *pcdr = (uint64_t *)(fields + 8);")
    (emit "            *pcar = copy_if_heap(*pcar);")
    (emit "            *pcdr = copy_if_heap(*pcdr);")
    (emit "        } else if (type == 2 || (type == 0 && ((header >> 10) & 0xFF) >= 1)) {")
    (emit "            uint64_t fcount = (header >> 10) & 0xFF;")
    (emit "            for (uint64_t fi = 1; fi < fcount; fi++) {")
    (emit "                uint64_t *pf = (uint64_t *)(fields + fi * 8);")
    (emit "                *pf = copy_if_heap(*pf);")
    (emit "            }")
    (emit "        } else if (type == 5) {")
    (emit "            uint64_t len = (*(uint64_t *)fields) >> 2;")
    (emit "            for (uint64_t vi = 0; vi < len; vi++) {")
    (emit "                uint64_t *pe = (uint64_t *)(fields + 8 + vi * 8);")
    (emit "                *pe = copy_if_heap(*pe);")
    (emit "            }")
    (emit "        }")
    (emit "        scan_ptr += total_bytes;")
    (emit "    }")
    (emit "    char *tmp = from_space;")
    (emit "    from_space = to_space;")
    (emit "    to_space = tmp;")
    (emit "    reg_r12 = (char *)(uintptr_t)to_space_free;")
    (emit "    ulisp_gc_state[0] = (uint64_t)(uintptr_t)from_space;")
    (emit "    ulisp_gc_state[1] = (uint64_t)(uintptr_t)to_space;")
    (emit "    ulisp_gc_state[8]++;")
    (emit "}")
    (emit "")
    (emit "static uint64_t ulisp_alloc(uint64_t bytes, uint64_t tag, uint64_t active_si) {")
    (emit "    uint64_t aligned_bytes = (bytes + 7) & ~7ULL;")
    (emit "    if (g_gc_stress_mode || ((uint64_t)(uintptr_t)(reg_r12 + aligned_bytes) > (uint64_t)(uintptr_t)(from_space + semi_space_size))) {")
    (emit "        ulisp_gc_collect(active_si);")
    (emit "        if ((uint64_t)(uintptr_t)(reg_r12 + aligned_bytes) > (uint64_t)(uintptr_t)(from_space + semi_space_size)) {")
    (emit "            ulisp_oom_exit();")
    (emit "        }")
    (emit "    }")
    (emit "    uint64_t res = ((uint64_t)(uintptr_t)reg_r12) + tag;")
    (emit "    reg_r12 += aligned_bytes;")
    (emit "    return res;")
    (emit "}")
    (emit "")
    (emit "static void ulisp_continuation_invoke(void) ULISP_UNUSED;")
    (emit "static void ulisp_continuation_invoke(void) {")
    (emit "    char *obj = (char *)(uintptr_t)(reg_r10 - 1);")
    (emit "    uint64_t size = *(uint64_t *)(obj + 8);")
    (emit "    char *target_rsp = (char *)(uintptr_t)*(uint64_t *)(obj + 16);")
    (emit "    reg_rax = *(uint64_t *)(reg_rsp + 8);")
    (emit "    ulisp_handler_chain = *(void **)(obj + 80);")
    (emit "    memcpy(target_rsp, obj + 96, size);")
    (emit "    reg_rsp = target_rsp;")
    (emit "    longjmp(*(jmp_buf *)(obj + 24), 1);")
    (emit "}")
    (emit "")
    ;; Forward declarations of lifted functions
    (for-each (lambda (fn)
                (let* ((lbl (cadr fn))
                       (lbl-str (c-sanitize-label lbl)))
                  (emit (string-append "static void " lbl-str "(void);"))))
              funcs)
    (emit "")
    ;; Emit string literals
    (if (not (null? (car *strings*)))
        (let loop ((ss (reverse (car *strings*))))
          (if (not (null? ss))
              (let* ((entry (car ss))
                     (lbl-str (c-sanitize-label (car entry)))
                     (escaped (escape-gas-string (cdr entry))))
                (emit (string-append "static const char " lbl-str "[] __attribute__((aligned(8))) = \"" escaped "\";"))
                (loop (cdr ss))))))
    (emit "")
    ;; Emit lifted function bodies
    (for-each emit-c-function funcs)
    ;; Emit scheme_entry
    (emit "uint64_t scheme_entry(char *heap_base) {")
    (emit "    semi_space_size = (1024ULL * 1024 * 1024);")
    (emit "    from_space = heap_base;")
    (emit "    to_space = heap_base + semi_space_size;")
    (emit "    to_space_free = (uint64_t)(uintptr_t)to_space;")
    (emit "    reg_r12 = from_space;")
    (emit "    reg_rsp = stack_mem + sizeof(stack_mem) - 1024;")
    (scan-c-blocks! main-body)
    (for-each (lambda (inst)
                (if (not (eq? (car inst) '%return))
                    (emit-c-instruction inst)))
              main-body)
    (emit "    return reg_rax;")
    (emit "}")
    (emit "")
    ;; Standalone main() entrypoint
    (emit "#ifndef ULISP_NO_MAIN")
    (emit "int main(int argc, char **argv) {")
    (emit "    struct sigaction sa;")
    (emit "    memset(&sa, 0, sizeof(sa));")
    (emit "    sa.sa_sigaction = crash_handler;")
    (emit "    sa.sa_flags = SA_SIGINFO;")
    (emit "    sigaction(SIGSEGV, &sa, NULL);")
    (emit "")
    (emit "    int quiet = 0;")
    (emit "    if (getenv(\"ULISP_QUIET\") != NULL) {")
    (emit "        quiet = 1;")
    (emit "    }")
    (emit "    if (argc > 1) {")
    (emit "        quiet = 1;")
    (emit "        int fd = open(argv[1], O_RDONLY);")
    (emit "        if (fd < 0) {")
    (emit "            perror(argv[1]);")
    (emit "            return 1;")
    (emit "        }")
    (emit "        if (dup2(fd, STDIN_FILENO) < 0) {")
    (emit "            perror(\"dup2\");")
    (emit "            close(fd);")
    (emit "            return 1;")
    (emit "        }")
    (emit "        close(fd);")
    (emit "    }")
    (emit "")
    (emit "    char *heap = (char *)mmap(NULL, HEAP_SIZE, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);")
    (emit "    if (heap == MAP_FAILED) {")
    (emit "        fprintf(stderr, \"Failed to mmap %zu bytes of heap\\n\", (size_t)HEAP_SIZE);")
    (emit "        return 1;")
    (emit "    }")
    (emit "")
    (emit "    uint64_t n_size = 4194304ULL;")
    (emit "    uint64_t m_size = 67108864ULL;")
    (emit "    uint64_t max_size = 1073741824ULL;")
    (emit "    uint64_t profile_id = 0;")
    (emit "")
    (emit "    char *prof = getenv(\"ULISP_GC_PROFILE\");")
    (emit "    if (prof != NULL) {")
    (emit "        if (prof[0] == 'c' || prof[0] == 'C') {")
    (emit "            n_size = 268435456ULL;")
    (emit "            m_size = 268435456ULL;")
    (emit "            max_size = 4294967296ULL;")
    (emit "            profile_id = 1;")
    (emit "        } else if (prof[0] == 's' || prof[0] == 'S') {")
    (emit "            n_size = 16777216ULL;")
    (emit "            m_size = 268435456ULL;")
    (emit "            max_size = 4294967296ULL;")
    (emit "            profile_id = 2;")
    (emit "        }")
    (emit "    }")
    (emit "    char *dbg = getenv(\"DEBUG_GC\");")
    (emit "    uint64_t debug_gc = (dbg != NULL && dbg[0] != '0') ? 1ULL : 0ULL;")
    (emit "    char *stress = getenv(\"ULISP_GC_STRESS\");")
    (emit "    if (stress != NULL && strcmp(stress, \"0\") != 0) {")
    (emit "        g_gc_stress_mode = 1;")
    (emit "    }")
    (emit "")
    (emit "    ulisp_gc_state[0] = (uint64_t)heap;")
    (emit "    ulisp_gc_state[1] = n_size;")
    (emit "    ulisp_gc_state[2] = (uint64_t)heap + n_size;")
    (emit "    ulisp_gc_state[3] = (uint64_t)heap + n_size + m_size;")
    (emit "    ulisp_gc_state[4] = m_size;")
    (emit "    ulisp_gc_state[5] = (uint64_t)heap + n_size;")
    (emit "    ulisp_gc_state[8] = 0;")
    (emit "    ulisp_gc_state[11] = 1;")
    (emit "    ulisp_gc_state[12] = max_size;")
    (emit "    ulisp_gc_state[13] = 0;")
    (emit "    ulisp_gc_state[14] = profile_id;")
    (emit "    ulisp_gc_state[15] = debug_gc;")
    (emit "")
    (emit "    uint64_t result = scheme_entry(heap);")
    (emit "    if (!quiet) {")
    (emit "        print_scheme_value(result);")
    (emit "    }")
    (emit "")
    (emit "    if (ulisp_gc_state[15] & 1) {")
    (emit "        fprintf(stderr, \"[DEBUG_GC] Execution complete. Rescued unmapped pointers: %llu\\n\",")
    (emit "                (unsigned long long)(ulisp_gc_state[15] >> 1));")
    (emit "    }")
    (emit "")
    (emit "    munmap(heap, HEAP_SIZE);")
    (emit "    return 0;")
    (emit "}")
    (emit "#endif")
    (emit "")))
;;; =======================================================================
;;; ULisp Compiler Pass 8: Compilation Driver & CLI Entrypoint
;;; Conforms to DSN-33 Architecture Specification & Issue #504
;;; =======================================================================

(define (read-all-forms)
  (let loop ((acc '()))
    (let ((expr (read)))
      (if (eof-object? expr)
          (reverse acc)
          (loop (cons expr acc))))))

(define (extract-directives-and-forms raw-forms)
  (let ((initial-gc 'all))
    (let loop ((forms raw-forms)
               (target 'x86_64)
               (gc-mode initial-gc)
               (verify #f)
               (trace #f)
               (debug #f))
      (if (null? forms)
          (list target gc-mode '() verify trace debug)
          (let ((first (car forms)))
            (cond
              ;; Target directives
              ((or (eq? first '--target-lir)
                   (and (pair? first) (eq? (car first) '!target) (pair? (cdr first)) (eq? (cadr first) 'lir)))
               (loop (cdr forms) 'lir gc-mode verify trace debug))
              ((and (pair? first) (eq? (car first) '!target) (pair? (cdr first)))
               (loop (cdr forms) (cadr first) gc-mode verify trace debug))
              ;; Extern symbol directives
              ((or (eq? first '--allow-extern)
                   (eq? first '!allow-extern)
                   (and (pair? first) (or (eq? (car first) '!allow-extern) (eq? (car first) '--allow-extern))))
               (set-allow-extern-symbols! #t)
               (loop (cdr forms) target gc-mode verify trace debug))
              ;; Module compilation directives with module id
              ((and (pair? first)
                    (or (eq? (car first) '!module-name)
                        (eq? (car first) '--module-name)
                        (and (eq? (car first) '!module) (pair? (cdr first)) (not (boolean? (cadr first))))))
               (set-module-mode! #t)
               (set-allow-extern-symbols! #t)
               (set-current-module-id! (cadr first))
               (loop (cdr forms) target gc-mode verify trace debug))
              ;; Module compilation directives (general)
              ((or (eq? first '--module)
                   (eq? first '!module)
                   (and (pair? first) (or (eq? (car first) '!module) (eq? (car first) '--module))))
               (set-module-mode! #t)
               (loop (cdr forms) target gc-mode verify trace debug))
              ;; Import SBI directive
              ((and (pair? first)
                    (or (eq? (car first) '!import-sbi)
                        (eq? (car first) '--import-sbi))
                    (pair? (cdr first)))
               (let* ((path (cadr first))
                      (imported-forms (slurp-single-file (if (symbol? path) (symbol->string path) path))))
                 (loop (append imported-forms (cdr forms)) target gc-mode verify trace debug)))
              ;; Emit SBI directive
              ((and (pair? first)
                    (or (eq? (car first) '!emit-sbi)
                        (eq? (car first) '--emit-sbi)))
               (display ";;; ULisp Compiler SBI (Scheme Binary Interface)\n")
               (display "(define-syntax newline (syntax-rules () ((newline) (port-newline *stdout-port*)) ((newline p) (port-newline p))))\n")
               (display "(define-syntax display (syntax-rules () ((display val) (port-display val *stdout-port*)) ((display val p) (port-display val p))))\n")
               (display "(define-syntax write (syntax-rules () ((write val) (port-write val *stdout-port*)) ((write val p) (port-write val p))))\n")
               (display "(define-syntax read (syntax-rules () ((read) (port-read *stdin-port*)) ((read p) (port-read p))))\n")
               (loop (cdr forms) target gc-mode verify trace debug))
              ;; GC directives
              ((and (pair? first) (eq? (car first) '!gc) (pair? (cdr first)))
               (loop (cdr forms) target (cadr first) verify trace debug))
              ((or (eq? first '--gc-stress) (eq? first '!gc-stress))
               (loop (cdr forms) target 'stress verify trace debug))
              ;; Optimization level directives (-O0, -O1, -O2)
              ((or (eq? first '-O0) (eq? first '!-O0))
               (set-pipeline-opt-level! 0)
               (loop (cdr forms) target gc-mode verify trace debug))
              ((or (eq? first '-O1) (eq? first '!-O1))
               (set-pipeline-opt-level! 1)
               (loop (cdr forms) target gc-mode verify trace debug))
              ((or (eq? first '-O2) (eq? first '!-O2))
               (set-pipeline-opt-level! 2)
               (loop (cdr forms) target gc-mode verify trace debug))
              ((and (pair? first) (eq? (car first) '!opt) (pair? (cdr first)))
               (set-pipeline-opt-level! (cadr first))
               (loop (cdr forms) target gc-mode verify trace debug))
              ;; Verification directives
              ((and (pair? first) (eq? (car first) '!verify))
               (let ((vmode (if (pair? (cdr first)) (cadr first) #t)))
                 (loop (cdr forms) target gc-mode vmode trace debug)))
              ;; Pass timing / profiling directives
              ((or (eq? first '--time-passes) (eq? first '!time-passes))
               (enable-pipeline-time-passes!)
               (loop (cdr forms) target gc-mode verify trace debug))
              ;; IR Dump directives
              ((or (eq? first '--print-after-all) (eq? first '!print-after-all))
               (enable-pipeline-print-after-all!)
               (loop (cdr forms) target gc-mode verify trace debug))
              ((and (pair? first) (eq? (car first) '!dump-ir) (pair? (cdr first)))
               (set-pipeline-dump-ir! (cadr first))
               (loop (cdr forms) target gc-mode verify trace debug))
              ;; Pass disable directives
              ((and (pair? first) (eq? (car first) '!disable-pass) (pair? (cdr first)))
               (disable-pass! (cadr first))
               (loop (cdr forms) target gc-mode verify trace debug))
              ;; Tracing and debugging directives
              ((or (eq? first '--trace-passes) (eq? first '!trace))
               (loop (cdr forms) target gc-mode verify #t debug))
              ((and (pair? first) (eq? (car first) '!trace))
               (loop (cdr forms) target gc-mode verify #t debug))
              ((or (eq? first '--debug) (eq? first '!debug))
               (loop (cdr forms) target gc-mode verify trace #t))
              ((and (pair? first) (eq? (car first) '!debug))
               (loop (cdr forms) target gc-mode verify trace #t))
              ;; String/Symbol prefix directives (--dump-ir=..., --disable-pass=...)
              ((symbol? first)
               (let ((str (symbol->string first)))
                 (cond
                   ((string-starts-with? str "--dump-ir=")
                    (let ((pname (string->symbol (substring str 10 (string-length str)))))
                      (set-pipeline-dump-ir! pname)
                      (loop (cdr forms) target gc-mode verify trace debug)))
                   ((string-starts-with? str "--disable-pass=")
                    (let ((pname (string->symbol (substring str 15 (string-length str)))))
                      (disable-pass! pname)
                      (loop (cdr forms) target gc-mode verify trace debug)))
                   ((string-starts-with? str "--module-name=")
                    (let ((mname (substring str 14 (string-length str))))
                      (set-module-mode! #t)
                      (set-allow-extern-symbols! #t)
                      (set-current-module-id! mname)
                      (loop (cdr forms) target gc-mode verify trace debug)))
                   ((string-starts-with? str "--import-sbi=")
                    (let* ((sbipath (substring str 13 (string-length str)))
                           (imported-forms (slurp-single-file sbipath)))
                      (loop (append imported-forms (cdr forms)) target gc-mode verify trace debug)))
                   (else
                    (list target gc-mode forms verify trace debug)))))
              (else
               (list target gc-mode forms verify trace debug))))))))

(define (extract-target-and-forms raw-forms)
  (let ((res (extract-directives-and-forms raw-forms)))
    (cons (car res) (caddr res))))

;;; -----------------------------------------------------------------------
;;; Two-Layer Compiler Pipeline API (Frontend/LIR & Backend)
;;; Conforms to DSN-33 Architecture Specification & Issue #590, #598
;;; -----------------------------------------------------------------------

(define (compile-to-lir forms verify-mode trace-mode)
  (run-pass-pipeline forms verify-mode trace-mode))

(define (compile-backend lir-ast target gc-mode)
  (let ((pass-name (string->symbol (string-append "backend-" (symbol->string target)))))
    (set-current-pass! pass-name)
    (with-call-frame pass-name lir-ast
      (lambda ()
        (cond
          ((eq? target 'c)
           (emit-c lir-ast gc-mode))
          ((eq? target 'aarch64)
           (emit-aarch64 lir-ast gc-mode))
          (else
           (emit-x86-64 lir-ast gc-mode)))))))

;;; -----------------------------------------------------------------------
;;; Canonical LIR S-expression Serializer
;;; Resolves compiled quotation symbols under native AOT without '?' masking
;;; -----------------------------------------------------------------------

(define *lir-known-symbols*
  '((%lir-program . "%lir-program")
    (%lir-functions . "%lir-functions")
    (%lir-function . "%lir-function")
    (%lir-main . "%lir-main")
    (strings . "strings")
    (stackmaps . "stackmaps")
    (frame-size . "frame-size")
    (body . "body")
    (params . "params")
    (%mov . "%mov")
    (%load . "%load")
    (%store . "%store")
    (%add . "%add")
    (%sub . "%sub")
    (%mul . "%mul")
    (%div . "%div")
    (%cmp . "%cmp")
    (%jump . "%jump")
    (%jump-cond . "%jump-cond")
    (%label . "%label")
    (%call . "%call")
    (%call-closure . "%call-closure")
    (%return . "%return")
    (%alloc . "%alloc")
    (%safepoint . "%safepoint")
    (%rax . "%rax")
    (%rbx . "%rbx")
    (%rcx . "%rcx")
    (%rdx . "%rdx")
    (%rsi . "%rsi")
    (%rdi . "%rdi")
    (%rbp . "%rbp")
    (%rsp . "%rsp")
    (%r8 . "%r8")
    (%r9 . "%r9")
    (%r10 . "%r10")
    (%r11 . "%r11")
    (%r12 . "%r12")
    (%r13 . "%r13")
    (%r14 . "%r14")
    (%r15 . "%r15")
    (%al . "%al")
    (equal . "equal")
    (not-equal . "not-equal")
    (less . "less")
    (less-equal . "less-equal")
    (greater . "greater")
    (greater-equal . "greater-equal")
    (zero . "zero")
    (not-zero . "not-zero")))

(define (lir-symbol->string sym)
  (let ((entry (assq sym *lir-known-symbols*)))
    (if entry
        (cdr entry)
        (let ((s (symbol->string sym)))
          (if (string=? s "?")
              "?"
              s)))))

(define (dump-lir-token val)
  (cond
    ((symbol? val)
     (display (lir-symbol->string val)))
    ((number? val)
     (display val))
    ((string? val)
     (write val))
    ((boolean? val)
     (display (if val "#t" "#f")))
    ((null? val)
     (display "()"))
    ((pair? val)
     (display "(")
     (let loop ((curr val) (first? #t))
       (cond
         ((null? curr)
          (display ")"))
         ((pair? curr)
          (if (not first?) (display " "))
          (dump-lir-token (car curr))
          (loop (cdr curr) #f))
         (else
          (display " . ")
          (dump-lir-token curr)
          (display ")")))))
    (else
     (write val))))

(define (dump-lir-ast lir-ast)
  (dump-lir-token lir-ast)
  (newline))

;;; Entry point: read all S-expressions from standard input and compile through two-layer pipeline
(let* ((raw (read-all-forms))
       (directives (extract-directives-and-forms raw))
       (target (car directives))
       (gc-mode (cadr directives))
       (forms (caddr directives))
       (verify-mode (cadddr directives))
       (trace-mode (car (cddddr directives)))
       (debug-mode (if (> (length directives) 5) (car (cdr (cddddr directives))) #f)))
  (if debug-mode
      (enable-call-stack-trace!))
  (if (not (null? forms))
      (cond
        ;; 1. LIR Intermediate Output Mode (--target-lir or (!target lir))
        ((eq? target 'lir)
         (let ((lir (compile-to-lir forms verify-mode trace-mode)))
           (dump-lir-ast lir)))
        ;; 2. Direct LIR Ingestion Mode (Input is already a Canonical LIR S-expression)
        ((and (pair? forms) (pair? (car forms)) (eq? (caar forms) '%lir-program))
         (let ((lir (car forms)))
           (if verify-mode
               (begin
                 (enable-verifier!)
                 (verify-pass-output 'lir lir)))
           (compile-backend lir target gc-mode)))
        ;; 3. Standard Full Pipeline (Frontend -> LIR -> Backend)
        (else
         (let ((lir (compile-to-lir forms verify-mode trace-mode)))
           (compile-backend lir target gc-mode))))))

