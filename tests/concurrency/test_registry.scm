;;; =======================================================================
;;; ULisp Concurrency Test Suite: Process Name Registry & Rebinding (#669)
;;; Conforms to DSN-37 Section 8.4.5 & Phase 6 Task 6.4
;;;
;;; Tests:
;;;   Group 1: Basic Registration, Unregistration & Whereis Lookup
;;;   Group 2: Duplicate Registration Rejection & Atomic Rebind
;;;   Group 3: Transparent Non-Blocking Send (synapse-send-named!)
;;;   Group 4: Supervisor Restart & Dynamic Rebind Integration
;;;   Group 5: High-Throughput Concurrent Registration & Lookup
;;;   Group 6: Security & Boundary Guards (CWE-843, CWE-400, CWE-833)
;;; =======================================================================

(load "ulisp/runtime/concurrency/atomic.scm")
(load "ulisp/runtime/concurrency/arena.scm")
(load "ulisp/runtime/concurrency/queue.scm")
(load "ulisp/runtime/concurrency/channel.scm")
(load "ulisp/runtime/concurrency/context.scm")
(load "ulisp/runtime/concurrency/deque.scm")
(load "ulisp/runtime/concurrency/thread.scm")
(load "ulisp/runtime/concurrency/futex.scm")
(load "ulisp/runtime/concurrency/scheduler.scm")
(load "ulisp/runtime/concurrency/links.scm")
(load "ulisp/runtime/concurrency/panic.scm")
(load "ulisp/runtime/concurrency/supervisor.scm")
(load "ulisp/runtime/concurrency/registry.scm")

(define *test-reg-failures* (vector 0))
(define *test-reg-passes* (vector 0))

(define (assert-true val msg)
  (if (not val)
      (begin
        (vector-set! *test-reg-failures* 0 (+ (vector-ref *test-reg-failures* 0) 1))
        (write-string "FAIL: ")
        (write-string msg)
        (write-char #\newline)
        (flush-output-port)
        #f)
      (begin
        (vector-set! *test-reg-passes* 0 (+ (vector-ref *test-reg-passes* 0) 1))
        (write-string "PASS: ")
        (write-string msg)
        (write-char #\newline)
        (flush-output-port)
        #t)))

(define (assert-equal actual expected msg)
  (if (not (equal? actual expected))
      (begin
        (vector-set! *test-reg-failures* 0 (+ (vector-ref *test-reg-failures* 0) 1))
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
        (vector-set! *test-reg-passes* 0 (+ (vector-ref *test-reg-passes* 0) 1))
        (write-string "PASS: ")
        (write-string msg)
        (write-char #\newline)
        (flush-output-port)
        #t)))

(define (assert-error thunk msg)
  (let ((raised-box (vector #f)))
    (guard (exn (else (vector-set! raised-box 0 #t)))
      (thunk))
    (if (vector-ref raised-box 0)
        (begin
          (vector-set! *test-reg-passes* 0 (+ (vector-ref *test-reg-passes* 0) 1))
          (write-string "PASS: ")
          (write-string msg)
          (write-char #\newline)
          (flush-output-port)
          #t)
        (begin
          (vector-set! *test-reg-failures* 0 (+ (vector-ref *test-reg-failures* 0) 1))
          (write-string "FAIL: ")
          (write-string msg)
          (write-string " (expected exception but none raised)")
          (write-char #\newline)
          (flush-output-port)
          #f))))

(write-string "=======================================================\n")
(write-string " Starting Synapse Process Registry Test Suite (#669)\n")
(write-string "=======================================================\n")
(flush-output-port)

;; -----------------------------------------------------------------------
;; Group 1: Basic Registration, Unregistration & Whereis Lookup
;; -----------------------------------------------------------------------
(write-string "--- Group 1: Basic Registration, Unregistration & Whereis ---\n")
(flush-output-port)

(let* ((reg (make-process-registry))
       (ch1 (make-channel 10)))
  (assert-true (process-registry? reg) "make-process-registry returns <process-registry>")
  (assert-equal (synapse-registry-count reg) 0 "initial registry count is 0")
  (assert-equal (synapse-whereis reg 'worker_1) #f "unregistered name resolves to #f")

  ;; Register ch1
  (assert-true (synapse-register! reg 'worker_1 ch1) "synapse-register! succeeds")
  (assert-equal (synapse-registry-count reg) 1 "registry count is 1")
  (assert-true (eq? (synapse-whereis reg 'worker_1) ch1) "synapse-whereis resolves to registered channel")

  ;; List names
  (let ((names (synapse-registered-names reg)))
    (assert-true (and (pair? names) (memq 'worker_1 names)) "synapse-registered-names contains 'worker_1"))

  ;; Unregister
  (assert-true (synapse-unregister! reg 'worker_1) "synapse-unregister! succeeds")
  (assert-equal (synapse-registry-count reg) 0 "registry count decrements to 0")
  (assert-equal (synapse-whereis reg 'worker_1) #f "unregistered name resolves to #f after removal")
  (assert-true (not (synapse-unregister! reg 'worker_1)) "unregistering non-existent name returns #f")

  ;; Clear
  (synapse-register! reg 'a ch1)
  (synapse-register! reg 'b ch1)
  (assert-equal (synapse-registry-count reg) 2 "registered 2 names")
  (assert-true (synapse-registry-clear! reg) "synapse-registry-clear! succeeds")
  (assert-equal (synapse-registry-count reg) 0 "count is 0 after clear")
  (assert-equal (synapse-whereis reg 'a) #f "'a resolved to #f after clear"))

;; -----------------------------------------------------------------------
;; Group 2: Duplicate Registration Rejection & Atomic Rebind
;; -----------------------------------------------------------------------
(write-string "--- Group 2: Duplicate Registration & Atomic Rebind ---\n")
(flush-output-port)

(let* ((reg (make-process-registry))
       (ch-old (make-channel 10))
       (ch-new (make-channel 10)))
  ;; Register old channel
  (assert-true (synapse-register! reg 'logger ch-old) "register 'logger with ch-old")
  ;; Duplicate registration must fail without overwriting
  (assert-true (not (synapse-register! reg 'logger ch-new)) "duplicate registration rejected (returns #f)")
  (assert-true (eq? (synapse-whereis reg 'logger) ch-old) "whereis still returns ch-old after failed duplicate")

  ;; Atomic Rebind replaces target
  (assert-true (synapse-rebind! reg 'logger ch-new) "synapse-rebind! succeeds on existing name")
  (assert-true (eq? (synapse-whereis reg 'logger) ch-new) "whereis resolves to ch-new after rebind")
  (assert-equal (synapse-registry-count reg) 1 "count remains 1 after rebind of existing name")

  ;; Rebind on non-existent name inserts it
  (assert-true (synapse-rebind! reg 'database ch-old) "synapse-rebind! inserts non-existent name")
  (assert-true (eq? (synapse-whereis reg 'database) ch-old) "whereis resolves 'database to ch-old")
  (assert-equal (synapse-registry-count reg) 2 "count increments to 2"))

;; -----------------------------------------------------------------------
;; Group 3: Transparent Non-Blocking Send (synapse-send-named!)
;; -----------------------------------------------------------------------
(write-string "--- Group 3: Transparent Non-Blocking Send ---\n")
(flush-output-port)

(let* ((reg (make-process-registry))
       (ch (make-channel 10))
       (received-box (vector #f)))
  (synapse-register! reg 'echo_service ch)

  ;; Send to registered channel
  (assert-equal (synapse-send-named! reg 'echo_service 42) #t "synapse-send-named! sends 42 to channel")
  (assert-equal (channel-recv! ch) 42 "channel-recv! received 42")

  ;; Send multiple messages
  (synapse-send-named! reg 'echo_service "hello")
  (synapse-send-named! reg 'echo_service "world")
  (assert-equal (channel-recv! ch) "hello" "received first message")
  (assert-equal (channel-recv! ch) "world" "received second message")

  ;; Send to unregistered name returns 'not_found
  (assert-equal (synapse-send-named! reg 'ghost_service 999) 'not_found "sending to unregistered name returns 'not_found")

  ;; Close channel and test dead process detection
  (channel-close! ch)
  (assert-equal (synapse-send-named! reg 'echo_service 100) 'dead_process "sending to closed channel returns 'dead_process")

  ;; Procedure target test
  (synapse-register! reg 'callback_service (lambda (msg) (vector-set! received-box 0 msg)))
  (assert-equal (synapse-send-named! reg 'callback_service 777) #t "send to procedure target succeeds")
  (assert-equal (vector-ref received-box 0) 777 "procedure target received payload"))

;; -----------------------------------------------------------------------
;; Group 4: Supervisor Restart & Dynamic Rebind Integration
;; -----------------------------------------------------------------------
(write-string "--- Group 4: Supervisor Restart & Dynamic Rebind ---\n")
(flush-output-port)

(let* ((default-reg (current-synapse-registry))
       (task-counter (vector 0))
       ;; Child start thunk returns fresh task context each time
       (child-start (lambda ()
                      (vector-set! task-counter 0 (+ (vector-ref task-counter 0) 1))
                      (let ((t (make-task-context)))
                        t)))
       (cspec (make-child-spec 'worker_actor child-start 'permanent))
       (sspec (make-supervisor-spec 'one_for_one 5 1000 (list cspec)))
       (sup (make-supervisor sspec)))

  ;; Enable supervisor rebind hook
  (synapse-enable-supervisor-rebind!)

  ;; Start supervisor
  (assert-true (supervisor-start! sup) "supervisor-start! succeeds")

  ;; Verify initial task context is registered under 'worker_actor
  (let ((initial-task (synapse-whereis 'worker_actor)))
    (assert-true (task-context? initial-task) "initial-task satisfies task-context?")
    (let ((initial-tid (%task-tid initial-task)))
      (assert-true (integer? initial-tid) "initial TID is integer")

      ;; Simulate child crash and trigger supervisor down handler
      (supervisor-handle-child-down! sup initial-tid 'panic)

      ;; Verify child was restarted with NEW TID
        (let* ((restarted-task (synapse-whereis 'worker_actor))
               (new-tid (%task-tid restarted-task)))
          (assert-true (task-context? restarted-task) "restarted task satisfies task-context?")
          (assert-true (not (= initial-tid new-tid)) "restarted task has fresh distinct TID")
          (assert-equal (synapse-send-named! 'worker_actor 'ping) #t "synapse-send-named! routes to restarted task transparently"))))

  (supervisor-stop! sup))

;; -----------------------------------------------------------------------
;; Group 5: High-Throughput Concurrent Registration & Lookup
;; -----------------------------------------------------------------------
(write-string "--- Group 5: High-Throughput Registration & Lookup ---\n")
(flush-output-port)

(define (test-group-5-throughput!)
  (let* ((reg (make-process-registry 5000))
         (total-entries 1000))
    ;; Register 1,000 distinct symbol keys with boxed vector targets
    (let loop ((i 0))
      (if (< i total-entries)
          (let ((sym (string->symbol (string-append "proc_" (number->string i))))
                (box (vector i)))
            (synapse-register! reg sym box)
            (loop (+ i 1)))
          #t))

    (assert-equal (synapse-registry-count reg) 1000 "1,000 entries registered")

    ;; Lookup all 1,000 entries
    (let ((all-matched?
           (let loop ((i 0) (mismatches 0))
             (if (>= i total-entries)
                 (= mismatches 0)
                 (let* ((sym (string->symbol (string-append "proc_" (number->string i))))
                        (box (synapse-whereis reg sym))
                        (val (if (vector? box) (vector-ref box 0) -1))
                        (match? (= val i)))
                   (loop (+ i 1) (if match? mismatches (+ mismatches 1))))))))
      (assert-true all-matched? "all 1,000 entries resolved to exact values"))

    ;; Rebind all 1,000 entries to i + i
    (let loop ((i 0))
      (if (< i total-entries)
          (let* ((sym (string->symbol (string-append "proc_" (number->string i))))
                 (box (vector (+ i i))))
            (synapse-rebind! reg sym box)
            (loop (+ i 1)))
          #t))

    ;; Lookup rebound values
    (let ((all-rebound?
           (let loop ((i 0) (mismatches 0))
             (if (>= i total-entries)
                 (= mismatches 0)
                 (let* ((sym (string->symbol (string-append "proc_" (number->string i))))
                        (box (synapse-whereis reg sym))
                        (expected (+ i i))
                        (val (if (vector? box) (vector-ref box 0) -1))
                        (match? (= val expected)))
                   (loop (+ i 1) (if match? mismatches (+ mismatches 1))))))))
      (assert-true all-rebound? "all 1,000 entries resolved to updated rebound values"))

    ;; Clear all
    (synapse-registry-clear! reg)
    (assert-equal (synapse-registry-count reg) 0 "registry cleared back to 0")))

(test-group-5-throughput!)

;; -----------------------------------------------------------------------
;; Group 6: Security & Boundary Guards (CWE-843, CWE-400, CWE-833)
;; -----------------------------------------------------------------------
(write-string "--- Group 6: Security & Boundary Guards ---\n")
(flush-output-port)

(let ((reg (make-process-registry 2)))
  ;; CWE-843: Type validation
  (assert-error (lambda () (synapse-register! reg "not-a-symbol" 1))
                "synapse-register! rejects string name (CWE-843)")
  (assert-error (lambda () (synapse-register! reg 12345 1))
                "synapse-register! rejects integer name (CWE-843)")
  (assert-error (lambda () (synapse-register! reg 'valid_name #f))
                "synapse-register! rejects #f target (CWE-843)")
  (assert-error (lambda () (synapse-unregister! reg "not-a-symbol"))
                "synapse-unregister! rejects non-symbol name (CWE-843)")
  (assert-error (lambda () (synapse-whereis reg "not-a-symbol"))
                "synapse-whereis rejects non-symbol name (CWE-843)")
  (assert-error (lambda () (synapse-rebind! reg "not-a-symbol" 1))
                "synapse-rebind! rejects non-symbol name (CWE-843)")
  (assert-error (lambda () (synapse-rebind! reg 'valid_name #f))
                "synapse-rebind! rejects #f target (CWE-843)")
  (assert-error (lambda () (make-process-registry -5))
                "make-process-registry rejects negative capacity (CWE-400)")
  (assert-error (lambda () (make-process-registry "max"))
                "make-process-registry rejects non-integer capacity (CWE-843)")

  ;; CWE-400: Capacity limit bounding
  (assert-true (synapse-register! reg 'slot_1 100) "slot 1 registered")
  (assert-true (synapse-register! reg 'slot_2 200) "slot 2 registered")
  (assert-error (lambda () (synapse-register! reg 'slot_3 300))
                "synapse-register! rejects exceeding capacity limit (CWE-400)"))

;; -----------------------------------------------------------------------
;; Test Suite Summary
;; -----------------------------------------------------------------------
(write-string "=======================================================\n")
(write-string " Synapse Process Registry Summary: ")
(write-string (number->string (vector-ref *test-reg-passes* 0)))
(write-string " passed, ")
(write-string (number->string (vector-ref *test-reg-failures* 0)))
(write-string " failed.\n")
(write-string "=======================================================\n")
(flush-output-port)

(if (> (vector-ref *test-reg-failures* 0) 0)
    (error "test_registry: some assertions failed" (vector-ref *test-reg-failures* 0))
    #t)
