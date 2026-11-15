;;; =======================================================================
;;; Phase 1 R7RS Compliance Verification Test Suite
;;; Covers Issues #847, #848, #849, #850, #851, #852
;;; =======================================================================

(define *test-count* (cons 0 '()))
(define *pass-count* (cons 0 '()))

(define (p1-assert name cond)
  (set-car! *test-count* (+ (car *test-count*) 1))
  (if cond
      (begin
        (set-car! *pass-count* (+ (car *pass-count*) 1))
        (display "  [PASS] ")
        (display name)
        (newline))
      (begin
        (display "  [FAIL] ")
        (display name)
        (newline)
        (error "Test assertion failed:" name))))

(define (p1-equal name expected actual)
  (p1-assert name (equal? expected actual)))

(display "=== [Test Suite: Phase 1 R7RS Compliance Verification] ===\n")

;;; -----------------------------------------------------------------------
;;; Issue #847: Missing Port I/O Procedures (read-string, read-bytevector, read-bytevector!)
;;; -----------------------------------------------------------------------
(display "--- Issue #847: read-string, read-bytevector, read-bytevector! ---\n")

;; 1. read-string
(let ((p (open-input-string "Hello, R7RS world!")))
  (p1-equal "read-string 5 chars" "Hello" (read-string 5 p))
  (p1-equal "read-string 2 chars" ", " (read-string 2 p))
  (p1-equal "read-string 0 chars" "" (read-string 0 p))
  (p1-equal "read-string remaining" "R7RS world!" (read-string 100 p))
  (p1-assert "read-string at EOF returns eof-object" (eof-object? (read-string 5 p))))

;; 2. read-bytevector & read-bytevector!
(let* ((bv-src (bytevector 10 20 30 40 50 60 70 80))
       (p (open-input-bytevector bv-src)))
  (p1-equal "read-bytevector 3 bytes" (bytevector 10 20 30) (read-bytevector 3 p))
  (p1-equal "read-bytevector 0 bytes" (bytevector) (read-bytevector 0 p))
  
  (let ((dest (make-bytevector 5 0)))
    (p1-equal "read-bytevector! 3 bytes into dest" 3 (read-bytevector! dest p 1 4))
    (p1-equal "read-bytevector! dest contents" (bytevector 0 40 50 60 0) dest))
  
  (p1-equal "read-bytevector remaining" (bytevector 70 80) (read-bytevector 10 p))
  (p1-assert "read-bytevector at EOF returns eof-object" (eof-object? (read-bytevector 5 p))))

;;; -----------------------------------------------------------------------
;;; Issue #848: First-Class Procedures for Port I/O & Vector Operations
;;; -----------------------------------------------------------------------
(display "--- Issue #848: First-Class Procedures ---\n")

(p1-assert "procedure? write-char" (procedure? write-char))
(p1-assert "procedure? write-u8" (procedure? write-u8))
(p1-assert "procedure? write-string" (procedure? write-string))
(p1-assert "procedure? read-line" (procedure? read-line))
(p1-assert "procedure? read-string" (procedure? read-string))
(p1-assert "procedure? read-u8" (procedure? read-u8))
(p1-assert "procedure? peek-u8" (procedure? peek-u8))
(p1-assert "procedure? char-ready?" (procedure? char-ready?))
(p1-assert "procedure? u8-ready?" (procedure? u8-ready?))
(p1-assert "procedure? flush-output-port" (procedure? flush-output-port))
(p1-assert "procedure? vector-append" (procedure? vector-append))
(p1-assert "procedure? bytevector-append" (procedure? bytevector-append))
(p1-assert "procedure? vector-copy!" (procedure? vector-copy!))
(p1-assert "procedure? bytevector-copy!" (procedure? bytevector-copy!))
(p1-assert "procedure? read-bytevector" (procedure? read-bytevector))
(p1-assert "procedure? read-bytevector!" (procedure? read-bytevector!))

;; Higher-order procedure usage
(let ((out (open-output-string)))
  (for-each (lambda (c) (write-char c out)) '(#\f #\o #\o))
  (p1-equal "for-each write-char" "foo" (get-output-string out)))

(p1-equal "apply vector-append" #(1 2 3 4) (apply vector-append (list #(1 2) #(3 4))))
(p1-equal "apply bytevector-append" (bytevector 1 2 3 4) (apply bytevector-append (list (bytevector 1 2) (bytevector 3 4))))

;; 4-arg vector-copy! (to at from start)
(let ((v (vector 0 0 0 0 0)))
  (vector-copy! v 1 #(10 20 30 40) 2)
  (p1-equal "vector-copy! 4 args" #(0 30 40 0 0) v))

;; 4-arg bytevector-copy! (to at from start)
(let ((bv (bytevector 0 0 0 0 0)))
  (bytevector-copy! bv 1 (bytevector 10 20 30 40) 2)
  (p1-equal "bytevector-copy! 4 args" (bytevector 0 30 40 0 0) bv))

;;; -----------------------------------------------------------------------
;;; Issue #849: Non-blocking Readiness Detection (char-ready?, u8-ready?)
;;; -----------------------------------------------------------------------
(display "--- Issue #849: Non-blocking Readiness ---\n")

(let ((sp (open-input-string "abc")))
  (p1-assert "char-ready? on string port" (char-ready? sp))
  (p1-assert "u8-ready? on string port" (u8-ready? sp)))

(let ((bp (open-input-bytevector (bytevector 1 2 3))))
  (p1-assert "char-ready? on bytevector port" (char-ready? bp))
  (p1-assert "u8-ready? on bytevector port" (u8-ready? bp)))

;;; -----------------------------------------------------------------------
;;; Issue #850: case Syntax Pipeline Arrow Clauses ((datum ...) => proc)
;;; -----------------------------------------------------------------------
(display "--- Issue #850: case Arrow Clauses ---\n")

(define (test-case-arrow val)
  (case val
    ((1 2 3) => (lambda (x) (* x 10)))
    ((4 5 6) => (lambda (x) (+ x 100)))
    (else => (lambda (x) (- 0 x)))))

(p1-equal "case arrow clause 1" 20 (test-case-arrow 2))
(p1-equal "case arrow clause 2" 105 (test-case-arrow 5))
(p1-equal "case arrow clause else" -99 (test-case-arrow 99))

;; Mixed clauses (standard + arrow)
(define (test-case-mixed val)
  (case val
    ((a b) 'matched-symbol)
    ((10 20) => (lambda (x) (cons 'num x)))
    (else 'default)))

(p1-equal "case mixed symbol" 'matched-symbol (test-case-mixed 'b))
(p1-equal "case mixed arrow" '(num . 20) (test-case-mixed 20))
(p1-equal "case mixed default" 'default (test-case-mixed 'z))

;;; -----------------------------------------------------------------------
;;; Issue #851: Generic Numeric Tower Dispatch & inexact? Predicate
;;; -----------------------------------------------------------------------
(display "--- Issue #851: Numeric Tower & inexact? ---\n")

(p1-assert "inexact? on fixnum is #f" (not (inexact? 42)))
(p1-assert "inexact? on 0 is #f" (not (inexact? 0)))
(p1-assert "inexact? on +inf.0 is #t" (inexact? +inf.0))
(p1-assert "inexact? on -inf.0 is #t" (inexact? -inf.0))
(p1-assert "inexact? on +nan.0 is #t" (inexact? +nan.0))

(p1-equal "fixnum addition fast-path" 42 (+ 40 2))
(p1-equal "fixnum subtraction fast-path" 38 (- 40 2))
(p1-equal "fixnum multiplication fast-path" 80 (* 40 2))
(p1-equal "fixnum division fast-path" 20 (/ 40 2))
(p1-assert "fixnum equality fast-path" (= 40 40))

;;; -----------------------------------------------------------------------
;;; Issue #852: Standard Library Exports
;;; -----------------------------------------------------------------------
(display "--- Issue #852: Standard Library Exports ---\n")

(p1-assert "caar exists" (procedure? caar))
(p1-assert "cadr exists" (procedure? cadr))
(p1-assert "cdar exists" (procedure? cdar))
(p1-assert "cddr exists" (procedure? cddr))
(p1-equal "cadr evaluation" 20 (cadr '(10 20 30)))
(p1-equal "cdar evaluation" '(2 3) (cdar '((1 2 3) 4)))

(newline)
(display "-------------------------------------------------------\n")
(display " [RESULT] Phase 1 Tests: ")
(display (car *pass-count*))
(display " passed (Total: ")
(display (car *test-count*))
(display ")\n")
(display "-------------------------------------------------------\n")
