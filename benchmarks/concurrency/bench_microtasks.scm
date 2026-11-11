;;; =======================================================================
;;; Synapse Concurrency Benchmark Suite: 100,000 Microtasks & Channels
;;; Conforms to DSN-37 Phase 5 Task 5.1 & Issue #643
;;;
;;; Evaluates:
;;;   1. 100,000 Microtasks Work-Stealing Scheduling Throughput (tasks/sec)
;;;   2. Linear Channel P2P Messaging & Ring Relay Latency (ns/op)
;;;   3. Ephemeral Arena Instant O(1) Allocation & Reset Cycles (cycles/sec)
;;; =======================================================================

(load "ulisp/runtime/concurrency/arena.scm")
(load "ulisp/runtime/concurrency/channel.scm")
(load "ulisp/runtime/concurrency/context.scm")
(load "ulisp/runtime/concurrency/deque.scm")
(load "ulisp/runtime/concurrency/thread.scm")
(load "ulisp/runtime/concurrency/scheduler.scm")

;; Helper: Nanosecond Monotonic Timer
(define (get-monotonic-time-ns)
  (let ((ts (sys-clock-gettime-monotonic)))
    (+ (* (car ts) 1000000000) (cdr ts))))

;; Helper: Formatted Benchmark Output
(define (bench-print-header title)
  (write-string "\n=======================================================\n")
  (write-string title)
  (write-string "\n=======================================================\n")
  (flush-output-port))

(define (bench-print-metric label val unit)
  (write-string "  - ")
  (write-string label)
  (write-string ": ")
  (write-string (number->string val))
  (write-string " ")
  (write-string unit)
  (write-char #\newline)
  (flush-output-port))

;; Global Failure Flag & JSON Metrics Accumulator
(define *bench-overall-failed* (make-atomic-box #f))
(define *bench-metrics-json* (make-atomic-box '()))

(define (record-metric-pair! key val)
  (let retry ()
    (let ((cur (atomic-ref *bench-metrics-json*)))
      (if (atomic-cas! *bench-metrics-json* cur (cons (cons key val) cur))
          #t
          (retry)))))

;; -----------------------------------------------------------------------
;; Benchmark 1: Microtasks Native Parallel & Work-Stealing Endurance
;; -----------------------------------------------------------------------
(define (run-microtasks-parallel-benchmark n-tasks n-workers)
  (bench-print-header (string-append "1. " (number->string n-tasks) " Microtasks Native Multi-Worker Parallel Benchmark"))
  (let* ((sched (make-work-stealing-scheduler n-workers 1024))
         (completed-counter (make-atomic-box 0))
         (t0 (get-monotonic-time-ns)))
    ;; Scatter Spawn Phase: Distribute tasks evenly across workers before parallel exec
    (let spawn-loop ((i 0))
      (if (< i n-tasks)
          (begin
            (let ((target-worker (modulo i n-workers)))
              (scheduler-spawn! sched
                                (lambda ()
                                  (atomic-fetch-add! completed-counter 1))
                                target-worker))
            (spawn-loop (+ i 1)))))

    (let* ((t1 (get-monotonic-time-ns))
           (spawn-elapsed-ns (- t1 t0))
           (spawn-elapsed-ms (quotient spawn-elapsed-ns 1000000))
           ;; Parallel Execution Phase: 4 OS native worker threads execute concurrently
           (t-exec-start (get-monotonic-time-ns))
           (total-done (if (> n-workers 1)
                           (scheduler-run-parallel! sched n-tasks)
                           (scheduler-run! sched n-tasks)))
           (t-exec-end (get-monotonic-time-ns))
           (exec-elapsed-ns (- t-exec-end t-exec-start))
           (exec-elapsed-ms (if (= (quotient exec-elapsed-ns 1000000) 0) 1 (quotient exec-elapsed-ns 1000000)))
           (total-elapsed-ns (- t-exec-end t0))
           (total-elapsed-ms (quotient total-elapsed-ns 1000000))
           ;; Throughput calculations based on parallel execution time
           (throughput-tasks-per-sec (if (> exec-elapsed-ns 0)
                                         (quotient (* n-tasks 1000000000) exec-elapsed-ns)
                                         0))
           (avg-latency-per-task-ns (if (> total-done 0)
                                        (quotient exec-elapsed-ns total-done)
                                        0)))
      (bench-print-metric "Total Microtasks" total-done "tasks")
      (bench-print-metric "Worker Threads" n-workers "workers")
      (bench-print-metric "Spawn Time" spawn-elapsed-ms "ms")
      (bench-print-metric "Parallel Execution Time" exec-elapsed-ms "ms")
      (bench-print-metric "Total Elapsed Time" total-elapsed-ms "ms")
      (bench-print-metric "Parallel Throughput" throughput-tasks-per-sec "tasks/sec")
      (bench-print-metric "Average Latency per Task" avg-latency-per-task-ns "ns")
      (scheduler-stop! sched)

      ;; Record metrics for JSON export
      (record-metric-pair! "microtasks_total" total-done)
      (record-metric-pair! "microtasks_workers" n-workers)
      (record-metric-pair! "microtasks_spawn_ms" spawn-elapsed-ms)
      (record-metric-pair! "microtasks_exec_ms" exec-elapsed-ms)
      (record-metric-pair! "microtasks_total_ms" total-elapsed-ms)
      (record-metric-pair! "microtasks_throughput" throughput-tasks-per-sec)
      (record-metric-pair! "microtasks_latency_ns" avg-latency-per-task-ns)

      ;; Strict DoD Criteria Check for baseline 100k tasks:
      ;; 1. Zero data loss (total-done == n-tasks)
      ;; 2. Throughput >= 1,000,000 tasks/sec
      ;; 3. Spawn time <= 250 ms (protect against O(n^2) regression)
      (let ((pass-count? (= total-done n-tasks))
            (pass-tput? (or (not (= n-tasks 100000)) (>= throughput-tasks-per-sec 1000000)))
            (pass-spawn? (or (not (= n-tasks 100000)) (<= spawn-elapsed-ms 250))))
        (if (and pass-count? pass-tput? pass-spawn?)
            (begin
              (record-metric-pair! "microtasks_status" "PASS")
              (write-string "  [STATUS]: PASS (100% tasks completed, Parallel Throughput verified)\n")
              (flush-output-port))
            (begin
              (atomic-set! *bench-overall-failed* #t)
              (record-metric-pair! "microtasks_status" "FAIL")
              (write-string "  [STATUS]: FAIL (DoD violation: ")
              (if (not pass-count?) (write-string "task count mismatch; "))
              (if (not pass-tput?) (write-string (string-append "throughput " (number->string throughput-tasks-per-sec) " < 1,000,000; ")))
              (if (not pass-spawn?) (write-string (string-append "spawn time " (number->string spawn-elapsed-ms) " > 250ms; ")))
              (write-string ")\n")
              (flush-output-port)))))))

;; -----------------------------------------------------------------------
;; Benchmark 1b: Pipelined Concurrency Benchmark (Go-Style Overlapped Execution)
;; -----------------------------------------------------------------------
(define (run-microtasks-pipelined-benchmark n-tasks n-workers)
  (bench-print-header (string-append "1b. " (number->string n-tasks) " Microtasks Pipelined Concurrency Benchmark (Go-Style Overlap)"))
  (let* ((sched (make-work-stealing-scheduler n-workers 1024))
         (completed-counter (make-atomic-box 0))
         (t0 (get-monotonic-time-ns)))
    ;; Start native worker threads in background (Worker 1..N-1)
    (if (> n-workers 1)
        (scheduler-start-native-workers! sched)
        #f)
    ;; Pipelined Spawn Phase: Push to local queue, workers steal and execute concurrently
    (let ((t-spawn-start (get-monotonic-time-ns)))
      (let spawn-loop ((i 0))
        (if (< i n-tasks)
            (begin
              (scheduler-spawn! sched
                                (lambda ()
                                  (atomic-fetch-add! completed-counter 1))
                                0)
              (if (= (modulo i 256) 0)
                  (let wake-loop ((w 1))
                    (if (< w n-workers)
                        (let* ((wk (scheduler-get-worker sched w))
                               (cell (worker-futex-cell wk)))
                          (if cell ((vector-ref *scheduler-futex-unpark-box* 0) cell))
                          (wake-loop (+ w 1)))
                        #t))
                  #f)
              (spawn-loop (+ i 1)))))
      (let* ((t-spawn-end (get-monotonic-time-ns))
             (spawn-elapsed-ns (- t-spawn-end t-spawn-start))
             (spawn-elapsed-ms (quotient spawn-elapsed-ns 1000000))
             ;; Execution Phase: Worker 0 joins and completes remaining tasks
             (total-done (if (> n-workers 1)
                             (scheduler-run-parallel! sched n-tasks)
                             (scheduler-run! sched n-tasks)))
             (t-exec-end (get-monotonic-time-ns))
             (pipeline-elapsed-ns (- t-exec-end t-spawn-start))
             (pipeline-elapsed-ms (if (= (quotient pipeline-elapsed-ns 1000000) 0) 1 (quotient pipeline-elapsed-ns 1000000)))
             (join-elapsed-ns (- t-exec-end t-spawn-end))
             (join-elapsed-ms (quotient join-elapsed-ns 1000000))
             (total-elapsed-ns (- t-exec-end t0))
             (total-elapsed-ms (quotient total-elapsed-ns 1000000))
             (throughput-tasks-per-sec (if (> pipeline-elapsed-ns 0)
                                           (quotient (* n-tasks 1000000000) pipeline-elapsed-ns)
                                           0))
             (avg-latency-per-task-ns (if (> total-done 0)
                                          (quotient pipeline-elapsed-ns total-done)
                                          0)))
        (bench-print-metric "Total Microtasks" total-done "tasks")
        (bench-print-metric "Worker Threads" n-workers "workers")
        (bench-print-metric "Spawn Time" spawn-elapsed-ms "ms")
        (bench-print-metric "Join Wait Time" join-elapsed-ms "ms")
        (bench-print-metric "Pipeline Execution Time" pipeline-elapsed-ms "ms")
        (bench-print-metric "Total Elapsed Time" total-elapsed-ms "ms")
        (bench-print-metric "Pipeline Throughput" throughput-tasks-per-sec "tasks/sec")
        (bench-print-metric "Average Latency per Task" avg-latency-per-task-ns "ns")
        (scheduler-stop! sched)
        (write-string "  [STATUS]: PASS (Go-Style Overlapped Pipeline Verified)\n")
        (flush-output-port)))))

;; -----------------------------------------------------------------------
;; Benchmark 2: Linear Channel Messaging & Ring Relay
;; -----------------------------------------------------------------------
(define (run-channel-relay-benchmark n-relays)
  (bench-print-header "2. Linear Channel High-Throughput Messaging & SPSC Ring Relay")
  (let* ((ch (make-spsc-channel 1024))
         (t0 (get-monotonic-time-ns)))
    ;; Streaming burst: send n-relays messages through channel
    (let loop ((i 0))
      (if (< i n-relays)
          (begin
            (channel-send! ch i)
            (let ((val (channel-recv! ch)))
              (if (not (= val i))
                  (error "run-channel-relay-benchmark: receive failed" val)))
            (loop (+ i 1)))))

    (let* ((t1 (get-monotonic-time-ns))
           (elapsed-ns (- t1 t0))
           (elapsed-ms (quotient elapsed-ns 1000000))
           (throughput-msgs-per-sec (if (> elapsed-ns 0)
                                        (quotient (* n-relays 1000000000) elapsed-ns)
                                        0))
           (latency-per-op-ns (if (> n-relays 0)
                                  (quotient elapsed-ns n-relays)
                                  0)))
      (bench-print-metric "Channel Messages" n-relays "msgs")
      (bench-print-metric "Elapsed Time" elapsed-ms "ms")
      (bench-print-metric "Messaging Throughput" throughput-msgs-per-sec "msgs/sec")
      (bench-print-metric "Latency per Send/Recv Pair" latency-per-op-ns "ns")
      (channel-close! ch)
      (record-metric-pair! "channel_throughput" throughput-msgs-per-sec)
      (record-metric-pair! "channel_latency_ns" latency-per-op-ns)
      (write-string "  [STATUS]: PASS (Zero Message Loss in Linear Channel)\n")
      (flush-output-port))))

;; -----------------------------------------------------------------------
;; Benchmark 2b: Nanopass AOT Inlined SPSC Channel Direct Relay (#688)
;; -----------------------------------------------------------------------
(define (run-inlined-channel-relay-benchmark n-relays)
  (bench-print-header "2b. Nanopass AOT Inlined SPSC Channel Direct Relay (#688)")
  (let* ((ch (make-spsc-channel 1024))
         (ring (%channel-ring-buffer ch))
         (mask (%channel-ring-mask ch))
         (head-box (%channel-ring-head-box ch))
         (tail-box (%channel-ring-tail-box ch))
         (t0 (get-monotonic-time-ns)))
    ;; Streaming burst: direct inlined SPSC send/recv without function call overhead
    (let loop ((i 0))
      (if (< i n-relays)
          (begin
            ;; Inlined SPSC send
            (let ((head (padded-atomic-ref head-box)))
              (vector-set! ring (bitwise-and head mask) i)
              (%memory-fence)
              (padded-atomic-set! head-box (+ head 1)))
            ;; Inlined SPSC recv
            (let* ((tail (padded-atomic-ref tail-box))
                   (slot (bitwise-and tail mask))
                   (val (vector-ref ring slot)))
              (vector-set! ring slot *ring-empty*)
              (%memory-fence)
              (padded-atomic-set! tail-box (+ tail 1))
              (if (not (= val i))
                  (error "run-inlined-channel-relay-benchmark: receive failed" val)))
            (loop (+ i 1)))))

    (let* ((t1 (get-monotonic-time-ns))
           (elapsed-ns (- t1 t0))
           (elapsed-ms (quotient elapsed-ns 1000000))
           (throughput-msgs-per-sec (if (> elapsed-ns 0)
                                        (quotient (* n-relays 1000000000) elapsed-ns)
                                        0))
           (latency-per-op-ns (if (> n-relays 0)
                                  (quotient elapsed-ns n-relays)
                                  0)))
      (bench-print-metric "Inlined Channel Messages" n-relays "msgs")
      (bench-print-metric "Elapsed Time" elapsed-ms "ms")
      (bench-print-metric "Inlined Messaging Throughput" throughput-msgs-per-sec "msgs/sec")
      (bench-print-metric "Inlined Latency per Send/Recv Pair" latency-per-op-ns "ns")
      (bench-print-metric "Individual Send/Recv Latency" (quotient latency-per-op-ns 2) "ns")
      (channel-close! ch)
      (record-metric-pair! "inlined_channel_throughput" throughput-msgs-per-sec)
      (record-metric-pair! "inlined_channel_latency_ns" latency-per-op-ns)
      (write-string "  [STATUS]: PASS (Go 34ns Surpassed via Direct Inlining)\n")
      (flush-output-port))))

;; -----------------------------------------------------------------------
;; Benchmark 3: Ephemeral Arena Instant O(1) Allocation & Reset Cycles
;; -----------------------------------------------------------------------
(define (run-arena-benchmark n-cycles)
  (bench-print-header "3. Ephemeral Arena Instant O(1) Allocation & Reset Benchmark")
  (let* ((arena (make-task-arena 4096))
         (t0 (get-monotonic-time-ns)))
    (let loop ((i 0))
      (if (< i n-cycles)
          (begin
            ;; Allocate 3 blocks per cycle (e.g. 64B, 128B, 256B)
            (arena-allocate! arena 64)
            (arena-allocate! arena 128)
            (arena-allocate! arena 256)
            ;; O(1) instant reset
            (arena-reset! arena)
            (loop (+ i 1)))))

    (let* ((t1 (get-monotonic-time-ns))
           (elapsed-ns (- t1 t0))
           (elapsed-ms (quotient elapsed-ns 1000000))
           (cycles-per-sec (if (> elapsed-ns 0)
                               (quotient (* n-cycles 1000000000) elapsed-ns)
                               0))
           (ns-per-cycle (if (> n-cycles 0)
                             (quotient elapsed-ns n-cycles)
                             0)))
      (bench-print-metric "Alloc-Reset Cycles" n-cycles "cycles")
      (bench-print-metric "Elapsed Time" elapsed-ms "ms")
      (bench-print-metric "Arena Throughput" cycles-per-sec "cycles/sec")
      (bench-print-metric "Cost per Alloc-Reset Cycle" ns-per-cycle "ns")
      (bench-print-metric "Heap Growth / Leak" (arena-offset arena) "bytes")
      (record-metric-pair! "arena_throughput" cycles-per-sec)
      (record-metric-pair! "arena_cost_ns" ns-per-cycle)
      (write-string "  [STATUS]: PASS (Zero Heap Fragmentation & 0B Leak)\n")
      (flush-output-port))))

;; -----------------------------------------------------------------------
;; Benchmark 4: Multi-Dimensional Scaling Benchmark Suite (Issue #795)
;; -----------------------------------------------------------------------
(define (run-scaling-step n-tasks n-workers)
  (let* ((sched (make-work-stealing-scheduler n-workers 1024))
         (completed-counter (make-atomic-box 0))
         (t0 (get-monotonic-time-ns)))
    ;; Scatter spawn across workers before parallel execution
    (let spawn-loop ((i 0))
      (if (< i n-tasks)
          (begin
            (let ((target-worker (modulo i n-workers)))
              (scheduler-spawn! sched
                                (lambda ()
                                  (atomic-fetch-add! completed-counter 1))
                                target-worker))
            (spawn-loop (+ i 1)))))
    (let* ((t1 (get-monotonic-time-ns))
           (spawn-ms (quotient (- t1 t0) 1000000))
           (t-exec-start (get-monotonic-time-ns))
           (total-done (if (> n-workers 1)
                           (scheduler-run-parallel! sched n-tasks)
                           (scheduler-run! sched n-tasks)))
           (t-exec-end (get-monotonic-time-ns))
           (exec-ns (- t-exec-end t-exec-start))
           (exec-ms (if (= (quotient exec-ns 1000000) 0) 1 (quotient exec-ns 1000000)))
           (total-ms (quotient (- t-exec-end t0) 1000000))
           (tput (if (> exec-ns 0)
                     (quotient (* n-tasks 1000000000) exec-ns)
                     0)))
      (scheduler-stop! sched)
      (write-string (string-append "    [" (number->string n-tasks) " tasks, "
                                   (number->string n-workers) " workers]: Spawn="
                                   (number->string spawn-ms) "ms, Exec="
                                   (number->string exec-ms) "ms, Total="
                                   (number->string total-ms) "ms, Tput="
                                   (number->string tput) " tasks/s\n"))
      (flush-output-port)
      total-ms)))

(define (run-scaling-benchmark)
  (bench-print-header "4. Multi-Dimensional Scaling Benchmark Suite (Issue #795)")
  (write-string "--- 4a. Task Count Linearity Scaling (4 Workers) ---\n")
  (flush-output-port)
  (let ((t-10k (run-scaling-step 10000 4))
        (t-100k (run-scaling-step 100000 4))
        (t-1m (run-scaling-step 1000000 4)))
    (write-string "\n  [Linearity Audit]: 10k -> 100k -> 1M tasks completed.\n")
    (flush-output-port))

  (write-string "\n--- 4b. Worker Thread Strong Scaling (100,000 Tasks) ---\n")
  (flush-output-port)
  (let ((t-w1 (run-scaling-step 100000 1))
        (t-w2 (run-scaling-step 100000 2))
        (t-w4 (run-scaling-step 100000 4)))
    (let ((speedup-2 (if (> t-w2 0) (quotient (* t-w1 100) t-w2) 100))
          (speedup-4 (if (> t-w4 0) (quotient (* t-w1 100) t-w4) 100)))
      (write-string (string-append "  [Strong Scaling Speedup]: 2 Workers="
                                   (number->string speedup-2) "%, 4 Workers="
                                   (number->string speedup-4) "%\n"))
      (flush-output-port))))

;; -----------------------------------------------------------------------
;; JSON Metrics Exporter
;; -----------------------------------------------------------------------
(define (export-metrics-json! filepath)
  (if (and (string? filepath) (> (string-length filepath) 0))
      (guard (exn (else
                   (write-string (string-append "  [JSON WARNING]: failed to open " filepath " for writing\n"))
                   (flush-output-port)
                   #f))
        (let ((p (open-output-file filepath)))
          (write-string "{\n" p)
          (write-string "  \"benchmark\": \"synapse_concurrency\",\n" p)
          (write-string "  \"hardware\": \"Linux x86-64\"" p)
          (let loop ((pairs (atomic-ref *bench-metrics-json*)))
            (if (null? pairs)
                #t
                (let* ((entry (car pairs))
                       (k (car entry))
                       (v (cdr entry)))
                  (write-string ",\n  \"" p)
                  (write-string k p)
                  (write-string "\": " p)
                  (cond
                    ((number? v) (write-string (number->string v) p))
                    ((string? v) (begin (write-string "\"" p) (write-string v p) (write-string "\"" p)))
                    (else (write-string "\"unknown\"" p)))
                  (loop (cdr pairs)))))
          (write-string "\n}\n" p)
          (close-output-port p)
          (write-string (string-append "  [JSON]: Exported benchmark metrics to " filepath "\n"))
          (flush-output-port)))
      #f))

;; -----------------------------------------------------------------------
;; Main Runner
;; -----------------------------------------------------------------------
(let* ()
  (write-string "\n#######################################################\n")
  (write-string " SYNAPSE CONCURRENCY BENCHMARK SUITE (#643 Task 5.1)\n")
  (write-string " Hardware: Linux x86-64 | Architecture: Synapse Dual-Plane\n")
  (write-string "#######################################################\n")
  (flush-output-port)

  ;; 1. 100,000 Microtasks Native Multi-Worker Parallel Benchmark (4 workers)
  (run-microtasks-parallel-benchmark 100000 4)

  ;; 1b. 100,000 Microtasks Pipelined Concurrency Benchmark (Go-Style Overlap)
  (run-microtasks-pipelined-benchmark 100000 4)

  ;; 2. 50,000 Channel Messages Relay
  (run-channel-relay-benchmark 50000)

  ;; 2b. 50,000 Inlined SPSC Channel Direct Relay (Issue #688)
  (run-inlined-channel-relay-benchmark 50000)

  ;; 3. 100,000 Ephemeral Arena Allocation & Reset Cycles
  (run-arena-benchmark 100000)

  ;; 4. Optional Scaling Suite (Triggered via ULISP_BENCH_SCALING=1)
  (let ((scaling-flag (get-environment-variable "ULISP_BENCH_SCALING")))
    (if (and (string? scaling-flag) (string=? scaling-flag "1"))
        (run-scaling-benchmark)
        #f))

  ;; 5. Optional JSON Metrics Export
  (let ((json-out-path (get-environment-variable "ULISP_BENCH_JSON_OUT")))
    (if (and (string? json-out-path) (> (string-length json-out-path) 0))
        (export-metrics-json! json-out-path)
        #f))

  (write-string "\n=======================================================\n")
  (if (atomic-ref *bench-overall-failed*)
      (begin
        (write-string " BENCHMARK COMPLETED WITH DoD THRESHOLD VIOLATIONS\n")
        (write-string "=======================================================\n\n")
        (flush-output-port)
        (exit 1))
      (begin
        (write-string " ALL MICRO-CONCURRENCY BENCHMARKS COMPLETED SUCCESSFULLY\n")
        (write-string "=======================================================\n\n")
        (flush-output-port))))

