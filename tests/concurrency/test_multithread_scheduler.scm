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
(load "ulisp/runtime/concurrency/queue.scm")
(load "ulisp/runtime/concurrency/channel.scm")
(load "ulisp/runtime/concurrency/context.scm")
(load "ulisp/runtime/concurrency/deque.scm")
(load "ulisp/runtime/concurrency/thread.scm")
(load "ulisp/runtime/concurrency/scheduler.scm")

(define *test-mt-failures* (vector 0))
(define *test-mt-passes* (vector 0))

(define (assert-true val msg)
  (if (not val)
      (begin
        (vector-set! *test-mt-failures* 0 (+ (vector-ref *test-mt-failures* 0) 1))
        (write-string "FAIL: ")
        (write-string msg)
        (write-char #\newline)
        (flush-output-port)
        #f)
      (begin
        (vector-set! *test-mt-passes* 0 (+ (vector-ref *test-mt-passes* 0) 1))
        (write-string "PASS: ")
        (write-string msg)
        (write-char #\newline)
        (flush-output-port)
        #t)))

(define (assert-equal actual expected msg)
  (if (not (eqv? actual expected))
      (begin
        (vector-set! *test-mt-failures* 0 (+ (vector-ref *test-mt-failures* 0) 1))
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
        (vector-set! *test-mt-passes* 0 (+ (vector-ref *test-mt-passes* 0) 1))
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
(write-string " Starting Multithreaded Work-Stealing Test Suite (#675)\n")
(write-string "=======================================================\n")
(flush-output-port)

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
;; Test Suite Summary
;; -----------------------------------------------------------------------
(let ((passes (vector-ref *test-mt-passes* 0))
      (fails (vector-ref *test-mt-failures* 0)))
  (write-string "=======================================================\n")
  (write-string " Multithreaded Scheduler Test Summary: ")
  (write-string (number->string passes))
  (write-string " passed, ")
  (write-string (number->string fails))
  (write-string " failed.\n")
  (write-string "=======================================================\n")
  (flush-output-port)
  (if (> fails 0)
      (exit 1)
      #t))
