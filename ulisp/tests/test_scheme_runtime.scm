;;; =======================================================================
;;; Unit Test Suite: ULisp Pure Scheme Runtime (Pre-Scheme Architecture)
;;; Conforms to DSN-33 Architecture Specification & Issue #580
;;;
;;; Verifies pure Scheme implementation of GC state management,
;;; low-level I/O primitives, value printer, and entrypoint orchestration.
;;; =======================================================================

(define *runtime-failures* (vector 0))

(define (assert-true val msg)
  (if (not val)
      (begin
        (vector-set! *runtime-failures* 0 (+ (vector-ref *runtime-failures* 0) 1))
        (write-string "FAIL: ")
        (write-string msg)
        (write-char #\newline)
        (flush-output-port)
        #f)
      (begin
        (write-string "PASS: ")
        (write-string msg)
        (write-char #\newline)
        (flush-output-port)
        #t)))

(define (assert-equal actual expected msg)
  (if (not (or (eqv? actual expected)
               (and (string? actual) (string? expected) (string=? actual expected))))
      (begin
        (vector-set! *runtime-failures* 0 (+ (vector-ref *runtime-failures* 0) 1))
        (write-string "FAIL: ")
        (write-string msg)
        (write-char #\newline)
        (flush-output-port)
        #f)
      (begin
        (write-string "PASS: ")
        (write-string msg)
        (write-char #\newline)
        (flush-output-port)
        #t)))

(write-string "=======================================================\n")
(write-string " Starting Pure Scheme Runtime (Pre-Scheme) Test Suite (#580)\n")
(write-string "=======================================================\n")
(flush-output-port)

;;; --- Group 1: I/O Primitives (io.scm) ---
(write-string "--- Group 1: I/O Primitives (io.scm) ---\n")
(flush-output-port)

;; Peek buffer operations
(runtime-clear-peek!)
(assert-true (not (runtime-has-peek?)) "peek buffer initial state is empty")

(runtime-set-peek! 65) ; 'A'
(assert-true (runtime-has-peek?) "has-peek is true after set")
(assert-equal (runtime-get-peek-byte) 65 "peek byte is 65 ('A')")

(assert-equal (runtime-peek-char)
              (bitwise-ior (* 65 256) 14)
              "runtime-peek-char returns tagged 'A'")
(assert-true (runtime-has-peek?) "peek-char does not consume buffer")

(assert-equal (runtime-read-char)
              (bitwise-ior (* 65 256) 14)
              "runtime-read-char returns tagged 'A' and clears peek")
(assert-true (not (runtime-has-peek?)) "read-char consumed peek buffer")

;; Reading from closed/empty stdin (e.g. /dev/null) returns EOF (79)
(assert-equal (runtime-read-char) 79 "runtime-read-char returns EOF (79) on empty stdin")

;; I/O write operations
(assert-equal (runtime-flush) 111 "runtime-flush returns #t")

;;; --- Group 2: GC State Management (gc.scm) ---
(write-string "--- Group 2: GC State Management (gc.scm) ---\n")
(flush-output-port)

(assert-true (procedure? runtime-gc-state-ref) "runtime-gc-state-ref procedure exists")
(assert-true (procedure? runtime-gc-grow-mature) "runtime-gc-grow-mature procedure exists")
(assert-true (procedure? runtime-gc-write-barrier) "runtime-gc-write-barrier procedure exists")
(assert-true (procedure? runtime-init-heap) "runtime-init-heap procedure exists")

;; Verify grow mature returns 0 when occupancy is low
(assert-equal (runtime-gc-grow-mature) 0 "runtime-gc-grow-mature returns 0 when no growth needed")

;;; --- Group 3: Scheme Value Printer (printer.scm) ---
(write-string "--- Group 3: Scheme Value Printer (printer.scm) ---\n")
(flush-output-port)

(assert-true (procedure? runtime-print-value-raw) "runtime-print-value-raw procedure exists")
(assert-true (procedure? runtime-print-value) "runtime-print-value procedure exists")

;; Test tag bit constants
(assert-equal *fixnum-mask* 3 "fixnum mask is 3")
(assert-equal *pair-mask* 7 "pair mask is 7")
(assert-equal *pair-tag* 1 "pair tag is 1")
(assert-equal *string-tag* 3 "string tag is 3")
(assert-equal *vector-tag* 5 "vector tag is 5")
(assert-equal *bytevector-tag* 7 "bytevector tag is 7")
(assert-equal *bool-false* 47 "bool-false is 47")
(assert-equal *bool-true* 111 "bool-true is 111")
(assert-equal *empty-list* 63 "empty-list is 63")
(assert-equal *eof-object* 79 "eof-object is 79")

;;; --- Group 4: Entrypoint (entry.scm) ---
(write-string "--- Group 4: Entrypoint Orchestration (entry.scm) ---\n")
(flush-output-port)

(assert-true (procedure? runtime-main) "runtime-main procedure exists")

;;; --- Summary ---
(write-string "=======================================================\n")
(if (= (vector-ref *runtime-failures* 0) 0)
    (begin
      (write-string " SUCCESS: ALL PURE SCHEME RUNTIME TESTS PASSED!\n")
      (write-string "=======================================================\n")
      (flush-output-port)
      #t)
    (begin
      (write-string " FAILURE: Some runtime tests failed!\n")
      (write-string "=======================================================\n")
      (flush-output-port)
      (exit 1)))
