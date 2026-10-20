;;; =======================================================================
;;; ULisp Pure Scheme Runtime: printer.scm (Pre-Scheme Architecture)
;;; Conforms to DSN-33 Architecture Specification & Issue #580
;;;
;;; Low-level Scheme value formatter and recursive printer:
;;; print_scheme_value, print_pair_elements, raw tag discrimination
;;; =======================================================================

(define *fixnum-mask*     3)
(define *fixnum-tag*      0)
(define *fixnum-shift*    2)

(define *pair-mask*       7)
(define *pair-tag*        1)

(define *string-mask*     7)
(define *string-tag*      3)

(define *vector-mask*     7)
(define *vector-tag*      5)

(define *bytevector-mask* 7)
(define *bytevector-tag*  7)

(define *char-mask*       255)
(define *char-tag*        14)
(define *char-shift*      8)

(define *symbol-mask*     255)
(define *symbol-tag*      2)
(define *symbol-shift*    8)

(define *bool-false*      47) ; 0x2F
(define *bool-true*       111); 0x6F
(define *empty-list*      63) ; 0x3F
(define *eof-object*      79) ; 0x4F

(define (runtime-print-pair-elements p)
  (let loop ((curr p) (first? #t))
    (if (= (bitwise-and curr *pair-mask*) *pair-tag*)
        (let* ((ptr (%ptr-untag curr))
               (car-val (%raw-load ptr 0))
               (cdr-val (%raw-load ptr 8)))
          (if (not first?) (sys-write-char #\space))
          (runtime-print-value-raw car-val)
          (loop cdr-val #f))
        (if (not (= curr *empty-list*))
            (begin
              (sys-write-string " . ")
              (runtime-print-value-raw curr))))))

(define (runtime-print-value-raw val)
  (cond
    ;; Fixnum: (val & 3) == 0
    ((= (bitwise-and val *fixnum-mask*) *fixnum-tag*)
     (sys-write-fixnum (quotient val 4)))

    ;; Boolean False (#f)
    ((= val *bool-false*)
     (sys-write-string "#f"))

    ;; Boolean True (#t)
    ((= val *bool-true*)
     (sys-write-string "#t"))

    ;; Empty List ()
    ((= val *empty-list*)
     (sys-write-string "()"))

    ;; EOF Object
    ((= val *eof-object*)
     (sys-write-string "#<eof>"))

    ;; Character
    ((= (bitwise-and val *char-mask*) *char-tag*)
     (let ((c (bitwise-and (quotient val 256) 255)))
       (sys-write-string "#\\")
       (cond
         ((= c 10) (sys-write-string "newline"))
         ((= c 32) (sys-write-string "space"))
         ((= c 9)  (sys-write-string "tab"))
         (else     (sys-write-char (integer->char c))))))

    ;; Pair
    ((= (bitwise-and val *pair-mask*) *pair-tag*)
     (sys-write-char #\()
     (runtime-print-pair-elements val)
     (sys-write-char #\)))

    ;; String
    ((= (bitwise-and val *string-mask*) *string-tag*)
     (sys-write-char #\")
     (let* ((ptr (%ptr-untag val))
            (len (%to-fixnum (%raw-load ptr 0))))
       (let loop ((i 0))
         (if (< i len)
             (let ((b (bitwise-and (%to-fixnum (%raw-load (%ptr-add ptr 8) i)) 255)))
               (sys-write-char (integer->char b))
               (loop (+ i 1))))))
     (sys-write-char #\"))

    ;; Vector
    ((= (bitwise-and val *vector-mask*) *vector-tag*)
     (sys-write-string "#(")
     (let* ((ptr (%ptr-untag val))
            (len (quotient (%to-fixnum (%raw-load ptr 0)) 4)))
       (let loop ((i 0))
         (if (< i len)
             (begin
               (if (> i 0) (sys-write-char #\space))
               (runtime-print-value-raw (%raw-load (%ptr-add ptr 8) (* i 8)))
               (loop (+ i 1))))))
     (sys-write-char #\)))

    ;; Bytevector
    ((= (bitwise-and val *bytevector-mask*) *bytevector-tag*)
     (sys-write-string "#u8(")
     (let* ((ptr (%ptr-untag val))
            (len (quotient (%to-fixnum (%raw-load ptr 0)) 4)))
       (let loop ((i 0))
         (if (< i len)
             (begin
               (if (> i 0) (sys-write-char #\space))
               (sys-write-fixnum (bitwise-and (%to-fixnum (%raw-load (%ptr-add ptr 8) i)) 255))
               (loop (+ i 1))))))
     (sys-write-char #\)))

    ;; Symbol
    ((= (bitwise-and val *symbol-mask*) *symbol-tag*)
     (sys-write-string "#<symbol-")
     (sys-write-fixnum (quotient val 256))
     (sys-write-char #\>))

    ;; Unknown
    (else
     (sys-write-string "#<unknown: ")
     (sys-write-fixnum val)
     (sys-write-char #\>))))

(define (runtime-print-value val)
  (runtime-print-value-raw val)
  (sys-write-char #\newline)
  (sys-flush))
