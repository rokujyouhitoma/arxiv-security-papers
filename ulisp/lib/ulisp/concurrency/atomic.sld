;;; =======================================================================
;;; Library: (ulisp concurrency atomic)
;;; Specification: DSN-37 Section 6 & Section 13.4 (Issue #631)
;;; Description: Low-Level Hardware Atomic Primitives & <atomic-box>
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

(define-library (ulisp concurrency atomic)
  (export
    ;; Hardware Memory Barrier
    memory-fence

    ;; Core <atomic-box> Primitives
    <atomic-box>
    make-atomic-box
    atomic-box?
    atomic-ref
    atomic-box-ref
    atomic-set!
    atomic-box-set!
    atomic-cas!

    ;; High-Level Derived Atomic Operations
    atomic-swap!
    atomic-fetch-add!
    atomic-update!

    ;; Cache-Line Padded Atomic Box (#680)
    <padded-atomic-box>
    make-padded-atomic-box
    padded-atomic-box?
    padded-atomic-ref
    padded-atomic-set!
    padded-atomic-cas!
    padded-atomic-swap!
    padded-atomic-fetch-add!

    ;; ABA-Safe <atomic-stamped-box> Primitives
    <atomic-stamped-box>
    make-atomic-stamped-box
    atomic-stamped-box?
    atomic-stamped-ref
    atomic-stamped-val
    atomic-stamped-stamp
    atomic-stamped-set!
    atomic-stamped-cas!)
  (import (scheme base)
          (scheme case-lambda))
  (include "ulisp/runtime/concurrency/atomic.scm"))

