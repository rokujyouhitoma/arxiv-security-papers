;;; =======================================================================
;;; (ulisp concurrency epoch) Library Definition
;;; Conforms to DSN-37 Section 8.2, 8.3 & Phase 4 Task 4.2 (Issue #642)
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

(define-library (ulisp concurrency epoch)
  (import (scheme base))
  (export
    epoch-current
    epoch-floor
    epoch-advance!
    epoch-set-floor!
    epoch-aborted?
    epoch-bind-task!
    epoch-unbind-task!
    epoch-registered-tasks
    abort-task!
    epoch-rollback-to!
    epoch-task-valid?
    install-epoch-channel-gate!
    epoch-checkpoint
    epoch-stats
    epoch-reset-stats!
    epoch-reset-global!)
  (include "ulisp/runtime/concurrency/epoch.scm"))
