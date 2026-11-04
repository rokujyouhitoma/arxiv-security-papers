;;; =======================================================================
;;; ULisp Standard Library: Environments, Dynamic Evaluation, and Load
;;; (R7RS-small Section 6.12, Section 6.14, (scheme eval), (scheme repl),
;;;  (scheme load), (scheme r5rs))
;;; Conforms to Issues #716, #717, #718
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

;; -----------------------------------------------------------------------
;; §6.12 First-Class Environment Specifier Objects (<environment>)
;; Representation: #(ulisp-env-tag <bindings-box> <macros-box> <parent> <mutable?> <name>)
;; -----------------------------------------------------------------------

(define (%make-r7rs-env bindings macros parent mutable? name)
  (let ((vec (make-vector 6 #f))
        (b-box (make-vector 1 bindings))
        (m-box (make-vector 1 macros)))
    (vector-set! vec 0 'ulisp-env-tag)
    (vector-set! vec 1 b-box)
    (vector-set! vec 2 m-box)
    (vector-set! vec 3 parent)
    (vector-set! vec 4 (if mutable? #t #f))
    (vector-set! vec 5 name)
    vec))

(define (environment? x)
  (and (vector? x)
       (= (vector-length x) 6)
       (eq? (vector-ref x 0) 'ulisp-env-tag)))

(define (%r7rs-env-bindings-box env) (vector-ref env 1))
(define (%r7rs-env-macros-box env)   (vector-ref env 2))
(define (%r7rs-env-parent env)       (vector-ref env 3))
(define (%r7rs-env-mutable? env)     (vector-ref env 4))
(define (%r7rs-env-name env)         (vector-ref env 5))

(define (%r7rs-env-bindings env)
  (vector-ref (%r7rs-env-bindings-box env) 0))

(define (%r7rs-env-macros env)
  (vector-ref (%r7rs-env-macros-box env) 0))

(define (%r7rs-env-find-cell env sym)
  (let loop ((cur env))
    (if (not cur)
        #f
        (let ((cell (assq sym (%r7rs-env-bindings cur))))
          (if cell
              cell
              (loop (%r7rs-env-parent cur)))))))

(define (%r7rs-env-bound? env sym)
  (if (not (environment? env))
      #f
      (if (%r7rs-env-find-cell env sym)
          #t
          #f)))

(define (%r7rs-env-lookup env sym)
  (if (not (environment? env))
      (error "eval: expected environment specifier" env)
      (let ((cell (%r7rs-env-find-cell env sym)))
        (if cell
            (cdr cell)
            (error "eval: unbound variable" sym)))))

(define (%r7rs-env-define! env sym val)
  (if (not (environment? env))
      (error "define: expected environment specifier" env)
      (if (not (%r7rs-env-mutable? env))
          (error "define: cannot define in immutable environment" sym)
          (let* ((box (%r7rs-env-bindings-box env))
                 (alist (vector-ref box 0))
                 (cell (assq sym alist)))
            (if cell
                (set-cdr! cell val)
                (vector-set! box 0 (cons (cons sym val) alist)))
            val))))

(define (%r7rs-env-set! env sym val)
  (if (not (environment? env))
      (error "set!: expected environment specifier" env)
      (let loop ((cur env))
        (if (not cur)
            (error "set!: unbound variable" sym)
            (let ((cell (assq sym (%r7rs-env-bindings cur))))
              (if cell
                  (if (not (%r7rs-env-mutable? cur))
                      (error "set!: cannot mutate binding in immutable environment" sym)
                      (begin
                        (set-cdr! cell val)
                        val))
                  (loop (%r7rs-env-parent cur))))))))

(define (%r7rs-env-find-macro env sym)
  (let loop ((cur env))
    (if (not cur)
        #f
        (let ((cell (assq sym (%r7rs-env-macros cur))))
          (if cell
              (cdr cell)
              (loop (%r7rs-env-parent cur)))))))

(define (%r7rs-env-define-macro! env sym transformer)
  (if (not (%r7rs-env-mutable? env))
      (error "define-syntax: cannot define macro in immutable environment" sym)
      (let* ((box (%r7rs-env-macros-box env))
             (alist (vector-ref box 0))
             (cell (assq sym alist)))
        (if cell
            (set-cdr! cell transformer)
            (vector-set! box 0 (cons (cons sym transformer) alist)))
        sym)))

;; -----------------------------------------------------------------------
;; First-Class Wrappers for Standard Procedures & Primitives
;; -----------------------------------------------------------------------

(define %eval-plus
  (case-lambda
    (() 0)
    ((a) (num+ 0 a))
    ((a b) (num+ a b))
    ((a b . rest)
     (let loop ((acc (num+ a b)) (rs rest))
       (if (null? rs)
           acc
           (loop (num+ acc (car rs)) (cdr rs)))))))

(define %eval-minus
  (case-lambda
    ((a) (num- a))
    ((a b) (num- a b))
    ((a b . rest)
     (let loop ((acc (num- a b)) (rs rest))
       (if (null? rs)
           acc
           (loop (num- acc (car rs)) (cdr rs)))))))

(define %eval-mul
  (case-lambda
    (() 1)
    ((a) (num* 1 a))
    ((a b) (num* a b))
    ((a b . rest)
     (let loop ((acc (num* a b)) (rs rest))
       (if (null? rs)
           acc
           (loop (num* acc (car rs)) (cdr rs)))))))

(define %eval-div
  (case-lambda
    ((a) (num/ 1 a))
    ((a b) (num/ a b))
    ((a b . rest)
     (let loop ((acc (num/ a b)) (rs rest))
       (if (null? rs)
           acc
           (loop (num/ acc (car rs)) (cdr rs)))))))

(define (%eval-chain-cmp pred)
  (case-lambda
    ((a b) (pred a b))
    ((a b . rest)
     (if (not (pred a b))
         #f
         (let loop ((prev b) (rs rest))
           (if (null? rs)
               #t
               (if (pred prev (car rs))
                   (loop (car rs) (cdr rs))
                   #f)))))))

(define %eval-num=  (%eval-chain-cmp (lambda (a b) (num= a b))))
(define %eval-num<  (%eval-chain-cmp (lambda (a b) (num< a b))))
(define %eval-num<= (%eval-chain-cmp (lambda (a b) (num<= a b))))
(define %eval-num>  (%eval-chain-cmp (lambda (a b) (num> a b))))
(define %eval-num>= (%eval-chain-cmp (lambda (a b) (num>= a b))))

(define %eval-char=?  (%eval-chain-cmp (lambda (a b) (char=? a b))))
(define %eval-char<?  (%eval-chain-cmp (lambda (a b) (char<? a b))))
(define %eval-char<=? (%eval-chain-cmp (lambda (a b) (char<=? a b))))
(define %eval-char>?  (%eval-chain-cmp (lambda (a b) (char>? a b))))
(define %eval-char>=? (%eval-chain-cmp (lambda (a b) (char>=? a b))))

(define %eval-char-ci=?  (%eval-chain-cmp (lambda (a b) (char-ci=? a b))))
(define %eval-char-ci<?  (%eval-chain-cmp (lambda (a b) (char-ci<? a b))))
(define %eval-char-ci<=? (%eval-chain-cmp (lambda (a b) (char-ci<=? a b))))
(define %eval-char-ci>?  (%eval-chain-cmp (lambda (a b) (char-ci>? a b))))
(define %eval-char-ci>=? (%eval-chain-cmp (lambda (a b) (char-ci>=? a b))))

(define %eval-string=?  (%eval-chain-cmp (lambda (a b) (string=? a b))))
(define %eval-string<?  (%eval-chain-cmp (lambda (a b) (string<? a b))))
(define %eval-string<=? (%eval-chain-cmp (lambda (a b) (string<=? a b))))
(define %eval-string>?  (%eval-chain-cmp (lambda (a b) (string>? a b))))
(define %eval-string>=? (%eval-chain-cmp (lambda (a b) (string>=? a b))))

(define %eval-string-ci=?  (%eval-chain-cmp (lambda (a b) (string-ci=? a b))))
(define %eval-string-ci<?  (%eval-chain-cmp (lambda (a b) (string-ci<? a b))))
(define %eval-string-ci<=? (%eval-chain-cmp (lambda (a b) (string-ci<=? a b))))
(define %eval-string-ci>?  (%eval-chain-cmp (lambda (a b) (string-ci>? a b))))
(define %eval-string-ci>=? (%eval-chain-cmp (lambda (a b) (string-ci>=? a b))))

(define %eval-boolean=? (%eval-chain-cmp (lambda (a b) (boolean=? a b))))
(define %eval-symbol=?  (%eval-chain-cmp (lambda (a b) (symbol=? a b))))

(define %eval-gcd
  (case-lambda
    (() 0)
    ((a) (%math-abs a))
    ((a b) (gcd-2 a b))
    ((a b . rest)
     (let loop ((acc (gcd-2 a b)) (rs rest))
       (if (null? rs)
           acc
           (loop (gcd-2 acc (car rs)) (cdr rs)))))))

(define %eval-lcm
  (case-lambda
    (() 1)
    ((a) (%math-abs a))
    ((a b) (lcm-2 a b))
    ((a b . rest)
     (let loop ((acc (lcm-2 a b)) (rs rest))
       (if (null? rs)
           acc
           (loop (lcm-2 acc (car rs)) (cdr rs)))))))

(define %eval-list
  (case-lambda
    (args args)))

(define %eval-vector
  (case-lambda
    (args (list->vector args))))

(define %eval-string
  (case-lambda
    (args (list->string args))))

(define %eval-bytevector
  (case-lambda
    (args
     (let* ((len (length args))
            (bv (make-bytevector len 0)))
       (let loop ((i 0) (as args))
         (if (null? as)
             bv
             (begin
               (bytevector-u8-set! bv i (car as))
               (loop (+ i 1) (cdr as)))))))))

(define %eval-append
  (case-lambda
    (() '())
    ((a) a)
    ((a b) (append a b))
    ((a b . rest)
     (let loop ((acc (append a b)) (rs rest))
       (if (null? rs)
           acc
           (loop (append acc (car rs)) (cdr rs)))))))

(define %eval-string-append
  (case-lambda
    (() "")
    ((a) a)
    ((a b) (string-append a b))
    ((a b . rest)
     (let loop ((acc (string-append a b)) (rs rest))
       (if (null? rs)
           acc
           (loop (string-append acc (car rs)) (cdr rs)))))))

(define %eval-values
  (case-lambda
    (() (values))
    ((a) a)
    ((a b) (values a b))
    ((a b c) (values a b c))
    ((a b c d) (values a b c d))
    ((a b c d e) (values a b c d e))))

(define %eval-error
  (case-lambda
    ((msg) (error msg))
    ((msg . irritants) (raise-continuable (cons 'error-object (cons msg irritants))))))

(define %eval-memv
  (lambda (x ls)
    (cond ((null? ls) #f)
          ((eqv? x (car ls)) ls)
          (else (%eval-memv x (cdr ls))))))

(define %eval-member
  (lambda (x ls)
    (cond ((null? ls) #f)
          ((equal? x (car ls)) ls)
          (else (%eval-member x (cdr ls))))))

(define %eval-assv
  (lambda (x ls)
    (cond ((null? ls) #f)
          ((eqv? x (caar ls)) (car ls))
          (else (%eval-assv x (cdr ls))))))

(define %eval-assoc
  (lambda (x ls)
    (cond ((null? ls) #f)
          ((equal? x (caar ls)) (car ls))
          (else (%eval-assoc x (cdr ls))))))

(define %eval-read-char
  (case-lambda
    (() (read-char))
    ((p) (read-char p))))

(define %eval-peek-char
  (case-lambda
    (() (peek-char))
    ((p) (peek-char p))))

(define %eval-read-line
  (case-lambda
    (() (read-line))
    ((p) (read-line p))))

(define %eval-char-ready?
  (case-lambda
    (() (char-ready?))
    ((p) (char-ready? p))))

(define %eval-read-u8
  (case-lambda
    (() (read-u8))
    ((p) (read-u8 p))))

(define %eval-peek-u8
  (case-lambda
    (() (peek-u8))
    ((p) (peek-u8 p))))

(define %eval-u8-ready?
  (case-lambda
    (() (u8-ready?))
    ((p) (u8-ready? p))))

(define %eval-write-char
  (case-lambda
    ((c) (write-char c))
    ((c p) (write-char c p))))

(define %eval-write-string
  (case-lambda
    ((s) (write-string s))
    ((s p) (write-string s p))))

(define %eval-write-u8
  (case-lambda
    ((b) (write-u8 b))
    ((b p) (write-u8 b p))))

(define %eval-flush-output-port
  (case-lambda
    (() (flush-output-port))
    ((p) (flush-output-port p))))

(define %eval-read
  (case-lambda
    (() (read))
    ((p) (read p))))

(define %eval-string->number
  (case-lambda
    ((s) (string->number s))
    ((s r) (string->number s r))))

(define %eval-make-parameter
  (case-lambda
    ((init) (make-parameter-1 init))
    ((init conv) (make-parameter-2 init conv))))

;; -----------------------------------------------------------------------
;; Standard Library Export Catalog for `(environment ...)`
;; -----------------------------------------------------------------------

(define *r7rs-core-syntax-markers*
  (list
    (cons 'quote 'core-syntax)
    (cons 'quasiquote 'core-syntax)
    (cons 'unquote 'core-syntax)
    (cons 'unquote-splicing 'core-syntax)
    (cons 'lambda 'core-syntax)
    (cons 'if 'core-syntax)
    (cons 'set! 'core-syntax)
    (cons 'begin 'core-syntax)
    (cons 'cond 'core-syntax)
    (cons 'and 'core-syntax)
    (cons 'or 'core-syntax)
    (cons 'case 'core-syntax)
    (cons 'let 'core-syntax)
    (cons 'let* 'core-syntax)
    (cons 'letrec 'core-syntax)
    (cons 'letrec* 'core-syntax)
    (cons 'let-values 'core-syntax)
    (cons 'let*-values 'core-syntax)
    (cons 'define 'core-syntax)
    (cons 'define-values 'core-syntax)
    (cons 'define-syntax 'core-syntax)
    (cons 'let-syntax 'core-syntax)
    (cons 'letrec-syntax 'core-syntax)
    (cons 'syntax-rules 'core-syntax)
    (cons 'do 'core-syntax)
    (cons 'when 'core-syntax)
    (cons 'unless 'core-syntax)
    (cons 'parameterize 'core-syntax)
    (cons 'guard 'core-syntax)
    (cons 'cond-expand 'core-syntax)
    (cons 'define-record-type 'core-syntax)))

(define (%build-scheme-base-bindings)
  (list
    ;; Numeric operations
    (cons '+ %eval-plus)
    (cons '- %eval-minus)
    (cons '* %eval-mul)
    (cons '/ %eval-div)
    (cons '= %eval-num=)
    (cons '< %eval-num<)
    (cons '<= %eval-num<=)
    (cons '> %eval-num>)
    (cons '>= %eval-num>=)
    (cons 'number? (lambda (x) (number? x)))
    (cons 'complex? (lambda (x) (complex? x)))
    (cons 'real? (lambda (x) (real? x)))
    (cons 'rational? (lambda (x) (rational? x)))
    (cons 'integer? (lambda (x) (integer? x)))
    (cons 'exact? (lambda (x) (exact? x)))
    (cons 'inexact? (lambda (x) (inexact? x)))
    (cons 'exact-integer? exact-integer?)
    (cons 'exact exact)
    (cons 'inexact inexact)
    (cons 'zero? (lambda (x) (num= x 0)))
    (cons 'positive? (lambda (x) (num> x 0)))
    (cons 'negative? (lambda (x) (num< x 0)))
    (cons 'odd? (lambda (x) (not (= (modulo x 2) 0))))
    (cons 'even? (lambda (x) (= (modulo x 2) 0)))
    (cons 'max max)
    (cons 'min min)
    (cons 'abs (lambda (x) (if (num< x 0) (num- x) x)))
    (cons 'quotient (lambda (a b) (quotient a b)))
    (cons 'remainder remainder)
    (cons 'modulo (lambda (a b) (modulo a b)))
    (cons 'floor/ floor/)
    (cons 'floor-quotient floor-quotient)
    (cons 'floor-remainder floor-remainder)
    (cons 'truncate/ truncate/)
    (cons 'truncate-quotient truncate-quotient)
    (cons 'truncate-remainder truncate-remainder)
    (cons 'gcd %eval-gcd)
    (cons 'lcm %eval-lcm)
    (cons 'numerator numerator)
    (cons 'denominator denominator)
    (cons 'floor floor)
    (cons 'ceiling ceiling)
    (cons 'truncate truncate)
    (cons 'round round)
    (cons 'rationalize rationalize)
    (cons 'square square)
    (cons 'exact-integer-sqrt exact-integer-sqrt)
    (cons 'expt expt)
    (cons 'number->string number->string)
    (cons 'string->number %eval-string->number)
    ;; Booleans & Equivalence
    (cons 'not (lambda (x) (not x)))
    (cons 'boolean? (lambda (x) (boolean? x)))
    (cons 'boolean=? %eval-boolean=?)
    (cons 'eq? (lambda (a b) (eq? a b)))
    (cons 'eqv? (lambda (a b) (eqv? a b)))
    (cons 'equal? equal?)
    ;; Pairs & Lists
    (cons 'pair? (lambda (x) (pair? x)))
    (cons 'cons (lambda (a b) (cons a b)))
    (cons 'car (lambda (x) (car x)))
    (cons 'cdr (lambda (x) (cdr x)))
    (cons 'set-car! (lambda (p v) (set-car! p v)))
    (cons 'set-cdr! (lambda (p v) (set-cdr! p v)))
    (cons 'caar caar)
    (cons 'cadr cadr)
    (cons 'cdar cdar)
    (cons 'cddr cddr)
    (cons 'null? (lambda (x) (null? x)))
    (cons 'list? list?)
    (cons 'make-list make-list)
    (cons 'list %eval-list)
    (cons 'length length)
    (cons 'append %eval-append)
    (cons 'reverse reverse)
    (cons 'list-tail list-tail)
    (cons 'list-ref list-ref)
    (cons 'list-set! list-set!)
    (cons 'list-copy list-copy)
    (cons 'memq memq)
    (cons 'memv %eval-memv)
    (cons 'member %eval-member)
    (cons 'assq assq)
    (cons 'assv %eval-assv)
    (cons 'assoc %eval-assoc)
    ;; Symbols
    (cons 'symbol? (lambda (x) (symbol? x)))
    (cons 'symbol=? %eval-symbol=?)
    (cons 'symbol->string (lambda (s) (symbol->string s)))
    (cons 'string->symbol (lambda (s) (string->symbol s)))
    ;; Characters
    (cons 'char? (lambda (x) (char? x)))
    (cons 'char=? %eval-char=?)
    (cons 'char<? %eval-char<?)
    (cons 'char>? %eval-char>?)
    (cons 'char<=? %eval-char<=?)
    (cons 'char>=? %eval-char>=?)
    (cons 'char->integer (lambda (c) (char->integer c)))
    (cons 'integer->char (lambda (n) (integer->char n)))
    ;; Strings
    (cons 'string? (lambda (x) (string? x)))
    (cons 'make-string (lambda (n) (make-string n)))
    (cons 'string %eval-string)
    (cons 'string-length (lambda (s) (string-length s)))
    (cons 'string-ref (lambda (s i) (string-ref s i)))
    (cons 'string-set! (lambda (s i c) (string-set! s i c)))
    (cons 'string=? %eval-string=?)
    (cons 'string<? %eval-string<?)
    (cons 'string>? %eval-string>?)
    (cons 'string<=? %eval-string<=?)
    (cons 'string>=? %eval-string>=?)
    (cons 'substring substring)
    (cons 'string-append %eval-string-append)
    (cons 'string-copy string-copy)
    (cons 'string-fill! string-fill!)
    ;; Vectors
    (cons 'vector? (lambda (x) (vector? x)))
    (cons 'make-vector
          (case-lambda
            ((k) (make-vector k #f))
            ((k fill) (make-vector k fill))))
    (cons 'vector %eval-vector)
    (cons 'vector-length (lambda (v) (vector-length v)))
    (cons 'vector-ref (lambda (v i) (vector-ref v i)))
    (cons 'vector-set! (lambda (v i x) (vector-set! v i x)))
    ;; Bytevectors
    (cons 'bytevector? (lambda (x) (bytevector? x)))
    (cons 'make-bytevector
          (case-lambda
            ((k) (make-bytevector k 0))
            ((k byte) (make-bytevector k byte))))
    (cons 'bytevector %eval-bytevector)
    (cons 'bytevector-length (lambda (bv) (bytevector-length bv)))
    (cons 'bytevector-u8-ref (lambda (bv i) (bytevector-u8-ref bv i)))
    (cons 'bytevector-u8-set! (lambda (bv i b) (bytevector-u8-set! bv i b)))
    ;; Control features
    (cons 'procedure? (lambda (x) (procedure? x)))
    (cons 'apply apply)
    (cons 'map map)
    (cons 'string-map string-map)
    (cons 'vector-map vector-map)
    (cons 'for-each for-each)
    (cons 'string-for-each string-for-each)
    (cons 'vector-for-each vector-for-each)
    (cons 'call-with-current-continuation call-with-current-continuation)
    (cons 'call/cc call/cc)
    (cons 'values %eval-values)
    (cons 'call-with-values (lambda (prod cons-fn) (call-with-values prod cons-fn)))
    (cons 'dynamic-wind dynamic-wind)
    ;; Exceptions & Parameters
    (cons 'with-exception-handler with-exception-handler)
    (cons 'raise (lambda (x) (raise-continuable x)))
    (cons 'raise-continuable raise-continuable)
    (cons 'error %eval-error)
    (cons 'error-object? error-object?)
    (cons 'error-object-message error-object-message)
    (cons 'error-object-irritants error-object-irritants)
    (cons 'read-error? read-error?)
    (cons 'file-error? file-error?)
    (cons 'make-parameter %eval-make-parameter)
    ;; Ports & I/O
    (cons 'port? port?)
    (cons 'input-port? input-port?)
    (cons 'output-port? output-port?)
    (cons 'textual-port? textual-port?)
    (cons 'binary-port? binary-port?)
    (cons 'input-port-open? input-port-open?)
    (cons 'output-port-open? output-port-open?)
    (cons 'current-input-port current-input-port)
    (cons 'current-output-port current-output-port)
    (cons 'current-error-port current-error-port)
    (cons 'close-port close-port)
    (cons 'close-input-port close-input-port)
    (cons 'close-output-port close-output-port)
    (cons 'open-input-string open-input-string)
    (cons 'open-output-string open-output-string)
    (cons 'get-output-string get-output-string)
    (cons 'open-input-bytevector open-input-bytevector)
    (cons 'open-output-bytevector open-output-bytevector)
    (cons 'get-output-bytevector get-output-bytevector)
    (cons 'read-char %eval-read-char)
    (cons 'peek-char %eval-peek-char)
    (cons 'read-line %eval-read-line)
    (cons 'eof-object? (lambda (x) (eof-object? x)))
    (cons 'eof-object (lambda () *eof-object*))
    (cons 'char-ready? %eval-char-ready?)
    (cons 'read-u8 %eval-read-u8)
    (cons 'peek-u8 %eval-peek-u8)
    (cons 'u8-ready? %eval-u8-ready?)
    (cons 'newline newline)
    (cons 'write-char %eval-write-char)
    (cons 'write-string %eval-write-string)
    (cons 'write-u8 %eval-write-u8)
    (cons 'flush-output-port %eval-flush-output-port)
    (cons 'features features)))

(define (%build-scheme-inexact-bindings)
  (list
    (cons 'acos acos)
    (cons 'asin asin)
    (cons 'atan atan)
    (cons 'cos cos)
    (cons 'exp exp)
    (cons 'finite? finite?)
    (cons 'infinite? infinite?)
    (cons 'log log)
    (cons 'nan? nan?)
    (cons 'sin sin)
    (cons 'sqrt sqrt)
    (cons 'tan tan)))

(define (%build-scheme-complex-bindings)
  (list
    (cons 'angle angle)
    (cons 'imag-part imag-part)
    (cons 'magnitude magnitude)
    (cons 'make-polar make-polar)
    (cons 'make-rectangular make-rectangular)
    (cons 'real-part real-part)))

(define (%build-scheme-char-bindings)
  (list
    (cons 'char-alphabetic? char-alphabetic?)
    (cons 'char-ci<=? %eval-char-ci<=?)
    (cons 'char-ci<? %eval-char-ci<?)
    (cons 'char-ci=? %eval-char-ci=?)
    (cons 'char-ci>=? %eval-char-ci>=?)
    (cons 'char-ci>? %eval-char-ci>?)
    (cons 'char-downcase char-downcase)
    (cons 'char-foldcase char-foldcase)
    (cons 'char-lower-case? char-lower-case?)
    (cons 'char-numeric? char-numeric?)
    (cons 'char-upcase char-upcase)
    (cons 'char-upper-case? char-upper-case?)
    (cons 'char-whitespace? char-whitespace?)
    (cons 'digit-value digit-value)
    (cons 'string-ci<=? %eval-string-ci<=?)
    (cons 'string-ci<? %eval-string-ci<?)
    (cons 'string-ci=? %eval-string-ci=?)
    (cons 'string-ci>=? %eval-string-ci>=?)
    (cons 'string-ci>? %eval-string-ci>?)
    (cons 'string-downcase string-downcase)
    (cons 'string-foldcase string-foldcase)
    (cons 'string-upcase string-upcase)))

(define (%build-scheme-cxr-bindings)
  (list
    (cons 'caaaar (lambda (x) (car (car (car (car x))))))
    (cons 'caaadr (lambda (x) (car (car (car (cdr x))))))
    (cons 'caaar  (lambda (x) (car (car (car x)))))
    (cons 'caadar (lambda (x) (car (car (cdr (car x))))))
    (cons 'caaddr (lambda (x) (car (car (cdr (cdr x))))))
    (cons 'caadr  (lambda (x) (car (car (cdr x)))))
    (cons 'cadaar (lambda (x) (car (cdr (car (car x))))))
    (cons 'cadadr (lambda (x) (car (cdr (car (cdr x))))))
    (cons 'cadar  (lambda (x) (car (cdr (car x)))))
    (cons 'caddar (lambda (x) (car (cdr (cdr (car x))))))
    (cons 'cadddr (lambda (x) (car (cdr (cdr (cdr x))))))
    (cons 'caddr  caddr)
    (cons 'cdaaar (lambda (x) (cdr (car (car (car x))))))
    (cons 'cdaadr (lambda (x) (cdr (car (car (cdr x))))))
    (cons 'cdaar  (lambda (x) (cdr (car (car x)))))
    (cons 'cdadar (lambda (x) (cdr (car (cdr (car x))))))
    (cons 'cdaddr (lambda (x) (cdr (car (cdr (cdr x))))))
    (cons 'cdadr  (lambda (x) (cdr (car (cdr x)))))
    (cons 'cddaar (lambda (x) (cdr (cdr (car (car x))))))
    (cons 'cddadr (lambda (x) (cdr (cdr (car (cdr x))))))
    (cons 'cddar  (lambda (x) (cdr (cdr (car x)))))
    (cons 'cdddar (lambda (x) (cdr (cdr (cdr (car x))))))
    (cons 'cddddr (lambda (x) (cdr (cdr (cdr (cdr x))))))
    (cons 'cdddr  cdddr)))

(define (%build-scheme-lazy-bindings)
  (list
    (cons 'delay 'core-syntax)
    (cons 'delay-force 'core-syntax)
    (cons 'force force)
    (cons 'make-promise make-promise)
    (cons 'promise? promise?)))

(define (%build-scheme-file-bindings)
  (list
    (cons 'call-with-input-file call-with-input-file)
    (cons 'call-with-output-file call-with-output-file)
    (cons 'delete-file delete-file)
    (cons 'file-exists? file-exists?)
    (cons 'open-binary-input-file open-binary-input-file)
    (cons 'open-binary-output-file open-binary-output-file)
    (cons 'open-input-file open-input-file)
    (cons 'open-output-file open-output-file)
    (cons 'with-input-from-file with-input-from-file)
    (cons 'with-output-to-file with-output-to-file)))

(define (%build-scheme-process-context-bindings)
  (list
    (cons 'command-line command-line)
    (cons 'emergency-exit emergency-exit)
    (cons 'exit exit)
    (cons 'get-environment-variable get-environment-variable)
    (cons 'get-environment-variables get-environment-variables)))

(define (%build-scheme-read-bindings)
  (list
    (cons 'read %eval-read)))

(define (%build-scheme-write-bindings)
  (list
    (cons 'display display)
    (cons 'write write)
    (cons 'write-shared write-shared)
    (cons 'write-simple write-simple)))

(define (%build-scheme-time-bindings)
  (list
    (cons 'current-jiffy current-jiffy)
    (cons 'current-second current-second)
    (cons 'jiffies-per-second jiffies-per-second)))

(define (%build-scheme-case-lambda-bindings)
  (list
    (cons 'case-lambda 'core-syntax)))

;; Forward-referenced wrappers for eval / load / environments
(define (%build-scheme-eval-bindings)
  (list
    (cons 'eval (case-lambda
                  ((expr) (eval expr))
                  ((expr env) (eval expr env))))
    (cons 'environment (case-lambda (specs (apply environment specs))))))

(define (%build-scheme-repl-bindings)
  (list
    (cons 'interaction-environment (lambda () (interaction-environment)))))

(define (%build-scheme-load-bindings)
  (list
    (cons 'load (case-lambda
                  ((filename) (load filename))
                  ((filename env) (load filename env))))))

(define (%build-scheme-r5rs-bindings)
  (let* ((b1 (append (%build-scheme-base-bindings) (%build-scheme-inexact-bindings)))
         (b2 (append b1 (%build-scheme-complex-bindings)))
         (b3 (append b2 (%build-scheme-char-bindings)))
         (b4 (append b3 (%build-scheme-cxr-bindings)))
         (b5 (append b4 (%build-scheme-lazy-bindings)))
         (b6 (append b5 (%build-scheme-file-bindings)))
         (b7 (append b6 (%build-scheme-read-bindings)))
         (b8 (append b7 (%build-scheme-write-bindings)))
         (b9 (append b8 (%build-scheme-eval-bindings)))
         (b10 (append b9 (%build-scheme-repl-bindings)))
         (b11 (append b10 (%build-scheme-load-bindings))))
    (append b11
      (list
        (cons 'exact->inexact exact->inexact)
        (cons 'inexact->exact inexact->exact)
        (cons 'null-environment (lambda (v) (null-environment v)))
        (cons 'scheme-report-environment (lambda (v) (scheme-report-environment v)))))))

(define (%lookup-library-exports lib-name)
  (cond
    ((equal? lib-name '(scheme base))
     (append *r7rs-core-syntax-markers* (%build-scheme-base-bindings)))
    ((equal? lib-name '(scheme inexact))
     (%build-scheme-inexact-bindings))
    ((equal? lib-name '(scheme complex))
     (%build-scheme-complex-bindings))
    ((equal? lib-name '(scheme char))
     (%build-scheme-char-bindings))
    ((equal? lib-name '(scheme cxr))
     (%build-scheme-cxr-bindings))
    ((equal? lib-name '(scheme lazy))
     (%build-scheme-lazy-bindings))
    ((equal? lib-name '(scheme file))
     (%build-scheme-file-bindings))
    ((equal? lib-name '(scheme process-context))
     (%build-scheme-process-context-bindings))
    ((equal? lib-name '(scheme read))
     (%build-scheme-read-bindings))
    ((equal? lib-name '(scheme write))
     (%build-scheme-write-bindings))
    ((equal? lib-name '(scheme time))
     (%build-scheme-time-bindings))
    ((equal? lib-name '(scheme case-lambda))
     (%build-scheme-case-lambda-bindings))
    ((equal? lib-name '(scheme eval))
     (%build-scheme-eval-bindings))
    ((equal? lib-name '(scheme repl))
     (%build-scheme-repl-bindings))
    ((equal? lib-name '(scheme load))
     (%build-scheme-load-bindings))
    ((equal? lib-name '(scheme r5rs))
     (append *r7rs-core-syntax-markers* (%build-scheme-r5rs-bindings)))
    ((or (equal? lib-name '(scheme box)) (equal? lib-name '(srfi 111)))
     (list (cons 'box box) (cons 'box? box?) (cons 'unbox unbox) (cons 'set-box! set-box!)))
    ((or (equal? lib-name '(scheme comparator)) (equal? lib-name '(srfi 128)))
     (list (cons 'comparator? (lambda (x) (comparator? x)))
           (cons 'make-comparator make-comparator)
           (cons 'make-default-comparator make-default-comparator)
           (cons '=? =?)
           (cons '<? <?)
           (cons '<=? <=?)
           (cons '>? >?)
           (cons '>=? >=?)))
    (else
     (error "environment: unknown library specifier" lib-name))))

;; -----------------------------------------------------------------------
;; Import Set Modifiers: only, except, prefix, rename
;; -----------------------------------------------------------------------

(define (%resolve-import-set spec)
  (if (not (pair? spec))
      (error "environment: malformed import set" spec)
      (let ((head (car spec)))
        (cond
          ((eq? head 'only)
           (let ((base (%resolve-import-set (cadr spec)))
                 (ids (cddr spec)))
             (let loop ((ids-left ids) (acc '()))
               (if (null? ids-left)
                   (reverse acc)
                   (let* ((id (car ids-left))
                          (cell (assq id base)))
                     (if (not cell)
                         (error "environment (only): identifier not exported by import set" id)
                         (loop (cdr ids-left) (cons cell acc))))))))
          ((eq? head 'except)
           (let ((base (%resolve-import-set (cadr spec)))
                 (ids (cddr spec)))
             (let check-ids ((rem ids))
               (if (pair? rem)
                   (if (not (assq (car rem) base))
                       (error "environment (except): identifier not exported by import set" (car rem))
                       (check-ids (cdr rem)))))
             (let loop ((bs base) (acc '()))
               (if (null? bs)
                   (reverse acc)
                   (if (memq (caar bs) ids)
                       (loop (cdr bs) acc)
                       (loop (cdr bs) (cons (car bs) acc)))))))
          ((eq? head 'prefix)
           (if (or (null? (cdr spec)) (null? (cddr spec)) (not (symbol? (caddr spec))))
               (error "environment (prefix): malformed prefix import set" spec)
               (let ((base (%resolve-import-set (cadr spec)))
                     (pref-str (symbol->string (caddr spec))))
                 (let loop ((bs base) (acc '()))
                   (if (null? bs)
                       (reverse acc)
                       (let* ((old-sym (caar bs))
                              (new-sym (string->symbol (string-append pref-str (symbol->string old-sym)))))
                         (loop (cdr bs) (cons (cons new-sym (cdar bs)) acc))))))))
          ((eq? head 'rename)
           (let ((base (%resolve-import-set (cadr spec)))
                 (pairs (cddr spec)))
             (let check-pairs ((ps pairs))
               (if (pair? ps)
                   (let ((p (car ps)))
                     (if (or (not (pair? p)) (null? (cdr p)) (not (assq (car p) base)))
                         (error "environment (rename): invalid rename pair" p)
                         (check-pairs (cdr ps))))))
             (let loop ((bs base) (acc '()))
               (if (null? bs)
                   (reverse acc)
                   (let* ((old-sym (caar bs))
                          (ren-pair (assq old-sym pairs))
                          (new-sym (if ren-pair (cadr ren-pair) old-sym)))
                     (loop (cdr bs) (cons (cons new-sym (cdar bs)) acc)))))))
          (else
           (%lookup-library-exports spec))))))

;; -----------------------------------------------------------------------
;; §6.12 Environment Constructors:
;;   environment, null-environment, scheme-report-environment, interaction-environment
;; -----------------------------------------------------------------------

(define environment
  (case-lambda
    (specs
     (let loop ((ss specs) (acc '()))
       (if (null? ss)
           (%make-r7rs-env acc '() #f #f specs)
           (let ((resolved (%resolve-import-set (car ss))))
             (loop (cdr ss) (append resolved acc))))))))

(define (null-environment version)
  (if (not (or (eqv? version 5) (eqv? version 7)))
      (error "null-environment: unsupported Scheme report version (expected 5)" version)
      (%make-r7rs-env *r7rs-core-syntax-markers* '() #f #f 'null-environment)))

(define (scheme-report-environment version)
  (if (not (or (eqv? version 5) (eqv? version 7)))
      (error "scheme-report-environment: unsupported Scheme report version (expected 5)" version)
      (%make-r7rs-env
        (append *r7rs-core-syntax-markers* (%build-scheme-r5rs-bindings))
        '()
        #f
        #f
        'scheme-report-environment)))

(define *global-interaction-env-box* (make-vector 1 #f))

(define (make-interaction-environment)
  (let* ((b1 (append *r7rs-core-syntax-markers* (%build-scheme-r5rs-bindings)))
         (b2 (append b1 (%build-scheme-process-context-bindings)))
         (b3 (append b2 (%build-scheme-time-bindings)))
         (b4 (append b3 (%build-scheme-case-lambda-bindings))))
    (%make-r7rs-env
      b4
      '()
      #f
      #t
      'interaction-environment)))

(define (interaction-environment)
  (let ((cur (vector-ref *global-interaction-env-box* 0)))
    (if cur
        cur
        (let ((fresh (make-interaction-environment)))
          (vector-set! *global-interaction-env-box* 0 fresh)
          fresh))))

;; Forward declarations for eval and load (implemented in Issues #717 and #718)
(define eval
  (case-lambda
    ((expr)
     (%r7rs-eval expr (interaction-environment)))
    ((expr env)
     (%r7rs-eval expr env))))

(define (%r7rs-eval expr env)
  (if (not (environment? env))
      (error "eval: expected environment specifier" env)
      (if (symbol? expr)
          (%r7rs-env-lookup env expr)
          expr)))

(define load
  (case-lambda
    ((filename)
     (load filename (interaction-environment)))
    ((filename env)
     (if (not (environment? env))
         (error "load: expected environment specifier" env)
         #t))))
