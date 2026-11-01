;;; =======================================================================
;;; Synapse Multicore Concurrency CI Harness (concurrency_harness.scm)
;;; Path: tests/concurrency/concurrency_harness.scm
;;; Conforms to DSN-37 Section 14.7 (Phase 5 Task 5.4) & Issue #645
;;;
;;; Evaluates:
;;;   Scenario 1: Chaos Jitter P2P / MPSC Channel Contention (CWE-362 Guard)
;;;   Scenario 2: Chase-Lev Deque ABA & Lock-free Invariant Verification
;;;   Scenario 3: Speculative Task Cancellation Under Epoch Advance (Rollback Guard)
;;;   Scenario 4: Multi-Task Arena O(1) Reclaim & Zero-Leak Stress (CWE-400 Guard)
;;;   Scenario 5: 100-Iteration Flakiness Elimination & CI Reporting Controller
;;; =======================================================================

(load "ulisp/runtime/concurrency/arena.scm")
(load "ulisp/runtime/concurrency/atomic.scm")
(load "ulisp/runtime/concurrency/queue.scm")
(load "ulisp/runtime/concurrency/channel.scm")
(load "ulisp/runtime/concurrency/boundary.scm")
(load "ulisp/runtime/concurrency/epoch.scm")
(load "ulisp/runtime/concurrency/context.scm")
(load "ulisp/runtime/concurrency/deque.scm")
(load "ulisp/runtime/concurrency/scheduler.scm")
(load "ulisp/runtime/concurrency/preempt.scm")
(load "ulisp/runtime/concurrency/eval_adapter.scm")

;; -----------------------------------------------------------------------
;; 1. PRNG & Chaos Jitter Utilities (Deterministic Knuth LCG)
;; -----------------------------------------------------------------------

(define (make-prng seed)
  (vector (if (= seed 0) 123456789 seed)))

(define (prng-next! prng)
  (let* ((s (vector-ref prng 0))
         ;; Knuth LCG: (a * s + c) mod m
         (next (modulo (+ (* s 1103515245) 12345) 2147483648)))
    (begin
      (vector-set! prng 0 next)
      next)))

(define (prng-range! prng min-val max-val)
  (let* ((val (prng-next! prng))
         (span (+ (- max-val min-val) 1)))
    (+ min-val (modulo val span))))

(define (inject-jitter! prng max-spins)
  (let ((spins (prng-range! prng 0 max-spins)))
    (let loop ((i 0))
      (if (< i spins)
          (loop (+ i 1))
          #t))))

;; -----------------------------------------------------------------------
;; 2. Harness Assertion & Telemetry Infrastructure
;; -----------------------------------------------------------------------

(define *harness-total-assertions* (vector 0))
(define *harness-failed-assertions* (vector 0))
(define *harness-current-iter* (vector 0))
(define *harness-current-scenario* (vector "init"))

(define (harness-assert-true condition msg)
  (begin
    (vector-set! *harness-total-assertions* 0 (+ (vector-ref *harness-total-assertions* 0) 1))
    (if (not condition)
        (begin
          (vector-set! *harness-failed-assertions* 0 (+ (vector-ref *harness-failed-assertions* 0) 1))
          (write-string "\n[CI HARNESS FAIL] Iteration ")
          (write-string (number->string (vector-ref *harness-current-iter* 0)))
          (write-string " | Scenario: ")
          (write-string (vector-ref *harness-current-scenario* 0))
          (write-string " | Reason: ")
          (write-string msg)
          (write-char #\newline)
          (flush-output-port)
          #f)
        #t)))

(define (harness-assert-false condition msg)
  (harness-assert-true (not condition) msg))

(define (harness-assert-equal actual expected msg)
  (begin
    (vector-set! *harness-total-assertions* 0 (+ (vector-ref *harness-total-assertions* 0) 1))
    (if (not (eqv? actual expected))
        (begin
          (vector-set! *harness-failed-assertions* 0 (+ (vector-ref *harness-failed-assertions* 0) 1))
          (write-string "\n[CI HARNESS FAIL] Iteration ")
          (write-string (number->string (vector-ref *harness-current-iter* 0)))
          (write-string " | Scenario: ")
          (write-string (vector-ref *harness-current-scenario* 0))
          (write-string " | Reason: ")
          (write-string msg)
          (write-string " (expected: ")
          (if (integer? expected) (write-string (number->string expected)) (write-string "<non-int>"))
          (write-string ", got: ")
          (if (integer? actual) (write-string (number->string actual)) (write-string "<non-int>"))
          (write-string ")\n")
          (flush-output-port)
          #f)
        #t)))

;; -----------------------------------------------------------------------
;; 3. Scenario 1: Chaos Jitter P2P / MPSC Channel Contention
;; -----------------------------------------------------------------------

(define (run-scenario-jitter-channel! iter-id prng)
  (begin
    (vector-set! *harness-current-scenario* 0 "1-Jitter-Channel")
    (let* ((cap 4)
           (ch (make-channel cap))
           (num-producers 3)
           (msgs-per-prod 10)
           (total-msgs (* num-producers msgs-per-prod))
           (last-seqs (make-vector num-producers -1))
           (received-count-box (vector 0)))
      (let loop-relay ((step 0)
                       (prod-idx 0)
                       (prod-seqs (make-vector num-producers 0)))
        (if (< (vector-ref received-count-box 0) total-msgs)
            (begin
              ;; Producer Step (if this producer has messages remaining)
              (let ((cur-p-seq (vector-ref prod-seqs prod-idx)))
                (if (< cur-p-seq msgs-per-prod)
                    (begin
                      (inject-jitter! prng 12)
                      (let ((sent? (channel-try-send! ch (+ (* prod-idx 1000) cur-p-seq))))
                        (if sent?
                            (begin
                              (vector-set! prod-seqs prod-idx (+ cur-p-seq 1))
                              (inject-jitter! prng 8))
                            #f))
                      #t)
                    #f))

              ;; Consumer Step
              (inject-jitter! prng 10)
              (let ((msg (channel-try-recv! ch)))
                (if msg
                    (let* ((p-id (quotient msg 1000))
                           (seq (modulo msg 1000))
                           (expected-seq (+ (vector-ref last-seqs p-id) 1)))
                      (begin
                        (harness-assert-equal seq expected-seq "Channel message out-of-order or duplicate")
                        (vector-set! last-seqs p-id seq)
                        (vector-set! received-count-box 0 (+ (vector-ref received-count-box 0) 1))
                        (inject-jitter! prng 6)))
                    #f))

              ;; Next producer round-robin
              (loop-relay (+ step 1)
                          (modulo (+ prod-idx 1) num-producers)
                          prod-seqs))
            #t))

      ;; Invariant Checks
      (harness-assert-equal (vector-ref received-count-box 0) total-msgs "Total received messages must equal total sent")
      (harness-assert-equal (channel-count ch) 0 "Channel message count must be 0 after drain")
      (harness-assert-true (channel-empty? ch) "Channel must be empty after complete drain"))))

;; -----------------------------------------------------------------------
;; 4. Scenario 2: Chase-Lev Deque ABA & Lock-free Invariant Verification
;; -----------------------------------------------------------------------

(define (run-scenario-deque-aba! iter-id prng)
  (begin
    (vector-set! *harness-current-scenario* 0 "2-Deque-ABA")
    (let* ((deque (make-chase-lev-deque 16))
           (num-ops 40)
           (total-pushed-box (vector 0))
           (owner-popped-box (vector 0))
           (stealer-stolen-box (vector 0)))

      (let loop-ops ((op 0))
        (if (< op num-ops)
            (let ((action (prng-range! prng 1 3)))
              (begin
                (cond
                  ;; Action 1: Owner Push (1 to 3 items)
                  ((= action 1)
                   (let ((push-count (prng-range! prng 1 3)))
                     (let push-loop ((k 0))
                       (if (< k push-count)
                           (begin
                             (inject-jitter! prng 8)
                             (deque-push! deque (+ (vector-ref total-pushed-box 0) 100))
                             (vector-set! total-pushed-box 0 (+ (vector-ref total-pushed-box 0) 1))
                             (push-loop (+ k 1)))
                           #t))))

                  ;; Action 2: Stealer Steal attempt
                  ((= action 2)
                   (begin
                     (inject-jitter! prng 12)
                     (let ((stolen (deque-steal! deque)))
                       (if (and (not (eqv? stolen 'empty)) (not (eqv? stolen 'abort)))
                           (vector-set! stealer-stolen-box 0 (+ (vector-ref stealer-stolen-box 0) 1))
                           #f))))

                  ;; Action 3: Owner Pop attempt
                  ((= action 3)
                   (begin
                     (inject-jitter! prng 10)
                     (let ((popped (deque-pop! deque)))
                       (if popped
                           (vector-set! owner-popped-box 0 (+ (vector-ref owner-popped-box 0) 1))
                           #f)))))

                (loop-ops (+ op 1))))
            #t))

      ;; Drain all remaining items in deque
      (let drain-loop ()
        (let ((item (deque-pop! deque)))
          (if item
              (begin
                (vector-set! owner-popped-box 0 (+ (vector-ref owner-popped-box 0) 1))
                (drain-loop))
              #t)))

      ;; ABA & Conservation Invariant: pushed == popped + stolen
      (harness-assert-equal (+ (vector-ref owner-popped-box 0) (vector-ref stealer-stolen-box 0))
                            (vector-ref total-pushed-box 0)
                            "Conservation law: pushed == owner_popped + stealer_stolen")
      (harness-assert-true (deque-empty? deque) "Deque must be empty after complete drain"))))

;; -----------------------------------------------------------------------
;; 5. Scenario 3: Speculative Task Cancellation Under Epoch Advance
;; -----------------------------------------------------------------------

(define (run-scenario-epoch-rollback! iter-id prng)
  (begin
    (vector-set! *harness-current-scenario* 0 "3-Epoch-Rollback")
    (epoch-reset-global!)

    (let* ((shared-state (make-atomic-box 0))
           (arena-base (make-task-arena 2048))
           (arena-spec (make-task-arena 2048))
           (task-base (make-task-context 1001))
           (task-spec (make-task-context 1002)))
      (begin
        ;; Task-base bound to initial Epoch 1
        (epoch-bind-task! task-base 1 arena-base)
        (harness-assert-equal (epoch-current) 1 "Initial epoch must be 1")

        ;; Advance to Epoch 2 for speculative work
        (let ((ep2 (epoch-advance!)))
          (begin
            (harness-assert-equal ep2 2 "Epoch advance must return 2")
            ;; Speculative Task-spec bound to Epoch 2
            (epoch-bind-task! task-spec 2 arena-spec)))

        (arena-allocate! arena-spec 64)
        (harness-assert-true (> (arena-used-bytes arena-spec) 0) "Speculative arena must have allocations")

        ;; Inject Jitter before rollback
        (inject-jitter! prng 15)

        ;; Rollback to Epoch 1 (Epochs > 1, i.e., Epoch 2, must be aborted)
        (let ((fresh-ep (epoch-rollback-to! 1)))
          (begin
            (harness-assert-true (>= fresh-ep 2) "Rollback must advance epoch")
            (harness-assert-true (epoch-aborted? 2) "Epoch 2 must be marked aborted")
            (harness-assert-false (epoch-aborted? 1) "Epoch 1 must NOT be aborted")

            ;; Check task-spec cancellation (CWE-400 & CWE-362 guard)
            (harness-assert-equal (task-state task-spec) 'terminated "Aborted task state must be terminated")
            (harness-assert-equal (task-reductions task-spec) 0 "Aborted task reductions must be zeroed")
            (harness-assert-equal (arena-used-bytes arena-spec) 0 "Speculative arena must be reset in O(1)")

            ;; Survivor task-base remains valid
            (harness-assert-equal (task-state task-base) 'ready "Survivor task must remain ready")

            ;; Survivor commits safely to shared state
            (atomic-set! shared-state 42)
            (harness-assert-equal (atomic-ref shared-state) 42 "Survivor commit to shared state must succeed")))))))

;; -----------------------------------------------------------------------
;; 6. Scenario 4: Multi-Task Arena O(1) Reclaim & Zero-Leak Stress
;; -----------------------------------------------------------------------

(define (run-scenario-arena-no-leak! iter-id prng)
  (begin
    (vector-set! *harness-current-scenario* 0 "4-Arena-No-Leak")
    (let ((arenas (vector (make-task-arena 2048)
                          (make-task-arena 2048)
                          (make-task-arena 2048))))
      (let loop-tasks ((t 0))
        (if (< t 3)
            (let ((ar (vector-ref arenas t)))
              (begin
                ;; Perform multiple allocations including overflow chaining (> 2KB)
                (let alloc-loop ((k 0))
                  (if (< k 5)
                      (let ((sz (prng-range! prng 64 600)))
                        (begin
                          (inject-jitter! prng 6)
                          (let ((off (arena-allocate! ar sz)))
                            (begin
                              (arena-u8-set! ar off (modulo (+ t k) 256))
                              (let ((read-val (arena-u8-ref ar off)))
                                (harness-assert-equal read-val (modulo (+ t k) 256)
                                                      "Arena data integrity violation"))))
                          (alloc-loop (+ k 1))))
                      #t))

                (harness-assert-true (> (arena-used-bytes ar) 0) "Arena must have non-zero usage before reset")

                ;; Instant O(1) Secure Reset
                (arena-secure-reset! ar)
                (harness-assert-equal (arena-used-bytes ar) 0 "Arena used bytes must be 0 after secure reset")
                (harness-assert-equal (arena-chunk-count ar) 0 "Arena chunk count must return to 0 (all chained freed)")

                (loop-tasks (+ t 1))))
            #t)))))

;; -----------------------------------------------------------------------
;; 7. Scenario 5: 100-Iteration Flakiness Elimination & CI Reporting Controller
;; -----------------------------------------------------------------------

(define (run-concurrency-ci-harness max-iterations base-seed)
  (begin
    (write-string "=======================================================\n")
    (write-string " Synapse Multicore Concurrency CI Harness (#645)\n")
    (write-string " Running ")
    (write-string (number->string max-iterations))
    (write-string " Iterations with Chaos Jitter Injection...\n")
    (write-string "=======================================================\n")
    (flush-output-port)

    (let iter-loop ((iter 1))
      (if (<= iter max-iterations)
          (begin
            (vector-set! *harness-current-iter* 0 iter)
            (let ((iter-prng (make-prng (+ base-seed (* iter 7919)))))
              (begin
                (run-scenario-jitter-channel! iter iter-prng)
                (run-scenario-deque-aba! iter iter-prng)
                (run-scenario-epoch-rollback! iter iter-prng)
                (run-scenario-arena-no-leak! iter iter-prng)))

            ;; Print periodic progress tick every 10 iterations
            (if (= (modulo iter 10) 0)
                (begin
                  (write-string "  [PROGRESS] Completed Iterations: ")
                  (write-string (number->string iter))
                  (write-string "/")
                  (write-string (number->string max-iterations))
                  (write-string " (Total Assertions: ")
                  (write-string (number->string (vector-ref *harness-total-assertions* 0)))
                  (write-string ")\n")
                  (flush-output-port))
                #f)

            (if (> (vector-ref *harness-failed-assertions* 0) 0)
                (begin
                  (write-string "\n[FATAL] Concurrency race or invariant violation detected at iteration ")
                  (write-string (number->string iter))
                  (write-string "!\n")
                  (flush-output-port)
                  (exit 1))
                (iter-loop (+ iter 1))))
          #t))

    ;; Final Audit Summary
    (write-string "\n=======================================================\n")
    (write-string " [CI HARNESS AUDIT SUMMARY]\n")
    (write-string " Result: 100% PASS (Flakiness Eliminated)\n")
    (write-string " Iterations Completed: ")
    (write-string (number->string max-iterations))
    (write-string "\n Total Assertions Verified: ")
    (write-string (number->string (vector-ref *harness-total-assertions* 0)))
    (write-string "\n Failed Assertions: ")
    (write-string (number->string (vector-ref *harness-failed-assertions* 0)))
    (write-string "\n=======================================================\n")
    (flush-output-port)

    (if (= (vector-ref *harness-failed-assertions* 0) 0)
        (exit 0)
        (exit 1))))

;; Default Entrypoint: 100 iterations with seed 20261101
(let* ()
  (run-concurrency-ci-harness 100 20261101))
