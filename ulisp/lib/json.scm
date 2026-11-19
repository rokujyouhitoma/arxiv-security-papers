;;; =======================================================================
;;; ULisp Standard Library: JSON Parser and Serializer (SRFI 180 / RFC 8259)
;;; R7RS-large Orange / Hypnos Docket: (scheme json)
;;; Conforms to DSN-33 Architecture Specification & Issue #862
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

;; ---------------------------------------------------------------------
;; §1. Error and Predicates
;; ---------------------------------------------------------------------

(define json-error
  (case-lambda
    ((reason) (list 'json-error reason))
    ((reason irritant) (list 'json-error reason irritant))
    ((reason irritant1 irritant2) (list 'json-error reason irritant1 irritant2))))

(define (json-error? obj)
  (and (pair? obj) (eq? (car obj) 'json-error)))

(define (json-error-reason obj)
  (if (json-error? obj)
      (cadr obj)
      (error "json-error-reason: expected json-error" obj)))

(define (json-null? obj)
  (eq? obj 'null))

;; ---------------------------------------------------------------------
;; §2. Parameters
;; ---------------------------------------------------------------------

(define json-nesting-depth-limit (make-parameter 1000))
(define json-number-of-character-limit (make-parameter #f))

;; ---------------------------------------------------------------------
;; §3. Character Source Abstraction & Limits Enforcement
;; ---------------------------------------------------------------------

(define (%make-char-source src)
  (let* ((actual-src (if (or (null? src) (not src))
                         (current-input-port)
                         src))
         (is-port (input-port? actual-src))
         (peeked-cell (cons '() #f))
         (count-cell (cons 0 '()))
         (char-limit (json-number-of-character-limit)))
    (define (read-raw)
      (if (cdr peeked-cell)
          (let ((ch (car peeked-cell)))
            (set-car! peeked-cell '())
            (set-cdr! peeked-cell #f)
            ch)
          (if is-port
              (read-char actual-src)
              (actual-src))))
    (define (peek-raw)
      (if (cdr peeked-cell)
          (car peeked-cell)
          (let ((ch (if is-port
                        (read-char actual-src)
                        (actual-src))))
            (set-car! peeked-cell ch)
            (set-cdr! peeked-cell #t)
            ch)))
    (define (get-ch)
      (let ((ch (read-raw)))
        (if (not (eof-object? ch))
            (let ((cnt (+ (car count-cell) 1)))
              (set-car! count-cell cnt)
              (if (and char-limit (> cnt char-limit))
                  (raise (json-error "json-read: number of character limit exceeded" cnt))
                  ch))
            ch)))
    (define (peek-ch)
      (peek-raw))
    (vector get-ch peek-ch)))

(define (%src-get-char src)
  ((vector-ref src 0)))

(define (%src-peek-char src)
  ((vector-ref src 1)))

(define (%json-whitespace? ch)
  (and (char? ch)
       (or (char=? ch #\space)
           (char=? ch #\tab)
           (char=? ch #\newline)
           (char=? ch #\return))))

(define (%json-skip-whitespace src)
  (let loop ()
    (let ((ch (%src-peek-char src)))
      (if (and (not (eof-object? ch)) (%json-whitespace? ch))
          (begin
            (%src-get-char src)
            (loop))
          #t))))

;; ---------------------------------------------------------------------
;; §4. Lexer & Parsing Primitives (RFC 8259 Compliance)
;; ---------------------------------------------------------------------

(define (%json-hex-digit? ch)
  (and (char? ch)
       (or (and (char>=? ch #\0) (char<=? ch #\9))
           (and (char>=? ch #\a) (char<=? ch #\f))
           (and (char>=? ch #\A) (char<=? ch #\F)))))

(define (%json-hex-val ch)
  (cond
    ((and (char>=? ch #\0) (char<=? ch #\9))
     (- (char->integer ch) 48))
    ((and (char>=? ch #\a) (char<=? ch #\f))
     (+ (- (char->integer ch) 97) 10))
    ((and (char>=? ch #\A) (char<=? ch #\F))
     (+ (- (char->integer ch) 65) 10))
    (else 0)))

(define (%read-4hex src)
  (let* ((c1 (%src-get-char src))
         (c2 (%src-get-char src))
         (c3 (%src-get-char src))
         (c4 (%src-get-char src)))
    (if (and (%json-hex-digit? c1)
             (%json-hex-digit? c2)
             (%json-hex-digit? c3)
             (%json-hex-digit? c4))
        (+ (* (%json-hex-val c1) 4096)
           (* (%json-hex-val c2) 256)
           (* (%json-hex-val c3) 16)
           (%json-hex-val c4))
        (raise (json-error "json-read: invalid \\u hex escape in string")))))

(define (%json-read-string-content src)
  ;; Opening quote was already consumed
  (let loop ((acc '()))
    (let ((ch (%src-get-char src)))
      (cond
        ((eof-object? ch)
         (raise (json-error "json-read: unexpected end of input in string literal")))
        ((char=? ch #\")
         (list->string (reverse acc)))
        ((< (char->integer ch) 32)
         (raise (json-error "json-read: unescaped control character in string literal" (char->integer ch))))
        ((char=? ch #\\)
         (let ((esc (%src-get-char src)))
           (cond
             ((eof-object? esc)
              (raise (json-error "json-read: unexpected end of input in escape sequence")))
             ((char=? esc #\") (loop (cons #\" acc)))
             ((char=? esc #\\) (loop (cons #\\ acc)))
             ((char=? esc #\/) (loop (cons #\/ acc)))
             ((char=? esc #\b) (loop (cons (integer->char 8) acc)))
             ((char=? esc #\f) (loop (cons (integer->char 12) acc)))
             ((char=? esc #\n) (loop (cons #\newline acc)))
             ((char=? esc #\r) (loop (cons (integer->char 13) acc)))
             ((char=? esc #\t) (loop (cons #\tab acc)))
             ((char=? esc #\u)
              (let ((code (%read-4hex src)))
                (cond
                  ;; High surrogate: 0xD800 - 0xDBFF
                  ((and (>= code #xd800) (<= code #xdbff))
                   (let ((slash (%src-get-char src))
                         (u (%src-get-char src)))
                     (if (and (eqv? slash #\\) (eqv? u #\u))
                         (let ((low-code (%read-4hex src)))
                           (if (and (>= low-code #xdc00) (<= low-code #xdfff))
                               (let ((scalar (+ #x10000
                                                (* (- code #xd800) #x400)
                                                (- low-code #xdc00))))
                                 (loop (cons (integer->char scalar) acc)))
                               (raise (json-error "json-read: invalid low surrogate after high surrogate" low-code))))
                         (raise (json-error "json-read: lone high surrogate without following low surrogate" code)))))
                  ;; Lone low surrogate: 0xDC00 - 0xDFFF
                  ((and (>= code #xdc00) (<= code #xdfff))
                   (raise (json-error "json-read: lone low surrogate" code)))
                  (else
                   (loop (cons (integer->char code) acc))))))
             (else
              (raise (json-error "json-read: invalid escape sequence" esc))))))
        (else
         (loop (cons ch acc)))))))

(define (%json-digit? ch)
  (and (char? ch) (char>=? ch #\0) (char<=? ch #\9)))

(define (%json-read-number src)
  (let ((acc-cell (cons '() '())))
    ;; 1. Optional minus
    (let ((c (%src-peek-char src)))
      (if (eqv? c #\-)
          (begin
            (set-car! acc-cell (cons (%src-get-char src) (car acc-cell)))
            (let ((next (%src-peek-char src)))
              (if (or (eof-object? next) (not (%json-digit? next)))
                  (raise (json-error "json-read: expected digit after minus sign" next)))))))
    ;; 2. Integer part
    (let ((c (%src-peek-char src)))
      (cond
        ((eqv? c #\0)
         (set-car! acc-cell (cons (%src-get-char src) (car acc-cell)))
         ;; Leading zero check: if next is digit, illegal in JSON
         (let ((next (%src-peek-char src)))
           (if (%json-digit? next)
               (raise (json-error "json-read: leading zeros are not permitted in JSON numbers" next)))))
        ((and (char? c) (char>=? c #\1) (char<=? c #\9))
         (let loop ()
           (let ((digit (%src-peek-char src)))
             (if (%json-digit? digit)
                 (begin
                   (set-car! acc-cell (cons (%src-get-char src) (car acc-cell)))
                   (loop))))))
        (else
         (raise (json-error "json-read: expected digit in number" c)))))
    ;; 3. Optional fraction
    (let ((dot (%src-peek-char src)))
      (if (eqv? dot #\.)
          (begin
            (set-car! acc-cell (cons (%src-get-char src) (car acc-cell)))
            (let ((first-frac (%src-peek-char src)))
              (if (or (eof-object? first-frac) (not (%json-digit? first-frac)))
                  (raise (json-error "json-read: expected digit after decimal point" first-frac))))
            (let loop ()
              (let ((frac (%src-peek-char src)))
                (if (%json-digit? frac)
                    (begin
                      (set-car! acc-cell (cons (%src-get-char src) (car acc-cell)))
                      (loop))))))))
    ;; 4. Optional exponent
    (let ((exp-ch (%src-peek-char src)))
      (if (or (eqv? exp-ch #\e) (eqv? exp-ch #\E))
          (begin
            (set-car! acc-cell (cons (%src-get-char src) (car acc-cell)))
            (let ((sign (%src-peek-char src)))
              (if (or (eqv? sign #\+) (eqv? sign #\-))
                  (set-car! acc-cell (cons (%src-get-char src) (car acc-cell)))))
            (let ((first-exp (%src-peek-char src)))
              (if (or (eof-object? first-exp) (not (%json-digit? first-exp)))
                  (raise (json-error "json-read: expected digit in exponent" first-exp))))
            (let loop ()
              (let ((exp-digit (%src-peek-char src)))
                (if (%json-digit? exp-digit)
                    (begin
                      (set-car! acc-cell (cons (%src-get-char src) (car acc-cell)))
                      (loop))))))))
    ;; 5. Construct Scheme number
    (let* ((num-str (list->string (reverse (car acc-cell))))
           (num (string->number num-str)))
      (if (number? num)
          num
          (raise (json-error "json-read: invalid number format" num-str))))))

(define (%json-match-literal src expected-str result-val)
  (let ((len (string-length expected-str)))
    (let loop ((i 0))
      (if (< i len)
          (let ((ch (%src-get-char src))
                (expected (string-ref expected-str i)))
            (if (eqv? ch expected)
                (loop (+ i 1))
                (raise (json-error "json-read: unexpected literal token" ch expected-str))))
          result-val))))

;; ---------------------------------------------------------------------
;; §5. JSON Read & In-Memory Value Parser
;; ---------------------------------------------------------------------

(define (%json-parse-value src depth)
  (let ((limit (json-nesting-depth-limit)))
    (if (and limit (> depth limit))
        (raise (json-error "json-read: nesting depth limit exceeded" depth))
        (begin
          (%json-skip-whitespace src)
          (let ((ch (%src-peek-char src)))
            (cond
              ((eof-object? ch)
               (raise (json-error "json-read: unexpected end of file")))
              ((eqv? ch #\")
               (%src-get-char src)
               (%json-read-string-content src))
              ((eqv? ch #\[)
               (%json-parse-array src depth))
              ((eqv? ch #\{)
               (%json-parse-object src depth))
              ((eqv? ch #\t)
               (%json-match-literal src "true" #t))
              ((eqv? ch #\f)
               (%json-match-literal src "false" #f))
              ((eqv? ch #\n)
               (%json-match-literal src "null" 'null))
              ((or (eqv? ch #\-) (%json-digit? ch))
               (%json-read-number src))
              (else
               (raise (json-error "json-read: unexpected character" ch)))))))))

(define (%json-parse-array src depth)
  (%src-get-char src) ;; consume '['
  (%json-skip-whitespace src)
  (let ((ch (%src-peek-char src)))
    (if (eqv? ch #\])
        (begin
          (%src-get-char src)
          (vector))
        (let loop ((acc '()))
          (let ((val (%json-parse-value src (+ depth 1))))
            (%json-skip-whitespace src)
            (let ((next (%src-get-char src)))
              (cond
                ((eqv? next #\,)
                 (%json-skip-whitespace src)
                 (if (eqv? (%src-peek-char src) #\])
                     (raise (json-error "json-read: trailing comma in array"))
                     (loop (cons val acc))))
                ((eqv? next #\])
                 (list->vector (reverse (cons val acc))))
                (else
                 (raise (json-error "json-read: expected ',' or ']' in array" next))))))))))

(define (%json-parse-object src depth)
  (%src-get-char src) ;; consume '{'
  (%json-skip-whitespace src)
  (let ((ch (%src-peek-char src)))
    (if (eqv? ch #\})
        (begin
          (%src-get-char src)
          '())
        (let loop ((acc '()))
          (%json-skip-whitespace src)
          (let ((q (%src-get-char src)))
            (if (not (eqv? q #\"))
                (raise (json-error "json-read: expected string key in object" q))
                (let ((key-str (%json-read-string-content src)))
                  (%json-skip-whitespace src)
                  (let ((colon (%src-get-char src)))
                    (if (not (eqv? colon #\:))
                        (raise (json-error "json-read: expected ':' after object key" colon))
                        (let ((val (%json-parse-value src (+ depth 1))))
                          (let ((pair (cons (string->symbol key-str) val)))
                            (%json-skip-whitespace src)
                            (let ((next (%src-get-char src)))
                              (cond
                                ((eqv? next #\,)
                                 (%json-skip-whitespace src)
                                 (if (eqv? (%src-peek-char src) #\})
                                     (raise (json-error "json-read: trailing comma in object"))
                                     (loop (cons pair acc))))
                                ((eqv? next #\})
                                 (reverse (cons pair acc)))
                                (else
                                 (raise (json-error "json-read: expected ',' or '}' in object" next))))))))))))))))

(define json-read
  (case-lambda
    (() (json-read (current-input-port)))
    ((port-or-gen)
     (let ((src (%make-char-source port-or-gen)))
       (%json-skip-whitespace src)
       (let ((ch (%src-peek-char src)))
         (if (eof-object? ch)
             ch
             (%json-parse-value src 0)))))))

;; ---------------------------------------------------------------------
;; §6. Streaming Event Generator & Fold (SRFI 180)
;; ---------------------------------------------------------------------

(define json-generator
  (case-lambda
    (() (json-generator (current-input-port)))
    ((port-or-gen)
     (let* ((src (%make-char-source port-or-gen))
            (stack-cell (cons (list 'top) '()))
            (depth-limit (json-nesting-depth-limit)))
       (lambda ()
         (if (null? (car stack-cell))
             (eof-object)
             (let* ((frames (car stack-cell))
                    (state (car frames)))
               (if (and depth-limit (> (length frames) depth-limit))
                   (raise (json-error "json-generator: nesting depth limit exceeded" (length frames))))
               (%json-skip-whitespace src)
               (cond
                 ;; ---------------------------------------------------
                 ;; State: top
                 ;; ---------------------------------------------------
                 ((eq? state 'top)
                  (set-car! stack-cell (cons 'top-done (cdr frames)))
                  (let ((ch (%src-peek-char src)))
                    (cond
                      ((eof-object? ch)
                       (set-car! stack-cell '())
                       (eof-object))
                      ((eqv? ch #\[)
                       (%src-get-char src)
                       (set-car! stack-cell (cons 'array-start (car stack-cell)))
                       'array-start)
                      ((eqv? ch #\{)
                       (%src-get-char src)
                       (set-car! stack-cell (cons 'object-start (car stack-cell)))
                       'object-start)
                      (else
                       (%json-parse-value src 0)))))

                 ;; ---------------------------------------------------
                 ;; State: top-done
                 ;; ---------------------------------------------------
                 ((eq? state 'top-done)
                  (set-car! stack-cell '())
                  (eof-object))

                 ;; ---------------------------------------------------
                 ;; State: array-start
                 ;; ---------------------------------------------------
                 ((eq? state 'array-start)
                  (let ((ch (%src-peek-char src)))
                    (cond
                      ((eof-object? ch)
                       (raise (json-error "json-generator: unexpected EOF in array")))
                      ((eqv? ch #\])
                       (%src-get-char src)
                       (set-car! stack-cell (cdr frames))
                       'array-end)
                      ((eqv? ch #\[)
                       (%src-get-char src)
                       (set-car! stack-cell (cons 'array-start (cons 'array-next (cdr frames))))
                       'array-start)
                      ((eqv? ch #\{)
                       (%src-get-char src)
                       (set-car! stack-cell (cons 'object-start (cons 'array-next (cdr frames))))
                       'object-start)
                      (else
                       (set-car! stack-cell (cons 'array-next (cdr frames)))
                       (%json-parse-value src (length frames))))))

                 ;; ---------------------------------------------------
                 ;; State: array-next
                 ;; ---------------------------------------------------
                 ((eq? state 'array-next)
                  (let ((ch (%src-get-char src)))
                    (cond
                      ((eqv? ch #\,)
                       (%json-skip-whitespace src)
                       (let ((next (%src-peek-char src)))
                         (cond
                           ((eof-object? next)
                            (raise (json-error "json-generator: unexpected EOF after comma in array")))
                           ((eqv? next #\])
                            (raise (json-error "json-generator: trailing comma in array")))
                           ((eqv? next #\[)
                            (%src-get-char src)
                            (set-car! stack-cell (cons 'array-start frames))
                            'array-start)
                           ((eqv? next #\{)
                            (%src-get-char src)
                            (set-car! stack-cell (cons 'object-start frames))
                            'object-start)
                           (else
                            (%json-parse-value src (length frames))))))
                      ((eqv? ch #\])
                       (set-car! stack-cell (cdr frames))
                       'array-end)
                      (else
                       (raise (json-error "json-generator: expected ',' or ']' in array" ch))))))

                 ;; ---------------------------------------------------
                 ;; State: object-start
                 ;; ---------------------------------------------------
                 ((eq? state 'object-start)
                  (let ((ch (%src-peek-char src)))
                    (cond
                      ((eof-object? ch)
                       (raise (json-error "json-generator: unexpected EOF in object")))
                      ((eqv? ch #\})
                       (%src-get-char src)
                       (set-car! stack-cell (cdr frames))
                       'object-end)
                      ((eqv? ch #\")
                       (%src-get-char src)
                       (let ((k (%json-read-string-content src)))
                         (%json-skip-whitespace src)
                         (let ((colon (%src-get-char src)))
                           (if (not (eqv? colon #\:))
                               (raise (json-error "json-generator: expected ':' after key in object" colon))
                               (begin
                                 (set-car! stack-cell (cons 'object-val (cdr frames)))
                                 k)))))
                      (else
                       (raise (json-error "json-generator: expected string key or '}' in object" ch))))))

                 ;; ---------------------------------------------------
                 ;; State: object-val
                 ;; ---------------------------------------------------
                 ((eq? state 'object-val)
                  (let ((ch (%src-peek-char src)))
                    (cond
                      ((eof-object? ch)
                       (raise (json-error "json-generator: unexpected EOF expecting value in object")))
                      ((eqv? ch #\[)
                       (%src-get-char src)
                       (set-car! stack-cell (cons 'array-start (cons 'object-next (cdr frames))))
                       'array-start)
                      ((eqv? ch #\{)
                       (%src-get-char src)
                       (set-car! stack-cell (cons 'object-start (cons 'object-next (cdr frames))))
                       'object-start)
                      (else
                       (set-car! stack-cell (cons 'object-next (cdr frames)))
                       (%json-parse-value src (length frames))))))

                 ;; ---------------------------------------------------
                 ;; State: object-next
                 ;; ---------------------------------------------------
                 ((eq? state 'object-next)
                  (let ((ch (%src-get-char src)))
                    (cond
                      ((eqv? ch #\,)
                       (%json-skip-whitespace src)
                       (let ((q (%src-get-char src)))
                         (cond
                           ((eof-object? q)
                            (raise (json-error "json-generator: unexpected EOF after comma in object")))
                           ((eqv? q #\})
                            (raise (json-error "json-generator: trailing comma in object")))
                           ((eqv? q #\")
                            (let ((k (%json-read-string-content src)))
                              (%json-skip-whitespace src)
                              (let ((colon (%src-get-char src)))
                                (if (not (eqv? colon #\:))
                                    (raise (json-error "json-generator: expected ':' after key in object" colon))
                                    (begin
                                      (set-car! stack-cell (cons 'object-val (cdr frames)))
                                      k)))))
                           (else
                            (raise (json-error "json-generator: expected string key in object" q))))))
                      ((eqv? ch #\})
                       (set-car! stack-cell (cdr frames))
                       'object-end)
                      (else
                       (raise (json-error "json-generator: expected ',' or '}' in object" ch))))))

                 (else
                  (raise (json-error "json-generator: invalid internal state" state)))))))))))

(define json-fold
  (case-lambda
    ((proc array-start array-end object-start object-end seed)
     (json-fold proc array-start array-end object-start object-end seed (current-input-port)))
    ((proc array-start array-end object-start object-end seed port-or-gen)
     (let ((gen (json-generator port-or-gen)))
       (let loop ((cur-seed seed))
         (let ((token (gen)))
           (cond
             ((eof-object? token)
              cur-seed)
             ((eq? token 'array-start)
              (loop (array-start cur-seed)))
             ((eq? token 'array-end)
              (loop (array-end cur-seed)))
             ((eq? token 'object-start)
              (loop (object-start cur-seed)))
             ((eq? token 'object-end)
              (loop (object-end cur-seed)))
             (else
              (loop (proc token cur-seed))))))))))

;; ---------------------------------------------------------------------
;; §7. JSON Lines & JSON Sequence Parsers
;; ---------------------------------------------------------------------

(define json-lines-read
  (case-lambda
    (() (json-lines-read (current-input-port)))
    ((port-or-gen)
     (let ((src (%make-char-source port-or-gen)))
       (lambda ()
         ;; Skip blank lines
         (let loop ()
           (let ((ch (%src-peek-char src)))
             (cond
               ((eof-object? ch)
                (eof-object))
               ((or (eqv? ch #\newline) (eqv? ch #\return) (eqv? ch #\space) (eqv? ch #\tab))
                (%src-get-char src)
                (loop))
               (else
                (let ((val (%json-parse-value src 0)))
                  ;; Consume line terminator if present
                  (let inner ()
                    (let ((next (%src-peek-char src)))
                      (cond
                        ((or (eqv? next #\space) (eqv? next #\tab))
                         (%src-get-char src)
                         (inner))
                        ((eqv? next #\newline)
                         (%src-get-char src)
                         val)
                        ((eqv? next #\return)
                         (%src-get-char src)
                         (if (eqv? (%src-peek-char src) #\newline)
                             (%src-get-char src))
                         val)
                        ((eof-object? next)
                         val)
                        (else
                         val))))))))))))))

(define json-sequence-read
  (case-lambda
    (() (json-sequence-read (current-input-port)))
    ((port-or-gen)
     (let ((src (%make-char-source port-or-gen)))
       (lambda ()
         ;; Find next record separator (#\x1e)
         (let loop ()
           (let ((ch (%src-get-char src)))
             (cond
               ((eof-object? ch)
                (eof-object))
               ((eqv? ch (integer->char #x1e))
                (%json-skip-whitespace src)
                (if (eof-object? (%src-peek-char src))
                    (eof-object)
                    (%json-parse-value src 0)))
               (else
                (loop))))))))))

;; ---------------------------------------------------------------------
;; §8. JSON Serializer & Accumulator (json-write & json-accumulator)
;; ---------------------------------------------------------------------

(define (%json-write-escaped-string str write-fn)
  (write-fn "\"")
  (let ((len (string-length str)))
    (let loop ((i 0))
      (if (< i len)
          (let* ((ch (string-ref str i))
                 (code (char->integer ch)))
            (cond
              ((eqv? ch #\") (write-fn "\\\""))
              ((eqv? ch #\\) (write-fn "\\\\"))
              ((eqv? ch #\newline) (write-fn "\\n"))
              ((eqv? ch (integer->char 13)) (write-fn "\\r"))
              ((eqv? ch #\tab) (write-fn "\\t"))
              ((eqv? ch (integer->char 8)) (write-fn "\\b"))
              ((eqv? ch (integer->char 12)) (write-fn "\\f"))
              ((< code 32)
               (let* ((digits "0123456789abcdef")
                      (d1 (string-ref digits (modulo (quotient code 4096) 16)))
                      (d2 (string-ref digits (modulo (quotient code 256) 16)))
                      (d3 (string-ref digits (modulo (quotient code 16) 16)))
                      (d4 (string-ref digits (modulo code 16))))
                 (write-fn (string #\\ #\u d1 d2 d3 d4))))
              (else
               (write-fn (string ch))))
            (loop (+ i 1))))))
  (write-fn "\""))

(define json-write
  (case-lambda
    ((obj) (json-write obj (current-output-port)))
    ((obj port-or-acc)
     (let* ((is-port (output-port? port-or-acc))
            (write-str (if is-port
                           (lambda (s) (display s port-or-acc))
                           port-or-acc))
            (depth-limit (json-nesting-depth-limit)))
       (define (recur datum depth)
         (if (and depth-limit (> depth depth-limit))
             (raise (json-error "json-write: nesting depth limit exceeded" depth))
             (cond
               ((eq? datum 'null)
                (write-str "null"))
               ((eq? datum #t)
                (write-str "true"))
               ((eq? datum #f)
                (write-str "false"))
               ((number? datum)
                (write-str (number->string datum)))
               ((string? datum)
                (%json-write-escaped-string datum write-str))
               ((symbol? datum)
                (%json-write-escaped-string (symbol->string datum) write-str))
               ((vector? datum)
                (write-str "[")
                (let ((len (vector-length datum)))
                  (let loop ((i 0))
                    (if (< i len)
                        (begin
                          (if (> i 0) (write-str ", "))
                          (recur (vector-ref datum i) (+ depth 1))
                          (loop (+ i 1))))))
                (write-str "]"))
               ((null? datum)
                (write-str "{}"))
               ((pair? datum)
                (write-str "{")
                (let loop ((pairs datum) (first #t))
                  (if (null? pairs)
                      (write-str "}")
                      (let ((p (car pairs)))
                        (if (not (pair? p))
                            (raise (json-error "json-write: expected pair in object alist" p))
                            (let ((k (car p))
                                  (v (cdr p)))
                              (if (not first) (write-str ", "))
                              (cond
                                ((string? k) (%json-write-escaped-string k write-str))
                                ((symbol? k) (%json-write-escaped-string (symbol->string k) write-str))
                                (else (raise (json-error "json-write: object key must be string or symbol" k))))
                              (write-str ": ")
                              (recur v (+ depth 1))
                              (loop (cdr pairs) #f)))))))
               (else
                (raise (json-error "json-write: unsupported Scheme datum for JSON serialization" datum))))))
       (recur obj 0)
       #t))))

(define (json-accumulator port-or-acc)
  (let* ((is-port (output-port? port-or-acc))
         (write-fn (if is-port
                       (lambda (s) (display s port-or-acc))
                       port-or-acc))
         (stack-cell (cons (list (cons 'top #f)) '()))
         (depth-limit (json-nesting-depth-limit)))
    (lambda (obj)
      (if (eof-object? obj)
          (if (not (null? (car stack-cell)))
              (let ((frames (car stack-cell)))
                (if (and (= (length frames) 1) (eq? (caar frames) 'top))
                    #t
                    (raise (json-error "json-accumulator: unfinished structures at EOF" frames))))
              #t)
          (begin
            (if (and depth-limit (> (length (car stack-cell)) depth-limit))
                (raise (json-error "json-accumulator: nesting depth limit exceeded" (length (car stack-cell)))))
            (cond
              ;; --------------------------------------------------------
              ;; 'array-start
              ;; --------------------------------------------------------
              ((eq? obj 'array-start)
               (let* ((frames (car stack-cell))
                      (top-frame (if (null? frames) #f (car frames))))
                 (if top-frame
                     (let ((kind (car top-frame))
                           (has-elem (cdr top-frame)))
                       (cond
                         ((eq? kind 'array)
                          (if has-elem (write-fn ", "))
                          (set-cdr! top-frame #t))
                         ((eq? kind 'object-val)
                          (set-car! stack-cell (cons (cons 'object-key #t) (cdr frames)))))))
                 (write-fn "[")
                 (set-car! stack-cell (cons (cons 'array #f) (car stack-cell)))))
              ;; --------------------------------------------------------
              ;; 'array-end
              ;; --------------------------------------------------------
              ((eq? obj 'array-end)
               (let* ((frames (car stack-cell)))
                 (if (or (null? frames) (not (eq? (caar frames) 'array)))
                     (raise (json-error "json-accumulator: unexpected 'array-end"))
                     (begin
                       (write-fn "]")
                       (set-car! stack-cell (cdr frames))))))
              ;; --------------------------------------------------------
              ;; 'object-start
              ;; --------------------------------------------------------
              ((eq? obj 'object-start)
               (let* ((frames (car stack-cell))
                      (top-frame (if (null? frames) #f (car frames))))
                 (if top-frame
                     (let ((kind (car top-frame))
                           (has-elem (cdr top-frame)))
                       (cond
                         ((eq? kind 'array)
                          (if has-elem (write-fn ", "))
                          (set-cdr! top-frame #t))
                         ((eq? kind 'object-val)
                          (set-car! stack-cell (cons (cons 'object-key #t) (cdr frames)))))))
                 (write-fn "{")
                 (set-car! stack-cell (cons (cons 'object-key #f) (car stack-cell)))))
              ;; --------------------------------------------------------
              ;; 'object-end
              ;; --------------------------------------------------------
              ((eq? obj 'object-end)
               (let* ((frames (car stack-cell)))
                 (if (or (null? frames) (not (eq? (caar frames) 'object-key)))
                     (raise (json-error "json-accumulator: unexpected 'object-end"))
                     (begin
                       (write-fn "}")
                       (set-car! stack-cell (cdr frames))))))
              ;; --------------------------------------------------------
              ;; Scalar value or Key
              ;; --------------------------------------------------------
              (else
               (let* ((frames (car stack-cell)))
                 (if (null? frames)
                     (raise (json-error "json-accumulator: no container open for value" obj))
                     (let* ((top-frame (car frames))
                            (kind (car top-frame))
                            (has-elem (cdr top-frame)))
                       (cond
                         ((eq? kind 'array)
                          (if has-elem (write-fn ", "))
                          (set-cdr! top-frame #t)
                          (json-write obj write-fn))
                         ((eq? kind 'object-key)
                          (if (not (or (string? obj) (symbol? obj)))
                              (raise (json-error "json-accumulator: object key must be string or symbol" obj)))
                          (if has-elem (write-fn ", "))
                          (cond
                            ((string? obj) (%json-write-escaped-string obj write-fn))
                            ((symbol? obj) (%json-write-escaped-string (symbol->string obj) write-fn)))
                          (write-fn ": ")
                          ;; Expecting value next
                          (set-car! stack-cell (cons (cons 'object-val #t) (cdr frames))))
                         ((eq? kind 'object-val)
                          (json-write obj write-fn)
                          ;; Back to expecting key
                          (set-car! stack-cell (cons (cons 'object-key #t) (cdr frames))))
                         ((eq? kind 'top)
                          (json-write obj write-fn)
                          (set-car! stack-cell (cdr frames)))
                         (else
                          (raise (json-error "json-accumulator: invalid state" kind))))))))))))))

;; ---------------------------------------------------------------------
;; §9. High-Level Convenience String & Bytevector Converters
;; ---------------------------------------------------------------------

(define (string->json str)
  (call-with-port (open-input-string str) json-read))

(define (json->string obj)
  (let ((p (open-output-string)))
    (json-write obj p)
    (get-output-string p)))

(define (bytes->json bv)
  (string->json (utf8->string bv)))

(define (json->bytes obj)
  (string->utf8 (json->string obj)))
