;;; =======================================================================
;;; (ulisp concurrency crash-logger) - Structured Crash Reporting (R7RS)
;;; Conforms to DSN-37 Section 8.4.6 & Section 14.8 Task 6.5 (Issue #670)
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

(define-library (ulisp concurrency crash-logger)
  (export
    ;; Record Types & Predicates
    <crash-report>
    make-crash-report
    crash-report?
    crash-report-id
    crash-report-tid
    crash-report-registered-name
    crash-report-epoch
    crash-report-fuel-consumed
    crash-report-arena-allocated
    crash-report-arena-capacity
    crash-report-reason
    crash-report-details
    crash-report-source-loc
    crash-report-last-msg-summary
    crash-report-timestamp

    ;; Ring Buffer Operations
    <crash-ring-buffer>
    make-crash-ring-buffer
    crash-ring-buffer?
    crash-buffer-capacity
    crash-buffer-count
    crash-buffer-dropped
    crash-buffer-enqueue!
    crash-buffer-dequeue!
    crash-buffer-drain!

    ;; Top-Level & Observability Operations
    current-crash-buffer
    synapse-set-current-crash-buffer!
    synapse-log-task-crash!
    format-crash-report
    crash-report->alist
    crash-report->sexpr
    synapse-crash-metrics
    synapse-reset-crash-metrics!
    synapse-record-crash-metric!)

  (import
    (scheme base)
    (ulisp atomic))

  (include "../../../runtime/concurrency/crash_logger.scm"))

