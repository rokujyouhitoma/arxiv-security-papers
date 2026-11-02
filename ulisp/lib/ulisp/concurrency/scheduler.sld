;;; =======================================================================
;;; R7RS Library: (ulisp concurrency scheduler)
;;; Conforms to DSN-37 Section 7.1, 7.2, 13.4 & Phase 2 Task 2.2 (Issue #635)
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
    worker-deque
    worker-current-task
    worker-tasks-executed
    worker-steals-attempted
    worker-steals-succeeded
    worker-yields
    worker-rng-seed
    worker-next-random!

    ;; Core scheduler operations
    scheduler-worker-count
    scheduler-workers
    scheduler-global-queue
    scheduler-get-worker
    scheduler-state
    scheduler-running?
    scheduler-stop!
    scheduler-tasks-spawned
    scheduler-tasks-completed
    scheduler-total-spawned
    scheduler-total-completed
    %scheduler-stats-reset!

    ;; Execution and work-stealing
    scheduler-spawn!
    scheduler-worker-step!
    scheduler-execute-task!
    scheduler-run!
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
    (ulisp concurrency context))

  (include "../../../runtime/concurrency/scheduler.scm"))

