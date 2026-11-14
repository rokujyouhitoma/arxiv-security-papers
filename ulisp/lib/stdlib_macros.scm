;;; =======================================================================
;;; ULisp Precompiled Standard Library Macros & Definitions
;;; Core syntax rules and definitions needed when compiling test targets
;;; separately and linking against build/ulisp_stdlib.o
;;; Conforms to R7RS Small (Section 6.1, 6.2, 6.13) & Issue #772
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

;;; -----------------------------------------------------------------------
;;; §6.13 Input and Output (Port / IO Macros)
;;; -----------------------------------------------------------------------
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

(define-syntax write-bytevector
  (syntax-rules ()
    ((write-bytevector bv)
     (let ((b bv))
       (port-write-bytevector-range b *stdout-port* 0 (bytevector-length b))))
    ((write-bytevector bv p)
     (let ((b bv))
       (port-write-bytevector-range b p 0 (bytevector-length b))))
    ((write-bytevector bv p start)
     (let ((b bv))
       (port-write-bytevector-range b p start (bytevector-length b))))
    ((write-bytevector bv p start end)
     (port-write-bytevector-range bv p start end))))

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

;;; -----------------------------------------------------------------------
;;; §6.2.6 Numerical Input and Output (string->number)
;;; -----------------------------------------------------------------------
(define-syntax string->number
  (syntax-rules ()
    ((string->number s) (string->number-core s 10 #f))
    ((string->number s r) (string->number-core s r #t))))

;;; -----------------------------------------------------------------------
;;; §6.1 Equivalence Predicates (eqv? Macro)
;;; -----------------------------------------------------------------------
(define-syntax eqv?
  (syntax-rules ()
    ((_ a b) (%eqv? a b))))

;;; -----------------------------------------------------------------------
;;; §6.2.5 Numerical Operations & Predicate Macros
;;; -----------------------------------------------------------------------
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

;;; -----------------------------------------------------------------------
;;; §6.2.5 IEEE 754 Flonum Constants
;;; -----------------------------------------------------------------------
(define +inf.0 (vector 'ulisp-flonum-tag 'pos-inf))
(define -inf.0 (vector 'ulisp-flonum-tag 'neg-inf))
(define +nan.0 (vector 'ulisp-flonum-tag 'nan))
(define -nan.0 +nan.0)

;;; -----------------------------------------------------------------------
;;; SRFI 64 Test Suite Macros (Issue #819, Issue #822)
;;; Enables test targets linked against ulisp_stdlib.o to use SRFI 64
;;; -----------------------------------------------------------------------
(define-syntax test-begin
  (syntax-rules ()
    ((test-begin suite-name)
     (%test-begin suite-name #f))
    ((test-begin suite-name count)
     (%test-begin suite-name count))))

(define-syntax test-end
  (syntax-rules ()
    ((test-end)
     (%test-end #f))
    ((test-end suite-name)
     (%test-end suite-name))))

(define-syntax %test-comp1body
  (syntax-rules ()
    ((%test-comp1body r expr)
     (let ()
       (if (%test-on-test-begin r)
           (let ()
             (test-result-set! r 'expected-value #t)
             (let ((res (guard (ex (else #f)) expr)))
               (test-result-set! r 'actual-value res)
               (%test-on-test-end r (if res #t #f)))))
       (%test-report-result)))))

(define-syntax %test-comp2body
  (syntax-rules ()
    ((%test-comp2body r comp expected expr)
     (let ()
       (if (%test-on-test-begin r)
           (let ((exp expected))
             (test-result-set! r 'expected-value exp)
             (let ((res (guard (ex (else (list 'unhandled-exception ex)))
                          expr)))
               (test-result-set! r 'actual-value res)
               (let ((compared (if (and (pair? res) (eq? (car res) 'unhandled-exception))
                                   #f
                                   (comp exp res))))
                 (%test-on-test-end r compared)))))
       (%test-report-result)))))

(define-syntax test-assert
  (syntax-rules ()
    ((test-assert tname test-expression)
     (let ((r (test-runner-get)))
       (test-result-alist! r (list (cons 'test-name tname)))
       (%test-comp1body r test-expression)))
    ((test-assert test-expression)
     (let ((r (test-runner-get)))
       (test-result-alist! r '())
       (%test-comp1body r test-expression)))))

(define-syntax %test-comp2
  (syntax-rules ()
    ((%test-comp2 comp tname expected expr)
     (let ((r (test-runner-get)))
       (test-result-alist! r (list (cons 'test-name tname)))
       (%test-comp2body r comp expected expr)))
    ((%test-comp2 comp expected expr)
     (let ((r (test-runner-get)))
       (test-result-alist! r '())
       (%test-comp2body r comp expected expr)))))

(define-syntax test-equal
  (syntax-rules ()
    ((test-equal . rest)
     (%test-comp2 equal? . rest))))

(define-syntax test-eqv
  (syntax-rules ()
    ((test-eqv . rest)
     (%test-comp2 eqv? . rest))))

(define-syntax test-eq
  (syntax-rules ()
    ((test-eq . rest)
     (%test-comp2 eq? . rest))))

(define-syntax test-approximate
  (syntax-rules ()
    ((test-approximate tname expected expr error)
     (%test-comp2 (%test-approximate= error) tname expected expr))
    ((test-approximate expected expr error)
     (%test-comp2 (%test-approximate= error) expected expr))))

(define-syntax %test-error-body
  (syntax-rules ()
    ((%test-error-body r etype expr)
     (let ()
       (if (%test-on-test-begin r)
           (let ()
             (test-result-set! r 'expected-error etype)
             (let ((caught (guard (ex (else
                                       (cond
                                         ((procedure? etype) (etype ex))
                                         ((eq? etype #t) #t)
                                         ((error-object? ex) #t)
                                         (else #t))))
                             (let ((v expr))
                               'no-error-raised))))
               (test-result-set! r 'actual-value caught)
               (%test-on-test-end r (not (eq? caught 'no-error-raised))))))
       (%test-report-result)))))

(define-syntax test-error
  (syntax-rules ()
    ((test-error name etype expr)
     (let ((r (test-runner-get)))
       (test-result-alist! r (list (cons 'test-name name)))
       (%test-error-body r etype expr)))
    ((test-error arg1 expr)
     (let ((r (test-runner-get))
           (a1 arg1))
       (if (string? a1)
           (begin
             (test-result-alist! r (list (cons 'test-name a1)))
             (%test-error-body r #t expr))
           (begin
             (test-result-alist! r '())
             (%test-error-body r a1 expr)))))
    ((test-error expr)
     (let ((r (test-runner-get)))
       (test-result-alist! r '())
       (%test-error-body r #t expr)))))

;;; -----------------------------------------------------------------------
;;; Pre-intern Desugared Compiler Symbols in Reader Table
;;; -----------------------------------------------------------------------
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
