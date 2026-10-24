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
(define (open-input-file path) #f)
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
(define *compiler-in-error* (cons #f '()))

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
  (set-car! *compiler-in-error* #f))

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

(define (sanitize-label-str str)
  (let* ((len (string-length str))
         (res (make-string len)))
    (let loop ((i 0))
      (if (< i len)
          (let ((c (string-ref str i)))
            (string-set! res i
              (cond
                ((char=? c #\-) #\_)
                ((char=? c #\?) #\_)
                ((char=? c #\!) #\_)
                ((char=? c #\*) #\_)
                ((char=? c #\/) #\_)
                ((char=? c #\<) #\_)
                ((char=? c #\>) #\_)
                ((char=? c #\=) #\_)
                ((char=? c #\%) #\_)
                ((char=? c #\:) #\_)
                (else c)))
            (loop (+ i 1)))
          res))))

(define (make-body-expr bodies)
  (cond
    ((null? bodies) (list 'begin))
    ((null? (cdr bodies)) (car bodies))
    (else (cons 'begin bodies))))

