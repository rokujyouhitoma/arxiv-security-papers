;;; =======================================================================
;;; ULisp Precompiled Standard Library Macros & Definitions
;;; Core syntax rules and definitions needed when compiling test targets
;;; separately and linking against build/ulisp_stdlib.o
;;; =======================================================================

;; --- Port / IO Macros ---
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

(define-syntax write-char
  (syntax-rules ()
    ((write-char c) (port-write-char c *stdout-port*))
    ((write-char c p) (port-write-char c p))))

(define-syntax write-u8
  (syntax-rules ()
    ((write-u8 byte) (port-write-u8 byte *stdout-port*))
    ((write-u8 byte p) (port-write-u8 byte p))))

(define-syntax write-string
  (syntax-rules ()
    ((write-string s) (port-write-string s *stdout-port*))
    ((write-string s p) (port-write-string s p))))

(define-syntax flush-output-port
  (syntax-rules ()
    ((flush-output-port) (port-flush-output *stdout-port*))
    ((flush-output-port p) (port-flush-output p))))

(define-syntax read
  (syntax-rules ()
    ((read) (port-read *stdin-port*))
    ((read p) (port-read p))))

(define-syntax read-char
  (syntax-rules ()
    ((read-char) (port-read-char *stdin-port*))
    ((read-char p) (port-read-char p))))

(define-syntax peek-char
  (syntax-rules ()
    ((peek-char) (port-peek-char *stdin-port*))
    ((peek-char p) (port-peek-char p))))

(define-syntax read-line
  (syntax-rules ()
    ((read-line) (port-read-line *stdin-port*))
    ((read-line p) (port-read-line p))))

(define-syntax read-u8
  (syntax-rules ()
    ((read-u8) (port-read-u8 *stdin-port*))
    ((read-u8 p) (port-read-u8 p))))

(define-syntax peek-u8
  (syntax-rules ()
    ((peek-u8) (port-peek-u8 *stdin-port*))
    ((peek-u8 p) (port-peek-u8 p))))

(define-syntax char-ready?
  (syntax-rules ()
    ((char-ready?) (port-char-ready? *stdin-port*))
    ((char-ready? p) (port-char-ready? p))))

(define-syntax u8-ready?
  (syntax-rules ()
    ((u8-ready?) (port-u8-ready? *stdin-port*))
    ((u8-ready? p) (port-u8-ready? p))))

(define-syntax string->number
  (syntax-rules ()
    ((string->number s) (string->number-core s 10 #f))
    ((string->number s r) (string->number-core s r #t))))

;; --- Equivalence Macros ---
(define-syntax eqv?
  (syntax-rules ()
    ((_ a b) (%eqv? a b))))

;; --- Numeric Tower Predicate Macros ---
(define-syntax number?
  (syntax-rules ()
    ((_ x) (%number? x))))

(define-syntax complex?
  (syntax-rules ()
    ((_ x) (%complex? x))))

(define-syntax real?
  (syntax-rules ()
    ((_ x) (%real? x))))

(define-syntax rational?
  (syntax-rules ()
    ((_ x) (%rational? x))))

(define-syntax integer?
  (syntax-rules ()
    ((_ x) (%integer? x))))

(define-syntax exact?
  (syntax-rules ()
    ((_ x) (%exact? x))))

(define-syntax inexact?
  (syntax-rules ()
    ((_ x) (%inexact? x))))

;; --- IEEE 754 Flonum Constants ---
(define +inf.0 (vector 'ulisp-flonum-tag 'pos-inf))
(define -inf.0 (vector 'ulisp-flonum-tag 'neg-inf))
(define +nan.0 (vector 'ulisp-flonum-tag 'nan))
(define -nan.0 +nan.0)

;; --- Pre-intern Desugared Compiler Symbols in Reader Table ---
(quote (make-vector-fill
        vector-copy-range
        vector-copy-range!
        make-bytevector-fill
        bytevector-copy-range
        bytevector-copy-range!
        string-copy-range
        string-copy-range!
        string-fill-range!
        error-object
        error))
