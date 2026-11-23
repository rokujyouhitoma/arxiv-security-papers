;;; =======================================================================
;;; ULisp C99 Frontend: PEG-Synthesized C99 Lexer & <c-token> Stream
;;; Conforms to DSN-33-11 §3.1/§3.4/§3.5, DSN-33-32 & Issue #913 / #931
;;; Synthesizes raw C99 token recognition directly from tools/grammars/c99.peg
;;; via (c99-peg-parser 'c99_raw_token) with physical <source-span> (#824)
;;; and unified diagnostics (#833).
;;; =======================================================================

;;; -----------------------------------------------------------------------
;;; 1. <c-token> Record & Predicates / Cloners
;;; -----------------------------------------------------------------------

(define-record-type <c-token>
  (make-c-token kind lexeme value span at-bol? has-leading-space? hide-set)
  c-token?
  (kind               c-token-kind)
  (lexeme             c-token-lexeme)
  (value              c-token-value)
  (span               c-token-span)
  (at-bol?            c-token-at-bol?)
  (has-leading-space? c-token-has-leading-space?)
  (hide-set           c-token-hide-set))

(define (c-token-is-keyword? tok kw-sym)
  (and (c-token? tok)
       (eq? (c-token-kind tok) 'keyword)
       (eq? (c-token-value tok) kw-sym)))

(define (c-token-is-punct? tok punct-str)
  (and (c-token? tok)
       (eq? (c-token-kind tok) 'punct)
       (string=? (c-token-lexeme tok) punct-str)))

(define (c-token-clone-with-span tok new-span)
  (make-c-token (c-token-kind tok)
                (c-token-lexeme tok)
                (c-token-value tok)
                new-span
                (c-token-at-bol? tok)
                (c-token-has-leading-space? tok)
                (c-token-hide-set tok)))

(define (c-token-clone-with-hide-set tok new-hide-set)
  (make-c-token (c-token-kind tok)
                (c-token-lexeme tok)
                (c-token-value tok)
                (c-token-span tok)
                (c-token-at-bol? tok)
                (c-token-has-leading-space? tok)
                new-hide-set))

;;; -----------------------------------------------------------------------
;;; 2. PEG-Synthesized c99_raw_token Parser Cache & Diagnostics
;;; -----------------------------------------------------------------------

(define *c99-peg-raw-token-parser* (cons #f '()))

(define (c99-raw-token-parser)
  (or (car *c99-peg-raw-token-parser*)
      (let ((p (c99-peg-parser 'c99_raw_token)))
        (set-car! *c99-peg-raw-token-parser* p)
        p)))

(define (%c-lex-raise-error code fname s-line s-col e-line e-col msg)
  (let* ((sp (make-source-span fname s-line s-col e-line e-col #f (next-source-span-id!)))
         (diag (make-diagnostic 'error code sp msg)))
    (report-diagnostic diag)
    (raise (list 'c99-lex-error code msg sp))))

;;; -----------------------------------------------------------------------
;;; 3. Phase 1: CRLF Normalization, Line Splicing (\\\n) & Coordinate Map
;;; -----------------------------------------------------------------------

(define (%c-normalize-and-map-coords src-text)
  (let* ((n (string-length src-text))
         (cr (integer->char 13)))
    (let loop ((i 0) (line 1) (col 1) (chars '()) (lines '()) (cols '()))
      (if (>= i n)
          (list (list->string (reverse chars))
                (list->vector (reverse (cons line lines)))
                (list->vector (reverse (cons col cols))))
          (let ((ch (string-ref src-text i)))
            (cond
              ;; Backslash + LF line continuation
              ((and (char=? ch #\\)
                    (< (+ i 1) n)
                    (char=? (string-ref src-text (+ i 1)) #\newline))
               (loop (+ i 2) (+ line 1) 1 chars lines cols))
              ;; Backslash + CRLF line continuation
              ((and (char=? ch #\\)
                    (< (+ i 2) n)
                    (char=? (string-ref src-text (+ i 1)) cr)
                    (char=? (string-ref src-text (+ i 2)) #\newline))
               (loop (+ i 3) (+ line 1) 1 chars lines cols))
              ;; Standalone CRLF -> LF
              ((and (char=? ch cr)
                    (< (+ i 1) n)
                    (char=? (string-ref src-text (+ i 1)) #\newline))
               (loop (+ i 2) (+ line 1) 1
                     (cons #\newline chars)
                     (cons line lines)
                     (cons col cols)))
              ;; Newline LF
              ((char=? ch #\newline)
               (loop (+ i 1) (+ line 1) 1
                     (cons #\newline chars)
                     (cons line lines)
                     (cons col cols)))
              ;; Normal character
              (else
               (loop (+ i 1) line (+ col 1)
                     (cons ch chars)
                     (cons line lines)
                     (cons col cols)))))))))

;;; -----------------------------------------------------------------------
;;; 4. Phase 2: Whitespace & Comment Scanner (at-bol? / has-leading-space?)
;;; -----------------------------------------------------------------------

(define (%c-horiz-ws? ch)
  (let ((code (char->integer ch)))
    (or (= code 32)   ; space
        (= code 9)    ; tab
        (= code 11)   ; vertical tab
        (= code 12)   ; form feed
        (= code 13))))

(define (%c-skip-trivia norm-text norm-len pos line-vec col-vec fname init-at-bol?)
  (let loop ((p pos) (at-bol? init-at-bol?) (has-ws? #f))
    (if (>= p norm-len)
        (list p at-bol? has-ws?)
        (let ((ch (string-ref norm-text p)))
          (cond
            ((%c-horiz-ws? ch)
             (loop (+ p 1) at-bol? #t))
            ((char=? ch #\newline)
             (loop (+ p 1) #t #t))
            ;; Single-line comment // ...
            ((and (char=? ch #\/)
                  (< (+ p 1) norm-len)
                  (char=? (string-ref norm-text (+ p 1)) #\/))
             (let scan-lc ((q (+ p 2)))
               (if (or (>= q norm-len)
                       (char=? (string-ref norm-text q) #\newline))
                   (loop q at-bol? #t)
                   (scan-lc (+ q 1)))))
            ;; Block comment /* ... */
            ((and (char=? ch #\/)
                  (< (+ p 1) norm-len)
                  (char=? (string-ref norm-text (+ p 1)) #\*))
             (let scan-bc ((q (+ p 2)))
               (cond
                 ((>= (+ q 1) norm-len)
                  (%c-lex-raise-error
                   "C99-LEX-001" fname
                   (vector-ref line-vec p) (vector-ref col-vec p)
                   (vector-ref line-vec (+ p 2)) (vector-ref col-vec (+ p 2))
                   "Unterminated block comment /* ... */"))
                 ((and (char=? (string-ref norm-text q) #\*)
                       (char=? (string-ref norm-text (+ q 1)) #\/))
                  (loop (+ q 2) at-bol? #t))
                 (else
                  (scan-bc (+ q 1))))))
            (else
             (list p at-bol? has-ws?)))))))

;;; -----------------------------------------------------------------------
;;; 5. Phase 3: Literal Decoding Helpers (Int, Float, Char, String Escapes)
;;; -----------------------------------------------------------------------

(define (%c-digit-val ch)
  (let ((c (char->integer ch)))
    (cond
      ((and (>= c 48) (<= c 57)) (- c 48))
      ((and (>= c 97) (<= c 102)) (+ 10 (- c 97)))
      ((and (>= c 65) (<= c 70)) (+ 10 (- c 65)))
      (else -1))))

(define (%c-parse-radix-int str start end radix)
  (let loop ((i start) (acc 0))
    (if (>= i end)
        acc
        (let ((d (%c-digit-val (string-ref str i))))
          (loop (+ i 1) (+ (* acc radix) d))))))

(define (%c-strip-int-suffix lexeme)
  (let loop ((end (string-length lexeme)))
    (if (<= end 0)
        0
        (let ((ch (string-ref lexeme (- end 1))))
          (if (or (char=? ch #\u) (char=? ch #\U)
                  (char=? ch #\l) (char=? ch #\L))
              (loop (- end 1))
              end)))))

(define (%c-decode-int-literal lexeme)
  (let ((end (%c-strip-int-suffix lexeme)))
    (cond
      ((and (>= end 2)
            (char=? (string-ref lexeme 0) #\0)
            (or (char=? (string-ref lexeme 1) #\x)
                (char=? (string-ref lexeme 1) #\X)))
       (%c-parse-radix-int lexeme 2 end 16))
      ((and (> end 1) (char=? (string-ref lexeme 0) #\0))
       (%c-parse-radix-int lexeme 1 end 8))
      (else
       (%c-parse-radix-int lexeme 0 end 10)))))

(define (%c-strip-float-suffix lexeme)
  (let ((len (string-length lexeme)))
    (if (<= len 0)
        0
        (let ((ch (string-ref lexeme (- len 1))))
          (if (or (char=? ch #\f) (char=? ch #\F)
                  (char=? ch #\l) (char=? ch #\L))
              (- len 1)
              len)))))

(define (%c-find-char-in-range str ch-a ch-b start end)
  (let loop ((i start))
    (cond
      ((>= i end) #f)
      ((or (char=? (string-ref str i) ch-a)
           (char=? (string-ref str i) ch-b))
       i)
      (else (loop (+ i 1))))))

(define (%c-parse-signed-int str start end)
  (let* ((neg? (and (< start end) (char=? (string-ref str start) #\-)))
         (pos-start (if (and (< start end)
                             (or (char=? (string-ref str start) #\+)
                                 (char=? (string-ref str start) #\-)))
                        (+ start 1)
                        start))
         (mag (%c-parse-radix-int str pos-start end 10)))
    (if neg? (- mag) mag)))

(define (%c-decode-mantissa str start end base)
  (let ((dot-idx (%c-find-char-in-range str #\. #\. start end)))
    (if (not dot-idx)
        (exact->inexact (%c-parse-radix-int str start end base))
        (let* ((int-val (%c-parse-radix-int str start dot-idx base))
               (frac-len (- end (+ dot-idx 1)))
               (frac-int (if (> frac-len 0)
                             (%c-parse-radix-int str (+ dot-idx 1) end base)
                             0))
               (scale (exact->inexact (expt base frac-len))))
          (+ (exact->inexact int-val)
             (/ (exact->inexact frac-int) scale))))))

(define (%c-scale-power val base exp-val)
  (cond
    ((= val 0.0) 0.0)
    ((= exp-val 0) val)
    ((= base 10)
     (cond
       ((> exp-val 308) (* 1e308 2.0))
       ((< exp-val -350) 0.0)
       ((> exp-val 0) (* val (exact->inexact (expt 10 exp-val))))
       ((< exp-val -300)
        (let ((half (exact->inexact (expt 10 150)))
              (rem  (exact->inexact (expt 10 (- (- exp-val) 150)))))
          (/ (/ val half) rem)))
       (else (/ val (exact->inexact (expt 10 (- exp-val)))))))
    (else
     (cond
       ((> exp-val 1024) (* 1e308 2.0))
       ((< exp-val -1100) 0.0)
       ((> exp-val 0) (* val (exact->inexact (expt base exp-val))))
       ((< exp-val -1000)
        (let ((half (exact->inexact (expt base 512)))
              (rem  (exact->inexact (expt base (- (- exp-val) 512)))))
          (/ (/ val half) rem)))
       (else (/ val (exact->inexact (expt base (- exp-val)))))))))

(define (%c-decode-float-literal lexeme)
  (let ((end (%c-strip-float-suffix lexeme)))
    (if (and (>= end 2)
             (char=? (string-ref lexeme 0) #\0)
             (or (char=? (string-ref lexeme 1) #\x)
                 (char=? (string-ref lexeme 1) #\X)))
        (let* ((p-idx (%c-find-char-in-range lexeme #\p #\P 2 end))
               (mant-end (if p-idx p-idx end))
               (mant (%c-decode-mantissa lexeme 2 mant-end 16))
               (exp-val (if p-idx (%c-parse-signed-int lexeme (+ p-idx 1) end) 0)))
          (%c-scale-power mant 2 exp-val))
        (let* ((e-idx (%c-find-char-in-range lexeme #\e #\E 0 end))
               (mant-end (if e-idx e-idx end))
               (mant (%c-decode-mantissa lexeme 0 mant-end 10))
               (exp-val (if e-idx (%c-parse-signed-int lexeme (+ e-idx 1) end) 0)))
          (%c-scale-power mant 10 exp-val)))))

(define (%c-octal-digit? ch)
  (let ((c (char->integer ch)))
    (and (>= c 48) (<= c 55))))

(define (%c-hex-digit? ch)
  (let ((d (%c-digit-val ch)))
    (>= d 0)))

(define (%c-decode-escape str idx end fname sl sc el sc2)
  ;; idx points to character right after '\\'
  (if (>= idx end)
      (%c-lex-raise-error "C99-LEX-002" fname sl sc el sc2 "Trailing backslash in literal")
      (let ((c (string-ref str idx)))
        (case c
          ((#\n) (cons #\newline (+ idx 1)))
          ((#\t) (cons #\tab (+ idx 1)))
          ((#\r) (cons (integer->char 13) (+ idx 1)))
          ((#\a) (cons (integer->char 7) (+ idx 1)))
          ((#\b) (cons (integer->char 8) (+ idx 1)))
          ((#\f) (cons (integer->char 12) (+ idx 1)))
          ((#\v) (cons (integer->char 11) (+ idx 1)))
          ((#\\) (cons #\\ (+ idx 1)))
          ((#\') (cons #\' (+ idx 1)))
          ((#\") (cons #\" (+ idx 1)))
          ((#\?) (cons #\? (+ idx 1)))
          ((#\x)
           (if (or (>= (+ idx 1) end) (not (%c-hex-digit? (string-ref str (+ idx 1)))))
               (%c-lex-raise-error "C99-LEX-003" fname sl sc el sc2
                                   "Hex escape sequence \\x requires at least one hex digit")
               (let loop ((j (+ idx 1)) (acc 0))
                 (if (and (< j end) (%c-hex-digit? (string-ref str j)))
                     (loop (+ j 1) (+ (* acc 16) (%c-digit-val (string-ref str j))))
                     (cons (integer->char (modulo acc 256)) j)))))
          (else
           (if (%c-octal-digit? c)
               (let loop ((j idx) (cnt 0) (acc 0))
                 (if (and (< j end) (< cnt 3) (%c-octal-digit? (string-ref str j)))
                     (loop (+ j 1) (+ cnt 1)
                           (+ (* acc 8) (%c-digit-val (string-ref str j))))
                     (cons (integer->char (modulo acc 256)) j)))
               (cons c (+ idx 1))))))))

(define (%c-decode-escaped-chars str start end fname sl sc el sc2)
  (let ((nul (integer->char 0)))
    (let loop ((i start) (acc '()))
      (if (>= i end)
          (reverse acc)
          (let ((ch (string-ref str i)))
            (cond
              ((char=? ch nul)
               (%c-lex-raise-error "C99-LEX-003" fname sl sc el sc2
                                   "Unexpected NUL byte inside literal"))
              ((char=? ch #\\)
               (let ((res (%c-decode-escape str (+ i 1) end fname sl sc el sc2)))
                 (loop (cdr res) (cons (car res) acc))))
              (else
               (loop (+ i 1) (cons ch acc)))))))))

(define (%c-decode-char-literal lexeme fname sl sc el sc2)
  (let* ((len (string-length lexeme))
         (body-start (if (and (> len 0) (char=? (string-ref lexeme 0) #\L)) 2 1))
         (body-end (- len 1))
         (chars (%c-decode-escaped-chars lexeme body-start body-end fname sl sc el sc2)))
    (if (null? chars)
        0
        (let loop ((cs chars) (acc 0))
          (if (null? cs)
              acc
              (loop (cdr cs) (+ (* acc 256) (char->integer (car cs)))))))))

(define (%c-decode-string-literal lexeme fname sl sc el sc2)
  (let* ((len (string-length lexeme))
         (body-start (if (and (> len 0) (char=? (string-ref lexeme 0) #\L)) 2 1))
         (body-end (- len 1))
         (chars (%c-decode-escaped-chars lexeme body-start body-end fname sl sc el sc2)))
    (list->string chars)))

(define (%c-build-token tag lexeme span at-bol? has-ws? fname)
  (let ((sl (span-start-line span))
        (sc (span-start-col span))
        (el (span-end-line span))
        (ec (span-end-col span)))
    (case tag
      ((kw)
       (make-c-token 'keyword lexeme (string->symbol lexeme) span at-bol? has-ws? '()))
      ((id)
       (make-c-token 'ident lexeme (string->symbol lexeme) span at-bol? has-ws? '()))
      ((int)
       (make-c-token 'int-lit lexeme (%c-decode-int-literal lexeme) span at-bol? has-ws? '()))
      ((flt)
       (make-c-token 'float-lit lexeme (%c-decode-float-literal lexeme) span at-bol? has-ws? '()))
      ((ch)
       (make-c-token 'char-lit lexeme
                     (%c-decode-char-literal lexeme fname sl sc el ec)
                     span at-bol? has-ws? '()))
      ((str)
       (make-c-token 'string-lit lexeme
                     (%c-decode-string-literal lexeme fname sl sc el ec)
                     span at-bol? has-ws? '()))
      ((punct)
       (make-c-token 'punct lexeme lexeme span at-bol? has-ws? '()))
      (else
       (make-c-token 'punct lexeme lexeme span at-bol? has-ws? '())))))

;;; -----------------------------------------------------------------------
;;; 6. Public Entry Points & CPP/PEG Bridge Utilities
;;; -----------------------------------------------------------------------

(define (c-tokenize-string src-text . maybe-filename)
  (let* ((fname (if (pair? maybe-filename) (car maybe-filename) "<c99-input>")))
    (diagnostic-register-source-string! fname src-text)
    (let* ((norm-info (%c-normalize-and-map-coords src-text))
           (norm-text (car norm-info))
           (line-vec  (cadr norm-info))
           (col-vec   (caddr norm-info))
           (norm-len  (string-length norm-text))
           (nul-ch    (integer->char 0)))
      (let loop ((pos 0) (init-bol? #t) (acc '()))
        (let* ((triv     (%c-skip-trivia norm-text norm-len pos line-vec col-vec fname init-bol?))
               (tok-pos  (car triv))
               (at-bol?  (cadr triv))
               (has-ws?  (caddr triv)))
          (if (>= tok-pos norm-len)
              (let ((eof-sp (make-source-span fname
                                              (vector-ref line-vec norm-len)
                                              (vector-ref col-vec norm-len)
                                              (vector-ref line-vec norm-len)
                                              (vector-ref col-vec norm-len)
                                              #f
                                              (next-source-span-id!))))
                (reverse (cons (make-c-token 'eof "" 'eof eof-sp at-bol? has-ws? '()) acc)))
              (let ((ch (string-ref norm-text tok-pos)))
                (if (char=? ch nul-ch)
                    (%c-lex-raise-error
                     "C99-LEX-003" fname
                     (vector-ref line-vec tok-pos) (vector-ref col-vec tok-pos)
                     (vector-ref line-vec (+ tok-pos 1)) (vector-ref col-vec (+ tok-pos 1))
                     "Unexpected NUL byte in C99 source")
                    (let ((hit (%c-scan-raw-token norm-text norm-len tok-pos)))
                      (if (not hit)
                          (let ((s-ln (vector-ref line-vec tok-pos))
                                (s-cl (vector-ref col-vec tok-pos))
                                (e-idx (min norm-len (+ tok-pos 1))))
                            (if (or (char=? ch #\")
                                    (char=? ch #\')
                                    (and (char=? ch #\L)
                                         (< (+ tok-pos 1) norm-len)
                                         (or (char=? (string-ref norm-text (+ tok-pos 1)) #\")
                                             (char=? (string-ref norm-text (+ tok-pos 1)) #\'))))
                                (%c-lex-raise-error
                                 "C99-LEX-002" fname s-ln s-cl
                                 (vector-ref line-vec e-idx) (vector-ref col-vec e-idx)
                                 "Unterminated character or string literal")
                                (%c-lex-raise-error
                                 "C99-LEX-003" fname s-ln s-cl
                                 (vector-ref line-vec e-idx) (vector-ref col-vec e-idx)
                                 (string-append "Invalid C99 token starting at '" (string ch) "'"))))
                          (let* ((tag      (car hit))
                                 (next-pos (cdr hit))
                                 (lexeme   (substring norm-text tok-pos next-pos))
                                 (sp       (make-source-span fname
                                                             (vector-ref line-vec tok-pos)
                                                             (vector-ref col-vec tok-pos)
                                                             (vector-ref line-vec next-pos)
                                                             (vector-ref col-vec next-pos)
                                                             #f
                                                             (next-source-span-id!)))
                                 (tok      (%c-build-token tag lexeme sp at-bol? has-ws? fname)))
                            (loop next-pos #f (cons tok acc)))))))))))))

(define (c-tokenize-file filepath)
  (c-tokenize-string (read-all-file-text filepath) filepath))

(define (%c-byte->octal3-escape code)
  (let* ((d2 (quotient code 64))
         (r2 (modulo code 64))
         (d1 (quotient r2 8))
         (d0 (modulo r2 8)))
    (string #\\
            (integer->char (+ 48 d2))
            (integer->char (+ 48 d1))
            (integer->char (+ 48 d0)))))

(define (%c-escape-string-for-c str)
  (let ((n (string-length str)))
    (let loop ((i 0) (parts '()))
      (if (>= i n)
          (apply string-append (reverse parts))
          (let* ((ch (string-ref str i))
                 (code (char->integer ch))
                 (seg (cond
                        ((= code 10) "\\n")
                        ((= code 9)  "\\t")
                        ((= code 13) "\\r")
                        ((= code 92) "\\\\")
                        ((= code 34) "\\\"")
                        ((or (< code 32) (>= code 127))
                         (%c-byte->octal3-escape code))
                        (else (string ch)))))
            (loop (+ i 1) (cons seg parts)))))))

(define (c-concat-adjacent-string-tokens tokens)
  (let loop ((rest tokens) (acc '()))
    (cond
      ((null? rest)
       (reverse acc))
      ((eq? (c-token-kind (car rest)) 'string-lit)
       (let ((first-tok (car rest)))
         (let gather ((cur-rest (cdr rest))
                      (vals (list (c-token-value first-tok)))
                      (last-tok first-tok))
           (if (and (pair? cur-rest)
                    (eq? (c-token-kind (car cur-rest)) 'string-lit))
               (gather (cdr cur-rest)
                       (cons (c-token-value (car cur-rest)) vals)
                       (car cur-rest))
               (let* ((merged-val (apply string-append (reverse vals)))
                      (merged-lex (string-append "\"" (%c-escape-string-for-c merged-val) "\""))
                      (s1 (c-token-span first-tok))
                      (s2 (c-token-span last-tok))
                      (merged-sp (make-source-span
                                  (span-file s1)
                                  (span-start-line s1) (span-start-col s1)
                                  (span-end-line s2) (span-end-col s2)
                                  (span-macro-origin s1)
                                  (next-source-span-id!)))
                      (merged-tok (make-c-token
                                   'string-lit
                                   merged-lex
                                   merged-val
                                   merged-sp
                                   (c-token-at-bol? first-tok)
                                   (c-token-has-leading-space? first-tok)
                                   (c-token-hide-set first-tok))))
                 (loop cur-rest (cons merged-tok acc)))))))
      (else
       (loop (cdr rest) (cons (car rest) acc))))))

(define (%c-word-like-char? ch)
  (let ((c (char->integer ch)))
    (or (and (>= c 97) (<= c 122))
        (and (>= c 65) (<= c 90))
        (and (>= c 48) (<= c 57))
        (= c 95))))

(define (%c-need-token-separator? prev-lex curr-lex)
  (let ((pl (string-length prev-lex))
        (cl (string-length curr-lex)))
    (and (> pl 0)
         (> cl 0)
         (%c-word-like-char? (string-ref prev-lex (- pl 1)))
         (%c-word-like-char? (string-ref curr-lex 0)))))

(define (c-tokens->source-string tokens)
  (let loop ((rest tokens) (first? #t) (prev-lex "") (parts '()))
    (if (null? rest)
        (apply string-append (reverse parts))
        (let ((tok (car rest)))
          (if (eq? (c-token-kind tok) 'eof)
              (loop (cdr rest) first? prev-lex parts)
              (let* ((lex (c-token-lexeme tok))
                     (sep (cond
                            (first? "")
                            ((c-token-at-bol? tok) "\n")
                            ((or (c-token-has-leading-space? tok)
                                 (%c-need-token-separator? prev-lex lex))
                             " ")
                            (else ""))))
                (loop (cdr rest) #f lex (cons lex (cons sep parts)))))))))
