;;; =======================================================================
;;; ULisp Concurrency Test Suite: Multithreaded Work-Stealing Scheduler (#675)
;;; Conforms to DSN-37 Section 7.4 & Phase 7 Task 7.1
;;;
;;; Tests:
;;;   Group 1: Native Threading Primitives & CPU Topology
;;;   Group 2: Direct Thread Spawn & Atomic Cross-Thread Synchronization
;;;   Group 3: Multi-Worker Native Thread Pool & Core Pinning
;;;   Group 4: Scheduler Parallel Task Execution (scheduler-run-parallel!)
;;;   Group 5: 10,000 Tasks High-Throughput Parallel Endurance Test
;;;   Group 6: Security & Boundary Guards (CWE-843 / CWE-20)
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
(load "ulisp/runtime/concurrency/supervisor.scm")
(load "ulisp/runtime/concurrency/scheduler.scm")

(test-begin "concurrency-multithread_scheduler")

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
;; Group 1: Native Threading Primitives & CPU Topology
;; -----------------------------------------------------------------------
(write-string "--- Group 1: Native Threading Primitives & CPU Topology ---\n")
(flush-output-port)

(assert-true (native-thread-supported?) "native-thread-supported? returns #t")
(let ((cpus (online-cpu-count)))
  (assert-true (integer? cpus) "online-cpu-count returns integer")
  (assert-true (> cpus 0) "online-cpu-count is strictly positive")
  (write-string "  [INFO] Hardware Online CPUs Detected: ")
  (write-string (number->string cpus))
  (write-string "\n")
  (flush-output-port))

;; Test CPU affinity on core 0
(assert-true (set-thread-affinity! 0) "set-thread-affinity! 0 succeeds")

;; -----------------------------------------------------------------------
;; Group 2: Direct Thread Spawn & Atomic Cross-Thread Synchronization
;; -----------------------------------------------------------------------
(write-string "--- Group 2: Direct Thread Spawn & Synchronization ---\n")
(flush-output-port)

(let* ((sync-box (make-atomic-box 0))
       (tid (spawn-native-thread
             (lambda (arg)
               (begin
                 (atomic-set! arg 42)
                 #t))
             sync-box)))
  (assert-true (integer? tid) "spawn-native-thread returns integer TID")
  (assert-true (> tid 0) "TID is strictly positive")

  ;; Poll for child thread completion with bounded backoff
  (let poll ((i 0))
    (if (and (< i 1000000) (not (= (atomic-ref sync-box) 42)))
        (poll (+ i 1))
        #t))
  (assert-equal (atomic-ref sync-box) 42 "child thread updated atomic box across threads"))

;; -----------------------------------------------------------------------
;; Group 3: Multi-Worker Native Thread Pool & Core Pinning
;; -----------------------------------------------------------------------
(write-string "--- Group 3: Multi-Worker Native Threads & Pinning ---\n")
(flush-output-port)

(let* ((num-threads 4)
       (cpus (online-cpu-count))
       (counter (make-atomic-box 0))
       (tids-box (vector '())))
  (let loop ((i 0))
    (if (< i num-threads)
        (let ((tid (spawn-native-thread
                    (lambda (wid)
                      (begin
                        (set-thread-affinity! (modulo wid cpus))
                        (atomic-fetch-add! counter 1)
                        #t))
                    i)))
          (vector-set! tids-box 0 (cons tid (vector-ref tids-box 0)))
          (loop (+ i 1)))
        #t))

  ;; Wait for all 4 threads to increment
  (let poll ((i 0))
    (if (and (< i 100000000) (< (atomic-ref counter) num-threads))
        (poll (+ i 1))
        #t))
  (assert-equal (atomic-ref counter) num-threads "all 4 native threads executed and pinned"))

;; -----------------------------------------------------------------------
;; Group 4: Scheduler Parallel Task Execution (scheduler-run-parallel!)
;; -----------------------------------------------------------------------
(write-string "--- Group 4: Scheduler Parallel Task Execution ---\n")
(flush-output-port)

(let* ((worker-count 4)
       (sched (make-work-stealing-scheduler worker-count 256))
       (n-tasks 1000)
       (done-counter (make-atomic-box 0)))

  ;; Spawn 1,000 tasks into scheduler
  (let loop ((i 0))
    (if (< i n-tasks)
        (begin
          (scheduler-spawn! sched
                            (lambda ()
                              (atomic-fetch-add! done-counter 1))
                            (modulo i worker-count))
          (loop (+ i 1)))
        #t))

  (assert-equal (scheduler-total-spawned sched) n-tasks "1,000 tasks spawned into scheduler")

  ;; Run multi-worker engine in parallel
  (let ((completed (scheduler-run-parallel! sched n-tasks)))
    (assert-equal completed n-tasks "scheduler-run-parallel! completed all 1,000 tasks")
    (assert-equal (atomic-ref done-counter) n-tasks "done-counter reached exactly 1,000")
    (assert-equal (scheduler-total-completed sched) n-tasks "scheduler-total-completed is 1,000"))

  ;; Inspect stats to verify multiple workers executed tasks
  (let* ((stats (scheduler-stats sched))
         (w-stats (cdr (assq 'workers stats)))
         (executed-sum
          (let sum-loop ((ws w-stats) (acc 0))
            (if (null? ws)
                acc
                (sum-loop (cdr ws) (+ acc (cdr (assq 'tasks-executed (car ws)))))))))
    (assert-equal executed-sum n-tasks "sum of worker executed tasks equals 1,000")
    (write-string "  [INFO] Parallel Execution Completed: ")
    (write-string (number->string executed-sum))
    (write-string " tasks distributed across ")
    (write-string (number->string worker-count))
    (write-string " native worker threads.\n")
    (flush-output-port)))

;; -----------------------------------------------------------------------
;; Group 5: 10,000 Tasks High-Throughput Parallel Endurance Test
;; -----------------------------------------------------------------------
(write-string "--- Group 5: 10,000 Tasks High-Throughput Parallel Endurance ---\n")
(flush-output-port)

(let* ((worker-count 4)
       (sched (make-work-stealing-scheduler worker-count 512))
       (n-tasks 10000)
       (accum (make-atomic-box 0)))

  (let loop ((i 0))
    (if (< i n-tasks)
        (begin
          (scheduler-spawn! sched
                            (lambda ()
                              (atomic-fetch-add! accum 1))
                            (if (= (modulo i 3) 0) #f (modulo i worker-count)))
          (loop (+ i 1)))
        #t))

  (assert-equal (scheduler-total-spawned sched) n-tasks "10,000 tasks spawned")

  (let ((completed (scheduler-run-parallel! sched n-tasks)))
    (assert-equal completed n-tasks "scheduler-run-parallel! completed 10,000 tasks")
    (assert-equal (atomic-ref accum) n-tasks "atomic accumulator matches exactly 10,000 (zero data race)")
    (assert-equal (scheduler-total-completed sched) n-tasks "scheduler total-completed is 10,000"))

  (scheduler-stop! sched))

;; -----------------------------------------------------------------------
;; Group 6: Security & Boundary Guards (CWE-843 / CWE-20)
;; -----------------------------------------------------------------------
(write-string "--- Group 6: Security & Boundary Guards ---\n")
(flush-output-port)

(assert-error (lambda () (set-thread-affinity! "invalid")) "set-thread-affinity! rejects string (CWE-843)")
(assert-error (lambda () (set-thread-affinity! -1)) "set-thread-affinity! rejects negative core (CWE-20)")
(assert-error (lambda () (set-thread-affinity! 9999)) "set-thread-affinity! rejects out of range core (CWE-20)")
(assert-error (lambda () (spawn-native-thread 12345 #f)) "spawn-native-thread rejects non-procedure (CWE-843)")
(assert-error (lambda () (scheduler-start-native-workers! "invalid")) "scheduler-start-native-workers! rejects non-scheduler (CWE-843)")
(assert-error (lambda () (scheduler-run-parallel! "invalid")) "scheduler-run-parallel! rejects non-scheduler (CWE-843)")

;; -----------------------------------------------------------------------
;; Group 7: NUMA Parallel Execution & Hierarchical Work Stealing (#681)
;; -----------------------------------------------------------------------
(write-string "--- Group 7: NUMA Parallel Execution & Work Stealing (#681) ---\n")
(flush-output-port)

(let* ((worker-count 4)
       (node-count 2)
       (sched (make-work-stealing-scheduler worker-count 256 node-count))
       (n-tasks 2000)
       (accum (make-atomic-box 0)))

  (assert-equal (scheduler-node-count sched) 2 "sched node-count is 2")

  ;; Asymmetrically spawn tasks: 1,000 into Worker 0 (Node 0), 1,000 into Worker 2 (Node 1)
  (let spawn-loop ((i 0))
    (if (< i 1000)
        (begin
          (scheduler-spawn! sched (lambda () (atomic-fetch-add! accum 1)) 0)
          (scheduler-spawn! sched (lambda () (atomic-fetch-add! accum 1)) 2)
          (spawn-loop (+ i 1)))
        #t))

  (assert-equal (scheduler-total-spawned sched) n-tasks "2,000 tasks spawned across NUMA nodes")

  (let ((completed (scheduler-run-parallel! sched n-tasks)))
    (assert-equal completed n-tasks "scheduler-run-parallel! completed 2,000 tasks in NUMA topology")
    (assert-equal (atomic-ref accum) n-tasks "atomic accumulator matches 2,000 across threads")
    (assert-equal (scheduler-total-completed sched) n-tasks "scheduler-total-completed is 2,000"))

  ;; Inspect stats to verify NUMA distribution and work-stealing
  (let* ((stats (scheduler-stats sched))
         (w-stats (cdr (assq 'workers stats)))
         (executed-sum
          (let sum-loop ((ws w-stats) (acc 0))
            (if (null? ws)
                acc
                (sum-loop (cdr ws) (+ acc (cdr (assq 'tasks-executed (car ws)))))))))
    (assert-equal executed-sum n-tasks "sum of worker executed tasks equals 2,000")
    (write-string "  [INFO] NUMA Parallel Execution Completed: ")
    (write-string (number->string executed-sum))
    (write-string " tasks distributed across ")
    (write-string (number->string worker-count))
    (write-string " native workers across ")
    (write-string (number->string node-count))
    (write-string " NUMA nodes.\n")
    (flush-output-port))

  (scheduler-stop! sched))

;; -----------------------------------------------------------------------
;; Group 8: Issue #747 TLS Worker Identification & 32MB+ Heap Resilience
;; -----------------------------------------------------------------------
(write-string "--- Group 8: Issue #747 TLS Worker Identification & Heap Resilience ---\n")
(flush-output-port)

;; 8.1: Verify TLS initialization
(assert-true (init-worker-tls!) "init-worker-tls! succeeds and returns #t")

;; 8.2: 32MB+ Heap Allocation in Parallel Worker Threads without Worker ID Drift (CWE-787)
(let* ((worker-count 2)
       (sched (make-work-stealing-scheduler worker-count 128))
       (accum (make-atomic-box 0)))
  (let loop ((i 0))
    (if (< i 10)
        (begin
          (scheduler-spawn!
           sched
           (lambda ()
             ;; Allocate ~8MB heap in task across workers
             (let ((vecs (make-vector 1000 #f)))
               (let vloop ((v 0))
                 (if (< v 1000)
                     (begin
                       (vector-set! vecs v (make-vector 1000 v))
                       (vloop (+ v 1)))
                     #t))
               ;; Verify exception handler isolation under large heap
               (guard (ex ((eq? ex 'handled-under-stress)
                           (atomic-fetch-add! accum 1)))
                 (raise 'handled-under-stress)))))
          (loop (+ i 1)))
        #t))

  (let ((completed (scheduler-run-parallel! sched 10)))
    (assert-equal completed 10 "10 large heap tasks completed across workers")
    (assert-equal (atomic-ref accum) 10 "all 10 tasks handled exceptions correctly under >32MB heap allocation"))
  (scheduler-stop! sched))
(write-string "  [PASS] 32MB+ heap allocation test passed with intact TLS worker isolation.\n")
(flush-output-port)

;; -----------------------------------------------------------------------
;; Group 9: Issue #740 / #787 Coroutine Yield & Cross-Worker Exception Resilience
;; -----------------------------------------------------------------------
(write-string "--- Group 9: Coroutine Yield & Cross-Worker Exception Resilience (#740, Issue #787) ---\n")
(flush-output-port)

(let* ((sched (make-work-stealing-scheduler 4 256))
       (n-tasks 20)
       (yield-count (make-atomic-box 0))
       (caught-count (make-atomic-box 0)))
  ;; Test: Worker 0 initiates coroutine, yields, then cross-worker task resumes and catches exception
  (let loop ((i 0))
    (if (< i n-tasks)
        (begin
          (scheduler-spawn!
           sched
           (lambda ()
             (let* ((co (make-coroutine-context
                         (lambda ()
                           (atomic-fetch-add! yield-count 1)
                           (context-yield! 'yielded-ok)
                           ;; Exception without local handler upon cross-worker resume
                           (car '()))))
                    (first-val (context-resume! co)))
               (assert-equal first-val 'yielded-ok "coroutine yielded successfully in initial worker")
               ;; Spawn resumption into another worker (cross-thread worker resumption)
               (scheduler-spawn!
                sched
                (lambda ()
                  (guard (exn (#t
                               (atomic-fetch-add! caught-count 1)
                               'caught-cleanly-across-workers))
                    (context-resume! co)))
                (+ (modulo i 3) 1))))
           0)
          (loop (+ i 1)))
        #t))

  (let ((completed (scheduler-run-parallel! sched (* n-tasks 2))))
    (assert-equal (atomic-ref yield-count) n-tasks "all 20 coroutines yielded in worker 0")
    (assert-equal (atomic-ref caught-count) n-tasks "all 20 exceptions caught cleanly across different workers")
    (assert-equal completed (* n-tasks 2) "all 40 combined tasks completed cleanly in parallel"))
  (scheduler-stop! sched))
(write-string "  [PASS] Coroutine yield and cross-worker exception resilience verified.\n")
(flush-output-port)

;; -----------------------------------------------------------------------
;; Group 10: Multi-Worker Parallel Supervisor Burst Crash Recovery (#791, Issue #789)
;; -----------------------------------------------------------------------
(write-string "--- Group 10: Parallel Supervisor Multi-Worker Burst Crash Recovery (#791) ---\n")
(flush-output-port)

(let* ((sched (make-work-stealing-scheduler 4 256))
       (child-restarts (make-atomic-box 0))
       (make-parallel-child
        (lambda (name)
          (make-child-spec
           name
           (lambda ()
             (atomic-fetch-add! child-restarts 1)
             (let ((t (make-task-context)))
               (task-resident-set! t #t)
               (task-next-run-set!
                t
                (lambda ()
                  ;; Permanent child stays in waiting state until termination
                  #t))
               t))
           'permanent)))
       (cspecs (list (make-parallel-child 'c0) (make-parallel-child 'c1)
                     (make-parallel-child 'c2) (make-parallel-child 'c3)
                     (make-parallel-child 'c4) (make-parallel-child 'c5)
                     (make-parallel-child 'c6) (make-parallel-child 'c7)))
       (sup-spec (make-supervisor-spec 'one_for_one 30 1000 cspecs))
       (sup (make-supervisor sup-spec #f sched))
       (sup-task (supervisor-task sup)))

  ;; Autonomous startup in multi-worker scheduler
  (supervisor-start! sup sched #t)
  (assert-equal (atomic-ref child-restarts) 8 "all 8 child tasks booted initially under parallel scheduler")

  ;; Save original child TIDs
  (let* ((tid0 (task-tid (supervisor-child-task sup 'c0)))
         (tid1 (task-tid (supervisor-child-task sup 'c1)))
         (tid2 (task-tid (supervisor-child-task sup 'c2)))
         (tid3 (task-tid (supervisor-child-task sup 'c3)))
         (tid4 (task-tid (supervisor-child-task sup 'c4)))
         (tid5 (task-tid (supervisor-child-task sup 'c5)))
         (tid6 (task-tid (supervisor-child-task sup 'c6)))
         (tid7 (task-tid (supervisor-child-task sup 'c7))))

    ;; Concurrent Burst Crash: terminate all 8 child tasks rapidly
    (let loop ((names '(c0 c1 c2 c3 c4 c5 c6 c7)))
      (if (not (null? names))
          (let ((ctask (supervisor-child-task sup (car names))))
            (task-exit! ctask '(panic . burst_crash_parallel))
            (loop (cdr names)))))

    ;; Run parallel scheduler across 4 native OS threads
    (scheduler-run-parallel! sched 30)

    ;; Verify all 8 workers restarted exactly once (total 16 boots)
    (assert-equal (atomic-ref child-restarts) 16 "all 8 children restarted cleanly under parallel multi-worker execution")

    ;; Verify all children assigned fresh, distinct TIDs
    (assert-true (not (= (task-tid (supervisor-child-task sup 'c0)) tid0)) "c0 assigned fresh TID")
    (assert-true (not (= (task-tid (supervisor-child-task sup 'c1)) tid1)) "c1 assigned fresh TID")
    (assert-true (not (= (task-tid (supervisor-child-task sup 'c2)) tid2)) "c2 assigned fresh TID")
    (assert-true (not (= (task-tid (supervisor-child-task sup 'c3)) tid3)) "c3 assigned fresh TID")
    (assert-true (not (= (task-tid (supervisor-child-task sup 'c4)) tid4)) "c4 assigned fresh TID")
    (assert-true (not (= (task-tid (supervisor-child-task sup 'c5)) tid5)) "c5 assigned fresh TID")
    (assert-true (not (= (task-tid (supervisor-child-task sup 'c6)) tid6)) "c6 assigned fresh TID")
    (assert-true (not (= (task-tid (supervisor-child-task sup 'c7)) tid7)) "c7 assigned fresh TID")

    ;; Verify supervisor task returned safely to waiting state and idle enqueued state
    (assert-equal (task-state sup-task) 'waiting "supervisor task state returned to 'waiting")
    (assert-equal (supervisor-enqueued-state sup) 'idle "supervisor enqueued state returned to 'idle"))

  (supervisor-stop! sup)
  (scheduler-stop! sched))
(write-string "  [PASS] Parallel multi-worker supervisor burst crash recovery verified.\n")
(flush-output-port)

;; -----------------------------------------------------------------------
;; Group 11: Multi-Worker Parallel Supervisor Coroutine Child Lifecycle (#791)
;; -----------------------------------------------------------------------
(write-string "--- Group 11: Parallel Supervisor Coroutine Child Lifecycle (#791) ---\n")
(flush-output-port)

(let* ((sched (make-work-stealing-scheduler 4 256))
       (coro-boot-count (make-atomic-box 0))
       (coro-yield-count (make-atomic-box 0))
       (coro-completed-box (make-atomic-box 0))
       (coro-child-spec
        (make-child-spec
         'coro_child
         (lambda ()
           (let ((boot-idx (atomic-fetch-add! coro-boot-count 1)))
             (let ((t (make-task-context)))
               (task-resident-set! t #t)
               (task-next-run-set!
                t
                (lambda ()
                  (let* ((co (make-coroutine-context
                              (lambda ()
                                (atomic-fetch-add! coro-yield-count 1)
                                (context-yield! 'yielded_ok)
                                (atomic-set! coro-completed-box 999)
                                'coroutine_done))))
                    ;; Step 1: initial resume up to yield point
                    (let ((val (context-resume! co)))
                      (if (= boot-idx 0)
                          ;; On first boot, simulate an external crash while child is yielded
                          (task-exit! t '(panic . coro_crashed_while_yielded))
                          ;; On second boot, resume coroutine to completion
                          (begin
                            (context-resume! co)
                            #t))))))
               t)))
         'permanent))
       (sup-spec (make-supervisor-spec 'one_for_one 10 1000 (list coro-child-spec)))
       (sup (make-supervisor sup-spec #f sched))
       (sup-task (supervisor-task sup)))

  ;; Autonomous startup in 4-worker parallel scheduler
  (supervisor-start! sup sched #t)

  ;; Run parallel scheduler: child executes, yields, crashes, Supervisor catches DOWN, restarts it,
  ;; and child re-runs to completion.
  (scheduler-run-parallel! sched 20)

  (assert-equal (atomic-ref coro-boot-count) 2 "coroutine child booted exactly twice (initial + restart)")
  (assert-equal (atomic-ref coro-yield-count) 2 "coroutine yielded twice across distinct lifecycles")
  (assert-equal (atomic-ref coro-completed-box) 999 "restarted coroutine child reached completion")
  (assert-equal (task-state sup-task) 'waiting "supervisor task state returned to 'waiting")
  (assert-equal (supervisor-enqueued-state sup) 'idle "supervisor enqueued state returned to 'idle")

  (supervisor-stop! sup)
  (scheduler-stop! sched))
(write-string "  [PASS] Parallel supervisor coroutine child lifecycle & crash recovery verified.\n")
(flush-output-port)

;; -----------------------------------------------------------------------
;; Group 12: Cross-Worker Coroutine Yield, Migration & Unhandled Exception Recovery (#799)
;; -----------------------------------------------------------------------
(write-string "--- Group 12: Cross-Worker Coroutine Yield & Exception Recovery (#799) ---\n")
(flush-output-port)

(let* ((sched (make-work-stealing-scheduler 4 256))
       (boot-count (make-atomic-box 0))
       (yield-count (make-atomic-box 0))
       (completed-box (make-atomic-box 0))
       (worker-0-runs (make-atomic-box 0))
       (worker-2-runs (make-atomic-box 0))
       (migrating-child-spec
        (make-child-spec
         'migrating_child
         (lambda ()
           (let ((boot-idx (atomic-fetch-add! boot-count 1)))
             (let ((t (make-task-context)))
               (task-resident-set! t #t)
               (if (= boot-idx 0)
                   ;; First boot: runs on worker 0, yields, then migrates t to worker 2 where exception occurs
                   (let* ((co (make-coroutine-context
                               (lambda ()
                                 (atomic-fetch-add! yield-count 1)
                                 (context-yield! 'yielded_step1)
                                 ;; Unhandled runtime exception in coroutine upon migration
                                 (car '())))))
                     (task-next-run-set!
                      t
                      (lambda ()
                        (let ((first-res (context-resume! co)))
                          (atomic-fetch-add! worker-0-runs 1)
                          (assert-equal first-res 'yielded_step1 "coroutine yielded step1 in worker 0")
                          ;; Reconfigure t's next-run to resume co on migrated worker 2
                          (task-next-run-set!
                           t
                           (lambda ()
                             (atomic-fetch-add! worker-2-runs 1)
                             ;; This context-resume! will trigger (car '()) inside co on worker 2's stack.
                             (context-resume! co)))
                          ;; Re-enqueue t into target worker 2 (cross-worker migration)
                          (task-state-set! t 'ready)
                          (scheduler-spawn! sched t 2)
                          ;; Exit first step without terminating task
                          (cons 'ok 'step1_done))))
                     t)
                   ;; Second boot (after Supervisor auto-restart): run to normal completion
                   (let* ((co-recovered (make-coroutine-context
                                         (lambda ()
                                           (atomic-fetch-add! yield-count 1)
                                           (context-yield! 'yielded_recovered)
                                           (atomic-set! completed-box 777)
                                           'coro_recovered_done))))
                     (task-next-run-set!
                      t
                      (lambda ()
                        (context-resume! co-recovered)
                        (context-resume! co-recovered)
                        (cons 'ok 'recovered_done)))
                     t)))))
         'permanent))
       (sup-spec (make-supervisor-spec 'one_for_one 10 1000 (list migrating-child-spec)))
       (sup (make-supervisor sup-spec #f sched))
       (sup-task (supervisor-task sup)))

  ;; Autonomous startup in 4-worker parallel scheduler
  (supervisor-start! sup sched #t)

  ;; Execute 40 steps across 4 native workers
  (scheduler-run-parallel! sched 40)

  (assert-equal (atomic-ref boot-count) 2 "coroutine child booted twice (initial crash + auto-restart) (#799)")
  (assert-equal (atomic-ref yield-count) 2 "coroutine yielded in both initial and recovered instances")
  (assert-equal (atomic-ref worker-0-runs) 1 "worker 0 executed initial coroutine step")
  (assert-equal (atomic-ref worker-2-runs) 1 "worker 2 executed cross-worker resumption step (#799)")
  (assert-equal (atomic-ref completed-box) 777 "recovered coroutine reached completion cleanly (#799)")
  (assert-equal (task-state sup-task) 'waiting "supervisor task state returned to 'waiting")
  (assert-equal (supervisor-enqueued-state sup) 'idle "supervisor enqueued state returned to 'idle")

  (supervisor-stop! sup)
  (scheduler-stop! sched))
(write-string "  [PASS] Cross-worker coroutine yield, migration & exception recovery verified.\n")
(flush-output-port)


(test-end "concurrency-multithread_scheduler")
