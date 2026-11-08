;;; =======================================================================
;;; ULisp Standard Library: reader.scm
;;; Hand-written recursive descent S-expression reader in pure Scheme
;;; Extended with R7RS Port Specification & Issue #534
;;; =======================================================================

;; §6.13.2 Input procedures: Lexical and character classification helpers

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

(define (%char-downcase-ascii c)
  (let ((code (char->integer c)))
    (if (and (>= code 65) (<= code 90))
        (integer->char (+ code 32))
        c)))

(define (%str-ci-eq-range? str start end target)
  (let ((tlen (string-length target)))
    (if (not (= (- end start) tlen))
        #f
        (let loop ((i 0))
          (if (= i tlen)
              #t
              (if (char=? (%char-downcase-ascii (string-ref str (+ start i)))
                          (string-ref target i))
                  (loop (+ i 1))
                  #f))))))

(define (%find-char-in-range str start end ch)
  (let loop ((i start))
    (cond
      ((>= i end) #f)
      ((char=? (string-ref str i) ch) i)
      (else (loop (+ i 1))))))

(define (%find-exp-in-range str start end)
  (let loop ((i start))
    (if (>= i end)
        #f
        (let ((c (%char-downcase-ascii (string-ref str i))))
          (if (or (char=? c #\e) (char=? c #\s) (char=? c #\f)
                  (char=? c #\d) (char=? c #\l))
              i
              (loop (+ i 1)))))))

(define (%parse-uint-range str start end radix limit)
  (if (>= start end)
      #f
      (let loop ((pos start) (acc 0) (count 0))
        (if (>= pos end)
            (if (= count 0) #f acc)
            (let ((d (ulisp-digit-value (string-ref str pos) radix)))
              (if (not d)
                  #f
                  (let ((q (quotient limit radix))
                        (r (modulo limit radix)))
                    (if (or (> acc q) (and (= acc q) (> d r)))
                        #f
                        (loop (+ pos 1)
                              (+ (* acc radix) d)
                              (+ count 1))))))))))

(define (%parse-signed-int-range str start end radix)
  (if (>= start end)
      #f
      (let* ((c0 (string-ref str start))
             (has-sign? (or (char=? c0 #\+) (char=? c0 #\-)))
             (neg? (char=? c0 #\-))
             (dstart (if has-sign? (+ start 1) start))
             (limit (if neg? *ulisp-fixnum-min-abs* *ulisp-fixnum-max*))
             (uval (%parse-uint-range str dstart end radix limit)))
        (if (not uval)
            #f
            (if neg? (- 0 uval) uval)))))

(define (%parse-decimal-or-exp-range str start end)
  (if (>= start end)
      #f
      (let* ((c0 (string-ref str start))
             (has-sign? (or (char=? c0 #\+) (char=? c0 #\-)))
             (neg? (char=? c0 #\-))
             (mstart (if has-sign? (+ start 1) start))
             (exp-idx (%find-exp-in-range str mstart end))
             (mend (if exp-idx exp-idx end))
             (exp-val (if exp-idx
                          (%parse-signed-int-range str (+ exp-idx 1) end 10)
                          0)))
        (if (or (not exp-val) (>= mstart mend) (> exp-val 15) (< exp-val -15))
            #f
            (let ((dot-idx (%find-char-in-range str mstart mend #\.)))
              (if dot-idx
                  (let* ((ilen (- dot-idx mstart))
                         (flen (- mend (+ dot-idx 1)))
                         (ipart (if (= ilen 0)
                                    0
                                    (%parse-uint-range str mstart dot-idx 10 *ulisp-fixnum-max*)))
                         (fpart (if (= flen 0)
                                    0
                                    (%parse-uint-range str (+ dot-idx 1) mend 10 *ulisp-fixnum-max*))))
                    (if (or (and (= ilen 0) (= flen 0))
                            (not ipart)
                            (not fpart)
                            (> flen 12))
                        #f
                        (let* ((fscale (%int-expt 10 flen))
                               (base-rat (make-rational (+ (* ipart fscale) fpart) fscale))
                               (scaled-rat
                                (cond
                                  ((= exp-val 0) base-rat)
                                  ((> exp-val 0) (rat* base-rat (%int-expt 10 exp-val)))
                                  (else (rat/ base-rat (%int-expt 10 (- 0 exp-val))))))
                               (signed-rat (if neg? (rat- scaled-rat) scaled-rat)))
                          (cons 'inexact-real signed-rat))))
                  ;; No dot, must have exp-idx
                  (let ((ipart (%parse-uint-range str mstart mend 10 *ulisp-fixnum-max*)))
                    (if (not ipart)
                        #f
                        (let* ((scaled-rat
                                (cond
                                  ((= exp-val 0) ipart)
                                  ((> exp-val 0) (* ipart (%int-expt 10 exp-val)))
                                  (else (make-rational ipart (%int-expt 10 (- 0 exp-val))))))
                               (signed-rat (if neg? (rat- scaled-rat) scaled-rat)))
                          (cons 'inexact-real signed-rat))))))))))

(define (%parse-real-token str start end radix exactness-pref)
  (cond
    ((>= start end) #f)
    ((%str-ci-eq-range? str start end "+inf.0")
     (if (eq? exactness-pref 'exact) #f +inf.0))
    ((%str-ci-eq-range? str start end "-inf.0")
     (if (eq? exactness-pref 'exact) #f -inf.0))
    ((or (%str-ci-eq-range? str start end "+nan.0")
         (%str-ci-eq-range? str start end "-nan.0"))
     (if (eq? exactness-pref 'exact) #f +nan.0))
    (else
     (let ((slash-idx (%find-char-in-range str start end #\/)))
       (if slash-idx
           (let ((n (%parse-signed-int-range str start slash-idx radix))
                 (d (%parse-uint-range str (+ slash-idx 1) end radix *ulisp-fixnum-max*)))
             (if (and n d (> d 0))
                 (let ((r (make-rational n d)))
                   (if (eq? exactness-pref 'inexact)
                       (inexact r)
                       r))
                 #f))
           (if (and (= radix 10)
                    (or (%find-char-in-range str start end #\.)
                        (%find-exp-in-range str start end)))
               (let ((dec-res (%parse-decimal-or-exp-range str start end)))
                 (if (not dec-res)
                     #f
                     (let ((exact-rat (cdr dec-res)))
                       (if (eq? exactness-pref 'exact)
                           exact-rat
                           (inexact exact-rat)))))
               (let ((ival (%parse-signed-int-range str start end radix)))
                 (if (not ival)
                     #f
                     (if (eq? exactness-pref 'inexact)
                         (inexact ival)
                         ival)))))))))

(define (%find-complex-split-sign str start end)
  (let loop ((i (- end 2)))
    (if (<= i start)
        #f
        (let ((c (string-ref str i))
              (prev (%char-downcase-ascii (string-ref str (- i 1)))))
          (if (and (or (char=? c #\+) (char=? c #\-))
                   (not (or (char=? prev #\e) (char=? prev #\s)
                            (char=? prev #\f) (char=? prev #\d)
                            (char=? prev #\l))))
              i
              (loop (- i 1)))))))

(define (%parse-complex-or-real str start end radix exactness-pref)
  (if (>= start end)
      #f
      (let ((at-idx (%find-char-in-range str start end #\@)))
        (if at-idx
            (let ((r (%parse-real-token str start at-idx radix exactness-pref))
                  (theta (%parse-real-token str (+ at-idx 1) end radix exactness-pref)))
              (if (and r theta)
                  (let ((z (make-polar r theta)))
                    (cond
                      ((eq? exactness-pref 'exact) (exact z))
                      ((eq? exactness-pref 'inexact) (inexact z))
                      (else z)))
                  #f))
            (let ((last-ch (%char-downcase-ascii (string-ref str (- end 1)))))
              (if (and (char=? last-ch #\i)
                       (not (%str-ci-eq-range? str start end "+inf.0"))
                       (not (%str-ci-eq-range? str start end "-inf.0")))
                  (cond
                    ((%str-ci-eq-range? str start end "+i")
                     (let ((one (if (eq? exactness-pref 'inexact) (inexact 1) 1))
                           (zero (if (eq? exactness-pref 'inexact) (inexact 0) 0)))
                       (make-rectangular zero one)))
                    ((%str-ci-eq-range? str start end "-i")
                     (let ((neg-one (if (eq? exactness-pref 'inexact) (inexact -1) -1))
                           (zero (if (eq? exactness-pref 'inexact) (inexact 0) 0)))
                       (make-rectangular zero neg-one)))
                    (else
                     (let ((split-idx (%find-complex-split-sign str start end)))
                       (if split-idx
                           (let* ((re (%parse-real-token str start split-idx radix exactness-pref))
                                  (im (cond
                                        ((= (+ split-idx 1) (- end 1))
                                         (let ((s (if (char=? (string-ref str split-idx) #\-) -1 1)))
                                           (if (eq? exactness-pref 'inexact) (inexact s) s)))
                                        (else
                                         (%parse-real-token str split-idx (- end 1) radix exactness-pref)))))
                             (if (and re im)
                                 (let ((re2 (if (and (inexact? im) (exact? re) (not (eq? exactness-pref 'exact)))
                                                (inexact re)
                                                re))
                                       (im2 (if (and (inexact? re) (exact? im) (not (eq? exactness-pref 'exact)))
                                                (inexact im)
                                                im)))
                                   (make-rectangular re2 im2))
                                 #f))
                           ;; Pure imaginary with sign at start: +4i, -2.5i
                           (let ((c0 (string-ref str start)))
                             (if (or (char=? c0 #\+) (char=? c0 #\-))
                                 (let ((im (%parse-real-token str start (- end 1) radix exactness-pref)))
                                   (if im
                                       (let ((zero (if (inexact? im) (inexact 0) 0)))
                                         (make-rectangular zero im))
                                       #f))
                                 #f))))))
                  (%parse-real-token str start end radix exactness-pref)))))))

(define (string->number-core str radix explicit-radix?)
  (if (not (string? str))
      #f
      (let ((len (string-length str)))
        (if (= len 0)
            #f
            (let* ((lead-sign? (and (>= len 3)
                                    (or (char=? (string-ref str 0) #\+)
                                        (char=? (string-ref str 0) #\-))
                                    (char=? (string-ref str 1) #\#)))
                   (start-idx (if lead-sign? 1 0)))
              (let parse-prefix ((i start-idx)
                                 (radix-found #f)
                                 (exactness-found #f))
                (if (and (< (+ i 1) len)
                         (char=? (string-ref str i) #\#))
                    (let ((c (%char-downcase-ascii (string-ref str (+ i 1)))))
                      (cond
                        ((char=? c #\b)
                         (if radix-found #f (parse-prefix (+ i 2) 2 exactness-found)))
                        ((char=? c #\o)
                         (if radix-found #f (parse-prefix (+ i 2) 8 exactness-found)))
                        ((char=? c #\d)
                         (if radix-found #f (parse-prefix (+ i 2) 10 exactness-found)))
                        ((char=? c #\x)
                         (if radix-found #f (parse-prefix (+ i 2) 16 exactness-found)))
                        ((char=? c #\e)
                         (if exactness-found #f (parse-prefix (+ i 2) radix-found 'exact)))
                        ((char=? c #\i)
                         (if exactness-found #f (parse-prefix (+ i 2) radix-found 'inexact)))
                        (else #f)))
                    (let ((effective-radix
                           (cond
                             ((and radix-found explicit-radix?)
                              (if (= radix-found radix) radix #f))
                             (radix-found radix-found)
                             (else radix))))
                      (if (or (not effective-radix)
                              (not (or (= effective-radix 2)
                                       (= effective-radix 8)
                                       (= effective-radix 10)
                                       (= effective-radix 16))))
                          #f
                          (if lead-sign?
                              (if (or (>= i len)
                                      (char=? (string-ref str i) #\+)
                                      (char=? (string-ref str i) #\-))
                                  #f
                                  (let ((s2 (string-append (string (string-ref str 0))
                                                           (substring str i len))))
                                    (%parse-complex-or-real s2 0 (string-length s2) effective-radix exactness-found)))
                              (%parse-complex-or-real str i len effective-radix exactness-found)))))))))))

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
           ;; R7RS Radix & Exactness Prefixes for numbers: #b, #o, #d, #x, #e, #i
           ((or (ulisp-char=? c2 #\b) (ulisp-char=? c2 #\B)
                (ulisp-char=? c2 #\o) (ulisp-char=? c2 #\O)
                (ulisp-char=? c2 #\d) (ulisp-char=? c2 #\D)
                (ulisp-char=? c2 #\x) (ulisp-char=? c2 #\X)
                (ulisp-char=? c2 #\e) (ulisp-char=? c2 #\E)
                (ulisp-char=? c2 #\i) (ulisp-char=? c2 #\I))
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
                          ((string=? name "return")  (integer->char 13))
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
;;; §6.13.2 R7RS Standard Macros and Compatibility Wrappers: read
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
