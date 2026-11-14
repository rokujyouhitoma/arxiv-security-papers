;;; =======================================================================
;;; (ulisp concurrency osal) - OS Abstraction Layer (R7RS)
;;; Conforms to DSN-37 Section 7.4 & DSN-33-02 Section 7.2 (Issue #697)
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

(define-library (ulisp concurrency osal)
  (export
    ;; Platform
    osal-platform
    osal-platform-name
    osal-set-platform-override!

    ;; Thread
    <osal-thread>
    osal-thread?
    osal-thread-id
    osal-thread-name
    osal-thread-native-handle
    osal-thread-state
    osal-thread-exit-code
    osal-thread-supported?
    osal-cpu-count
    osal-thread-yield
    osal-set-affinity!
    osal-thread-spawn
    osal-thread-exit!
    osal-thread-join!

    ;; Futex
    <osal-futex-cell>
    osal-futex-cell?
    osal-futex-supported?
    osal-futex-cell-active?
    osal-make-futex-cell
    osal-free-futex-cell!
    osal-futex-get
    osal-futex-set!
    osal-futex-cas!
    osal-futex-wait!
    osal-futex-wake!
    osal-futex-park!
    osal-futex-unpark!
    osal-futex-unpark-all!

    ;; Event Loop
    <osal-event-loop>
    osal-event-loop?
    osal-event-loop-platform
    osal-event-loop-backend
    osal-event-loop-active?
    osal-event-loop-capacity
    osal-make-event-loop
    osal-event-loop-close!
    osal-event-register-read!
    osal-event-register-write!
    osal-event-unregister!
    osal-event-poll!
    osal-event-loop-stats)

  (import
    (scheme base))

  (include "ulisp/runtime/concurrency/osal.scm"))
