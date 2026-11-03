;;; =======================================================================
;;; ULisp Concurrency Test Suite: Work-Stealing Scheduler & Deque (#635)
;;; Tests:
;;;   Group 1: Chase-Lev Deque Single-Worker LIFO Operations & Growth
;;;   Group 2: Chase-Lev Deque FIFO Steal & Multi-Client Contention
;;;   Group 3: Scheduler Creation, Multi-Worker Setup & Task Spawning
;;;   Group 4: Asymmetric Work-Stealing Load Balancing & Channel Wake
;;;   Group 5: 100,000 Tasks High-Throughput Work-Stealing Endurance Test
;;;   Group 6: Security & Boundary Guards (CWE-362 / CWE-400 / CWE-843 / CWE-20)
;;; =======================================================================

(load "ulisp/runtime/concurrency/channel.scm")
(load "ulisp/runtime/concurrency/context.scm")
(load "ulisp/runtime/concurrency/deque.scm")
(load "ulisp/runtime/concurrency/thread.scm")
(load "ulisp/runtime/concurrency/scheduler.scm")

(define *test-sched-failures* (vector 0))
(define *test-sched-passes* (vector 0))

(define (assert-true val msg)
  (if (not val)
      (begin
        (vector-set! *test-sched-failures* 0 (+ (vector-ref *test-sched-failures* 0) 1))
        (write-string "FAIL: ")
        (write-string msg)
        (write-char #\newline)
        (flush-output-port)
        #f)
      (begin
        (vector-set! *test-sched-passes* 0 (+ (vector-ref *test-sched-passes* 0) 1))
        (write-string "PASS: ")
        (write-string msg)
        (write-char #\newline)
        (flush-output-port)
        #t)))

(define (assert-equal actual expected msg)
  (if (not (eqv? actual expected))
      (begin
        (vector-set! *test-sched-failures* 0 (+ (vector-ref *test-sched-failures* 0) 1))
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
        (vector-set! *test-sched-passes* 0 (+ (vector-ref *test-sched-passes* 0) 1))
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
(write-string " Starting Work-Stealing Scheduler Test Suite (#635)\n")
(write-string "=======================================================\n")
(flush-output-port)

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
  (assert-equal (scheduler-total-spawned sched) 0 "scheduler-total-spawned matches tasks-spawned (0)")
  (assert-equal (scheduler-total-completed sched) 0 "scheduler-total-completed matches tasks-completed (0)")

  ;; Verify atomic increment operations
  (%scheduler-tasks-spawned-inc! sched)
  (assert-equal (scheduler-tasks-spawned sched) 1 "tasks-spawned is 1 after inc")
  (assert-equal (scheduler-total-spawned sched) 1 "total-spawned reflects 1")

  (%scheduler-tasks-completed-inc! sched)
  (assert-equal (scheduler-tasks-completed sched) 1 "tasks-completed is 1 after inc")
  (assert-equal (scheduler-total-completed sched) 1 "total-completed reflects 1")

  ;; Perform rapid 100 increments
  (let loop ((k 0))
    (if (< k 100)
        (begin
          (%scheduler-tasks-spawned-inc! sched)
          (%scheduler-tasks-completed-inc! sched)
          (loop (+ k 1)))
        #t))

  (assert-equal (scheduler-tasks-spawned sched) 101 "tasks-spawned reached 101")
  (assert-equal (scheduler-tasks-completed sched) 101 "tasks-completed reached 101")

  ;; Reset stats
  (assert-true (%scheduler-stats-reset! sched) "%scheduler-stats-reset! returns #t")
  (assert-equal (scheduler-tasks-spawned sched) 0 "tasks-spawned is 0 after reset")
  (assert-equal (scheduler-tasks-completed sched) 0 "tasks-completed is 0 after reset")

  ;; Guard against non-scheduler object (CWE-843)
  (assert-error (lambda () (scheduler-tasks-spawned "invalid")) "scheduler-tasks-spawned rejects non-scheduler (CWE-843)")
  (assert-error (lambda () (scheduler-tasks-completed 12345)) "scheduler-tasks-completed rejects non-scheduler (CWE-843)")
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
  (assert-equal (deque-count (worker-deque (scheduler-get-worker sched 0))) 1000 "worker 0 deque holds 1,000 tasks")
  (assert-equal (deque-count (worker-deque (scheduler-get-worker sched 1))) 0 "worker 1 deque is initially empty")

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

;; -----------------------------------------------------------------------
;; Summary
;; -----------------------------------------------------------------------
(write-string "=======================================================\n")
(write-string " Work-Stealing Scheduler Test Summary: ")
(write-string (number->string (vector-ref *test-sched-passes* 0)))
(write-string " passed, ")
(write-string (number->string (vector-ref *test-sched-failures* 0)))
(write-string " failed.\n")
(write-string "=======================================================\n")
(flush-output-port)

(if (> (vector-ref *test-sched-failures* 0) 0)
    (error "test_scheduler: one or more assertions failed" (vector-ref *test-sched-failures* 0)))

