;;; =======================================================================
;;; R7RS Library: (ulisp concurrency deque)
;;; Conforms to DSN-37 Section 7.1, 13.4 & Phase 2 Task 2.2 (Issue #635)
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

(define-library (ulisp concurrency deque)
  (export
    ;; Record type & predicate
    <chase-lev-deque>
    chase-lev-deque?
    make-chase-lev-deque

    ;; Core Owner & Thief operations
    deque-push!
    deque-pop!
    deque-steal!

    ;; Observability & size inspection
    deque-empty?
    deque-count
    deque-capacity
    deque-stats

    ;; Constants
    *deque-min-capacity*
    *deque-default-capacity*
    *deque-max-capacity*

    ;; L1 Bounded Ring Buffer (Go-Style 256-Entry CAS-Free Queue, Issue #804)
    <l1-ring-buffer>
    l1-ring-buffer?
    make-l1-ring-buffer
    l1-ring-push!
    l1-ring-pop!
    l1-ring-steal!
    l1-ring-empty?
    l1-ring-full?
    l1-ring-count
    l1-ring-runnext
    l1-ring-drain-all!
    *l1-ring-capacity*
    *l1-ring-mask*
    *l1-batch-size*)

  (import
    (scheme base)
    (ulisp concurrency atomic))

  (include "ulisp/runtime/concurrency/deque.scm"))

