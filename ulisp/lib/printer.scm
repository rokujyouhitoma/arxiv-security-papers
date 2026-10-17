;;; =======================================================================
;;; ULisp Standard Library: printer.scm
;;; Formatted Scheme output procedures implemented purely in Scheme
;;; Extended with R7RS Port Specification & Issue #534
;;; =======================================================================

(define (port-newline p)
  (port-write-char #\newline p))

(define (port-display-string s p)
  (port-write-string s p))

(define (port-display val p)
  (cond
    ((string? val)
     (port-display-string val p))
    ((char? val)
     (port-write-char val p))
    ((boolean? val)
     (if val (port-display-string "#t" p) (port-display-string "#f" p)))
    ((null? val)
     (port-display-string "()" p))
    ((number? val)
     (port-display-string (number->string val) p))
    ((symbol? val)
     (port-display-string (symbol->string val) p))
    ((pair? val)
     (port-write-char #\( p)
     (let loop ((curr val) (first? #t))
       (cond
         ((null? curr)
          (port-write-char #\) p))
         ((pair? curr)
          (if (not first?) (port-write-char #\space p))
          (port-display (car curr) p)
          (loop (cdr curr) #f))
         (else
          (port-write-char #\space p)
          (port-write-char #\. p)
          (port-write-char #\space p)
          (port-display curr p)
          (port-write-char #\) p)))))
    ((eof-object? val)
     (port-display-string "#<eof>" p))
    ((bytevector? val)
     (port-display-string "#u8(" p)
     (let ((len (bytevector-length val)))
       (let loop ((i 0))
         (if (< i len)
             (begin
               (if (> i 0) (port-write-char #\space p))
               (port-display-string (number->string (bytevector-u8-ref val i)) p)
               (loop (+ i 1)))
             #t)))
     (port-write-char #\) p))
    (else
     (port-display-string "#<unknown>" p))))

(define (port-write-char-literal c p)
  (port-display-string "#\\" p)
  (cond
    ((char=? c #\newline) (port-display-string "newline" p))
    ((char=? c #\space)   (port-display-string "space" p))
    ((char=? c #\tab)     (port-display-string "tab" p))
    (else                 (port-write-char c p))))

(define (port-write val p)
  (cond
    ((string? val)
     (port-write-char #\" p)
     (let ((len (string-length val)))
       (let loop ((i 0))
         (if (< i len)
             (let ((c (string-ref val i)))
               (cond
                 ((char=? c #\newline) (port-display-string "\\n" p))
                 ((char=? c #\tab)     (port-display-string "\\t" p))
                 ((char=? c (integer->char 13)) (port-display-string "\\r" p))
                 ((char=? c #\\)       (port-display-string "\\\\" p))
                 ((char=? c #\")       (port-display-string "\\\"" p))
                 (else                 (port-write-char c p)))
               (loop (+ i 1)))
             #t)))
     (port-write-char #\" p))
    ((char? val)
     (port-write-char-literal val p))
    (else
     (port-display val p))))

;;; -----------------------------------------------------------------------
;;; R7RS Standard Macros and Compatibility Wrappers
;;; -----------------------------------------------------------------------

(define-syntax newline
  (syntax-rules ()
    ((newline) (port-newline *stdout-port*))
    ((newline p) (port-newline p))))

(define-syntax display
  (syntax-rules ()
    ((display val) (port-display val *stdout-port*))
    ((display val p) (port-display val p))))

(define-syntax write
  (syntax-rules ()
    ((write val) (port-write val *stdout-port*))
    ((write val p) (port-write val p))))
