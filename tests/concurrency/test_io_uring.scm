;;; =======================================================================
;;; Synapse Concurrency: Linux io_uring Event Loop Test Suite
;;; Conforms to Issue #677, DSN-37 Section 7.4.3 & Section 14.9 Task 7.3
;;; =======================================================================

(load "ulisp/runtime/concurrency/atomic.scm")
(load "ulisp/runtime/concurrency/arena.scm")
(load "ulisp/runtime/concurrency/boundary.scm")
(load "ulisp/runtime/concurrency/channel.scm")
(load "ulisp/runtime/concurrency/links.scm")
(load "ulisp/runtime/concurrency/panic.scm")
(load "ulisp/runtime/concurrency/supervisor.scm")
(load "ulisp/runtime/concurrency/registry.scm")
(load "ulisp/runtime/concurrency/crash_logger.scm")
(load "ulisp/runtime/concurrency/io_uring.scm")

;; -----------------------------------------------------------------------
;; Minimal Test Harness
;; -----------------------------------------------------------------------

(define *pass-count* (vector 0))
(define *fail-count* (vector 0))

(define (assert-true cond msg)
  (if cond
      (begin
        (vector-set! *pass-count* 0 (+ (vector-ref *pass-count* 0) 1))
        (write-string "PASS: ") (write-string msg) (write-char #\newline))
      (begin
        (vector-set! *fail-count* 0 (+ (vector-ref *fail-count* 0) 1))
        (write-string "FAIL: ") (write-string msg) (write-char #\newline))))

(define (assert-equal actual expected msg)
  (if (equal? actual expected)
      (begin
        (vector-set! *pass-count* 0 (+ (vector-ref *pass-count* 0) 1))
        (write-string "PASS: ") (write-string msg) (write-char #\newline))
      (begin
        (vector-set! *fail-count* 0 (+ (vector-ref *fail-count* 0) 1))
        (write-string "FAIL: ") (write-string msg)
        (write-string " [expected ") (write-string (number->string expected))
        (write-string ", got ") (write-string (number->string actual)) (write-string "]\n"))))

(define (assert-error thunk msg)
  (let ((caught? (vector #f)))
    (guard (ex (else (vector-set! caught? 0 #t)))
      (thunk))
    (if (vector-ref caught? 0)
        (begin
          (vector-set! *pass-count* 0 (+ (vector-ref *pass-count* 0) 1))
          (write-string "PASS: ") (write-string msg) (write-char #\newline))
        (begin
          (vector-set! *fail-count* 0 (+ (vector-ref *fail-count* 0) 1))
          (write-string "FAIL: ") (write-string msg) (write-string " (expected error not raised)\n")))))

(write-string "=======================================================\n")
(write-string " Starting Synapse io_uring Event Loop Test Suite (#677)\n")
(write-string "=======================================================\n")
(flush-output-port)

;; -----------------------------------------------------------------------
;; Group 1: Basic Ring Initialization & Lifecycle
;; -----------------------------------------------------------------------
(define (run-group-1!)
  (write-string "--- Group 1: Ring Initialization & Lifecycle ---\n")
  (flush-output-port)
  (let ((ring (make-io-uring 64)))
    (assert-true (io-uring? ring) "make-io-uring returns <io-uring>")
    (assert-equal (io-uring-capacity ring) 64 "capacity is 64")
    (assert-equal (io-uring-submitted-count ring) 0 "initial submitted count is 0")
    (assert-equal (io-uring-completed-count ring) 0 "initial completed count is 0")
    (assert-equal (io-uring-pending-count ring) 0 "initial pending count is 0")
    (assert-true (io-uring-active? ring) "ring is active initially")
    (assert-true (boolean? (io-uring-native? ring)) "native? returns boolean")

    ;; Stats API
    (let ((st (io-uring-stats ring)))
      (assert-true (pair? st) "io-uring-stats returns alist")
      (assert-equal (cdr (assq 'capacity st)) 64 "stats capacity is 64")
      (assert-equal (cdr (assq 'pending st)) 0 "stats pending is 0"))

    ;; Close ring
    (assert-true (io-uring-close! ring) "io-uring-close! returns #t")
    (assert-true (not (io-uring-active? ring)) "ring is inactive after close")
    (assert-true (not (io-uring-close! ring)) "duplicate close returns #f")))

(run-group-1!)

;; -----------------------------------------------------------------------
;; Group 2: NOP Submission, Task Suspension & CQE Retrieval
;; -----------------------------------------------------------------------
(define (run-group-2!)
  (write-string "--- Group 2: NOP Submission & Task Resumption ---\n")
  (flush-output-port)
  (let ((ring (make-io-uring 32))
        (task (make-task-context)))
    (assert-true (io-uring-submit-nop! ring 12345 task) "io-uring-submit-nop! succeeds")
    (assert-equal (io-uring-pending-count ring) 1 "pending count is 1")
    (assert-equal (io-uring-submitted-count ring) 1 "submitted count is 1")
    (assert-true (eq? (task-state task) 'waiting-io) "task suspended to 'waiting-io")

    ;; Poll completions
    (let ((completed-count (io-uring-poll-completions! ring)))
      (assert-equal completed-count 1 "poll-completions returned 1")
      (assert-equal (io-uring-pending-count ring) 0 "pending count decremented to 0")
      (assert-equal (io-uring-completed-count ring) 1 "completed count is 1")
      (assert-true (eq? (task-state task) 'ready) "task resumed to 'ready")

      ;; Check task handoff result
      (let ((handoff (task-handoff task)))
        (assert-true (pair? handoff) "task handoff is pair")
        (assert-true (eq? (car handoff) 'io_complete) "handoff tag is 'io_complete")
        (assert-equal (cdr handoff) 0 "NOP result is 0 bytes"))

      ;; Dequeue CQE from ring
      (let ((cqe (io-uring-dequeue-completion! ring)))
        (assert-true (pair? cqe) "dequeue returns pair")
        (assert-equal (car cqe) 12345 "user_data matches 12345")
        (assert-equal (cdr cqe) 0 "result bytes is 0")))

    (io-uring-close! ring)))

(run-group-2!)

;; -----------------------------------------------------------------------
;; Group 3: Async Read & Write Submissions
;; -----------------------------------------------------------------------
(define (run-group-3!)
  (write-string "--- Group 3: Async Read & Write Operations ---\n")
  (flush-output-port)
  (let ((ring (make-io-uring 32))
        (buf (make-bytevector 64 0))
        (task-r (make-task-context))
        (task-w (make-task-context)))

    ;; Submit async write
    (assert-true (io-uring-submit-write! ring 1 buf 0 32 task-w) "submit write succeeds")
    (assert-true (eq? (task-state task-w) 'waiting-io) "writer task suspended to 'waiting-io")

    ;; Submit async read
    (assert-true (io-uring-submit-read! ring 0 buf 0 48 task-r) "submit read succeeds")
    (assert-true (eq? (task-state task-r) 'waiting-io) "reader task suspended to 'waiting-io")

    (assert-equal (io-uring-pending-count ring) 2 "pending count is 2")

    ;; Poll completions
    (let ((c (io-uring-poll-completions! ring)))
      (assert-equal c 2 "both write and read completed")
      (assert-true (eq? (task-state task-w) 'ready) "writer task resumed to 'ready")
      (assert-true (eq? (task-state task-r) 'ready) "reader task resumed to 'ready")
      (assert-equal (cdr (task-handoff task-w)) 32 "writer transferred 32 bytes")
      (assert-equal (cdr (task-handoff task-r)) 48 "reader transferred 48 bytes"))

    (io-uring-close! ring)))

(run-group-3!)

;; -----------------------------------------------------------------------
;; Group 4: Task Resumption and Multiplexing
;; -----------------------------------------------------------------------
(define (run-group-4!)
  (write-string "--- Group 4: Multiplexed Concurrent I/O Tasks ---\n")
  (flush-output-port)
  (let ((ring (make-io-uring 64))
        (t1 (make-task-context))
        (t2 (make-task-context))
        (t3 (make-task-context)))

    (io-uring-submit-nop! ring 101 t1)
    (io-uring-submit-nop! ring 102 t2)
    (io-uring-submit-nop! ring 103 t3)

    (assert-true (eq? (task-state t1) 'waiting-io) "t1 is waiting-io")
    (assert-true (eq? (task-state t2) 'waiting-io) "t2 is waiting-io")
    (assert-true (eq? (task-state t3) 'waiting-io) "t3 is waiting-io")

    (let ((completed (io-uring-poll-completions! ring)))
      (assert-equal completed 3 "3 multiplexed tasks completed simultaneously")
      (assert-true (eq? (task-state t1) 'ready) "t1 resumed")
      (assert-true (eq? (task-state t2) 'ready) "t2 resumed")
      (assert-true (eq? (task-state t3) 'ready) "t3 resumed"))

    (io-uring-close! ring)))

(run-group-4!)

;; -----------------------------------------------------------------------
;; Group 5: High-Throughput Burst & Bounded Capacity (CWE-400)
;; -----------------------------------------------------------------------
(define (run-group-5!)
  (write-string "--- Group 5: High-Throughput Burst & Bounded Capacity ---\n")
  (flush-output-port)
  (let* ((ring (make-io-uring 1000))
         (n 500))

    ;; Submit 500 NOPs in a burst loop
    (let loop ((i 0))
      (if (< i n)
          (begin
            (io-uring-submit-nop! ring (+ i 1))
            (loop (+ i 1)))
          #t))

    (assert-equal (io-uring-pending-count ring) 500 "pending count is 500")
    (assert-equal (io-uring-submitted-count ring) 500 "submitted count is 500")

    ;; Poll completions
    (let ((c (io-uring-poll-completions! ring)))
      (assert-equal c 500 "all 500 operations completed")
      (assert-equal (io-uring-pending-count ring) 0 "pending drained to 0")
      (assert-equal (io-uring-completed-count ring) 500 "completed count matches 500"))

    (io-uring-close! ring)))

(run-group-5!)

;; -----------------------------------------------------------------------
;; Group 6: Security Guards & Boundary Validations (CWE-119, CWE-400, CWE-843, CWE-833)
;; -----------------------------------------------------------------------
(define (run-group-6!)
  (write-string "--- Group 6: Security & Boundary Guards ---\n")
  (flush-output-port)

  (let ((ring (make-io-uring 16))
        (buf (make-bytevector 32 0)))

    ;; CWE-119: Buffer bound violations
    (assert-error (lambda () (io-uring-submit-read! ring 0 buf 0 64 #f))
                  "rejects length exceeding buffer size (CWE-119)")
    (assert-error (lambda () (io-uring-submit-read! ring 0 buf -1 16 #f))
                  "rejects negative offset (CWE-119)")
    (assert-error (lambda () (io-uring-submit-read! ring 0 buf 0 -5 #f))
                  "rejects negative length (CWE-119)")

    ;; CWE-400: Capacity bounds
    (assert-error (lambda () (make-io-uring 0))
                  "rejects zero capacity (CWE-400)")
    (assert-error (lambda () (make-io-uring -10))
                  "rejects negative capacity (CWE-400)")
    (assert-error (lambda () (make-io-uring 5000))
                  "rejects capacity exceeding max 4096 (CWE-400)")

    ;; CWE-400: Ring full rejection
    (let ((small-ring (make-io-uring 2)))
      (io-uring-submit-nop! small-ring 1)
      (io-uring-submit-nop! small-ring 2)
      (assert-error (lambda () (io-uring-submit-nop! small-ring 3))
                    "rejects submission when ring buffer full (CWE-400)")
      (io-uring-close! small-ring))

    ;; CWE-843: Type confusion rejection
    (assert-error (lambda () (make-io-uring "not-an-int"))
                  "make-io-uring rejects non-integer capacity (CWE-843)")
    (assert-error (lambda () (io-uring-submit-read! ring "not-an-fd" buf 0 16 #f))
                  "rejects non-integer fd (CWE-843)")
    (assert-error (lambda () (io-uring-submit-read! ring 0 "not-a-bytevector" 0 16 #f))
                  "rejects non-bytevector buffer (CWE-843)")
    (assert-error (lambda () (io-uring-submit-nop! "not-a-ring" 1))
                  "rejects non-io-uring object (CWE-843)")

    ;; CWE-833: Closed ring rejection
    (io-uring-close! ring)
    (assert-error (lambda () (io-uring-submit-nop! ring 1))
                  "rejects submission on closed ring (CWE-833)")))

(run-group-6!)

;; -----------------------------------------------------------------------
;; Summary
;; -----------------------------------------------------------------------
(write-string "=======================================================\n")
(write-string " Synapse io_uring Summary: ")
(write-string (number->string (vector-ref *pass-count* 0)))
(write-string " passed, ")
(write-string (number->string (vector-ref *fail-count* 0)))
(write-string " failed.\n")
(write-string "=======================================================\n")
(flush-output-port)

(if (> (vector-ref *fail-count* 0) 0)
    (exit 1)
    (exit 0))

