;;; =======================================================================
;;; ULisp Standard Library: text.scm
;;; Specification: R7RS-large (Red Edition) / SRFI 135 (Immutable Texts)
;;; Description: Purely functional, immutable text sequence data type with
;;;              worst-case O(1) length, O(1) subtext slicing (structural sharing),
;;;              and logarithmic/constant time random access indexing.
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md §2.1
;;; =======================================================================

;; ---------------------------------------------------------------------
;; §2.1 R7RS-large Red Edition / SRFI 135: Internal Data Structures
;; ---------------------------------------------------------------------
;;
;; A text is represented as one of 4 tagged vector nodes:
;; 1. #(ulisp-text-leaf len str)
;; 2. #(ulisp-text-slice len src start end)
;; 3. #(ulisp-text-concat len left right depth)
;; 4. #(ulisp-text-repeat len char)

(define (%make-text-leaf str)
  (vector 'ulisp-text-leaf (string-length str) str))

(define (%make-text-repeat len ch)
  (vector 'ulisp-text-repeat len ch))

(define (%make-text-slice len src start end)
  (vector 'ulisp-text-slice len src start end))

(define (%make-text-concat len left right depth)
  (vector 'ulisp-text-concat len left right depth))

(define %empty-text
  (vector 'ulisp-text-leaf 0 ""))

(define (%text-depth txt)
  (let ((tag (vector-ref txt 0)))
    (if (eq? tag 'ulisp-text-concat)
        (vector-ref txt 4)
        1)))

;; ---------------------------------------------------------------------
;; §2.1 R7RS-large Red Edition / SRFI 135: Predicates
;; ---------------------------------------------------------------------

(define (text? obj)
  (and (vector? obj)
       (>= (vector-length obj) 3)
       (let ((tag (vector-ref obj 0)))
         (or (eq? tag 'ulisp-text-leaf)
             (eq? tag 'ulisp-text-slice)
             (eq? tag 'ulisp-text-concat)
             (eq? tag 'ulisp-text-repeat)))))

(define (textual? obj)
  (or (text? obj) (string? obj)))

(define (text-length text)
  (if (not (text? text))
      (error "text-length: expected text" text)
      (vector-ref text 1)))

(define (textual-length textual)
  (cond
    ((text? textual) (vector-ref textual 1))
    ((string? textual) (string-length textual))
    (else (error "textual-length: expected textual" textual))))

(define (textual-null? textual)
  (= (textual-length textual) 0))

;; ---------------------------------------------------------------------
;; §2.1 R7RS-large Red Edition / SRFI 135: Accessors & Flattening
;; ---------------------------------------------------------------------

(define (%text-ref txt idx)
  (let ((tag (vector-ref txt 0)))
    (cond
      ((eq? tag 'ulisp-text-leaf)
       (string-ref (vector-ref txt 2) idx))
      ((eq? tag 'ulisp-text-repeat)
       (vector-ref txt 2))
      ((eq? tag 'ulisp-text-slice)
       (let ((src (vector-ref txt 2))
             (start (vector-ref txt 3)))
         (%text-ref src (+ start idx))))
      ((eq? tag 'ulisp-text-concat)
       (let* ((left (vector-ref txt 2))
              (left-len (vector-ref left 1)))
         (if (< idx left-len)
             (%text-ref left idx)
             (%text-ref (vector-ref txt 3) (- idx left-len)))))
      (else
       (error "%text-ref: corrupt text node" txt)))))

(define (text-ref text idx)
  (if (not (text? text))
      (error "text-ref: expected text" text)
      (let ((len (vector-ref text 1)))
        (if (or (< idx 0) (>= idx len))
            (error "text-ref: index out of bounds" idx len)
            (%text-ref text idx)))))

(define (textual-ref textual idx)
  (cond
    ((text? textual)
     (let ((len (vector-ref textual 1)))
       (if (or (< idx 0) (>= idx len))
           (error "textual-ref: index out of bounds" idx len)
           (%text-ref textual idx))))
    ((string? textual)
     (let ((len (string-length textual)))
       (if (or (< idx 0) (>= idx len))
           (error "textual-ref: index out of bounds" idx len)
           (string-ref textual idx))))
    (else (error "textual-ref: expected textual" textual))))

(define (%text-flatten-into! txt dst dst-offset)
  (let ((tag (vector-ref txt 0)))
    (cond
      ((eq? tag 'ulisp-text-leaf)
       (let* ((str (vector-ref txt 2))
              (len (vector-ref txt 1)))
         (let loop ((i 0))
           (if (< i len)
               (begin
                 (string-set! dst (+ dst-offset i) (string-ref str i))
                 (loop (+ i 1)))))))
      ((eq? tag 'ulisp-text-repeat)
       (let ((len (vector-ref txt 1))
             (ch (vector-ref txt 2)))
         (let loop ((i 0))
           (if (< i len)
               (begin
                 (string-set! dst (+ dst-offset i) ch)
                 (loop (+ i 1)))))))
      ((eq? tag 'ulisp-text-slice)
       (let ((len (vector-ref txt 1)))
         (let loop ((i 0))
           (if (< i len)
               (begin
                 (string-set! dst (+ dst-offset i) (%text-ref txt i))
                 (loop (+ i 1)))))))
      ((eq? tag 'ulisp-text-concat)
       (let* ((left (vector-ref txt 2))
              (right (vector-ref txt 3))
              (left-len (vector-ref left 1)))
         (%text-flatten-into! left dst dst-offset)
         (%text-flatten-into! right dst (+ dst-offset left-len)))))))

(define (%text->string txt)
  (let* ((len (vector-ref txt 1))
         (res (make-string len)))
    (%text-flatten-into! txt res 0)
    res))

;; ---------------------------------------------------------------------
;; §2.1 R7RS-large Red Edition / SRFI 135: Subtexts & Slices (O(1))
;; ---------------------------------------------------------------------

(define (subtext text start end)
  (if (not (text? text))
      (error "subtext: expected text" text)
      (let ((len (vector-ref text 1)))
        (if (or (< start 0) (> start end) (> end len))
            (error "subtext: invalid range" start end len)
            (let ((count (- end start)))
              (cond
                ((= count 0) %empty-text)
                ((and (= start 0) (= end len)) text)
                (else
                 (let ((tag (vector-ref text 0)))
                   (cond
                     ((eq? tag 'ulisp-text-repeat)
                      (%make-text-repeat count (vector-ref text 2)))
                     ((eq? tag 'ulisp-text-slice)
                      (let ((src (vector-ref text 2))
                            (orig-start (vector-ref text 3)))
                        (%make-text-slice count src (+ orig-start start) (+ orig-start end))))
                     ((eq? tag 'ulisp-text-concat)
                      (let* ((left (vector-ref text 2))
                             (right (vector-ref text 3))
                             (left-len (vector-ref left 1)))
                        (cond
                          ((<= end left-len)
                           (subtext left start end))
                          ((>= start left-len)
                           (subtext right (- start left-len) (- end left-len)))
                          (else
                           (%make-text-slice count text start end)))))
                     (else
                      (%make-text-slice count text start end)))))))))))

(define (subtextual textual start end)
  (cond
    ((text? textual)
     (subtext textual start end))
    ((string? textual)
     (let ((len (string-length textual)))
       (if (or (< start 0) (> start end) (> end len))
           (error "subtextual: invalid range" start end len)
           (if (= start end)
               %empty-text
               (%make-text-leaf (substring textual start end))))))
    (else (error "subtextual: expected textual" textual))))

;; ---------------------------------------------------------------------
;; §2.1 R7RS-large Red Edition / SRFI 135: Basic Conversions (Defined Early)
;; ---------------------------------------------------------------------

(define (textual->text textual)
  (cond
    ((text? textual) textual)
    ((string? textual) (%make-text-leaf (substring textual 0 (string-length textual))))
    (else (error "textual->text: expected textual" textual))))

(define textual->string
  (case-lambda
    ((textual)
     (textual->string textual 0 (textual-length textual)))
    ((textual start)
     (textual->string textual start (textual-length textual)))
    ((textual start end)
     (cond
       ((string? textual)
        (let ((len (string-length textual)))
          (if (or (< start 0) (> start end) (> end len))
              (error "textual->string: invalid range" start end len)
              (substring textual start end))))
       ((text? textual)
        (%text->string (subtext textual start end)))
       (else (error "textual->string: expected textual" textual))))))

(define string->text
  (case-lambda
    ((str)
     (string->text str 0 (string-length str)))
    ((str start)
     (string->text str start (string-length str)))
    ((str start end)
     (if (not (string? str))
         (error "string->text: expected string" str)
         (let ((len (string-length str)))
           (if (or (< start 0) (> start end) (> end len))
               (error "string->text: invalid range" start end len)
               (if (= start end)
                   %empty-text
                   (%make-text-leaf (substring str start end)))))))))

(define (list->text chars)
  (let* ((len (length chars))
         (str (make-string len)))
    (let loop ((i 0) (cs chars))
      (if (null? cs)
          (%make-text-leaf str)
          (let ((c (car cs)))
            (if (not (char? c))
                (error "list->text: element is not a character" c)
                (begin
                  (string-set! str i c)
                  (loop (+ i 1) (cdr cs)))))))))

(define (reverse-list->text chars)
  (list->text (reverse chars)))

(define vector->text
  (case-lambda
    ((vec)
     (vector->text vec 0 (vector-length vec)))
    ((vec start)
     (vector->text vec start (vector-length vec)))
    ((vec start end)
     (if (not (vector? vec))
         (error "vector->text: expected vector" vec)
         (let* ((vlen (vector-length vec))
                (count (- end start)))
           (if (or (< start 0) (> start end) (> end vlen))
               (error "vector->text: invalid range" start end vlen)
               (if (= count 0)
                   %empty-text
                   (let ((str (make-string count)))
                     (let loop ((i 0))
                       (if (< i count)
                           (let ((c (vector-ref vec (+ start i))))
                             (if (not (char? c))
                                 (error "vector->text: element is not a character" c)
                                 (begin
                                   (string-set! str i c)
                                   (loop (+ i 1)))))
                           (%make-text-leaf str)))))))))))

(define textual->vector
  (case-lambda
    ((textual)
     (textual->vector textual 0 (textual-length textual)))
    ((textual start)
     (textual->vector textual start (textual-length textual)))
    ((textual start end)
     (let* ((len (textual-length textual))
            (count (- end start)))
       (if (or (< start 0) (> start end) (> end len))
           (error "textual->vector: invalid range" start end len)
           (let ((vec (make-vector count)))
             (let loop ((i 0))
               (if (< i count)
                   (begin
                     (vector-set! vec i (textual-ref textual (+ start i)))
                     (loop (+ i 1)))
                   vec))))))))

(define textual->list
  (case-lambda
    ((textual)
     (textual->list textual 0 (textual-length textual)))
    ((textual start)
     (textual->list textual start (textual-length textual)))
    ((textual start end)
     (let* ((len (textual-length textual)))
       (if (or (< start 0) (> start end) (> end len))
           (error "textual->list: invalid range" start end len)
           (let loop ((i (- end 1)) (acc '()))
             (if (< i start)
                 acc
                 (loop (- i 1) (cons (textual-ref textual i) acc)))))))))

;; ---------------------------------------------------------------------
;; §2.1 R7RS-large Red Edition / SRFI 135: Constructors
;; ---------------------------------------------------------------------

(define make-text
  (case-lambda
    ((len)
     (make-text len #\space))
    ((len char)
     (if (or (not (integer? len)) (< len 0))
         (error "make-text: invalid length" len)
         (if (not (char? char))
             (error "make-text: invalid char" char)
             (if (= len 0)
                 %empty-text
                 (%make-text-repeat len char)))))))

(define text
  (case-lambda
    (() %empty-text)
    ((c) (list->text (list c)))
    ((c1 c2) (list->text (list c1 c2)))
    ((c1 c2 c3) (list->text (list c1 c2 c3)))
    ((c1 c2 c3 c4) (list->text (list c1 c2 c3 c4)))
    ((c1 c2 c3 c4 . rest) (list->text (cons c1 (cons c2 (cons c3 (cons c4 rest))))))))

(define (text-tabulate len proc)
  (if (or (not (integer? len)) (< len 0))
      (error "text-tabulate: invalid length" len)
      (let ((str (make-string len)))
        (let loop ((i 0))
          (if (< i len)
              (let ((c (proc i)))
                (if (not (char? c))
                    (error "text-tabulate: procedure returned non-character" c)
                    (begin
                      (string-set! str i c)
                      (loop (+ i 1)))))
              (%make-text-leaf str))))))

(define (text-unfold stop? mapper successor seed)
  (let loop ((s seed) (acc '()))
    (if (stop? s)
        (list->text (reverse acc))
        (loop (successor s) (cons (mapper s) acc)))))

(define (text-unfold-right stop? mapper successor seed)
  (let loop ((s seed) (acc '()))
    (if (stop? s)
        (list->text acc)
        (loop (successor s) (cons (mapper s) acc)))))

;; ---------------------------------------------------------------------
;; §2.1 R7RS-large Red Edition / SRFI 135: Concatenation
;; ---------------------------------------------------------------------

(define (%text-append-2 t1 t2)
  (let ((len1 (text-length t1))
        (len2 (text-length t2)))
    (cond
      ((= len1 0) t2)
      ((= len2 0) t1)
      ((<= (+ len1 len2) 32)
       (%make-text-leaf (string-append (%text->string t1) (%text->string t2))))
      (else
       (let ((d1 (%text-depth t1))
             (d2 (%text-depth t2)))
         (let ((depth (+ 1 (max d1 d2))))
           (if (> depth 32)
               ;; Flatten to prevent unbalanced tree growth
               (%make-text-leaf (string-append (%text->string t1) (%text->string t2)))
               (%make-text-concat (+ len1 len2) t1 t2 depth))))))))

(define textual-append
  (case-lambda
    (() %empty-text)
    ((t) (textual->text t))
    ((t1 t2) (%text-append-2 (textual->text t1) (textual->text t2)))
    ((t1 t2 t3) (%text-append-2 (%text-append-2 (textual->text t1) (textual->text t2)) (textual->text t3)))
    ((t1 t2 t3 . rest)
     (let loop ((acc (%text-append-2 (%text-append-2 (textual->text t1) (textual->text t2)) (textual->text t3)))
                (rs rest))
       (if (null? rs)
           acc
           (loop (%text-append-2 acc (textual->text (car rs))) (cdr rs)))))))

(define (textual-concatenate textual-list)
  (let loop ((acc %empty-text) (rest textual-list))
    (if (null? rest)
        acc
        (loop (%text-append-2 acc (textual->text (car rest))) (cdr rest)))))

(define textual-concatenate-reverse
  (case-lambda
    ((textual-list)
     (textual-concatenate (reverse textual-list)))
    ((textual-list final-textual)
     (textual-append (textual-concatenate (reverse textual-list))
                     (textual->text final-textual)))
    ((textual-list final-textual end)
     (textual-append (textual-concatenate (reverse textual-list))
                     (subtextual final-textual 0 end)))))

(define textual-join
  (case-lambda
    ((textual-list)
     (textual-join textual-list " " 'infix))
    ((textual-list delimiter)
     (textual-join textual-list delimiter 'infix))
    ((textual-list delimiter grammar)
     (let ((delim (textual->text delimiter)))
       (cond
         ((null? textual-list)
          (if (eq? grammar 'strict-infix)
              (error "textual-join: strict-infix requires non-empty list" textual-list)
              %empty-text))
         ((eq? grammar 'infix)
          (let loop ((acc (textual->text (car textual-list)))
                     (rest (cdr textual-list)))
            (if (null? rest)
                acc
                (loop (textual-append acc delim (textual->text (car rest)))
                      (cdr rest)))))
         ((eq? grammar 'strict-infix)
          (textual-join textual-list delimiter 'infix))
         ((eq? grammar 'prefix)
          (let loop ((acc %empty-text) (rest textual-list))
            (if (null? rest)
                acc
                (loop (textual-append acc delim (textual->text (car rest)))
                      (cdr rest)))))
         ((eq? grammar 'suffix)
          (let loop ((acc %empty-text) (rest textual-list))
            (if (null? rest)
                acc
                (loop (textual-append acc (textual->text (car rest)) delim)
                      (cdr rest)))))
         (else
          (error "textual-join: invalid grammar" grammar)))))))

;; ---------------------------------------------------------------------
;; §2.1 R7RS-large Red Edition / SRFI 135: Selection, Take, Drop, Pad, Trim, Replace
;; ---------------------------------------------------------------------

(define textual-copy
  (case-lambda
    ((textual)
     (textual-copy textual 0 (textual-length textual)))
    ((textual start)
     (textual-copy textual start (textual-length textual)))
    ((textual start end)
     (subtextual textual start end))))

(define (textual-take textual nchars)
  (let ((len (textual-length textual)))
    (if (or (< nchars 0) (> nchars len))
        (error "textual-take: invalid nchars" nchars len)
        (subtextual textual 0 nchars))))

(define (textual-drop textual nchars)
  (let ((len (textual-length textual)))
    (if (or (< nchars 0) (> nchars len))
        (error "textual-drop: invalid nchars" nchars len)
        (subtextual textual nchars len))))

(define (textual-take-right textual nchars)
  (let ((len (textual-length textual)))
    (if (or (< nchars 0) (> nchars len))
        (error "textual-take-right: invalid nchars" nchars len)
        (subtextual textual (- len nchars) len))))

(define (textual-drop-right textual nchars)
  (let ((len (textual-length textual)))
    (if (or (< nchars 0) (> nchars len))
        (error "textual-drop-right: invalid nchars" nchars len)
        (subtextual textual 0 (- len nchars)))))

(define textual-pad
  (case-lambda
    ((textual len)
     (textual-pad textual len #\space 0 (textual-length textual)))
    ((textual len char)
     (textual-pad textual len char 0 (textual-length textual)))
    ((textual len char start)
     (textual-pad textual len char start (textual-length textual)))
    ((textual len char start end)
     (let* ((sub (subtextual textual start end))
            (slen (text-length sub)))
       (cond
         ((= slen len) sub)
         ((> slen len) (subtext sub (- slen len) slen))
         (else (textual-append (make-text (- len slen) char) sub)))))))

(define textual-pad-right
  (case-lambda
    ((textual len)
     (textual-pad-right textual len #\space 0 (textual-length textual)))
    ((textual len char)
     (textual-pad-right textual len char 0 (textual-length textual)))
    ((textual len char start)
     (textual-pad-right textual len char start (textual-length textual)))
    ((textual len char start end)
     (let* ((sub (subtextual textual start end))
            (slen (text-length sub)))
       (cond
         ((= slen len) sub)
         ((> slen len) (subtext sub 0 len))
         (else (textual-append sub (make-text (- len slen) char))))))))

(define textual-trim
  (case-lambda
    ((textual)
     (textual-trim textual char-whitespace? 0 (textual-length textual)))
    ((textual pred)
     (textual-trim textual pred 0 (textual-length textual)))
    ((textual pred start)
     (textual-trim textual pred start (textual-length textual)))
    ((textual pred start end)
     (let ((len (textual-length textual)))
       (if (or (< start 0) (> start end) (> end len))
           (error "textual-trim: invalid range" start end len)
           (let loop ((i start))
             (if (>= i end)
                 %empty-text
                 (if (pred (textual-ref textual i))
                     (loop (+ i 1))
                     (subtextual textual i end)))))))))

(define textual-trim-right
  (case-lambda
    ((textual)
     (textual-trim-right textual char-whitespace? 0 (textual-length textual)))
    ((textual pred)
     (textual-trim-right textual pred 0 (textual-length textual)))
    ((textual pred start)
     (textual-trim-right textual pred start (textual-length textual)))
    ((textual pred start end)
     (let ((len (textual-length textual)))
       (if (or (< start 0) (> start end) (> end len))
           (error "textual-trim-right: invalid range" start end len)
           (let loop ((i (- end 1)))
             (if (< i start)
                 %empty-text
                 (if (pred (textual-ref textual i))
                     (loop (- i 1))
                     (subtextual textual start (+ i 1))))))))))

(define textual-trim-both
  (case-lambda
    ((textual)
     (textual-trim-both textual char-whitespace? 0 (textual-length textual)))
    ((textual pred)
     (textual-trim-both textual pred 0 (textual-length textual)))
    ((textual pred start)
     (textual-trim-both textual pred start (textual-length textual)))
    ((textual pred start end)
     (let ((len (textual-length textual)))
       (if (or (< start 0) (> start end) (> end len))
           (error "textual-trim-both: invalid range" start end len)
           (let loop-l ((l start))
             (if (>= l end)
                 %empty-text
                 (if (pred (textual-ref textual l))
                     (loop-l (+ l 1))
                     (let loop-r ((r (- end 1)))
                       (if (< r l)
                           %empty-text
                           (if (pred (textual-ref textual r))
                               (loop-r (- r 1))
                               (subtextual textual l (+ r 1)))))))))))))

(define textual-replace
  (case-lambda
    ((textual1 start1 end1 textual2)
     (textual-replace textual1 start1 end1 textual2 0 (textual-length textual2)))
    ((textual1 start1 end1 textual2 start2)
     (textual-replace textual1 start1 end1 textual2 start2 (textual-length textual2)))
    ((textual1 start1 end1 textual2 start2 end2)
     (let ((len1 (textual-length textual1)))
       (if (or (< start1 0) (> start1 end1) (> end1 len1))
           (error "textual-replace: invalid range 1" start1 end1 len1)
           (textual-append (subtextual textual1 0 start1)
                           (subtextual textual2 start2 end2)
                           (subtextual textual1 end1 len1)))))))

;; ---------------------------------------------------------------------
;; §2.1 R7RS-large Red Edition / SRFI 135: Comparisons
;; ---------------------------------------------------------------------

(define (%textual-compare-2 t1 t2 ci?)
  (let ((len1 (textual-length t1))
        (len2 (textual-length t2)))
    (let ((min-len (min len1 len2)))
      (let loop ((i 0))
        (if (< i min-len)
            (let ((c1 (textual-ref t1 i))
                  (c2 (textual-ref t2 i)))
              (let ((diff (if ci?
                              (- (char->integer (char-foldcase c1))
                                 (char->integer (char-foldcase c2)))
                              (- (char->integer c1)
                                 (char->integer c2)))))
                (if (= diff 0)
                    (loop (+ i 1))
                    diff)))
            (- len1 len2))))))

(define textual=?
  (case-lambda
    ((t1 t2)
     (= (%textual-compare-2 t1 t2 #f) 0))
    ((t1 t2 t3)
     (and (= (%textual-compare-2 t1 t2 #f) 0)
          (= (%textual-compare-2 t2 t3 #f) 0)))
    ((t1 t2 t3 . rest)
     (and (= (%textual-compare-2 t1 t2 #f) 0)
          (= (%textual-compare-2 t2 t3 #f) 0)
          (let loop ((prev t3) (rs rest))
            (if (null? rs)
                #t
                (and (= (%textual-compare-2 prev (car rs) #f) 0)
                     (loop (car rs) (cdr rs)))))))))

(define textual<?
  (case-lambda
    ((t1 t2)
     (< (%textual-compare-2 t1 t2 #f) 0))
    ((t1 t2 t3)
     (and (< (%textual-compare-2 t1 t2 #f) 0)
          (< (%textual-compare-2 t2 t3 #f) 0)))
    ((t1 t2 t3 . rest)
     (and (< (%textual-compare-2 t1 t2 #f) 0)
          (< (%textual-compare-2 t2 t3 #f) 0)
          (let loop ((prev t3) (rs rest))
            (if (null? rs)
                #t
                (and (< (%textual-compare-2 prev (car rs) #f) 0)
                     (loop (car rs) (cdr rs)))))))))

(define textual>?
  (case-lambda
    ((t1 t2)
     (> (%textual-compare-2 t1 t2 #f) 0))
    ((t1 t2 t3)
     (and (> (%textual-compare-2 t1 t2 #f) 0)
          (> (%textual-compare-2 t2 t3 #f) 0)))
    ((t1 t2 t3 . rest)
     (and (> (%textual-compare-2 t1 t2 #f) 0)
          (> (%textual-compare-2 t2 t3 #f) 0)
          (let loop ((prev t3) (rs rest))
            (if (null? rs)
                #t
                (and (> (%textual-compare-2 prev (car rs) #f) 0)
                     (loop (car rs) (cdr rs)))))))))

(define textual<=?
  (case-lambda
    ((t1 t2)
     (<= (%textual-compare-2 t1 t2 #f) 0))
    ((t1 t2 t3)
     (and (<= (%textual-compare-2 t1 t2 #f) 0)
          (<= (%textual-compare-2 t2 t3 #f) 0)))
    ((t1 t2 t3 . rest)
     (and (<= (%textual-compare-2 t1 t2 #f) 0)
          (<= (%textual-compare-2 t2 t3 #f) 0)
          (let loop ((prev t3) (rs rest))
            (if (null? rs)
                #t
                (and (<= (%textual-compare-2 prev (car rs) #f) 0)
                     (loop (car rs) (cdr rs)))))))))

(define textual>=?
  (case-lambda
    ((t1 t2)
     (>= (%textual-compare-2 t1 t2 #f) 0))
    ((t1 t2 t3)
     (and (>= (%textual-compare-2 t1 t2 #f) 0)
          (>= (%textual-compare-2 t2 t3 #f) 0)))
    ((t1 t2 t3 . rest)
     (and (>= (%textual-compare-2 t1 t2 #f) 0)
          (>= (%textual-compare-2 t2 t3 #f) 0)
          (let loop ((prev t3) (rs rest))
            (if (null? rs)
                #t
                (and (>= (%textual-compare-2 prev (car rs) #f) 0)
                     (loop (car rs) (cdr rs)))))))))

(define textual-ci=?
  (case-lambda
    ((t1 t2)
     (= (%textual-compare-2 t1 t2 #t) 0))
    ((t1 t2 t3)
     (and (= (%textual-compare-2 t1 t2 #t) 0)
          (= (%textual-compare-2 t2 t3 #t) 0)))
    ((t1 t2 t3 . rest)
     (and (= (%textual-compare-2 t1 t2 #t) 0)
          (= (%textual-compare-2 t2 t3 #t) 0)
          (let loop ((prev t3) (rs rest))
            (if (null? rs)
                #t
                (and (= (%textual-compare-2 prev (car rs) #t) 0)
                     (loop (car rs) (cdr rs)))))))))

(define textual-ci<?
  (case-lambda
    ((t1 t2)
     (< (%textual-compare-2 t1 t2 #t) 0))
    ((t1 t2 t3)
     (and (< (%textual-compare-2 t1 t2 #t) 0)
          (< (%textual-compare-2 t2 t3 #t) 0)))
    ((t1 t2 t3 . rest)
     (and (< (%textual-compare-2 t1 t2 #t) 0)
          (< (%textual-compare-2 t2 t3 #t) 0)
          (let loop ((prev t3) (rs rest))
            (if (null? rs)
                #t
                (and (< (%textual-compare-2 prev (car rs) #t) 0)
                     (loop (car rs) (cdr rs)))))))))

(define textual-ci>?
  (case-lambda
    ((t1 t2)
     (> (%textual-compare-2 t1 t2 #t) 0))
    ((t1 t2 t3)
     (and (> (%textual-compare-2 t1 t2 #t) 0)
          (> (%textual-compare-2 t2 t3 #t) 0)))
    ((t1 t2 t3 . rest)
     (and (> (%textual-compare-2 t1 t2 #t) 0)
          (> (%textual-compare-2 t2 t3 #t) 0)
          (let loop ((prev t3) (rs rest))
            (if (null? rs)
                #t
                (and (> (%textual-compare-2 prev (car rs) #t) 0)
                     (loop (car rs) (cdr rs)))))))))

(define textual-ci<=?
  (case-lambda
    ((t1 t2)
     (<= (%textual-compare-2 t1 t2 #t) 0))
    ((t1 t2 t3)
     (and (<= (%textual-compare-2 t1 t2 #t) 0)
          (<= (%textual-compare-2 t2 t3 #t) 0)))
    ((t1 t2 t3 . rest)
     (and (<= (%textual-compare-2 t1 t2 #t) 0)
          (<= (%textual-compare-2 t2 t3 #t) 0)
          (let loop ((prev t3) (rs rest))
            (if (null? rs)
                #t
                (and (<= (%textual-compare-2 prev (car rs) #t) 0)
                     (loop (car rs) (cdr rs)))))))))

(define textual-ci>=?
  (case-lambda
    ((t1 t2)
     (>= (%textual-compare-2 t1 t2 #t) 0))
    ((t1 t2 t3)
     (and (>= (%textual-compare-2 t1 t2 #t) 0)
          (>= (%textual-compare-2 t2 t3 #t) 0)))
    ((t1 t2 t3 . rest)
     (and (>= (%textual-compare-2 t1 t2 #t) 0)
          (>= (%textual-compare-2 t2 t3 #t) 0)
          (let loop ((prev t3) (rs rest))
            (if (null? rs)
                #t
                (and (>= (%textual-compare-2 prev (car rs) #t) 0)
                     (loop (car rs) (cdr rs)))))))))

;; ---------------------------------------------------------------------
;; §2.1 R7RS-large Red Edition / SRFI 135: Prefixes & Suffixes
;; ---------------------------------------------------------------------

(define textual-prefix-length
  (case-lambda
    ((t1 t2)
     (textual-prefix-length t1 t2 0 (textual-length t1) 0 (textual-length t2)))
    ((t1 t2 start1)
     (textual-prefix-length t1 t2 start1 (textual-length t1) 0 (textual-length t2)))
    ((t1 t2 start1 end1)
     (textual-prefix-length t1 t2 start1 end1 0 (textual-length t2)))
    ((t1 t2 start1 end1 start2)
     (textual-prefix-length t1 t2 start1 end1 start2 (textual-length t2)))
    ((t1 t2 start1 end1 start2 end2)
     (let ((max-n (min (- end1 start1) (- end2 start2))))
       (let loop ((i 0))
         (if (< i max-n)
             (if (char=? (textual-ref t1 (+ start1 i))
                         (textual-ref t2 (+ start2 i)))
                 (loop (+ i 1))
                 i)
             max-n))))))

(define textual-suffix-length
  (case-lambda
    ((t1 t2)
     (textual-suffix-length t1 t2 0 (textual-length t1) 0 (textual-length t2)))
    ((t1 t2 start1)
     (textual-suffix-length t1 t2 start1 (textual-length t1) 0 (textual-length t2)))
    ((t1 t2 start1 end1)
     (textual-suffix-length t1 t2 start1 end1 0 (textual-length t2)))
    ((t1 t2 start1 end1 start2)
     (textual-suffix-length t1 t2 start1 end1 start2 (textual-length t2)))
    ((t1 t2 start1 end1 start2 end2)
     (let ((max-n (min (- end1 start1) (- end2 start2))))
       (let loop ((i 0))
         (if (< i max-n)
             (if (char=? (textual-ref t1 (- (- end1 1) i))
                         (textual-ref t2 (- (- end2 1) i)))
                 (loop (+ i 1))
                 i)
             max-n))))))

(define textual-prefix?
  (case-lambda
    ((t1 t2)
     (textual-prefix? t1 t2 0 (textual-length t1) 0 (textual-length t2)))
    ((t1 t2 start1)
     (textual-prefix? t1 t2 start1 (textual-length t1) 0 (textual-length t2)))
    ((t1 t2 start1 end1)
     (textual-prefix? t1 t2 start1 end1 0 (textual-length t2)))
    ((t1 t2 start1 end1 start2)
     (textual-prefix? t1 t2 start1 end1 start2 (textual-length t2)))
    ((t1 t2 start1 end1 start2 end2)
     (= (textual-prefix-length t1 t2 start1 end1 start2 end2)
        (- end1 start1)))))

(define textual-suffix?
  (case-lambda
    ((t1 t2)
     (textual-suffix? t1 t2 0 (textual-length t1) 0 (textual-length t2)))
    ((t1 t2 start1)
     (textual-suffix? t1 t2 start1 (textual-length t1) 0 (textual-length t2)))
    ((t1 t2 start1 end1)
     (textual-suffix? t1 t2 start1 end1 0 (textual-length t2)))
    ((t1 t2 start1 end1 start2)
     (textual-suffix? t1 t2 start1 end1 start2 (textual-length t2)))
    ((t1 t2 start1 end1 start2 end2)
     (= (textual-suffix-length t1 t2 start1 end1 start2 end2)
        (- end1 start1)))))

;; ---------------------------------------------------------------------
;; §2.1 R7RS-large Red Edition / SRFI 135: Searching
;; ---------------------------------------------------------------------

(define textual-index
  (case-lambda
    ((pred textual)
     (textual-index pred textual 0 (textual-length textual)))
    ((pred textual start)
     (textual-index pred textual start (textual-length textual)))
    ((pred textual start end)
     (let ((len (textual-length textual)))
       (if (or (< start 0) (> start end) (> end len))
           (error "textual-index: invalid range" start end len)
           (let loop ((i start))
             (if (< i end)
                 (if (pred (textual-ref textual i))
                     i
                     (loop (+ i 1)))
                 #f)))))))

(define textual-index-right
  (case-lambda
    ((pred textual)
     (textual-index-right pred textual 0 (textual-length textual)))
    ((pred textual start)
     (textual-index-right pred textual start (textual-length textual)))
    ((pred textual start end)
     (let ((len (textual-length textual)))
       (if (or (< start 0) (> start end) (> end len))
           (error "textual-index-right: invalid range" start end len)
           (let loop ((i (- end 1)))
             (if (>= i start)
                 (if (pred (textual-ref textual i))
                     i
                     (loop (- i 1)))
                 #f)))))))

(define textual-skip
  (case-lambda
    ((pred textual)
     (textual-skip pred textual 0 (textual-length textual)))
    ((pred textual start)
     (textual-skip pred textual start (textual-length textual)))
    ((pred textual start end)
     (textual-index (lambda (c) (not (pred c))) textual start end))))

(define textual-skip-right
  (case-lambda
    ((pred textual)
     (textual-skip-right pred textual 0 (textual-length textual)))
    ((pred textual start)
     (textual-skip-right pred textual start (textual-length textual)))
    ((pred textual start end)
     (textual-index-right (lambda (c) (not (pred c))) textual start end))))

(define textual-contains
  (case-lambda
    ((t1 t2)
     (textual-contains t1 t2 0 (textual-length t1) 0 (textual-length t2)))
    ((t1 t2 start1)
     (textual-contains t1 t2 start1 (textual-length t1) 0 (textual-length t2)))
    ((t1 t2 start1 end1)
     (textual-contains t1 t2 start1 end1 0 (textual-length t2)))
    ((t1 t2 start1 end1 start2)
     (textual-contains t1 t2 start1 end1 start2 (textual-length t2)))
    ((t1 t2 start1 end1 start2 end2)
     (let* ((len1 (- end1 start1))
            (len2 (- end2 start2)))
       (cond
         ((= len2 0) start1)
         ((< len1 len2) #f)
         (else
          (let ((limit (+ (- end1 len2) 1)))
            (let loop ((i start1))
              (if (< i limit)
                  (let loop-match ((j 0))
                    (if (< j len2)
                        (if (char=? (textual-ref t1 (+ i j))
                                    (textual-ref t2 (+ start2 j)))
                            (loop-match (+ j 1))
                            (loop (+ i 1)))
                        i))
                  #f)))))))))

(define textual-contains-right
  (case-lambda
    ((t1 t2)
     (textual-contains-right t1 t2 0 (textual-length t1) 0 (textual-length t2)))
    ((t1 t2 start1)
     (textual-contains-right t1 t2 start1 (textual-length t1) 0 (textual-length t2)))
    ((t1 t2 start1 end1)
     (textual-contains-right t1 t2 start1 end1 0 (textual-length t2)))
    ((t1 t2 start1 end1 start2)
     (textual-contains-right t1 t2 start1 end1 start2 (textual-length t2)))
    ((t1 t2 start1 end1 start2 end2)
     (let* ((len1 (- end1 start1))
            (len2 (- end2 start2)))
       (cond
         ((= len2 0) end1)
         ((< len1 len2) #f)
         (else
          (let loop ((i (- end1 len2)))
            (if (>= i start1)
                (let loop-match ((j 0))
                  (if (< j len2)
                      (if (char=? (textual-ref t1 (+ i j))
                                  (textual-ref t2 (+ start2 j)))
                          (loop-match (+ j 1))
                          (loop (- i 1)))
                      i))
                #f))))))))

;; ---------------------------------------------------------------------
;; §2.1 R7RS-large Red Edition / SRFI 135: Case Conversion
;; ---------------------------------------------------------------------

(define (textual-upcase textual)
  (let* ((len (textual-length textual))
         (str (make-string len)))
    (let loop ((i 0))
      (if (< i len)
          (begin
            (string-set! str i (char-upcase (textual-ref textual i)))
            (loop (+ i 1)))
          (%make-text-leaf str)))))

(define (textual-downcase textual)
  (let* ((len (textual-length textual))
         (str (make-string len)))
    (let loop ((i 0))
      (if (< i len)
          (begin
            (string-set! str i (char-downcase (textual-ref textual i)))
            (loop (+ i 1)))
          (%make-text-leaf str)))))

(define (textual-foldcase textual)
  (let* ((len (textual-length textual))
         (str (make-string len)))
    (let loop ((i 0))
      (if (< i len)
          (begin
            (string-set! str i (char-foldcase (textual-ref textual i)))
            (loop (+ i 1)))
          (%make-text-leaf str)))))

(define (textual-titlecase textual)
  (let* ((len (textual-length textual))
         (str (make-string len)))
    (let loop ((i 0) (in-word? #f))
      (if (< i len)
          (let ((c (textual-ref textual i)))
            (if (char-whitespace? c)
                (begin
                  (string-set! str i c)
                  (loop (+ i 1) #f))
                (begin
                  (string-set! str i (if in-word? (char-downcase c) (char-upcase c)))
                  (loop (+ i 1) #t))))
          (%make-text-leaf str)))))

;; ---------------------------------------------------------------------
;; §2.1 R7RS-large Red Edition / SRFI 135: Iteration, Mapping & Folding
;; ---------------------------------------------------------------------

(define textual-every
  (case-lambda
    ((pred textual)
     (textual-every pred textual 0 (textual-length textual)))
    ((pred textual start)
     (textual-every pred textual start (textual-length textual)))
    ((pred textual start end)
     (let ((len (textual-length textual)))
       (if (or (< start 0) (> start end) (> end len))
           (error "textual-every: invalid range" start end len)
           (if (= start end)
               #t
               (let loop ((i start) (last-val #t))
                 (if (< i end)
                     (let ((val (pred (textual-ref textual i))))
                       (if val
                           (loop (+ i 1) val)
                           #f))
                     last-val))))))))

(define textual-any
  (case-lambda
    ((pred textual)
     (textual-any pred textual 0 (textual-length textual)))
    ((pred textual start)
     (textual-any pred textual start (textual-length textual)))
    ((pred textual start end)
     (let ((len (textual-length textual)))
       (if (or (< start 0) (> start end) (> end len))
           (error "textual-any: invalid range" start end len)
           (if (= start end)
               #f
               (let loop ((i start))
                 (if (< i end)
                     (let ((val (pred (textual-ref textual i))))
                       (if val
                           val
                           (loop (+ i 1))))
                     #f))))))))

(define textual-fold
  (case-lambda
    ((kons knil textual)
     (textual-fold kons knil textual 0 (textual-length textual)))
    ((kons knil textual start)
     (textual-fold kons knil textual start (textual-length textual)))
    ((kons knil textual start end)
     (let ((len (textual-length textual)))
       (if (or (< start 0) (> start end) (> end len))
           (error "textual-fold: invalid range" start end len)
           (let loop ((i start) (acc knil))
             (if (< i end)
                 (loop (+ i 1) (kons (textual-ref textual i) acc))
                 acc)))))))

(define textual-fold-right
  (case-lambda
    ((kons knil textual)
     (textual-fold-right kons knil textual 0 (textual-length textual)))
    ((kons knil textual start)
     (textual-fold-right kons knil textual start (textual-length textual)))
    ((kons knil textual start end)
     (let ((len (textual-length textual)))
       (if (or (< start 0) (> start end) (> end len))
           (error "textual-fold-right: invalid range" start end len)
           (let loop ((i (- end 1)) (acc knil))
             (if (>= i start)
                 (loop (- i 1) (kons (textual-ref textual i) acc))
                 acc)))))))

(define textual-map
  (case-lambda
    ((proc t1)
     (let* ((len (textual-length t1))
            (str (make-string len)))
       (let loop ((i 0))
         (if (< i len)
             (let ((res (proc (textual-ref t1 i))))
               (cond
                 ((char? res)
                  (string-set! str i res)
                  (loop (+ i 1)))
                 (else
                  (let gen-loop ((j 0) (acc '()))
                    (if (< j len)
                        (let ((v (proc (textual-ref t1 j))))
                          (cond
                            ((char? v) (gen-loop (+ j 1) (cons (text v) acc)))
                            ((string? v) (gen-loop (+ j 1) (cons (string->text v) acc)))
                            ((text? v) (gen-loop (+ j 1) (cons v acc)))
                            (else (error "textual-map: invalid return value" v))))
                        (textual-concatenate (reverse acc)))))))
             (%make-text-leaf str)))))
    ((proc t1 t2)
     (let* ((len1 (textual-length t1))
            (len2 (textual-length t2))
            (min-len (min len1 len2)))
       (let loop ((i 0) (acc '()))
         (if (< i min-len)
             (let ((res (proc (textual-ref t1 i) (textual-ref t2 i))))
               (cond
                 ((char? res) (loop (+ i 1) (cons (text res) acc)))
                 ((string? res) (loop (+ i 1) (cons (string->text res) acc)))
                 ((text? res) (loop (+ i 1) (cons res acc)))
                 (else (error "textual-map: invalid return value" res))))
             (textual-concatenate (reverse acc))))))
    ((proc t1 t2 . rest)
     (let* ((all (cons t1 (cons t2 rest)))
            (lens (map textual-length all))
            (min-len (apply min lens)))
       (let loop ((i 0) (acc '()))
         (if (< i min-len)
             (let* ((args (map (lambda (t) (textual-ref t i)) all))
                    (res (apply proc args)))
               (cond
                 ((char? res) (loop (+ i 1) (cons (text res) acc)))
                 ((string? res) (loop (+ i 1) (cons (string->text res) acc)))
                 ((text? res) (loop (+ i 1) (cons res acc)))
                 (else (error "textual-map: invalid return value" res))))
             (textual-concatenate (reverse acc))))))))

(define textual-for-each
  (case-lambda
    ((proc t1)
     (let ((len (textual-length t1)))
       (let loop ((i 0))
         (if (< i len)
             (begin
               (proc (textual-ref t1 i))
               (loop (+ i 1)))))))
    ((proc t1 t2)
     (let* ((len1 (textual-length t1))
            (len2 (textual-length t2))
            (min-len (min len1 len2)))
       (let loop ((i 0))
         (if (< i min-len)
             (begin
               (proc (textual-ref t1 i) (textual-ref t2 i))
               (loop (+ i 1)))))))
    ((proc t1 t2 . rest)
     (let* ((all (cons t1 (cons t2 rest)))
            (lens (map textual-length all))
            (min-len (apply min lens)))
       (let loop ((i 0))
         (if (< i min-len)
             (let ((args (map (lambda (t) (textual-ref t i)) all)))
               (apply proc args)
               (loop (+ i 1)))))))))

(define textual-map-index
  (case-lambda
    ((proc textual)
     (textual-map-index proc textual 0 (textual-length textual)))
    ((proc textual start)
     (textual-map-index proc textual start (textual-length textual)))
    ((proc textual start end)
     (let ((len (textual-length textual)))
       (if (or (< start 0) (> start end) (> end len))
           (error "textual-map-index: invalid range" start end len)
           (let loop ((i start) (acc '()))
             (if (< i end)
                 (let ((res (proc i)))
                   (cond
                     ((char? res)
                      (loop (+ i 1) (cons (text res) acc)))
                     ((string? res)
                      (loop (+ i 1) (cons (string->text res) acc)))
                     ((text? res)
                      (loop (+ i 1) (cons res acc)))
                     (else
                      (error "textual-map-index: procedure returned invalid value" res))))
                 (textual-concatenate (reverse acc)))))))))

(define textual-for-each-index
  (case-lambda
    ((proc textual)
     (textual-for-each-index proc textual 0 (textual-length textual)))
    ((proc textual start)
     (textual-for-each-index proc textual start (textual-length textual)))
    ((proc textual start end)
     (let ((len (textual-length textual)))
       (if (or (< start 0) (> start end) (> end len))
           (error "textual-for-each-index: invalid range" start end len)
           (let loop ((i start))
             (if (< i end)
                 (begin
                   (proc i)
                   (loop (+ i 1))))))))))

(define textual-count
  (case-lambda
    ((pred textual)
     (textual-count pred textual 0 (textual-length textual)))
    ((pred textual start)
     (textual-count pred textual start (textual-length textual)))
    ((pred textual start end)
     (let ((len (textual-length textual)))
       (if (or (< start 0) (> start end) (> end len))
           (error "textual-count: invalid range" start end len)
           (let loop ((i start) (cnt 0))
             (if (< i end)
                 (loop (+ i 1) (if (pred (textual-ref textual i)) (+ cnt 1) cnt))
                 cnt)))))))

(define textual-filter
  (case-lambda
    ((pred textual)
     (textual-filter pred textual 0 (textual-length textual)))
    ((pred textual start)
     (textual-filter pred textual start (textual-length textual)))
    ((pred textual start end)
     (let ((len (textual-length textual)))
       (if (or (< start 0) (> start end) (> end len))
           (error "textual-filter: invalid range" start end len)
           (let loop ((i (- end 1)) (acc '()))
             (if (>= i start)
                 (let ((c (textual-ref textual i)))
                   (loop (- i 1) (if (pred c) (cons c acc) acc)))
                 (list->text acc))))))))

(define textual-remove
  (case-lambda
    ((pred textual)
     (textual-remove pred textual 0 (textual-length textual)))
    ((pred textual start)
     (textual-remove pred textual start (textual-length textual)))
    ((pred textual start end)
     (textual-filter (lambda (c) (not (pred c))) textual start end))))

;; ---------------------------------------------------------------------
;; §2.1 R7RS-large Red Edition / SRFI 135: Replication & Splitting
;; ---------------------------------------------------------------------

(define textual-replicate
  (case-lambda
    ((textual from to)
     (textual-replicate textual from to 0 (textual-length textual)))
    ((textual from to start)
     (textual-replicate textual from to start (textual-length textual)))
    ((textual from to start end)
     (if (or (not (integer? from)) (not (integer? to)) (< to from))
         (error "textual-replicate: invalid from/to" from to)
         (let ((src-len (- end start)))
           (cond
             ((= from to) %empty-text)
             ((= src-len 0)
              (error "textual-replicate: empty source with non-empty target range"))
             (else
              (let* ((count (- to from))
                     (str (make-string count)))
                (let loop ((i 0) (k from))
                  (if (< i count)
                      (let* ((mod-idx (modulo k src-len))
                             (c (textual-ref textual (+ start mod-idx))))
                        (string-set! str i c)
                        (loop (+ i 1) (+ k 1)))
                      (%make-text-leaf str)))))))))))

(define textual-split
  (case-lambda
    ((textual delimiter)
     (textual-split textual delimiter 'infix #f 0 (textual-length textual)))
    ((textual delimiter grammar)
     (textual-split textual delimiter grammar #f 0 (textual-length textual)))
    ((textual delimiter grammar limit)
     (textual-split textual delimiter grammar limit 0 (textual-length textual)))
    ((textual delimiter grammar limit start)
     (textual-split textual delimiter grammar limit start (textual-length textual)))
    ((textual delimiter grammar limit start end)
     (let* ((delim-match?
             (cond
               ((char? delimiter)
                (lambda (t idx)
                  (if (< idx end)
                      (if (char=? (textual-ref t idx) delimiter) 1 #f)
                      #f)))
               ((procedure? delimiter)
                (lambda (t idx)
                  (if (< idx end)
                      (if (delimiter (textual-ref t idx)) 1 #f)
                      #f)))
               ((textual? delimiter)
                (let ((dlen (textual-length delimiter)))
                  (if (= dlen 0)
                      (error "textual-split: empty delimiter")
                      (lambda (t idx)
                        (if (<= (+ idx dlen) end)
                            (let loop-chk ((j 0))
                              (if (< j dlen)
                                  (if (char=? (textual-ref t (+ idx j))
                                              (textual-ref delimiter j))
                                      (loop-chk (+ j 1))
                                      #f)
                                  dlen))
                            #f)))))
               (else
                (error "textual-split: invalid delimiter" delimiter)))))
       (let loop ((idx start) (cur-start start) (count 0) (acc '()))
         (if (>= idx end)
             (let ((final-acc (cons (subtextual textual cur-start end) acc)))
               (reverse final-acc))
             (if (and limit (> limit 0) (= count (- limit 1)))
                 (let ((final-acc (cons (subtextual textual cur-start end) acc)))
                   (reverse final-acc))
                 (let ((match-len (delim-match? textual idx)))
                   (if match-len
                       (loop (+ idx match-len)
                             (+ idx match-len)
                             (+ count 1)
                             (cons (subtextual textual cur-start idx) acc))
                       (loop (+ idx 1) cur-start count acc))))))))))

;; ---------------------------------------------------------------------
;; §2.1 R7RS-large Red Edition / SRFI 135: UTF-8 and UTF-16 Encoders & Decoders
;; ---------------------------------------------------------------------

(define textual->utf8
  (case-lambda
    ((textual)
     (textual->utf8 textual 0 (textual-length textual)))
    ((textual start)
     (textual->utf8 textual start (textual-length textual)))
    ((textual start end)
     (let ((len (textual-length textual)))
       (if (or (< start 0) (> start end) (> end len))
           (error "textual->utf8: invalid range" start end len)
           (let loop-len ((i start) (byte-count 0))
             (if (< i end)
                 (let ((c (char->integer (textual-ref textual i))))
                   (cond
                     ((< c 128) (loop-len (+ i 1) (+ byte-count 1)))
                     ((< c 2048) (loop-len (+ i 1) (+ byte-count 2)))
                     ((< c 65536) (loop-len (+ i 1) (+ byte-count 3)))
                     (else (loop-len (+ i 1) (+ byte-count 4)))))
                 (let ((bv (%make-bytevector byte-count)))
                   (let loop-enc ((i start) (pos 0))
                     (if (< i end)
                         (let ((c (char->integer (textual-ref textual i))))
                           (cond
                             ((< c 128)
                              (bytevector-u8-set! bv pos c)
                              (loop-enc (+ i 1) (+ pos 1)))
                             ((< c 2048)
                              (bytevector-u8-set! bv pos (+ 192 (quotient c 64)))
                              (bytevector-u8-set! bv (+ pos 1) (+ 128 (bitwise-and c 63)))
                              (loop-enc (+ i 1) (+ pos 2)))
                             ((< c 65536)
                              (bytevector-u8-set! bv pos (+ 224 (quotient c 4096)))
                              (bytevector-u8-set! bv (+ pos 1) (+ 128 (bitwise-and (quotient c 64) 63)))
                              (bytevector-u8-set! bv (+ pos 2) (+ 128 (bitwise-and c 63)))
                              (loop-enc (+ i 1) (+ pos 3)))
                             (else
                              (bytevector-u8-set! bv pos (+ 240 (quotient c 262144)))
                              (bytevector-u8-set! bv (+ pos 1) (+ 128 (bitwise-and (quotient c 4096) 63)))
                              (bytevector-u8-set! bv (+ pos 2) (+ 128 (bitwise-and (quotient c 64) 63)))
                              (bytevector-u8-set! bv (+ pos 3) (+ 128 (bitwise-and c 63)))
                              (loop-enc (+ i 1) (+ pos 4)))))
                         bv))))))))))

(define utf8->text
  (case-lambda
    ((bv)
     (utf8->text bv 0 (bytevector-length bv)))
    ((bv start)
     (utf8->text bv start (bytevector-length bv)))
    ((bv start end)
     (let ((bv-len (bytevector-length bv)))
       (if (or (< start 0) (> start end) (> end bv-len))
           (error "utf8->text: invalid range" start end bv-len)
           (let loop ((i start) (chars '()))
             (if (>= i end)
                 (list->text (reverse chars))
                 (let ((b0 (bytevector-u8-ref bv i)))
                   (cond
                     ((< b0 128)
                      (loop (+ i 1) (cons (integer->char b0) chars)))
                     ((< b0 224)
                      (if (>= (+ i 1) end)
                          (error "utf8->text: truncated UTF-8 sequence" i)
                          (let* ((b1 (bytevector-u8-ref bv (+ i 1)))
                                 (code (+ (* (bitwise-and b0 31) 64)
                                          (bitwise-and b1 63))))
                            (loop (+ i 2) (cons (integer->char code) chars)))))
                     ((< b0 240)
                      (if (>= (+ i 2) end)
                          (error "utf8->text: truncated UTF-8 sequence" i)
                          (let* ((b1 (bytevector-u8-ref bv (+ i 1)))
                                 (b2 (bytevector-u8-ref bv (+ i 2)))
                                 (code (+ (* (bitwise-and b0 15) 4096)
                                          (* (bitwise-and b1 63) 64)
                                          (bitwise-and b2 63))))
                            (loop (+ i 3) (cons (integer->char code) chars)))))
                     (else
                      (if (>= (+ i 3) end)
                          (error "utf8->text: truncated UTF-8 sequence" i)
                          (let* ((b1 (bytevector-u8-ref bv (+ i 1)))
                                 (b2 (bytevector-u8-ref bv (+ i 2)))
                                 (b3 (bytevector-u8-ref bv (+ i 3)))
                                 (code (+ (* (bitwise-and b0 7) 262144)
                                          (* (bitwise-and b1 63) 4096)
                                          (* (bitwise-and b2 63) 64)
                                          (bitwise-and b3 63))))
                            (loop (+ i 4) (cons (integer->char code) chars))))))))))))))

(define (%textual->utf16-helper textual start end big-endian?)
  (let ((len (textual-length textual)))
    (if (or (< start 0) (> start end) (> end len))
        (error "%textual->utf16: invalid range" start end len)
        (let loop-len ((i start) (unit-count 0))
          (if (< i end)
              (let ((c (char->integer (textual-ref textual i))))
                (if (< c 65536)
                    (loop-len (+ i 1) (+ unit-count 1))
                    (loop-len (+ i 1) (+ unit-count 2))))
              (let ((bv (%make-bytevector (* unit-count 2))))
                (let loop-enc ((i start) (pos 0))
                  (if (< i end)
                      (let ((c (char->integer (textual-ref textual i))))
                        (if (< c 65536)
                            (begin
                              (if big-endian?
                                  (begin
                                    (bytevector-u8-set! bv pos (quotient c 256))
                                    (bytevector-u8-set! bv (+ pos 1) (bitwise-and c 255)))
                                  (begin
                                    (bytevector-u8-set! bv pos (bitwise-and c 255))
                                    (bytevector-u8-set! bv (+ pos 1) (quotient c 256))))
                              (loop-enc (+ i 1) (+ pos 2)))
                            (let* ((u (- c 65536))
                                   (hi (+ 55296 (quotient u 1024)))
                                   (lo (+ 56320 (bitwise-and u 1023))))
                              (if big-endian?
                                  (begin
                                    (bytevector-u8-set! bv pos (quotient hi 256))
                                    (bytevector-u8-set! bv (+ pos 1) (bitwise-and hi 255))
                                    (bytevector-u8-set! bv (+ pos 2) (quotient lo 256))
                                    (bytevector-u8-set! bv (+ pos 3) (bitwise-and lo 255)))
                                  (begin
                                    (bytevector-u8-set! bv pos (bitwise-and hi 255))
                                    (bytevector-u8-set! bv (+ pos 1) (quotient hi 256))
                                    (bytevector-u8-set! bv (+ pos 2) (bitwise-and lo 255))
                                    (bytevector-u8-set! bv (+ pos 3) (quotient lo 256))))
                              (loop-enc (+ i 1) (+ pos 4)))))
                      bv))))))))

(define textual->utf16be
  (case-lambda
    ((textual) (textual->utf16be textual 0 (textual-length textual)))
    ((textual start) (textual->utf16be textual start (textual-length textual)))
    ((textual start end) (%textual->utf16-helper textual start end #t))))

(define textual->utf16le
  (case-lambda
    ((textual) (textual->utf16le textual 0 (textual-length textual)))
    ((textual start) (textual->utf16le textual start (textual-length textual)))
    ((textual start end) (%textual->utf16-helper textual start end #f))))

(define textual->utf16
  (case-lambda
    ((textual) (textual->utf16be textual))
    ((textual start) (textual->utf16be textual start))
    ((textual start end) (textual->utf16be textual start end))))

(define (%utf16->text-helper bv start end big-endian?)
  (let ((bv-len (bytevector-length bv)))
    (if (or (< start 0) (> start end) (> end bv-len))
        (error "%utf16->text: invalid range" start end bv-len)
        (let loop ((i start) (chars '()))
          (if (>= i end)
              (list->text (reverse chars))
              (if (> (+ i 2) end)
                  (error "%utf16->text: truncated UTF-16 sequence" i)
                  (let* ((b0 (bytevector-u8-ref bv i))
                         (b1 (bytevector-u8-ref bv (+ i 1)))
                         (w (if big-endian?
                                (+ (* b0 256) b1)
                                (+ (* b1 256) b0))))
                    (if (and (>= w 55296) (<= w 56319))
                        ;; High surrogate
                        (if (> (+ i 4) end)
                            (error "%utf16->text: truncated surrogate pair" i)
                            (let* ((b2 (bytevector-u8-ref bv (+ i 2)))
                                   (b3 (bytevector-u8-ref bv (+ i 3)))
                                   (w2 (if big-endian?
                                           (+ (* b2 256) b3)
                                           (+ (* b3 256) b2))))
                              (if (and (>= w2 56320) (<= w2 57343))
                                  (let ((code (+ 65536
                                                 (* (- w 55296) 1024)
                                                 (- w2 56320))))
                                    (loop (+ i 4) (cons (integer->char code) chars)))
                                  (error "%utf16->text: invalid low surrogate" w2))))
                        (loop (+ i 2) (cons (integer->char w) chars))))))))))

(define utf16be->text
  (case-lambda
    ((bv) (utf16be->text bv 0 (bytevector-length bv)))
    ((bv start) (utf16be->text bv start (bytevector-length bv)))
    ((bv start end) (%utf16->text-helper bv start end #t))))

(define utf16le->text
  (case-lambda
    ((bv) (utf16le->text bv 0 (bytevector-length bv)))
    ((bv start) (utf16le->text bv start (bytevector-length bv)))
    ((bv start end) (%utf16->text-helper bv start end #f))))

(define utf16->text
  (case-lambda
    ((bv) (utf16->text bv 0 (bytevector-length bv)))
    ((bv start) (utf16->text bv start (bytevector-length bv)))
    ((bv start end)
     (let ((count (- end start)))
       (if (>= count 2)
           (let ((b0 (bytevector-u8-ref bv start))
                 (b1 (bytevector-u8-ref bv (+ start 1))))
             (cond
               ((and (= b0 254) (= b1 255))
                ;; BOM Big-Endian
                (%utf16->text-helper bv (+ start 2) end #t))
               ((and (= b0 255) (= b1 254))
                ;; BOM Little-Endian
                (%utf16->text-helper bv (+ start 2) end #f))
               (else
                ;; Default to Big-Endian
                (%utf16->text-helper bv start end #t))))
           (%utf16->text-helper bv start end #t))))))
