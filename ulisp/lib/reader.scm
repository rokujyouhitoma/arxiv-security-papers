;;; =======================================================================
;;; ULisp Standard Library: reader.scm
;;; Hand-written recursive descent S-expression reader in pure Scheme
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

(define (ulisp-skip-ws)
  (let ((c (peek-char)))
    (cond
      ((eof-object? c) c)
      ((ulisp-is-whitespace? c)
       (read-char)
       (ulisp-skip-ws))
      ((ulisp-char=? c #\;)
       (let skip-comment ()
         (let ((ch (read-char)))
           (cond
             ((eof-object? ch) ch)
             ((ulisp-char=? ch #\newline) (ulisp-skip-ws))
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

(define (read)
  (let ((c (ulisp-skip-ws)))
    (cond
      ((eof-object? c) c)

      ;; List or Empty list: ( ... )
      ((ulisp-char=? c #\()
       (read-char) ; consume '('
       (let read-list ()
         (let ((c2 (ulisp-skip-ws)))
           (cond
             ((eof-object? c2) c2)
             ((ulisp-char=? c2 #\))
              (read-char) ; consume ')'
              '())
             ((ulisp-char=? c2 #\.)
              (read-char) ; consume '.'
              (let ((cdr-val (read)))
                (ulisp-skip-ws)
                (read-char) ; consume ')'
                cdr-val))
             (else
              (let ((elem (read)))
                (cons elem (read-list))))))))

      ;; Quote: 'datum => (quote datum)
      ((ulisp-char=? c #\')
       (read-char) ; consume '\''
       (list 'quote (read)))

      ;; String: "..."
      ((ulisp-char=? c #\")
       (read-char) ; consume '"'
       (let read-str ((acc '()))
         (let ((ch (read-char)))
           (cond
             ((or (eof-object? ch) (ulisp-char=? ch #\"))
              (ulisp-chars->string (reverse acc)))
             ((ulisp-char=? ch #\\)
              (let ((escaped (read-char)))
                (cond
                  ((ulisp-char=? escaped #\n) (read-str (cons #\newline acc)))
                  ((ulisp-char=? escaped #\t) (read-str (cons #\tab acc)))
                  ((ulisp-char=? escaped #\r) (read-str (cons (integer->char 13) acc)))
                  (else (read-str (cons escaped acc))))))
             (else
              (read-str (cons ch acc)))))))

      ;; Boolean or Character Literal: #t, #f, #\newline, #\space, #\c
      ((ulisp-char=? c #\#)
       (read-char) ; consume '#'
       (let ((c2 (read-char)))
         (cond
           ((ulisp-char=? c2 #\t) #t)
           ((ulisp-char=? c2 #\f) #f)
           ((ulisp-char=? c2 #\\)
            (let ((c3 (read-char)))
              (let read-char-name ((acc (list c3)))
                (let ((next (peek-char)))
                  (if (or (ulisp-is-delimiter? next) (eof-object? next))
                      (let ((name (ulisp-chars->string (reverse acc))))
                        (cond
                          ((eq? (string-length name) 1) c3)
                          ((string=? name "newline") #\newline)
                          ((string=? name "space")   #\space)
                          ((string=? name "tab")     #\tab)
                          (else c3)))
                      (begin
                        (read-char)
                        (read-char-name (cons next acc))))))))
           (else #f))))

      ;; Numbers and Symbols / Identifiers
      (else
       (let read-token ((acc '()))
         (let ((next (peek-char)))
           (if (or (ulisp-is-delimiter? next) (eof-object? next))
               (let* ((chars (reverse acc))
                      (len (length chars)))
                 (cond
                   ((= len 0) #f)
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
                 (read-char)
                 (read-token (cons next acc))))))))))
