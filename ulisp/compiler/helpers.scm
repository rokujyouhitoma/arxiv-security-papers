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
       (let ((v0 (make-vector (+ len2 1)))
             (v1 (make-vector (+ len2 1))))
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

(define *known-compiler-symbols*
  '((string-append2 . "string-append2")
    (vector-append2 . "vector-append2")
    (bytevector-append2 . "bytevector-append2")
    (nanopass-try-clause . "nanopass-try-clause")
    (nanopass-catamorphism-step . "nanopass-catamorphism-step")
    (set-current-pass! . "set-current-pass!")
    (nanopass-verifier-enabled? . "nanopass-verifier-enabled?")
    (nanopass-verify-ast . "nanopass-verify-ast")
    (with-call-frame . "with-call-frame")
    (nanopass-display-ast-diff . "nanopass-display-ast-diff")
    (nanopass-trace-enabled? . "nanopass-trace-enabled?")
    (nanopass-register-language! . "nanopass-register-language!")
    (nanopass-parse-language-spec . "nanopass-parse-language-spec")
    (nanopass-parse . "nanopass-parse")
    (nanopass-unparse . "nanopass-unparse")
    (nanopass-ast-valid? . "nanopass-ast-valid?")
    (nanopass-parse-nt . "nanopass-parse-nt")
    (current-jiffy . "current-jiffy")
    (jiffies-per-second . "jiffies-per-second")
    (sys-getenv . "sys-getenv")
    (sys-bench-passes? . "sys-bench-passes?")
    (sys-clock-gettime-monotonic . "sys-clock-gettime-monotonic")
    (gc-current-heap-bytes . "gc-current-heap-bytes")))

(define (symbol->raw-name sym)
  (let ((entry (assq sym (car *symbol-table*))))
    (if (and entry (pair? (cdr entry)) (pair? (cddr entry)))
        (caddr entry)
        (let ((known (assq sym *known-compiler-symbols*)))
          (if known
              (cdr known)
              (let ((s (symbol->string sym)))
                (if (string=? s "?")
                    (let ((k2 (assq sym *known-compiler-symbols*)))
                      (if k2 (cdr k2) s))
                    s)))))))

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
  (string->symbol (string-append "ulisp_fn_" (sanitize-label-str (symbol->raw-name name)))))

(define (mangle-gvar-label name)
  (string-append "ulisp_gvar_" (sanitize-label-str (symbol->raw-name name))))

(define (mangle-mod-init-label mod-id)
  (string-append "ulisp_mod_init_" (sanitize-label-str (if (symbol? mod-id) (symbol->raw-name mod-id) mod-id))))

(define (make-body-expr bodies)
  (cond
    ((null? bodies) (list 'begin))
    ((null? (cdr bodies)) (car bodies))
    (else (cons 'begin bodies))))

;;; -----------------------------------------------------------------------
;;; Standard Error & Profiling Port / Timer Fallbacks (Issue #621)
;;; -----------------------------------------------------------------------

(define *compiler-stderr-port* (cons '%standard-output-port (cons 2 '())))

(define (get-compiler-error-port)
  (cond
    ((and (procedure? current-error-port) (not (null? (current-error-port))))
     (current-error-port))
    (else
     *compiler-stderr-port*)))

(define (sys-clock-gettime-monotonic)
  (cons 0 0))

(define (gc-current-heap-bytes)
  0)

(define (sys-getenv name)
  #f)


(define (current-jiffy)
  0)

(define (jiffies-per-second)
  1000000000)




