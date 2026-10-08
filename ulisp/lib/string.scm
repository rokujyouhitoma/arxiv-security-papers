;;; =======================================================================
;;; ULisp Standard Library: string.scm
;;; String and Symbol manipulation procedures implemented purely in Scheme
;;; =======================================================================

(define (length ls)
  (let loop ((l ls) (n 0))
    (if (null? l) n
        (loop (cdr l) (+ n 1)))))

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

(define (string=? s1 s2)
  (let ((len1 (string-length s1))
        (len2 (string-length s2)))
    (if (= len1 len2)
        (let loop ((i 0))
          (if (< i len1)
              (if (char=? (string-ref s1 i) (string-ref s2 i))
                  (loop (+ i 1))
                  #f)
              #t))
        #f)))

;;; Dynamic Symbol Registry in pure Scheme (shared across quoted literals and reader)
(define *symbol-registry* (cons '() '()))
(define *next-sym-id* (cons 100 '()))

(define (string->symbol str)
  (let loop ((entries (car *symbol-registry*)))
    (if (null? entries)
        (let* ((curr-id (car *next-sym-id*))
               (sym (integer->symbol curr-id)))
          (set-car! *next-sym-id* (+ curr-id 1))
          (set-car! *symbol-registry* (cons (cons str sym) (car *symbol-registry*)))
          sym)
        (let ((entry (car entries)))
          (if (string=? (car entry) str)
              (cdr entry)
              (loop (cdr entries)))))))

(define (symbol->string sym)
  (let loop ((entries (car *symbol-registry*)))
    (if (null? entries)
        "?"
        (let ((entry (car entries)))
          (if (eq? (cdr entry) sym)
              (car entry)
              (loop (cdr entries)))))))




