;;; =======================================================================
;;; Synapse Concurrency: OSAL (OS Abstraction Layer) Test Suite
;;; Conforms to DSN-37 Section 7.4, DSN-33-02 Section 7.2 (Issue #697)
;;;
;;; Tests:
;;;   Group 1: OSAL Platform Detection & Dynamic Override
;;;   Group 2: OSAL Threading Subsystem & CPU Topology
;;;   Group 3: OSAL Futex Cell Allocation, Value Ops & Atomic CAS
;;;   Group 4: 3-State Park / Unpark Semantics (CWE-833 Lost Wakeup Free)
;;;   Group 5: 10,000-Cycle High-Load Park / Unpark Stress Gate (0 Lost Wakeups)
;;;   Group 6: OSAL Event Loop Lifecycle & Notification Dispatch
;;;   Group 7: Cross-Platform Matrix Simulation (Darwin kqueue & Windows IOCP)
;;;   Group 8: Security Boundary & Exception Handling (CWE-843, CWE-400, CWE-416)
;;; =======================================================================

(load "ulisp/runtime/concurrency/atomic.scm")
(load "ulisp/runtime/concurrency/queue.scm")
(load "ulisp/runtime/concurrency/channel.scm")
(load "ulisp/runtime/concurrency/context.scm")
(load "ulisp/runtime/concurrency/deque.scm")
(load "ulisp/runtime/concurrency/thread.scm")
(load "ulisp/runtime/concurrency/futex.scm")
(load "ulisp/runtime/concurrency/io_uring.scm")
(load "ulisp/runtime/concurrency/io_kqueue.scm")
(load "ulisp/runtime/concurrency/osal.scm")

;; -----------------------------------------------------------------------
;; Test Harness Macros
;; -----------------------------------------------------------------------

(test-begin "concurrency-osal")

(define-syntax assert-true
  (syntax-rules ()
    ((assert-true val msg)
     (test-assert msg val))
    ((assert-true val)
     (test-assert "assert-true" val))))

(define-syntax assert-false
  (syntax-rules ()
    ((assert-false val msg)
     (test-assert msg (not val)))
    ((assert-false val)
     (test-assert "assert-false" (not val)))))

(define-syntax assert-eq
  (syntax-rules ()
    ((assert-eq actual expected msg)
     (test-equal msg expected actual))))

(define-syntax assert-equal
  (syntax-rules ()
    ((assert-equal actual expected msg)
     (test-equal msg expected actual))))

(define-syntax assert-error
  (syntax-rules ()
    ((assert-error thunk msg)
     (let ((caught
            (guard (exn (#t #t))
              (thunk)
              #f)))
       (test-assert msg caught)))))

;; -----------------------------------------------------------------------
;; Group 1: OSAL Platform Detection & Dynamic Override
;; -----------------------------------------------------------------------
(write-string "--- Group 1: Platform Detection & Dynamic Override ---\n")
(flush-output-port)

(let ((plat (osal-platform)))
  (assert-true (memq plat '(linux darwin windows generic)) "osal-platform returns valid symbol")
  (assert-true (string? (osal-platform-name)) "osal-platform-name returns descriptive string"))

;; Dynamic Override to Darwin
(osal-set-platform-override! 'darwin)
(assert-eq (osal-platform) 'darwin "platform successfully overridden to darwin")
(assert-true (string? (osal-platform-name)) "darwin platform name is valid string")

;; Dynamic Override to Windows
(osal-set-platform-override! 'windows)
(assert-eq (osal-platform) 'windows "platform successfully overridden to windows")

;; Dynamic Override to Generic
(osal-set-platform-override! 'generic)
(assert-eq (osal-platform) 'generic "platform successfully overridden to generic")

;; Reset Override to default
(osal-set-platform-override! #f)
(assert-true (memq (osal-platform) '(linux darwin windows generic)) "platform override reset to auto-detect")

;; Invalid override parameter (CWE-843)
(assert-error (lambda () (osal-set-platform-override! 'solaris)) "invalid platform override rejected")

;; -----------------------------------------------------------------------
;; Group 2: OSAL Threading Subsystem & CPU Topology
;; -----------------------------------------------------------------------
(write-string "--- Group 2: Threading Subsystem & CPU Topology ---\n")
(flush-output-port)

(assert-true (osal-thread-supported?) "osal-thread-supported? returns #t")
(assert-true (> (osal-cpu-count) 0) "osal-cpu-count returns positive integer")
(assert-true (osal-thread-yield) "osal-thread-yield succeeds")

;; Affinity verification
(assert-true (osal-set-affinity! 0 0) "affinity set on core 0 succeeds")
(assert-error (lambda () (osal-set-affinity! 0 -1)) "negative core-id rejected (CWE-20)")
(assert-error (lambda () (osal-set-affinity! 0 1024)) "core-id > 1023 rejected (CWE-20)")
(assert-error (lambda () (osal-set-affinity! "invalid" 0)) "invalid thread handle rejected (CWE-843)")

;; Thread spawning & completion
(let* ((completed-box (make-atomic-box #f))
       (t (osal-thread-spawn
           (lambda ()
             (atomic-set! completed-box #t)
             42)
           "test-worker")))
  (assert-true (osal-thread? t) "osal-thread-spawn returns <osal-thread>")
  (assert-true (> (osal-thread-id t) 0) "thread has positive TID")
  (assert-equal (osal-thread-name t) "test-worker" "thread has specified name")
  (assert-true (osal-thread-join! t 5000) "thread completed within timeout")
  (assert-true (atomic-ref completed-box) "thread thunk executed successfully")
  (assert-equal (osal-thread-state t) 'terminated "thread state is terminated")
  (assert-equal (osal-thread-exit-code t) 0 "thread exit code is 0"))

;; -----------------------------------------------------------------------
;; Group 3: OSAL Futex Cell Allocation, Value Ops & Atomic CAS
;; -----------------------------------------------------------------------
(write-string "--- Group 3: Futex Cell Allocation & Atomic CAS ---\n")
(flush-output-port)

(assert-true (osal-futex-supported?) "osal-futex-supported? returns #t")

(let ((cell (osal-make-futex-cell 0)))
  (assert-true (osal-futex-cell? cell) "osal-make-futex-cell returns <osal-futex-cell>")
  (assert-true (osal-futex-cell-active? cell) "new cell is active")
  (assert-equal (osal-futex-get cell) 0 "initial value is 0")

  (osal-futex-set! cell 100)
  (assert-equal (osal-futex-get cell) 100 "osal-futex-set! updates value to 100")

  ;; CAS Match
  (assert-true (osal-futex-cas! cell 100 200) "osal-futex-cas! succeeds on expected match")
  (assert-equal (osal-futex-get cell) 200 "value updated to 200")

  ;; CAS Mismatch
  (assert-false (osal-futex-cas! cell 100 300) "osal-futex-cas! fails on expected mismatch")
  (assert-equal (osal-futex-get cell) 200 "value remains 200 after failed CAS")

  ;; Free cell
  (assert-true (osal-free-futex-cell! cell) "osal-free-futex-cell! succeeds")
  (assert-false (osal-futex-cell-active? cell) "cell is marked inactive after free")

  ;; UAF Detection (CWE-416)
  (assert-error (lambda () (osal-futex-get cell)) "UAF on get rejected (CWE-416)")
  (assert-error (lambda () (osal-futex-set! cell 1)) "UAF on set! rejected (CWE-416)")
  (assert-error (lambda () (osal-futex-cas! cell 0 1)) "UAF on cas! rejected (CWE-416)"))

;; -----------------------------------------------------------------------
;; Group 4: 3-State Park / Unpark Semantics (CWE-833 Lost Wakeup Free)
;; -----------------------------------------------------------------------
(write-string "--- Group 4: 3-State Park / Unpark Semantics ---\n")
(flush-output-port)

;; Test 1: Immediate timeout when value matches
(let ((cell (osal-make-futex-cell 10)))
  (let ((status (osal-futex-wait! cell 10 0)))
    (assert-true (or (= status 0) (= status 2)) "timed wait returns 0 or 2 (ETIMEDOUT)"))
  (osal-free-futex-cell! cell))

;; Test 2: Immediate return (EAGAIN) when expected value mismatches
(let ((cell (osal-make-futex-cell 10)))
  (let ((status (osal-futex-wait! cell 20 50)))
    (assert-equal status 1 "futex-wait! returns 1 (EAGAIN) immediately on value mismatch"))
  (osal-free-futex-cell! cell))

;; Test 3: Unpark BEFORE Park (Wakeup Token Bypass)
;; Under standard 2-state futex, unpark before park causes Lost Wakeup (CWE-833).
;; Under 3-state CAS state machine, NOTIFIED (2) is set, allowing park to consume token instantly!
(let ((cell (osal-make-futex-cell 0)))
  ;; 1. Unpark first
  (assert-true (osal-futex-unpark! cell) "unpark prior to park succeeds")
  ;; 2. Park consumes NOTIFIED token (2 -> 0) without sleeping!
  (assert-true (osal-futex-park! cell 100) "park consumes prior token immediately")
  (assert-equal (osal-futex-get cell) 0 "cell state reset to EMPTY (0)")
  (osal-free-futex-cell! cell))

;; Test 4: Broadcast Wakeup (unpark-all!)
(let ((cell (osal-make-futex-cell 0)))
  (assert-true (osal-futex-unpark-all! cell) "osal-futex-unpark-all! succeeds")
  (assert-true (osal-futex-park! cell 50) "park consumes broadcast token immediately")
  (osal-free-futex-cell! cell))

;; -----------------------------------------------------------------------
;; Group 5: 10,000-Cycle High-Load Park / Unpark Stress Gate (0 Lost Wakeups)
;; -----------------------------------------------------------------------
(write-string "--- Group 5: 10,000-Cycle Park/Unpark Stress Gate ---\n")
(flush-output-port)

(let ((cell (osal-make-futex-cell 0))
      (iterations 10000))
  (let loop ((i 0) (lost-wakeups 0))
    (if (>= i iterations)
        (begin
          (assert-equal lost-wakeups 0 "10,000 park/unpark cycles completed with ZERO lost wakeups")
          (assert-equal (osal-futex-get cell) 0 "final cell state is EMPTY (0)"))
        (begin
          ;; Rapid alternate: unpark then park
          (osal-futex-unpark! cell)
          (let ((res (osal-futex-park! cell 10)))
            (if (not res)
                (loop (+ i 1) (+ lost-wakeups 1))
                (loop (+ i 1) lost-wakeups))))))
  (osal-free-futex-cell! cell))

;; -----------------------------------------------------------------------
;; Group 6: OSAL Event Loop Lifecycle & Notification Dispatch
;; -----------------------------------------------------------------------
(write-string "--- Group 6: Event Loop Lifecycle & Notification Dispatch ---\n")
(flush-output-port)

(let ((loop (osal-make-event-loop 64 'auto)))
  (assert-true (osal-event-loop? loop) "osal-make-event-loop returns <osal-event-loop>")
  (assert-true (osal-event-loop-active? loop) "event loop is active upon creation")
  (assert-equal (osal-event-loop-capacity loop) 64 "capacity is 64")

  ;; Register read & write events
  (assert-true (osal-event-register-read! loop 10 1001) "register read event succeeds")
  (assert-true (osal-event-register-write! loop 11 1002) "register write event succeeds")

  ;; Poll events
  (let ((events (osal-event-poll! loop 32 0)))
    (assert-true (list? events) "osal-event-poll! returns event list")
    (assert-true (>= (length events) 0) "received polled events"))

  ;; Stats inspection
  (let ((stats (osal-event-loop-stats loop)))
    (assert-true (list? stats) "stats returns alist")
    (assert-true (assq 'capacity stats) "stats contains capacity")
    (assert-true (assq 'active? stats) "stats contains active?"))

  ;; Close loop
  (assert-true (osal-event-loop-close! loop) "close loop succeeds")
  (assert-false (osal-event-loop-active? loop) "loop is marked inactive after close")
  (assert-false (osal-event-loop-close! loop) "double close returns #f idempotently")

  ;; Use-After-Close guards (CWE-416)
  (assert-error (lambda () (osal-event-register-read! loop 10 1)) "register on closed loop rejected")
  (assert-error (lambda () (osal-event-register-write! loop 10 1)) "register write on closed loop rejected")
  (assert-error (lambda () (osal-event-poll! loop 10 0)) "poll on closed loop rejected"))

;; -----------------------------------------------------------------------
;; Group 7: Cross-Platform Matrix Simulation (Darwin kqueue & Windows IOCP)
;; -----------------------------------------------------------------------
(write-string "--- Group 7: Cross-Platform Matrix Simulation ---\n")
(flush-output-port)

;; 7.1 macOS Darwin (kqueue & POSIX sync) Simulation
(osal-set-platform-override! 'darwin)
(assert-eq (osal-platform) 'darwin "switched to darwin platform mode")

(let ((kq-loop (osal-make-event-loop 64 'kqueue)))
  (assert-true (osal-event-loop? kq-loop) "kqueue event loop created")
  (assert-eq (osal-event-loop-backend kq-loop) 'kqueue "backend is kqueue")
  (assert-true (osal-event-register-read! kq-loop 3 5001) "register read on kqueue succeeds")
  (assert-true (osal-event-register-write! kq-loop 4 5002) "register write on kqueue succeeds")
  (let ((evs (osal-event-poll! kq-loop 10 0)))
    (assert-equal (length evs) 2 "polled 2 events from kqueue loop")
    (assert-equal (caar evs) 5001 "first event udata is 5001")
    (assert-equal (caadr evs) 5002 "second event udata is 5002"))
  (osal-event-loop-close! kq-loop))

(let ((d-cell (osal-make-futex-cell 0)))
  (assert-true (osal-futex-cell? d-cell) "darwin simulated futex cell created")
  (assert-true (osal-futex-unpark! d-cell) "darwin unpark succeeds")
  (assert-true (osal-futex-park! d-cell 10) "darwin park consumes token")
  (osal-free-futex-cell! d-cell))

;; 7.2 Windows Win32 (IOCP & WaitOnAddress) Simulation
(osal-set-platform-override! 'windows)
(assert-eq (osal-platform) 'windows "switched to windows platform mode")

(let ((win-loop (osal-make-event-loop 64 'iocp)))
  (assert-true (osal-event-loop? win-loop) "windows event loop created")
  (assert-eq (osal-event-loop-backend win-loop) 'iocp "backend is iocp")
  (assert-true (osal-event-register-read! win-loop 5 7001) "register read on windows loop succeeds")
  (let ((evs (osal-event-poll! win-loop 10 0)))
    (assert-equal (length evs) 1 "polled 1 event from windows loop")
    (assert-equal (caar evs) 7001 "event udata matches"))
  (osal-event-loop-close! win-loop))

(let ((w-cell (osal-make-futex-cell 0)))
  (assert-true (osal-futex-cell? w-cell) "windows WaitOnAddress futex cell created")
  (assert-true (osal-futex-unpark! w-cell) "windows unpark succeeds")
  (assert-true (osal-futex-park! w-cell 10) "windows park consumes token")
  (osal-free-futex-cell! w-cell))

;; 7.3 Generic Portable Mode
(osal-set-platform-override! 'generic)
(let ((gen-loop (osal-make-event-loop 32 'simulator)))
  (assert-true (osal-event-loop? gen-loop) "generic loop created")
  (osal-event-loop-close! gen-loop))

;; Restore auto-detect
(osal-set-platform-override! #f)

;; -----------------------------------------------------------------------
;; Group 8: Security Boundary & Exception Handling (CWE-843, CWE-400, CWE-416)
;; -----------------------------------------------------------------------
(write-string "--- Group 8: Security Boundary Guards ---\n")
(flush-output-port)

;; CWE-843 Type Confusion checks
(assert-error (lambda () (osal-futex-get "not-a-cell")) "invalid cell type rejected on get")
(assert-error (lambda () (osal-futex-set! "not-a-cell" 1)) "invalid cell type rejected on set!")
(assert-error (lambda () (osal-futex-cas! "not-a-cell" 0 1)) "invalid cell type rejected on cas!")
(assert-error (lambda () (osal-futex-park! "not-a-cell")) "invalid cell type rejected on park!")
(assert-error (lambda () (osal-futex-unpark! "not-a-cell")) "invalid cell type rejected on unpark!")
(assert-error (lambda () (osal-event-loop-active? "not-a-loop")) "invalid loop type rejected")
(assert-error (lambda () (osal-event-register-read! "not-a-loop" 1 0)) "invalid loop type on read reg")

;; CWE-400 Capacity Bounds checks
(assert-error (lambda () (osal-make-event-loop 0)) "zero capacity rejected (CWE-400)")
(assert-error (lambda () (osal-make-event-loop -1)) "negative capacity rejected (CWE-400)")
(assert-error (lambda () (osal-make-event-loop 5000)) "excessive capacity rejected (CWE-400)")

(test-end "concurrency-osal")
