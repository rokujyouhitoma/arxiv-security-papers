;;; =======================================================================
;;; ULisp Pure Scheme Runtime: io.scm (Pre-Scheme Architecture)
;;; Conforms to DSN-33 Architecture Specification & Issue #580
;;;
;;; Low-level direct POSIX / OS I/O primitives:
;;; ulisp_read_char, ulisp_peek_char, ulisp_write_char, ulisp_write_string, ulisp_flush
;;; =======================================================================

(define *runtime-peek-cell* (cons 0 (cons 0 '()))) ; [0]: has_peek, [1]: peek_byte
(define *runtime-io-buf* (cons 0 (cons 0 '())))    ; 16-byte raw buffer for single byte I/O

(define (runtime-peek-ptr)
  (%ptr-untag *runtime-peek-cell*))

(define (runtime-io-buf-ptr)
  (%ptr-untag *runtime-io-buf*))

(define (runtime-has-peek?)
  (not (= (%to-fixnum (%raw-load (runtime-peek-ptr) 0)) 0)))

(define (runtime-set-peek! byte-val)
  (%raw-store! (runtime-peek-ptr) 0 (%to-raw 1))
  (%raw-store! (runtime-peek-ptr) 8 (%to-raw byte-val)))

(define (runtime-clear-peek!)
  (%raw-store! (runtime-peek-ptr) 0 0))

(define (runtime-get-peek-byte)
  (%to-fixnum (%raw-load (runtime-peek-ptr) 8)))

;; ulisp_read_char: reads 1 character from stdin (fd 0)
;; Returns tagged Scheme character (c * 256) | 14, or 79 (EOF_OBJECT)
(define (runtime-read-char)
  (if (runtime-has-peek?)
      (let ((c (runtime-get-peek-byte)))
        (runtime-clear-peek!)
        (bitwise-ior (* c 256) 14))
      (let ((ret (sys-read 0 (runtime-io-buf-ptr) 1)))
        (if (<= ret 0)
            79 ; EOF_OBJECT (0x4F)
            (let ((c (bitwise-and (%to-fixnum (%raw-load (runtime-io-buf-ptr) 0)) 255)))
              (bitwise-ior (* c 256) 14))))))

;; ulisp_peek_char: looks ahead 1 character from stdin (fd 0) without consuming
;; Returns tagged Scheme character (c * 256) | 14, or 79 (EOF_OBJECT)
(define (runtime-peek-char)
  (if (runtime-has-peek?)
      (let ((c (runtime-get-peek-byte)))
        (bitwise-ior (* c 256) 14))
      (let ((ret (sys-read 0 (runtime-io-buf-ptr) 1)))
        (if (<= ret 0)
            79 ; EOF_OBJECT
            (let ((c (bitwise-and (%to-fixnum (%raw-load (runtime-io-buf-ptr) 0)) 255)))
              (runtime-set-peek! c)
              (bitwise-ior (* c 256) 14))))))

;; ulisp_write_char: writes 1 tagged Scheme character val to stdout (fd 1)
;; Returns 111 (#t)
(define (runtime-write-char val)
  (let ((c (bitwise-and (quotient val 256) 255)))
    (sys-write-char (integer->char c))
    111)) ; #t (0x6F)

;; ulisp_write_string: writes tagged Scheme string val to stdout (fd 1)
;; Returns 111 (#t)
(define (runtime-write-string val)
  (let ((str (if (string? val) val (%ptr-tag-add val 3))))
    (sys-write-string str)
    111))

;; ulisp_flush: flushes stdout buffer
;; Returns 111 (#t)
(define (runtime-flush)
  (sys-flush)
  111)
