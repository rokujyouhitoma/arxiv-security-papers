;;; =======================================================================
;;; R7RS Library: (ulisp concurrency preempt)
;;; Conforms to DSN-37 Section 7.2 & Phase 2 Task 2.3 (Issue #636)
;;; =======================================================================

(define-library (ulisp concurrency preempt)
  (export
    ;; Record type & constructors
    <budgeted-task>
    budgeted-task?
    make-budgeted-task

    ;; Accessors & mutators
    task-id
    task-target-obj
    task-initial-budget
    task-reductions
    task-reductions-set!
    task-exhaustion-count
    task-state
    task-state-set!
    task-exhausted?

    ;; Reduction accounting & replenishment
    task-consume-reductions!
    task-replenish!

    ;; Safepoint checking & preemption
    check-safepoint!
    safepoint-poll!
    scheduler-yield!
    budgeted-task-execute!
    budgeted-task-stats

    ;; Constants
    *default-reduction-budget*
    *min-reduction-budget*
    *max-reduction-budget*)
  (import (scheme base))
  (include "../../../runtime/concurrency/preempt.scm"))
