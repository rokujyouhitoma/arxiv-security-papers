;;; =======================================================================
;;; ULisp Concurrency Test Suite: Work-Stealing Scheduler & Deque (#635)
;;; Tests:
;;;   Group 1: Chase-Lev Deque Single-Worker LIFO Operations & Growth
;;;   Group 2: Chase-Lev Deque FIFO Steal & Multi-Client Contention
;;;   Group 3: Scheduler Creation, Multi-Worker Setup & Task Spawning
;;;   Group 4: Asymmetric Work-Stealing Load Balancing & Channel Wake
;;;   Group 5: 100,000 Tasks High-Throughput Work-Stealing Endurance Test
;;;   Group 6: Security & Boundary Guards (CWE-362 / CWE-400 / CWE-843 / CWE-20)
;;;   Group 7: NUMA-Aware Hierarchical Work-Stealing (#681)
;;;   Group 8: Live Tasks Concurrency Limit & CWE-400 Long-Running DoS Prevention (#793)
;;; =======================================================================

(load "ulisp/runtime/concurrency/channel.scm")
(load "ulisp/runtime/concurrency/context.scm")
(load "ulisp/runtime/concurrency/deque.scm")
(load "ulisp/runtime/concurrency/thread.scm")
(load "ulisp/runtime/concurrency/scheduler.scm")

(test-begin "concurrency-scheduler")

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
;; Group 1: Chase-Lev Deque Single-Worker LIFO Operations & Growth
;; -----------------------------------------------------------------------
(write-string "--- Group 1: Chase-Lev Deque Single-Worker LIFO & Growth ---\n")
(flush-output-port)

(let ((dq-def (make-chase-lev-deque))
      (dq-16  (make-chase-lev-deque 16))
      (dq-20  (make-chase-lev-deque 20)))
  (assert-true (chase-lev-deque? dq-def) "dq-def satisfies chase-lev-deque?")
  (assert-true (chase-lev-deque? dq-16) "dq-16 satisfies chase-lev-deque?")
  (assert-true (not (chase-lev-deque? 12345)) "fixnum is not chase-lev-deque?")
  (assert-true (not (chase-lev-deque? (vector 1 2 3))) "raw vector is not chase-lev-deque?")
  (assert-equal (deque-capacity dq-def) 256 "default deque capacity is 256")
  (assert-equal (deque-capacity dq-16) 16 "16-capacity deque has capacity 16")
  (assert-equal (deque-capacity dq-20) 32 "non-power-of-two 20 rounds up to 32")
  (assert-true (deque-empty? dq-def) "dq-def is initially empty")
  (assert-equal (deque-count dq-def) 0 "dq-def initial count is 0")

  ;; Push 3 items: 10, 20, 30
  (assert-true (deque-push! dq-def 10) "deque-push! 10 returns #t")
  (assert-true (deque-push! dq-def 20) "deque-push! 20 returns #t")
  (assert-true (deque-push! dq-def 30) "deque-push! 30 returns #t")
  (assert-true (not (deque-empty? dq-def)) "dq-def is not empty after pushes")
  (assert-equal (deque-count dq-def) 3 "deque-count after 3 pushes is 3")

  ;; Pop in LIFO order: 30, 20, 10
  (assert-equal (deque-pop! dq-def) 30 "first deque-pop! returns 30 (LIFO)")
  (assert-equal (deque-pop! dq-def) 20 "second deque-pop! returns 20 (LIFO)")
  (assert-equal (deque-pop! dq-def) 10 "third deque-pop! returns 10 (LIFO)")
  (assert-true (deque-empty? dq-def) "dq-def is empty after popping all items")
  (assert-equal (deque-pop! dq-def) #f "deque-pop! on empty deque returns #f")
  (assert-equal (deque-count dq-def) 0 "deque-count is 0 after draining")

  ;; Buffer growth test: Push 100 items into 16-capacity deque
  (let loop ((i 1))
    (if (<= i 100)
        (begin
          (deque-push! dq-16 i)
          (loop (+ i 1)))))
  (assert-true (>= (deque-capacity dq-16) 128) "dq-16 dynamically expanded to >= 128 capacity")
  (assert-equal (deque-count dq-16) 100 "dq-16 count is 100 after dynamic growth")

  ;; Pop all 100 items and verify exact reverse order 100..1
  (let ((order-ok
         (let loop ((expected 100) (ok #t))
           (if (< expected 1)
               ok
               (let ((val (deque-pop! dq-16)))
                 (loop (- expected 1) (and ok (eqv? val expected))))))))
    (assert-true order-ok "all 100 items popped in strict reverse LIFO order after expansion"))
  (assert-true (deque-empty? dq-16) "dq-16 empty after draining 100 items"))

;; -----------------------------------------------------------------------
;; Group 2: Chase-Lev Deque FIFO Steal & Multi-Client Contention
;; -----------------------------------------------------------------------
(write-string "--- Group 2: Chase-Lev Deque FIFO Steal & Contention ---\n")
(flush-output-port)

(let ((dq (make-chase-lev-deque 32)))
  (deque-push! dq 'first)
  (deque-push! dq 'second)
  (deque-push! dq 'third)
  (deque-push! dq 'fourth)

  ;; Thief steals from Top (FIFO order): 'first, then 'second
  (assert-equal (deque-steal! dq) 'first "thief steals 'first from Top (FIFO)")
  (assert-equal (deque-steal! dq) 'second "thief steals 'second from Top (FIFO)")
  (assert-equal (deque-count dq) 2 "deque-count is 2 after two steals")

  ;; Owner pops from Bottom (LIFO): 'fourth
  (assert-equal (deque-pop! dq) 'fourth "owner pops 'fourth from Bottom (LIFO)")
  (assert-equal (deque-count dq) 1 "deque-count is 1 before race")

  ;; Owner pops the last remaining item 'third (winning the single-element CAS race)
  (assert-equal (deque-pop! dq) 'third "owner pops last item 'third")
  (assert-true (deque-empty? dq) "deque is empty after popping last item")

  ;; Subsequent steals and pops return 'empty and #f
  (assert-equal (deque-steal! dq) 'empty "thief deque-steal! on empty deque returns 'empty")
  (assert-equal (deque-pop! dq) #f "owner deque-pop! on empty deque returns #f")

  (let ((stats (deque-stats dq)))
    (assert-equal (cdr (assq 'count stats)) 0 "deque-stats count is 0")
    (assert-equal (cdr (assq 'capacity stats)) 32 "deque-stats capacity is 32")))

;; -----------------------------------------------------------------------
;; Group 3: Scheduler Creation, Multi-Worker Setup & Task Spawning
;; -----------------------------------------------------------------------
(write-string "--- Group 3: Scheduler Creation & Worker Initialization ---\n")
(flush-output-port)

(let ((sched (make-work-stealing-scheduler 4)))
  (assert-true (work-stealing-scheduler? sched) "sched satisfies work-stealing-scheduler?")
  (assert-true (not (work-stealing-scheduler? 999)) "fixnum is not work-stealing-scheduler?")
  (assert-equal (scheduler-worker-count sched) 4 "scheduler-worker-count is 4")
  (assert-true (scheduler-running? sched) "scheduler is initially in 'running state")
  (assert-equal (scheduler-state sched) 'running "scheduler-state is 'running")
  (assert-equal (scheduler-total-spawned sched) 0 "initial spawned count is 0")
  (assert-equal (scheduler-total-completed sched) 0 "initial completed count is 0")
  (assert-true (lock-free-queue? (scheduler-global-queue sched)) "global-queue is <lock-free-queue>")

  ;; Check worker contexts
  (let ((w0 (scheduler-get-worker sched 0))
        (w3 (scheduler-get-worker sched 3)))
    (assert-true (worker-context? w0) "w0 satisfies worker-context?")
    (assert-true (worker-context? w3) "w3 satisfies worker-context?")
    (assert-equal (worker-id w0) 0 "w0 id is 0")
    (assert-equal (worker-id w3) 3 "w3 id is 3")
    (assert-true (chase-lev-deque? (worker-deque w0)) "w0 deque is <chase-lev-deque>")
    (assert-equal (worker-tasks-executed w0) 0 "w0 initial tasks-executed is 0")
    (assert-equal (worker-steals-attempted w0) 0 "w0 initial steals-attempted is 0")
    (assert-equal (worker-steals-succeeded w0) 0 "w0 initial steals-succeeded is 0")
    (assert-equal (worker-yields w0) 0 "w0 initial yields is 0")

    ;; Verify Xorshift PRNG sequence on worker
    (let* ((seed0 (worker-rng-seed w0))
           (r1 (worker-next-random! w0))
           (r2 (worker-next-random! w0)))
      (assert-true (> seed0 0) "w0 has positive initial rng-seed")
      (assert-true (> r1 0) "first xorshift random value is positive")
      (assert-true (> r2 0) "second xorshift random value is positive")
      (assert-true (not (= r1 r2)) "successive xorshift values differ")
      (assert-equal (worker-rng-seed w0) r2 "worker-rng-seed tracks updated state")))

  ;; Spawn single task into global queue and execute via worker 0
  (let ((flag (vector #f)))
    (assert-true (scheduler-spawn! sched (lambda () (vector-set! flag 0 #t)))
                 "scheduler-spawn! thunk returns #t")
    (assert-equal (scheduler-total-spawned sched) 1 "total-spawned incremented to 1")
    (assert-equal (scheduler-total-completed sched) 0 "total-completed is still 0 before step")
    (assert-true (scheduler-worker-step! sched 0) "scheduler-worker-step! worker 0 executes task")
    (assert-true (vector-ref flag 0) "task execution mutated flag to #t")
    (assert-equal (scheduler-total-completed sched) 1 "total-completed incremented to 1 after step")
    (assert-equal (worker-tasks-executed (scheduler-get-worker sched 0)) 1 "worker 0 executed 1 task"))

  (scheduler-stop! sched)
  (assert-equal (scheduler-state sched) 'stopped "scheduler-state is 'stopped after stop!"))

;; -----------------------------------------------------------------------
;; Group 3b: Atomic Scheduler Stats Counters & Monotonic Invariants (#674)
;; -----------------------------------------------------------------------
(write-string "--- Group 3b: Atomic Scheduler Stats Counters (#674) ---\n")
(flush-output-port)

(let ((sched (make-work-stealing-scheduler 2 64)))
  (assert-equal (scheduler-tasks-spawned sched) 0 "initial tasks-spawned is 0")
  (assert-equal (scheduler-tasks-completed sched) 0 "initial tasks-completed is 0")
  (assert-equal (scheduler-tasks-failed sched) 0 "initial tasks-failed is 0")
  (assert-equal (scheduler-total-spawned sched) 0 "scheduler-total-spawned matches tasks-spawned (0)")
  (assert-equal (scheduler-total-completed sched) 0 "scheduler-total-completed matches tasks-completed (0)")
  (assert-equal (scheduler-total-failed sched) 0 "scheduler-total-failed matches tasks-failed (0)")
  (assert-equal (scheduler-live-tasks sched) 0 "initial live-tasks is 0")
  (assert-equal (scheduler-total-live sched) 0 "scheduler-total-live matches live-tasks (0)")

  ;; Verify atomic increment operations
  (%scheduler-tasks-spawned-inc! sched)
  (assert-equal (scheduler-tasks-spawned sched) 1 "tasks-spawned is 1 after inc")
  (assert-equal (scheduler-total-spawned sched) 1 "total-spawned reflects 1")

  (%scheduler-tasks-completed-inc! sched)
  (assert-equal (scheduler-tasks-completed sched) 1 "tasks-completed is 1 after inc")
  (assert-equal (scheduler-total-completed sched) 1 "total-completed reflects 1")

  (%scheduler-tasks-failed-inc! sched)
  (assert-equal (scheduler-tasks-failed sched) 1 "tasks-failed is 1 after inc")
  (assert-equal (scheduler-total-failed sched) 1 "total-failed reflects 1")

  (%scheduler-live-tasks-inc! sched)
  (assert-equal (scheduler-live-tasks sched) 1 "live-tasks is 1 after inc")
  (assert-equal (scheduler-total-live sched) 1 "total-live reflects 1")

  ;; Perform rapid 100 increments
  (let loop ((k 0))
    (if (< k 100)
        (begin
          (%scheduler-tasks-spawned-inc! sched)
          (%scheduler-tasks-completed-inc! sched)
          (%scheduler-tasks-failed-inc! sched)
          (%scheduler-live-tasks-inc! sched)
          (loop (+ k 1)))
        #t))

  (assert-equal (scheduler-tasks-spawned sched) 101 "tasks-spawned reached 101")
  (assert-equal (scheduler-tasks-completed sched) 101 "tasks-completed reached 101")
  (assert-equal (scheduler-tasks-failed sched) 101 "tasks-failed reached 101")
  (assert-equal (scheduler-live-tasks sched) 101 "live-tasks reached 101")

  ;; Check scheduler-stats alist
  (let ((st (scheduler-stats sched)))
    (assert-equal (cdr (assq 'tasks-spawned st)) 101 "stats tasks-spawned is 101")
    (assert-equal (cdr (assq 'tasks-completed st)) 101 "stats tasks-completed is 101")
    (assert-equal (cdr (assq 'tasks-failed st)) 101 "stats tasks-failed is 101")
    (assert-equal (cdr (assq 'live-tasks st)) 101 "stats live-tasks is 101"))

  ;; Reset stats
  (assert-true (%scheduler-stats-reset! sched) "%scheduler-stats-reset! returns #t")
  (assert-equal (scheduler-tasks-spawned sched) 0 "tasks-spawned is 0 after reset")
  (assert-equal (scheduler-tasks-completed sched) 0 "tasks-completed is 0 after reset")
  (assert-equal (scheduler-tasks-failed sched) 0 "tasks-failed is 0 after reset")
  (assert-equal (scheduler-live-tasks sched) 0 "live-tasks is 0 after reset")

  ;; Test real execution differentiation: spawn 2 successful tasks, 1 failing task
  (scheduler-spawn! sched (lambda () 42))
  (scheduler-spawn! sched (lambda () (error "simulated task panic")))
  (scheduler-spawn! sched (lambda () 100))
  (assert-equal (scheduler-live-tasks sched) 3 "3 live tasks spawned before run")
  (scheduler-run! sched 3)
  (assert-equal (scheduler-tasks-spawned sched) 3 "spawned 3 tasks")
  (assert-equal (scheduler-tasks-completed sched) 2 "2 tasks completed successfully")
  (assert-equal (scheduler-tasks-failed sched) 1 "1 task recorded as failed")
  (assert-equal (scheduler-live-tasks sched) 0 "live-tasks is 0 after all 3 tasks finish")

  ;; Guard against non-scheduler object (CWE-843)
  (assert-error (lambda () (scheduler-tasks-spawned "invalid")) "scheduler-tasks-spawned rejects non-scheduler (CWE-843)")
  (assert-error (lambda () (scheduler-tasks-completed 12345)) "scheduler-tasks-completed rejects non-scheduler (CWE-843)")
  (assert-error (lambda () (scheduler-tasks-failed 'bad)) "scheduler-tasks-failed rejects non-scheduler (CWE-843)")
  (assert-error (lambda () (scheduler-live-tasks #f)) "scheduler-live-tasks rejects non-scheduler (CWE-843)")
  (assert-error (lambda () (%scheduler-stats-reset! #f)) "%scheduler-stats-reset! rejects non-scheduler (CWE-843)")

  (scheduler-stop! sched))

;; -----------------------------------------------------------------------
;; Group 4: Asymmetric Work-Stealing Load Balancing & Channel Wake
;; -----------------------------------------------------------------------
(write-string "--- Group 4: Asymmetric Load Balancing & Work-Stealing ---\n")
(flush-output-port)

(let* ((sched (make-work-stealing-scheduler 4 256))
       (task-count 1000)
       (done-box (vector 0)))
  ;; Asymmetric Injection: Spawn all 1,000 tasks EXCLUSIVELY into Worker 0!
  ;; Workers 1, 2, and 3 start with completely empty deques.
  (let loop ((i 0))
    (if (< i task-count)
        (begin
          (scheduler-spawn! sched
                            (lambda ()
                              (vector-set! done-box 0 (+ (vector-ref done-box 0) 1)))
                            0) ; Inject into worker 0
          (loop (+ i 1)))))

  (assert-equal (scheduler-total-spawned sched) 1000 "all 1,000 tasks spawned into worker 0")
  (let ((w0 (scheduler-get-worker sched 0))
        (w1 (scheduler-get-worker sched 1)))
    (assert-equal (+ (l1-ring-count (worker-l1-queue w0)) (deque-count (worker-deque w0))) 1000 "worker 0 holds 1,000 tasks across L1 and L2")
    (assert-equal (+ (l1-ring-count (worker-l1-queue w1)) (deque-count (worker-deque w1))) 0 "worker 1 is initially empty"))

  ;; Run multi-worker scheduler loop
  (let ((completed (scheduler-run! sched)))
    (assert-equal completed 1000 "scheduler-run! completed all 1,000 tasks")
    (assert-equal (vector-ref done-box 0) 1000 "done-box recorded exactly 1,000 completed executions")
    (assert-equal (scheduler-total-completed sched) 1000 "scheduler-total-completed is 1,000"))

  ;; Inspect work distribution and verify steals happened!
  (let* ((stats (scheduler-stats sched))
         (w-stats (cdr (assq 'workers stats)))
         (w0-exec (cdr (assq 'tasks-executed (list-ref w-stats 0))))
         (w1-exec (cdr (assq 'tasks-executed (list-ref w-stats 1))))
         (w2-exec (cdr (assq 'tasks-executed (list-ref w-stats 2))))
         (w3-exec (cdr (assq 'tasks-executed (list-ref w-stats 3))))
         (total-exec (+ (+ w0-exec w1-exec) (+ w2-exec w3-exec)))
         (total-steals (+ (+ (cdr (assq 'steals-succeeded (list-ref w-stats 0)))
                             (cdr (assq 'steals-succeeded (list-ref w-stats 1))))
                          (+ (cdr (assq 'steals-succeeded (list-ref w-stats 2)))
                             (cdr (assq 'steals-succeeded (list-ref w-stats 3)))))))
    (assert-equal total-exec 1000 "sum of tasks executed across 4 workers equals 1,000")
    (assert-true (> total-steals 0) "workers successfully stole tasks from worker 0")
    (assert-true (> w1-exec 0) "worker 1 executed stolen tasks")
    (assert-true (> (+ w2-exec w3-exec) 0) "workers 2 & 3 executed stolen tasks"))

  ;; Test Channel Wake-Hook Integration
  (assert-true (scheduler-enable-channel-wake! sched) "scheduler-enable-channel-wake! succeeds")
  (let ((ch (make-channel 0))
        (recv-task (make-task-context 777))
        (woken-res (vector #f)))
    (scheduler-spawn! sched
                      (lambda ()
                        ;; Receiver task waits on rendezvous channel
                        (let ((val (channel-recv! ch recv-task)))
                          (if (not (eq? val 'suspended))
                              (vector-set! woken-res 0 val)))))
    ;; Step worker 0 to run receiver (suspends on channel)
    (scheduler-worker-step! sched 0)
    (assert-equal (vector-ref woken-res 0) #f "receiver suspended on empty channel")
    ;; Send message on channel from another task, waking receiver into scheduler
    (channel-send! ch 'synapse-msg)
    ;; Run scheduler to execute the woken task
    (scheduler-run! sched)
    (assert-true (task-has-handoff? recv-task) "recv-task received channel handoff")
    (assert-equal (task-take-handoff! recv-task) 'synapse-msg "woken task resumed and received channel message"))

  (scheduler-stop! sched))

;; -----------------------------------------------------------------------
;; Group 5: 100,000 Tasks High-Throughput Work-Stealing Endurance Test
;; -----------------------------------------------------------------------
(write-string "--- Group 5: 100,000 Tasks High-Throughput Endurance Test ---\n")
(flush-output-port)

(let* ((sched (make-work-stealing-scheduler 4 512))
       (n-tasks 100000)
       (counter (vector 0)))
  ;; Scatter 100,000 lightweight tasks across 4 workers and global queue
  (let loop ((i 0))
    (if (< i n-tasks)
        (let ((target (modulo i 5))) ; 0..3 target workers, 4 = global queue
          (scheduler-spawn! sched
                            (lambda ()
                              (vector-set! counter 0 (+ (vector-ref counter 0) 1)))
                            (if (= target 4) #f target))
          (loop (+ i 1)))))

  (assert-equal (scheduler-total-spawned sched) 100000 "100,000 tasks spawned")

  ;; Run multi-worker engine to completion
  (let ((completed (scheduler-run! sched n-tasks)))
    (assert-equal completed 100000 "100,000 tasks completed in multi-worker engine")
    (assert-equal (vector-ref counter 0) 100000 "counter reached exactly 100,000 with zero dropped tasks")
    (assert-equal (scheduler-total-completed sched) 100000 "scheduler-total-completed is 100,000")
    (assert-equal (queue-size (scheduler-global-queue sched)) 0 "global queue drained to 0"))

  (let* ((stats (scheduler-stats sched))
         (w-stats (cdr (assq 'workers stats))))
    (let loop ((ws w-stats))
      (if (not (null? ws))
          (begin
            (assert-equal (cdr (assq 'deque-count (car ws))) 0 "worker deque fully drained to 0")
            (loop (cdr ws))))))

  (scheduler-stop! sched))

;; -----------------------------------------------------------------------
;; Group 6: Security & Boundary Guards (CWE-362 / CWE-400 / CWE-843 / CWE-20)
;; -----------------------------------------------------------------------
(write-string "--- Group 6: Security & Boundary Guards (CWE-362 / CWE-400 / CWE-843) ---\n")
(flush-output-port)

;; 6a. Deque capacity boundary checks
(assert-error (lambda () (make-chase-lev-deque -10))
              "make-chase-lev-deque rejects negative capacity (CWE-20)")
(assert-error (lambda () (make-chase-lev-deque 99999999))
              "make-chase-lev-deque rejects oversized capacity > *deque-max-capacity* (CWE-400)")
(assert-error (lambda () (make-chase-lev-deque 'not-an-int))
              "make-chase-lev-deque rejects non-integer capacity (CWE-843)")

;; 6b. Deque push invalid value (#f disallowed as task)
(assert-error (lambda () (deque-push! (make-chase-lev-deque) #f))
              "deque-push! rejects #f as task payload")
(assert-error (lambda () (deque-push! 'not-a-deque 42))
              "deque-push! rejects non-deque object (CWE-843)")
(assert-error (lambda () (deque-pop! 'not-a-deque))
              "deque-pop! rejects non-deque object (CWE-843)")
(assert-error (lambda () (deque-steal! 'not-a-deque))
              "deque-steal! rejects non-deque object (CWE-843)")

;; 6c. Scheduler worker-count boundaries
(assert-error (lambda () (make-work-stealing-scheduler 0))
              "make-work-stealing-scheduler rejects 0 workers (CWE-400)")
(assert-error (lambda () (make-work-stealing-scheduler -1))
              "make-work-stealing-scheduler rejects negative workers (CWE-20)")
(assert-error (lambda () (make-work-stealing-scheduler 128))
              "make-work-stealing-scheduler rejects >64 workers (CWE-400)")
(assert-error (lambda () (make-work-stealing-scheduler 'bad))
              "make-work-stealing-scheduler rejects non-integer worker-count (CWE-843)")

;; 6d. Scheduler invalid task spawning
(let ((s (make-work-stealing-scheduler 2)))
  (assert-error (lambda () (scheduler-spawn! s 12345))
                "scheduler-spawn! rejects non-procedure / non-task object (CWE-843)")
  (assert-error (lambda () (scheduler-spawn! 'not-a-sched (lambda () #t)))
                "scheduler-spawn! rejects non-scheduler object (CWE-843)")
  (scheduler-stop! s)
  (assert-error (lambda () (scheduler-spawn! s (lambda () #t)))
                "scheduler-spawn! rejects spawning into stopped scheduler"))

;; 6e. Coroutine task exception boundary isolation (#740)
(let* ((s (make-work-stealing-scheduler 2 64))
       (box (make-atomic-box 0))
       (bad-coro (make-coroutine-context (lambda () (car '()))))
       (bad-t (make-task-context))
       (good-coro (make-coroutine-context (lambda () (atomic-fetch-add! box 55))))
       (good-t (make-task-context)))
  (task-next-run-set! bad-t bad-coro)
  (task-next-run-set! good-t good-coro)
  (scheduler-spawn! s bad-t 0)
  (scheduler-spawn! s good-t 1)
  (scheduler-run! s 3)
  (assert-equal (task-state bad-t) 'terminated "scheduler isolates crashing coroutine (#740)")
  (assert-true (coroutine-terminated? bad-coro) "coroutine state is terminated (#740)")
  (assert-equal (atomic-ref box) 55 "sibling coroutine executes despite crash in scheduler (#740)")
  (scheduler-stop! s)
  (free-coroutine-context! bad-coro)
  (free-coroutine-context! good-coro))

;; -----------------------------------------------------------------------
;; Group 7: NUMA-Aware Hierarchical Work-Stealing Topology & 2-Tier Stealing (#681)
;; -----------------------------------------------------------------------
(write-string "--- Group 7: NUMA-Aware Hierarchical Work-Stealing (#681) ---\n")

;; 7a. Linux SYS_getcpu integration
(let* ((cpu-node (get-current-cpu-node))
       (core-id (car cpu-node))
       (node-id (cdr cpu-node)))
  (assert-true (integer? core-id) "get-current-core-id returns integer")
  (assert-true (>= core-id 0) "core-id is non-negative")
  (assert-true (integer? node-id) "get-current-node-id returns integer")
  (assert-true (>= node-id 0) "node-id is non-negative")
  (assert-equal (get-current-core-id) core-id "get-current-core-id matches cpu-node car")
  (assert-equal (get-current-node-id) node-id "get-current-node-id matches cpu-node cdr"))

;; 7b. Scheduler NUMA Topology Configuration
(let ((sched (make-work-stealing-scheduler 4 32 2)))
  (assert-equal (scheduler-worker-count sched) 4 "worker-count is 4")
  (assert-equal (scheduler-node-count sched) 2 "node-count is 2")
  ;; Node 0 workers: worker 0 and worker 1
  (let ((w0 (scheduler-get-worker sched 0))
        (w1 (scheduler-get-worker sched 1))
        (w2 (scheduler-get-worker sched 2))
        (w3 (scheduler-get-worker sched 3)))
    (assert-equal (worker-node-id w0) 0 "worker 0 belongs to node 0")
    (assert-equal (worker-node-id w1) 0 "worker 1 belongs to node 0")
    (assert-equal (worker-node-id w2) 1 "worker 2 belongs to node 1")
    (assert-equal (worker-node-id w3) 1 "worker 3 belongs to node 1")
    (let ((node0-workers (scheduler-node-workers sched 0))
          (node1-workers (scheduler-node-workers sched 1)))
      (assert-equal (vector-length node0-workers) 2 "node 0 has 2 workers")
      (assert-equal (vector-ref node0-workers 0) 0 "node 0 worker 0 is wid 0")
      (assert-equal (vector-ref node0-workers 1) 1 "node 0 worker 1 is wid 1")
      (assert-equal (vector-length node1-workers) 2 "node 1 has 2 workers")
      (assert-equal (vector-ref node1-workers 0) 2 "node 1 worker 0 is wid 2")
      (assert-equal (vector-ref node1-workers 1) 3 "node 1 worker 1 is wid 3")))

  ;; 7c. Tier 1 Intra-Node Stealing Verification
  ;; Worker 0 pushes 50 tasks into its local deque. Worker 1 steals from Worker 0 (same NUMA node).
  (let ((done-box (make-atomic-box 0)))
    (let push-loop ((i 0))
      (if (< i 50)
          (begin
            (scheduler-spawn! sched (lambda () (atomic-fetch-add! done-box 1)) 0)
            (push-loop (+ i 1)))
          #t))
    ;; Step worker 1 to steal intra-node from worker 0
    (let step-loop ((i 0))
      (if (< i 10)
          (begin
            (scheduler-worker-step! sched 1)
            (step-loop (+ i 1)))
          #t))
    (let ((w1 (scheduler-get-worker sched 1)))
      (assert-true (> (worker-local-steals-succeeded w1) 0) "worker 1 succeeded at local (intra-node) steals")
      (assert-equal (worker-remote-steals-succeeded w1) 0 "worker 1 had zero remote steals during intra-node workload")))

  ;; 7d. Tier 2 Inter-Node Fallback Stealing Verification
  ;; Node 0 (Worker 0 and 1) is completely exhausted.
  ;; Spawn 50 tasks into Worker 2 (Node 1). Worker 0 (Node 0) must fall back to Tier 2 remote steal!
  (let ((w0 (scheduler-get-worker sched 0))
        (w1 (scheduler-get-worker sched 1))
        (w2 (scheduler-get-worker sched 2)))
    ;; Drain remaining tasks from worker 0 & 1 first
    (scheduler-run! sched 50)
    (assert-equal (deque-count (worker-deque w0)) 0 "worker 0 deque drained")
    (assert-equal (deque-count (worker-deque w1)) 0 "worker 1 deque drained")
    ;; Now spawn solely to worker 2 (node 1)
    (let push-remote-loop ((i 0))
      (if (< i 50)
          (begin
            (scheduler-spawn! sched (lambda () #t) 2)
            (push-remote-loop (+ i 1)))
          #t))
    ;; Worker 0 (node 0) steps: local node 0 is empty, so Tier 2 must steal from node 1!
    (let step-remote-loop ((i 0))
      (if (< i 10)
          (begin
            (scheduler-worker-step! sched 0)
            (step-remote-loop (+ i 1)))
          #t))
    (assert-true (> (worker-remote-steals-succeeded w0) 0) "worker 0 succeeded at remote (inter-node) steals")
    ;; Complete all tasks
    (scheduler-run! sched 100)
    (assert-equal (scheduler-tasks-completed sched) 100 "all tasks completed across tiers")
    (scheduler-stop! sched)))

;; 7e. NUMA Scheduler Boundary & CWE Protection Guards
(assert-error (lambda () (make-work-stealing-scheduler 4 32 0))
              "make-work-stealing-scheduler rejects 0 node-count (CWE-400)")
(assert-error (lambda () (make-work-stealing-scheduler 4 32 -1))
              "make-work-stealing-scheduler rejects negative node-count (CWE-20)")
(assert-error (lambda () (make-work-stealing-scheduler 4 32 5))
              "make-work-stealing-scheduler rejects node-count > worker-count (CWE-400)")
(assert-error (lambda () (make-work-stealing-scheduler 4 32 'bad))
              "make-work-stealing-scheduler rejects non-integer node-count (CWE-843)")
(let ((s (make-work-stealing-scheduler 4 32 2)))
  (assert-error (lambda () (scheduler-node-workers s -1))
                "scheduler-node-workers rejects negative node-id (CWE-400)")
  (assert-error (lambda () (scheduler-node-workers s 2))
                "scheduler-node-workers rejects node-id >= node-count (CWE-400)")
  (assert-error (lambda () (scheduler-node-workers s 'invalid))
                "scheduler-node-workers rejects non-integer node-id (CWE-843)")
  (assert-error (lambda () (scheduler-node-workers 'not-a-sched 0))
                "scheduler-node-workers rejects non-scheduler (CWE-843)")
  (scheduler-stop! s))

;; 7f. Task Exception Boundary Isolation in Scheduler (#720)
(let ((s (make-work-stealing-scheduler 2 32))
      (ok-count (make-atomic-box 0)))
  (scheduler-spawn! s (lambda () (error "task-error-isolated")) 0)
  (scheduler-spawn! s (lambda () (raise 'task-raise-isolated)) 1)
  (scheduler-spawn! s (lambda () (car '())) 0)
  (scheduler-spawn! s (lambda () (atomic-fetch-add! ok-count 1)) 1)
  (scheduler-run! s 4)
  (assert-equal (atomic-ref ok-count) 1 "valid task completes after preceding tasks raise/error/(car '()) (#720)")
  (scheduler-stop! s))

;; -----------------------------------------------------------------------
;; Group 8: Live Tasks Concurrency Limit & CWE-400 Long-Running DoS Prevention (#793)
;; -----------------------------------------------------------------------
(write-string "--- Group 8: Live Tasks Concurrency Limit & CWE-400 Prevention (#793) ---\n")
(flush-output-port)

(let* ((sched (make-work-stealing-scheduler 2 32))
       (orig-limit (scheduler-max-tasks))
       (counter (make-atomic-box 0)))
  ;; Test 8a: Verify live-tasks increases on spawn and decreases on completion
  (assert-equal (scheduler-live-tasks sched) 0 "initial live-tasks is 0")
  (scheduler-spawn! sched (lambda () (atomic-fetch-add! counter 1)))
  (assert-equal (scheduler-live-tasks sched) 1 "live-tasks is 1 after spawn")
  (assert-equal (scheduler-tasks-spawned sched) 1 "tasks-spawned is 1")
  (scheduler-run! sched 1)
  (assert-equal (scheduler-live-tasks sched) 0 "live-tasks returns to 0 after run")
  (assert-equal (scheduler-tasks-completed sched) 1 "tasks-completed is 1")
  (assert-equal (atomic-ref counter) 1 "counter incremented to 1")

  ;; Test 8b: Set small concurrency limit via scheduler-set-max-tasks! (limit = 3)
  (assert-true (scheduler-set-max-tasks! 3) "scheduler-set-max-tasks! to 3 succeeds")
  (assert-equal (scheduler-max-tasks) 3 "scheduler-max-tasks reflects 3")
  ;; Guard checks on scheduler-set-max-tasks! (CWE-843 / CWE-400)
  (assert-error (lambda () (scheduler-set-max-tasks! "invalid"))
                "scheduler-set-max-tasks! rejects non-integer limit (CWE-843)")
  (assert-error (lambda () (scheduler-set-max-tasks! 0))
                "scheduler-set-max-tasks! rejects 0 limit (CWE-400)")
  (assert-error (lambda () (scheduler-set-max-tasks! -5))
                "scheduler-set-max-tasks! rejects negative limit (CWE-400)")

  ;; Spawn 3 concurrent tasks (reaches max-tasks limit)
  (scheduler-spawn! sched (lambda () (atomic-fetch-add! counter 10)))
  (scheduler-spawn! sched (lambda () (atomic-fetch-add! counter 20)))
  (scheduler-spawn! sched (lambda () (atomic-fetch-add! counter 30)))
  (assert-equal (scheduler-live-tasks sched) 3 "live-tasks is 3 (at limit)")
  ;; 4th spawn MUST fail with CWE-400 because live-tasks (3) >= limit (3)
  (assert-error (lambda () (scheduler-spawn! sched (lambda () 999)))
                "scheduler-spawn! rejects 4th task when live-tasks >= *scheduler-max-tasks* (CWE-400)")

  ;; Now run scheduler to drain the 3 live tasks
  (scheduler-run! sched 3)
  (assert-equal (scheduler-live-tasks sched) 0 "live-tasks returns to 0 after draining")
  (assert-equal (scheduler-tasks-spawned sched) 4 "cumulative tasks-spawned is 4 (1 prior + 3 drained)")
  (assert-equal (scheduler-tasks-completed sched) 4 "cumulative tasks-completed is 4")

  ;; Test 8c: Crucial Issue #793 verification:
  ;; Even though cumulative tasks-spawned (4) >= *scheduler-max-tasks* (3),
  ;; spawning a new task MUST SUCCEED because live-tasks is 0 (< 3)!
  (assert-true (scheduler-spawn! sched (lambda () (atomic-fetch-add! counter 100)))
               "scheduler-spawn! succeeds when cumulative > max-tasks but live-tasks < max-tasks (#793)")
  (assert-equal (scheduler-live-tasks sched) 1 "live-tasks is 1 after post-limit spawn")
  (assert-equal (scheduler-tasks-spawned sched) 5 "tasks-spawned incremented to 5")

  ;; Complete the 5th task
  (scheduler-run! sched 1)
  (assert-equal (scheduler-live-tasks sched) 0 "live-tasks is 0 after final step")
  (assert-equal (scheduler-tasks-completed sched) 5 "tasks-completed incremented to 5")
  (assert-equal (atomic-ref counter) 161 "all task operations executed safely (1+10+20+30+100)")

  ;; Restore original limit
  (assert-true (scheduler-set-max-tasks! orig-limit) "restore scheduler-max-tasks succeeds")
  (assert-equal (scheduler-max-tasks) orig-limit "scheduler-max-tasks restored")
  (scheduler-stop! sched))

;; -----------------------------------------------------------------------
;; Group 18: Task Context Object Pool & Recycling Verification (#803)
;; -----------------------------------------------------------------------
(write-string "--- Group 18: Task Context Object Pool & Recycling Verification (#803) ---\n")
(flush-output-port)

(let ()
  ;; Step 1: Initialize pool and reset stats
  (task-pool-clear!)
  (task-pool-reset-stats!)
  (assert-equal (task-pool-hits) 0 "initial pool hits is 0")
  (assert-equal (task-pool-misses) 0 "initial pool misses is 0")

  ;; Step 2: Acquire from empty pool -> Miss & Allocate
  (let ((t1 (acquire-task-context! 0)))
    (assert-true (task-context? t1) "acquire-task-context! returns <task-context>")
    (assert-equal (task-state t1) 'ready "initial task state is 'ready")
    (assert-true (not (task-pooled? t1)) "t1 is not pooled")
    (assert-equal (task-pool-hits) 0 "pool hits still 0")
    (assert-equal (task-pool-misses) 1 "pool misses incremented to 1")

    (let ((tid1 (task-tid t1)))
      ;; Step 3: Release task back to worker 0 pool
      (assert-true (release-task-context! t1 0) "release-task-context! succeeds")
      (assert-true (task-pooled? t1) "t1 is marked pooled")
      (assert-equal (task-state t1) 'terminated "t1 task-state returns 'terminated for DSN-37 compatibility")

      ;; CWE-416 Defense: Double-free prevention
      (assert-equal (release-task-context! t1 0) #f "double release-task-context! is rejected (CWE-416)")

      ;; CWE-416 Defense: Execute rejected on pooled task
      (assert-equal (scheduler-execute-task! t1) #f "scheduler-execute-task! rejects execution of pooled task (CWE-416)")

      ;; Step 4: Re-acquire from pool -> Hit & Recycling
      (let ((t2 (acquire-task-context! 0)))
        (assert-true (task-context? t2) "re-acquired task is valid <task-context>")
        (assert-true (eq? t1 t2) "re-acquired task reuses identical context vector (zero heap allocation)")
        (assert-true (not (task-pooled? t2)) "t2 state is unsealed from 'pooled")
        (assert-equal (task-state t2) 'ready "t2 state is reset to 'ready")
        (assert-true (> (task-tid t2) tid1) "re-acquired task has newly allocated monotonic TID")
        (assert-equal (task-meta-fast t2) #f "t2 meta-box fast slot is #f")
        (assert-equal (task-pool-hits) 1 "pool hits incremented to 1 (Hit!)")
        (assert-equal (task-pool-misses) 1 "pool misses unchanged at 1")

        ;; Clean up t2
        (release-task-context! t2 0))))

  ;; Step 5: High-throughput task recycling verification (1,000 tasks)
  (task-pool-clear!)
  (task-pool-reset-stats!)
  (let* ((sched (make-work-stealing-scheduler 1))
         (cnt (make-atomic-box 0)))
    ;; Repeatedly spawn and execute tasks sequentially
    (let loop ((i 0))
      (if (< i 1000)
          (begin
            (scheduler-spawn! sched (lambda () (atomic-fetch-add! cnt 1)) 0)
            (scheduler-run! sched 1)
            (loop (+ i 1)))
          #t))
    (assert-equal (atomic-ref cnt) 1000 "all 1000 microtasks executed cleanly")
    (let ((hits (task-pool-hits))
          (misses (task-pool-misses)))
      ;; Almost all spawns (after the very first warm-up) should hit the pool (> 95% hit rate)
      (assert-true (> hits 950) "high-throughput pool hits > 950 (>95% hit rate)")
      (assert-true (<= misses 50) "high-throughput pool misses <= 50"))
    (scheduler-stop! sched)))

;; -----------------------------------------------------------------------
;; Group 19: L1 Bounded Ring Buffer & Two-Tier Work-Stealing (#804)
;; -----------------------------------------------------------------------
(write-string "--- Group 19: L1 Bounded Ring Buffer & Two-Tier Work-Stealing (#804) ---\n")
(flush-output-port)

;; 19a. Basic L1 Ring Buffer Construction & Initial State
(let ((l1 (make-l1-ring-buffer)))
  (assert-true (l1-ring-buffer? l1) "make-l1-ring-buffer returns <l1-ring-buffer>")
  (assert-true (l1-ring-empty? l1) "l1-ring-buffer is initially empty")
  (assert-equal (l1-ring-count l1) 0 "initial count is 0")
  (assert-true (not (l1-ring-full? l1)) "initial l1-ring is not full")
  (assert-true (not (l1-ring-runnext l1)) "runnext slot is initially #f")

  ;; 19b. Fast-Path: runnext Single Task Execution
  (l1-ring-push! l1 'task-fast)
  (assert-equal (l1-ring-count l1) 1 "l1 count is 1 after fast-path push")
  (assert-equal (l1-ring-runnext l1) 'task-fast "runnext holds 'task-fast")
  (assert-true (not (l1-ring-empty? l1)) "l1-ring is not empty with runnext")
  (let ((popped (l1-ring-pop! l1)))
    (assert-equal popped 'task-fast "l1-ring-pop! takes from runnext")
    (assert-true (l1-ring-empty? l1) "l1-ring is empty after taking runnext")
    (assert-equal (l1-ring-count l1) 0 "l1 count returns to 0"))

  ;; 19c. LIFO Ordering within L1 Ring Buffer
  (l1-ring-push! l1 't1)
  (l1-ring-push! l1 't2)
  (l1-ring-push! l1 't3)
  (assert-equal (l1-ring-count l1) 3 "l1 count is 3")
  ;; Pop order: runnext is 't3, then ring buffer LIFO 't2, then 't1
  (assert-equal (l1-ring-pop! l1) 't3 "first pop takes latest runnext 't3")
  (assert-equal (l1-ring-pop! l1) 't2 "second pop takes LIFO 't2 from ring")
  (assert-equal (l1-ring-pop! l1) 't1 "third pop takes LIFO 't1 from ring")
  (assert-true (l1-ring-empty? l1) "l1 is empty after popping all 3")

  ;; 19d. 256-Entry Capacity & Batch Offload to L2 Chase-Lev Deque
  (let ((l2 (make-chase-lev-deque 256)))
    ;; Fill L1 with 256 tasks (1 in runnext, 255 in ring buffer)
    (let fill-loop ((i 0))
      (if (< i 256)
          (begin
            (l1-ring-push! l1 (cons 'item i) l2)
            (fill-loop (+ i 1)))
          #t))
    (assert-equal (l1-ring-count l1) 256 "l1 has 256 tasks")
    (assert-equal (deque-count l2) 0 "l2 deque is still empty (threshold is 256)")

    ;; Push 257th task: triggers %l1-ring-batch-offload! of 128 tasks into L2 deque!
    (l1-ring-push! l1 'item-256 l2)
    (assert-equal (deque-count l2) 128 "128 tasks batch offloaded to L2 deque")
    (assert-equal (l1-ring-count l1) 129 "l1 holds remaining 129 tasks (257 - 128)")

    ;; 19e. L1 Exhaustion & Automatic Batch Refill from L2 Deque
    ;; Drain L1 ring buffer completely
    (let drain-l1 ((drained 0))
      (if (< drained 129)
          (let ((item (l1-ring-pop! l1 #f)))
            (assert-true (not (not item)) "item popped from L1")
            (drain-l1 (+ drained 1)))
          #t))
    (assert-true (l1-ring-empty? l1) "l1 is now completely empty")
    (assert-equal (deque-count l2) 128 "l2 still holds 128 offloaded tasks")

    ;; Next pop with L2 passes: should automatically refill up to 128 tasks from L2 into L1!
    (let ((refilled-item (l1-ring-pop! l1 l2)))
      (assert-true (not (not refilled-item)) "item popped via automatic L2 refill")
      (assert-equal (deque-count l2) 0 "l2 deque completely drained into L1")
      (assert-equal (l1-ring-count l1) 127 "l1 has 127 remaining refilled tasks"))

    ;; Drain remaining 127 refilled items
    (let ((all-drained (l1-ring-drain-all! l1)))
      (assert-equal (length all-drained) 127 "l1-ring-drain-all! drained exactly 127 tasks")
      (assert-true (l1-ring-empty? l1) "l1 is empty after drain-all!")))

  ;; 19f. FIFO Work-Stealing via l1-ring-steal!
  (let ((l1-victim (make-l1-ring-buffer)))
    (l1-ring-push! l1-victim 'victim-t0)
    (l1-ring-push! l1-victim 'victim-t1)
    (l1-ring-push! l1-victim 'victim-t2)
    ;; Thief steals from head (FIFO order: 'victim-t0 was moved to ring first)
    (let ((stolen (l1-ring-steal! l1-victim)))
      (assert-equal stolen 'victim-t0 "thief steals oldest 'victim-t0 from head (FIFO)"))
    (let ((stolen2 (l1-ring-steal! l1-victim)))
      (assert-equal stolen2 'victim-t1 "thief steals second 'victim-t1 from head"))
    (assert-equal (l1-ring-steal! l1-victim) 'empty "thief gets 'empty when ring is empty"))

  ;; 19g. High-Throughput 10,000 Tasks End-to-End Execution with L1 Integration
  (let* ((sched (make-work-stealing-scheduler 4 256))
         (done-counter (make-atomic-box 0))
         (n-tasks 10000))
    ;; Spawn 10,000 tasks across all 4 workers
    (let loop ((i 0))
      (if (< i n-tasks)
          (let ((target-wid (modulo i 4)))
            (scheduler-spawn! sched (lambda () (atomic-fetch-add! done-counter 1)) target-wid)
            (loop (+ i 1)))
          #t))
    (assert-equal (scheduler-total-spawned sched) n-tasks "10,000 tasks spawned")
    ;; Run multi-worker scheduler to completion
    (let ((completed (scheduler-run! sched n-tasks)))
      (assert-equal completed n-tasks "scheduler-run! completed all 10,000 tasks")
      (assert-equal (atomic-ref done-counter) n-tasks "all 10,000 tasks executed with zero loss")
      (assert-equal (scheduler-total-completed sched) n-tasks "scheduler total-completed is 10,000")
      (assert-equal (scheduler-live-tasks sched) 0 "zero live tasks remaining"))

    ;; Inspect stats to verify L1 metrics
    (let* ((stats (scheduler-stats sched))
           (w-stats (cdr (assq 'workers stats))))
      (assert-equal (length w-stats) 4 "4 worker stats entries")
      (let check-w ((i 0))
        (if (< i 4)
            (let* ((ws (list-ref w-stats i))
                   (l1-cnt (cdr (assq 'l1-count ws)))
                   (dq-cnt (cdr (assq 'deque-count ws))))
              (assert-equal l1-cnt 0 "worker L1 queue is empty after completion")
              (assert-equal dq-cnt 0 "worker L2 deque is empty after completion")
              (check-w (+ i 1)))
            #t)))
    (scheduler-stop! sched)))

(test-end "concurrency-scheduler")
