;;; =======================================================================
;;; ULisp Standard Library: printer.scm
;;; Formatted Scheme output procedures implemented purely in Scheme
;;; =======================================================================

(define (newline)
  (write-char #\newline))

(define (display-string s)
  (let ((len (string-length s)))
    (let loop ((i 0))
      (if (< i len)
          (begin
            (write-char (string-ref s i))
            (loop (+ i 1)))
          #t))))

(define (display val)
  (cond
    ((string? val)
     (display-string val))
    ((char? val)
     (write-char val))
    ((boolean? val)
     (if val (display-string "#t") (display-string "#f")))
    ((null? val)
     (display-string "()"))
    ((number? val)
     (display-string (number->string val)))
    ((symbol? val)
     (display-string (symbol->string val)))
    ((pair? val)
     (write-char #\()
     (let loop ((curr val) (first? #t))
       (cond
         ((null? curr)
          (write-char #\)))
         ((pair? curr)
          (if (not first?) (write-char #\space))
          (display (car curr))
          (loop (cdr curr) #f))
         (else
          (write-char #\space)
          (write-char #\.)
          (write-char #\space)
          (display curr)
          (write-char #\))))))
    ((eof-object? val)
     (display-string "#<eof>"))
    (else
     (display-string "#<unknown>"))))

(define (write-char-literal c)
  (display-string "#\\")
  (cond
    ((char=? c #\newline) (display-string "newline"))
    ((char=? c #\space)   (display-string "space"))
    ((char=? c #\tab)     (display-string "tab"))
    (else                 (write-char c))))

(define (write val)
  (cond
    ((string? val)
     (write-char #\")
     (let ((len (string-length val)))
       (let loop ((i 0))
         (if (< i len)
             (let ((c (string-ref val i)))
               (cond
                 ((char=? c #\newline) (display-string "\\n"))
                 ((char=? c #\tab)     (display-string "\\t"))
                 ((char=? c (integer->char 13)) (display-string "\\r"))
                 ((char=? c #\\)       (display-string "\\\\"))
                 ((char=? c #\")       (display-string "\\\""))
                 (else                 (write-char c)))
               (loop (+ i 1)))
             #t)))
     (write-char #\"))
    ((char? val)
     (write-char-literal val))
    (else
     (display val))))
