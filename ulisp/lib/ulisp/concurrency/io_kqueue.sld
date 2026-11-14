;;; =======================================================================
;;; (ulisp concurrency io-kqueue) - macOS/BSD kqueue Event Loop (R7RS)
;;; Conforms to DSN-37 Section 7.4.3 & Phase 7 Task 7.3 (Issue #697)
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

(define-library (ulisp concurrency io-kqueue)
  (export
    <kqueue-loop>
    make-kqueue-loop
    kqueue-loop?
    kqueue-loop-fd
    kqueue-loop-capacity
    kqueue-loop-native?
    kqueue-loop-active?
    kqueue-loop-close!

    kqueue-register-read!
    kqueue-register-write!
    kqueue-register-timer!
    kqueue-unregister!

    kqueue-poll-events!
    kqueue-dequeue-completion!

    kqueue-submitted-count
    kqueue-completed-count
    kqueue-pending-count
    kqueue-registered-count
    kqueue-stats

    EVFILT_READ
    EVFILT_WRITE
    EVFILT_AIO
    EVFILT_VNODE
    EVFILT_PROC
    EVFILT_SIGNAL
    EVFILT_TIMER

    EV_ADD
    EV_DELETE
    EV_ENABLE
    EV_DISABLE
    EV_ONESHOT
    EV_CLEAR
    EV_RECEIPT
    EV_DISPATCH
    EV_UDATA_SPECIFIC
    EV_EOF
    EV_ERROR)

  (import
    (scheme base))

  (include "ulisp/runtime/concurrency/io_kqueue.scm"))
