;;; =======================================================================
;;; ULisp Standard Library: reader.scm
;;; Hand-written recursive descent S-expression reader in pure Scheme
;;; Extended with R7RS Port Specification & Issue #534
;;; =======================================================================

(define (ulisp-char=? c expected)
  (and (not (eof-object? c))
       (char=? c expected)))

(define (ulisp-is-whitespace? c)
  (or (ulisp-char=? c #\space)
      (or (ulisp-char=? c #\newline)
          (or (ulisp-char=? c #\tab)
              (ulisp-char=? c (integer->char 13))))))

(define (ulisp-is-delimiter? c)
  (or (eof-object? c)
      (or (ulisp-is-whitespace? c)
          (or (ulisp-char=? c #\()
              (or (ulisp-char=? c #\))
                  (or (ulisp-char=? c #\;)
                      (ulisp-char=? c #\")))))))

(define (ulisp-is-digit? c)
  (and (not (eof-object? c))
       (let ((code (char->integer c)))
         (and (>= code 48) (<= code 57)))))

;;; -----------------------------------------------------------------------
;;; R7RS §6.2.6 string->number and Radix Support (CWE-190 Overflow Hardened)
;;; -----------------------------------------------------------------------

(define *ulisp-fixnum-max* 288230376151711743)
(define *ulisp-fixnum-min-abs* (+ *ulisp-fixnum-max* 1))

(define (ulisp-digit-value c radix)
  (if (eof-object? c)
      #f
      (let ((code (char->integer c)))
        (cond
          ;; '0' - '9'
          ((and (>= code 48) (<= code 57))
           (let ((val (- code 48)))
             (if (< val radix) val #f)))
          ;; 'a' - 'f'
          ((and (>= code 97) (<= code 102))
           (if (= radix 16)
               (+ (- code 97) 10)
               #f))
          ;; 'A' - 'F'
          ((and (>= code 65) (<= code 70))
           (if (= radix 16)
               (+ (- code 65) 10)
               #f))
          (else #f)))))

(define (string->number-core str radix explicit-radix?)
  (if (not (string? str))
      #f
      (let ((len (string-length str)))
        (if (= len 0)
            #f
            (let parse-prefix ((i 0)
                               (radix-found #f)
                               (exactness-found #f)
                               (neg? #f)
                               (sign-found? #f))
              (cond
                ;; Check prefix: '#' followed by prefix char
                ((and (< (+ i 1) len)
                      (char=? (string-ref str i) #\#))
                 (let ((c (string-ref str (+ i 1))))
                   (cond
                     ;; #b / #B
                     ((or (char=? c #\b) (char=? c #\B))
                      (if radix-found
                          #f ; duplicate radix
                          (parse-prefix (+ i 2) 2 exactness-found neg? sign-found?)))
                     ;; #o / #O
                     ((or (char=? c #\o) (char=? c #\O))
                      (if radix-found
                          #f
                          (parse-prefix (+ i 2) 8 exactness-found neg? sign-found?)))
                     ;; #d / #D
                     ((or (char=? c #\d) (char=? c #\D))
                      (if radix-found
                          #f
                          (parse-prefix (+ i 2) 10 exactness-found neg? sign-found?)))
                     ;; #x / #X
                     ((or (char=? c #\x) (char=? c #\X))
                      (if radix-found
                          #f
                          (parse-prefix (+ i 2) 16 exactness-found neg? sign-found?)))
                     ;; #e / #E (exact)
                     ((or (char=? c #\e) (char=? c #\E))
                      (if exactness-found
                          #f
                          (parse-prefix (+ i 2) radix-found 'exact neg? sign-found?)))
                     ;; #i / #I (inexact: unsupported in integer-only ulisp)
                     ((or (char=? c #\i) (char=? c #\I))
                      #f)
                     (else #f))))
                ;; Check sign '+' or '-'
                ((and (< i len)
                      (not sign-found?)
                      (or (char=? (string-ref str i) #\+)
                          (char=? (string-ref str i) #\-)))
                 (let ((is-minus (char=? (string-ref str i) #\-)))
                   (parse-prefix (+ i 1) radix-found exactness-found is-minus #t)))
                ;; Finished prefixes and signs: validate and parse digits
                (else
                 (let* ((effective-radix
                         (cond
                           ((and radix-found explicit-radix?)
                            (if (= radix-found radix) radix #f))
                           (radix-found radix-found)
                           (else radix))))
                   (if (or (not effective-radix)
                           (not (or (= effective-radix 2)
                                    (or (= effective-radix 8)
                                        (or (= effective-radix 10)
                                            (= effective-radix 16))))))
                       #f
                       (if (>= i len)
                           #f ; no digits present
                           (let ((limit (if neg? *ulisp-fixnum-min-abs* *ulisp-fixnum-max*)))
                             (let parse-digits ((pos i)
                                                (acc 0)
                                                (count 0))
                               (if (>= pos len)
                                   (if (= count 0)
                                       #f
                                       (if neg? (- 0 acc) acc))
                                   (let ((d (ulisp-digit-value (string-ref str pos) effective-radix)))
                                     (if (not d)
                                         #f ; invalid digit
                                         (let ((q (quotient limit effective-radix))
                                               (r (modulo limit effective-radix)))
                                           (if (or (> acc q) (and (= acc q) (> d r)))
                                               #f ; overflow
                                               (parse-digits (+ pos 1)
                                                             (+ (* acc effective-radix) d)
                                                             (+ count 1)))))))))))))))))))

(define (string->number-radix s r)
  (string->number-core s r #t))

(define-syntax string->number
  (syntax-rules ()
    ((string->number s) (string->number-core s 10 #f))
    ((string->number s r) (string->number-core s r #t))))

(define (ulisp-skip-ws-port p)
  (let ((c (port-peek-char p)))
    (cond
      ((eof-object? c) c)
      ((ulisp-is-whitespace? c)
       (port-read-char p)
       (ulisp-skip-ws-port p))
      ((ulisp-char=? c #\;)
       (let skip-comment ()
         (let ((ch (port-read-char p)))
           (cond
             ((eof-object? ch) ch)
             ((ulisp-char=? ch #\newline) (ulisp-skip-ws-port p))
             (else (skip-comment))))))
      (else c))))

(define (ulisp-chars->string chars)
  (let* ((len (length chars))
         (res (make-string len)))
    (let loop ((i 0) (cs chars))
      (if (null? cs)
          res
          (begin
            (string-set! res i (car cs))
            (loop (+ i 1) (cdr cs)))))))

;;; Read the rest of a symbol whose leading '.' has already been consumed
(define (ulisp-read-dot-symbol p)
  (let loop ((acc (list #\.)))
    (let ((next (port-peek-char p)))
      (if (ulisp-is-delimiter? next)
          (string->symbol (ulisp-chars->string (reverse acc)))
          (begin
            (port-read-char p)
            (loop (cons next acc)))))))

(define (port-read p)
  (let ((c (ulisp-skip-ws-port p)))
    (cond
      ((eof-object? c) c)

      ;; List or Empty list: ( ... )
      ((ulisp-char=? c #\()
       (port-read-char p) ; consume '('
       (let read-list ()
         (let ((c2 (ulisp-skip-ws-port p)))
           (cond
             ((eof-object? c2)
              (error "read: unexpected EOF while reading list" (port-filename p)))
             ((ulisp-char=? c2 #\))
              (port-read-char p) ; consume ')'
              '())
             ((ulisp-char=? c2 #\.)
              (port-read-char p) ; consume '.'
              (if (ulisp-is-delimiter? (port-peek-char p))
                  ;; Lone '.': dotted pair tail
                  (let ((cdr-val (port-read p)))
                    (if (eof-object? cdr-val)
                        (error "read: unexpected EOF while reading dotted pair tail" (port-filename p))
                        (let ((c3 (ulisp-skip-ws-port p)))
                          (if (eof-object? c3)
                              (error "read: unexpected EOF expecting ')' after dotted pair" (port-filename p))
                              (if (ulisp-char=? c3 #\))
                                  (begin
                                    (port-read-char p) ; consume ')'
                                    cdr-val)
                                  (error "read: expected ')' after dotted pair value" (port-filename p)))))))
                  ;; Token starting with '.' (e.g. the ellipsis '...')
                  (let ((elem (ulisp-read-dot-symbol p)))
                    (cons elem (read-list)))))
             (else
              (let ((elem (port-read p)))
                (cons elem (read-list))))))))

      ;; Quote: 'datum => (quote datum)
      ((ulisp-char=? c #\')
       (port-read-char p) ; consume '\''
       (let ((datum (port-read p)))
         (if (eof-object? datum)
             (error "read: unexpected EOF after quote" (port-filename p))
             (list 'quote datum))))

      ;; Quasiquote: `datum => (quasiquote datum)
      ((ulisp-char=? c #\`)
       (port-read-char p) ; consume '`'
       (let ((datum (port-read p)))
         (if (eof-object? datum)
             (error "read: unexpected EOF after quasiquote" (port-filename p))
             (list 'quasiquote datum))))

      ;; Unquote: ,datum => (unquote datum), ,@datum => (unquote-splicing datum)
      ((ulisp-char=? c #\,)
       (port-read-char p) ; consume ','
       (if (ulisp-char=? (port-peek-char p) #\@)
           (begin
             (port-read-char p) ; consume '@'
             (let ((datum (port-read p)))
               (if (eof-object? datum)
                   (error "read: unexpected EOF after unquote-splicing" (port-filename p))
                   (list 'unquote-splicing datum))))
           (let ((datum (port-read p)))
             (if (eof-object? datum)
                 (error "read: unexpected EOF after unquote" (port-filename p))
                 (list 'unquote datum)))))

      ;; String: "..."
      ((ulisp-char=? c #\")
       (port-read-char p) ; consume '"'
       (let read-str ((acc '()))
         (let ((ch (port-read-char p)))
           (cond
             ((eof-object? ch)
              (error "read: unexpected EOF while reading string literal" (port-filename p)))
             ((ulisp-char=? ch #\")
              (ulisp-chars->string (reverse acc)))
             ((ulisp-char=? ch #\\)
              (let ((escaped (port-read-char p)))
                (cond
                  ((ulisp-char=? escaped #\n) (read-str (cons #\newline acc)))
                  ((ulisp-char=? escaped #\t) (read-str (cons #\tab acc)))
                  ((ulisp-char=? escaped #\r) (read-str (cons (integer->char 13) acc)))
                  (else (read-str (cons escaped acc))))))
             (else
              (read-str (cons ch acc)))))))

      ;; Boolean, Character, Vector, or Bytevector Literal: #t, #f, #\c, #( ... ), #u8( ... )
      ((ulisp-char=? c #\#)
       (port-read-char p) ; consume '#'
       (let ((c2 (port-read-char p)))
         (cond
           ((ulisp-char=? c2 #\:)
            (let read-kw ((acc (list #\:)))
              (let ((next (port-peek-char p)))
                (if (or (ulisp-is-delimiter? next) (eof-object? next))
                    (string->symbol (ulisp-chars->string (reverse acc)))
                    (begin
                      (port-read-char p)
                      (read-kw (cons next acc)))))))
           ((ulisp-char=? c2 #\t) #t)
           ((ulisp-char=? c2 #\f) #f)
           ;; R7RS Radix & Exactness Prefixes for numbers: #b, #o, #d, #x, #e
           ((or (ulisp-char=? c2 #\b) (ulisp-char=? c2 #\B)
                (ulisp-char=? c2 #\o) (ulisp-char=? c2 #\O)
                (ulisp-char=? c2 #\d) (ulisp-char=? c2 #\D)
                (ulisp-char=? c2 #\x) (ulisp-char=? c2 #\X)
                (ulisp-char=? c2 #\e) (ulisp-char=? c2 #\E))
            (let read-num-token ((acc (list c2 #\#)))
              (let ((next (port-peek-char p)))
                (if (or (ulisp-is-delimiter? next) (eof-object? next))
                    (let* ((num-str (ulisp-chars->string (reverse acc)))
                           (n (string->number-core num-str 10 #f)))
                      (if n
                          n
                          (error "read: invalid number syntax" num-str)))
                    (begin
                      (port-read-char p)
                      (read-num-token (cons next acc)))))))
           ((ulisp-char=? c2 #\() ; Vector literal #( ... )
            (let read-vec-list ()
              (let ((c3 (ulisp-skip-ws-port p)))
                (cond
                  ((eof-object? c3)
                   (error "read: unexpected EOF while reading vector literal" (port-filename p)))
                  ((ulisp-char=? c3 #\))
                   (port-read-char p) ; consume ')'
                   '(vector))
                  (else
                   (cons 'vector
                         (let read-elems ()
                           (let ((elem (port-read p)))
                             (let ((c4 (ulisp-skip-ws-port p)))
                               (cond
                                 ((eof-object? c4)
                                  (error "read: unexpected EOF while reading vector literal" (port-filename p)))
                                 ((ulisp-char=? c4 #\))
                                  (port-read-char p)
                                  (list elem))
                                 (else
                                  (cons elem (read-elems)))))))))))))
           ((and (ulisp-char=? c2 #\u) (ulisp-char=? (port-peek-char p) #\8))
            (port-read-char p) ; consume '8'
            (let ((c3 (ulisp-skip-ws-port p)))
              (if (ulisp-char=? c3 #\()
                  (begin
                    (port-read-char p) ; consume '('
                    (let read-bv-list ()
                      (let ((c4 (ulisp-skip-ws-port p)))
                        (cond
                          ((eof-object? c4)
                           (error "read: unexpected EOF while reading bytevector literal" (port-filename p)))
                          ((ulisp-char=? c4 #\))
                           (port-read-char p)
                           '(bytevector))
                          (else
                           (cons 'bytevector
                                 (let read-bv-elems ()
                                   (let ((elem (port-read p)))
                                     (let ((c5 (ulisp-skip-ws-port p)))
                                       (cond
                                         ((eof-object? c5)
                                          (error "read: unexpected EOF while reading bytevector literal" (port-filename p)))
                                         ((ulisp-char=? c5 #\))
                                          (port-read-char p)
                                          (list elem))
                                         (else
                                          (cons elem (read-bv-elems)))))))))))))
                  #f)))
           ((ulisp-char=? c2 #\\)
            (let ((c3 (port-read-char p)))
              (let read-char-name ((acc (list c3)))
                (let ((next (port-peek-char p)))
                  (if (or (ulisp-is-delimiter? next) (eof-object? next))
                      (let ((name (ulisp-chars->string (reverse acc))))
                        (cond
                          ((eq? (string-length name) 1) c3)
                          ((string=? name "newline") #\newline)
                          ((string=? name "space")   #\space)
                          ((string=? name "tab")     #\tab)
                          (else c3)))
                      (begin
                        (port-read-char p)
                        (read-char-name (cons next acc))))))))
           (else #f))))

      ;; Numbers and Symbols / Identifiers
      (else
       (let read-token ((acc '()))
         (let ((next (port-peek-char p)))
           (if (or (ulisp-is-delimiter? next) (eof-object? next))
               (let* ((chars (reverse acc))
                      (len (length chars)))
                 (cond
                   ((= len 0)
                    ;; Safe advance if encountered isolated delimiter to prevent infinite loop
                    (if (not (eof-object? next))
                        (port-read-char p))
                    #f)
                   ;; Check if number
                   ((and (>= len 1)
                         (or (ulisp-is-digit? (car chars))
                             (and (or (ulisp-char=? (car chars) #\-) (ulisp-char=? (car chars) #\+))
                                  (> len 1))))
                    (let* ((num-str (ulisp-chars->string chars))
                           (n (string->number-core num-str 10 #f)))
                      (if n
                          n
                          (string->symbol num-str))))
                   ;; Otherwise, Symbol
                   (else
                    (string->symbol (ulisp-chars->string chars)))))
               (begin
                 (port-read-char p)
                 (read-token (cons next acc))))))))))

;;; -----------------------------------------------------------------------
;;; R7RS Standard Macros and Compatibility Wrappers
;;; -----------------------------------------------------------------------

(define (read-from-port p)
  (port-read p))

(define (port-read-with-source-info p)
  (let ((c (ulisp-skip-ws-port p)))
    (if (eof-object? c)
        c
        (let ((fn (port-filename p))
              (line (port-line p))
              (col (port-col p))
              (datum (port-read p)))
          (if (eof-object? datum)
              datum
              (list '%source-loc fn line col datum))))))

(define (read-with-source-info p)
  (port-read-with-source-info p))

(define-syntax read
  (syntax-rules ()
    ((read) (port-read (current-input-port)))
    ((read p) (port-read p))))
