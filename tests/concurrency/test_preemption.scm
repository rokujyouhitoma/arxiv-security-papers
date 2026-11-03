;;; =======================================================================
;;; ULisp Concurrency Test Suite: Reduction Safepoint & Preemption (#636)
;;; Tests:
;;;   Group 1: Reduction Accounting & Task State Accessors
;;;   Group 2: Reduction Consumption, Underflow Clamping & Replenishment
;;;   Group 3: Safepoint Polling & Automatic Preemption Callback
;;;   Group 4: Scheduler Integration & Starvation Freedom
;;;   Group 5: Coroutine Cooperative Preemptive Context Switching
;;;   Group 6: 100,000 Reductions High-Throughput Safepoint Endurance
;;;   Group 7: Security & Boundary Guards (CWE-190 / CWE-400 / CWE-843)
;;; =======================================================================

(load "ulisp/runtime/concurrency/channel.scm")
(load "ulisp/runtime/concurrency/context.scm")
(load "ulisp/runtime/concurrency/deque.scm")
(load "ulisp/runtime/concurrency/thread.scm")
(load "ulisp/runtime/concurrency/scheduler.scm")
(load "ulisp/runtime/concurrency/preempt.scm")

(define *test-preempt-failures* (vector 0))
(define *test-preempt-passes* (vector 0))

(define (assert-true val msg)
  (if (not val)
      (begin
        (vector-set! *test-preempt-failures* 0 (+ (vector-ref *test-preempt-failures* 0) 1))
        (write-string "FAIL: ")
        (write-string msg)
        (write-char #\newline)
        (flush-output-port)
        #f)
      (begin
        (vector-set! *test-preempt-passes* 0 (+ (vector-ref *test-preempt-passes* 0) 1))
        (write-string "PASS: ")
        (write-string msg)
        (write-char #\newline)
        (flush-output-port)
        #t)))

(define (assert-equal actual expected msg)
  (if (not (eqv? actual expected))
      (begin
        (vector-set! *test-preempt-failures* 0 (+ (vector-ref *test-preempt-failures* 0) 1))
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
        (vector-set! *test-preempt-passes* 0 (+ (vector-ref *test-preempt-passes* 0) 1))
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
    (if caught
        (begin
          (vector-set! *test-preempt-passes* 0 (+ (vector-ref *test-preempt-passes* 0) 1))
          (write-string "PASS: ")
          (write-string msg)
          (write-char #\newline)
          (flush-output-port)
          #t)
        (begin
          (vector-set! *test-preempt-failures* 0 (+ (vector-ref *test-preempt-failures* 0) 1))
          (write-string "FAIL (expected error): ")
          (write-string msg)
          (write-char #\newline)
          (flush-output-port)
          #f))))

(write-string "=======================================================\n")
(write-string " Starting Reduction Safepoint & Preemption Test Suite (#636)\n")
(write-string "=======================================================\n")

;; -----------------------------------------------------------------------
;; Group 1: Reduction Accounting & Task State Accessors
;; -----------------------------------------------------------------------
(write-string "--- Group 1: Reduction Accounting & Task State Accessors ---\n")

(define dummy-fn (lambda () 42))
(define t-def (make-budgeted-task 1 dummy-fn))
(define t-100 (make-budgeted-task 2 dummy-fn 100))

(assert-true (budgeted-task? t-def) "default task satisfies budgeted-task?")
(assert-true (budgeted-task? t-100) "100-budget task satisfies budgeted-task?")
(assert-true (not (budgeted-task? 123)) "fixnum is not budgeted-task?")
(assert-true (not (budgeted-task? (vector 1 2 3))) "raw vector is not budgeted-task?")

(assert-equal (task-id t-def) 1 "t-def id is 1")
(assert-equal (task-id t-100) 2 "t-100 id is 2")
(assert-equal (task-initial-budget t-def) 4096 "default initial budget is 4096")
(assert-equal (task-initial-budget t-100) 100 "custom initial budget is 100")
(assert-equal (task-reductions t-def) 4096 "initial remaining reductions equal initial budget")
(assert-equal (task-reductions t-100) 100 "custom remaining reductions equal 100")
(assert-equal (task-exhaustion-count t-def) 0 "initial exhaustion count is 0")
(assert-equal (task-state t-def) 'ready "initial task state is 'ready")
(assert-true (not (task-exhausted? t-def)) "fresh task is not exhausted")

(task-state-set! t-def 'running)
(assert-equal (task-state t-def) 'running "task-state-set! transitions state to 'running")

(task-reductions-set! t-def 2000)
(assert-equal (task-reductions t-def) 2000 "task-reductions-set! updates reductions")

(let ((stats-1 (budgeted-task-stats t-def)))
  (assert-true (pair? stats-1) "budgeted-task-stats returns non-empty list")
  (assert-equal (cdr (assq 'id stats-1)) 1 "stats id is 1")
  (assert-equal (cdr (assq 'initial-budget stats-1)) 4096 "stats initial-budget is 4096")
  (assert-equal (cdr (assq 'remaining stats-1)) 2000 "stats remaining reductions is 2000"))

;; -----------------------------------------------------------------------
;; Group 2: Reduction Consumption, Underflow Clamping & Replenishment
;; -----------------------------------------------------------------------
(write-string "--- Group 2: Reduction Consumption & Replenishment ---\n")

(define t-sub (make-budgeted-task 10 dummy-fn 10))

(assert-equal (task-consume-reductions! t-sub) 9 "task-consume-reductions! default 1 decr to 9")
(assert-equal (task-consume-reductions! t-sub 4) 5 "task-consume-reductions! delta 4 decr to 5")
(assert-equal (task-reductions t-sub) 5 "task-reductions reflects 5 remaining")
(assert-true (not (task-exhausted? t-sub)) "task not yet exhausted at 5")

(assert-equal (task-consume-reductions! t-sub 5) 0 "consuming exact 5 reductions leaves 0")
(assert-true (task-exhausted? t-sub) "task is exhausted when reductions reaches 0")

(assert-equal (task-consume-reductions! t-sub 10) 0 "underflow consumption clamps to 0")
(assert-true (task-exhausted? t-sub) "task remains exhausted after underflow")

(assert-equal (task-replenish! t-sub) 10 "task-replenish! resets reductions to initial budget")
(assert-equal (task-reductions t-sub) 10 "task-reductions is 10 after replenish")
(assert-equal (task-exhaustion-count t-sub) 1 "task-exhaustion-count is incremented to 1")
(assert-true (not (task-exhausted? t-sub)) "task is no longer exhausted after replenish")

(task-replenish! t-sub)
(assert-equal (task-exhaustion-count t-sub) 2 "consecutive replenish increments exhaustion count to 2")

;; -----------------------------------------------------------------------
;; Group 3: Safepoint Polling & Automatic Preemption Callback
;; -----------------------------------------------------------------------
(write-string "--- Group 3: Safepoint Polling & Preemption Callback ---\n")

(define t-poll (make-budgeted-task 20 dummy-fn 5))
(define callback-count (vector 0))

(define on-exhaust (lambda ()
                     (vector-set! callback-count 0 (+ (vector-ref callback-count 0) 1))))

;; 4 normal ticks: reductions go from 5 to 1
(assert-true (check-safepoint! t-poll on-exhaust) "tick 1 returns #t (4 remaining)")
(assert-true (check-safepoint! t-poll on-exhaust) "tick 2 returns #t (3 remaining)")
(assert-true (check-safepoint! t-poll on-exhaust) "tick 3 returns #t (2 remaining)")
(assert-true (check-safepoint! t-poll on-exhaust) "tick 4 returns #t (1 remaining)")
(assert-equal (vector-ref callback-count 0) 0 "callback not triggered before exhaustion")

;; 5th tick: triggers exhaustion and calls on-exhaust
(check-safepoint! t-poll on-exhaust)
(assert-equal (vector-ref callback-count 0) 1 "callback triggered exactly on 5th tick")
(assert-equal (task-exhaustion-count t-poll) 1 "task exhaustion count is 1")
(assert-equal (task-reductions t-poll) 5 "task-reductions automatically replenished to 5")

;; Loop with 4096-budget task: exactly 1 preemption in 4096 iterations
(define t-beam (make-budgeted-task 21 dummy-fn 4096))
(define beam-exhaustions (vector 0))
(define beam-cb (lambda ()
                  (vector-set! beam-exhaustions 0 (+ (vector-ref beam-exhaustions 0) 1))))

(let loop ((i 0))
  (if (< i 4096)
      (begin
        (check-safepoint! t-beam beam-cb)
        (loop (+ i 1)))
      #t))

(assert-equal (vector-ref beam-exhaustions 0) 1 "4096-budget task triggered exact 1 callback in 4096 ticks")
(assert-equal (task-exhaustion-count t-beam) 1 "task exhaustion count is 1 after 4096 ticks")

;; Loop with 20,480 iterations (4096 * 5)
(let loop ((i 0))
  (if (< i (* 4096 4)) ; 4 more full budgets
      (begin
        (check-safepoint! t-beam beam-cb)
        (loop (+ i 1)))
      #t))

(assert-equal (vector-ref beam-exhaustions 0) 5 "total 5 preemption callbacks after 20,480 ticks")
(assert-equal (task-exhaustion-count t-beam) 5 "task exhaustion count is exactly 5")

;; -----------------------------------------------------------------------
;; Group 4: Scheduler Integration & Starvation Freedom
;; -----------------------------------------------------------------------
(write-string "--- Group 4: Scheduler Integration & Starvation Freedom ---\n")

(define sched (make-work-stealing-scheduler 2))
(define task-a-loops (vector 0))
(define task-b-done (vector #f))
(define max-loop-target 50000)

;; Task A: CPU-bound loop with safepoints triggering scheduler-yield!
(define task-a-box (vector #f))

(define task-a-proc
  (lambda ()
    (let loop ()
      (let ((cnt (vector-ref task-a-loops 0)))
        (if (< cnt max-loop-target)
            (begin
              (vector-set! task-a-loops 0 (+ cnt 1))
              (check-safepoint!
               (vector-ref task-a-box 0)
               (lambda ()
                 (scheduler-yield! (vector-ref task-a-box 0) sched)))
              (loop))
            #t)))))

(define btask-a (make-budgeted-task 101 task-a-proc 500))
(vector-set! task-a-box 0 btask-a)

;; Task B: Finite, short task that must not be starved by Task A
(define task-b-proc
  (lambda ()
    (vector-set! task-b-done 0 #t)
    #t))

(define btask-b (make-budgeted-task 102 task-b-proc 1000))

;; Spawn both tasks into worker 0's local queue
(scheduler-spawn! sched btask-a 0)
(scheduler-spawn! sched btask-b 0)

;; Run scheduler until tasks complete
(scheduler-run! sched 2000)

(assert-true (vector-ref task-b-done 0) "Task B was NOT starved and completed successfully")
(assert-true (> (vector-ref task-a-loops 0) 0) "Task A made computational progress")
(assert-true (> (task-exhaustion-count btask-a) 0) "Task A incurred multiple preemptive yields")

(scheduler-stop! sched)

;; -----------------------------------------------------------------------
;; Group 5: Coroutine Cooperative Preemptive Context Switching
;; -----------------------------------------------------------------------
(write-string "--- Group 5: Coroutine Cooperative Preemptive Context Switching ---\n")

(define coro-runs (vector 0))
(define coro-task-box (vector #f))

(define coro-target
  (lambda ()
    (let loop ((i 0))
      (if (< i 30)
          (begin
            (vector-set! coro-runs 0 (+ (vector-ref coro-runs 0) 1))
            (check-safepoint!
             (vector-ref coro-task-box 0)
             (lambda ()
               (scheduler-yield! (vector-ref coro-task-box 0))))
            (loop (+ i 1)))
          'coro-finished))))

(define test-coro (make-coroutine-context coro-target 8192))
(define btask-coro (make-budgeted-task 201 test-coro 10))
(vector-set! coro-task-box 0 btask-coro)

;; Step 1: runs 10 ticks (0..9) -> 1st preemption yield
(assert-equal (task-state btask-coro) 'ready "initial coro state is 'ready")
(budgeted-task-execute! btask-coro)
(assert-equal (vector-ref coro-runs 0) 10 "coro ran 10 iterations on step 1")
(assert-equal (task-state btask-coro) 'yielded "coro state transitioned to 'yielded on exhaustion")
(assert-equal (task-exhaustion-count btask-coro) 1 "coro incurred 1 exhaustion")

;; Step 2: runs 10 ticks (10..19) -> 2nd preemption yield
(budgeted-task-execute! btask-coro)
(assert-equal (vector-ref coro-runs 0) 20 "coro ran 20 cumulative iterations on step 2")
(assert-equal (task-state btask-coro) 'yielded "coro state is 'yielded on step 2")
(assert-equal (task-exhaustion-count btask-coro) 2 "coro incurred 2 exhaustions")

;; Step 3: runs 10 ticks (20..29) -> 3rd preemption yield
(budgeted-task-execute! btask-coro)
(assert-equal (vector-ref coro-runs 0) 30 "coro ran 30 cumulative iterations on step 3")
(assert-equal (task-state btask-coro) 'yielded "coro state is 'yielded on step 3")
(assert-equal (task-exhaustion-count btask-coro) 3 "coro incurred 3 exhaustions")

;; Step 4: loop terminates (i = 30) and returns 'coro-finished -> completes
(budgeted-task-execute! btask-coro)
(assert-equal (vector-ref coro-runs 0) 30 "coro ran exactly 30 total loop iterations")
(assert-equal (task-state btask-coro) 'completed "coro state transitioned to 'completed")

(free-coroutine-context! test-coro)

;; -----------------------------------------------------------------------
;; Group 6: 100,000 Reductions High-Throughput Safepoint Endurance
;; -----------------------------------------------------------------------
(write-string "--- Group 6: 100,000 Reductions Safepoint Endurance ---\n")

(define t-endurance (make-budgeted-task 301 dummy-fn 1000))
(define endurance-exhaustions (vector 0))
(define endurance-cb (lambda ()
                       (vector-set! endurance-exhaustions 0 (+ (vector-ref endurance-exhaustions 0) 1))))

(let loop ((i 0))
  (if (< i 100000)
      (begin
        (check-safepoint! t-endurance endurance-cb)
        (loop (+ i 1)))
      #t))

(assert-equal (vector-ref endurance-exhaustions 0) 100 "100,000 ticks with 1000 budget produced exact 100 preemption callbacks")
(assert-equal (task-exhaustion-count t-endurance) 100 "task exhaustion count is exactly 100")
(assert-equal (task-reductions t-endurance) 1000 "reductions correctly replenished to 1000")

;; -----------------------------------------------------------------------
;; Group 7: Security & Boundary Guards (CWE-190 / CWE-400 / CWE-843)
;; -----------------------------------------------------------------------
(write-string "--- Group 7: Security & Boundary Guards ---\n")

(assert-error (lambda () (make-budgeted-task "not-int" dummy-fn))
              "make-budgeted-task rejects non-integer id (CWE-843)")

(assert-error (lambda () (make-budgeted-task 1 dummy-fn 0))
              "make-budgeted-task rejects budget 0 (CWE-190)")

(assert-error (lambda () (make-budgeted-task 1 dummy-fn -50))
              "make-budgeted-task rejects negative budget (CWE-190)")

(assert-error (lambda () (make-budgeted-task 1 dummy-fn "500"))
              "make-budgeted-task rejects non-integer budget (CWE-843)")

(assert-error (lambda () (make-budgeted-task 1 dummy-fn 2000000))
              "make-budgeted-task rejects oversized budget > 1M (CWE-400)")

(assert-error (lambda () (task-reductions 12345))
              "task-reductions rejects non-budgeted-task (CWE-843)")

(assert-error (lambda () (task-reductions-set! 12345 100))
              "task-reductions-set! rejects non-budgeted-task (CWE-843)")

(assert-error (lambda () (task-reductions-set! t-def "invalid"))
              "task-reductions-set! rejects non-integer reductions (CWE-843)")

(assert-error (lambda () (task-consume-reductions! 12345))
              "task-consume-reductions! rejects non-budgeted-task (CWE-843)")

(assert-error (lambda () (task-consume-reductions! t-def -10))
              "task-consume-reductions! rejects negative delta (CWE-190)")

(assert-error (lambda () (task-replenish! 12345))
              "task-replenish! rejects non-budgeted-task (CWE-843)")

(assert-error (lambda () (check-safepoint! 12345))
              "check-safepoint! rejects non-budgeted-task (CWE-843)")

(assert-error (lambda () (scheduler-yield! 12345))
              "scheduler-yield! rejects non-budgeted-task (CWE-843)")

(assert-error (lambda () (budgeted-task-execute! 12345))
              "budgeted-task-execute! rejects non-budgeted-task (CWE-843)")

(assert-error (lambda () (budgeted-task-stats 12345))
              "budgeted-task-stats rejects non-budgeted-task (CWE-843)")

;; -----------------------------------------------------------------------
;; Summary
;; -----------------------------------------------------------------------
(write-string "=======================================================\n")
(write-string " Preemption & Reduction Safepoint Test Summary: ")
(write-string (number->string (vector-ref *test-preempt-passes* 0)))
(write-string " passed, ")
(write-string (number->string (vector-ref *test-preempt-failures* 0)))
(write-string " failed.\n")
(write-string "=======================================================\n")

(if (> (vector-ref *test-preempt-failures* 0) 0)
    (exit 1)
    (exit 0))
