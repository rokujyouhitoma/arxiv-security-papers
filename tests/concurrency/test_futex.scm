;;; =======================================================================
;;; ULisp Concurrency Test Suite: Linux Futex Park / Unpark Primitives (#676)
;;; Conforms to DSN-37 Section 7.4.2 & Phase 7 Task 7.2
;;;
;;; Tests:
;;;   Group 1: Low-Level Futex Cell Allocation, Value Ops & Atomic CAS
;;;   Group 2: Direct futex-wait! Timeout (ETIMEDOUT) & Mismatch (EAGAIN)
;;;   Group 3: 3-State Park / Unpark Semantics (Lost Wakeup Free)
;;;   Group 4: Cross-Native-Thread Park / Unpark Synchronization
;;;   Group 5: Multiple Waiters and futex-unpark-all! Broadcast
;;;   Group 6: Scheduler Native Worker Idle Park & Rapid Spawn Wakeup
;;;   Group 7: Security & Boundary Guards (CWE-843 & CWE-416)
;;; =======================================================================

(load "ulisp/runtime/concurrency/atomic.scm")
(load "ulisp/runtime/concurrency/queue.scm")
(load "ulisp/runtime/concurrency/channel.scm")
(load "ulisp/runtime/concurrency/context.scm")
(load "ulisp/runtime/concurrency/deque.scm")
(load "ulisp/runtime/concurrency/thread.scm")
(load "ulisp/runtime/concurrency/futex.scm")
(load "ulisp/runtime/concurrency/scheduler.scm")

(define *test-futex-failures* (vector 0))
(define *test-futex-passes* (vector 0))

(define (assert-true val msg)
  (if (not val)
      (begin
        (vector-set! *test-futex-failures* 0 (+ (vector-ref *test-futex-failures* 0) 1))
        (write-string "FAIL: ")
        (write-string msg)
        (write-char #\newline)
        (flush-output-port)
        #f)
      (begin
        (vector-set! *test-futex-passes* 0 (+ (vector-ref *test-futex-passes* 0) 1))
        (write-string "PASS: ")
        (write-string msg)
        (write-char #\newline)
        (flush-output-port)
        #t)))

(define (assert-equal actual expected msg)
  (if (not (eqv? actual expected))
      (begin
        (vector-set! *test-futex-failures* 0 (+ (vector-ref *test-futex-failures* 0) 1))
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
        (vector-set! *test-futex-passes* 0 (+ (vector-ref *test-futex-passes* 0) 1))
        (write-string "PASS: ")
        (write-string msg)
        (write-char #\newline)
        (flush-output-port)
        #t)))

(define (assert-error thunk msg)
  (let ((caught
         (guard (exn (#t #t))
           (thunk)
           #f)))
    (assert-true caught msg)))

(write-string "=======================================================\n")
(write-string " Starting Linux Futex Park / Unpark Test Suite (#676) \n")
(write-string "=======================================================\n")
(flush-output-port)

;; -----------------------------------------------------------------------
;; Group 1: Low-Level Futex Cell Allocation, Value Ops & Atomic CAS
;; -----------------------------------------------------------------------
(write-string "--- Group 1: Futex Cell Allocation & Atomic CAS ---\n")
(flush-output-port)

(let ((cell (make-futex-cell 0)))
  (assert-true (futex-cell? cell) "make-futex-cell returns <futex-cell>")
  (assert-equal (futex-cell-ref cell) 0 "initial value is 0")
  
  (futex-cell-set! cell 42)
  (assert-equal (futex-cell-ref cell) 42 "futex-cell-set! updates value to 42")
  (assert-equal (futex-cell-value cell) 42 "futex-cell-value alias returns 42")

  ;; CAS success
  (assert-true (futex-cell-cas! cell 42 100) "futex-cell-cas! succeeds on expected match")
  (assert-equal (futex-cell-ref cell) 100 "futex-cell-ref reflects updated CAS value 100")

  ;; CAS failure
  (assert-true (not (futex-cell-cas! cell 42 200)) "futex-cell-cas! fails on mismatch")
  (assert-equal (futex-cell-ref cell) 100 "futex-cell-ref remains 100 after failed CAS")

  (assert-true (free-futex-cell! cell) "free-futex-cell! succeeds"))

;; -----------------------------------------------------------------------
;; Group 2: Direct futex-wait! Timeout (ETIMEDOUT) & Mismatch (EAGAIN)
;; -----------------------------------------------------------------------
(write-string "--- Group 2: futex-wait! Timeout & Mismatch ---\n")
(flush-output-port)

(let ((cell (make-futex-cell 10)))
  ;; Expected mismatch: current is 10, expected is 20 -> status 1 (EAGAIN)
  (let ((status (futex-wait! cell 20 50)))
    (assert-equal status 1 "futex-wait! returns 1 (EAGAIN) immediately on value mismatch"))

  ;; Expected match: current is 10, expected is 10, timeout 30ms -> status 2 (ETIMEDOUT)
  (let ((status (futex-wait! cell 10 30)))
    (assert-equal status 2 "futex-wait! returns 2 (ETIMEDOUT) on timer expiration"))

  (free-futex-cell! cell))

;; -----------------------------------------------------------------------
;; Group 3: 3-State Park / Unpark Semantics (Lost Wakeup Free)
;; -----------------------------------------------------------------------
(write-string "--- Group 3: 3-State Park / Unpark Semantics ---\n")
(flush-output-port)

(let ((cell (make-futex-cell 0)))
  ;; 1. Pre-notification token test: unpark BEFORE park
  ;; unpark sets NOTIFIED (2)
  (assert-true (futex-unpark! cell) "futex-unpark! sets NOTIFIED token")
  (assert-equal (futex-cell-ref cell) FUTEX_STATE_NOTIFIED "cell state is NOTIFIED (2)")

  ;; Subsequent park should NOT sleep and immediately return #t, resetting to EMPTY (0)
  (let ((park-res (futex-park! cell 1000)))
    (assert-true park-res "futex-park! consumes pre-existing NOTIFIED token without sleeping")
    (assert-equal (futex-cell-ref cell) FUTEX_STATE_EMPTY "cell state reset to EMPTY (0)"))

  ;; 2. Timeout park test
  (let ((timed-out? (futex-park! cell 25)))
    (assert-true (not timed-out?) "futex-park! returns #f on timeout")
    (assert-equal (futex-cell-ref cell) FUTEX_STATE_EMPTY "cell state is EMPTY after timeout"))

  (free-futex-cell! cell))

;; -----------------------------------------------------------------------
;; Group 4: Cross-Native-Thread Park / Unpark Synchronization
;; -----------------------------------------------------------------------
(write-string "--- Group 4: Cross-Thread Park / Unpark Sync ---\n")
(flush-output-port)

(let ((cell (make-futex-cell 0))
      (flag (make-atomic-box 0)))
  ;; Spawn worker thread that parks on futex
  (let ((tid (spawn-native-thread
              (lambda (arg)
                (futex-park! cell -1) ;; Block indefinitely until unparked
                (atomic-set! flag 1)
                (exit-native-thread! 0))
              0)))
    (assert-true (> tid 0) "spawned child thread for park test")

    ;; Wait for child thread to enter PARKED state (1)
    (let wait-park ((attempts 0))
      (if (or (= (futex-cell-ref cell) FUTEX_STATE_PARKED) (>= attempts 100000))
          #t
          (wait-park (+ attempts 1))))

    ;; Unpark the parked child thread
    (assert-true (futex-unpark! cell) "parent calls futex-unpark!")

    ;; Wait for child to complete and set flag to 1
    (let wait-flag ((spins 0))
      (if (or (= (atomic-ref flag) 1) (>= spins 10000000))
          #t
          (wait-flag (+ spins 1))))

    (assert-equal (atomic-ref flag) 1 "child thread was unparked and executed completion logic")
    (free-futex-cell! cell)))

;; -----------------------------------------------------------------------
;; Group 5: Multiple Waiters and futex-unpark-all! Broadcast
;; -----------------------------------------------------------------------
(write-string "--- Group 5: Broadcast Wakeup (futex-unpark-all!) ---\n")
(flush-output-port)

(let ((cell (make-futex-cell 0))
      (done1 (make-atomic-box 0))
      (done2 (make-atomic-box 0)))
  ;; Spawn thread 1
  (spawn-native-thread
   (lambda (arg)
     (futex-wait! cell 0 1000)
     (atomic-set! done1 1)
     (exit-native-thread! 0))
   0)

  ;; Spawn thread 2
  (spawn-native-thread
   (lambda (arg)
     (futex-wait! cell 0 1000)
     (atomic-set! done2 1)
     (exit-native-thread! 0))
   0)

  ;; Allow threads to start and enter futex-wait
  (let spin ((i 0)) (if (< i 500000) (spin (+ i 1)) #f))

  ;; Broadcast wake
  (assert-true (futex-unpark-all! cell) "futex-unpark-all! wakes all waiting threads")

  ;; Wait for both threads to finish
  (let wait-all ((spins 0))
    (if (or (and (= (atomic-ref done1) 1) (= (atomic-ref done2) 1)) (>= spins 10000000))
        #t
        (wait-all (+ spins 1))))

  (assert-equal (atomic-ref done1) 1 "worker 1 woken by broadcast")
  (assert-equal (atomic-ref done2) 1 "worker 2 woken by broadcast")
  (free-futex-cell! cell))

;; -----------------------------------------------------------------------
;; Group 6: Scheduler Native Worker Idle Park & Rapid Spawn Wakeup
;; -----------------------------------------------------------------------
(write-string "--- Group 6: Scheduler Worker Park / Unpark Integration ---\n")
(flush-output-port)

(let ((sched (make-work-stealing-scheduler 2)))
  (scheduler-enable-futex! sched)
  (let ((res (scheduler-start-native-workers! sched)))
    (assert-true res "scheduler native workers started with futex enabled")

    ;; Verify worker 1 has an allocated futex cell
    (let* ((w1 (scheduler-get-worker sched 1))
           (cell (worker-futex-cell w1)))
      (assert-true (futex-cell? cell) "worker 1 has valid <futex-cell>"))

    ;; Idle spin period: worker 1 enters futex-park!
    (let spin ((i 0)) (if (< i 1000000) (spin (+ i 1)) #f))

    ;; Spawn task: scheduler-spawn! should unpark worker 1
    (let ((task-executed (make-atomic-box 0)))
      (scheduler-spawn! sched
                        (lambda ()
                          (atomic-set! task-executed 777)))
      
      ;; Wait for worker to wake up and execute task
      (let wait-task ((spins 0))
        (if (or (= (atomic-ref task-executed) 777) (>= spins 10000000))
            #t
            (wait-task (+ spins 1))))

      (assert-equal (atomic-ref task-executed) 777 "idle worker woken by scheduler-spawn! and completed task"))

    ;; Stop scheduler: unparks all workers to gracefully shut down
    (assert-true (scheduler-stop! sched) "scheduler-stop! successfully unparked and stopped workers")))

;; -----------------------------------------------------------------------
;; Group 7: Security & Boundary Guards (CWE-843 & CWE-416)
;; -----------------------------------------------------------------------
(write-string "--- Group 7: Security & Boundary Guards ---\n")
(flush-output-port)

;; Type checking (CWE-843)
(assert-error (lambda () (make-futex-cell "bad-type"))
              "make-futex-cell rejects non-integer argument (CWE-843)")

(assert-error (lambda () (futex-cell-ref "not-a-cell"))
              "futex-cell-ref rejects non-<futex-cell> (CWE-843)")

(assert-error (lambda () (futex-park! 999))
              "futex-park! rejects non-<futex-cell> (CWE-843)")

(assert-error (lambda () (futex-unpark! #f))
              "futex-unpark! rejects non-<futex-cell> (CWE-843)")

;; Use-after-free prevention (CWE-416)
(let ((cell (make-futex-cell 0)))
  (free-futex-cell! cell)
  (assert-error (lambda () (futex-cell-ref cell))
                "futex-cell-ref rejects use-after-free on freed cell (CWE-416)")
  (assert-error (lambda () (futex-cell-set! cell 10))
                "futex-cell-set! rejects use-after-free on freed cell (CWE-416)")
  (assert-error (lambda () (futex-park! cell))
                "futex-park! rejects use-after-free on freed cell (CWE-416)")
  (assert-error (lambda () (futex-unpark! cell))
                "futex-unpark! rejects use-after-free on freed cell (CWE-416)"))

;; -----------------------------------------------------------------------
;; Summary
;; -----------------------------------------------------------------------
(write-string "=======================================================\n")
(write-string " Tests Passed: ")
(write-string (number->string (vector-ref *test-futex-passes* 0)))
(write-string " | Tests Failed: ")
(write-string (number->string (vector-ref *test-futex-failures* 0)))
(write-char #\newline)
(write-string "=======================================================\n")
(flush-output-port)

(if (> (vector-ref *test-futex-failures* 0) 0)
    (error "test_futex failed" (vector-ref *test-futex-failures* 0))
    #t)
