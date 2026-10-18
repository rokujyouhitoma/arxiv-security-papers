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
             ((eof-object? c2) c2)
             ((ulisp-char=? c2 #\))
              (port-read-char p) ; consume ')'
              '())
             ((ulisp-char=? c2 #\.)
              (port-read-char p) ; consume '.'
              (let ((cdr-val (port-read p)))
                (ulisp-skip-ws-port p)
                (port-read-char p) ; consume ')'
                cdr-val))
             (else
              (let ((elem (port-read p)))
                (cons elem (read-list))))))))

      ;; Quote: 'datum => (quote datum)
      ((ulisp-char=? c #\')
       (port-read-char p) ; consume '\''
       (list 'quote (port-read p)))

      ;; String: "..."
      ((ulisp-char=? c #\")
       (port-read-char p) ; consume '"'
       (let read-str ((acc '()))
         (let ((ch (port-read-char p)))
           (cond
             ((or (eof-object? ch) (ulisp-char=? ch #\"))
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
           ((ulisp-char=? c2 #\t) #t)
           ((ulisp-char=? c2 #\f) #f)
           ((ulisp-char=? c2 #\() ; Vector literal #( ... )
            (let read-vec-list ()
              (let ((c3 (ulisp-skip-ws-port p)))
                (cond
                  ((eof-object? c3) c3)
                  ((ulisp-char=? c3 #\))
                   (port-read-char p) ; consume ')'
                   '(vector))
                  (else
                   (cons 'vector
                         (let read-elems ()
                           (let ((elem (port-read p)))
                             (let ((c4 (ulisp-skip-ws-port p)))
                               (if (or (eof-object? c4) (ulisp-char=? c4 #\)))
                                   (begin
                                     (if (not (eof-object? c4)) (port-read-char p))
                                     (list elem))
                                   (cons elem (read-elems))))))))))))
           ((and (ulisp-char=? c2 #\u) (ulisp-char=? (port-peek-char p) #\8))
            (port-read-char p) ; consume '8'
            (let ((c3 (ulisp-skip-ws-port p)))
              (if (ulisp-char=? c3 #\()
                  (begin
                    (port-read-char p) ; consume '('
                    (let read-bv-list ()
                      (let ((c4 (ulisp-skip-ws-port p)))
                        (cond
                          ((eof-object? c4) c4)
                          ((ulisp-char=? c4 #\))
                           (port-read-char p)
                           '(bytevector))
                          (else
                           (cons 'bytevector
                                 (let read-bv-elems ()
                                   (let ((elem (port-read p)))
                                     (let ((c5 (ulisp-skip-ws-port p)))
                                       (if (or (eof-object? c5) (ulisp-char=? c5 #\)))
                                           (begin
                                             (if (not (eof-object? c5)) (port-read-char p))
                                             (list elem))
                                           (cons elem (read-bv-elems))))))))))))
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
                                  (and (> len 1) (ulisp-is-digit? (cadr chars))))))
                    (let* ((neg? (ulisp-char=? (car chars) #\-))
                           (digit-chars (if (or (ulisp-char=? (car chars) #\-) (ulisp-char=? (car chars) #\+))
                                            (cdr chars)
                                            chars)))
                      (let parse-digits ((ds digit-chars) (num 0))
                        (if (null? ds)
                            (if neg? (- 0 num) num)
                            (parse-digits (cdr ds) (+ (* num 10) (- (char->integer (car ds)) 48)))))))
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

(define-syntax read
  (syntax-rules ()
    ((read) (port-read *stdin-port*))
    ((read p) (port-read p))))
