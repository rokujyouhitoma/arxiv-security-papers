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
    task-take-handoff!

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
    channel-empty?
    channel-full?
    channel-send!
    channel-try-send!
    channel-recv!
    channel-try-recv!
    channel-try-recv-with-status!
    channel-close!
    channel-deep-copy
    broadcast-send!
    channel-stats)
  (import (scheme base)
          (scheme case-lambda))
  (include "ulisp/runtime/concurrency/channel.scm"))

