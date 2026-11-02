;;; =======================================================================
;;; Library: (ulisp concurrency channel)
;;; Specification: DSN-37 Section 4, 6.1 & 13.4 (Issue #633)
;;; Description: Linear Ownership Transfer Channel & Bounded Backpressure
;;; =======================================================================

(define-library (ulisp concurrency channel)
  (export
    ;; Constants & Hooks
    *task-default-reductions*
    *channel-max-capacity*
    *task-next-id*
    allocate-task-id!
    task-next-id-current
    task-reset-next-id!
    set-channel-wake-hook!
    channel-wake-hook
    set-channel-epoch-validator!
    channel-epoch-validator

    ;; <task-context> Record & Accessors (DSN-37 Section 6.1)
    <task-context>
    make-task-context
    task-context?
    task-tid
    task-state
    task-state-set!
    task-reductions
    task-reductions-set!
    task-continuation-pc
    task-continuation-pc-set!
    task-stack-pointer
    task-stack-pointer-set!
    task-arena-base
    task-arena-offset
    task-arena-offset-set!
    task-arena-capacity
    task-blocked-on
    task-blocked-on-set!
    task-epoch
    task-epoch-set!
    task-next-run
    task-next-run-set!
    task-reduction-exhaustions
    task-reduction-exhaustions-set!
    task-steals-count
    task-steals-count-set!
    task-has-handoff?
    task-handoff-box
    task-set-handoff!
    task-take-handoff!
    task-links-box
    task-links
    task-monitors-box
    task-monitors
    task-monitored-by-box
    task-monitored-by
    task-trap-exit?
    task-trap-exit!
    task-wake!
    task-owned-channels-box
    task-owned-channels
    task-register-channel!
    task-unregister-channel!
    task-poison-owned-channels!

    ;; <channel-waiter> Record
    <channel-waiter>
    make-channel-waiter
    channel-waiter?
    channel-waiter-task
    channel-waiter-state

    ;; <channel> Record & Core CSP Operations
    <channel>
    make-channel
    make-channel-internal
    channel?
    channel-message-queue
    channel-recv-wait-queue
    channel-send-wait-queue
    channel-capacity
    channel-current-count
    channel-count
    channel-closed?
    channel-poisoned?
    channel-empty?
    channel-full?
    channel-send!
    channel-try-send!
    channel-recv!
    channel-try-recv!
    channel-try-recv-with-status!
    channel-close!
    channel-poison!
    channel-deep-copy
    broadcast-send!
    channel-stats)
  (import (scheme base)
          (scheme case-lambda))
  (include "ulisp/runtime/concurrency/channel.scm"))

