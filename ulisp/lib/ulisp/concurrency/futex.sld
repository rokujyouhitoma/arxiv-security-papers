;;; =======================================================================
;;; R7RS Library: (ulisp concurrency futex)
;;; Conforms to DSN-37 Section 7.4.2 & Section 14.9 Task 7.2 (Issue #676)
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

(define-library (ulisp concurrency futex)
  (export
    <futex-cell>
    futex-cell?
    make-futex-cell
    free-futex-cell!
    futex-cell-ref
    futex-cell-value
    futex-cell-set!
    futex-cell-cas!
    futex-wait!
    futex-wake!
    futex-park!
    futex-park-adaptive!
    futex-unpark!
    futex-unpark-all!
    futex-spin-pause!
    scheduler-enable-futex!
    FUTEX_STATE_EMPTY
    FUTEX_STATE_PARKED
    FUTEX_STATE_NOTIFIED
    %sys-futex-alloc-cell
    %sys-futex-free-cell!
    %sys-futex-get
    %sys-futex-set!
    %sys-futex-cas!
    %sys-futex-wait
    %sys-futex-wake
    %sys-cpu-pause)

  (import
    (scheme base))

  (include "ulisp/runtime/concurrency/futex.scm"))
