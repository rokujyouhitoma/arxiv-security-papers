;;; =======================================================================
;;; ULisp Standard Library: SRFI 28 Basic Format Strings (lib/format.scm)
;;; Conforms to DSN-33 Architecture Specification & Issue #654
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

;; §SRFI-28 Basic Format Strings: %format and format
(define (%format fmt objects)
  (if (not (string? fmt))
      (error "format: format-string must be a string" fmt)
      (let ((p (open-output-string))
            (len (string-length fmt)))
        (let loop ((i 0) (args objects))
          (if (>= i len)
              (if (null? args)
                  (get-output-string p)
                  (error "format: too many arguments" args))
              (let ((c (string-ref fmt i)))
                (if (char=? c #\~)
                    (if (>= (+ i 1) len)
                        (error "format: illegal trailing escape character ~")
                        (let ((directive (string-ref fmt (+ i 1))))
                          (cond
                            ((or (char=? directive #\a) (char=? directive #\A))
                             (if (null? args)
                                 (error "format: too few arguments" directive)
                                 (begin
                                   (display (car args) p)
                                   (loop (+ i 2) (cdr args)))))
                            ((or (char=? directive #\s) (char=? directive #\S))
                             (if (null? args)
                                 (error "format: too few arguments" directive)
                                 (begin
                                   (write (car args) p)
                                   (loop (+ i 2) (cdr args)))))
                            ((char=? directive #\%)
                             (newline p)
                             (loop (+ i 2) args))
                            ((char=? directive #\~)
                             (write-char #\~ p)
                             (loop (+ i 2) args))
                            (else
                             (error "format: illegal directive" directive)))))
                    (begin
                      (write-char c p)
                      (loop (+ i 1) args)))))))))

(define format
  (case-lambda
    ((fmt)
     (%format fmt '()))
    ((fmt a1)
     (%format fmt (list a1)))
    ((fmt a1 a2)
     (%format fmt (list a1 a2)))
    ((fmt a1 a2 a3)
     (%format fmt (list a1 a2 a3)))
    ((fmt a1 a2 a3 a4)
     (%format fmt (list a1 a2 a3 a4)))
    ((fmt a1 a2 a3 a4 . rest)
     (%format fmt (cons a1 (cons a2 (cons a3 (cons a4 rest))))))))

