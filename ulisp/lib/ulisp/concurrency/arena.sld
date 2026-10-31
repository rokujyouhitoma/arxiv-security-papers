;;; =======================================================================
;;; Library: (ulisp concurrency arena)
;;; Specification: DSN-37 Section 5 & Section 13.4 (Issue #630)
;;; Description: Process-Local Ephemeral Bump Arena & O(1) Instant Reset
;;; =======================================================================

(define-library (ulisp concurrency arena)
  (export
    ;; Constants
    *arena-min-capacity*
    *arena-default-capacity*
    *arena-max-initial-capacity*
    *arena-overflow-chunk-size*
    *arena-default-align*
    *arena-default-base*
    *arena-chunk-stride*
    *arena-max-chunks*
    *arena-max-alloc-size*

    ;; Alignment Helpers
    arena-power-of-two?
    arena-align-up

    ;; Record Types & Constructors
    <arena-chunk>
    make-arena-chunk
    arena-chunk?
    arena-chunk-base
    arena-chunk-offset
    arena-chunk-offset-set!
    arena-chunk-capacity
    arena-chunk-buffer
    arena-chunk-next
    arena-chunk-next-set!

    <task-arena>
    make-task-arena
    task-arena?
    arena-base
    arena-base-set!
    arena-offset
    arena-offset-set!
    arena-capacity
    arena-capacity-set!
    arena-buffer
    arena-buffer-set!
    arena-chunks
    arena-chunks-set!
    arena-chunk-count
    arena-chunk-count-set!
    arena-max-chunks
    arena-max-chunks-set!
    arena-total-allocated
    arena-total-allocated-set!
    arena-reset-count
    arena-reset-count-set!

    ;; Core Allocation & Reset Procedures
    arena-allocate!
    arena-overflow-fallback!
    arena-reset!
    arena-secure-reset!

    ;; Memory Read/Write & Telemetry
    arena-u8-ref
    arena-u8-set!
    arena-u64-ref
    arena-u64-set!
    arena-used-bytes
    arena-available-bytes
    arena-empty?
    arena-stats)
  (import (scheme base)
          (scheme case-lambda))
  (include "ulisp/runtime/concurrency/arena.scm"))
