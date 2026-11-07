;;; =======================================================================
;;; Library: (ulisp concurrency supervisor)
;;; Specification: DSN-37 Section 8.4.3 & 14.8 Task 6.2 (Issue #667)
;;; Description: Erlang/OTP Supervision Tree, Restart Strategies, and Flapping Limits
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

(define-library (ulisp concurrency supervisor)
  (export
    ;; Global Timestamp Clock
    allocate-supervisor-timestamp!
    supervisor-clock-now
    supervisor-clock-advance!

    ;; Record Types & Predicates
    <child-spec>
    child-spec?
    child-spec-id
    child-spec-start-thunk
    child-spec-restart-type
    child-spec-shutdown-strategy
    child-spec-child-type
    child-spec-init-args
    make-child-spec

    <supervisor-spec>
    supervisor-spec?
    supervisor-spec-strategy
    supervisor-spec-max-restarts
    supervisor-spec-max-time
    supervisor-spec-child-specs
    make-supervisor-spec

    <supervisor-context>
    supervisor-context?
    supervisor-spec
    supervisor-task
    supervisor-children
    supervisor-restart-history
    supervisor-state
    supervisor-parent
    make-supervisor

    ;; Lifecycle Operations
    supervisor-start!
    supervisor-stop!
    supervisor-handle-child-down!
    supervisor-child-task
    supervisor-poll-down-signals!

    ;; Signal Preservation & Message Routing (Issue #751)
    supervisor-preserved-messages
    supervisor-take-preserved-message!
    supervisor-clear-preserved-messages!
    supervisor-message-handler
    supervisor-set-message-handler!)
  (import (scheme base)
          (scheme case-lambda)
          (ulisp concurrency channel)
          (ulisp concurrency arena)
          (ulisp concurrency links)
          (ulisp concurrency panic))
  (include "ulisp/runtime/concurrency/supervisor.scm"))

