;;; =======================================================================
;;; ULisp Concurrency Test: Fail-Fast "Let It Crash" Semantics (#668)
;;; Conforms to DSN-37 Section 8.4.4 & 14.8 Task 6.3
;;; =======================================================================

(load "ulisp/runtime/concurrency/atomic.scm")
(load "ulisp/runtime/concurrency/arena.scm")
(load "ulisp/runtime/concurrency/queue.scm")
(load "ulisp/runtime/concurrency/channel.scm")
(load "ulisp/runtime/concurrency/context.scm")
(load "ulisp/runtime/concurrency/deque.scm")
(load "ulisp/runtime/concurrency/thread.scm")
(load "ulisp/runtime/concurrency/links.scm")
(load "ulisp/runtime/concurrency/panic.scm")
(load "ulisp/runtime/concurrency/scheduler.scm")

;; -----------------------------------------------------------------------
;; Minimal Test Harness (Vector Boxes instead of top-level set!)
;; -----------------------------------------------------------------------

(define *tests-passed* (vector 0))
(define *tests-failed* (vector 0))

(define (assert-true expr msg)
  (if expr
      (begin
        (vector-set! *tests-passed* 0 (+ (vector-ref *tests-passed* 0) 1))
        (write-string "PASS: ")
        (write-string msg)
        (write-string "\n")
        (flush-output-port))
      (begin
        (vector-set! *tests-failed* 0 (+ (vector-ref *tests-failed* 0) 1))
        (write-string "FAIL: ")
        (write-string msg)
        (write-string "\n")
        (flush-output-port))))

(define (assert-eq a b msg)
  (assert-true (eq? a b) msg))

(define (assert-equal a b msg)
  (assert-true (equal? a b) msg))

;; -----------------------------------------------------------------------
;; Test Suite Execution
;; -----------------------------------------------------------------------

(write-string "=======================================================\n")
(write-string " Starting Synapse Let-It-Crash & Panic Test Suite (#668)\n")
(write-string "=======================================================\n")
(flush-output-port)

;; -----------------------------------------------------------------------
;; Group 1: Basic Panic Behavior & Zero-State Contamination Boundary
;; -----------------------------------------------------------------------
(write-string "--- Group 1: Basic Panic Behavior & Boundary Isolation ---\n")
(flush-output-port)

(let* ((t1 (make-task-context))
       (res-ok (with-synapse-task-boundary t1
                 (lambda ()
                   (+ 10 20)))))
  (assert-true (pair? res-ok) "normal execution returns pair")
  (assert-eq (car res-ok) 'ok "normal execution status is 'ok")
  (assert-equal (cdr res-ok) 30 "normal execution returns thunk value"))

(let* ((t2 (make-task-context))
       (side-effect (vector #f))
       (res-panic (with-synapse-task-boundary t2
                    (lambda ()
                      (vector-set! side-effect 0 'before-panic)
                      (synapse-panic! 'out-of-fuel "gas depleted" 42)
                      ;; Code below must NOT be reached
                      (vector-set! side-effect 0 'after-panic)
                      999))))
  (assert-true (pair? res-panic) "panic execution returns pair")
  (assert-eq (car res-panic) 'panic "panic execution status is 'panic")
  (assert-true (synapse-panic-record? (cdr res-panic)) "payload is <synapse-panic-record>")
  (assert-eq (synapse-panic-reason (cdr res-panic)) 'out-of-fuel "panic reason is 'out-of-fuel")
  (assert-equal (synapse-panic-details (cdr res-panic)) '("gas depleted" 42) "panic details match")
  (assert-eq (vector-ref side-effect 0) 'before-panic "code after panic is skipped")
  (assert-eq (task-state t2) 'terminated "task state transitioned to 'terminated"))

;; -----------------------------------------------------------------------
;; Group 2: Ephemeral Arena O(1) Instant Reset & Zero Leak
;; -----------------------------------------------------------------------
(write-string "--- Group 2: Ephemeral Arena O(1) Reset & Zero Leak ---\n")
(flush-output-port)

(let* ((t (make-task-context))
       (arena (make-task-arena 4096)))
  (task-set-arena! t arena)
  (assert-eq (task-arena t) arena "arena attached to task")
  ;; Allocate some memory inside arena
  (let ((addr1 (arena-allocate! arena 256)))
    (assert-true (> addr1 0) "first allocation in arena succeeds")
    (assert-true (> (arena-offset arena) 0) "arena offset is positive")
    (assert-eq (arena-reset-count arena) 0 "initial reset count is 0")

    ;; Run task that panics
    (let ((res (with-synapse-task-boundary t
                 (lambda ()
                   (arena-allocate! arena 512)
                   (synapse-panic! 'fatal-bad-data)))))
      (assert-eq (car res) 'panic "task panicked as expected")
      ;; Verify O(1) Arena instant reset
      (assert-eq (arena-offset arena) 0 "arena offset is reset to 0 in O(1)")
      (assert-eq (arena-chunk-count arena) 0 "arena chunks reset to 0")
      (assert-eq (arena-reset-count arena) 1 "arena-reset-count incremented to 1")

      ;; Verify clean re-allocation in reset arena
      (let ((addr2 (arena-allocate! arena 128)))
        (assert-true (> addr2 0) "re-allocation succeeds in reset arena")
        (assert-eq (arena-offset arena) 128 "offset reflects new allocation only")))))

;; -----------------------------------------------------------------------
;; Group 3: Automatic Channel Poisoning & Deadlock Elimination (CWE-833)
;; -----------------------------------------------------------------------
(write-string "--- Group 3: Automatic Channel Poisoning & Deadlock Elimination ---\n")
(flush-output-port)

(let* ((worker (make-task-context))
       (ch (make-channel 10)))
  (task-register-channel! worker ch)
  (assert-eq (channel-poisoned? ch) #f "channel initially not poisoned")

  (let ((res (with-synapse-task-boundary worker
               (lambda ()
                 (synapse-panic! 'connection-lost "socket closed unexpectedly")))))
    (assert-eq (car res) 'panic "worker panicked")
    ;; Channel must be poisoned
    (assert-eq (channel-poisoned? ch) #t "channel is poisoned on panic")
    (assert-eq (channel-closed? ch) #t "channel reports closed when poisoned")

    ;; Enqueue and Dequeue attempts must fail fast with 'poisoned
    (let ((send-res (channel-try-send! ch 'data))
          (recv-res (channel-try-recv-with-status! ch)))
      (assert-equal send-res (cons #f 'poisoned) "send on poisoned channel returns (cons #f 'poisoned)")
      (assert-equal recv-res (cons #f 'poisoned) "recv on poisoned channel returns (cons #f 'poisoned)"))))

;; -----------------------------------------------------------------------
;; Group 4: Assertion Guards & Fail-Fast Detection
;; -----------------------------------------------------------------------
(write-string "--- Group 4: Assertion Guards & Fail-Fast Detection ---\n")
(flush-output-port)

(let* ((t (make-task-context)))
  (let ((res-pass (with-synapse-task-boundary t
                    (lambda ()
                      (synapse-assert (= 10 10) "ten equals ten")
                      'ok-val))))
    (assert-eq (car res-pass) 'ok "assert true passes successfully")
    (assert-eq (cdr res-pass) 'ok-val "returns expected value"))

  (let ((res-fail (with-synapse-task-boundary t
                    (lambda ()
                      (synapse-assert (< 100 10) "100 must be less than 10" 'extra-metric 999)
                      'should-not-reach))))
    (assert-eq (car res-fail) 'panic "assert violation caught as panic")
    (assert-eq (synapse-panic-reason (cdr res-fail)) 'assertion-violation "reason is 'assertion-violation")
    (assert-true (pair? (synapse-panic-details (cdr res-fail))) "details present in assertion panic")
    (assert-equal (car (synapse-panic-details (cdr res-fail))) "100 must be less than 10" "assertion message matches")))

;; -----------------------------------------------------------------------
;; Group 5: Fault Signal Propagation (Links & Monitors Integration)
;; -----------------------------------------------------------------------
(write-string "--- Group 5: Links & Monitors Integration ---\n")
(flush-output-port)

;; 5.1 Monitor receives DOWN with panic reason
(let* ((observer (make-task-context))
       (worker (make-task-context))
       (m-ref (task-monitor observer worker)))
  (assert-true (integer? m-ref) "task-monitor returns ref")

  (let ((res (with-synapse-task-boundary worker
               (lambda ()
                 (synapse-panic! 'div-by-zero "zero divisor")))))
    (assert-eq (car res) 'panic "worker panicked")
    (assert-eq (task-state worker) 'terminated "worker is terminated")

    ;; Check observer received DOWN notification
    (let ((handoff (task-handoff observer)))
      (assert-true (pair? handoff) "observer has handoff notification")
      (assert-eq (car handoff) 'DOWN "message is 'DOWN")
      (assert-eq (cadr handoff) m-ref "monitor ref matches")
      (assert-eq (caddr handoff) 'process "subject is 'process")
      (assert-eq (cadddr handoff) (task-tid worker) "tid matches worker")
      (assert-equal (car (cddddr handoff)) '(panic . div-by-zero) "DOWN reason is '(panic . div-by-zero)"))))

;; 5.2 Linked task with trap-exit receives EXIT signal
(let* ((supervisor (make-task-context))
       (child (make-task-context)))
  (task-trap-exit! supervisor #t)
  (task-link! supervisor child)
  (assert-true (task-linked? supervisor child) "supervisor and child linked")

  (let ((res (with-synapse-task-boundary child
               (lambda ()
                 (synapse-panic! 'worker-crashed)))))
    (assert-eq (car res) 'panic "child panicked")
    (assert-eq (task-state supervisor) 'ready "supervisor survives due to trap-exit")
    (let ((sig (task-handoff supervisor)))
      (assert-true (pair? sig) "supervisor has EXIT message")
      (assert-eq (car sig) 'EXIT "signal type is 'EXIT")
      (assert-eq (cadr sig) (task-tid child) "signal from child tid")
      (assert-equal (caddr sig) '(panic . worker-crashed) "signal reason is '(panic . worker-crashed)"))))

;; -----------------------------------------------------------------------
;; Group 6: Security Guards & CWE-212 Memory Scrubbing
;; -----------------------------------------------------------------------
(write-string "--- Group 6: Security Guards & CWE-212 Memory Scrubbing ---\n")
(flush-output-port)

;; 6.1 Secure Scrubbing Zero-out
(let* ((t (make-task-context))
       (arena (make-task-arena 1024)))
  (task-set-arena! t arena)
  ;; Write sensitive pattern into arena buffer
  (let ((buf (arena-buffer arena)))
    (bytevector-u8-set! buf 0 255)
    (bytevector-u8-set! buf 1 170)
    (bytevector-u8-set! buf 10 187)
    (arena-offset-set! arena 64)

    (let ((res (with-synapse-task-boundary t
                 (lambda ()
                   (synapse-secure-panic! 'key-compromised "wiping memory"))
                 #t)))
      (assert-eq (car res) 'panic "secure panic executed")
      (assert-eq (arena-offset arena) 0 "arena offset reset")
      ;; Verify sensitive bytes are zero-scrubbed (CWE-212 mitigation)
      (assert-eq (bytevector-u8-ref buf 0) 0 "byte 0 scrubbed to 0")
      (assert-eq (bytevector-u8-ref buf 1) 0 "byte 1 scrubbed to 0")
      (assert-eq (bytevector-u8-ref buf 10) 0 "byte 10 scrubbed to 0"))))

;; 6.2 CWE-843 Type Confusion Guards
(let ((good-task (make-task-context)))
  (assert-true (guard (exn (else #t)) (with-synapse-task-boundary "invalid-task" (lambda () 123)) #f)
               "with-synapse-task-boundary rejects non-task (CWE-843)")
  (assert-true (guard (exn (else #t)) (with-synapse-task-boundary good-task "not-a-procedure") #f)
               "with-synapse-task-boundary rejects non-procedure (CWE-843)")
  (assert-true (guard (exn (else #t)) (synapse-cleanup-task-resources! "bad-task" 'err) #f)
               "synapse-cleanup-task-resources! rejects non-task (CWE-843)"))

;; -----------------------------------------------------------------------
;; Group 7: Per-Worker TLS Isolation of Handler Chain & Current Task (#719)
;; -----------------------------------------------------------------------
(write-string "--- Group 7: Per-Worker TLS Isolation (#719) ---\n")
(flush-output-port)

(let* ((t-w0 (make-task-context))
       (t-w1 (make-task-context))
       (w1-done (make-atomic-box #f))
       (w1-tid-seen (make-atomic-box #f))
       (w1-caught (make-atomic-box #f))
       (w0-tid-seen (make-atomic-box #f))
       (w0-caught (make-atomic-box #f)))
  (with-synapse-task-boundary t-w0
    (lambda ()
      (guard (ex0 (#t (atomic-set! w0-caught ex0)))
        (spawn-native-thread
         (lambda (arg)
           (with-synapse-task-boundary t-w1
             (lambda ()
               (guard (ex1 (#t (atomic-set! w1-caught ex1)))
                 (atomic-set! w1-tid-seen (task-tid (current-synapse-task)))
                 (raise 'worker1-exn)))
             #f)
           (atomic-set! w1-done #t))
         0)
        (let wait-loop ((spins 0))
          (if (and (not (atomic-ref w1-done)) (< spins 5000000))
              (wait-loop (+ spins 1))
              #t))
        (atomic-set! w0-tid-seen (task-tid (current-synapse-task)))
        (raise 'worker0-exn)))
    #f)
  (assert-eq (atomic-ref w1-tid-seen) (task-tid t-w1) "worker 1 TLS current-synapse-task is t-w1")
  (assert-eq (atomic-ref w0-tid-seen) (task-tid t-w0) "worker 0 TLS current-synapse-task remained t-w0 without interference")
  (assert-eq (atomic-ref w1-caught) 'worker1-exn "worker 1 TLS handler chain caught 'worker1-exn")
  (assert-eq (atomic-ref w0-caught) 'worker0-exn "worker 0 TLS handler chain caught 'worker0-exn"))

;; -----------------------------------------------------------------------
;; Group 8: Task Exception Boundary with-exception-handler & Scheduler Integration (#720)
;; -----------------------------------------------------------------------
(write-string "--- Group 8: Task Exception Boundary & Scheduler Connection (#720) ---\n")
(flush-output-port)

;; 8.1 error caught inside with-synapse-task-boundary
(let* ((t-err (make-task-context))
       (res (with-synapse-task-boundary t-err
              (lambda ()
                (error "boom-error" 123)))))
  (assert-eq (car res) 'panic "R7RS (error ...) caught as task panic")
  (assert-true (synapse-panic-record? (cdr res)) "error produces <synapse-panic-record>")
  (assert-eq (synapse-panic-reason (cdr res)) 'error "error panic reason is 'error")
  (assert-eq (task-state t-err) 'terminated "task state is 'terminated after error"))

;; 8.2 raise caught inside with-synapse-task-boundary
(let* ((t-raise (make-task-context))
       (res (with-synapse-task-boundary t-raise
              (lambda ()
                (raise 'custom-exception-payload)))))
  (assert-eq (car res) 'panic "R7RS (raise ...) caught as task panic")
  (assert-true (synapse-panic-record? (cdr res)) "raise produces <synapse-panic-record>")
  (assert-eq (synapse-panic-reason (cdr res)) 'unhandled-exception "raise panic reason is 'unhandled-exception")
  (assert-equal (synapse-panic-details (cdr res)) '(custom-exception-payload) "raise panic details preserved")
  (assert-eq (task-state t-raise) 'terminated "task state is 'terminated after raise"))

;; 8.3 (car '()) and (cdr '()) caught inside with-synapse-task-boundary
(let* ((t-car (make-task-context))
       (empty-ls '())
       (res-car (with-synapse-task-boundary t-car
                  (lambda ()
                    (car empty-ls))))
       (t-cdr (make-task-context))
       (res-cdr (with-synapse-task-boundary t-cdr
                  (lambda ()
                    (cdr empty-ls)))))
  (assert-eq (car res-car) 'panic "(car '()) caught as task panic without SIGSEGV")
  (assert-eq (task-state t-car) 'terminated "t-car state is 'terminated")
  (assert-eq (car res-cdr) 'panic "(cdr '()) caught as task panic without SIGSEGV")
  (assert-eq (task-state t-cdr) 'terminated "t-cdr state is 'terminated"))

;; 8.4 scheduler-execute-task! and scheduler-run! isolate crashing tasks
(let* ((sched (make-work-stealing-scheduler 2 64))
       (survivor-box (make-atomic-box 0))
       (bad-task (make-task-context))
       (good-task (make-task-context)))
  (task-next-run-set! bad-task (lambda () (car '())))
  (task-next-run-set! good-task (lambda () (atomic-fetch-add! survivor-box 10)))
  (scheduler-spawn! sched bad-task 0)
  (scheduler-spawn! sched (lambda () (error "thunk-boom")) 0)
  (scheduler-spawn! sched (lambda () (raise 'raw-raise)) 1)
  (scheduler-spawn! sched good-task 1)
  (scheduler-spawn! sched (lambda () (atomic-fetch-add! survivor-box 32)) 0)
  (scheduler-run! sched 5)
  (assert-eq (task-state bad-task) 'terminated "bad-task running (car '()) terminated cleanly in scheduler")
  (assert-eq (atomic-ref survivor-box) 42 "unrelated tasks completed normally despite sibling crashes")
  (scheduler-stop! sched))

;; -----------------------------------------------------------------------
;; Group 9: Arena Overflow Separation into Task-Local synapse-panic! (#721)
;; -----------------------------------------------------------------------
(write-string "--- Group 9: Arena Overflow Task-Local synapse-panic! (#721) ---\n")
(flush-output-port)

(let* ((overflow-task (make-task-context))
       (arena (make-task-arena 2048))
       (survivor-task (make-task-context))
       (survivor-ran (make-atomic-box #f)))
  (arena-max-chunks-set! arena 2)
  (task-set-arena! overflow-task arena)
  (let ((res (with-synapse-task-boundary overflow-task
               (lambda ()
                 (arena-allocate! arena 2048) ; fills primary
                 (arena-allocate! arena 8192) ; chunk 1
                 (arena-allocate! arena 8192) ; chunk 2
                 ;; Next allocation exceeds max-chunks=2 -> triggers task-local synapse-panic! 'arena-overflow
                 (arena-allocate! arena 64)
                 'unreachable))))
    (assert-eq (car res) 'panic "arena overflow triggers task panic")
    (assert-true (synapse-panic-record? (cdr res)) "arena overflow returns <synapse-panic-record>")
    (assert-eq (synapse-panic-reason (cdr res)) 'arena-overflow "arena overflow panic reason is 'arena-overflow (not generic 'error)")
    (assert-eq (task-state overflow-task) 'terminated "overflow-task transitioned to 'terminated")
    (assert-eq (arena-offset arena) 0 "overflowing task's arena was O(1) reset to offset 0")
    (assert-eq (arena-chunk-count arena) 0 "overflowing task's arena chunks were reclaimed to 0"))
  ;; Verify sibling task runs unaffected
  (let ((res2 (with-synapse-task-boundary survivor-task
                (lambda ()
                  (atomic-set! survivor-ran #t)
                  'survived))))
    (assert-eq (car res2) 'ok "sibling task after arena-overflow panic succeeds")
    (assert-eq (atomic-ref survivor-ran) #t "sibling task body executed normally")))

;; -----------------------------------------------------------------------
;; Final Summary
;; -----------------------------------------------------------------------

(write-string "=======================================================\n")
(write-string " Synapse Let-It-Crash & Panic Summary: ")
(write-string (number->string (vector-ref *tests-passed* 0)))
(write-string " passed, ")
(write-string (number->string (vector-ref *tests-failed* 0)))
(write-string " failed.\n")
(write-string "=======================================================\n")
(flush-output-port)

(if (> (vector-ref *tests-failed* 0) 0)
    (sys-exit 1)
    (sys-exit 0))
