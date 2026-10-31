;;; =======================================================================
;;; Library: (ulisp concurrency queue)
;;; Specification: DSN-37 Section 6 & Section 13.4 (Issue #632)
;;; Description: Michael-Scott Non-Blocking Lock-Free MPMC Queue & ABA-Safe Node Pool
;;; =======================================================================

(define-library (ulisp concurrency queue)
  (export
    ;; <queue-node> Record & Accessors
    <queue-node>
    make-queue-node
    queue-node?
    queue-node-value
    queue-node-value-set!
    queue-node-next
    queue-node-next-set!

    ;; <lock-free-queue> Record & Core MPMC Queue Operations
    <lock-free-queue>
    make-lock-free-queue
    lock-free-queue?
    lock-free-queue-head
    lock-free-queue-head-set!
    lock-free-queue-tail
    lock-free-queue-tail-set!
    queue-head
    queue-tail
    enqueue-lockfree!
    queue-enqueue!
    dequeue-lockfree!
    queue-dequeue!
    dequeue-lockfree-with-status!
    queue-empty?
    lock-free-queue-empty?
    queue-peek
    lock-free-queue-peek
    queue-size
    lock-free-queue-size
    queue->list
    queue-stats

    ;; ABA-Safe <queue-node-pool> Operations (DSN-37 Section 6.3)
    <queue-node-pool>
    make-queue-node-pool
    queue-node-pool?
    queue-node-pool-stamp
    queue-node-pool-capacity
    queue-node-pool-available
    pool-alloc-node!
    queue-pool-acquire!
    pool-free-node!
    queue-pool-release!
    enqueue-lockfree/pooled!
    dequeue-lockfree/pooled!)
  (import (scheme base)
          (scheme case-lambda))
  (include "ulisp/runtime/concurrency/queue.scm"))
