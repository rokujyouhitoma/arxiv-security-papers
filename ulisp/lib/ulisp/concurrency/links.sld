;;; =======================================================================
;;; Library: (ulisp concurrency links)
;;; Specification: DSN-37 Section 8.4.1 & 8.4.2 (Issue #666)
;;; Description: Task Links, Monitors, and Auto-Poisoning Fault Tolerance
;;; =======================================================================

(define-library (ulisp concurrency links)
  (export
    ;; Constants & References
    *max-task-links*
    *max-task-monitors*
    *monitor-next-id*
    allocate-monitor-ref!
    monitor-next-id-current
    monitor-reset-next-id!

    ;; Bi-directional Links
    task-link!
    task-unlink!
    task-linked?

    ;; Unidirectional Monitors
    task-monitor
    task-demonitor

    ;; Termination & Cascade Propagation
    task-handle-termination!
    task-exit!)
  (import (scheme base)
          (scheme case-lambda)
          (ulisp concurrency channel))
  (include "ulisp/runtime/concurrency/links.scm"))

