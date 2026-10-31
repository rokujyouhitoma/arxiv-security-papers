;;; =======================================================================
;;; Unit & Endurance Test Suite: Low-Level Atomic Primitives (Issue #631)
;;; Conforms to DSN-37 Section 6, Section 13.4 & Section 14.2 (Phase 0 Task 0.2)
;;; =======================================================================

(load "ulisp/runtime/concurrency/atomic.scm")

(define *test-atomic-failures* (vector 0))
(define *test-atomic-passes* (vector 0))

(define (assert-true val msg)
  (if (not val)
      (begin
        (vector-set! *test-atomic-failures* 0 (+ (vector-ref *test-atomic-failures* 0) 1))
        (write-string "FAIL: ")
        (write-string msg)
        (write-char #\newline)
        (flush-output-port)
        #f)
      (begin
        (vector-set! *test-atomic-passes* 0 (+ (vector-ref *test-atomic-passes* 0) 1))
        (write-string "PASS: ")
        (write-string msg)
        (write-char #\newline)
        (flush-output-port)
        #t)))

(define (assert-equal actual expected msg)
  (if (not (eqv? actual expected))
      (begin
        (vector-set! *test-atomic-failures* 0 (+ (vector-ref *test-atomic-failures* 0) 1))
        (write-string "FAIL: ")
        (write-string msg)
        (write-string " (expected ")
        (if (integer? expected) (write-string (number->string expected)) (write-string "<val>"))
        (write-string ", got ")
        (if (integer? actual) (write-string (number->string actual)) (write-string "<val>"))
        (write-string ")\n")
        (flush-output-port)
        #f)
      (begin
        (vector-set! *test-atomic-passes* 0 (+ (vector-ref *test-atomic-passes* 0) 1))
        (write-string "PASS: ")
        (write-string msg)
        (write-char #\newline)
        (flush-output-port)
        #t)))

(write-string "=======================================================\n")
(write-string " Starting Low-Level Atomic Primitives Test Suite (#631)\n")
(write-string "=======================================================\n")
(flush-output-port)

;; -----------------------------------------------------------------------
;; Group 1: <atomic-box> Initialization, Predicates, Ref/Set & Memory Fence
;; -----------------------------------------------------------------------
(write-string "--- Group 1: <atomic-box> Initialization & Ref/Set ---\n")
(flush-output-port)

(let ((b1 (make-atomic-box 42))
      (b2 (make-atomic-box 'ready)))
  (assert-true (memory-fence) "memory-fence executes MFENCE and returns #t")
  (assert-true (atomic-box? b1) "b1 satisfies atomic-box?")
  (assert-true (atomic-box? b2) "b2 satisfies atomic-box?")
  (assert-true (not (atomic-box? 42)) "fixnum is not atomic-box?")
  (assert-true (not (atomic-box? (cons 1 2))) "pair is not atomic-box?")
  (assert-true (not (atomic-box? (vector 1 2))) "plain vector is not atomic-box?")
  (assert-equal (atomic-ref b1) 42 "atomic-ref reads initial fixnum 42")
  (assert-equal (atomic-box-ref b1) 42 "atomic-box-ref alias reads initial fixnum 42")
  (assert-true (eq? (atomic-ref b2) 'ready) "atomic-ref reads initial symbol 'ready")
  (atomic-set! b1 100)
  (assert-equal (atomic-ref b1) 100 "atomic-set! updates box value to 100")
  (atomic-box-set! b1 256)
  (assert-equal (atomic-box-ref b1) 256 "atomic-box-set! alias updates box value to 256"))

;; -----------------------------------------------------------------------
;; Group 2: Hardware atomic-cas! (LOCK CMPXCHG) Success & Failure Semantics
;; -----------------------------------------------------------------------
(write-string "--- Group 2: Hardware atomic-cas! (LOCK CMPXCHG) ---\n")
(flush-output-port)

(let* ((box (make-atomic-box 10))
       (ok1 (atomic-cas! box 10 20))
       (val1 (atomic-ref box))
       (ok2 (atomic-cas! box 10 30))
       (val2 (atomic-ref box))
       (ok3 (atomic-cas! box 20 30))
       (val3 (atomic-ref box)))
  (assert-true ok1 "atomic-cas! succeeds (#t) when expected value matches (10 -> 20)")
  (assert-equal val1 20 "box value is updated to 20 after successful CAS")
  (assert-true (not ok2) "atomic-cas! fails (#f) when expected value mismatches (10 != 20)")
  (assert-equal val2 20 "box value remains 20 after failed CAS")
  (assert-true ok3 "subsequent atomic-cas! with matching expected 20 succeeds (20 -> 30)")
  (assert-equal val3 30 "box value is updated to 30"))

;; Pointer identity CAS on heap-allocated pairs and vectors
(let* ((node-a (cons 'a '()))
       (node-b (cons 'b node-a))
       (node-a-twin (cons 'a '()))
       (head (make-atomic-box node-a)))
  (assert-true (not (atomic-cas! head node-a-twin node-b))
               "atomic-cas! uses pointer identity (eq?) and rejects distinct pair with equal contents")
  (assert-true (eq? (atomic-ref head) node-a)
               "head still points to original node-a after rejected twin CAS")
  (assert-true (atomic-cas! head node-a node-b)
               "atomic-cas! succeeds when exact pointer node-a is supplied")
  (assert-true (eq? (atomic-ref head) node-b)
               "head now points to node-b"))

;; -----------------------------------------------------------------------
;; Group 3: Derived Atomic Operations (swap!, fetch-add!, update!)
;; -----------------------------------------------------------------------
(write-string "--- Group 3: Derived Atomic Operations ---\n")
(flush-output-port)

(let ((counter (make-atomic-box 0)))
  (let ((prev1 (atomic-fetch-add! counter 5))
        (prev2 (atomic-fetch-add! counter 12))
        (prev3 (atomic-fetch-add! counter -3)))
    (assert-equal prev1 0 "atomic-fetch-add! returns previous value 0")
    (assert-equal prev2 5 "atomic-fetch-add! returns previous value 5")
    (assert-equal prev3 17 "atomic-fetch-add! returns previous value 17")
    (assert-equal (atomic-ref counter) 14 "counter final value after fetch-add! sequence is 14"))
  (let ((old (atomic-swap! counter 99)))
    (assert-equal old 14 "atomic-swap! returns old value 14")
    (assert-equal (atomic-ref counter) 99 "atomic-swap! installs new value 99"))
  (let ((updated (atomic-update! counter (lambda (x) (* x 2)))))
    (assert-equal updated 198 "atomic-update! returns newly computed value 198")
    (assert-equal (atomic-ref counter) 198 "box holds updated value 198")))

;; -----------------------------------------------------------------------
;; Group 4: ABA Problem Prevention (<atomic-stamped-box>)
;; -----------------------------------------------------------------------
(write-string "--- Group 4: ABA Problem Prevention (<atomic-stamped-box>) ---\n")
(flush-output-port)

(let* ((node-a (cons 'node-a '()))
       (node-b (cons 'node-b '()))
       (sbox   (make-atomic-stamped-box node-a 1)))
  (assert-true (atomic-stamped-box? sbox) "sbox satisfies atomic-stamped-box?")
  (assert-true (not (atomic-stamped-box? (make-atomic-box 1))) "plain atomic-box is not atomic-stamped-box?")
  (assert-true (eq? (atomic-stamped-val sbox) node-a) "initial stamped val is node-a")
  (assert-equal (atomic-stamped-stamp sbox) 1 "initial stamp is 1")

  ;; Thread 1 observes (node-a, stamp=1)
  (let ((observed-val (atomic-stamped-val sbox))
        (observed-stamp (atomic-stamped-stamp sbox)))
    ;; Thread 2 mutates A -> B (stamp 1 -> 2), then B -> A (stamp 2 -> 3)
    (assert-true (atomic-stamped-cas! sbox node-a node-b 1 2)
                 "transition A -> B (stamp 1 -> 2) succeeds")
    (assert-true (atomic-stamped-cas! sbox node-b node-a 2 3)
                 "transition B -> A (stamp 2 -> 3) succeeds")
    (assert-true (eq? (atomic-stamped-val sbox) node-a)
                 "value is back to identical pointer node-a (ABA state)")
    (assert-equal (atomic-stamped-stamp sbox) 3
                  "stamp has advanced to 3")

    ;; Thread 1 now attempts CAS with stale stamp=1 -> MUST FAIL!
    (assert-true (not (atomic-stamped-cas! sbox observed-val node-b observed-stamp 2))
                 "ABA mitigation: atomic-stamped-cas! rejects stale stamp 1 even though value is node-a")
    (assert-equal (atomic-stamped-stamp sbox) 3
                  "stamp remains 3 after rejected ABA CAS")

    ;; CAS with current stamp=3 succeeds
    (assert-true (atomic-stamped-cas! sbox node-a node-b 3 4)
                 "atomic-stamped-cas! succeeds with matching stamp 3 -> 4")
    (assert-true (eq? (atomic-stamped-val sbox) node-b)
                 "stamped box value updated to node-b")
    (assert-equal (atomic-stamped-stamp sbox) 4
                  "stamped box stamp updated to 4")))

;; -----------------------------------------------------------------------
;; Group 5: Lock-Free Treiber Stack & Endurance CAS Stress Test (10,000 ops)
;; -----------------------------------------------------------------------
(write-string "--- Group 5: Lock-Free Treiber Stack & 10,000 CAS Endurance ---\n")
(flush-output-port)

(let ((stack-head (make-atomic-box '()))
      (ops-counter (make-atomic-box 0)))
  (let push-loop ((i 1))
    (if (<= i 5000)
        (let retry ()
          (let ((old-head (atomic-ref stack-head)))
            (if (atomic-cas! stack-head old-head (cons i old-head))
                (begin
                  (atomic-fetch-add! ops-counter 1)
                  (push-loop (+ i 1)))
                (retry))))))
  (assert-equal (atomic-ref ops-counter) 5000 "5,000 lock-free CAS pushes completed")

  (let pop-loop ((cur (atomic-ref stack-head)) (sum 0) (count 0))
    (if (null? cur)
        (begin
          (assert-equal count 5000 "5,000 lock-free CAS pops completed")
          (assert-equal sum 12502500 "sum of popped elements 1..5000 is 12502500")
          (assert-equal (atomic-ref ops-counter) 10000 "total atomic CAS + fetch-add operations = 10,000"))
        (if (atomic-cas! stack-head cur (cdr cur))
            (begin
              (atomic-fetch-add! ops-counter 1)
              (pop-loop (atomic-ref stack-head) (+ sum (car cur)) (+ count 1)))
            (pop-loop (atomic-ref stack-head) sum count)))))

;; -----------------------------------------------------------------------
;; Group 6: Security Guard Verification (TM-631-01 / CWE-843 Type Confusion)
;; -----------------------------------------------------------------------
(write-string "--- Group 6: Security Guard Verification (CWE-843) ---\n")
(flush-output-port)

(let ((caught-ref
       (guard (exn (#t #t))
         (atomic-ref (vector 1 2 3))
         #f))
      (caught-set
       (guard (exn (#t #t))
         (atomic-set! 123 456)
         #f))
      (caught-cas
       (guard (exn (#t #t))
         (atomic-cas! (cons 1 2) 1 2)
         #f))
      (caught-stamped
       (guard (exn (#t #t))
         (atomic-stamped-cas! (make-atomic-box 1) 1 2 0 1)
         #f)))
  (assert-true caught-ref "atomic-ref rejects raw vector (CWE-843 mitigation)")
  (assert-true caught-set "atomic-set! rejects fixnum (CWE-843 mitigation)")
  (assert-true caught-cas "atomic-cas! rejects pair (CWE-843 mitigation)")
  (assert-true caught-stamped "atomic-stamped-cas! rejects plain atomic-box (CWE-843 mitigation)"))

;; -----------------------------------------------------------------------
;; Summary
;; -----------------------------------------------------------------------
(write-string "=======================================================\n")
(write-string " Atomic Primitives Test Summary: ")
(write-string (number->string (vector-ref *test-atomic-passes* 0)))
(write-string " passed, ")
(write-string (number->string (vector-ref *test-atomic-failures* 0)))
(write-string " failed.\n")
(write-string "=======================================================\n")
(flush-output-port)

(if (> (vector-ref *test-atomic-failures* 0) 0)
    (error "test_atomic: one or more assertions failed" (vector-ref *test-atomic-failures* 0)))

