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
(load "ulisp/runtime/concurrency/arena.scm")
(load "ulisp/runtime/concurrency/context.scm")
(load "ulisp/runtime/concurrency/deque.scm")
(load "ulisp/runtime/concurrency/thread.scm")
(load "ulisp/runtime/concurrency/links.scm")
(load "ulisp/runtime/concurrency/panic.scm")
(load "ulisp/runtime/concurrency/scheduler.scm")
(load "ulisp/runtime/concurrency/preempt.scm")

(test-begin "concurrency-preemption")

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
;; Group 8: Link Cascade Termination Safepoint Exit & Cleanup (#723)
;; -----------------------------------------------------------------------
(write-string "--- Group 8: Link Cascade Safepoint Exit & Ordered Resource Cleanup (#723) ---\n")

(let* ((t-leader (make-task-context))
       (t-peer (make-task-context))
       (peer-arena (make-task-arena 2048))
       (peer-iters (vector 0)))
  (task-set-arena! t-peer peer-arena)
  (task-link! t-leader t-peer)

  ;; Run t-peer inside task boundary; on iteration 3, t-leader crashes and cascade-kills t-peer
  (let ((res (with-synapse-task-boundary t-peer
               (lambda ()
                 (arena-allocate! peer-arena 128)
                 (let loop ((i 0))
                   (if (< i 100)
                       (begin
                         (vector-set! peer-iters 0 (+ (vector-ref peer-iters 0) 1))
                         (if (= i 2)
                             ;; Simulate linked peer t-leader crashing on another worker
                             (task-handle-termination! t-leader 'peer_crash)
                             #f)
                         ;; Safepoint must immediately exit when t-peer is marked 'terminated with reductions 0
                         (check-safepoint! t-peer)
                         (loop (+ i 1)))
                       'completed-100))))))
    (assert-equal (task-state t-peer) 'terminated "linked peer task state is 'terminated")
    (assert-equal (task-reductions t-peer) 0 "linked peer reductions remained 0 without replenishment")
    (assert-equal (vector-ref peer-iters 0) 3 "linked peer stopped immediately at safepoint on iteration 3 (not 100)")
    (assert-equal (car res) 'terminated "task boundary returned 'terminated from safepoint escape")
    (assert-equal (arena-used-bytes peer-arena) 0 "peer arena reclaimed to 0 bytes after execution stopped at safepoint")))

;; -----------------------------------------------------------------------
;; Group 9: Layer 1 Loop Safepoint Exit & Global Polling Entrypoint (#744)
;; -----------------------------------------------------------------------
(write-string "--- Group 9: Layer 1 Loop Safepoint Exit & Global Polling (#744) ---\n")

;; 1. Out-of-task context safety
(assert-true (%synapse-safepoint-poll!) "%synapse-safepoint-poll! returns #t safely outside task context")
(assert-true (%safepoint-poll!) "%safepoint-poll! returns #t safely outside task context")

;; 2. In-task Layer 1 loop preemption & forced termination
(let* ((t-killer (make-task-context))
       (t-worker (make-task-context))
       (worker-arena (make-task-arena 2048))
       (worker-iters (vector 0)))
  (task-set-arena! t-worker worker-arena)
  (task-link! t-killer t-worker)

  (let ((res (with-synapse-task-boundary t-worker
               (lambda ()
                 ;; Pure Layer 1 R7RS loop with compiler-injected (%synapse-safepoint-poll!)
                 (let loop ((count 0))
                   (if (< count 100)
                       (begin
                         (vector-set! worker-iters 0 (+ (vector-ref worker-iters 0) 1))
                         (if (= count 4)
                             ;; Linked peer terminates abruptly
                             (task-handle-termination! t-killer 'peer_fault)
                             #f)
                         ;; Unparameterized Layer 1 safepoint poll
                         (%synapse-safepoint-poll!)
                         (loop (+ count 1)))
                       'completed-100))))))
    (assert-equal (task-state t-worker) 'terminated "Layer 1 worker task state transitioned to 'terminated")
    (assert-equal (task-reductions t-worker) 0 "Layer 1 worker reductions zeroed upon termination")
    (assert-equal (vector-ref worker-iters 0) 5 "Layer 1 loop stopped immediately on iteration 5 (not 100)")
    (assert-equal (car res) 'terminated "boundary returned 'terminated from Layer 1 safepoint escape")))

;; -----------------------------------------------------------------------
;; Group 10: Automatic Safepoint Injection into Pure Scheme Loops (#790)
;; -----------------------------------------------------------------------
(write-string "--- Group 10: Automatic Safepoint Preemption & Forced Exit (#790) ---\n")

;; 1. Out-of-band termination signal handled at loop entry/backedge safepoint
(let* ((t-killer2 (make-task-context))
       (t-worker2 (make-task-context))
       (worker-arena2 (make-task-arena 2048))
       (auto-worker-iters (vector 0)))
  (task-set-arena! t-worker2 worker-arena2)
  (task-link! t-killer2 t-worker2)

  ;; Loop structured exactly as transformed by pass-synapse-inject-safepoints:
  ;; prologue safepoint at loop entry and backedge safepoint before recursive call.
  (let ((res (with-synapse-task-boundary t-worker2
               (lambda ()
                 (let loop ((count 0))
                   (%synapse-safepoint-poll!)
                   (if (< count 100)
                       (begin
                         (vector-set! auto-worker-iters 0 (+ (vector-ref auto-worker-iters 0) 1))
                         (if (= count 4)
                             (task-handle-termination! t-killer2 'peer_fault)
                             #f)
                         (begin
                           (%synapse-safepoint-poll!)
                           (loop (+ count 1))))
                       'completed-100))))))
    (assert-equal (task-state t-worker2) 'terminated "worker state transitioned to 'terminated via injected safepoint")
    (assert-equal (task-reductions t-worker2) 0 "worker reductions zeroed upon termination")
    (assert-equal (vector-ref auto-worker-iters 0) 5 "loop stopped immediately on iteration 5 (not 100)")
    (assert-equal (car res) 'terminated "task boundary caught safepoint termination exit")))



;; -----------------------------------------------------------------------
;; Group 11: True Dynamic Preemption with Compiler-Injected Safepoints (#808)
;; -----------------------------------------------------------------------
(write-string "--- Group 11: Dynamic Injected Safepoint Preemption (#808) ---\n")

;; 1. Pure Scheme loop without manual poll halts via compiler-injected safepoint
(let* ((t-killer3 (make-task-context))
       (t-worker3 (make-task-context))
       (worker-arena3 (make-task-arena 2048))
       (pure-worker-iters (vector 0)))
  (task-set-arena! t-worker3 worker-arena3)
  (task-link! t-killer3 t-worker3)

  ;; Pure loop WITHOUT any manual (%synapse-safepoint-poll!) calls:
  ;; Rely 100% on pass-synapse-inject-safepoints compiler pass.
  (let ((res (with-synapse-task-boundary t-worker3
               (lambda ()
                 (let pure-loop ((count 0))
                   (if (< count 1000000)
                       (begin
                         (vector-set! pure-worker-iters 0 (+ (vector-ref pure-worker-iters 0) 1))
                         (if (= count 5)
                             (task-handle-termination! t-killer3 'peer_fault)
                             #f)
                         (pure-loop (+ count 1)))
                       'completed-1m))))))
    (assert-equal (task-state t-worker3) 'terminated "pure worker task transitioned to 'terminated via injected safepoint")
    (assert-equal (task-reductions t-worker3) 0 "pure worker reductions zeroed upon termination")
    (assert-equal (vector-ref pure-worker-iters 0) 6 "pure loop stopped immediately at count 5/6 (not 1,000,000)")
    (assert-equal (car res) 'terminated "task boundary returned 'terminated from compiler-injected safepoint")
    (assert-equal (arena-used-bytes worker-arena3) 0 "task arena reclaimed after safepoint exit")))

;; 2. Multi-iteration nested loop without manual poll halts via loop backedge safepoint
(let* ((t-killer4 (make-task-context))
       (t-worker4 (make-task-context))
       (worker-arena4 (make-task-arena 2048))
       (nested-iters (vector 0)))
  (task-set-arena! t-worker4 worker-arena4)
  (task-link! t-killer4 t-worker4)

  (let ((res (with-synapse-task-boundary t-worker4
               (lambda ()
                 (let outer ((i 0))
                   (if (< i 100)
                       (begin
                         (let inner ((j 0))
                           (if (< j 1000000)
                               (begin
                                 (vector-set! nested-iters 0 (+ (vector-ref nested-iters 0) 1))
                                 (if (= j 4)
                                     (task-handle-termination! t-killer4 'peer_crash)
                                     #f)
                                 (inner (+ j 1)))
                               'inner-done))
                         (outer (+ i 1)))
                       'outer-done))))))
    (assert-equal (task-state t-worker4) 'terminated "nested worker task transitioned to 'terminated")
    (assert-equal (task-reductions t-worker4) 0 "nested worker reductions zeroed upon termination")
    (assert-true (< (vector-ref nested-iters 0) 10) "nested loop stopped immediately after termination signal")
    (assert-equal (car res) 'terminated "boundary caught termination during nested loop")
    (assert-equal (arena-used-bytes worker-arena4) 0 "arena reclaimed after nested loop termination")))

(test-end "concurrency-preemption")
