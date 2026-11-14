;;; =======================================================================
;;; ULisp Compiler Pass 0: Common Helpers & Primitive Predicates
;;; Conforms to DSN-33 Architecture Specification
;;; =======================================================================

;;; Standard Helper Procedures (Self-hosting primitives)
;; Host compatibility shim for Gauche / ILisp bootstrapping (Issue #646)
(define (file-input-port? p)
  (and (pair? p) (eq? (car p) '%file-input-port)))
(define (port-line p)
  (if (file-input-port? p)
      (car (cadr (cddddr p)))
      1))
(define (port-col p)
  (if (file-input-port? p)
      (car (caddr (cddddr p)))
      1))

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

(define (string-ends-with? s suffix)
  (let ((slen (string-length s))
        (suflen (string-length suffix)))
    (if (< slen suflen)
        #f
        (let ((start (- slen suflen)))
          (let loop ((i 0))
            (if (= i suflen)
                #t
                (if (char=? (string-ref s (+ start i)) (string-ref suffix i))
                    (loop (+ i 1))
                    #f)))))))

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

(define (occurs-in? var expr)
  (cond
    ((symbol? expr) (eq? expr var))
    ((not (pair? expr)) #f)
    (else
     (or (occurs-in? var (car expr))
         (occurs-in? var (cdr expr))))))

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

(define (string=? s1 s2)
  (string-equal? s1 s2))

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

(define *stdlib-enabled* (cons #t '()))
(define (stdlib-enabled?) (car *stdlib-enabled*))
(define (set-stdlib-enabled! val) (set-car! *stdlib-enabled* val))

(define (is-known-stdlib-symbol? sym)
  (memq sym '(*stdout-port*
              *stdin-port*
              *stderr-port*
              *current-input-port-cell*
              *current-output-port-cell*
              *current-error-port-cell*
              port-newline
              port-display
              port-display-string
              port-write
              port-write-char
              port-write-u8
              port-write-string
              port-write-bytevector
              port-write-bytevector-range
              port-flush-output
              port-read
              port-read-char
              port-peek-char
              port-read-line
              port-read-u8
              port-peek-u8
              port-char-ready?
              port-u8-ready?
              port-close
              close-port
              close-input-port
              close-output-port
              current-input-port
              current-output-port
              current-error-port
              open-input-file
              open-output-file
              open-input-string
              open-output-string
              get-output-string
              call-with-port
              string->number-core
              %eqv?
              %number?
              %complex?
              %real?
              %rational?
              %integer?
              %exact?
              %inexact?
              ulisp-flonum-tag
              pos-inf
              neg-inf
              nan
              make-hash-table
              hash-table-ref
              hash-table-set!
              hash-table-delete!
              hash-table-contains?
              hash-table-size
              hash-table-keys
              hash-table-values
              number->string
              string->number
              exact
              inexact
              floor
              ceiling
              truncate
              round
              sin
              cos
              tan
              asin
              acos
              atan
              sqrt
              exp
              log
              expt
              %synapse-safepoint-poll!
              synapse-safepoint-poll!
              %safepoint-poll!)))

(define (stdlib-symbol? sym)
  (and (stdlib-enabled?)
       (symbol? sym)
       (is-known-stdlib-symbol? sym)))

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

;;; Debug Symbol Generation Context (Conforms to DSN-33 & Issue #619)
(define *debug-symbols-enabled* (cons #f '()))
(define (debug-symbols-enabled?) (car *debug-symbols-enabled*))
(define (enable-debug-symbols!) (set-car! *debug-symbols-enabled* #t))
(define (disable-debug-symbols!) (set-car! *debug-symbols-enabled* #f))

(define (sanitize-source-path path)
  (if (not (string? path))
      "source.scm"
      (let loop ((i (- (string-length path) 1)) (acc '()))
        (if (< i 0)
            (list->string acc)
            (let ((c (string-ref path i)))
              (cond
                ((char=? c #\") (loop (- i 1) acc))
                ((char=? c #\\) (loop (- i 1) (cons #\/ acc)))
                ((or (char=? c #\newline) (char=? c (integer->char 13)) (char=? c #\tab))
                 (loop (- i 1) (cons #\_ acc)))
                (else (loop (- i 1) (cons c acc)))))))))

(define *source-file-table* (cons '() '()))
(define (reset-source-file-table!) (set-car! *source-file-table* '()))
(define (get-source-file-table) (reverse (car *source-file-table*)))

(define (register-source-file! path)
  (let* ((clean-path (sanitize-source-path path))
         (entry (assoc clean-path (car *source-file-table*))))
    (if entry
        (cdr entry)
        (let* ((new-id (+ (length (car *source-file-table*)) 1)))
          (set-car! *source-file-table* (cons (cons clean-path new-id) (car *source-file-table*)))
          new-id))))

(define *function-source-loc-table* (cons '() '()))
(define (reset-function-source-loc-table!) (set-car! *function-source-loc-table* '()))
(define (register-function-source-loc! fn file line col)
  (let ((clean (sanitize-source-path file)))
    (set-car! *function-source-loc-table*
              (cons (cons fn (list clean line col))
                    (car *function-source-loc-table*)))))
(define (lookup-function-source-loc fn)
  (let ((entry (assq fn (car *function-source-loc-table*))))
    (if entry
        (cdr entry)
        (let loop ((es (car *function-source-loc-table*)))
          (cond
            ((null? es) #f)
            ((and (symbol? (car (car es)))
                  (not (eq? (car (car es)) '%main))
                  (eq? (mangle-fn-label (car (car es))) fn))
             (cdr (car es)))
            (else (loop (cdr es))))))))

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

;;; -----------------------------------------------------------------------
;;; Standard Error Output Helpers & Active Output File Rollback (Issue #785)
;;; -----------------------------------------------------------------------

(define *compiler-stderr-port* (cons '%standard-output-port (cons 2 '())))

(define (get-compiler-error-port)
  (cond
    ((and (procedure? current-error-port) (not (null? (current-error-port))))
     (current-error-port))
    (else
     *compiler-stderr-port*)))

(define (display-stderr msg)
  (display msg (get-compiler-error-port)))

(define (newline-stderr)
  (newline (get-compiler-error-port)))

(define (write-stderr val)
  (write val (get-compiler-error-port)))

(define *cli-active-output-file* (cons #f '()))

(define (compiler-abort-and-cleanup! code)
  (let ((out (car *cli-active-output-file*)))
    (if (and (string? out) (not (string=? out "-")))
        (begin
          (set-car! *cli-active-output-file* #f)
          (cond
            ((and (procedure? sys-unlink) (not (null? sys-unlink)))
             (sys-unlink out))
            ((and (procedure? delete-file) (not (null? delete-file)))
             (delete-file out))
            (else #f)))))
  (exit code))

(define (display-call-stack-traceback frames)
  (if (null? frames)
      (display-stderr "    (no stack frames recorded - run with DEBUG=1 or --debug)\n")
      (let* ((rev-frames (reverse frames)))
        (let loop ((cur rev-frames) (i 1))
          (if (null? cur)
              #t
              (let* ((fr (car cur))
                     (name (car fr))
                     (summary (cdr fr)))
                (display-stderr "    [")
                (display-stderr i)
                (display-stderr "] ")
                (cond
                  ((and (pair? summary) (not (null? summary)))
                   (display-stderr "(")
                   (display-stderr (if (symbol? name) (symbol->string name) name))
                   (display-stderr " ")
                   (write-stderr summary)
                   (display-stderr ")"))
                  ((symbol? name)
                   (display-stderr "(")
                   (display-stderr (symbol->string name))
                   (display-stderr ")"))
                  (else
                   (write-stderr name)))
                (newline-stderr)
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
      ((and (>= depth 3) (pair? e)) '(...))
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

;;; Error Handling & Reporting Controls
(define *compiler-abort-on-error* (cons #t '()))
(define *compiler-suppress-diagnostics* (cons #f '()))

;;; Structured Compiler Diagnostic Report
(define (compiler-diagnostic-report msg irritants)
  (if (not (car *compiler-suppress-diagnostics*))
      (begin
        (display-stderr "\n======================================================================\n")
        (display-stderr "[COMPILER ERROR] Compilation aborted in Pass: ")
        (display-stderr (current-pass))
        (newline-stderr)
        (display-stderr "======================================================================\n")
        (if (not (eq? (current-source-file) 'none))
            (begin
              (display-stderr "  Source Location   : ")
              (display-stderr (current-source-file))
              (display-stderr ":")
              (display-stderr (current-source-line))
              (if (> (current-source-col) 0)
                  (begin
                    (display-stderr ":")
                    (display-stderr (current-source-col))))
              (newline-stderr)))
        (display-stderr "  Message           : ")
        (display-stderr msg)
        (newline-stderr)
        (display-stderr "  Target / Irritant : ")
        (write-stderr irritants)
        (newline-stderr)
        (display-stderr "  Toplevel Form     : ")
        (write-stderr (current-toplevel-name))
        (newline-stderr)
        (display-stderr "  Current Expr      : ")
        (write-stderr (truncate-expr-for-diagnostics (current-form)))
        (newline-stderr)
        (display-stderr "----------------------------------------------------------------------\n")
        (display-stderr "  Call Traceback (most recent call last):\n")
        (display-call-stack-traceback (current-call-stack))
        (display-stderr "======================================================================\n\n"))))

(define (error msg val)
  (if (car *compiler-in-error*)
      (begin
        (if (not (car *compiler-suppress-diagnostics*))
            (begin
              (display-stderr "\n*** [RECURSIVE ERROR] Aborting during error reporting: ")
              (display-stderr msg)
              (display-stderr " ")
              (write-stderr val)
              (newline-stderr)))
        (if (car *compiler-abort-on-error*)
            (compiler-abort-and-cleanup! 1)
            val))
      (begin
        (set-car! *compiler-in-error* #t)
        (compiler-diagnostic-report msg val)
        (set-car! *compiler-in-error* #f)
        (if (car *compiler-abort-on-error*)
            (compiler-abort-and-cleanup! 1)
            val))))

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
  (if (and (not (car *compiler-in-error*))
           (not (car *compiler-suppress-diagnostics*)))
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
          (display-stderr "\n======================================================================\n")
          (display-stderr "[LIR COMPILER ERROR] Unbound Variable Resolution Failed\n")
          (display-stderr "======================================================================\n")
          (display-stderr "  Unbound Symbol   : ")
          (display-stderr (symbol->string var))
          (newline-stderr)
          (display-stderr "  Current Function : ")
          (write-stderr (current-toplevel-name))
          (newline-stderr)
          (display-stderr "  Current Expr     : ")
          (write-stderr (truncate-expr-for-diagnostics (current-form)))
          (newline-stderr)
          (if (pair? similar)
              (begin
                (display-stderr "  Did you mean?    : ")
                (write-stderr similar)
                (newline-stderr))
              (begin
                (display-stderr "  Did you mean?    : (no similar candidates in scope)\n")))
          (display-stderr "  Active Local Bindings in 'env' (")
          (display-stderr (length all-symbols))
          (display-stderr " entries):\n")
          (if (null? env)
              (display-stderr "    - (empty environment)\n")
              (let print-env ((e env) (count 0))
                (cond
                  ((null? e) (display-stderr ""))
                  ((>= count 20)
                   (display-stderr "    - ... (")
                   (display-stderr (- (length all-symbols) 20))
                   (display-stderr " more bindings omitted)\n"))
                  ((and (pair? e) (pair? (car e)))
                   (let ((entry (car e)))
                     (display-stderr "    - ")
                     (display-stderr (symbol->string (car entry)))
                     (display-stderr " -> ")
                     (display-stderr (format-binding-info (cdr entry)))
                     (newline-stderr)
                     (print-env (cdr e) (+ count 1))))
                  (else (print-env (cdr e) (+ count 1))))))
          (display-stderr "======================================================================\n\n"))
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
         ((not (pair? cur)) (+ (+ len 3) (datum-repr-length cur)))
         ((null? (cdr cur)) (+ len (datum-repr-length (car cur))))
         (else (loop (cdr cur) (+ (+ len (datum-repr-length (car cur))) 1))))))
    (else 4)))

(define (print-spaces n)
  (let loop ((i 0))
    (if (< i n)
        (begin
          (display-stderr " ")
          (loop (+ i 1))))))

(define (compute-expr-columns form base-col)
  (if (and (pair? form) (pair? (cdr form)))
      (let* ((op (car form))
             (op-col (+ base-col 1))
             (args (cdr form)))
        (let loop ((as args)
                   (cur-col (+ (+ op-col (datum-repr-length op)) 1))
                   (cols (list op-col)))
          (if (null? as)
              (reverse cols)
              (loop (cdr as)
                    (+ (+ cur-col (datum-repr-length (car as))) 1)
                    (cons cur-col cols)))))
      (list base-col)))

(define (print-pipes-line cols)
  (let loop ((cur-col 0) (remaining cols))
    (if (pair? remaining)
        (let ((target-col (car remaining)))
          (print-spaces (- target-col cur-col))
          (display-stderr "|")
          (loop (+ target-col 1) (cdr remaining)))
        (newline-stderr))))

(define (format-power-assert-diagram expr-datum sub-evals result)
  (let ((base-col 4))
    (print-spaces base-col)
    (write-stderr expr-datum)
    (newline-stderr)
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
                          (display-stderr "|")
                          (loop-cols (+ target-c 1) (cdr lcs)))
                        (begin
                          (print-spaces (- col cur-c))
                          (write-stderr (truncate-expr-for-diagnostics val))
                          (newline-stderr))))
                  (print-items (cdr rem))))))
        (begin
          (print-spaces base-col)
          (display-stderr "|\n")
          (print-spaces base-col)
          (write-stderr (truncate-expr-for-diagnostics result))
          (newline-stderr)))))

(define (power-assert-report expr-datum sub-evals result)
  (if (not (car *compiler-suppress-diagnostics*))
      (begin
        (display-stderr "\n======================================================================\n")
        (display-stderr "[POWER ASSERT FAILED] Assertion condition evaluated to #f\n")
        (display-stderr "======================================================================\n")
        (display-stderr "  Expression  : ")
        (write-stderr expr-datum)
        (newline-stderr)
        (display-stderr "  Evaluations :\n")
        (let loop ((items sub-evals))
          (if (pair? items)
              (let ((item (car items)))
                (display-stderr "    - ")
                (write-stderr (car item))
                (display-stderr " => ")
                (write-stderr (truncate-expr-for-diagnostics (cadr item)))
                (newline-stderr)
                (loop (cdr items)))))
        (display-stderr "  Result      : ")
        (write-stderr result)
        (newline-stderr)
        (display-stderr "----------------------------------------------------------------------\n")
        (display-stderr "  Diagram     :\n")
        (format-power-assert-diagram expr-datum sub-evals result)
        (display-stderr "======================================================================\n\n")))
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
(define *symbol-table-buckets* (make-vector 1024 '()))
(define (reset-symbol-table!)
  (set-car! *symbol-table* '())
  (reset-label-caches!))

(define (symbol-hash-str str)
  (let ((len (string-length str)))
    (let loop ((i 0) (h 5381))
      (if (= i len)
          (modulo h 16777213)
          (let ((c (char->integer (string-ref str i))))
            (loop (+ i 1)
                  (modulo (+ (* h 33) c) 16777213)))))))

(define (string-fast-hash-1024 str)
  (let ((len (string-length str)))
    (if (= len 0)
        0
        (let ((c0 (char->integer (string-ref str 0)))
              (c1 (char->integer (string-ref str (- len 1))))
              (cm (char->integer (string-ref str (quotient len 2)))))
          (modulo (+ (+ (* len 31) (* c0 131)) (+ (* c1 17) (* cm 7))) 1024)))))

(define (intern-symbol sym)
  (let* ((b-idx (symbol->hash-idx sym))
         (bucket (vector-ref *symbol-table-buckets* b-idx))
         (entry (assq sym bucket)))
    (if entry
        (cadr entry)
        (let* ((raw-str (symbol->raw-name sym))
               (str (if (string=? raw-str "?")
                        (let ((known (assq sym *known-compiler-symbols*)))
                          (if known (cdr known) raw-str))
                        raw-str))
               (id (if (string=? str "?")
                       (if (number? sym)
                           sym
                           (let ((h (symbol->integer sym)))
                             (+ (* h 256) 2)))
                       (let ((h (symbol-hash-str str)))
                         (+ (* h 256) 2))))
               (new-entry (list sym id str)))
          (vector-set! *symbol-table-buckets* b-idx (cons new-entry bucket))
          (set-car! *symbol-table* (cons new-entry (car *symbol-table*)))
          id))))

(define *known-compiler-symbols*
  '((quote . "quote")
    (quasiquote . "quasiquote")
    (unquote . "unquote")
    (unquote-splicing . "unquote-splicing")
    (vector . "vector")
    (bytevector . "bytevector")
    (... . "...")
    (_ . "_")
    (guard . "guard")
    (a . "a")
    (b . "b")
    (c . "c")
    (d . "d")
    (e . "e")
    (f . "f")
    (g . "g")
    (h . "h")
    (i . "i")
    (j . "j")
    (k . "k")
    (l . "l")
    (m . "m")
    (n . "n")
    (o . "o")
    (p . "p")
    (q . "q")
    (r . "r")
    (s . "s")
    (t . "t")
    (u . "u")
    (v . "v")
    (w . "w")
    (x . "x")
    (y . "y")
    (z . "z")
    (e0 . "e0")
    (e1 . "e1")
    (e2 . "e2")
    (e3 . "e3")
    (e_test . "e_test")
    (e_res . "e_res")
    (e_cmd . "e_cmd")
    (e_else . "e_else")
    (x0 . "x0")
    (x1 . "x1")
    (x2 . "x2")
    (x3 . "x3")
    (d0 . "d0")
    (d1 . "d1")
    (d2 . "d2")
    (d3 . "d3")
    (c0 . "c0")
    (c1 . "c1")
    (c2 . "c2")
    (c3 . "c3")
    (p0 . "p0")
    (p1 . "p1")
    (p2 . "p2")
    (p3 . "p3")
    (a0 . "a0")
    (a1 . "a1")
    (a2 . "a2")
    (a3 . "a3")
    (b0 . "b0")
    (b1 . "b1")
    (b2 . "b2")
    (b3 . "b3")
    (t0 . "t0")
    (t1 . "t1")
    (t2 . "t2")
    (t3 . "t3")
    (s0 . "s0")
    (s1 . "s1")
    (s2 . "s2")
    (s3 . "s3")
    (v0 . "v0")
    (v1 . "v1")
    (v2 . "v2")
    (v3 . "v3")
    (r0 . "r0")
    (r1 . "r1")
    (r2 . "r2")
    (lval . "lval")
    (lval0 . "lval0")
    (lval1 . "lval1")
    (params . "params")
    (args . "args")
    (formals . "formals")
    (clauses . "clauses")
    (bindings . "bindings")
    (bodies . "bodies")
    (spec . "spec")
    (%make-closure . "%make-closure")
    (%make-closure-env . "%make-closure-env")
    (%closure-ref . "%closure-ref")
    (%closure-set! . "%closure-set!")
    (%cont-fun . "%cont-fun")
    (%cont-call . "%cont-call")
    (%direct-call . "%direct-call")
    (%call-closure . "%call-closure")
    (%tail-call . "%tail-call")
    (%push-handler . "%push-handler")
    (%pop-handler . "%pop-handler")
    (%code-ref . "%code-ref")
    (%str-ref . "%str-ref")
    (%gvar-ref . "%gvar-ref")
    (%gvar-set! . "%gvar-set!")
    (%global-ref . "%global-ref")
    (%global-set! . "%global-set!")
    (%alloc . "%alloc")
    (%alloc-stack . "%alloc-stack")
    (%store . "%store")
    (%load . "%load")
    (%mov . "%mov")
    (%jump . "%jump")
    (%jump-if . "%jump-if")
    (%jump-if-not . "%jump-if-not")
    (%label . "%label")
    (%return . "%return")
    (%phi . "%phi")
    (%safepoint . "%safepoint")
    (%num-args . "%num-args")
    (list . "list")
    (cons . "cons")
    (car . "car")
    (cdr . "cdr")
    (caar . "caar")
    (cadr . "cadr")
    (cdar . "cdar")
    (cddr . "cddr")
    (pair? . "pair?")
    (null? . "null?")
    (list? . "list?")
    (length . "length")
    (append . "append")
    (reverse . "reverse")
    (memq . "memq")
    (memv . "memv")
    (member . "member")
    (assq . "assq")
    (assv . "assv")
    (assoc . "assoc")
    (+ . "+")
    (- . "-")
    (* . "*")
    (/ . "/")
    (= . "=")
    (< . "<")
    (<= . "<=")
    (> . ">")
    (>= . ">=")
    (zero? . "zero?")
    (positive? . "positive?")
    (negative? . "negative?")
    (eq? . "eq?")
    (eqv? . "eqv?")
    (equal? . "equal?")
    (not . "not")
    (boolean? . "boolean?")
    (symbol? . "symbol?")
    (number? . "number?")
    (integer? . "integer?")
    (procedure? . "procedure?")
    (apply . "apply")
    (map . "map")
    (for-each . "for-each")
    (lambda . "lambda")
    (define . "define")
    (set! . "set!")
    (if . "if")
    (cond . "cond")
    (case . "case")
    (and . "and")
    (or . "or")
    (when . "when")
    (unless . "unless")
    (let . "let")
    (let* . "let*")
    (letrec . "letrec")
    (letrec* . "letrec*")
    (begin . "begin")
    (do . "do")
    (case-lambda . "case-lambda")
    (error . "error")
    (make-vector . "make-vector")
    (vector-ref . "vector-ref")
    (vector-set! . "vector-set!")
    (vector-length . "vector-length")
    (vector->list . "vector->list")
    (list->vector . "list->vector")
    (make-string . "make-string")
    (string-ref . "string-ref")
    (string-set! . "string-set!")
    (string-length . "string-length")
    (string=? . "string=?")
    (string-append . "string-append")
    (values . "values")
    (call-with-values . "call-with-values")
    (call/cc . "call/cc")
    (include . "include")
    (include-ci . "include-ci")
    (include-library-declarations . "include-library-declarations")
    (define-library . "define-library")
    (import . "import")
    (export . "export")
    (rename . "rename")
    (only . "only")
    (except . "except")
    (prefix . "prefix")
    (cond-expand . "cond-expand")
    (library-rec . "library-rec")
    (syntax-rules . "syntax-rules")
    (define-syntax . "define-syntax")
    (let-syntax . "let-syntax")
    (letrec-syntax . "letrec-syntax")
    (syntax-error . "syntax-error")
    (define-values . "define-values")
    (define-record-type . "define-record-type")
    (let-values . "let-values")
    (let*-values . "let*-values")
    (nanopass-map2 . "nanopass-map2")
    (nanopass-map3 . "nanopass-map3")
    (string-append2 . "string-append2")
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
    (gc-current-heap-bytes . "gc-current-heap-bytes")
    (ulisp_arity_error . "ulisp_arity_error")
    (L_cst . "L_cst")
    (L_src . "L_src")
    (L_core . "L_core")
    (L_anf . "L_anf")
    (L_lifted . "L_lifted")
    (L_lir_raw . "L_lir_raw")
    (L_lir_canonical . "L_lir_canonical")
    (L_asm_x86 . "L_asm_x86")
    (L_asm_aarch64 . "L_asm_aarch64")
    (L_x86_64 . "L_x86_64")
    (L_aarch64 . "L_aarch64")
    (L_c . "L_c")
    (extends . "extends")
    (entry . "entry")
    (exit . "exit")
    (terminals . "terminals")
    (keywords . "keywords")
    (nongenerative-id . "nongenerative-id")
    (L_cst? . "L_cst?")
    (L_src? . "L_src?")
    (L_core? . "L_core?")
    (L_anf? . "L_anf?")
    (L_lifted? . "L_lifted?")
    (L_lir_raw? . "L_lir_raw?")
    (L_lir_canonical? . "L_lir_canonical?")
    (L_asm_x86? . "L_asm_x86?")
    (L_asm_aarch64? . "L_asm_aarch64?")
    (%program . "%program")
    (output . "output")
    (input . "input")
    (trace . "trace")
    (debug . "debug")
    (verify . "verify")
    (make-vector-fill . "make-vector-fill")
    (make-bytevector-fill . "make-bytevector-fill")
    (make-list-fill . "make-list-fill")
    (string-copy-range . "string-copy-range")
    (string-copy-range! . "string-copy-range!")
    (string-fill-range! . "string-fill-range!")
    (bytevector-copy-range . "bytevector-copy-range")
    (bytevector-copy-range! . "bytevector-copy-range!")
    (string->utf8-range . "string->utf8-range")
    (utf8->string-range . "utf8->string-range")
    (vector-copy-range . "vector-copy-range")
    (vector-copy-range! . "vector-copy-range!")
    (vector-fill-range! . "vector-fill-range!")
    (vector->list-range . "vector->list-range")
    (string->list-range . "string->list-range")
    (string->vector-range . "string->vector-range")
    (vector->string-range . "vector->string-range")
    (%%make-promise . "%%make-promise")
    (make-parameter-1 . "make-parameter-1")
    (make-parameter-2 . "make-parameter-2")
    (%values . "%values")
    (raise . "raise")
    (error-object . "error-object")
    (%math-abs . "%math-abs")
    (gcd-2 . "gcd-2")
    (lcm-2 . "lcm-2")
    (max-2 . "max-2")
    (min-2 . "min-2")
    (%format . "%format")
    (%call-with-values . "%call-with-values")
    (%with-handler . "%with-handler")
    (bytevector-append2 . "bytevector-append2")
    (vector-append2 . "vector-append2")
    (%make-vector . "%make-vector")
    (%make-bytevector . "%make-bytevector")
    (%raw-call/cc . "%raw-call/cc")
    (port-write-bytevector-range . "port-write-bytevector-range")
    (port-write-bytevector . "port-write-bytevector")
    (assemble-and-build-elf-obj . "assemble-and-build-elf-obj")
    (emit-x86-64-elf-obj . "emit-x86-64-elf-obj")
    (build-x86-64-elf-obj . "build-x86-64-elf-obj")
    (assemble-stream-to-elf-obj . "assemble-stream-to-elf-obj")))

;; True in AOT-compiled binaries where uninterned symbol->string returns "?"
(define *aot-fast-sym-hash?* (= (string-length (symbol->string '%%ulisp-probe%%)) 1))

(define (symbol->raw-name sym)
  (if (not (symbol? sym))
      (if (string? sym) sym (number->string sym))
      (let ((s (symbol->string sym)))
        (if (not (string=? s "?"))
            s
            (let ((known (assq sym *known-compiler-symbols*)))
              (if known
                  (cdr known)
                  (let ((entry (if *aot-fast-sym-hash?*
                                   (assq sym (vector-ref *symbol-table-buckets* (symbol->hash-idx sym)))
                                   (assq sym (car *symbol-table*)))))
                    (if (and entry (pair? (cdr entry)) (pair? (cddr entry)))
                        (caddr entry)
                        s))))))))

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

(define *offset-str-cache* (make-vector 256 #f))
(define (offset->string offset)
  (if (and (<= offset 0) (>= offset -2040) (= (modulo offset 8) 0))
      (let* ((idx (- 0 (quotient offset 8)))
             (cached (vector-ref *offset-str-cache* idx)))
        (if cached
            cached
            (let ((s (string-append "- " (number->string (- 0 offset)))))
              (vector-set! *offset-str-cache* idx s)
              s)))
      (if (< offset 0)
          (string-append "- " (number->string (- 0 offset)))
          (string-append "+ " (number->string offset)))))

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
    (else (+ (+ 1 (expr-size (car expr))) (expr-size (cdr expr))))))

(define (expr-size-budget expr budget)
  (cond
    ((< budget 0) -1)
    ((not (pair? expr)) (- budget 1))
    (else
     (let ((b1 (expr-size-budget (car expr) (- budget 1))))
       (if (< b1 0)
           -1
           (expr-size-budget (cdr expr) b1))))))

(define (expr-size-le? expr limit)
  (>= (expr-size-budget expr limit) 0))

(define (%program? form)
  (and (pair? form) (eq? (car form) '%program)))

(define *char-mangle-vector*
  (let ((v (make-vector 256 "_")))
    (let loop ((i 0))
      (if (< i 256)
          (let ((c (integer->char i)))
            (vector-set! v i
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
            (loop (+ i 1)))
          v))))

(define (char->mangle-str c)
  (let ((idx (char->integer c)))
    (if (and (>= idx 0) (< idx 256))
        (vector-ref *char-mangle-vector* idx)
        "_")))

(define (string-all-clean? str len)
  (let loop ((i 0))
    (if (= i len)
        #t
        (let ((c (string-ref str i)))
          (if (or (and (char>=? c #\a) (char<=? c #\z))
                  (and (char>=? c #\A) (char<=? c #\Z))
                  (and (char>=? c #\0) (char<=? c #\9))
                  (char=? c #\_)
                  (char=? c #\.))
              (loop (+ i 1))
              #f)))))

(define *sanitized-str-cache* (make-vector 1024 '()))

(define (sanitize-label-str str)
  (let ((len (string-length str)))
    (if (string-all-clean? str len)
        str
        (let* ((h (string-fast-hash-1024 str))
               (bucket (vector-ref *sanitized-str-cache* h))
               (cached (assoc str bucket)))
          (if cached
              (cdr cached)
              (let loop ((i 0) (res ""))
                (if (< i len)
                    (loop (+ i 1) (string-append res (char->mangle-str (string-ref str i))))
                    (begin
                      (vector-set! *sanitized-str-cache* h (cons (cons str res) bucket))
                      res))))))))

(define (symbol->hash-idx sym)
  (if (symbol? sym)
      (if *aot-fast-sym-hash?*
          (let* ((h (symbol->integer sym))
                 (pos-h (if (< h 0) (- 0 h) h)))
            ;; Mix bits since compile-time symbol->integer values are multiples of 4.
            (modulo (+ pos-h (quotient pos-h 4)) 1024))
          (string-fast-hash-1024 (symbol->raw-name sym)))
      0))

(define *fn-label-cache* (make-vector 1024 '()))
(define *gvar-label-cache* (make-vector 1024 '()))

(define (reset-label-caches!)
  (let loop ((i 0))
    (if (< i 1024)
        (begin
          (vector-set! *symbol-table-buckets* i '())
          (vector-set! *sanitized-str-cache* i '())
          (vector-set! *fn-label-cache* i '())
          (vector-set! *gvar-label-cache* i '())
          (loop (+ i 1))))))

(define (asm-label->str lbl)
  (if (symbol? lbl)
      (let ((s (symbol->raw-name lbl)))
        (if (or (string=? s "?") (string=? s ""))
            (string-append ".L_sym_" (number->string (if (symbol? lbl) (symbol->integer lbl) (symbol-hash-str s))))
            s))
      (if (string? lbl)
          lbl
          (number->string lbl))))

(define (mangle-fn-label name)
  (let* ((b-idx (symbol->hash-idx name))
         (bucket (vector-ref *fn-label-cache* b-idx))
         (entry (assq name bucket)))
    (if entry
        (cdr entry)
        (let* ((raw (symbol->raw-name name))
               (res (string->symbol
                     (string-append "ulisp_fn_"
                                    (if (or (string=? raw "?") (string=? raw ""))
                                        (string-append "sym_" (number->string (if (symbol? name) (symbol->integer name) 0)))
                                        (sanitize-label-str raw))))))
          (vector-set! *fn-label-cache* b-idx (cons (cons name res) bucket))
          res))))

(define (mangle-gvar-label name)
  (let* ((b-idx (symbol->hash-idx name))
         (bucket (vector-ref *gvar-label-cache* b-idx))
         (entry (assq name bucket)))
    (if entry
        (cdr entry)
        (let* ((raw (symbol->raw-name name))
               (res (string-append "ulisp_gvar_"
                                   (if (or (string=? raw "?") (string=? raw ""))
                                       (string-append "sym_" (number->string (if (symbol? name) (symbol->integer name) 0)))
                                       (sanitize-label-str raw)))))
          (vector-set! *gvar-label-cache* b-idx (cons (cons name res) bucket))
          res))))

(define (mangle-mod-init-label mod-id)
  (let ((raw (if (symbol? mod-id) (symbol->raw-name mod-id) mod-id)))
    (string-append "ulisp_mod_init_"
                   (if (or (string=? raw "?") (string=? raw ""))
                       (string-append "sym_" (number->string (if (symbol? mod-id) (symbol->integer mod-id) 0)))
                       (sanitize-label-str raw)))))

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

;;; -----------------------------------------------------------------------
;;; R7RS Section 4.2.1 / 5.5.1 Feature Identifiers & cond-expand Helpers
;;; -----------------------------------------------------------------------

(define *current-target-arch* (cons 'x86_64 '()))

(define (current-target-arch)
  (car *current-target-arch*))

(define (set-current-target-arch! arch)
  (set-car! *current-target-arch* arch))

(define (ulisp-supported-feature? feat)
  (cond
    ((memq feat '(aarch64 arm64))
     (let ((tgt (current-target-arch)))
       (or (eq? tgt 'aarch64) (eq? tgt 'arm64))))
    ((memq feat '(x86-64 x86_64))
     (let ((tgt (current-target-arch)))
       (or (eq? tgt 'x86_64) (eq? tgt 'x86-64) (eq? tgt 'elf) (eq? tgt 'asm) (eq? tgt 'obj) (eq? tgt 'elf-obj))))
    ((memq feat '(ulisp r7rs exact-closed little-endian posix linux unix srfi-14 srfi-64 srfi-78 srfi-116 srfi-117 srfi-127 srfi-134 srfi-146 srfi-193))
     #t)
    (else #f)))

(define (builtin-library-name? name)
  (and (pair? name)
       (or (and (eq? (car name) 'scheme)
                (memq (cadr name) '(base write read time file process-context cxr inexact complex char lazy case-lambda eval repl r5rs load list hash-table sort division box comparator set stream generator list-queue lseq charset)))
           (and (eq? (car name) 'srfi)
                (memq (cadr name) '(1 14 28 41 64 69 78 95 111 113 117 121 125 127 128 132 141 145 158 193)))
           (and (eq? (car name) 'ulisp)
                (memq (cadr name) '(base core native))))))

(define (library-name->sld-path lib-name)
  (let loop ((rest lib-name) (acc "lib"))
    (if (null? rest)
        (string-append acc ".sld")
        (let* ((elem (car rest))
               (part (cond
                       ((symbol? elem) (symbol->string elem))
                       ((number? elem) (number->string elem))
                       (else "sub"))))
          (loop (cdr rest) (string-append acc "/" part))))))

(define (find-included-file path)
  (let ((try-file (lambda (p) (if (file-exists? p) p #f))))
    (or (try-file path)
        (try-file (string-append "ulisp/" path))
        (if (string-starts-with? path "ulisp/")
            (try-file (substring path 6 (string-length path)))
            #f)
        path)))

(define (ulisp-library-available? name)
  (or (builtin-library-name? name)
      (let* ((sld-rel (library-name->sld-path name))
             (resolved (find-included-file sld-rel)))
        (file-exists? resolved))))

(define (eval-feature-requirement req)
  (cond
    ((symbol? req)
     (ulisp-supported-feature? req))
    ((and (pair? req) (eq? (car req) 'library) (pair? (cdr req)))
     (ulisp-library-available? (cadr req)))
    ((and (pair? req) (eq? (car req) 'and))
     (let loop ((rest (cdr req)))
       (if (null? rest)
           #t
           (if (eval-feature-requirement (car rest))
               (loop (cdr rest))
               #f))))
    ((and (pair? req) (eq? (car req) 'or))
     (let loop ((rest (cdr req)))
       (if (null? rest)
           #f
           (if (eval-feature-requirement (car rest))
               #t
               (loop (cdr rest))))))
    ((and (pair? req) (eq? (car req) 'not) (pair? (cdr req)))
     (not (eval-feature-requirement (cadr req))))
    (else #f)))

(define (expand-cond-expand clauses)
  (let loop ((cls clauses))
    (if (or (null? cls) (not (pair? cls)))
        (error "syntax-error [R7RS §4.2.1]: cond-expand no matching clause" clauses)
        (let ((c (car cls)))
          (cond
            ((not (pair? c))
             (loop (cdr cls)))
            ((eq? (car c) 'else)
             (cdr c))
            ((eval-feature-requirement (car c))
             (cdr c))
            (else
             (loop (cdr cls))))))))

(define (sanitize-reader-form expr)
  (cond
    ((pair? expr)
     (let ((a (sanitize-reader-form (car expr)))
           (d (sanitize-reader-form (cdr expr))))
       (if (and (eq? a (car expr)) (eq? d (cdr expr)))
           expr
           (cons a d))))
    ((vector? expr)
     (let* ((len (vector-length expr))
            (new-v (make-vector len)))
       (let loop ((i 0))
         (if (= i len)
             new-v
             (begin
               (vector-set! new-v i (sanitize-reader-form (vector-ref expr i)))
               (loop (+ i 1)))))))
    (else
     (cond-expand
       (gauche
        (cond
          ((and (number? expr) (nan? expr))
           (string->symbol "+nan.0"))
          ((and (number? expr) (infinite? expr) (> expr 0))
           (string->symbol "+inf.0"))
          ((and (number? expr) (infinite? expr) (< expr 0))
           (string->symbol "-inf.0"))
          (else expr)))
       (else expr)))))





