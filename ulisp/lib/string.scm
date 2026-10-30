;;; =======================================================================
;;; ULisp Standard Library: string.scm
;;; String and Symbol manipulation procedures implemented purely in Scheme
;;; =======================================================================

(define (length ls)
  (let loop ((l ls) (n 0))
    (if (null? l) n
        (loop (cdr l) (+ n 1)))))

(define (reverse ls)
  (let loop ((l ls) (acc '()))
    (if (null? l)
        acc
        (loop (cdr l) (cons (car l) acc)))))

(define (string-append2 s1 s2)
  (let* ((len1 (string-length s1))
         (len2 (string-length s2))
         (total (+ len1 len2))
         (res (make-string total)))
    (let loop1 ((i 0))
      (if (< i len1)
          (begin
            (string-set! res i (string-ref s1 i))
            (loop1 (+ i 1)))
          (let loop2 ((j 0))
            (if (< j len2)
                (begin
                  (string-set! res (+ len1 j) (string-ref s2 j))
                  (loop2 (+ j 1)))
                res))))))

(define (substring str start end)
  (let* ((len (- end start))
         (res (make-string len)))
    (let loop ((i 0))
      (if (< i len)
          (begin
            (string-set! res i (string-ref str (+ start i)))
            (loop (+ i 1)))
          res))))

(define (number->string n)
  (if (= n 0)
      "0"
      (let* ((neg? (< n 0))
             (abs-n (if neg? (- 0 n) n)))
        (let loop ((curr abs-n) (digits '()))
          (if (= curr 0)
              (let* ((chars (if neg? (cons #\- digits) digits))
                     (len (length chars))
                     (res (make-string len)))
                (let copy-loop ((i 0) (cs chars))
                  (if (null? cs)
                      res
                      (begin
                        (string-set! res i (car cs))
                        (copy-loop (+ i 1) (cdr cs))))))
              (let* ((rem (modulo curr 10))
                     (next-curr (quotient curr 10))
                     (ch (integer->char (+ 48 rem))))
                (loop next-curr (cons ch digits))))))))


(define (escape-gas-string s)
  (let* ((len (string-length s))
         ;; Count extra chars needed for escape
         (extra (let count-loop ((i 0) (acc 0))
                  (if (< i len)
                      (let ((c (string-ref s i)))
                        (if (or (char=? c #\newline)
                                (or (char=? c #\tab)
                                    (or (char=? c (integer->char 13))
                                        (or (char=? c #\\)
                                            (char=? c #\")))))
                            (count-loop (+ i 1) (+ acc 1))
                            (count-loop (+ i 1) acc)))
                      acc))))
    (if (= extra 0)
        s
        (let ((res (make-string (+ len extra))))
          (let loop ((i 0) (out-idx 0))
            (if (< i len)
                (let ((c (string-ref s i)))
                  (cond
                    ((char=? c #\newline)
                     (string-set! res out-idx #\\)
                     (string-set! res (+ out-idx 1) #\n)
                     (loop (+ i 1) (+ out-idx 2)))
                    ((char=? c #\tab)
                     (string-set! res out-idx #\\)
                     (string-set! res (+ out-idx 1) #\t)
                     (loop (+ i 1) (+ out-idx 2)))
                    ((char=? c (integer->char 13))
                     (string-set! res out-idx #\\)
                     (string-set! res (+ out-idx 1) #\r)
                     (loop (+ i 1) (+ out-idx 2)))
                    ((char=? c #\\)
                     (string-set! res out-idx #\\)
                     (string-set! res (+ out-idx 1) #\\)
                     (loop (+ i 1) (+ out-idx 2)))
                    ((char=? c #\")
                     (string-set! res out-idx #\\)
                     (string-set! res (+ out-idx 1) #\")
                     (loop (+ i 1) (+ out-idx 2)))
                    (else
                     (string-set! res out-idx c)
                     (loop (+ i 1) (+ out-idx 1)))))
                res))))))

(define (%string-eq-loop s1 s2 i len)
  (if (< i len)
      (if (char=? (string-ref s1 i) (string-ref s2 i))
          (%string-eq-loop s1 s2 (+ i 1) len)
          #f)
      #t))

(define (string=? s1 s2)
  (let ((len1 (string-length s1))
        (len2 (string-length s2)))
    (if (= len1 len2)
        (%string-eq-loop s1 s2 0 len1)
        #f)))

;;; Dynamic Symbol Registry in pure Scheme (shared across quoted literals and reader)
(define *symbol-registry* (cons '() '()))
(define *next-sym-id* (cons 100 '()))

(define (%string-find-symbol str entries)
  (if (or (null? entries) (not (pair? entries)))
      #f
      (let ((entry (car entries)))
        (if (and (pair? entry) (string=? (car entry) str))
            (cdr entry)
            (%string-find-symbol str (cdr entries))))))

(define (%symbol-hash-str str)
  (let ((len (string-length str)))
    (let loop ((i 0) (h 5381))
      (if (= i len)
          (modulo h 16777213)
          (let ((c (char->integer (string-ref str i))))
            (loop (+ i 1)
                  (modulo (+ (* h 33) c) 16777213)))))))

(define (%sym-id-taken? sym entries)
  (if (or (null? entries) (not (pair? entries)))
      #f
      (let ((entry (car entries)))
        (if (and (pair? entry) (eq? (cdr entry) sym))
            #t
            (%sym-id-taken? sym (cdr entries))))))

(define (string->symbol str)
  (let ((found (%string-find-symbol str (car *symbol-registry*))))
    (if found
        found
        (let loop ((h (%symbol-hash-str str)))
          (let ((candidate (integer->symbol h)))
            (if (%sym-id-taken? candidate (car *symbol-registry*))
                (loop (modulo (+ (* h 33) 1) 16777213))
                (begin
                  (set-car! *symbol-registry* (cons (cons str candidate) (car *symbol-registry*)))
                  candidate)))))))

(define *known-runtime-symbols*
  '((quote . "quote")
    (quasiquote . "quasiquote")
    (unquote . "unquote")
    (unquote-splicing . "unquote-splicing")
    (vector . "vector")
    (bytevector . "bytevector")
    (... . "...")
    (_ . "_")
    (guard . "guard")
    (nanopass-map2 . "nanopass-map2")
    (nanopass-map3 . "nanopass-map3")
    (string-append2 . "string-append2")
    (vector-append2 . "vector-append2")
    (bytevector-append2 . "bytevector-append2")
    (nanopass-try-clause . "nanopass-try-clause")
    (nanopass-catamorphism-step . "nanopass-catamorphism-step")
    (set-current-pass! . "set-current-pass!")
    (nanopass-verifier-enabled? . "nanopass-verifier-enabled?")
    (nanopass-verify-ast . "nanopass-verify-ast")
    (with-call-frame . "with-call-frame")
    (nanopass-display-ast-diff . "nanopass-display-ast-diff")
    (nanopass-trace-enabled? . "nanopass-trace-enabled?")
    (nanopass-register-language! . "nanopass-register-language!")
    (nanopass-parse-language-spec . "nanopass-parse-language-spec")
    (nanopass-parse . "nanopass-parse")
    (nanopass-unparse . "nanopass-unparse")
    (nanopass-ast-valid? . "nanopass-ast-valid?")
    (nanopass-parse-nt . "nanopass-parse-nt")
    (current-jiffy . "current-jiffy")
    (jiffies-per-second . "jiffies-per-second")
    (sys-getenv . "sys-getenv")
    (sys-clock-gettime-monotonic . "sys-clock-gettime-monotonic")
    (gc-current-heap-bytes . "gc-current-heap-bytes")))

(define (%sym-assoc-string sym alist)
  (cond
    ((null? alist) #f)
    ((not (pair? alist)) #f)
    ((and (pair? (car alist)) (eq? (car (car alist)) sym))
     (cdr (car alist)))
    (else (%sym-assoc-string sym (cdr alist)))))

(define (%symbol-find-string sym entries)
  (let ((known (%sym-assoc-string sym *known-runtime-symbols*)))
    (if known
        known
        (let loop ((es entries))
          (if (or (null? es) (not (pair? es)))
              "?"
              (let ((entry (car es)))
                (if (and (pair? entry) (eq? (cdr entry) sym))
                    (car entry)
                    (loop (cdr es)))))))))

(define (symbol->string sym)
  (%symbol-find-string sym (car *symbol-registry*)))

(define (string-copy-range str start end)
  (substring str start end))

(define (string-copy-range! to at from start end)
  (let ((count (- end start)))
    (if (and (eq? to from) (> at start))
        ;; Backward copy to handle overlapping regions
        (let loop ((i (- count 1)))
          (if (>= i 0)
              (begin
                (string-set! to (+ at i) (string-ref from (+ start i)))
                (loop (- i 1)))
              63))
        ;; Forward copy
        (let loop ((i 0))
          (if (< i count)
              (begin
                (string-set! to (+ at i) (string-ref from (+ start i)))
                (loop (+ i 1)))
              63)))))

(define (string-fill-range! str fill start end)
  (let loop ((i start))
    (if (< i end)
        (begin
          (string-set! str i fill)
          (loop (+ i 1)))
        63)))

(define (string-map proc str)
  (let* ((len (string-length str))
         (res (make-string len)))
    (let loop ((i 0))
      (if (< i len)
          (begin
            (string-set! res i (proc (string-ref str i)))
            (loop (+ i 1)))
          res))))

(define (string-for-each proc str)
  (let ((len (string-length str)))
    (let loop ((i 0))
      (if (< i len)
          (begin
            (proc (string-ref str i))
            (loop (+ i 1)))
          63))))

(define (string-copy str)
  (string-copy-range str 0 (string-length str)))

(define (string-fill! str fill)
  (string-fill-range! str fill 0 (string-length str)))

;; ---------------------------------------------------------------------
;; §6.7 Strings: string->list-range / list->string
;; ---------------------------------------------------------------------
(define (string->list-range str start end)
  (let loop ((i (- end 1)) (acc '()))
    (if (< i start)
        acc
        (loop (- i 1) (cons (string-ref str i) acc)))))

(define (list->string lst)
  (let* ((len (length lst))
         (s (make-string len)))
    (let loop ((curr lst) (i 0))
      (if (null? curr)
          s
          (begin
            (string-set! s i (car curr))
            (loop (cdr curr) (+ i 1)))))))

(define string
  (case-lambda
    (() "")
    (chars (list->string chars))))

;; ---------------------------------------------------------------------
;; §6.7 Strings: Lexicographic Comparison (string<?, string>?, string<=?, string>=?)
;; ---------------------------------------------------------------------
(define (%string-compare s1 s2)
  (let ((len1 (string-length s1))
        (len2 (string-length s2)))
    (let ((min-len (if (< len1 len2) len1 len2)))
      (let loop ((i 0))
        (if (< i min-len)
            (let ((n1 (char->integer (string-ref s1 i)))
                  (n2 (char->integer (string-ref s2 i))))
              (cond
                ((< n1 n2) -1)
                ((> n1 n2) 1)
                (else (loop (+ i 1)))))
            (cond
              ((< len1 len2) -1)
              ((> len1 len2) 1)
              (else 0)))))))

(define (string<? s1 s2)
  (< (%string-compare s1 s2) 0))

(define (string>? s1 s2)
  (> (%string-compare s1 s2) 0))

(define (string<=? s1 s2)
  (<= (%string-compare s1 s2) 0))

(define (string>=? s1 s2)
  (>= (%string-compare s1 s2) 0))


