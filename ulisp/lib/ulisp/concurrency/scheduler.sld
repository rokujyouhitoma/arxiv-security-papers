;;; =======================================================================
;;; R7RS Library: (ulisp concurrency scheduler)
;;; Conforms to DSN-37 Section 7.1, 7.2, 13.4 & Phase 2 Task 2.2 (Issue #635)
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

(define-library (ulisp concurrency scheduler)
  (export
    ;; Record types & constructors
    <work-stealing-scheduler>
    work-stealing-scheduler?
    make-work-stealing-scheduler

    <worker-context>
    worker-context?
    worker-id
    worker-node-id
    worker-deque
    worker-current-task
    worker-tasks-executed
    worker-steals-attempted
    worker-steals-succeeded
    worker-local-steals-attempted
    worker-local-steals-succeeded
    worker-remote-steals-attempted
    worker-remote-steals-succeeded
    worker-yields
    worker-rng-seed
    worker-next-random!
    worker-futex-cell

    ;; Core scheduler operations
    scheduler-worker-count
    scheduler-node-count
    scheduler-node-workers
    scheduler-workers
    scheduler-global-queue
    scheduler-get-worker
    scheduler-state
    scheduler-running?
    scheduler-stop!
    scheduler-tasks-spawned
    scheduler-tasks-completed
    scheduler-tasks-failed
    scheduler-total-spawned
    scheduler-total-completed
    scheduler-total-failed
    %scheduler-stats-reset!

    ;; Execution and work-stealing
    scheduler-spawn!
    scheduler-worker-step!
    scheduler-execute-task!
    scheduler-run!
    scheduler-run-parallel!
    scheduler-start-native-workers!
    scheduler-stats

    ;; Channel wake integration
    scheduler-enable-channel-wake!

    ;; Constants
    *scheduler-default-workers*
    *scheduler-max-workers*
    *scheduler-max-tasks*)

  (import
    (scheme base)
    (ulisp concurrency atomic)
    (ulisp concurrency deque)
    (ulisp concurrency queue)
    (ulisp concurrency channel)
    (ulisp concurrency links)
    (ulisp concurrency context)
    (ulisp concurrency thread)
    (ulisp concurrency futex))

  (include "ulisp/runtime/concurrency/scheduler.scm"))

