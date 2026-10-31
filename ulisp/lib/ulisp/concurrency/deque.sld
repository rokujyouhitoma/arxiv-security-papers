;;; =======================================================================
;;; R7RS Library: (ulisp concurrency deque)
;;; Conforms to DSN-37 Section 7.1, 13.4 & Phase 2 Task 2.2 (Issue #635)
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
    *deque-max-capacity*)

  (import
    (scheme base)
    (ulisp concurrency atomic))

  (include "../../../runtime/concurrency/deque.scm"))

