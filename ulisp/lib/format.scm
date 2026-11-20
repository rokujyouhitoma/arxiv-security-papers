;;; =======================================================================
;;; ULisp Standard Library: SRFI 48 Intermediate Format Strings (lib/format.scm)
;;; Conforms to DSN-33 Architecture Specification, SRFI 48 & R7RS Orange Docket
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

;; §SRFI-48 Intermediate Format Strings: Documentation
(define %format-documentation-string
"(format [<port>] <format-string> [<arg>...]) -- <port> is #t, #f or an output-port
OPTION  [MNEMONIC]      DESCRIPTION     -- Implementation Assumes ASCII Text Encoding
~H      [Help]          output this text
~A      [Any]           (display arg) for humans
~S      [Slashified]    (write arg) for parsers
~W      [WriteCircular] like ~s but outputs circular and recursive data structures
~~      [tilde]         output a tilde
~T      [Tab]           output a tab character
~%      [Newline]       output a newline character
~&      [Freshline]     output a newline character if the previous output was not a newline
~D      [Decimal]       the arg is a number which is output in decimal radix
~X      [heXadecimal]   the arg is a number which is output in hexdecimal radix
~O      [Octal]         the arg is a number which is output in octal radix
~B      [Binary]        the arg is a number which is output in binary radix
~w,dF   [Fixed]         the arg is a string or number which has width w and d digits after the decimal
~C      [Character]     character arg is output by write-char
~_      [Space]         a single space character is output
~Y      [Yuppify]       the list arg is pretty-printed to the output
~?      [Indirection]   recursive format: next 2 args are format-string and list of arguments
~K      [Indirection]   same as ~?
")

(define (%format-string-index str c)
  (let ((len (string-length str)))
    (let loop ((i 0))
      (cond
        ((= i len) #f)
        ((char=? c (string-ref str i)) i)
        (else (loop (+ i 1)))))))

(define (%format-string-grow str len char)
  (let ((off (- len (string-length str))))
    (if (> off 0)
        (string-append (make-string off char) str)
        str)))

(define (%format-compose-with-digits digits pre-str frac-str exp-str)
  (let ((frac-len (string-length frac-str)))
    (cond
      ((= digits 0)
       (let* ((minus-flag (and (> (string-length pre-str) 0)
                               (char=? (string-ref pre-str 0) #\-)))
              (pre-str* (if minus-flag
                            (substring pre-str 1 (string-length pre-str))
                            pre-str))
              (combined-num (string->number (string-append pre-str* "." frac-str)))
              (rounded (exact (round combined-num)))
              (rounded-str (number->string rounded)))
         (string-append (if minus-flag "-" "") rounded-str exp-str)))
      ((< frac-len digits)
       (string-append pre-str "." frac-str (make-string (- digits frac-len) #\0) exp-str))
      ((= frac-len digits)
       (string-append pre-str "." frac-str exp-str))
      (else
       (let* ((minus-flag (and (> (string-length pre-str) 0)
                               (char=? (string-ref pre-str 0) #\-)))
              (pre-str* (if minus-flag
                            (substring pre-str 1 (string-length pre-str))
                            pre-str))
              (first-part (substring frac-str 0 digits))
              (last-part (substring frac-str digits frac-len))
              (combined-num (string->number (string-append pre-str* first-part "." last-part)))
              (temp-str (%format-string-grow
                         (number->string (exact (round combined-num)))
                         digits
                         #\0))
              (temp-len (string-length temp-str))
              (new-pre (substring temp-str 0 (- temp-len digits)))
              (new-frac (substring temp-str (- temp-len digits) temp-len)))
         (string-append
          (if minus-flag "-" "")
          (if (string=? new-pre "")
              (if (and (string=? pre-str* "")
                       (> digits 0)
                       (not (= (string->number new-frac) 0)))
                  "" "0")
              new-pre)
          "."
          new-frac
          exp-str))))))

(define (%format-fixed-number-or-string num-or-str width digits)
  (cond
    ((string? num-or-str)
     (%format-string-grow num-or-str width #\space))
    ((number? num-or-str)
     (let ((im (imag-part num-or-str)))
       (cond
         ((not (zero? im))
          (let ((re (real-part num-or-str)))
            (%format-string-grow
             (string-append (%format-fixed-number-or-string re 0 digits)
                            (if (negative? im) "" "+")
                            (%format-fixed-number-or-string im 0 digits)
                            "i")
             width
             #\space)))
         (digits
          (let* ((real-val (real-part num-or-str))
                 (num-str (number->string (exact->inexact real-val)))
                 (dot-idx (%format-string-index num-str #\.))
                 (exp-idx (%format-string-index num-str #\e))
                 (len (string-length num-str))
                 (pre-str (if dot-idx
                              (substring num-str 0 dot-idx)
                              (if exp-idx
                                  (substring num-str 0 exp-idx)
                                  num-str)))
                 (exp-str (if exp-idx
                              (substring num-str exp-idx len)
                              ""))
                 (frac-str (if dot-idx
                               (if exp-idx
                                   (substring num-str (+ dot-idx 1) exp-idx)
                                   (substring num-str (+ dot-idx 1) len))
                               "")))
            (if (%format-string-index num-str #\n)
                (%format-string-grow num-str width #\space)
                (%format-string-grow
                 (%format-compose-with-digits digits pre-str frac-str exp-str)
                 width
                 #\space))))
         (else
          (%format-string-grow (number->string (real-part num-or-str)) width #\space)))))
    (else
     (error "format: ~F requires a number or a string" num-or-str))))

(define (%format-has-newline? obj last-newline?)
  (cond
    ((char? obj) (char=? obj #\newline))
    ((string? obj)
     (let ((len (string-length obj)))
       (if (= len 0)
           last-newline?
           (char=? (string-ref obj (- len 1)) #\newline))))
    (else #f)))

;; §SRFI-48 Intermediate Format Strings: Core Formatting Engine
(define (%format-loop p fmt args i last-newline?)
  (let ((len (string-length fmt)))
    (let loop ((i i) (args args) (last-newline? last-newline?))
      (if (>= i len)
          args
          (let ((c (string-ref fmt i)))
            (if (char=? c #\~)
                (if (>= (+ i 1) len)
                    (error "format: illegal trailing escape character ~")
                    (let ((directive (string-ref fmt (+ i 1))))
                      (cond
                        ((or (char=? directive #\a) (char=? directive #\A))
                         (if (null? args)
                             (error "format: too few arguments" directive)
                             (let ((val (car args)))
                               (display val p)
                               (loop (+ i 2) (cdr args) (%format-has-newline? val last-newline?)))))
                        ((or (char=? directive #\s) (char=? directive #\S))
                         (if (null? args)
                             (error "format: too few arguments" directive)
                             (let ((val (car args)))
                               (write val p)
                               (loop (+ i 2) (cdr args) (%format-has-newline? val last-newline?)))))
                        ((or (char=? directive #\w) (char=? directive #\W))
                         (if (null? args)
                             (error "format: too few arguments" directive)
                             (let ((val (car args)))
                               (write val p)
                               (loop (+ i 2) (cdr args) (%format-has-newline? val last-newline?)))))
                        ((or (char=? directive #\d) (char=? directive #\D))
                         (if (null? args)
                             (error "format: too few arguments" directive)
                             (let ((val (car args)))
                               (if (not (number? val))
                                   (error "format: ~d requires a number" val)
                                   (begin
                                     (display (number->string val 10) p)
                                     (loop (+ i 2) (cdr args) #f))))))
                        ((or (char=? directive #\x) (char=? directive #\X))
                         (if (null? args)
                             (error "format: too few arguments" directive)
                             (let ((val (car args)))
                               (if (not (number? val))
                                   (error "format: ~x requires a number" val)
                                   (begin
                                     (display (number->string val 16) p)
                                     (loop (+ i 2) (cdr args) #f))))))
                        ((or (char=? directive #\o) (char=? directive #\O))
                         (if (null? args)
                             (error "format: too few arguments" directive)
                             (let ((val (car args)))
                               (if (not (number? val))
                                   (error "format: ~o requires a number" val)
                                   (begin
                                     (display (number->string val 8) p)
                                     (loop (+ i 2) (cdr args) #f))))))
                        ((or (char=? directive #\b) (char=? directive #\B))
                         (if (null? args)
                             (error "format: too few arguments" directive)
                             (let ((val (car args)))
                               (if (not (number? val))
                                   (error "format: ~b requires a number" val)
                                   (begin
                                     (display (number->string val 2) p)
                                     (loop (+ i 2) (cdr args) #f))))))
                        ((or (char=? directive #\c) (char=? directive #\C))
                         (if (null? args)
                             (error "format: too few arguments" directive)
                             (let ((val (car args)))
                               (if (not (char? val))
                                   (error "format: ~c requires a character" val)
                                   (begin
                                     (write-char val p)
                                     (loop (+ i 2) (cdr args) (char=? val #\newline)))))))
                        ((or (char=? directive #\y) (char=? directive #\Y))
                         (if (null? args)
                             (error "format: too few arguments" directive)
                             (let ((val (car args)))
                               (write val p)
                               (loop (+ i 2) (cdr args) (%format-has-newline? val last-newline?)))))
                        ((or (char=? directive #\?) (char=? directive #\k) (char=? directive #\K))
                         (if (< (length args) 2)
                             (error "format: too few arguments for ~?")
                             (let ((sub-fmt (car args))
                                   (sub-args (cadr args)))
                               (if (not (string? sub-fmt))
                                   (error "format: ~? requires a format string" sub-fmt)
                                   (if (not (list? sub-args))
                                       (error "format: ~? requires an argument list" sub-args)
                                       (let ((unused-sub (%format-loop p sub-fmt sub-args 0 last-newline?)))
                                         (if (not (null? unused-sub))
                                             (error "format: ~? unused arguments" unused-sub)
                                             (loop (+ i 2) (cddr args) #f))))))))
                        ((or (char=? directive #\f) (char=? directive #\F))
                         (if (null? args)
                             (error "format: too few arguments for ~F")
                             (let ((res (%format-fixed-number-or-string (car args) 0 #f)))
                               (display res p)
                               (loop (+ i 2) (cdr args) (%format-has-newline? res last-newline?)))))
                        ((char=? directive #\~)
                         (write-char #\~ p)
                         (loop (+ i 2) args #f))
                        ((char=? directive #\%)
                         (newline p)
                         (loop (+ i 2) args #t))
                        ((char=? directive #\&)
                         (if (not last-newline?)
                             (newline p))
                         (loop (+ i 2) args #t))
                        ((or (char=? directive #\t) (char=? directive #\T))
                         (write-char (integer->char 9) p)
                         (loop (+ i 2) args #f))
                        ((char=? directive #\_)
                         (write-char #\space p)
                         (loop (+ i 2) args #f))
                        ((or (char=? directive #\h) (char=? directive #\H))
                         (display %format-documentation-string p)
                         (loop (+ i 2) args #t))
                        ((char-numeric? directive)
                         (let num-loop ((idx (+ i 2)) (w-chars (list directive)) (d-chars '()) (in-w? #t))
                           (if (>= idx len)
                               (error "format: premature end of format string in ~w,dF directive")
                               (let ((next-c (string-ref fmt idx)))
                                 (cond
                                   ((char-numeric? next-c)
                                    (if in-w?
                                        (num-loop (+ idx 1) (cons next-c w-chars) d-chars #t)
                                        (num-loop (+ idx 1) w-chars (cons next-c d-chars) #f)))
                                   ((or (char=? next-c #\F) (char=? next-c #\f))
                                    (let* ((w (string->number (list->string (reverse w-chars))))
                                           (d (if (null? d-chars)
                                                  #f
                                                  (string->number (list->string (reverse d-chars))))))
                                      (if (null? args)
                                          (error "format: too few arguments for ~F")
                                          (let ((res (%format-fixed-number-or-string (car args) w d)))
                                            (display res p)
                                            (loop (+ idx 1) (cdr args) (%format-has-newline? res last-newline?))))))
                                   ((char=? next-c #\,)
                                    (if in-w?
                                        (num-loop (+ idx 1) w-chars d-chars #f)
                                        (error "format: too many commas in ~w,dF directive")))
                                   (else
                                    (error "format: illegal character in ~w,dF directive" next-c)))))))
                        (else
                         (error "format: illegal directive" directive)))))
                (begin
                  (write-char c p)
                  (loop (+ i 1) args (char=? c #\newline)))))))))

;; §SRFI-48 Intermediate Format Strings: Dispatch & Entry Point
(define (%format first-arg rest-args)
  (let* ((is-str (string? first-arg))
         (output-port (if is-str #f first-arg))
         (format-string (if is-str
                            first-arg
                            (if (null? rest-args)
                                (error "format: required format-string argument is missing")
                                (car rest-args))))
         (objects (if is-str
                      rest-args
                      (cdr rest-args))))
    (if (not (string? format-string))
        (error "format: format-string must be a string" format-string)
        (let* ((is-string-port (eq? output-port #f))
               (p (cond
                    ((eq? output-port #f) (open-output-string))
                    ((eq? output-port #t) (current-output-port))
                    ((output-port? output-port) output-port)
                    (else (error "format: bad output-port argument" output-port)))))
          (let ((unused (%format-loop p format-string objects 0 #f)))
            (if (not (null? unused))
                (error "format: too many arguments" unused)
                (if is-string-port
                    (get-output-string p)
                    (if #f #f))))))))

(define format
  (case-lambda
    (()
     (error "format: required format-string argument is missing"))
    ((a0)
     (%format a0 '()))
    ((a0 a1)
     (%format a0 (list a1)))
    ((a0 a1 a2)
     (%format a0 (list a1 a2)))
    ((a0 a1 a2 a3)
     (%format a0 (list a1 a2 a3)))
    ((a0 a1 a2 a3 a4)
     (%format a0 (list a1 a2 a3 a4)))
    ((a0 a1 a2 a3 a4 a5)
     (%format a0 (list a1 a2 a3 a4 a5)))
    ((a0 a1 a2 a3 a4 a5 a6)
     (%format a0 (list a1 a2 a3 a4 a5 a6)))
    ((a0 a1 a2 a3 a4 a5 a6 a7)
     (%format a0 (list a1 a2 a3 a4 a5 a6 a7)))
    ((a0 a1 a2 a3 a4 a5 a6 a7 . rest)
     (%format a0 (cons a1 (cons a2 (cons a3 (cons a4 (cons a5 (cons a6 (cons a7 rest)))))))))))
