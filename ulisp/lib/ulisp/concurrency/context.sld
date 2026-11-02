;;; =======================================================================
;;; R7RS Library: (ulisp concurrency context)
;;; Conforms to DSN-37 Section 5, Section 7.3 & Section 13.4, Issue #634
;;; =======================================================================

(define-library (ulisp concurrency context)
  (export
    ;; Stack Configuration Constants
    *context-min-stack-size*
    *context-default-stack-size*
    *context-max-stack-size*
    *context-stack-align*
    *context-tcb-header-size*
    *context-frame-size*
    *context-stack-canary*

    ;; <task-stack> Record & Stack Management
    <task-stack>
    make-task-stack
    task-stack?
    task-stack-base
    task-stack-size
    task-stack-top
    task-stack-initial-sp
    task-stack-sp
    task-stack-freed?
    free-task-stack!
    task-stack-check-canary
    setup-task-stack

    ;; <coroutine-context> & Context Switching API
    <coroutine-context>
    *coroutine-next-id*
    allocate-coroutine-id!
    coroutine-next-id-current
    coroutine-reset-next-id!
    make-coroutine-context
    coroutine-context?
    coroutine-id
    coroutine-stack
    coroutine-entry-fn
    coroutine-owns-stack?
    free-coroutine-context!
    coroutine-state
    coroutine-terminated?
    coroutine-switch-count
    coroutine-stack-pointer
    context-resume!
    context-yield!
    context-switch!
    swap-context!

    ;; ABI Verification, 10M Endurance & Telemetry
    verify-swap-context-abi!
    bench-swap-context!
    context-stats)
  (import (scheme base)
          (scheme case-lambda)
          (ulisp concurrency atomic))
  (include "ulisp/runtime/concurrency/context.scm"))

